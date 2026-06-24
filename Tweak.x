/**
 * OverlayIOSTOOL - SpringBoard visual host with guarded app proxies.
 *
 * The companion app publishes a selected image through a named pasteboard and
 * posts a Darwin notification. SpringBoard is the only process that renders
 * the image; user apps get a guarded transparent proxy for input forwarding.
 * Hooks are initialized only after process validation to avoid system UIKit
 * process crash loops on arm64e/Dopamine.
 */

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <unistd.h>
#import <string.h>

static NSString * const kOverlayDirectory = @"/var/mobile/Library/OverlayIOSTOOL";
static NSString * const kOverlayImagePath = @"/var/mobile/Library/OverlayIOSTOOL/overlay.png";
static NSString * const kOverlaySettingsPath = @"/var/mobile/Library/OverlayIOSTOOL/settings.plist";
static NSString * const kOverlayStatePath = @"/var/mobile/Library/OverlayIOSTOOL/state.plist";
static NSString * const kSpringBoardGuardPath = @"/var/mobile/Library/OverlayIOSTOOL/springboard-guard.plist";
static NSString * const kSpringBoardDisabledPath = @"/var/mobile/Library/OverlayIOSTOOL/disabled-after-crash";
static NSString * const kOverlayPasteboardName = @"com.vietanh.overlayiostool.image";
static const char *kOverlayUpdatedNotification = "com.vietanh.overlayiostool.image-updated";
static const char *kOverlayRemoveNotification = "com.vietanh.overlayiostool.image-remove";
static const char *kOverlaySettingsNotification = "com.vietanh.overlayiostool.settings-updated";
static const char *kOverlayStateNotification = "com.vietanh.overlayiostool.state-updated";
static const char *kOverlayDepositActionNotification = "com.vietanh.overlayiostool.action.deposit";
static const char *kOverlayWithdrawActionNotification = "com.vietanh.overlayiostool.action.withdraw";
static const char *kOverlayRealtimeSocketPath = "/var/mobile/Library/OverlayIOSTOOL/realtime.sock";
static const uint32_t kOverlayRealtimeMagic = 0x4F495254;

static BOOL gOverlayHostReady = NO;
static BOOL gToggleClickEnabled = NO;
static BOOL gOverlayVisible = YES;
static BOOL gOverlayDimmed = NO;
static BOOL gScaleLockModeEnabled = NO;
static BOOL gApplyingRemoteState = NO;
static BOOL gIsSpringBoardProcess = NO;
static BOOL gOverlayProcessEnabled = NO;
static BOOL gObserversInstalled = NO;
static BOOL gQuickActionsVisible = NO;
static BOOL gScreenBlanked = NO;
static BOOL gScreenLocked = NO;
static BOOL gDataUnavailable = NO;
static NSUInteger gToggleGeneration = 0;
static NSInteger gHideDelayMs = 300;
static NSInteger gShowDelayMs = 300;
static NSInteger gDimAnimationMs = 0;
static CGFloat gDimOpacity = 1.0;
static CFTimeInterval gLastRealtimeStateSync = 0;
static int gRealtimeClientSocket = -1;
static CFSocketRef gRealtimeServerSocket = NULL;
static CFRunLoopSourceRef gRealtimeServerSource = NULL;
static UIWindow *gOverlayWindow = nil;
static __weak UIWindow *gPreviousKeyWindow = nil;
static UIImageView *gOverlayImageView = nil;
static UIControl *gQuickActionsBackdrop = nil;
static UIView *gQuickActionsPanel = nil;
static UIButton *gQuickActionsCancelButton = nil;
static UIView *gScaleLockControlsPanel = nil;
static UISlider *gOverlayHideDelaySlider = nil;
static UISlider *gOverlayShowDelaySlider = nil;
static UISlider *gOverlayDimOpacitySlider = nil;
static UISlider *gOverlayDimAnimationSlider = nil;
static UILabel *gOverlayHideDelayValueLabel = nil;
static UILabel *gOverlayShowDelayValueLabel = nil;
static UILabel *gOverlayDimOpacityValueLabel = nil;
static UILabel *gOverlayDimAnimationValueLabel = nil;
static UIButton *gToggleClickButton = nil;
static UIButton *gHideImageButton = nil;
static UIPanGestureRecognizer *gImagePanGesture = nil;
static UIPinchGestureRecognizer *gImagePinchGesture = nil;
static UILongPressGestureRecognizer *gImageLongPressGesture = nil;
static UITapGestureRecognizer *gQuickActionsTapGesture = nil;
static UIPinchGestureRecognizer *gExpandedPinchGesture = nil;
static UIPanGestureRecognizer *gRelativePanGesture = nil;
static UITapGestureRecognizer *gInputBlockTapGesture = nil;
static int gNotifyToken = 0;
static int gRemoveToken = 0;
static int gSettingsToken = 0;
static int gStateToken = 0;
static int gBlankedScreenToken = 0;
static int gLockStateToken = 0;

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t version;
    uint32_t kind;
    double x;
    double y;
    double width;
    double height;
    double dimOpacity;
    double dimAnimationMs;
    uint8_t visible;
    uint8_t dimmed;
    uint8_t scaleLock;
} OverlayRealtimeMessage;

@interface OverlayPassthroughWindow : UIWindow
@end

static CGRect expandedScaleHitboxInRootView(void);
static void refreshOverlayWindowVisibility(void);
static void updateScaleLockControlsVisibility(void);
static void updateOverlayControlValues(void);
static void attachOverlayWindowScene(void);

@implementation OverlayPassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    UIView *rootView = self.rootViewController.view;

    if (gQuickActionsVisible && rootView) {
        return hitView ?: rootView;
    }

    if (gScaleLockModeEnabled) {
        if (gScaleLockControlsPanel && !gScaleLockControlsPanel.hidden && [hitView isDescendantOfView:gScaleLockControlsPanel]) {
            return hitView;
        }
        if (CGRectContainsPoint(self.bounds, point) && rootView) {
            if (!hitView || hitView == self || hitView == rootView) {
                return rootView;
            }
            return hitView;
        }
        if (!hitView || hitView == self) {
            return rootView;
        }
        return hitView;
    }

    if (gOverlayImageView && gOverlayVisible && !gOverlayImageView.hidden && rootView) {
        CGPoint rootPoint = [rootView convertPoint:point fromView:self];
        CGPoint imagePoint = [gOverlayImageView convertPoint:rootPoint fromView:rootView];
        if ([gOverlayImageView pointInside:imagePoint withEvent:event]) {
            return gOverlayImageView;
        }
    }

    if ((hitView == self || hitView == rootView) && event.allTouches.count >= 2 && rootView) {
        CGPoint rootPoint = [rootView convertPoint:point fromView:self];
        if (CGRectContainsPoint(expandedScaleHitboxInRootView(), rootPoint)) {
            return rootView;
        }
    }

    if (hitView == self || hitView == self.rootViewController.view) {
        return nil;
    }
    return hitView;
}

@end

@interface OverlayGestureHandler : NSObject <UIGestureRecognizerDelegate>
@end

static OverlayGestureHandler *gGestureHandler = nil;

static UIWindow *currentKeyWindowExcludingOverlay(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        if (window != gOverlayWindow && window.isKeyWindow) {
            return window;
        }
    }
    return nil;
}

static BOOL shouldEnableOverlayInCurrentProcess(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    NSString *executablePath = NSBundle.mainBundle.executablePath;

    if (!bundleIdentifier.length || !bundlePath.length) {
        return NO;
    }

    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        return YES;
    }

    if ([bundleIdentifier hasPrefix:@"com.vietanh.overlayiostool"]) {
        return NO;
    }

    if ([bundlePath containsString:@".appex"] || [executablePath containsString:@"/PlugIns/"]) {
        return NO;
    }

    if (![bundlePath hasSuffix:@".app"]) {
        return NO;
    }

    if ([bundlePath hasPrefix:@"/var/containers/Bundle/Application/"] ||
        [bundlePath hasPrefix:@"/private/var/containers/Bundle/Application/"] ||
        [bundlePath hasPrefix:@"/Applications/"] ||
        [bundlePath hasPrefix:@"/var/jb/Applications/"] ||
        [bundlePath hasPrefix:@"/private/var/jb/Applications/"]) {
        return YES;
    }

    return NO;
}

static BOOL springBoardCrashGuardShouldDisable(void) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if ([fileManager fileExistsAtPath:kSpringBoardDisabledPath]) {
        return YES;
    }

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *previousState = [NSDictionary dictionaryWithContentsOfFile:kSpringBoardGuardPath];
    BOOL previousLaunchArmed = [previousState[@"armed"] boolValue];
    NSTimeInterval previousLaunchTime = [previousState[@"timestamp"] doubleValue];
    NSInteger failureCount = [previousState[@"failureCount"] integerValue];

    if (previousLaunchArmed && previousLaunchTime > 0 && now - previousLaunchTime < 120.0) {
        failureCount += 1;
    } else {
        failureCount = 1;
    }

    [fileManager createDirectoryAtPath:kOverlayDirectory
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:nil];

    if (failureCount >= 3) {
        [@"disabled" writeToFile:kSpringBoardDisabledPath
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];
        NSLog(@"[OverlayIOSTOOL] Disabled after repeated SpringBoard launch failures");
        return YES;
    }

    [@{
        @"armed": @YES,
        @"timestamp": @(now),
        @"failureCount": @(failureCount)
    } writeToFile:kSpringBoardGuardPath atomically:YES];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [@{
            @"armed": @NO,
            @"timestamp": @(NSDate.date.timeIntervalSince1970),
            @"failureCount": @0
        } writeToFile:kSpringBoardGuardPath atomically:YES];
    });
    return NO;
}

static UIPasteboard *overlayPasteboard(BOOL create) {
    return [UIPasteboard pasteboardWithName:kOverlayPasteboardName create:create];
}

static NSDictionary *overlayStateDictionary(void) {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"scaleLockModeEnabled"] = @(gScaleLockModeEnabled);
    state[@"overlayVisible"] = @(gOverlayVisible);
    state[@"overlayDimmed"] = @(gOverlayDimmed);
    state[@"dimOpacity"] = @(gDimOpacity);
    state[@"dimAnimationMs"] = @(gDimAnimationMs);

    if (gOverlayImageView) {
        CGRect frame = gOverlayImageView.frame;
        state[@"frame"] = @{
            @"x": @(frame.origin.x),
            @"y": @(frame.origin.y),
            @"w": @(frame.size.width),
            @"h": @(frame.size.height)
        };
    }

    return state;
}

static void persistOverlayState(BOOL broadcast) {
    if (!gOverlayImageView || gApplyingRemoteState) {
        return;
    }

    NSDictionary *state = overlayStateDictionary();
    [state writeToFile:kOverlayStatePath atomically:YES];
    if (broadcast) {
        notify_post(kOverlayStateNotification);
    }
}

static void applyRealtimeOverlayMessage(const OverlayRealtimeMessage *message) {
    if (!gIsSpringBoardProcess || !message || message->magic != kOverlayRealtimeMagic || !gOverlayImageView) {
        return;
    }

    gApplyingRemoteState = YES;
    gOverlayImageView.frame = CGRectMake(message->x, message->y, message->width, message->height);
    gOverlayVisible = message->visible;
    gOverlayDimmed = message->dimmed;
    gDimOpacity = MAX(0.0, MIN(message->dimOpacity, 1.0));
    gDimAnimationMs = MAX(0, MIN((NSInteger)message->dimAnimationMs, 10000));
    gScaleLockModeEnabled = message->scaleLock;
    gOverlayImageView.hidden = !gOverlayVisible && !gScaleLockModeEnabled;
    gOverlayImageView.alpha = gOverlayDimmed ? gDimOpacity : 1.0;
    gOverlayImageView.layer.borderWidth = gScaleLockModeEnabled ? 3.0 : 0.0;
    gOverlayImageView.layer.borderColor = gScaleLockModeEnabled ? UIColor.systemBlueColor.CGColor : nil;
    updateOverlayControlValues();
    updateScaleLockControlsVisibility();
    refreshOverlayWindowVisibility();
    gApplyingRemoteState = NO;
}

static void realtimeSocketCallback(CFSocketRef socket,
                                   CFSocketCallBackType type,
                                   CFDataRef address,
                                   const void *data,
                                   void *info) {
    if (type != kCFSocketDataCallBack || !data) {
        return;
    }

    CFDataRef packetData = (CFDataRef)data;
    if (CFDataGetLength(packetData) < (CFIndex)sizeof(OverlayRealtimeMessage)) {
        return;
    }

    OverlayRealtimeMessage message;
    memcpy(&message, CFDataGetBytePtr(packetData), sizeof(message));
    applyRealtimeOverlayMessage(&message);
}

static void __attribute__((unused)) startRealtimeServerIfNeeded(void) {
    if (!gIsSpringBoardProcess || gRealtimeServerSocket) {
        return;
    }

    unlink(kOverlayRealtimeSocketPath);

    CFSocketContext context = {0, NULL, NULL, NULL, NULL};
    gRealtimeServerSocket = CFSocketCreate(kCFAllocatorDefault,
                                           PF_LOCAL,
                                           SOCK_DGRAM,
                                           0,
                                           kCFSocketDataCallBack,
                                           realtimeSocketCallback,
                                           &context);
    if (!gRealtimeServerSocket) {
        NSLog(@"[OverlayIOSTOOL] Failed to create realtime socket");
        return;
    }

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, kOverlayRealtimeSocketPath, sizeof(address.sun_path));

    NSData *addressData = [NSData dataWithBytes:&address length:sizeof(address)];
    if (CFSocketSetAddress(gRealtimeServerSocket, (__bridge CFDataRef)addressData) != kCFSocketSuccess) {
        NSLog(@"[OverlayIOSTOOL] Failed to bind realtime socket");
        CFRelease(gRealtimeServerSocket);
        gRealtimeServerSocket = NULL;
        unlink(kOverlayRealtimeSocketPath);
        return;
    }

    chmod(kOverlayRealtimeSocketPath, 0666);
    gRealtimeServerSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, gRealtimeServerSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), gRealtimeServerSource, kCFRunLoopCommonModes);
    NSLog(@"[OverlayIOSTOOL] Realtime socket ready");
}

static void sendRealtimeOverlayState(void) {
    if (gIsSpringBoardProcess || !gOverlayImageView || gApplyingRemoteState) {
        return;
    }

    if (gRealtimeClientSocket < 0) {
        gRealtimeClientSocket = socket(AF_UNIX, SOCK_DGRAM, 0);
        if (gRealtimeClientSocket < 0) {
            return;
        }
    }

    CGRect frame = gOverlayImageView.frame;
    OverlayRealtimeMessage message = {
        .magic = kOverlayRealtimeMagic,
        .version = 1,
        .kind = 1,
        .x = frame.origin.x,
        .y = frame.origin.y,
        .width = frame.size.width,
        .height = frame.size.height,
        .dimOpacity = gDimOpacity,
        .dimAnimationMs = gDimAnimationMs,
        .visible = gOverlayVisible ? 1 : 0,
        .dimmed = gOverlayDimmed ? 1 : 0,
        .scaleLock = gScaleLockModeEnabled ? 1 : 0
    };

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, kOverlayRealtimeSocketPath, sizeof(address.sun_path));

    ssize_t sent = sendto(gRealtimeClientSocket,
                          &message,
                          sizeof(message),
                          0,
                          (struct sockaddr *)&address,
                          sizeof(address));
    if (sent < 0) {
        close(gRealtimeClientSocket);
        gRealtimeClientSocket = -1;
    }
}

static void syncOverlayStateRealtime(BOOL force) {
    if (!gOverlayImageView || gApplyingRemoteState) {
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (!force && now - gLastRealtimeStateSync < (1.0 / 60.0)) {
        return;
    }

    gLastRealtimeStateSync = now;
    sendRealtimeOverlayState();
    if (force) {
        persistOverlayState(YES);
    }
}

static CGRect frameFromOverlayState(NSDictionary *state) {
    NSDictionary *frameState = state[@"frame"];
    if (![frameState isKindOfClass:NSDictionary.class]) {
        return CGRectNull;
    }

    CGFloat x = [frameState[@"x"] doubleValue];
    CGFloat y = [frameState[@"y"] doubleValue];
    CGFloat w = [frameState[@"w"] doubleValue];
    CGFloat h = [frameState[@"h"] doubleValue];
    if (w < 2 || h < 2) {
        return CGRectNull;
    }

    return CGRectMake(x, y, w, h);
}

static CGRect centeredFrameForImage(UIImage *image) {
    CGRect bounds = UIScreen.mainScreen.bounds;
    CGSize imageSize = image.size;

    if (imageSize.width <= 0 || imageSize.height <= 0) {
        return CGRectInset(bounds, bounds.size.width * 0.2, bounds.size.height * 0.35);
    }

    CGFloat maxWidth = bounds.size.width * 0.72;
    CGFloat maxHeight = bounds.size.height * 0.72;
    CGFloat scale = MIN(maxWidth / imageSize.width, maxHeight / imageSize.height);
    scale = MIN(MAX(scale, 0.08), 1.0);

    CGSize overlaySize = CGSizeMake(imageSize.width * scale, imageSize.height * scale);
    return CGRectMake((bounds.size.width - overlaySize.width) / 2.0,
                      (bounds.size.height - overlaySize.height) / 2.0,
                      overlaySize.width,
                      overlaySize.height);
}

static void configureRawImageView(UIImageView *imageView) {
    // [DEBUG 5.8.7] Nền đỏ + viền vàng để thấy cửa sổ render dù ảnh chưa tải được.
    imageView.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.45];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.userInteractionEnabled = YES;
    imageView.clipsToBounds = YES;
    imageView.layer.borderWidth = 4;
    imageView.layer.borderColor = UIColor.yellowColor.CGColor;
    imageView.layer.shadowOpacity = 0;
    imageView.layer.shadowRadius = 0;
    imageView.layer.shadowOffset = CGSizeZero;
    imageView.layer.cornerRadius = 0;
    imageView.layer.masksToBounds = YES;
}

static void applyOverlayAlpha(void) {
    if (!gOverlayImageView) {
        return;
    }
    gOverlayImageView.alpha = gOverlayDimmed ? gDimOpacity : 1.0;
}

static void animateOverlayAlphaForCurrentDimState(void) {
    if (!gOverlayImageView) {
        return;
    }

    CGFloat targetAlpha = gOverlayDimmed ? gDimOpacity : 1.0;
    if (gDimAnimationMs <= 0) {
        gOverlayImageView.alpha = targetAlpha;
        return;
    }

    [UIView animateWithDuration:gDimAnimationMs / 1000.0
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveLinear
                     animations:^{
        gOverlayImageView.alpha = targetAlpha;
    } completion:nil];
}

static BOOL rendersOverlayImage(void) {
    // iOS 15: cửa sổ SpringBoard không nổi trên app foreground được, nên CHO MỖI
    // app foreground tự vẽ overlay trong scene active của nó -> nổi trên app đó.
    return gOverlayProcessEnabled;
}

static CGFloat overlayWindowLevel(void) {
    return UIWindowLevelAlert + 100000.0;
}

static void refreshOverlayWindowVisibility(void) {
    if (!gOverlayWindow) {
        return;
    }

    attachOverlayWindowScene();

    // Khi khoá/tắt màn hình: chỉ ẩn cửa sổ, KHÔNG xoá ảnh/state.
    BOOL lockHidden = gScreenBlanked || gScreenLocked || gDataUnavailable;
    BOOL baseHidden = !gOverlayVisible && !gScaleLockModeEnabled;
    gOverlayWindow.hidden = lockHidden || baseHidden;

    if (rendersOverlayImage()) {
        gOverlayWindow.userInteractionEnabled = YES;
    } else {
        gOverlayWindow.userInteractionEnabled = gOverlayVisible || gScaleLockModeEnabled;
    }
}

static void finishOverlayQuickActions(void) {
    gQuickActionsVisible = NO;
    [gQuickActionsPanel removeFromSuperview];
    [gQuickActionsCancelButton removeFromSuperview];
    [gQuickActionsBackdrop removeFromSuperview];
    gQuickActionsPanel = nil;
    gQuickActionsCancelButton = nil;
    gQuickActionsBackdrop = nil;
    refreshOverlayWindowVisibility();
}

static void dismissOverlayQuickActions(void) {
    if (!gQuickActionsVisible) {
        return;
    }

    UIView *panel = gQuickActionsPanel;
    UIControl *backdrop = gQuickActionsBackdrop;
    UIButton *cancelButton = gQuickActionsCancelButton;
    [UIView animateWithDuration:0.18
                     animations:^{
        panel.alpha = 0.0;
        panel.transform = CGAffineTransformMakeTranslation(0.0, 24.0);
        backdrop.alpha = 0.0;
        cancelButton.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        finishOverlayQuickActions();
    }];
}

static UILabel *quickActionsLabel(NSString *text, CGFloat fontSize, UIFontWeight weight) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:fontSize weight:weight];
    return label;
}

static UIButton *quickActionsButton(NSString *title, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRed:0.10 green:0.52 blue:1.0 alpha:1.0]
                 forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightRegular];
    button.backgroundColor = [UIColor colorWithWhite:0.11 alpha:0.98];
    [button addTarget:gGestureHandler action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static void showOverlayQuickActions(void) {
    if (gScaleLockModeEnabled || gQuickActionsVisible || !gOverlayWindow || !gOverlayWindow.rootViewController) {
        return;
    }

    if (!gGestureHandler) {
        gGestureHandler = [OverlayGestureHandler new];
    }

    UIView *rootView = gOverlayWindow.rootViewController.view;
    CGRect bounds = rootView.bounds;
    CGFloat margin = 12.0;
    CGFloat safeBottom = MAX(gOverlayWindow.safeAreaInsets.bottom, 10.0);
    CGFloat cancelHeight = 64.0;
    CGFloat panelHeight = 274.0;
    CGFloat panelWidth = bounds.size.width - margin * 2.0;

    gQuickActionsVisible = YES;
    gQuickActionsBackdrop = [[UIControl alloc] initWithFrame:bounds];
    gQuickActionsBackdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    gQuickActionsBackdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.56];
    [gQuickActionsBackdrop addTarget:gGestureHandler
                              action:@selector(handleQuickActionsBackgroundButton:)
                    forControlEvents:UIControlEventTouchUpInside];
    [rootView addSubview:gQuickActionsBackdrop];

    CGFloat cancelY = bounds.size.height - safeBottom - cancelHeight;
    gQuickActionsCancelButton = quickActionsButton(@"Hủy", @selector(handleQuickActionsCancelButton:));
    gQuickActionsCancelButton.frame = CGRectMake(margin, cancelY, panelWidth, cancelHeight);
    gQuickActionsCancelButton.layer.cornerRadius = 13.0;
    gQuickActionsCancelButton.layer.masksToBounds = YES;
    [rootView addSubview:gQuickActionsCancelButton];

    CGFloat panelY = cancelY - 10.0 - panelHeight;
    gQuickActionsPanel = [[UIView alloc] initWithFrame:CGRectMake(margin, panelY, panelWidth, panelHeight)];
    gQuickActionsPanel.backgroundColor = [UIColor colorWithWhite:0.11 alpha:0.98];
    gQuickActionsPanel.layer.cornerRadius = 13.0;
    gQuickActionsPanel.layer.masksToBounds = YES;
    [rootView addSubview:gQuickActionsPanel];

    UILabel *titleLabel = quickActionsLabel(@"Số dư", 18.0, UIFontWeightSemibold);
    titleLabel.frame = CGRectMake(16.0, 17.0, panelWidth - 32.0, 26.0);
    [gQuickActionsPanel addSubview:titleLabel];

    UILabel *messageLabel = quickActionsLabel(@"Nhanh chóng di chuyển đến trang nạp/rút tiền trên trang web của broker",
                                               15.0,
                                               UIFontWeightRegular);
    messageLabel.textColor = [UIColor colorWithWhite:0.76 alpha:1.0];
    messageLabel.frame = CGRectMake(22.0, 47.0, panelWidth - 44.0, 52.0);
    [gQuickActionsPanel addSubview:messageLabel];

    UIView *separator1 = [[UIView alloc] initWithFrame:CGRectMake(0.0, 112.0, panelWidth, 0.5)];
    separator1.backgroundColor = [UIColor colorWithWhite:0.35 alpha:0.7];
    [gQuickActionsPanel addSubview:separator1];

    UIButton *depositButton = quickActionsButton(@"Tiền nạp", @selector(handleQuickActionsDepositButton:));
    depositButton.frame = CGRectMake(0.0, 112.5, panelWidth, 80.5);
    [gQuickActionsPanel addSubview:depositButton];

    UIView *separator2 = [[UIView alloc] initWithFrame:CGRectMake(0.0, 193.0, panelWidth, 0.5)];
    separator2.backgroundColor = [UIColor colorWithWhite:0.35 alpha:0.7];
    [gQuickActionsPanel addSubview:separator2];

    UIButton *withdrawButton = quickActionsButton(@"Tiền rút", @selector(handleQuickActionsWithdrawButton:));
    withdrawButton.frame = CGRectMake(0.0, 193.5, panelWidth, panelHeight - 193.5);
    [gQuickActionsPanel addSubview:withdrawButton];

    gQuickActionsBackdrop.alpha = 0.0;
    gQuickActionsPanel.alpha = 0.0;
    gQuickActionsPanel.transform = CGAffineTransformMakeTranslation(0.0, 24.0);
    gQuickActionsCancelButton.alpha = 0.0;

    [UIView animateWithDuration:0.2 animations:^{
        gQuickActionsBackdrop.alpha = 1.0;
        gQuickActionsPanel.alpha = 1.0;
        gQuickActionsPanel.transform = CGAffineTransformIdentity;
        gQuickActionsCancelButton.alpha = 1.0;
    }];
}

static void attachGestures(UIImageView *imageView) {
    if (!gGestureHandler) {
        gGestureHandler = [OverlayGestureHandler new];
    }

    gImagePanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:gGestureHandler action:@selector(handlePan:)];
    gImagePanGesture.maximumNumberOfTouches = 1;
    gImagePanGesture.delegate = gGestureHandler;
    [imageView addGestureRecognizer:gImagePanGesture];

    gImagePinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:gGestureHandler action:@selector(handlePinch:)];
    gImagePinchGesture.delegate = gGestureHandler;
    [imageView addGestureRecognizer:gImagePinchGesture];

    gImageLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:gGestureHandler action:@selector(handleLongPress:)];
    gImageLongPressGesture.minimumPressDuration = 1.0;
    gImageLongPressGesture.allowableMovement = 12.0;
    gImageLongPressGesture.delegate = gGestureHandler;
    [imageView addGestureRecognizer:gImageLongPressGesture];

    gQuickActionsTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:gGestureHandler action:@selector(handleQuickActionsTap:)];
    gQuickActionsTapGesture.numberOfTapsRequired = 1;
    gQuickActionsTapGesture.delegate = gGestureHandler;
    [gQuickActionsTapGesture requireGestureRecognizerToFail:gImageLongPressGesture];
    [imageView addGestureRecognizer:gQuickActionsTapGesture];
}

static void attachOverlayWindowScene(void) {
    // iOS 13+ BẮT BUỘC cửa sổ phải thuộc 1 UIWindowScene mới render. Gắn vào scene
    // đang foreground-active của CHÍNH tiến trình này (app foreground hoặc
    // SpringBoard khi ở màn hình chính) -> overlay hiện trên tiến trình đó.
    if (!gOverlayWindow) {
        return;
    }
    UIWindowScene *active = nil;
    UIWindowScene *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            active = (UIWindowScene *)scene;
            break;
        }
        if (!fallback) {
            fallback = (UIWindowScene *)scene;
        }
    }
    UIWindowScene *target = active ?: fallback;
    if (target && gOverlayWindow.windowScene != target) {
        gOverlayWindow.windowScene = target;
    }
}

static void ensureOverlayWindow(void) {
    if (gOverlayWindow || !gOverlayHostReady) {
        return;
    }

    CGRect bounds = UIScreen.mainScreen.bounds;
    gOverlayWindow = [[OverlayPassthroughWindow alloc] initWithFrame:bounds];
    gOverlayWindow.windowLevel = overlayWindowLevel();
    gOverlayWindow.backgroundColor = UIColor.clearColor;
    gOverlayWindow.opaque = NO;
    gOverlayWindow.clipsToBounds = NO;

    UIViewController *rootViewController = [UIViewController new];
    rootViewController.view.backgroundColor = UIColor.clearColor;
    rootViewController.view.userInteractionEnabled = YES;
    gOverlayWindow.rootViewController = rootViewController;
    attachOverlayWindowScene();
    gOverlayWindow.hidden = NO;
}

static void applyScaleLockMode(BOOL enabled);

static void applyOverlayStateFromDisk(void) {
    if (!gOverlayImageView) {
        return;
    }

    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:kOverlayStatePath];
    if (![state isKindOfClass:NSDictionary.class]) {
        return;
    }

    gApplyingRemoteState = YES;

    CGRect frame = frameFromOverlayState(state);
    if (!CGRectIsNull(frame)) {
        gOverlayImageView.frame = frame;
    }

    if (state[@"overlayVisible"]) {
        gOverlayVisible = [state[@"overlayVisible"] boolValue];
        gOverlayImageView.hidden = !gOverlayVisible;
    }

    if (state[@"overlayDimmed"]) {
        gOverlayDimmed = [state[@"overlayDimmed"] boolValue];
    }

    if (state[@"dimOpacity"]) {
        gDimOpacity = MAX(0.0, MIN([state[@"dimOpacity"] doubleValue], 1.0));
    }

    if (state[@"dimAnimationMs"]) {
        gDimAnimationMs = MAX(0, MIN([state[@"dimAnimationMs"] integerValue], 10000));
    }

    if (state[@"scaleLockModeEnabled"]) {
        applyScaleLockMode([state[@"scaleLockModeEnabled"] boolValue]);
    }

    applyOverlayAlpha();
    updateOverlayControlValues();
    updateScaleLockControlsVisibility();
    refreshOverlayWindowVisibility();

    gApplyingRemoteState = NO;
}

static CGRect expandedScaleHitboxInRootView(void) {
    if (!gOverlayImageView || !gOverlayWindow) {
        return CGRectNull;
    }

    UIView *rootView = gOverlayWindow.rootViewController.view;
    CGRect imageFrame = [gOverlayImageView.superview convertRect:gOverlayImageView.frame toView:rootView];
    CGFloat inflateX = MAX(imageFrame.size.width * 25.0, 240.0);
    CGFloat inflateY = MAX(imageFrame.size.height * 25.0, 240.0);
    return CGRectInset(imageFrame, -inflateX, -inflateY);
}

static void updateExpandedPinchGesture(void) {
    if (!gOverlayWindow || !gGestureHandler) {
        return;
    }

    UIView *rootView = gOverlayWindow.rootViewController.view;
    if (!gExpandedPinchGesture) {
        gExpandedPinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:gGestureHandler action:@selector(handleExpandedPinch:)];
        gExpandedPinchGesture.cancelsTouchesInView = YES;
        gExpandedPinchGesture.delegate = gGestureHandler;
        [rootView addGestureRecognizer:gExpandedPinchGesture];
    }

    if (!gRelativePanGesture) {
        gRelativePanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:gGestureHandler action:@selector(handleRelativePan:)];
        gRelativePanGesture.minimumNumberOfTouches = 1;
        gRelativePanGesture.maximumNumberOfTouches = 1;
        gRelativePanGesture.cancelsTouchesInView = YES;
        gRelativePanGesture.delegate = gGestureHandler;
        [rootView addGestureRecognizer:gRelativePanGesture];
    }

    if (!gInputBlockTapGesture) {
        gInputBlockTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:gGestureHandler action:@selector(handleBlockedTap:)];
        gInputBlockTapGesture.cancelsTouchesInView = YES;
        gInputBlockTapGesture.delegate = gGestureHandler;
        [gInputBlockTapGesture requireGestureRecognizerToFail:gExpandedPinchGesture];
        [gInputBlockTapGesture requireGestureRecognizerToFail:gRelativePanGesture];
        [rootView addGestureRecognizer:gInputBlockTapGesture];
    }
}

static UILabel *overlayControlLabel(NSString *text, CGFloat fontSize, UIFontWeight weight) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:fontSize weight:weight];
    return label;
}

static void writeOverlaySettings(void) {
    NSDictionary *settings = @{
        @"toggleClickEnabled": @(gToggleClickEnabled),
        @"hideDelayMs": @(gHideDelayMs),
        @"showDelayMs": @(gShowDelayMs),
        @"dimOpacity": @(gDimOpacity),
        @"dimAnimationMs": @(gDimAnimationMs)
    };
    [NSFileManager.defaultManager createDirectoryAtPath:[kOverlaySettingsPath stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    [settings writeToFile:kOverlaySettingsPath atomically:YES];
    notify_post(kOverlaySettingsNotification);
}

static void updateOverlayControlValues(void) {
    if (!gScaleLockControlsPanel) {
        return;
    }

    if (gOverlayHideDelaySlider && !gOverlayHideDelaySlider.tracking) {
        gOverlayHideDelaySlider.value = gHideDelayMs;
    }
    if (gOverlayShowDelaySlider && !gOverlayShowDelaySlider.tracking) {
        gOverlayShowDelaySlider.value = gShowDelayMs;
    }
    if (gOverlayDimOpacitySlider && !gOverlayDimOpacitySlider.tracking) {
        gOverlayDimOpacitySlider.value = gDimOpacity;
    }
    if (gOverlayDimAnimationSlider && !gOverlayDimAnimationSlider.tracking) {
        gOverlayDimAnimationSlider.value = gDimAnimationMs;
    }

    gOverlayHideDelayValueLabel.text = [NSString stringWithFormat:@"%ld ms", (long)gHideDelayMs];
    gOverlayShowDelayValueLabel.text = [NSString stringWithFormat:@"%ld ms", (long)gShowDelayMs];
    gOverlayDimOpacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", gDimOpacity * 100.0];
    gOverlayDimAnimationValueLabel.text = [NSString stringWithFormat:@"%ld ms", (long)gDimAnimationMs];
    NSString *buttonTitle = gToggleClickEnabled ? @"Tat Toggle Click" : @"Bat Toggle Click";
    [gToggleClickButton setTitle:buttonTitle forState:UIControlStateNormal];
}

static void updateScaleLockControlsVisibility(void) {
    if (!gScaleLockControlsPanel) {
        return;
    }
    gScaleLockControlsPanel.hidden = !gScaleLockModeEnabled;
    gScaleLockControlsPanel.alpha = rendersOverlayImage() ? 1.0 : 0.02;
}

static BOOL pointInsideScaleLockControls(CGPoint pointInWindow) {
    if (!gScaleLockControlsPanel || gScaleLockControlsPanel.hidden || !gOverlayWindow) {
        return NO;
    }
    CGPoint point = [gScaleLockControlsPanel convertPoint:pointInWindow fromView:gOverlayWindow];
    return [gScaleLockControlsPanel pointInside:point withEvent:nil];
}

static void overlayHideDelayChanged(UISlider *slider) {
    gHideDelayMs = (NSInteger)slider.value;
    updateOverlayControlValues();
    writeOverlaySettings();
}

static void overlayShowDelayChanged(UISlider *slider) {
    gShowDelayMs = (NSInteger)slider.value;
    updateOverlayControlValues();
    writeOverlaySettings();
}

static void overlayDimOpacityChanged(UISlider *slider) {
    gDimOpacity = MAX(0.0, MIN(slider.value, 1.0));
    applyOverlayAlpha();
    updateOverlayControlValues();
    writeOverlaySettings();
    persistOverlayState(YES);
}

static void overlayDimAnimationChanged(UISlider *slider) {
    gDimAnimationMs = (NSInteger)slider.value;
    updateOverlayControlValues();
    writeOverlaySettings();
}

static void toggleClickTapped(__unused UIButton *button) {
    gToggleClickEnabled = !gToggleClickEnabled;
    if (!gToggleClickEnabled) {
        gOverlayDimmed = NO;
    }
    applyOverlayAlpha();
    updateOverlayControlValues();
    writeOverlaySettings();
    persistOverlayState(YES);
}

static void hideImageFromPanelTapped(__unused UIButton *button) {
    if (!gOverlayImageView) {
        return;
    }

    if (gScaleLockModeEnabled) {
        applyScaleLockMode(NO);
    }
    gOverlayVisible = NO;
    gOverlayDimmed = NO;
    gToggleGeneration++;
    gOverlayImageView.hidden = YES;
    gOverlayImageView.layer.borderWidth = 0;
    gOverlayImageView.layer.borderColor = nil;
    applyOverlayAlpha();
    updateScaleLockControlsVisibility();
    refreshOverlayWindowVisibility();
    persistOverlayState(YES);
    syncOverlayStateRealtime(YES);
}

@interface OverlayControlTarget : NSObject
- (void)hideDelayChanged:(UISlider *)slider;
- (void)showDelayChanged:(UISlider *)slider;
- (void)dimOpacityChanged:(UISlider *)slider;
- (void)dimAnimationChanged:(UISlider *)slider;
- (void)toggleClickTapped:(UIButton *)button;
- (void)hideImageTapped:(UIButton *)button;
@end

@implementation OverlayControlTarget
- (void)hideDelayChanged:(UISlider *)slider { overlayHideDelayChanged(slider); }
- (void)showDelayChanged:(UISlider *)slider { overlayShowDelayChanged(slider); }
- (void)dimOpacityChanged:(UISlider *)slider { overlayDimOpacityChanged(slider); }
- (void)dimAnimationChanged:(UISlider *)slider { overlayDimAnimationChanged(slider); }
- (void)toggleClickTapped:(UIButton *)button { toggleClickTapped(button); }
- (void)hideImageTapped:(UIButton *)button { hideImageFromPanelTapped(button); }
@end

static OverlayControlTarget *gOverlayControlTarget = nil;

static void ensureScaleLockControls(void) {
    if (!gOverlayWindow || gScaleLockControlsPanel) {
        return;
    }

    if (!gOverlayControlTarget) {
        gOverlayControlTarget = [OverlayControlTarget new];
    }

    UIView *rootView = gOverlayWindow.rootViewController.view;
    CGRect bounds = rootView.bounds;
    CGFloat safeBottom = gOverlayWindow.safeAreaInsets.bottom;
    CGFloat panelHeight = 328.0;
    CGFloat margin = 12.0;
    gScaleLockControlsPanel = [[UIView alloc] initWithFrame:CGRectMake(margin,
                                                                       bounds.size.height - panelHeight - MAX(safeBottom, margin),
                                                                       bounds.size.width - margin * 2.0,
                                                                       panelHeight)];
    gScaleLockControlsPanel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    gScaleLockControlsPanel.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.82];
    gScaleLockControlsPanel.layer.cornerRadius = 12.0;
    gScaleLockControlsPanel.hidden = YES;
    [rootView addSubview:gScaleLockControlsPanel];

    NSArray<NSString *> *titles = @[@"Delay an", @"Delay hien", @"Do mo", @"Animation mo"];
    NSMutableArray<UILabel *> *titleLabels = [NSMutableArray array];
    NSMutableArray<UILabel *> *valueLabels = [NSMutableArray array];
    NSMutableArray<UISlider *> *sliders = [NSMutableArray array];

    for (NSUInteger index = 0; index < titles.count; index++) {
        CGFloat y = 14.0 + index * 55.0;
        UILabel *title = overlayControlLabel(titles[index], 13.0, UIFontWeightSemibold);
        title.frame = CGRectMake(14.0, y, 130.0, 20.0);
        [gScaleLockControlsPanel addSubview:title];
        [titleLabels addObject:title];

        UILabel *value = overlayControlLabel(@"", 13.0, UIFontWeightRegular);
        value.textAlignment = NSTextAlignmentRight;
        value.frame = CGRectMake(gScaleLockControlsPanel.bounds.size.width - 104.0, y, 90.0, 20.0);
        value.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [gScaleLockControlsPanel addSubview:value];
        [valueLabels addObject:value];

        UISlider *slider = [UISlider new];
        slider.frame = CGRectMake(14.0, y + 22.0, gScaleLockControlsPanel.bounds.size.width - 28.0, 28.0);
        slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [gScaleLockControlsPanel addSubview:slider];
        [sliders addObject:slider];
    }

    gOverlayHideDelayValueLabel = valueLabels[0];
    gOverlayShowDelayValueLabel = valueLabels[1];
    gOverlayDimOpacityValueLabel = valueLabels[2];
    gOverlayDimAnimationValueLabel = valueLabels[3];
    gOverlayHideDelaySlider = sliders[0];
    gOverlayShowDelaySlider = sliders[1];
    gOverlayDimOpacitySlider = sliders[2];
    gOverlayDimAnimationSlider = sliders[3];

    gOverlayHideDelaySlider.minimumValue = 0;
    gOverlayHideDelaySlider.maximumValue = 2000;
    gOverlayShowDelaySlider.minimumValue = 0;
    gOverlayShowDelaySlider.maximumValue = 2000;
    gOverlayDimOpacitySlider.minimumValue = 0.0;
    gOverlayDimOpacitySlider.maximumValue = 1.0;
    gOverlayDimAnimationSlider.minimumValue = 0;
    gOverlayDimAnimationSlider.maximumValue = 2000;

    [gOverlayHideDelaySlider addTarget:gOverlayControlTarget action:@selector(hideDelayChanged:) forControlEvents:UIControlEventValueChanged];
    [gOverlayShowDelaySlider addTarget:gOverlayControlTarget action:@selector(showDelayChanged:) forControlEvents:UIControlEventValueChanged];
    [gOverlayDimOpacitySlider addTarget:gOverlayControlTarget action:@selector(dimOpacityChanged:) forControlEvents:UIControlEventValueChanged];
    [gOverlayDimAnimationSlider addTarget:gOverlayControlTarget action:@selector(dimAnimationChanged:) forControlEvents:UIControlEventValueChanged];

    gToggleClickButton = [UIButton buttonWithType:UIButtonTypeSystem];
    gToggleClickButton.frame = CGRectMake(14.0, panelHeight - 48.0, gScaleLockControlsPanel.bounds.size.width - 28.0, 36.0);
    gToggleClickButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    gToggleClickButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.47 blue:1.0 alpha:0.95];
    gToggleClickButton.layer.cornerRadius = 8.0;
    gToggleClickButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [gToggleClickButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [gToggleClickButton addTarget:gOverlayControlTarget action:@selector(toggleClickTapped:) forControlEvents:UIControlEventTouchUpInside];
    [gScaleLockControlsPanel addSubview:gToggleClickButton];

    gHideImageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    gHideImageButton.frame = CGRectMake(14.0, panelHeight - 92.0, gScaleLockControlsPanel.bounds.size.width - 28.0, 36.0);
    gHideImageButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    gHideImageButton.backgroundColor = [UIColor colorWithRed:0.95 green:0.22 blue:0.18 alpha:0.95];
    gHideImageButton.layer.cornerRadius = 8.0;
    gHideImageButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [gHideImageButton setTitle:@"An anh" forState:UIControlStateNormal];
    [gHideImageButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [gHideImageButton addTarget:gOverlayControlTarget action:@selector(hideImageTapped:) forControlEvents:UIControlEventTouchUpInside];
    [gScaleLockControlsPanel addSubview:gHideImageButton];

    updateOverlayControlValues();
    updateScaleLockControlsVisibility();
}

static UIImage *overlayImageFromPasteboard(void) {
    UIPasteboard *pasteboard = overlayPasteboard(NO);
    UIImage *image = pasteboard.image;
    if (image) {
        return image;
    }

    NSData *pngData = [pasteboard dataForPasteboardType:@"public.png"];
    if (pngData.length) {
        image = [UIImage imageWithData:pngData scale:UIScreen.mainScreen.scale];
        if (image) {
            return image;
        }
    }

    NSData *jpegData = [pasteboard dataForPasteboardType:@"public.jpeg"];
    if (jpegData.length) {
        return [UIImage imageWithData:jpegData scale:UIScreen.mainScreen.scale];
    }

    return nil;
}

static UIImage *overlayImageFromSharedFile(void) {
    NSData *imageData = [NSData dataWithContentsOfFile:kOverlayImagePath];
    if (!imageData.length) {
        return nil;
    }
    return [UIImage imageWithData:imageData scale:UIScreen.mainScreen.scale];
}

static void showOverlayImage(UIImage *image) {
    if (!image) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        ensureOverlayWindow();
        if (!gOverlayWindow) {
            return;
        }

        if (!gOverlayImageView) {
            gOverlayImageView = [[UIImageView alloc] initWithFrame:centeredFrameForImage(image)];
            configureRawImageView(gOverlayImageView);
            attachGestures(gOverlayImageView);
            [gOverlayWindow.rootViewController.view addSubview:gOverlayImageView];
        }
        updateExpandedPinchGesture();
        ensureScaleLockControls();

        gOverlayImageView.image = rendersOverlayImage() ? image : nil;
        if (CGRectIsEmpty(gOverlayImageView.frame) || gOverlayImageView.frame.size.width < 2 || gOverlayImageView.frame.size.height < 2) {
            gOverlayImageView.frame = centeredFrameForImage(image);
        }

        gOverlayImageView.hidden = NO;
        applyOverlayAlpha();
        gOverlayVisible = YES;
        applyOverlayStateFromDisk();
        refreshOverlayWindowVisibility();
        persistOverlayState(NO);
        NSLog(@"[OverlayIOSTOOL] Overlay shown %.0fx%.0f", image.size.width, image.size.height);
    });
}

static void loadAndShowPublishedOverlay(void) {
    UIImage *image = overlayImageFromPasteboard();
    if (!image) {
        image = overlayImageFromSharedFile();
    }

    if (!image) {
        NSLog(@"[OverlayIOSTOOL] No published image");
        return;
    }

    showOverlayImage(image);
}

static void removeOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gQuickActionsVisible) {
            dismissOverlayQuickActions();
        }
        if (gScaleLockModeEnabled) {
            applyScaleLockMode(NO);
        }
        gScaleLockModeEnabled = NO;
        if (gOverlayImageView) {
            [gOverlayImageView removeFromSuperview];
            gOverlayImageView = nil;
        }

        if (gOverlayWindow) {
            gOverlayWindow.hidden = YES;
        }

        gOverlayVisible = NO;
        NSLog(@"[OverlayIOSTOOL] Overlay removed");
    });
}

static void clearPublishedStorage(void) {
    [UIPasteboard removePasteboardWithName:kOverlayPasteboardName];
    [NSFileManager.defaultManager removeItemAtPath:kOverlayImagePath error:nil];
    [NSFileManager.defaultManager removeItemAtPath:kOverlayStatePath error:nil];
}

static void __attribute__((unused)) stopOverlayTool(void) {
    clearPublishedStorage();
    removeOverlay();
}

static void loadOverlaySettings(void) {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:kOverlaySettingsPath];
    gToggleClickEnabled = [settings[@"toggleClickEnabled"] boolValue];
    gHideDelayMs = settings[@"hideDelayMs"] ? [settings[@"hideDelayMs"] integerValue] : 0;
    gShowDelayMs = settings[@"showDelayMs"] ? [settings[@"showDelayMs"] integerValue] : 0;
    gDimOpacity = settings[@"dimOpacity"] ? [settings[@"dimOpacity"] doubleValue] : 1.0;
    gDimAnimationMs = settings[@"dimAnimationMs"] ? [settings[@"dimAnimationMs"] integerValue] : 0;
    gHideDelayMs = MAX(0, MIN(gHideDelayMs, 10000));
    gShowDelayMs = MAX(0, MIN(gShowDelayMs, 10000));
    gDimAnimationMs = MAX(0, MIN(gDimAnimationMs, 10000));
    gDimOpacity = MAX(0.0, MIN(gDimOpacity, 1.0));
    if (!gToggleClickEnabled) {
        gOverlayDimmed = NO;
    }
    applyOverlayAlpha();
    updateOverlayControlValues();
    NSLog(@"[OverlayIOSTOOL] Settings toggle=%@ hide=%ld show=%ld dim=%.2f anim=%ld", @(gToggleClickEnabled), (long)gHideDelayMs, (long)gShowDelayMs, gDimOpacity, (long)gDimAnimationMs);
}

static void applyOverlayVisibility(BOOL visible) {
    if (!gOverlayImageView) {
        return;
    }

    if (gScaleLockModeEnabled) {
        return;
    }

    gOverlayVisible = visible;
    if (!visible) {
        gOverlayDimmed = NO;
    }
    applyOverlayAlpha();
    gOverlayImageView.hidden = !visible;
    refreshOverlayWindowVisibility();
    persistOverlayState(YES);
}

static void applyOverlayDimmed(BOOL dimmed) {
    if (!gOverlayImageView || !gOverlayVisible || gScaleLockModeEnabled) {
        return;
    }

    gOverlayDimmed = dimmed;
    gOverlayImageView.hidden = NO;
    animateOverlayAlphaForCurrentDimState();
    refreshOverlayWindowVisibility();
    persistOverlayState(YES);
}

static void applyScaleLockMode(BOOL enabled) {
    if (!gOverlayImageView) {
        gScaleLockModeEnabled = NO;
        return;
    }

    if (enabled && gQuickActionsVisible) {
        dismissOverlayQuickActions();
    }

    gScaleLockModeEnabled = enabled;
    gToggleGeneration++;

    gImagePanGesture.enabled = !enabled;
    gImagePinchGesture.enabled = !enabled;
    gQuickActionsTapGesture.enabled = !enabled;

    // Reset recognizer state when switching modes, which is important on older devices.
    gExpandedPinchGesture.enabled = NO;
    gExpandedPinchGesture.enabled = YES;
    gRelativePanGesture.enabled = NO;
    gRelativePanGesture.enabled = YES;
    gInputBlockTapGesture.enabled = NO;
    gInputBlockTapGesture.enabled = YES;

    if (enabled) {
        gOverlayVisible = YES;
        gOverlayDimmed = NO;
        gOverlayWindow.frame = UIScreen.mainScreen.bounds;
        gOverlayWindow.windowLevel = overlayWindowLevel();
        gOverlayWindow.userInteractionEnabled = YES;
        gOverlayWindow.rootViewController.view.userInteractionEnabled = YES;
        gOverlayWindow.hidden = NO;
        if (!gOverlayWindow.isKeyWindow) {
            gPreviousKeyWindow = currentKeyWindowExcludingOverlay();
            [gOverlayWindow makeKeyAndVisible];
        }
        gOverlayImageView.hidden = NO;
        applyOverlayAlpha();
        gOverlayImageView.layer.borderWidth = rendersOverlayImage() ? 3.0 : 0.0;
        gOverlayImageView.layer.borderColor = rendersOverlayImage() ? UIColor.systemBlueColor.CGColor : nil;
    } else {
        gOverlayWindow.windowLevel = overlayWindowLevel();
        gOverlayImageView.layer.borderWidth = 0;
        gOverlayImageView.layer.borderColor = nil;
        [gOverlayWindow resignKeyWindow];
        if (gPreviousKeyWindow) {
            [gPreviousKeyWindow makeKeyWindow];
        }
        gPreviousKeyWindow = nil;
    }

    refreshOverlayWindowVisibility();
    updateScaleLockControlsVisibility();
    updateOverlayControlValues();
    persistOverlayState(YES);
    NSLog(@"[OverlayIOSTOOL] Scale lock mode %@", enabled ? @"ON" : @"OFF");
}

static void __attribute__((unused)) scheduleToggleOverlayVisibility(void) {
    if (!gToggleClickEnabled || !gOverlayImageView) {
        return;
    }

    BOOL targetDimmed = !gOverlayDimmed;
    NSInteger delayMs = targetDimmed ? gHideDelayMs : gShowDelayMs;
    NSUInteger generation = ++gToggleGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayMs * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        if (generation != gToggleGeneration) {
            return;
        }
        applyOverlayDimmed(targetDimmed);
    });
}

static BOOL pointInsideOverlayImage(CGPoint pointInWindow) {
    if (!gOverlayImageView || gOverlayImageView.hidden || !gOverlayVisible) {
        return NO;
    }

    CGPoint point = [gOverlayImageView convertPoint:pointInWindow fromView:gOverlayWindow];
    return [gOverlayImageView pointInside:point withEvent:nil];
}

static BOOL touchInsideOverlayImage(UITouch *touch) {
    if (!touch || !gOverlayWindow || !gOverlayImageView) {
        return NO;
    }

    UIWindow *sourceWindow = touch.window;
    CGPoint sourcePoint = [touch locationInView:sourceWindow];
    CGPoint overlayPoint = sourceWindow ? [gOverlayWindow convertPoint:sourcePoint fromWindow:sourceWindow] : [touch locationInView:gOverlayWindow];
    return pointInsideOverlayImage(overlayPoint);
}

static void __attribute__((unused)) handleHiddenImageDoubleTapIfNeeded(UIEvent *event) {
    if (gScaleLockModeEnabled || !gOverlayImageView || gOverlayVisible || event.type != UIEventTypeTouches) {
        return;
    }

    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan || touch.tapCount < 2) {
            continue;
        }

        applyOverlayVisibility(YES);
        syncOverlayStateRealtime(YES);
        return;
    }
}

static void registerOverlayNotification(void) {
    if (!gOverlayProcessEnabled || gNotifyToken != 0) {
        return;
    }

    notify_register_dispatch(kOverlayUpdatedNotification, &gNotifyToken, dispatch_get_main_queue(), ^(__unused int token) {
        NSLog(@"[OverlayIOSTOOL] Update notification received");
        loadAndShowPublishedOverlay();
    });

    notify_register_dispatch(kOverlayRemoveNotification, &gRemoveToken, dispatch_get_main_queue(), ^(__unused int token) {
        NSLog(@"[OverlayIOSTOOL] Remove notification received");
        clearPublishedStorage();
        removeOverlay();
    });

    notify_register_dispatch(kOverlaySettingsNotification, &gSettingsToken, dispatch_get_main_queue(), ^(__unused int token) {
        loadOverlaySettings();
    });

    if (gIsSpringBoardProcess) {
        notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &gBlankedScreenToken, dispatch_get_main_queue(), ^(int token) {
            uint64_t state = 0;
            notify_get_state(token, &state);
            gScreenBlanked = (state != 0);   // 1 = màn hình tắt
            refreshOverlayWindowVisibility();
        });

        notify_register_dispatch("com.apple.springboard.lockstate", &gLockStateToken, dispatch_get_main_queue(), ^(int token) {
            uint64_t state = 0;
            notify_get_state(token, &state);
            gScreenLocked = (state != 0);    // 1 = đã khoá
            refreshOverlayWindowVisibility();
        });
    }

    notify_register_dispatch(kOverlayStateNotification, &gStateToken, dispatch_get_main_queue(), ^(__unused int token) {
        if (!gOverlayImageView) {
            loadAndShowPublishedOverlay();
            return;
        }
        applyOverlayStateFromDisk();
    });
}

static void activateOverlayHost(void) {
    if (!gOverlayProcessEnabled || !UIApplication.sharedApplication) {
        return;
    }

    if (!gOverlayHostReady) {
        gOverlayHostReady = YES;
        loadOverlaySettings();
        registerOverlayNotification();
        startRealtimeServerIfNeeded();
        NSLog(@"[OverlayIOSTOOL] Overlay host ready in %@", NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName);
    }

    if (!gIsSpringBoardProcess && ![NSFileManager.defaultManager fileExistsAtPath:kOverlayImagePath] && !overlayPasteboard(NO).image) {
        return;
    }

    if (!gIsSpringBoardProcess) {
        loadAndShowPublishedOverlay();
    }
}

@implementation OverlayGestureHandler

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    if (!view || gScaleLockModeEnabled) {
        return;
    }

    CGPoint translation = [gesture translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:view.superview];
    BOOL finished = (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled);
    syncOverlayStateRealtime(finished);
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    if (!view || gScaleLockModeEnabled) {
        return;
    }

    CGFloat scale = gesture.scale;
    CGSize newSize = CGSizeMake(view.bounds.size.width * scale, view.bounds.size.height * scale);
    if (newSize.width >= 24 && newSize.height >= 24) {
        view.bounds = CGRectMake(0, 0, newSize.width, newSize.height);
    }
    gesture.scale = 1.0;
    BOOL finished = (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled);
    syncOverlayStateRealtime(finished);
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        applyScaleLockMode(!gScaleLockModeEnabled);
    }
}

- (void)handleQuickActionsTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized && !gScaleLockModeEnabled) {
        showOverlayQuickActions();
    }
}

- (void)handleQuickActionsBackgroundButton:(__unused UIControl *)control {
    dismissOverlayQuickActions();
}

- (void)handleQuickActionsCancelButton:(__unused UIButton *)button {
    dismissOverlayQuickActions();
}

- (void)handleQuickActionsDepositButton:(__unused UIButton *)button {
    finishOverlayQuickActions();
    notify_post(kOverlayDepositActionNotification);
}

- (void)handleQuickActionsWithdrawButton:(__unused UIButton *)button {
    finishOverlayQuickActions();
    notify_post(kOverlayWithdrawActionNotification);
}

- (void)handleExpandedPinch:(UIPinchGestureRecognizer *)gesture {
    if (!gOverlayImageView) {
        return;
    }

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        gesture.scale = 1.0;
        syncOverlayStateRealtime(YES);
        return;
    }

    if (gesture.numberOfTouches < 2) {
        gesture.scale = 1.0;
        return;
    }

    UIView *rootView = gOverlayWindow.rootViewController.view;
    if (!gScaleLockModeEnabled) {
        CGPoint firstPoint = [gesture locationOfTouch:0 inView:rootView];
        CGPoint secondPoint = [gesture locationOfTouch:1 inView:rootView];
        CGRect hitbox = expandedScaleHitboxInRootView();
        if (!CGRectContainsPoint(hitbox, firstPoint) || !CGRectContainsPoint(hitbox, secondPoint)) {
            gesture.scale = 1.0;
            return;
        }
    }

    CGFloat scale = MAX(0.5, MIN(gesture.scale, 2.0));
    CGSize newSize = CGSizeMake(gOverlayImageView.bounds.size.width * scale, gOverlayImageView.bounds.size.height * scale);
    CGFloat maxDimension = MAX(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height) * 20.0;
    if (newSize.width >= 12 && newSize.height >= 12 &&
        newSize.width <= maxDimension && newSize.height <= maxDimension) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        gOverlayImageView.bounds = CGRectMake(0, 0, newSize.width, newSize.height);
        [CATransaction commit];
    }
    gesture.scale = 1.0;
    syncOverlayStateRealtime(NO);
}

- (void)handleRelativePan:(UIPanGestureRecognizer *)gesture {
    if (!gScaleLockModeEnabled || !gOverlayImageView) {
        [gesture setTranslation:CGPointZero inView:gOverlayWindow.rootViewController.view];
        return;
    }

    UIView *rootView = gOverlayWindow.rootViewController.view;
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        [gesture setTranslation:CGPointZero inView:rootView];
        syncOverlayStateRealtime(YES);
        return;
    }

    CGPoint translation = [gesture translationInView:rootView];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gOverlayImageView.center = CGPointMake(gOverlayImageView.center.x + translation.x, gOverlayImageView.center.y + translation.y);
    [CATransaction commit];
    [gesture setTranslation:CGPointZero inView:rootView];
    syncOverlayStateRealtime(NO);
}

- (void)handleBlockedTap:(UITapGestureRecognizer *)gesture {
    // Intentionally consume taps while scale-lock mode routes the whole screen to the overlay window.
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gQuickActionsVisible) {
        return NO;
    }

    if (gScaleLockModeEnabled && gOverlayWindow) {
        CGPoint point = [touch locationInView:gOverlayWindow];
        if (pointInsideScaleLockControls(point)) {
            return NO;
        }
    }
    if (gestureRecognizer == gImagePanGesture || gestureRecognizer == gImagePinchGesture) {
        return !gScaleLockModeEnabled;
    }
    if (gestureRecognizer == gQuickActionsTapGesture) {
        return !gScaleLockModeEnabled;
    }
    if (gestureRecognizer == gExpandedPinchGesture) {
        if (gScaleLockModeEnabled) {
            return YES;
        }
        return !gOverlayImageView || ![touch.view isDescendantOfView:gOverlayImageView];
    }
    if (gestureRecognizer == gInputBlockTapGesture) {
        return gScaleLockModeEnabled;
    }
    if (gestureRecognizer == gRelativePanGesture) {
        return gScaleLockModeEnabled;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == gInputBlockTapGesture || otherGestureRecognizer == gInputBlockTapGesture) {
        return NO;
    }
    return YES;
}

@end

%group OverlayUIApplicationHooks

%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    if (!gOverlayProcessEnabled) {
        %orig(event);
        return;
    }

    BOOL quickActionsWereVisible = gQuickActionsVisible;

    if (event.type == UIEventTypeTouches && gScaleLockModeEnabled && gOverlayImageView) {
        BOOL overlayTouch = NO;
        for (UITouch *touch in event.allTouches) {
            UIWindow *touchWindow = touch.window;
            if (touchWindow == gOverlayWindow || [touch.view isDescendantOfView:gOverlayWindow]) {
                overlayTouch = YES;
                break;
            }
        }

        if (!overlayTouch) {
            return;
        }

        %orig(event);
        return;
    }

    %orig(event);

    if (quickActionsWereVisible || gQuickActionsVisible) {
        return;
    }

    handleHiddenImageDoubleTapIfNeeded(event);

    if (gScaleLockModeEnabled || !gToggleClickEnabled || !gOverlayImageView || event.type != UIEventTypeTouches) {
        return;
    }

    BOOL hasOutsideBeganTouch = NO;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) {
            continue;
        }

        if (touchInsideOverlayImage(touch)) {
            return;
        }

        hasOutsideBeganTouch = YES;
    }

    if (hasOutsideBeganTouch) {
        scheduleToggleOverlayVisibility();
    }
}

%end

%end

%ctor {
    @autoreleasepool {
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
        gIsSpringBoardProcess = [bundleIdentifier isEqualToString:@"com.apple.springboard"];
        if (gIsSpringBoardProcess && springBoardCrashGuardShouldDisable()) {
            return;
        }
        gOverlayProcessEnabled = shouldEnableOverlayInCurrentProcess();
        if (!gOverlayProcessEnabled) {
            return;
        }

        %init(OverlayUIApplicationHooks);

        NSLog(@"[OverlayIOSTOOL] Loaded in %@", NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gObserversInstalled) {
                return;
            }
            gObserversInstalled = YES;

            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                              object:nil
                                                               queue:NSOperationQueue.mainQueue
                                                          usingBlock:^(__unused NSNotification *notification) {
                activateOverlayHost();
            }];
            if (gIsSpringBoardProcess) {
                [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataWillBecomeUnavailable
                                                                  object:nil
                                                                   queue:NSOperationQueue.mainQueue
                                                              usingBlock:^(__unused NSNotification *notification) {
                    gDataUnavailable = YES;          // khoá máy -> chỉ ẩn, giữ ảnh
                    refreshOverlayWindowVisibility();
                }];
                [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable
                                                                  object:nil
                                                                   queue:NSOperationQueue.mainQueue
                                                              usingBlock:^(__unused NSNotification *notification) {
                    gDataUnavailable = NO;           // mở khoá -> hiện lại
                    refreshOverlayWindowVisibility();
                }];
            }
        });
        if (gIsSpringBoardProcess) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                activateOverlayHost();
            });
        }
    }
}
