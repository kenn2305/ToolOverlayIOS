static CGRect centeredFrameForImage(UIImage *image) {
    CGRect bounds = UIScreen.mainScreen.bounds;
    CGSize imageSize = image.size;

    if (imageSize.width <= 0 || imageSize.height <= 0) {
        return CGRectInset(bounds, bounds.size.width * 0.2, bounds.size.height * 0.35);
    }

    // Căn để ảnh lấp ~72% màn theo cạnh giới hạn. CHO PHÉP phóng to ảnh nhỏ (vd nguồn
    // 52x44) lên cỡ dùng được - trước đây kẹp scale <=1.0 khiến ảnh nhỏ giữ nguyên tí
    // xíu -> không bấm/nhúm trúng (bấm trượt thành "ngoài ảnh" -> dim thay vì panel).
    CGFloat maxWidth = bounds.size.width * 0.72;
    CGFloat maxHeight = bounds.size.height * 0.72;
    CGFloat scale = MIN(maxWidth / imageSize.width, maxHeight / imageSize.height);
    scale = MIN(MAX(scale, 0.08), 16.0);

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

// HIỂN THỊ ĐA-ẢNH (chế độ thường): chỉ ảnh ĐANG HIỆN (gActiveImageIndex) nhìn thấy;
// ảnh kia luôn ẩn hẳn (hidden=YES) -> 2 ảnh KHÔNG bao giờ cùng hiện. Ảnh đang hiện
// có alpha = độ mờ nếu gOverlayDimmed (bấm hitbox Mờ), ngược lại 1.0. TỨC THÌ, không
// animation. Trong viền xanh thì CẢ 2 ảnh hiện rõ (xử lý ở applyScaleLockMode/hitTest).
static void applyActiveImageDisplay(void) {
    if (gScaleLockModeEnabled) {
        for (NSInteger i = 0; i < 2; i++) {
            UIImageView *v = imageViewAtIndex(i);
            if (!v) continue;
            v.hidden = NO;
            v.alpha = 1.0;
        }
        return;
    }
    for (NSInteger i = 0; i < 2; i++) {
        UIImageView *v = imageViewAtIndex(i);
        if (!v) continue;
        if (i == gActiveImageIndex && gOverlayVisible) {
            v.hidden = NO;
            v.alpha = gOverlayDimmed ? gDimOpacity : 1.0;
        } else {
            v.hidden = YES;
        }
    }
}

static void applyOverlayAlpha(void) {
    applyActiveImageDisplay();
}

static void __attribute__((unused)) animateOverlayAlphaForCurrentDimState(void) {
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

