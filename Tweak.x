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
#import <stdio.h>

static NSString * const kOverlayDirectory = @"/var/mobile/Library/OverlayIOSTOOL";
static NSString * const kOverlayImagePath = @"/var/mobile/Library/OverlayIOSTOOL/overlay.png";
static NSString * const kOverlaySettingsPath = @"/var/mobile/Library/OverlayIOSTOOL/settings.plist";
static NSString * const kOverlayStatePath = @"/var/mobile/Library/OverlayIOSTOOL/state.plist";
static NSString * const kOverlayPasteboardName = @"com.vietanh.overlayiostool.image";
// Pasteboard "báo danh": mỗi app tweak chạy vào ghi 1 dòng "<bundleid> <status>"
// -> app tool đọc để biết tweak ĐÃ vào app nào (chẩn đoán, không phải đoán mò).
static NSString * const kOverlayActiveAppsPasteboard = @"com.vietanh.overlayiostool.active-apps";
static const char *kOverlayUpdatedNotification = "com.vietanh.overlayiostool.image-updated";
static const char *kOverlayRemoveNotification = "com.vietanh.overlayiostool.image-remove";
static const char *kOverlaySettingsNotification = "com.vietanh.overlayiostool.settings-updated";
static const char *kOverlayStateNotification = "com.vietanh.overlayiostool.state-updated";
static const char *kOverlayDepositActionNotification = "com.vietanh.overlayiostool.action.deposit";
static const char *kOverlayWithdrawActionNotification = "com.vietanh.overlayiostool.action.withdraw";
// Toggle-click xuyên app: app chỉ phát hiện chạm (ngoài ảnh) -> báo SpringBoard.
static const char *kOverlayAppTouchNotification = "com.vietanh.overlayiostool.app-touch";
// Kênh state (notify_set_state/get_state, không dính sandbox) để app biết có cần relay.
static const char *kOverlayToggleActiveState = "com.vietanh.overlayiostool.toggle-active";
static const char *kOverlayRealtimeSocketPath = "/var/mobile/Library/OverlayIOSTOOL/realtime.sock";
static const uint32_t kOverlayRealtimeMagic = 0x4F495254;

// Hằng số font-weight CỦA TA (không phải symbol import UIKit) — tránh PAC-crash khi
// arm64e clang 11 truy cập hằng số import. Giá trị bằng đúng UIFontWeight* của Apple.
static const CGFloat kOverlayFontWeightRegular = 0.0;     // = UIFontWeightRegular
static const CGFloat kOverlayFontWeightSemibold = 0.3;    // = UIFontWeightSemibold

static BOOL gOverlayHostReady = NO;
static BOOL gToggleClickEnabled = NO;
static BOOL gOverlayVisible = YES;
static BOOL gOverlayDimmed = NO;
static BOOL gScaleLockModeEnabled = NO;
static BOOL gApplyingRemoteState = NO;
static BOOL gIsSpringBoardProcess = NO;
static BOOL gOverlayProcessEnabled = NO;
static BOOL gAppTouchRelayEnabled = NO;
static BOOL gObserversInstalled = NO;
static BOOL gQuickActionsVisible = NO;
static BOOL gScreenBlanked = NO;
static BOOL gScreenLocked = NO;
static BOOL gDataUnavailable = NO;
static BOOL gManualPinchActive = NO;        // đang nhúm 2 ngón (tự tính, không qua recognizer)
static CGFloat gManualPinchInitialDistance = 0;
static CGSize gManualPinchInitialBounds = {0, 0};
static BOOL gLongPressTracking = NO;        // đang đếm giờ giữ-lâu 1 ngón (tự tính)
static BOOL gLongPressConsumed = NO;        // đã toggle bằng lần giữ này -> chờ nhấc tay
static int gLongPressGeneration = 0;
static CGPoint gLongPressStart = {0, 0};
static BOOL gTapCandidate = NO;             // chạm 1 ngón trên ảnh, có thể là tap mở panel
static CGPoint gTapStart = {0, 0};
static BOOL gManualPanActive = NO;          // đang kéo 1 ngón di chuyển ảnh (viền xanh, tự tính)
static CGPoint gManualPanLast = {0, 0};
static NSUInteger gToggleGeneration = 0;
static NSInteger gHideDelayMs = 300;
static NSInteger gShowDelayMs = 300;
static NSInteger gDimAnimationMs = 0;
static CGFloat gDimOpacity = 1.0;
static CFTimeInterval gLastRealtimeStateSync = 0;
static int gRealtimeClientSocket = -1;
static CFSocketRef gRealtimeServerSocket = NULL;
static CFRunLoopSourceRef gRealtimeServerSource = NULL;
static __weak UIWindow *gOverlayHostWindow = nil;
static UIWindow *gOverlayWindow = nil;
@class OverlayPassthroughView;
static OverlayPassthroughView *gOverlayRoot = nil;
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
static int gAppTouchToken = 0;          // SpringBoard: nhận tín hiệu chạm từ app
static int gSbToggleStateToken = 0;     // SpringBoard: set state toggle-active
static int gAppToggleStateToken = 0;    // App: đọc state toggle-active

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

@interface OverlayPassthroughView : UIView
@end

static void refreshOverlayWindowVisibility(void);
static void updateScaleLockControlsVisibility(void);
static void updateOverlayControlValues(void);
static UIWindowScene *foregroundOverlayScene(void);

static NSString * const kOverlayLogPath = @"/var/mobile/Library/OverlayIOSTOOL/tweak.log";

// Ghi log ra file để đọc bằng Filza (chỉ SpringBoard ghi file -> nếu file KHÔNG
// tồn tại nghĩa là tweak chưa hề chạy trong SpringBoard). Mọi tiến trình vẫn NSLog.
static void overlayLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[OverlayIOSTOOL] %@", msg);

    if (!gIsSpringBoardProcess) {
        return;  // app thứ ba bị sandbox chặn ghi -> chỉ NSLog
    }

    @try {
        NSString *line = [NSString stringWithFormat:@"%.3f SB %@\n",
                          NSDate.date.timeIntervalSince1970, msg];
        [NSFileManager.defaultManager createDirectoryAtPath:kOverlayDirectory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kOverlayLogPath];
        if (!handle) {
            [line writeToFile:kOverlayLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    } @catch (__unused id exception) {
    }
}

@implementation OverlayPassthroughView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    // Trong UIView subclass, "rootView" chính là container này (self).

    if (gQuickActionsVisible) {
        return hitView ?: self;
    }

    if (gScaleLockModeEnabled) {
        if (gScaleLockControlsPanel && !gScaleLockControlsPanel.hidden && [hitView isDescendantOfView:gScaleLockControlsPanel]) {
            return hitView;
        }
        if (CGRectContainsPoint(self.bounds, point)) {
            if (!hitView || hitView == self) {
                return self;
            }
            return hitView;
        }
        if (!hitView || hitView == self) {
            return self;
        }
        return hitView;
    }

    // KHÔNG viền xanh: chỉ nhận chạm khi NGÓN nằm TRÊN ảnh (2 ngón trong ảnh -> zoom;
    // 1 ngón trong ảnh -> di chuyển / long-press / tap). Chạm NGOÀI ảnh -> xuyên xuống
    // app bên dưới (app vẫn bấm được, toggle-click chạy). Muốn zoom ở chế độ thường thì
    // cả 2 ngón phải đặt trong ảnh.
    if (gOverlayImageView && gOverlayVisible && !gOverlayImageView.hidden) {
        CGPoint imagePoint = [gOverlayImageView convertPoint:point fromView:self];
        if ([gOverlayImageView pointInside:imagePoint withEvent:event]) {
            return gOverlayImageView;
        }
    }

    if (hitView == self) {
        // Vùng trống của container -> để touch xuyên xuống app bên dưới.
        return nil;
    }
    return hitView;
}

@end

// Cửa sổ host (SpringBoard) ở windowLevel rất cao để NỔI trên mọi app + màn hình
// chính. Vùng trống trả về nil -> touch xuyên xuống app bên dưới (giống AssistiveTouch).
@interface OverlayHostWindow : UIWindow
@end

@implementation OverlayHostWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // Nếu không có view con nào nhận (chạm vào vùng trống) -> super trả về chính
    // window. Chuyển thành nil để hệ thống chuyển touch xuống app foreground.
    if (hit == self) {
        return nil;
    }
    return hit;
}

@end

@interface OverlayGestureHandler : NSObject <UIGestureRecognizerDelegate>
@end

static OverlayGestureHandler *gGestureHandler = nil;

// Heartbeat: ghi trạng thái app hiện tại vào pasteboard "báo danh" để app tool đọc.
// status: "loaded" (tweak đã vào app), "img-ok" (đọc được ảnh + đã vẽ), "no-img"
// (vào được nhưng chưa có ảnh trên pasteboard).
static void reportAppStatus(NSString *status) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleIdentifier.length) {
        return;
    }
    @try {
        UIPasteboard *board = [UIPasteboard pasteboardWithName:kOverlayActiveAppsPasteboard create:YES];
        if (!board) {
            return;
        }
        NSString *existing = board.string ?: @"";
        NSMutableArray<NSString *> *kept = [NSMutableArray array];
        for (NSString *line in [existing componentsSeparatedByString:@"\n"]) {
            if (!line.length) {
                continue;
            }
            if ([line hasPrefix:[bundleIdentifier stringByAppendingString:@" "]]) {
                continue;  // bỏ dòng cũ của chính app này
            }
            [kept addObject:line];
        }
        [kept addObject:[NSString stringWithFormat:@"%@ %@", bundleIdentifier, status]];
        while (kept.count > 40) {
            [kept removeObjectAtIndex:0];
        }
        board.string = [kept componentsJoinedByString:@"\n"];
    } @catch (__unused id exception) {
    }
}

static BOOL shouldEnableOverlayInCurrentProcess(void) {
    // KIẾN TRÚC SpringBoard: CHỈ SpringBoard render overlay trên 1 UIWindow level
    // cực cao -> nổi trên mọi app + màn hình chính (như iPhone 6/7). Cần build arm64e
    // ĐÚNG CHUẨN (bằng Xcode/macOS qua GitHub Actions) thì mới nạp vào SpringBoard
    // arm64e mà không PAC-crash.
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}

// App thứ ba đủ điều kiện chạy "relay chạm" (chỉ phát hiện chạm ngoài ảnh -> báo
// SpringBoard toggle dim). KHÔNG vẽ gì, KHÔNG đọc file -> không dính sandbox, nhẹ.
static BOOL shouldRelayAppTouches(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    NSString *executablePath = NSBundle.mainBundle.executablePath;

    if (!bundleIdentifier.length || !bundlePath.length) {
        return NO;
    }
    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        return NO;  // SpringBoard tự xử lý chạm của nó
    }
    if ([bundleIdentifier hasPrefix:@"com.vietanh.overlayiostool"]) {
        return NO;  // app tool
    }
    if ([bundlePath containsString:@".appex"] || [executablePath containsString:@"/PlugIns/"]) {
        return NO;
    }
    if (![bundlePath hasSuffix:@".app"]) {
        return NO;
    }
    return [bundlePath hasPrefix:@"/var/containers/Bundle/Application/"] ||
           [bundlePath hasPrefix:@"/private/var/containers/Bundle/Application/"] ||
           [bundlePath hasPrefix:@"/Applications/"] ||
           [bundlePath hasPrefix:@"/var/jb/Applications/"] ||
           [bundlePath hasPrefix:@"/private/var/jb/Applications/"];
}

// SpringBoard công bố: "toggle-click đang hiệu lực" (ảnh hiện + bật toggle + không
// scale-lock) qua notify state. App đọc state này để biết có cần relay chạm hay không.
static void updateToggleActiveState(void) {
    if (!gIsSpringBoardProcess) {
        return;
    }
    if (gSbToggleStateToken == 0) {
        notify_register_check(kOverlayToggleActiveState, &gSbToggleStateToken);
    }
    BOOL active = gToggleClickEnabled && gOverlayImageView && gOverlayVisible && !gScaleLockModeEnabled;
    notify_set_state(gSbToggleStateToken, active ? 1 : 0);
    notify_post(kOverlayToggleActiveState);
}

// App: đọc nhanh state toggle-active (không dính sandbox).
static BOOL overlayToggleActiveForApp(void) {
    if (gAppToggleStateToken == 0) {
        return NO;
    }
    uint64_t state = 0;
    notify_get_state(gAppToggleStateToken, &state);
    return state != 0;
}

// LƯỚI AN TOÀN CHỐNG TREO TÁO — viết bằng C THUẦN (không phụ thuộc ObjC, vốn là
// thứ CÓ THỂ lỗi nếu ABI sai). Mỗi lần SpringBoard khởi động: tăng bộ đếm crash.
// Nếu crash >= 2 lần liên tiếp -> ghi cờ disabled -> tweak TỰ TẮT ngay lần sau ->
// máy vào được màn hình chính. Nếu SpringBoard sống qua 15s -> coi như khoẻ -> xoá
// bộ đếm. Tối đa 2 lần respring, KHÔNG bao giờ treo táo vĩnh viễn.
static BOOL springBoardCrashGuardShouldDisable(void) {
    static const char *kDir = "/var/mobile/Library/OverlayIOSTOOL";
    static const char *kDisabled = "/var/mobile/Library/OverlayIOSTOOL/disabled-after-crash";
    static const char *kCount = "/var/mobile/Library/OverlayIOSTOOL/sb-crash-count";

    mkdir(kDir, 0755);  // tạo thư mục nếu chưa có (bỏ qua nếu đã có)

    if (access(kDisabled, F_OK) == 0) {
        return YES;  // đã bị tắt từ trước -> không nạp
    }

    int count = 0;
    FILE *rf = fopen(kCount, "r");
    if (rf) {
        if (fscanf(rf, "%d", &count) != 1) {
            count = 0;
        }
        fclose(rf);
    }
    count += 1;

    if (count >= 2) {
        FILE *df = fopen(kDisabled, "w");
        if (df) { fputs("1", df); fclose(df); }
        unlink(kCount);
        NSLog(@"[OverlayIOSTOOL] Disabled after %d SpringBoard launch failures", count);
        return YES;  // crash 2 lần -> tắt ngay
    }

    FILE *wf = fopen(kCount, "w");
    if (wf) { fprintf(wf, "%d", count); fclose(wf); }

    // SpringBoard sống qua 15s -> khoẻ -> xoá bộ đếm (lần boot kế tính lại từ đầu).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        unlink(kCount);
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
    imageView.backgroundColor = UIColor.clearColor;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.userInteractionEnabled = YES;
    imageView.multipleTouchEnabled = YES;   // BẮT BUỘC để pinch 2 ngón nhận đủ touch
    imageView.clipsToBounds = YES;
    imageView.layer.borderWidth = 0;
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
    // Per-app: mỗi app bật overlay đều render trong cửa sổ của chính nó.
    return gOverlayProcessEnabled;
}

static void ensureOverlayRoot(void);

static const CGFloat kOverlayWindowLevel = 100000.0;  // cao hơn status bar/alert -> nổi trên mọi app

static void refreshOverlayWindowVisibility(void) {
    updateToggleActiveState();

    if (!gOverlayRoot || !gOverlayWindow) {
        return;
    }

    // Khi khoá/tắt màn hình: chỉ ẩn cửa sổ, KHÔNG xoá ảnh/state.
    BOOL lockHidden = gScreenBlanked || gScreenLocked || gDataUnavailable;
    BOOL baseHidden = !gOverlayVisible && !gScaleLockModeEnabled;
    BOOL hidden = lockHidden || baseHidden;

    gOverlayWindow.hidden = hidden;
    gOverlayRoot.hidden = hidden;
    gOverlayRoot.userInteractionEnabled = YES;

    if (!hidden) {
        // Giữ luôn ở trên cùng (một số chuyển cảnh của SpringBoard hạ level).
        gOverlayWindow.windowLevel = kOverlayWindowLevel;
        if (gOverlayImageView) {
            [gOverlayRoot bringSubviewToFront:gOverlayImageView];
        }
        if (gScaleLockControlsPanel && !gScaleLockControlsPanel.hidden) {
            [gOverlayRoot bringSubviewToFront:gScaleLockControlsPanel];
        }
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
    button.titleLabel.font = [UIFont systemFontOfSize:22.0 weight:kOverlayFontWeightRegular];
    button.backgroundColor = [UIColor colorWithWhite:0.11 alpha:0.98];
    [button addTarget:gGestureHandler action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static void showOverlayQuickActions(void) {
    if (gScaleLockModeEnabled || gQuickActionsVisible || !gOverlayRoot) {
        overlayLog(@"showOverlayQuickActions BO QUA (scaleLock=%d visible=%d root=%d)",
                   gScaleLockModeEnabled, gQuickActionsVisible, gOverlayRoot != nil);
        return;
    }

    if (!gGestureHandler) {
        gGestureHandler = [OverlayGestureHandler new];
    }

    UIView *rootView = gOverlayRoot;
    CGRect bounds = rootView.bounds;
    CGFloat margin = 12.0;
    CGFloat hostSafeBottom = gOverlayHostWindow ? gOverlayHostWindow.safeAreaInsets.bottom : gOverlayRoot.safeAreaInsets.bottom;
    CGFloat safeBottom = MAX(hostSafeBottom, 10.0);
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

    UILabel *titleLabel = quickActionsLabel(@"Số dư", 18.0, kOverlayFontWeightSemibold);
    titleLabel.frame = CGRectMake(16.0, 17.0, panelWidth - 32.0, 26.0);
    [gQuickActionsPanel addSubview:titleLabel];

    UILabel *messageLabel = quickActionsLabel(@"Nhanh chóng di chuyển đến trang nạp/rút tiền trên trang web của broker",
                                               15.0,
                                               kOverlayFontWeightRegular);
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
    gImagePanGesture.cancelsTouchesInView = NO;   // để tap luôn kết thúc bằng Ended -> nhận panel
    gImagePanGesture.delegate = gGestureHandler;
    [imageView addGestureRecognizer:gImagePanGesture];

    // KHÔNG gắn pinch recognizer: zoom 2 ngón được xử lý TỰ TÍNH trong sendEvent
    // (overlayHandleManualPinch) vì recognizer đa chạm hay không nhận diện trên cửa sổ
    // overlay không-key.

    // KHÔNG gắn long-press recognizer: giữ-lâu để vào/thoát viền xanh được xử lý TỰ
    // TÍNH trong sendEvent (overlayHandleManualLongPress) vì recognizer cũng hay không
    // nhận diện trên cửa sổ overlay không-key.

    // KHÔNG gắn tap recognizer: tap mở panel nạp/rút được xử lý TỰ TÍNH trong sendEvent
    // (overlayHandleManualTap) cho đáng tin trên cửa sổ overlay không-key.
}

static UIWindowScene *foregroundOverlayScene(void) {
    UIWindowScene *active = nil;
    UIWindowScene *fallback = nil;
    NSUInteger windowSceneCount = 0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        windowSceneCount++;
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            active = (UIWindowScene *)scene;
            break;
        }
        if (!fallback) {
            fallback = (UIWindowScene *)scene;
        }
    }

    UIWindowScene *chosen = active ?: fallback;
    if (chosen) {
        return chosen;
    }

    // Fallback: SpringBoard có thể không liệt kê UIWindowScene trong connectedScenes
    // ở mọi thời điểm -> lấy scene từ cửa sổ đang tồn tại.
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.windowScene) {
            return window.windowScene;
        }
    }

    overlayLog(@"foregroundOverlayScene: KHONG co UIWindowScene (connected windowScenes=%lu, windows=%lu)",
               (unsigned long)windowSceneCount,
               (unsigned long)UIApplication.sharedApplication.windows.count);
    return nil;
}

static void ensureOverlayRoot(void) {
    if (gOverlayRoot || !gOverlayHostReady || !gOverlayProcessEnabled) {
        return;
    }

    // iOS 15 (kiến trúc B): SpringBoard tạo 1 UIWindow riêng đặt windowLevel cực cao
    // -> cửa sổ NỔI trên mọi app foreground và màn hình chính. KHÔNG makeKeyAndVisible
    // (chỉ hidden=NO) để không cướp first responder / bàn phím của app bên dưới.
    // Bọc @try/@catch: nếu bước nào ném exception thì KHÔNG để crash SpringBoard,
    // chỉ ghi log và bỏ qua (log cuối cùng cho biết kẹt ở đâu).
    @try {
        UIWindowScene *scene = foregroundOverlayScene();
        CGRect bounds = UIScreen.mainScreen.bounds;

        OverlayHostWindow *window = nil;
        if (scene) {
            CGRect sceneBounds = scene.coordinateSpace.bounds;
            if (!CGRectIsEmpty(sceneBounds)) {
                bounds = sceneBounds;
            }
            overlayLog(@"ensureOverlayRoot: B1 initWithWindowScene bounds=%@", NSStringFromCGRect(bounds));
            window = [[OverlayHostWindow alloc] initWithWindowScene:scene];
        } else {
            overlayLog(@"ensureOverlayRoot: B1 KHONG co scene -> initWithFrame bounds=%@", NSStringFromCGRect(bounds));
            window = [[OverlayHostWindow alloc] initWithFrame:bounds];
        }

        overlayLog(@"ensureOverlayRoot: B2 cau hinh window");
        window.frame = bounds;
        window.windowLevel = kOverlayWindowLevel;
        window.backgroundColor = UIColor.clearColor;
        window.opaque = NO;
        window.userInteractionEnabled = YES;
        window.multipleTouchEnabled = YES;

        overlayLog(@"ensureOverlayRoot: B3 tao root view");
        OverlayPassthroughView *root = [[OverlayPassthroughView alloc] initWithFrame:bounds];
        root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        root.backgroundColor = UIColor.clearColor;
        root.userInteractionEnabled = YES;
        root.multipleTouchEnabled = YES;

        overlayLog(@"ensureOverlayRoot: B4 gan rootViewController");
        UIViewController *hostController = [UIViewController new];
        hostController.view = root;
        window.rootViewController = hostController;

        overlayLog(@"ensureOverlayRoot: B5 hien window (hidden=NO)");
        window.hidden = NO;   // hiển thị mà KHÔNG làm key window

        gOverlayWindow = window;
        gOverlayHostWindow = window;
        gOverlayRoot = root;
        overlayLog(@"ensureOverlayRoot: WINDOW SAN SANG level=%.0f hidden=%d", (double)window.windowLevel, window.hidden);
    } @catch (NSException *exception) {
        overlayLog(@"ensureOverlayRoot: EXCEPTION %@ - %@", exception.name, exception.reason);
        gOverlayWindow = nil;
        gOverlayHostWindow = nil;
        gOverlayRoot = nil;
    }
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

static void updateExpandedPinchGesture(void) {
    if (!gOverlayRoot || !gGestureHandler) {
        return;
    }

    // Viền xanh KHÔNG dùng recognizer nữa (đa chạm/đơn chạm đều hay không nhận diện trên
    // cửa sổ overlay không-key): zoom 2 ngón, di chuyển 1 ngón và giữ-lâu thoát đều xử lý
    // TỰ TÍNH trong sendEvent (overlayHandleManualPinch/Pan/LongPress). Việc chặn input
    // phía sau do hitTest (trả root cho cả màn) + sendEvent (nuốt touch ngoài overlay).
    (void)gOverlayRoot;
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

static BOOL pointInsideScaleLockControls(CGPoint pointInRoot) {
    if (!gScaleLockControlsPanel || gScaleLockControlsPanel.hidden || !gOverlayRoot) {
        return NO;
    }
    CGPoint point = [gScaleLockControlsPanel convertPoint:pointInRoot fromView:gOverlayRoot];
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
    updateToggleActiveState();
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
    if (!gOverlayRoot || gScaleLockControlsPanel) {
        return;
    }

    if (!gOverlayControlTarget) {
        gOverlayControlTarget = [OverlayControlTarget new];
    }

    UIView *rootView = gOverlayRoot;
    CGRect bounds = rootView.bounds;
    CGFloat safeBottom = gOverlayHostWindow ? gOverlayHostWindow.safeAreaInsets.bottom : gOverlayRoot.safeAreaInsets.bottom;
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
        UILabel *title = overlayControlLabel(titles[index], 13.0, kOverlayFontWeightSemibold);
        title.frame = CGRectMake(14.0, y, 130.0, 20.0);
        [gScaleLockControlsPanel addSubview:title];
        [titleLabels addObject:title];

        UILabel *value = overlayControlLabel(@"", 13.0, kOverlayFontWeightRegular);
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
    gToggleClickButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:kOverlayFontWeightSemibold];
    [gToggleClickButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [gToggleClickButton addTarget:gOverlayControlTarget action:@selector(toggleClickTapped:) forControlEvents:UIControlEventTouchUpInside];
    [gScaleLockControlsPanel addSubview:gToggleClickButton];

    gHideImageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    gHideImageButton.frame = CGRectMake(14.0, panelHeight - 92.0, gScaleLockControlsPanel.bounds.size.width - 28.0, 36.0);
    gHideImageButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    gHideImageButton.backgroundColor = [UIColor colorWithRed:0.95 green:0.22 blue:0.18 alpha:0.95];
    gHideImageButton.layer.cornerRadius = 8.0;
    gHideImageButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:kOverlayFontWeightSemibold];
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

// resetFrame=YES: ảnh MỚI do người dùng vừa chọn -> bỏ vị trí/kích thước cũ, đưa
// về khung giữa màn hình, thoát viền xanh, ghi đè state.plist. resetFrame=NO: chỉ
// khôi phục ảnh đang có (foreground app / đồng bộ state) -> giữ nguyên frame đã lưu.
static void showOverlayImage(UIImage *image, BOOL resetFrame) {
    if (!image) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      @try {
        ensureOverlayRoot();
        if (!gOverlayRoot) {
            overlayLog(@"showOverlayImage: gOverlayRoot=nil (chua tao duoc window) -> KHONG hien");
            return;
        }

        BOOL doReset = resetFrame;
        if (!gOverlayImageView) {
            overlayLog(@"showOverlayImage: tao image view + gesture");
            gOverlayImageView = [[UIImageView alloc] initWithFrame:centeredFrameForImage(image)];
            configureRawImageView(gOverlayImageView);
            attachGestures(gOverlayImageView);
            [gOverlayRoot addSubview:gOverlayImageView];
            doReset = YES;  // view vừa tạo -> luôn căn giữa theo ảnh
        }
        updateExpandedPinchGesture();
        ensureScaleLockControls();

        gOverlayImageView.image = rendersOverlayImage() ? image : nil;

        if (doReset) {
            // Ảnh mới: huỷ mọi toggle dim đang chờ, thoát viền xanh, căn giữa lại
            // theo kích thước ảnh mới, rồi GHI ĐÈ state cũ. KHÔNG đọc lại state.plist
            // (nếu không sẽ dính lại frame/scale-lock của ảnh trước).
            gToggleGeneration++;
            if (gScaleLockModeEnabled) {
                applyScaleLockMode(NO);
            }
            gScaleLockModeEnabled = NO;
            gOverlayVisible = YES;
            gOverlayDimmed = NO;
            gOverlayImageView.transform = CGAffineTransformIdentity;
            gOverlayImageView.frame = centeredFrameForImage(image);
            gOverlayImageView.hidden = NO;
            gOverlayImageView.layer.borderWidth = 0;
            gOverlayImageView.layer.borderColor = nil;
            applyOverlayAlpha();
            updateScaleLockControlsVisibility();
            refreshOverlayWindowVisibility();
            persistOverlayState(YES);
            overlayLog(@"Overlay ANH MOI (reset frame) %.0fx%.0f", image.size.width, image.size.height);
        } else {
            if (CGRectIsEmpty(gOverlayImageView.frame) || gOverlayImageView.frame.size.width < 2 || gOverlayImageView.frame.size.height < 2) {
                gOverlayImageView.frame = centeredFrameForImage(image);
            }
            gOverlayImageView.hidden = NO;
            applyOverlayAlpha();
            gOverlayVisible = YES;
            applyOverlayStateFromDisk();
            refreshOverlayWindowVisibility();
            persistOverlayState(NO);
        }

        overlayLog(@"Overlay HIEN %.0fx%.0f windowHidden=%d rootHidden=%d",
                   image.size.width, image.size.height,
                   gOverlayWindow.hidden, gOverlayRoot.hidden);
      } @catch (NSException *exception) {
        overlayLog(@"showOverlayImage: EXCEPTION %@ - %@", exception.name, exception.reason);
      }
    });
}

static void loadAndShowPublishedOverlay(BOOL resetFrame) {
    UIImage *image = overlayImageFromPasteboard();
    if (!image) {
        image = overlayImageFromSharedFile();
    }

    if (!image) {
        overlayLog(@"loadAndShowPublishedOverlay: KHONG doc duoc anh (pasteboard+file %@ deu rong)", kOverlayImagePath);
        return;
    }

    overlayLog(@"loadAndShowPublishedOverlay: doc duoc anh %.0fx%.0f reset=%d", image.size.width, image.size.height, resetFrame);
    showOverlayImage(image, resetFrame);
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

        if (gScaleLockControlsPanel) {
            [gScaleLockControlsPanel removeFromSuperview];
            gScaleLockControlsPanel = nil;
        }

        if (gOverlayRoot) {
            [gOverlayRoot removeFromSuperview];
            gOverlayRoot = nil;
        }

        if (gOverlayWindow) {
            gOverlayWindow.hidden = YES;
            gOverlayWindow.rootViewController = nil;
            gOverlayWindow = nil;
        }
        gOverlayHostWindow = nil;

        gOverlayVisible = NO;
        updateToggleActiveState();
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
    updateToggleActiveState();
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

    // Reset trạng thái cử chỉ tự tính khi đổi chế độ.
    gManualPinchActive = NO;
    gManualPanActive = NO;
    gLongPressTracking = NO;
    gLongPressGeneration++;
    gTapCandidate = NO;

    if (enabled) {
        gOverlayVisible = YES;
        gOverlayDimmed = NO;
        // Toàn-màn-hình capture được đảm bảo bởi hitTest của container trả về root
        // khi gScaleLockModeEnabled -> không cần đụng tới key window.
        gOverlayRoot.userInteractionEnabled = YES;
        gOverlayRoot.hidden = NO;
        if (gOverlayHostWindow) {
            [gOverlayHostWindow bringSubviewToFront:gOverlayRoot];
        }
        gOverlayImageView.hidden = NO;
        applyOverlayAlpha();
        gOverlayImageView.layer.borderWidth = rendersOverlayImage() ? 3.0 : 0.0;
        gOverlayImageView.layer.borderColor = rendersOverlayImage() ? UIColor.systemBlueColor.CGColor : nil;
    } else {
        gOverlayImageView.layer.borderWidth = 0;
        gOverlayImageView.layer.borderColor = nil;
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

static BOOL pointInsideOverlayImage(CGPoint pointInRoot) {
    if (!gOverlayImageView || gOverlayImageView.hidden || !gOverlayVisible) {
        return NO;
    }

    CGPoint point = [gOverlayImageView convertPoint:pointInRoot fromView:gOverlayRoot];
    return [gOverlayImageView pointInside:point withEvent:nil];
}

static BOOL touchInsideOverlayImage(UITouch *touch) {
    if (!touch || !gOverlayRoot || !gOverlayImageView) {
        return NO;
    }

    CGPoint overlayPoint = [touch locationInView:gOverlayRoot];
    return pointInsideOverlayImage(overlayPoint);
}

// Zoom 2 ngón TỰ TÍNH (không qua UIPinchGestureRecognizer - vốn hay không nhận diện
// trên cửa sổ overlay không-key). Lấy đúng 2 touch đầu đang chạm, đo khoảng cách, scale
// kích thước ảnh theo tỉ lệ so với lúc bắt đầu nhúm. Viền xanh: 2 ngón ở đâu cũng được.
// Chế độ thường: chỉ zoom khi CẢ 2 ngón nằm trong ảnh.
static void overlayHandleManualPinch(UIEvent *event) {
    if (!gOverlayImageView || gOverlayImageView.hidden || !gOverlayRoot || event.type != UIEventTypeTouches) {
        gManualPinchActive = NO;
        return;
    }

    NSMutableArray<UITouch *> *active = [NSMutableArray array];
    for (UITouch *touch in event.allTouches) {
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            continue;
        }
        [active addObject:touch];
        if (active.count >= 2) {
            break;
        }
    }

    if (active.count < 2) {
        if (gManualPinchActive) {
            gManualPinchActive = NO;
            persistOverlayState(YES);   // chốt kích thước khi nhấc ngón
        }
        return;
    }

    UITouch *t0 = active[0];
    UITouch *t1 = active[1];

    CGPoint p0 = [t0 locationInView:gOverlayRoot];
    CGPoint p1 = [t1 locationInView:gOverlayRoot];
    CGFloat dx = p0.x - p1.x;
    CGFloat dy = p0.y - p1.y;
    CGFloat distance = sqrt(dx * dx + dy * dy);
    if (distance < 1.0) {
        return;
    }

    if (!gManualPinchActive) {
        // BẮT ĐẦU nhúm: chế độ thường yêu cầu CẢ 2 ngón đặt trong ảnh; viền xanh thì
        // ở đâu cũng được. Đã bắt đầu rồi thì zoom tiếp tới khi nhấc ngón (kể cả ngón
        // ra ngoài ảnh khi thu nhỏ).
        if (!gScaleLockModeEnabled && (!touchInsideOverlayImage(t0) || !touchInsideOverlayImage(t1))) {
            return;
        }
        gManualPinchActive = YES;
        gManualPinchInitialDistance = distance;
        gManualPinchInitialBounds = gOverlayImageView.bounds.size;
        return;
    }

    CGFloat ratio = distance / gManualPinchInitialDistance;
    CGFloat newW = gManualPinchInitialBounds.width * ratio;
    CGFloat newH = gManualPinchInitialBounds.height * ratio;
    CGFloat maxDimension = MAX(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height) * 20.0;
    if (newW >= 12 && newH >= 12 && newW <= maxDimension && newH <= maxDimension) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        gOverlayImageView.bounds = CGRectMake(0, 0, newW, newH);
        [CATransaction commit];
        syncOverlayStateRealtime(NO);
    }
}

// Ngón đang chạm vào bảng điều khiển (sliders/nút) của viền xanh? -> không coi là pan/giữ.
static BOOL touchOnScaleLockControls(UITouch *touch) {
    if (!touch || !gScaleLockControlsPanel || gScaleLockControlsPanel.hidden || !gOverlayRoot) {
        return NO;
    }
    CGPoint p = [touch locationInView:gOverlayRoot];
    return pointInsideScaleLockControls(p);
}

// Di chuyển ảnh bằng 1 ngón TỰ TÍNH (không qua UIPanGestureRecognizer). CHỈ ở viền xanh:
// 1 ngón ở BẤT KỲ đâu trên màn hình -> kéo ảnh theo. Bỏ qua khi chạm vào bảng điều khiển
// hoặc khi đang nhúm 2 ngón.
static void overlayHandleManualPan(UIEvent *event) {
    if (!gScaleLockModeEnabled || !gOverlayImageView || event.type != UIEventTypeTouches) {
        gManualPanActive = NO;
        return;
    }

    NSUInteger activeCount = 0;
    UITouch *single = nil;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            continue;
        }
        activeCount++;
        single = touch;
    }

    if (activeCount != 1 || gManualPinchActive || touchOnScaleLockControls(single)) {
        gManualPanActive = NO;
        return;
    }

    CGPoint p = [single locationInView:gOverlayRoot];
    if (!gManualPanActive) {
        gManualPanActive = YES;
        gManualPanLast = p;
        return;
    }

    CGFloat dx = p.x - gManualPanLast.x;
    CGFloat dy = p.y - gManualPanLast.y;
    gManualPanLast = p;
    if (dx == 0 && dy == 0) {
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gOverlayImageView.center = CGPointMake(gOverlayImageView.center.x + dx, gOverlayImageView.center.y + dy);
    [CATransaction commit];
    syncOverlayStateRealtime(NO);
}

// Giữ-lâu 1 ngón TỰ TÍNH (không qua UILongPressGestureRecognizer - cũng hay không nhận
// diện trên cửa sổ overlay không-key). Giữ 1 ngón yên ~0.6s -> bật/tắt viền xanh.
// Viền xanh: giữ ở ĐÂU cũng thoát. Chế độ thường: phải giữ TRÊN ảnh mới vào viền xanh.
static void overlayHandleManualLongPress(UIEvent *event) {
    if (!gOverlayImageView || event.type != UIEventTypeTouches) {
        return;
    }

    NSUInteger activeCount = 0;
    UITouch *single = nil;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            continue;
        }
        activeCount++;
        single = touch;
    }

    // 0 hoặc >=2 ngón -> không phải giữ-lâu 1 ngón. Nhấc hết tay thì cho phép lần giữ mới.
    if (activeCount != 1) {
        gLongPressTracking = NO;
        gLongPressGeneration++;
        if (activeCount == 0) {
            gLongPressConsumed = NO;
        }
        return;
    }

    if (gLongPressConsumed) {
        return;   // đã toggle bằng lần giữ này -> chờ nhấc tay rồi mới nhận lần mới
    }

    // Chạm vào bảng điều khiển viền xanh -> không tính giữ-lâu (để chỉnh slider yên).
    if (touchOnScaleLockControls(single)) {
        gLongPressTracking = NO;
        gLongPressGeneration++;
        return;
    }

    CGPoint p = [single locationInView:gOverlayRoot];

    // Chế độ thường: chỉ nhận giữ-lâu khi ngón TRÊN ảnh (để vào viền xanh).
    if (!gScaleLockModeEnabled && !touchInsideOverlayImage(single)) {
        gLongPressTracking = NO;
        gLongPressGeneration++;
        return;
    }

    if (!gLongPressTracking) {
        gLongPressTracking = YES;
        gLongPressStart = p;
        int gen = ++gLongPressGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gen != gLongPressGeneration || !gLongPressTracking) {
                return;
            }
            gLongPressTracking = NO;
            gLongPressConsumed = YES;
            applyScaleLockMode(!gScaleLockModeEnabled);
        });
        return;
    }

    // Đang đếm giờ: di chuyển quá xa -> huỷ (coi như kéo, không phải giữ-lâu).
    CGFloat dx = p.x - gLongPressStart.x;
    CGFloat dy = p.y - gLongPressStart.y;
    if (dx * dx + dy * dy > 28.0 * 28.0) {
        gLongPressTracking = NO;
        gLongPressGeneration++;
    }
}

// Tap 1 ngón TRÊN ẢNH (tự tính, không qua recognizer) -> hiện panel nạp/rút. KHÔNG làm
// mờ ảnh (dim chỉ xảy ra khi chạm NGOÀI ảnh). Chỉ chạy ở chế độ thường (không viền xanh).
static void overlayHandleManualTap(UIEvent *event) {
    if (gScaleLockModeEnabled || !gOverlayImageView || event.type != UIEventTypeTouches) {
        gTapCandidate = NO;
        return;
    }

    // Nhúm 2 ngón -> không phải tap.
    if (event.allTouches.count >= 2) {
        gTapCandidate = NO;
        return;
    }

    NSUInteger activeCount = 0;
    BOOL anyEnded = NO;
    UITouch *activeTouch = nil;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            anyEnded = YES;
            continue;
        }
        activeCount++;
        activeTouch = touch;
    }

    if (activeTouch) {
        if (activeTouch.phase == UITouchPhaseBegan) {
            // Bắt đầu 1 ngón: chỉ là ứng viên tap nếu đặt TRÊN ảnh.
            gTapCandidate = touchInsideOverlayImage(activeTouch);
            gTapStart = [activeTouch locationInView:gOverlayRoot];
        } else if (gTapCandidate) {
            CGPoint p = [activeTouch locationInView:gOverlayRoot];
            CGFloat dx = p.x - gTapStart.x;
            CGFloat dy = p.y - gTapStart.y;
            if (dx * dx + dy * dy > 24.0 * 24.0) {
                gTapCandidate = NO;   // đã kéo -> không phải tap
            }
        }
        return;
    }

    // Đã nhấc hết tay (Ended HOẶC Cancelled - pan recognizer có thể đổi phase thành
    // Cancelled). Vẫn là tap hợp lệ (chạm trên ảnh, không kéo/giữ-lâu/nhúm) -> hiện panel.
    if (anyEnded && activeCount == 0) {
        BOOL fire = gTapCandidate && !gLongPressConsumed && !gManualPinchActive;
        gTapCandidate = NO;
        if (fire) {
            overlayLog(@"manual tap tren anh -> hien panel nap/rut");
            showOverlayQuickActions();
        }
    }
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
        overlayLog(@"Nhan notification 'image-updated' -> tai & hien anh (reset frame)");
        loadAndShowPublishedOverlay(YES);
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

        // App thứ ba báo "có chạm ngoài ảnh" -> toggle dim ảnh (toggle-click xuyên app).
        notify_register_dispatch(kOverlayAppTouchNotification, &gAppTouchToken, dispatch_get_main_queue(), ^(__unused int token) {
            scheduleToggleOverlayVisibility();
        });

        // Công bố state ban đầu cho các app đọc.
        updateToggleActiveState();
    }

    notify_register_dispatch(kOverlayStateNotification, &gStateToken, dispatch_get_main_queue(), ^(__unused int token) {
        if (!gOverlayImageView) {
            loadAndShowPublishedOverlay(NO);
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
    }

    // Báo danh: app này đã có tweak chạy.
    reportAppStatus(@"loaded");

    // PER-APP: khi app foreground, tự đọc ảnh từ pasteboard và hiện trong app này.
    if (gOverlayImageView) {
        refreshOverlayWindowVisibility();
        reportAppStatus(@"img-ok");
        return;
    }

    UIImage *image = overlayImageFromPasteboard();
    if (!image) {
        image = overlayImageFromSharedFile();  // fallback (chỉ chạy được nơi đọc được file)
    }
    if (image) {
        showOverlayImage(image, NO);
        reportAppStatus(@"img-ok");
    } else {
        reportAppStatus(@"no-img");
    }
}

// Thử hiện lại liên tục tới ~24s sau khi tweak nạp: app có thể vừa mở (scene chưa
// sẵn sàng), hoặc bạn bấm "Hiển thị" muộn -> cứ thử lại cho tới khi ảnh hiện.
// LƯU Ý: chỉ chạy được nếu dylib ĐÃ được ElleKit nạp vào app lúc app khởi động;
// không thể "tự nạp" nếu chưa được inject.
static void scheduleActivationRetry(int attempt) {
    if (attempt >= 12 || gOverlayImageView) {
        return;
    }
    double delaySeconds = (attempt == 0) ? 1.0 : 2.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        activateOverlayHost();
        if (!gOverlayImageView) {
            scheduleActivationRetry(attempt + 1);
        }
    });
}

@implementation OverlayGestureHandler

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    if (!view || gScaleLockModeEnabled) {
        return;
    }
    if (gManualPinchActive) {   // đang nhúm 2 ngón -> không cho 1 ngón kéo trôi ảnh
        [gesture setTranslation:CGPointZero inView:view.superview];
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

- (void)handleRelativePan:(UIPanGestureRecognizer *)gesture {
    if (!gScaleLockModeEnabled || !gOverlayImageView || gManualPinchActive) {
        [gesture setTranslation:CGPointZero inView:gOverlayRoot];
        return;
    }

    UIView *rootView = gOverlayRoot;
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

    if (gScaleLockModeEnabled && gOverlayRoot) {
        CGPoint point = [touch locationInView:gOverlayRoot];
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
        // App relay: cú chạm lọt tới app = chạm NGOÀI ảnh (vùng ảnh bị cửa sổ
        // SpringBoard nuốt). Nếu toggle-click đang hiệu lực -> báo SpringBoard dim.
        if (gAppTouchRelayEnabled && event.type == UIEventTypeTouches) {
            for (UITouch *touch in event.allTouches) {
                if (touch.phase == UITouchPhaseBegan) {
                    if (overlayToggleActiveForApp()) {
                        notify_post(kOverlayAppTouchNotification);
                    }
                    break;
                }
            }
        }
        return;
    }

    BOOL quickActionsWereVisible = gQuickActionsVisible;

    if (event.type == UIEventTypeTouches && gScaleLockModeEnabled && gOverlayImageView) {
        BOOL overlayTouch = NO;
        for (UITouch *touch in event.allTouches) {
            if (gOverlayRoot && (touch.view == gOverlayRoot || [touch.view isDescendantOfView:gOverlayRoot])) {
                overlayTouch = YES;
                break;
            }
        }

        if (!overlayTouch) {
            return;
        }

        %orig(event);
        overlayHandleManualPinch(event);       // viền xanh: 2 ngón ở đâu cũng zoom
        overlayHandleManualPan(event);         // viền xanh: 1 ngón ở đâu cũng di chuyển ảnh
        overlayHandleManualLongPress(event);   // viền xanh: giữ-lâu 1 ngón -> thoát
        return;
    }

    %orig(event);

    if (quickActionsWereVisible || gQuickActionsVisible) {
        return;
    }

    handleHiddenImageDoubleTapIfNeeded(event);

    // Chế độ thường: 2 ngón TRONG ảnh -> zoom; giữ-lâu 1 ngón trên ảnh -> vào viền xanh;
    // tap 1 ngón trên ảnh -> hiện panel nạp/rút (KHÔNG làm mờ ảnh).
    overlayHandleManualPinch(event);
    overlayHandleManualLongPress(event);
    overlayHandleManualTap(event);

    if (gScaleLockModeEnabled || !gToggleClickEnabled || !gOverlayImageView || event.type != UIEventTypeTouches) {
        return;
    }

    // Cử chỉ 2 ngón = zoom -> KHÔNG coi là "chạm ngoài ảnh" để tránh toggle dim nhầm.
    if (event.allTouches.count >= 2) {
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
        if (gIsSpringBoardProcess) {
            overlayLog(@"[ctor] dylib DA NAP vao SpringBoard (bat dau)");
        }
        if (gIsSpringBoardProcess && springBoardCrashGuardShouldDisable()) {
            overlayLog(@"[ctor] CRASH-GUARD chan! (co file disabled-after-crash hoac SpringBoard vua crash lien tuc) -> tweak TU TAT trong SpringBoard");
            return;
        }
        gOverlayProcessEnabled = shouldEnableOverlayInCurrentProcess();
        gAppTouchRelayEnabled = !gOverlayProcessEnabled && shouldRelayAppTouches();
        if (!gOverlayProcessEnabled && !gAppTouchRelayEnabled) {
            return;
        }

        %init(OverlayUIApplicationHooks);

        // App relay: chỉ cần hook sendEvent + token đọc state. KHÔNG vẽ, KHÔNG đọc file.
        if (gAppTouchRelayEnabled) {
            notify_register_check(kOverlayToggleActiveState, &gAppToggleStateToken);
            NSLog(@"[OverlayIOSTOOL] App touch relay in %@", bundleIdentifier ?: NSProcessInfo.processInfo.processName);
            return;
        }

        overlayLog(@"[ctor] host khoi tao xong, cho DidBecomeActive + retry");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gObserversInstalled) {
                return;
            }
            gObserversInstalled = YES;

            // BÁO DANH NGAY khi dylib nạp (không chờ app active) -> app tool thấy
            // ngay "loaded" để biết tweak ĐÃ vào app này.
            reportAppStatus(@"loaded");

            // DÙNG CHUỖI LITERAL thay cho hằng số import của UIKit. Crash log cho thấy
            // PAC-crash xảy ra đúng tại `[name copy]` trên hằng số NSString import
            // (UIApplicationDidBecomeActiveNotification...). Giá trị của các hằng này
            // BẰNG đúng tên symbol -> dùng @"..." là chuỗi của TA, không import -> né
            // hẳn điểm crash (lớp phòng thủ kèm với clang 13).
            [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidBecomeActiveNotification"
                                                              object:nil
                                                               queue:NSOperationQueue.mainQueue
                                                          usingBlock:^(__unused NSNotification *notification) {
                activateOverlayHost();
            }];
            if (gIsSpringBoardProcess) {
                [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationProtectedDataWillBecomeUnavailable"
                                                                  object:nil
                                                                   queue:NSOperationQueue.mainQueue
                                                              usingBlock:^(__unused NSNotification *notification) {
                    gDataUnavailable = YES;          // khoá máy -> chỉ ẩn, giữ ảnh
                    refreshOverlayWindowVisibility();
                }];
                [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationProtectedDataDidBecomeAvailable"
                                                                  object:nil
                                                                   queue:NSOperationQueue.mainQueue
                                                              usingBlock:^(__unused NSNotification *notification) {
                    gDataUnavailable = NO;           // mở khoá -> hiện lại
                    refreshOverlayWindowVisibility();
                }];
            }
        });

        // KÍCH HOẠT DỰ PHÒNG + thử lại tới ~24s: app có thể đã ACTIVE trước khi
        // observer kịp thêm, hoặc ảnh được đăng muộn -> thử lại liên tục cho chắc.
        scheduleActivationRetry(0);
    }
}
