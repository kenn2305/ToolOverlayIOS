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
        if (gOverlayImageView2) {
            [gOverlayRoot bringSubviewToFront:gOverlayImageView2];
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

static void attachGestures(UIImageView *imageView, NSInteger index) {
    if (!gGestureHandler) {
        gGestureHandler = [OverlayGestureHandler new];
    }

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gGestureHandler action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.cancelsTouchesInView = NO;   // để tap luôn kết thúc bằng Ended -> nhận panel
    pan.delegate = gGestureHandler;
    [imageView addGestureRecognizer:pan];
    if (index == 1) {
        gImagePanGesture2 = pan;
    } else {
        gImagePanGesture = pan;
    }

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

