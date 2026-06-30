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
    gOverlayImageView.layer.borderWidth = 0;
    gOverlayImageView.layer.borderColor = nil;
    if (gOverlayImageView2) {
        gOverlayImageView2.layer.borderWidth = 0;
        gOverlayImageView2.layer.borderColor = nil;
    }
    applyActiveImageDisplay();   // gOverlayVisible=NO -> ẩn cả 2 ảnh
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

static void __attribute__((unused)) ensureScaleLockControls(void) {
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

