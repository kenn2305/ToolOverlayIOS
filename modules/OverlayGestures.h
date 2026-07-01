static BOOL pointInsideImageView(UIImageView *v, CGPoint pointInRoot) {
    if (!v || v.hidden || !gOverlayRoot) {
        return NO;
    }
    CGPoint point = [v convertPoint:pointInRoot fromView:gOverlayRoot];
    return [v pointInside:point withEvent:nil];
}

// Chạm có trên ẢNH ĐANG HIỆN RÕ không (chế độ thường). Ảnh đang MỜ/ẩn -> coi như không
// có -> mọi sự kiện (panel, giữ-lâu) ở vùng đó bị vô hiệu, chạm lọt xuống app.
static BOOL pointInsideOverlayImage(CGPoint pointInRoot) {
    if (!gOverlayVisible || gOverlayDimmed) {
        return NO;
    }
    return pointInsideImageView(activeImageView(), pointInRoot);
}

// Chạm có trên ảnh không: viền xanh xét CẢ 2 ảnh; thường xét ảnh đang hiện.
static BOOL touchInsideOverlayImage(UITouch *touch) {
    if (!touch || !gOverlayRoot) {
        return NO;
    }
    CGPoint p = [touch locationInView:gOverlayRoot];
    if (gScaleLockModeEnabled) {
        return pointInsideImageView(gOverlayImageView, p) || pointInsideImageView(gOverlayImageView2, p);
    }
    return pointInsideOverlayImage(p);
}

// CHẾ ĐỘ THƯỜNG - quyết định 1 cú chạm (toạ độ root), kích hoạt khi THẢ TAY:
//  trúng hitbox HIỆN của ảnh N -> HIỆN ảnh N (ảnh kia ẩn hẳn); trúng hitbox MỜ của ảnh N
//  -> CHỈ mờ ảnh N nếu N đang hiện (không đổi/hiện ảnh kia); trúng ẢNH đang hiện -> panel.
static void overlayTriggerAtPoint(CGPoint p) {
    if (gScaleLockModeEnabled || !gOverlayImageView) {
        return;
    }
    p = overlayNormalizePoint(p);   // pixel (màn hình chính) -> điểm; relay (điểm) giữ nguyên

    // XÉT TẤT CẢ hitbox phủ lên điểm chạm (không chỉ cái trên cùng) -> ƯU TIÊN HIỆN.
    // Nếu vùng chồng có cả "Hiện ảnh A" lẫn "Mờ ảnh B" thì HIỆN A thắng (A hiện, B tự ẩn)
    // -> 1 lần bấm là xong, không còn no-op gây phải bấm 2-3 lần. Chỉ khi KHÔNG có "Hiện"
    // nào mới xét "Mờ" (ẩn ảnh đang hiện).
    NSInteger showImg = -1;   // ảnh cần HIỆN (ưu tiên cao nhất)
    BOOL hasHide = NO;        // có trúng hitbox MỜ (chỉ dùng khi không có Hiện)
    BOOL hitAny = NO;
    for (NSInteger i = (NSInteger)gHitboxes.count - 1; i >= 0; i--) {
        if (!CGRectContainsPoint(hitboxRectAt(i), p)) {
            continue;
        }
        if ([gHitboxes[i][@"type"] integerValue] == 0) {   // Hiện
            NSInteger img = hitboxImageAt(i);
            if (img == 1 && !hasSecondImage()) {
                continue;   // hitbox HIỆN ảnh 2 nhưng chưa có ảnh 2 -> bỏ qua
            }
            hitAny = YES;
            if (showImg < 0) showImg = img;
        } else {                                           // Mờ
            hitAny = YES;
            hasHide = YES;
        }
    }
    if (showImg >= 0) {
        scheduleShowImage(showImg, NO);   // HIỆN: hiện ảnh N, ẩn hẳn ảnh kia
        return;
    }
    if (hasHide) {
        scheduleHideImage();              // MỜ: ẩn ảnh ĐANG HIỆN (không đụng ảnh kia)
        return;
    }
    if (hitAny) {
        return;   // có trúng hitbox (nhưng đã xử lý) -> không mở panel
    }
    // Panel nạp/rút CHỈ mở khi ảnh đang HIỆN RÕ. Ảnh đang mờ/ẩn -> vùng đó vô hiệu.
    UIImageView *active = activeImageView();
    if (active && gOverlayVisible && !gOverlayDimmed) {
        CGRect zone = CGRectInset(active.frame, -28.0, -28.0);
        if (pointInsideOverlayImage(p) || CGRectContainsPoint(zone, p)) {
            showOverlayQuickActions();
        }
    }
}

// Zoom 2 ngón TỰ TÍNH (không qua UIPinchGestureRecognizer - vốn hay không nhận diện
// trên cửa sổ overlay không-key). Lấy đúng 2 touch đầu đang chạm, đo khoảng cách, scale
// kích thước ảnh theo tỉ lệ so với lúc bắt đầu nhúm. Viền xanh: 2 ngón ở đâu cũng được.
// Chế độ thường: chỉ zoom khi CẢ 2 ngón nằm trong ảnh.
static void __attribute__((unused)) overlayHandleManualPinch(UIEvent *event) {
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

// Ngón đang chạm vào UI chỉnh sửa (sliders/toolbar) của viền xanh? -> không coi là pan/giữ.
static BOOL touchOnScaleLockControls(UITouch *touch) {
    if (!touch || !gScaleLockModeEnabled || !gOverlayRoot) {
        return NO;
    }
    CGPoint p = [touch locationInView:gOverlayRoot];
    return pointOnHitboxEditUI(p);
}

// Di chuyển phần tử ĐANG CHỌN (ảnh hoặc hitbox) bằng 1 ngón TỰ TÍNH. CHỈ ở viền xanh.
// Bỏ qua khi chạm UI chỉnh sửa hoặc khi đang nhúm.
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
    CGRect f = selectedElementFrame();
    f.origin.x += dx;
    f.origin.y += dy;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    setSelectedElementFrame(f);
    [CATransaction commit];
    if (gSelectedIndex < 0) {
        syncOverlayStateRealtime(NO);
    } else {
        saveHitboxes();
    }
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

    // Vào/THOÁT viền xanh đều bằng giữ-lâu TRÊN ẢNH (không phải hitbox/nền/đối tượng đang
    // chọn). Khi đang ở viền xanh còn phải KHÔNG trùng hitbox để không lẫn với chọn hitbox.
    BOOL onImage = touchInsideOverlayImage(single);
    if (!onImage || (gScaleLockModeEnabled && hitboxIndexAtPointForImage(p, gEditingImageIndex) >= 0)) {
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

// Viền xanh: CHẠM XUỐNG (Began) để CHỌN phần tử. Trúng hitbox -> chọn hitbox đó; trúng
// ảnh -> chọn ảnh; nền trống -> giữ nguyên lựa chọn (để kéo nền vẫn dời cái đang chọn).
// Chạy TRƯỚC pan để cú kéo dời đúng phần tử vừa chọn.
static void overlayHandleScaleLockSelect(UIEvent *event) {
    if (!gScaleLockModeEnabled || !gOverlayImageView || event.type != UIEventTypeTouches) {
        return;
    }
    NSUInteger activeCount = 0;
    UITouch *began = nil;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            continue;
        }
        activeCount++;
        if (touch.phase == UITouchPhaseBegan) began = touch;
    }
    if (activeCount != 1 || !began || touchOnScaleLockControls(began)) {
        return;
    }
    CGPoint p = [began locationInView:gOverlayRoot];
    // Ưu tiên hitbox của ảnh ĐANG FOCUS (chỉ hitbox đó mới hiện). Nếu trúng ẢNH 2 (đang
    // focus ảnh 1) hoặc ngược lại -> CHUYỂN FOCUS sang ảnh được chạm + chọn chính ảnh đó.
    NSInteger idx = hitboxIndexAtPointForImage(p, gEditingImageIndex);
    if (idx >= 0) {
        gSelectedIndex = idx;
    } else if (pointInsideImageView(editingImageView(), p)) {
        gSelectedIndex = -1;                       // chạm ảnh đang focus -> chọn ảnh đó
    } else {
        // Chạm ảnh KHÁC -> đổi focus sang nó.
        NSInteger other = gEditingImageIndex == 0 ? 1 : 0;
        if (pointInsideImageView(imageViewAtIndex(other), p)) {
            setEditingImageIndex(other);
            return;
        }
        return;   // nền trống -> giữ nguyên
    }
    updateHitboxSelectionHighlight();
    updateHitboxEditUIForSelection();
}

// Tap 1 ngón TỰ TÍNH (không qua recognizer), chế độ thường. GỘP 1 chỗ để panel & dim
// không mâu thuẫn: tap TRÊN ảnh -> panel nạp/rút (KHÔNG dim, kể cả toggle bật); tap
// NGOÀI ảnh -> dim (chỉ khi toggle bật). Quyết định lúc NHẢ tay (Ended/Cancelled).
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
            CGPoint p = overlayNormalizePoint([activeTouch locationInView:gOverlayRoot]);
            gTapCandidate = YES;
            gTapStart = p;
            // Trên ảnh = trong frame ẢNH ĐANG HIỆN + dung sai 28pt (ảnh nhỏ dễ bấm trượt).
            UIImageView *active = activeImageView();
            CGRect activeFrame = active ? active.frame : CGRectZero;
            CGRect zone = CGRectInset(activeFrame, -28.0, -28.0);
            gTapOnImage = pointInsideOverlayImage(p) || CGRectContainsPoint(zone, p);
            overlayLog(@"SB tap Began (%.0f,%.0f) onImage=%d frame=%@ toggle=%d",
                       p.x, p.y, gTapOnImage, NSStringFromCGRect(activeFrame), gToggleClickEnabled);
        } else if (gTapCandidate) {
            CGPoint p = overlayNormalizePoint([activeTouch locationInView:gOverlayRoot]);
            CGFloat dx = p.x - gTapStart.x;
            CGFloat dy = p.y - gTapStart.y;
            if (dx * dx + dy * dy > 24.0 * 24.0) {
                gTapCandidate = NO;   // đã kéo -> không phải tap
            }
        }
        return;
    }

    // Nhấc hết tay. Tap hợp lệ (không kéo/giữ-lâu/nhúm) -> trigger theo hitbox/ảnh.
    if (anyEnded && activeCount == 0) {
        BOOL validTap = gTapCandidate && !gLongPressConsumed && !gManualPinchActive;
        CGPoint tapPoint = gTapStart;
        gTapCandidate = NO;
        if (validTap) {
            overlayTriggerAtPoint(tapPoint);
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

    notify_register_dispatch(kOverlayUpdated2Notification, &gNotify2Token, dispatch_get_main_queue(), ^(__unused int token) {
        overlayLog(@"Nhan notification 'image2-updated' -> tai & hien anh 2 (reset frame)");
        loadAndShowPublishedOverlay2(YES);
    });

    notify_register_dispatch(kOverlayRemove2Notification, &gRemove2Token, dispatch_get_main_queue(), ^(__unused int token) {
        NSLog(@"[OverlayIOSTOOL] Remove image 2 notification received");
        removeImage2();
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

        // App thứ ba báo "có chạm" kèm toạ độ. SpringBoard biết vị trí ảnh + hitbox nên tự
        // quyết: trúng hitbox -> mờ/rõ theo loại; trúng ảnh -> panel nạp/rút; còn lại -> 0.
        notify_register_check(kOverlayAppTouchLocState, &gAppTouchLocToken);
        notify_register_dispatch(kOverlayAppTouchNotification, &gAppTouchToken, dispatch_get_main_queue(), ^(__unused int token) {
            uint64_t packed = 0;
            if (gAppTouchLocToken != 0) {
                notify_get_state(gAppTouchLocToken, &packed);
            }
            CGPoint p = CGPointMake((double)(uint32_t)(packed >> 32),
                                    (double)(uint32_t)(packed & 0xFFFFFFFFu));
            overlayLog(@"app-touch (%.0f,%.0f)", p.x, p.y);
            overlayTriggerAtPoint(p);
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
        if (!gOverlayImageView2) {
            loadAndShowPublishedOverlay2(NO);   // khôi phục ảnh 2 nếu có
        }
        reportAppStatus(@"img-ok");
        return;
    }

    UIImage *image = overlayImageFromPasteboard();
    if (!image) {
        image = overlayImageFromSharedFile();  // fallback (chỉ chạy được nơi đọc được file)
    }
    if (image) {
        showOverlayImage(image, NO);
        if (!gOverlayImageView2) {
            loadAndShowPublishedOverlay2(NO);   // khôi phục ảnh 2 nếu có
        }
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
    if (gestureRecognizer == gImagePanGesture || gestureRecognizer == gImagePanGesture2 || gestureRecognizer == gImagePinchGesture) {
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

