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
    if (gOverlayImageView2) {
        CGRect frame2 = frameFromOverlayStateKey(state, @"frame2");
        if (!CGRectIsNull(frame2)) {
            gOverlayImageView2.frame = frame2;
        }
    }

    if (state[@"overlayVisible"]) {
        gOverlayVisible = [state[@"overlayVisible"] boolValue];
    }

    if (state[@"overlayDimmed"]) {
        gOverlayDimmed = [state[@"overlayDimmed"] boolValue];
    }

    if (state[@"activeImageIndex"]) {
        NSInteger idx = [state[@"activeImageIndex"] integerValue];
        gActiveImageIndex = (idx == 1 && gOverlayImageView2) ? 1 : 0;
    }

    if (state[@"dimOpacity"]) {
        gDimOpacity = MAX(0.0, MIN([state[@"dimOpacity"] doubleValue], 1.0));
    }

    if (state[@"dimAnimationMs"]) {
        gDimAnimationMs = MAX(0, MIN([state[@"dimAnimationMs"] integerValue], 10000));
    }

    if (state[@"scaleLockModeEnabled"]) {
        BOOL want = [state[@"scaleLockModeEnabled"] boolValue];
        if (want != gScaleLockModeEnabled) {   // chỉ gọi khi THỰC SỰ đổi -> tránh tác dụng phụ
            applyScaleLockMode(want);
        }
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

