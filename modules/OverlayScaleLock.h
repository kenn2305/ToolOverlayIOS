static void applyScaleLockMode(BOOL enabled) {
    if (!gOverlayImageView) {
        gScaleLockModeEnabled = NO;
        return;
    }

    if (enabled && gQuickActionsVisible) {
        dismissOverlayQuickActions();
    }

    BOOL wasEnabled = gScaleLockModeEnabled;   // để biết có PHẢI vừa thoát viền xanh không
    gScaleLockModeEnabled = enabled;
    gToggleGeneration++;

    gImagePanGesture.enabled = !enabled;
    gImagePanGesture2.enabled = !enabled;

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
        // Vào viền xanh: CẢ 2 ẢNH hiện rõ; mặc định focus ảnh đang hiện (hoặc ảnh 1).
        gEditingImageIndex = (gActiveImageIndex == 1 && hasSecondImage()) ? 1 : 0;
        applyActiveImageDisplay();         // gScaleLockModeEnabled -> hiện cả 2 ảnh
        gSelectedIndex = -1;               // mặc định chọn ẢNH đang focus
        ensureHitboxEditUI();
        rebuildHitboxViews();              // hiện hitbox của ảnh focus
        setHitboxEditUIHidden(NO);
        updateHitboxEditUIForSelection();
        updateHitboxSelectionHighlight();
    } else {
        // CHỈ khi vừa THỰC SỰ thoát viền xanh (wasEnabled) mới đặt ảnh focus thành ảnh
        // hiện (rõ). applyScaleLockMode(NO) còn bị gọi từ ĐỒNG BỘ STATE (mỗi lần đổi ảnh/
        // mờ bằng hitbox) — KHÔNG được reset active/dim ở đó, nếu không lệnh hitbox vừa
        // chạy sẽ bị HOÀN TÁC ngay (đúng triệu chứng "không mất, không mờ").
        if (wasEnabled) {
            gActiveImageIndex = (gEditingImageIndex == 1 && hasSecondImage()) ? 1 : 0;
            gOverlayDimmed = NO;
        }
        if (gOverlayImageView) {
            gOverlayImageView.layer.borderWidth = 0;
            gOverlayImageView.layer.borderColor = nil;
        }
        if (gOverlayImageView2) {
            gOverlayImageView2.layer.borderWidth = 0;
            gOverlayImageView2.layer.borderColor = nil;
        }
        setHitboxViewsHidden(YES);         // thoát: hitbox tàng hình
        setHitboxEditUIHidden(YES);
        applyActiveImageDisplay();         // thoát: chỉ ảnh đang focus còn hiện
    }

    refreshOverlayWindowVisibility();
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

// Đặt mờ/rõ theo HƯỚNG (không toggle) với delay tương ứng. (Đường cũ 1 ảnh - giữ lại.)
static void __attribute__((unused)) scheduleSetOverlayDimmed(BOOL dimmed) {
    if (!gOverlayImageView || gOverlayDimmed == dimmed) {
        return;
    }
    NSInteger delayMs = dimmed ? gHideDelayMs : gShowDelayMs;
    overlayLog(@"scheduleSetOverlayDimmed dimmed=%d delay=%ldms opacity=%.2f", dimmed, (long)delayMs, gDimOpacity);
    NSUInteger generation = ++gToggleGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayMs * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        if (generation != gToggleGeneration) {
            return;
        }
        applyOverlayDimmed(dimmed);
    });
}

// Đọc TƯƠI Delay ẩn/hiện từ settings.plist ngay trước khi lên lịch. Không phụ thuộc
// notify (nếu notify tới trễ/lệch nhịp thì gShow/HideDelayMs có thể còn cũ = 0) -> luôn
// dùng đúng giá trị người dùng vừa chỉnh trong app. File rất nhỏ nên đọc mỗi lần bấm OK.
static void overlayRefreshDelaysFromDisk(void) {
    NSDictionary *s = [NSDictionary dictionaryWithContentsOfFile:kOverlaySettingsPath];
    if (![s isKindOfClass:NSDictionary.class]) {
        return;
    }
    if (s[@"hideDelayMs"]) gHideDelayMs = MAX(0, MIN([s[@"hideDelayMs"] integerValue], 10000));
    if (s[@"showDelayMs"]) gShowDelayMs = MAX(0, MIN([s[@"showDelayMs"] integerValue], 10000));
    // Delay hiện ảnh 2 riêng; nếu chưa có key thì theo delay hiện ảnh 1 (tương thích ngược).
    if (s[@"showDelayMs2"]) gShowDelayMs2 = MAX(0, MIN([s[@"showDelayMs2"] integerValue], 10000));
    else gShowDelayMs2 = gShowDelayMs;
}

// ĐA-ẢNH: áp dụng (sau delay) việc HIỆN/MỜ 1 ảnh. Ảnh này thành ảnh đang hiện
// (gActiveImageIndex) -> ảnh kia tự ẩn hẳn (loại trừ lẫn nhau). dimmed=YES: ảnh này mờ
// về độ mờ dùng chung. TỨC THÌ, không animation.
static void applyActiveImage(NSInteger index, BOOL dimmed) {
    if (gScaleLockModeEnabled || index < 0 || index > 1 || !imageViewAtIndex(index)) {
        overlayLog(@"applyActiveImage BO QUA idx=%ld dimmed=%d scaleLock=%d hasView=%d",
                   (long)index, dimmed, gScaleLockModeEnabled, imageViewAtIndex(index) != nil);
        return;
    }
    gActiveImageIndex = index;
    gOverlayDimmed = dimmed;
    applyActiveImageDisplay();
    refreshOverlayWindowVisibility();
    // KHÔNG broadcast: không process nào khác nghe state-notification (app chỉ relay).
    // Broadcast sẽ tự bắn lại -> applyOverlayStateFromDisk -> applyScaleLockMode(NO) ->
    // hoàn tác đúng lệnh vừa chạy. Ghi đĩa (NO) là đủ để bền qua respring.
    persistOverlayState(NO);
    UIImageView *v1 = gOverlayImageView2;
    overlayLog(@"applyActiveImage OK active=%ld dim=%d vis=%d | img0 hidden=%d alpha=%.2f | img1 %@",
               (long)gActiveImageIndex, gOverlayDimmed, gOverlayVisible,
               gOverlayImageView.hidden, gOverlayImageView.alpha,
               v1 ? [NSString stringWithFormat:@"hidden=%d alpha=%.2f", v1.hidden, v1.alpha] : @"nil");
}

// Lên lịch HIỆN ảnh index sau delay (Hiện -> delay hiện, Mờ -> delay ẩn). Kích hoạt khi
// THẢ TAY (gọi từ overlayTriggerAtPoint). Bỏ qua nếu trạng thái không đổi.
static void scheduleShowImage(NSInteger index, BOOL dimmed) {
    if (index < 0 || index > 1 || !imageViewAtIndex(index)) {
        return;
    }
    if (gActiveImageIndex == index && gOverlayDimmed == dimmed && !imageViewAtIndex(index).hidden) {
        return;   // đang đúng trạng thái rồi -> khỏi làm
    }
    overlayRefreshDelaysFromDisk();
    // HIỆN: ảnh 2 dùng delay riêng (gShowDelayMs2) để canh thời gian load tab khác nhau.
    NSInteger delayMs = dimmed ? gHideDelayMs : (index == 1 ? gShowDelayMs2 : gShowDelayMs);
    overlayLog(@"scheduleShowImage idx=%ld dimmed=%d delay=%ldms", (long)index, dimmed, (long)delayMs);
    NSUInteger generation = ++gToggleGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayMs * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        if (generation != gToggleGeneration) {
            return;
        }
        applyActiveImage(index, dimmed);
    });
}

// ẨN/MỜ: hitbox Mờ -> mờ ẢNH ĐANG HIỆN (bất kể hitbox thuộc ảnh nào), KHÔNG hiện ảnh
// kia. "Chỉ ẩn ảnh hiện tại" -> tap vùng Mờ ở đâu cũng ẩn cái đang hiện -> LUÔN ăn, không
// còn no-op kiểu "ẩn ảnh không-hiện" gây cảm giác bấm lúc được lúc không.
static void applyHideImage(void) {
    if (gScaleLockModeEnabled || gActiveImageIndex < 0 || gActiveImageIndex > 1) {
        return;
    }
    if (!imageViewAtIndex(gActiveImageIndex) || gOverlayDimmed) {
        return;   // không có ảnh đang hiện, hoặc đã mờ rồi -> bỏ
    }
    gOverlayDimmed = YES;
    applyActiveImageDisplay();   // ảnh đang hiện -> alpha = độ mờ; ảnh kia GIỮ NGUYÊN (ẩn)
    refreshOverlayWindowVisibility();
    persistOverlayState(NO);
    overlayLog(@"applyHideImage OK active=%ld dim=1", (long)gActiveImageIndex);
}

static void scheduleHideImage(void) {
    if (gActiveImageIndex < 0 || gActiveImageIndex > 1 || !imageViewAtIndex(gActiveImageIndex)) {
        return;
    }
    if (gOverlayDimmed) {
        return;   // đã mờ rồi -> khỏi làm
    }
    overlayRefreshDelaysFromDisk();
    overlayLog(@"scheduleHideImage delay=%ldms", (long)gHideDelayMs);
    NSUInteger generation = ++gToggleGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(gHideDelayMs * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        if (generation != gToggleGeneration) {
            return;
        }
        applyHideImage();
    });
}

// Quy đổi PIXEL -> ĐIỂM. Trong SpringBoard, chạm XUYÊN QUA (vùng trống/hitbox ở màn hình
// chính) bị trả về theo PIXEL (vượt khung điểm), trong khi ảnh/hitbox lưu theo ĐIỂM ->
// phải quy về điểm nếu không sẽ dò trượt. Toạ độ đã là điểm (<= khung) thì giữ nguyên,
// nên relay từ app (vốn gửi điểm) KHÔNG bị ảnh hưởng.
static CGPoint overlayNormalizePoint(CGPoint p) {
    if (!gOverlayRoot) {
        return p;
    }
    CGSize b = gOverlayRoot.bounds.size;
    CGFloat scale = UIScreen.mainScreen.scale;
    if (scale > 1.0 && b.width > 0 && b.height > 0 && (p.x > b.width || p.y > b.height)) {
        p.x /= scale;
        p.y /= scale;
    }
    return p;
}

