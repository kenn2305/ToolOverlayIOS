// ===================== HITBOX: model + lưu trữ =====================
static void loadHitboxes(void) {
    if (!gHitboxes) gHitboxes = [NSMutableArray array];
    [gHitboxes removeAllObjects];
    NSArray *arr = [NSArray arrayWithContentsOfFile:kOverlayHitboxesPath];
    if ([arr isKindOfClass:NSArray.class]) {
        for (id item in arr) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *d = item;
            NSMutableDictionary *h = [NSMutableDictionary dictionary];
            h[@"type"] = @([d[@"type"] integerValue] == 1 ? 1 : 0);
            h[@"img"] = @([d[@"img"] integerValue] == 1 ? 1 : 0);   // 0 = ảnh 1 (mặc định), 1 = ảnh 2
            h[@"x"] = @([d[@"x"] doubleValue]);
            h[@"y"] = @([d[@"y"] doubleValue]);
            h[@"w"] = @(MAX(20.0, [d[@"w"] doubleValue]));
            h[@"h"] = @(MAX(20.0, [d[@"h"] doubleValue]));
            [gHitboxes addObject:h];
        }
    }
}

static void saveHitboxes(void) {
    if (gApplyingRemoteState) return;
    [NSFileManager.defaultManager createDirectoryAtPath:kOverlayDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [(gHitboxes ?: @[]) writeToFile:kOverlayHitboxesPath atomically:YES];
}

static NSInteger hitboxImageAt(NSInteger index) {
    if (index < 0 || index >= (NSInteger)gHitboxes.count) return 0;
    return [gHitboxes[index][@"img"] integerValue] == 1 ? 1 : 0;
}

// Đếm hitbox theo loại VÀ theo ảnh (giới hạn 8 mỗi loại / mỗi ảnh).
static NSInteger countHitboxesOfTypeForImage(NSInteger type, NSInteger img) {
    NSInteger n = 0;
    for (NSDictionary *h in gHitboxes) {
        if ([h[@"type"] integerValue] == type && [h[@"img"] integerValue] == img) n++;
    }
    return n;
}

static CGRect hitboxRectAt(NSInteger index) {
    if (index < 0 || index >= (NSInteger)gHitboxes.count) return CGRectZero;
    NSDictionary *h = gHitboxes[index];
    return CGRectMake([h[@"x"] doubleValue], [h[@"y"] doubleValue], [h[@"w"] doubleValue], [h[@"h"] doubleValue]);
}

// Hitbox trên cùng chứa điểm p (toạ độ root). -1 nếu không trúng. (Giữ lại - trigger
// giờ xét TẤT CẢ hitbox phủ điểm trong overlayTriggerAtPoint thay vì chỉ cái trên cùng.)
static NSInteger __attribute__((unused)) hitboxIndexAtPoint(CGPoint p) {
    for (NSInteger i = (NSInteger)gHitboxes.count - 1; i >= 0; i--) {
        if (CGRectContainsPoint(hitboxRectAt(i), p)) return i;
    }
    return -1;
}

// Như trên nhưng CHỈ xét hitbox thuộc ảnh img (dùng khi chọn trong viền xanh để không
// lẫn sang hitbox của ảnh không-focus).
static NSInteger hitboxIndexAtPointForImage(CGPoint p, NSInteger img) {
    for (NSInteger i = (NSInteger)gHitboxes.count - 1; i >= 0; i--) {
        if (hitboxImageAt(i) == img && CGRectContainsPoint(hitboxRectAt(i), p)) return i;
    }
    return -1;
}

static UIColor *hitboxColorForType(NSInteger type) {
    return type == 0 ? UIColor.systemGreenColor : UIColor.systemRedColor;
}

// ===================== HITBOX: hiển thị (viền xanh) =====================
// Chỉ hitbox của ảnh ĐANG FOCUS hiện trong viền xanh (tránh chèn lẫn nhau).
static BOOL hitboxViewShouldShow(NSInteger index) {
    if (!gScaleLockModeEnabled) return NO;
    return hitboxImageAt(index) == gEditingImageIndex;
}

static void updateHitboxSelectionHighlight(void) {
    for (NSUInteger i = 0; i < gHitboxViews.count && i < gHitboxes.count; i++) {
        UIView *v = gHitboxViews[i];
        BOOL sel = ((NSInteger)i == gSelectedIndex);
        NSInteger type = [gHitboxes[i][@"type"] integerValue];
        v.layer.borderWidth = sel ? 4.0 : 2.0;
        v.backgroundColor = [hitboxColorForType(type) colorWithAlphaComponent:(sel ? 0.32 : 0.15)];
    }
    // Viền xanh: cả 2 ảnh đều viền xanh; ảnh đang FOCUS đậm hơn, ảnh được CHỌN dày nhất.
    for (NSInteger i = 0; i < 2; i++) {
        UIImageView *img = imageViewAtIndex(i);
        if (!img) continue;
        if (!gScaleLockModeEnabled) {
            img.layer.borderWidth = 0.0;
            img.layer.borderColor = nil;
            continue;
        }
        BOOL focused = (i == gEditingImageIndex);
        BOOL selected = focused && (gSelectedIndex < 0);
        img.layer.borderWidth = selected ? 4.0 : (focused ? 3.0 : 1.5);
        img.layer.borderColor = UIColor.systemBlueColor.CGColor;
    }
}

static void rebuildHitboxViews(void) {
    if (!gOverlayRoot) return;
    if (!gHitboxViews) gHitboxViews = [NSMutableArray array];
    for (UIView *v in gHitboxViews) [v removeFromSuperview];
    [gHitboxViews removeAllObjects];

    for (NSUInteger i = 0; i < gHitboxes.count; i++) {
        NSInteger type = [gHitboxes[i][@"type"] integerValue];
        UIView *v = [[UIView alloc] initWithFrame:hitboxRectAt((NSInteger)i)];
        v.userInteractionEnabled = NO;   // chỉ là hình; chọn bằng toạ độ trong sendEvent
        v.layer.borderColor = hitboxColorForType(type).CGColor;
        v.layer.cornerRadius = 6.0;
        v.hidden = !hitboxViewShouldShow((NSInteger)i);
        [gOverlayRoot addSubview:v];
        [gHitboxViews addObject:v];
    }
    if (gOverlayImageView) [gOverlayRoot bringSubviewToFront:gOverlayImageView];
    if (gOverlayImageView2) [gOverlayRoot bringSubviewToFront:gOverlayImageView2];
    if (gHitboxToolbar) [gOverlayRoot bringSubviewToFront:gHitboxToolbar];
    if (gImageFocusBar) [gOverlayRoot bringSubviewToFront:gImageFocusBar];
    if (gSizeXSlider) [gOverlayRoot bringSubviewToFront:gSizeXSlider];
    if (gSizeYSlider) [gOverlayRoot bringSubviewToFront:gSizeYSlider];
    updateHitboxSelectionHighlight();
}

// Cập nhật ẩn/hiện ô hitbox theo ảnh đang focus (dùng khi đổi focus / vào viền xanh).
static void refreshHitboxViewVisibility(void) {
    for (NSUInteger i = 0; i < gHitboxViews.count && i < gHitboxes.count; i++) {
        gHitboxViews[i].hidden = !hitboxViewShouldShow((NSInteger)i);
    }
}

static void setHitboxViewsHidden(BOOL hidden) {
    for (UIView *v in gHitboxViews) v.hidden = hidden;
}

// ===================== HITBOX: phần tử đang chọn (ảnh/hitbox) =====================
static CGRect selectedElementFrame(void) {
    if (gSelectedIndex < 0) {
        UIImageView *v = editingImageView();
        return v ? v.frame : CGRectZero;
    }
    return hitboxRectAt(gSelectedIndex);
}

static void setSelectedElementFrame(CGRect f) {
    if (gSelectedIndex < 0) {
        UIImageView *v = editingImageView();
        if (v) v.frame = f;
        return;
    }
    if (gSelectedIndex >= (NSInteger)gHitboxes.count) return;
    NSMutableDictionary *h = gHitboxes[gSelectedIndex];
    h[@"x"] = @(f.origin.x); h[@"y"] = @(f.origin.y);
    h[@"w"] = @(f.size.width); h[@"h"] = @(f.size.height);
    if (gSelectedIndex < (NSInteger)gHitboxViews.count) {
        gHitboxViews[gSelectedIndex].frame = f;
    }
}

// ===================== HITBOX: UI chỉnh sửa (2 slider + toolbar) =====================
static void hitboxResizeWidth(CGFloat newW);
static void hitboxResizeHeight(CGFloat newH);
static void overlayAddHitbox(NSInteger type);
static void overlayRemoveSelectedHitbox(void);
static void setEditingImageIndex(NSInteger index);
static void updateImageFocusButtons(void);
static void overlayDeleteFocusedImageInEdit(void);
static void overlayPromoteImage2ToImage1(void);

@interface OverlayHitboxTarget : NSObject
@end
@implementation OverlayHitboxTarget
- (void)sizeXChanged:(UISlider *)s { hitboxResizeWidth(s.value); }
- (void)sizeYChanged:(UISlider *)s { hitboxResizeHeight(s.value); }
- (void)addShow { overlayAddHitbox(0); }
- (void)addDim { overlayAddHitbox(1); }
// Xoá: đang chọn HITBOX -> xoá hitbox đó; đang chọn ẢNH -> xoá ảnh focus + hitbox của nó.
- (void)removeSel {
    if (gSelectedIndex >= 0) {
        overlayRemoveSelectedHitbox();
    } else {
        overlayDeleteFocusedImageInEdit();
    }
}
- (void)doneEdit { applyScaleLockMode(NO); }
- (void)focusImage1 { setEditingImageIndex(0); }
- (void)focusImage2 { setEditingImageIndex(1); }
@end
static OverlayHitboxTarget *gHitboxTarget = nil;

static void updateHitboxEditUIForSelection(void) {
    if (gSizeXSlider && !gSizeXSlider.tracking) {
        CGFloat w = selectedElementFrame().size.width;
        gSizeXSlider.value = MIN(MAX(w, gSizeXSlider.minimumValue), gSizeXSlider.maximumValue);
    }
    if (gSizeYSlider && !gSizeYSlider.tracking) {
        CGFloat h = selectedElementFrame().size.height;
        gSizeYSlider.value = MIN(MAX(h, gSizeYSlider.minimumValue), gSizeYSlider.maximumValue);
    }
}

static void hitboxResizeWidth(CGFloat newW) {
    CGRect f = selectedElementFrame();
    if (f.size.width <= 0) return;
    CGPoint c = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    CGFloat newH = f.size.height;
    if (gSelectedIndex < 0) {                 // ẢNH: đồng bộ -> giữ tỉ lệ
        CGFloat scale = newW / MAX(f.size.width, 1.0);
        newH = f.size.height * scale;
        if (gSizeYSlider && !gSizeYSlider.tracking) gSizeYSlider.value = MIN(MAX(newH, gSizeYSlider.minimumValue), gSizeYSlider.maximumValue);
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    setSelectedElementFrame(CGRectMake(c.x - newW/2.0, c.y - newH/2.0, newW, newH));
    [CATransaction commit];
    if (gSelectedIndex < 0) persistOverlayState(NO); else saveHitboxes();
}

static void hitboxResizeHeight(CGFloat newH) {
    CGRect f = selectedElementFrame();
    if (f.size.height <= 0) return;
    CGPoint c = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    CGFloat newW = f.size.width;
    if (gSelectedIndex < 0) {                 // ẢNH: đồng bộ -> giữ tỉ lệ
        CGFloat scale = newH / MAX(f.size.height, 1.0);
        newW = f.size.width * scale;
        if (gSizeXSlider && !gSizeXSlider.tracking) gSizeXSlider.value = MIN(MAX(newW, gSizeXSlider.minimumValue), gSizeXSlider.maximumValue);
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    setSelectedElementFrame(CGRectMake(c.x - newW/2.0, c.y - newH/2.0, newW, newH));
    [CATransaction commit];
    if (gSelectedIndex < 0) persistOverlayState(NO); else saveHitboxes();
}

static void overlayAddHitbox(NSInteger type) {
    if (!gOverlayRoot) return;
    // Giới hạn 8 mỗi loại / mỗi ảnh; hitbox mới thuộc ảnh đang focus.
    if (countHitboxesOfTypeForImage(type, gEditingImageIndex) >= kOverlayMaxHitboxesPerType) return;
    if (!gHitboxes) gHitboxes = [NSMutableArray array];
    CGRect b = gOverlayRoot.bounds;
    CGFloat w = 130, h = 70;
    NSMutableDictionary *hb = [NSMutableDictionary dictionary];
    hb[@"type"] = @(type);
    hb[@"img"] = @(gEditingImageIndex);
    hb[@"x"] = @((b.size.width - w)/2.0);
    hb[@"y"] = @((b.size.height - h)/2.0);
    hb[@"w"] = @(w);
    hb[@"h"] = @(h);
    [gHitboxes addObject:hb];
    gSelectedIndex = (NSInteger)gHitboxes.count - 1;
    rebuildHitboxViews();
    updateHitboxEditUIForSelection();
    saveHitboxes();
}

static void overlayRemoveSelectedHitbox(void) {
    if (gSelectedIndex < 0 || gSelectedIndex >= (NSInteger)gHitboxes.count) return;
    [gHitboxes removeObjectAtIndex:gSelectedIndex];
    gSelectedIndex = -1;   // quay về chọn ảnh
    rebuildHitboxViews();
    updateHitboxEditUIForSelection();
    saveHitboxes();
}

static void clearAllHitboxes(void) {
    if (gHitboxViews) { for (UIView *v in gHitboxViews) [v removeFromSuperview]; [gHitboxViews removeAllObjects]; }
    if (gHitboxes) [gHitboxes removeAllObjects];
    gSelectedIndex = -1;
    [NSFileManager.defaultManager removeItemAtPath:kOverlayHitboxesPath error:nil];
}

// Đưa ẢNH 2 lên thay chỗ ẢNH 1: copy nội dung/khung, gỡ ảnh 1 cũ + hitbox img==0, đổi
// hitbox img==1 -> img==0, và đồng bộ file (overlay2.png -> overlay.png) để bền qua respring.
static void overlayPromoteImage2ToImage1(void) {
    if (!gOverlayImageView || !gOverlayImageView2) return;
    gOverlayImageView.image = gOverlayImageView2.image;
    gOverlayImageView.transform = CGAffineTransformIdentity;
    gOverlayImageView.frame = gOverlayImageView2.frame;
    [gOverlayImageView2 removeFromSuperview];
    gOverlayImageView2 = nil;

    if (gHitboxes) {
        for (NSInteger i = (NSInteger)gHitboxes.count - 1; i >= 0; i--) {
            NSInteger im = [gHitboxes[i][@"img"] integerValue];
            if (im == 0) {
                [gHitboxes removeObjectAtIndex:i];      // bỏ hitbox của ảnh 1 cũ
            } else {
                gHitboxes[i][@"img"] = @(0);            // hitbox ảnh 2 -> thuộc ảnh 1
            }
        }
        saveHitboxes();
    }

    @try {
        NSFileManager *fm = NSFileManager.defaultManager;
        if ([fm fileExistsAtPath:kOverlayImage2Path]) {
            [fm removeItemAtPath:kOverlayImagePath error:nil];
            [fm copyItemAtPath:kOverlayImage2Path toPath:kOverlayImagePath error:nil];
            [fm removeItemAtPath:kOverlayImage2Path error:nil];
        }
    } @catch (__unused id e) {}
    // Xoá pasteboard cũ -> respring sẽ đọc lại ảnh 1 từ overlay.png (đã là nội dung ảnh 2).
    [UIPasteboard removePasteboardWithName:kOverlayPasteboardName];
    [UIPasteboard removePasteboardWithName:kOverlayPasteboard2Name];

    gActiveImageIndex = 0;
    gEditingImageIndex = 0;
}

// VIỀN XANH - xoá ẢNH đang focus + hitbox của nó. Ảnh 2: gỡ thẳng, ở lại viền xanh.
// Ảnh 1: nếu có ảnh 2 thì ảnh 2 thế chỗ; nếu là ảnh DUY NHẤT thì xoá sạch + thoát tool.
static void overlayDeleteFocusedImageInEdit(void) {
    if (!gScaleLockModeEnabled) return;

    if (gEditingImageIndex == 1) {
        if (gOverlayImageView2) { [gOverlayImageView2 removeFromSuperview]; gOverlayImageView2 = nil; }
        if (gHitboxes) {
            for (NSInteger i = (NSInteger)gHitboxes.count - 1; i >= 0; i--) {
                if ([gHitboxes[i][@"img"] integerValue] == 1) [gHitboxes removeObjectAtIndex:i];
            }
            saveHitboxes();
        }
        [UIPasteboard removePasteboardWithName:kOverlayPasteboard2Name];
        [NSFileManager.defaultManager removeItemAtPath:kOverlayImage2Path error:nil];
        gEditingImageIndex = 0;
        gActiveImageIndex = 0;
    } else {
        if (hasSecondImage()) {
            overlayPromoteImage2ToImage1();
        } else {
            applyScaleLockMode(NO);     // ảnh duy nhất -> thoát viền xanh + xoá sạch
            clearPublishedStorage();
            removeOverlay();
            return;
        }
    }

    // Còn ảnh -> ở lại viền xanh, cập nhật hiển thị + UI.
    gSelectedIndex = -1;
    gImageFocusBar.hidden = !hasSecondImage();
    updateImageFocusButtons();
    rebuildHitboxViews();
    updateHitboxSelectionHighlight();
    updateHitboxEditUIForSelection();
    applyActiveImageDisplay();
    refreshOverlayWindowVisibility();
    persistOverlayState(YES);
    overlayLog(@"overlayDeleteFocusedImageInEdit xong: hasImg2=%d", hasSecondImage());
}

static UIButton *hitboxToolButton(NSString *title, UIColor *color, SEL action) {
    UIButton *bt = [UIButton buttonWithType:UIButtonTypeSystem];
    [bt setTitle:title forState:UIControlStateNormal];
    [bt setTitleColor:color forState:UIControlStateNormal];
    bt.titleLabel.font = [UIFont systemFontOfSize:15 weight:kOverlayFontWeightSemibold];
    [bt addTarget:gHitboxTarget action:action forControlEvents:UIControlEventTouchUpInside];
    return bt;
}

static void ensureHitboxEditUI(void) {
    if (!gOverlayRoot) return;
    if (!gHitboxTarget) gHitboxTarget = [OverlayHitboxTarget new];
    UIView *root = gOverlayRoot;
    CGRect b = root.bounds;
    CGFloat safeTop = gOverlayHostWindow ? MAX(gOverlayHostWindow.safeAreaInsets.top, 30.0) : 44.0;
    CGFloat safeBottom = gOverlayHostWindow ? gOverlayHostWindow.safeAreaInsets.bottom : 0.0;

    if (!gHitboxToolbar) {
        gHitboxToolbar = [[UIView alloc] init];
        gHitboxToolbar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        gHitboxToolbar.layer.cornerRadius = 10.0;
        [root addSubview:gHitboxToolbar];
        UIButton *bShow = hitboxToolButton(@"+ Hiện", UIColor.systemGreenColor, @selector(addShow));
        UIButton *bDim = hitboxToolButton(@"+ Mờ", UIColor.systemRedColor, @selector(addDim));
        UIButton *bDel = hitboxToolButton(@"Xoá", UIColor.whiteColor, @selector(removeSel));
        UIButton *bDone = hitboxToolButton(@"Xong", [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0], @selector(doneEdit));
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[bShow, bDim, bDel, bDone]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.distribution = UIStackViewDistributionFillEqually;
        stack.tag = 7788;
        [gHitboxToolbar addSubview:stack];
    }
    gHitboxToolbar.frame = CGRectMake(10, safeTop, b.size.width - 20, 42);
    UIView *stack = [gHitboxToolbar viewWithTag:7788];
    stack.frame = gHitboxToolbar.bounds;

    // Thanh chọn FOCUS "Ảnh 1 / Ảnh 2" (chỉ ý nghĩa khi có ảnh 2). Bấm để đổi ảnh đang
    // chỉnh: hitbox + điều khiển theo ảnh đó; cả 2 ảnh vẫn hiện.
    if (!gImageFocusBar) {
        gImageFocusBar = [[UIView alloc] init];
        gImageFocusBar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        gImageFocusBar.layer.cornerRadius = 10.0;
        [root addSubview:gImageFocusBar];
        gFocusImage1Button = hitboxToolButton(@"Ảnh 1", UIColor.whiteColor, @selector(focusImage1));
        gFocusImage2Button = hitboxToolButton(@"Ảnh 2", UIColor.whiteColor, @selector(focusImage2));
        UIStackView *fstack = [[UIStackView alloc] initWithArrangedSubviews:@[gFocusImage1Button, gFocusImage2Button]];
        fstack.axis = UILayoutConstraintAxisHorizontal;
        fstack.distribution = UIStackViewDistributionFillEqually;
        fstack.tag = 7799;
        [gImageFocusBar addSubview:fstack];
    }
    gImageFocusBar.frame = CGRectMake(10, safeTop + 48, b.size.width - 20, 40);
    UIView *fstack = [gImageFocusBar viewWithTag:7799];
    fstack.frame = gImageFocusBar.bounds;
    gImageFocusBar.hidden = !hasSecondImage();
    updateImageFocusButtons();

    if (!gSizeXSlider) {
        gSizeXSlider = [UISlider new];
        gSizeXSlider.minimumValue = 20.0;
        gSizeXSlider.minimumTrackTintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
        [gSizeXSlider addTarget:gHitboxTarget action:@selector(sizeXChanged:) forControlEvents:UIControlEventValueChanged];
        [root addSubview:gSizeXSlider];
    }
    gSizeXSlider.maximumValue = b.size.width;
    gSizeXSlider.frame = CGRectMake(28, b.size.height - safeBottom - 46, b.size.width - 76, 30);

    if (!gSizeYSlider) {
        gSizeYSlider = [UISlider new];
        gSizeYSlider.minimumValue = 20.0;
        gSizeYSlider.minimumTrackTintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
        [gSizeYSlider addTarget:gHitboxTarget action:@selector(sizeYChanged:) forControlEvents:UIControlEventValueChanged];
        [root addSubview:gSizeYSlider];
    }
    gSizeYSlider.maximumValue = b.size.height;
    CGFloat vLen = b.size.height - safeTop - 150.0;
    if (vLen < 120) vLen = 120;
    gSizeYSlider.transform = CGAffineTransformIdentity;
    gSizeYSlider.frame = CGRectMake(0, 0, vLen, 30);
    gSizeYSlider.transform = CGAffineTransformMakeRotation(-M_PI_2);
    gSizeYSlider.center = CGPointMake(b.size.width - 22, safeTop + 60 + vLen/2.0);
}

static void setHitboxEditUIHidden(BOOL hidden) {
    gHitboxToolbar.hidden = hidden;
    gSizeXSlider.hidden = hidden;
    gSizeYSlider.hidden = hidden;
    gImageFocusBar.hidden = hidden || !hasSecondImage();
}

// Tô đậm nút focus của ảnh đang chỉnh.
static void updateImageFocusButtons(void) {
    UIColor *on = [UIColor colorWithRed:0.12 green:0.47 blue:1.0 alpha:0.95];
    UIColor *off = [UIColor colorWithWhite:0.18 alpha:0.95];
    gFocusImage1Button.backgroundColor = (gEditingImageIndex == 0) ? on : off;
    gFocusImage2Button.backgroundColor = (gEditingImageIndex == 1) ? on : off;
}

// Đổi ảnh đang FOCUS trong viền xanh: hitbox + điều khiển chuyển sang ảnh đó; chọn lại
// chính ảnh đó (gSelectedIndex=-1). Cả 2 ảnh vẫn hiện.
static void setEditingImageIndex(NSInteger index) {
    if (!gScaleLockModeEnabled) return;
    if (index == 1 && !hasSecondImage()) index = 0;
    if (index < 0 || index > 1) index = 0;
    gEditingImageIndex = index;
    gSelectedIndex = -1;
    refreshHitboxViewVisibility();
    updateImageFocusButtons();
    updateHitboxSelectionHighlight();
    updateHitboxEditUIForSelection();
}

// Điểm có nằm trên UI chỉnh sửa (slider/toolbar) không -> để không nhầm thành kéo phần tử.
static BOOL pointOnHitboxEditUI(CGPoint pInRoot) {
    UIView *controls[4] = { gHitboxToolbar, gImageFocusBar, gSizeXSlider, gSizeYSlider };
    for (int i = 0; i < 4; i++) {
        UIView *c = controls[i];
        if (c && !c.hidden) {
            CGPoint lp = [c convertPoint:pInRoot fromView:gOverlayRoot];
            if ([c pointInside:lp withEvent:nil]) return YES;
        }
    }
    return NO;
}

