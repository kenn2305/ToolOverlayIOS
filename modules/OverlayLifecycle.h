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
        if (gOverlayImageView2) {
            [gOverlayImageView2 removeFromSuperview];
            gOverlayImageView2 = nil;
        }
        gActiveImageIndex = 0;
        gEditingImageIndex = 0;

        clearAllHitboxes();           // xoá ảnh -> xoá luôn mọi hitbox
        gHitboxToolbar = nil;
        gSizeXSlider = nil;
        gSizeYSlider = nil;

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
    [UIPasteboard removePasteboardWithName:kOverlayPasteboard2Name];
    [NSFileManager.defaultManager removeItemAtPath:kOverlayImagePath error:nil];
    [NSFileManager.defaultManager removeItemAtPath:kOverlayImage2Path error:nil];
    [NSFileManager.defaultManager removeItemAtPath:kOverlayStatePath error:nil];
    [NSFileManager.defaultManager removeItemAtPath:kOverlayHitboxesPath error:nil];
}

// Xoá RIÊNG ảnh 2 (giữ nguyên ảnh 1): gỡ view, xoá hitbox của ảnh 2, đưa active về ảnh 1.
static void removeImage2(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gOverlayImageView2) {
            [gOverlayImageView2 removeFromSuperview];
            gOverlayImageView2 = nil;
        }
        // Xoá mọi hitbox thuộc ảnh 2.
        if (gHitboxes) {
            for (NSInteger i = (NSInteger)gHitboxes.count - 1; i >= 0; i--) {
                if ([gHitboxes[i][@"img"] integerValue] == 1) {
                    [gHitboxes removeObjectAtIndex:i];
                }
            }
            saveHitboxes();
        }
        if (gActiveImageIndex == 1) {
            gActiveImageIndex = 0;
        }
        gEditingImageIndex = 0;
        [UIPasteboard removePasteboardWithName:kOverlayPasteboard2Name];
        [NSFileManager.defaultManager removeItemAtPath:kOverlayImage2Path error:nil];
        rebuildHitboxViews();
        applyActiveImageDisplay();
        refreshOverlayWindowVisibility();
        persistOverlayState(YES);
        NSLog(@"[OverlayIOSTOOL] Image 2 removed");
    });
}

static void __attribute__((unused)) stopOverlayTool(void) {
    clearPublishedStorage();
    removeOverlay();
}

static void loadOverlaySettings(void) {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:kOverlaySettingsPath];
    gToggleClickEnabled = [settings[@"toggleClickEnabled"] boolValue];
    gHideDelayMs = settings[@"hideDelayMs"] ? [settings[@"hideDelayMs"] integerValue] : 0;
    gHideDelayMs2 = settings[@"hideDelayMs2"] ? [settings[@"hideDelayMs2"] integerValue] : gHideDelayMs;
    gShowDelayMs = settings[@"showDelayMs"] ? [settings[@"showDelayMs"] integerValue] : 0;
    gShowDelayMs2 = settings[@"showDelayMs2"] ? [settings[@"showDelayMs2"] integerValue] : gShowDelayMs;
    gDimOpacity = settings[@"dimOpacity"] ? [settings[@"dimOpacity"] doubleValue] : 1.0;
    gDimAnimationMs = settings[@"dimAnimationMs"] ? [settings[@"dimAnimationMs"] integerValue] : 0;
    gHideDelayMs = MAX(0, MIN(gHideDelayMs, 10000));
    gHideDelayMs2 = MAX(0, MIN(gHideDelayMs2, 10000));
    gShowDelayMs = MAX(0, MIN(gShowDelayMs, 10000));
    gShowDelayMs2 = MAX(0, MIN(gShowDelayMs2, 10000));
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
    applyActiveImageDisplay();
    refreshOverlayWindowVisibility();
    persistOverlayState(YES);
}

static void applyOverlayDimmed(BOOL dimmed) {
    if (!gOverlayImageView || !gOverlayVisible || gScaleLockModeEnabled) {
        return;
    }

    gOverlayDimmed = dimmed;
    applyActiveImageDisplay();   // TỨC THÌ, không animation
    refreshOverlayWindowVisibility();
    persistOverlayState(YES);
}

