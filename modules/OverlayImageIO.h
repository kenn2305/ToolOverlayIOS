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

static UIImage *overlayImage2FromPasteboard(void) {
    UIPasteboard *pasteboard = [UIPasteboard pasteboardWithName:kOverlayPasteboard2Name create:NO];
    if (!pasteboard) {
        return nil;
    }
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

static UIImage *overlayImage2FromSharedFile(void) {
    NSData *imageData = [NSData dataWithContentsOfFile:kOverlayImage2Path];
    if (!imageData.length) {
        return nil;
    }
    return [UIImage imageWithData:imageData scale:UIScreen.mainScreen.scale];
}

// resetFrame=YES: ảnh MỚI do người dùng vừa chọn -> bỏ vị trí/kích thước cũ, đưa
// về khung giữa màn hình, thoát viền xanh, ghi đè state.plist. resetFrame=NO: chỉ
// khôi phục ảnh đang có (foreground app / đồng bộ state) -> giữ nguyên frame đã lưu.
// index: 0 = ẢNH 1, 1 = ẢNH 2. resetFrame=YES: ảnh vừa chọn -> căn giữa, cho HIỆN ngay
// (ảnh kia tự ẩn vì loại trừ lẫn nhau). resetFrame=NO: khôi phục từ state đã lưu.
static void showOverlayImageAtIndex(UIImage *image, BOOL resetFrame, NSInteger index) {
    if (!image || index < 0 || index > 1) {
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
        UIImageView *view = imageViewAtIndex(index);
        if (!view) {
            overlayLog(@"showOverlayImage: tao image view %ld + gesture", (long)index);
            view = [[UIImageView alloc] initWithFrame:centeredFrameForImage(image)];
            configureRawImageView(view);
            attachGestures(view, index);
            [gOverlayRoot addSubview:view];
            if (index == 1) { gOverlayImageView2 = view; } else { gOverlayImageView = view; }
            doReset = YES;  // view vừa tạo -> luôn căn giữa theo ảnh
        }
        updateExpandedPinchGesture();
        loadHitboxes();          // nạp hitbox đã lưu
        rebuildHitboxViews();    // dựng ô (ẩn ở chế độ thường)

        view.image = rendersOverlayImage() ? image : nil;

        if (doReset) {
            // Ảnh mới: huỷ mọi toggle đang chờ, thoát viền xanh, căn giữa lại, cho ảnh
            // này HIỆN (active=index) -> ảnh kia tự ẩn. GHI ĐÈ state cũ.
            gToggleGeneration++;
            if (gScaleLockModeEnabled) {
                applyScaleLockMode(NO);
            }
            gScaleLockModeEnabled = NO;
            gOverlayVisible = YES;
            gOverlayDimmed = NO;
            gActiveImageIndex = index;
            view.transform = CGAffineTransformIdentity;
            view.frame = centeredFrameForImage(image);
            view.layer.borderWidth = 0;
            view.layer.borderColor = nil;
            applyActiveImageDisplay();
            updateScaleLockControlsVisibility();
            refreshOverlayWindowVisibility();
            persistOverlayState(YES);
            overlayLog(@"Overlay ANH %ld MOI (reset frame) %.0fx%.0f", (long)index, image.size.width, image.size.height);
        } else {
            if (CGRectIsEmpty(view.frame) || view.frame.size.width < 2 || view.frame.size.height < 2) {
                view.frame = centeredFrameForImage(image);
            }
            gOverlayVisible = YES;
            applyOverlayStateFromDisk();
            applyActiveImageDisplay();
            refreshOverlayWindowVisibility();
            persistOverlayState(NO);
        }

        overlayLog(@"Overlay HIEN anh %ld %.0fx%.0f windowHidden=%d rootHidden=%d",
                   (long)index, image.size.width, image.size.height,
                   gOverlayWindow.hidden, gOverlayRoot.hidden);
      } @catch (NSException *exception) {
        overlayLog(@"showOverlayImage: EXCEPTION %@ - %@", exception.name, exception.reason);
      }
    });
}

static void showOverlayImage(UIImage *image, BOOL resetFrame) {
    showOverlayImageAtIndex(image, resetFrame, 0);
}

static UIImage *overlayImage2FromPasteboard(void);
static UIImage *overlayImage2FromSharedFile(void);

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

static void loadAndShowPublishedOverlay2(BOOL resetFrame) {
    UIImage *image = overlayImage2FromPasteboard();
    if (!image) {
        image = overlayImage2FromSharedFile();
    }
    if (!image) {
        return;   // ảnh 2 là tùy chọn -> vắng mặt là bình thường, không log
    }
    overlayLog(@"loadAndShowPublishedOverlay2: doc duoc anh 2 %.0fx%.0f reset=%d", image.size.width, image.size.height, resetFrame);
    showOverlayImageAtIndex(image, resetFrame, 1);
}

