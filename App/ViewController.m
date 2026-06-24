#import "ViewController.h"
#import <notify.h>

static NSString * const kOverlayDirectory = @"/var/mobile/Library/OverlayIOSTOOL";
static NSString * const kOverlayImagePath = @"/var/mobile/Library/OverlayIOSTOOL/overlay.png";
static NSString * const kOverlaySettingsPath = @"/var/mobile/Library/OverlayIOSTOOL/settings.plist";
static NSString * const kOverlayStatePath = @"/var/mobile/Library/OverlayIOSTOOL/state.plist";
static NSString * const kOverlayPasteboardName = @"com.vietanh.overlayiostool.image";
static const char *kOverlayUpdatedNotification = "com.vietanh.overlayiostool.image-updated";
static const char *kOverlayRemoveNotification = "com.vietanh.overlayiostool.image-remove";
static const char *kOverlaySettingsNotification = "com.vietanh.overlayiostool.settings-updated";

@interface ViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIImage *selectedImage;
@property (nonatomic, strong) NSData *selectedImageData;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *showButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UISwitch *toggleClickSwitch;
@property (nonatomic, strong) UISlider *hideDelaySlider;
@property (nonatomic, strong) UISlider *showDelaySlider;
@property (nonatomic, strong) UISlider *dimOpacitySlider;
@property (nonatomic, strong) UISlider *dimAnimationSlider;
@property (nonatomic, strong) UILabel *hideDelayValueLabel;
@property (nonatomic, strong) UILabel *showDelayValueLabel;
@property (nonatomic, strong) UILabel *dimOpacityValueLabel;
@property (nonatomic, strong) UILabel *dimAnimationValueLabel;
@property (nonatomic, assign) int settingsNotifyToken;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"OverlayIOSTOOL";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self buildUI];
    [self loadSettings];
    [self registerSettingsNotification];
    [self updateState];
}

- (void)dealloc {
    if (self.settingsNotifyToken != 0) {
        notify_cancel(self.settingsNotifyToken);
    }
}

- (void)buildUI {
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];

    UIView *contentView = [UIView new];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentView];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [contentView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],
    ]];

    self.previewImageView = [UIImageView new];
    self.previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewImageView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.previewImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewImageView.clipsToBounds = YES;
    self.previewImageView.layer.cornerRadius = 8;
    [contentView addSubview:self.previewImageView];

    UIButton *chooseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    chooseButton.translatesAutoresizingMaskIntoConstraints = NO;
    chooseButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [chooseButton setTitle:@"Chon anh" forState:UIControlStateNormal];
    [chooseButton addTarget:self action:@selector(chooseImageTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:chooseButton];

    self.showButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.showButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.showButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [self.showButton setTitle:@"Hien thi" forState:UIControlStateNormal];
    [self.showButton addTarget:self action:@selector(showImageTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:self.showButton];

    self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.deleteButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [self.deleteButton setTitle:@"Xoa anh" forState:UIControlStateNormal];
    [self.deleteButton addTarget:self action:@selector(deleteImageTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:self.deleteButton];

    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.numberOfLines = 2;
    [contentView addSubview:self.statusLabel];

    UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[chooseButton, self.showButton, self.deleteButton]];
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.distribution = UIStackViewDistributionFillEqually;
    buttonStack.spacing = 12;
    [contentView addSubview:buttonStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.previewImageView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:24],
        [self.previewImageView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.previewImageView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.previewImageView.heightAnchor constraintEqualToAnchor:self.previewImageView.widthAnchor multiplier:1.15],

        [buttonStack.topAnchor constraintEqualToAnchor:self.previewImageView.bottomAnchor constant:20],
        [buttonStack.leadingAnchor constraintEqualToAnchor:self.previewImageView.leadingAnchor],
        [buttonStack.trailingAnchor constraintEqualToAnchor:self.previewImageView.trailingAnchor],
        [buttonStack.heightAnchor constraintEqualToConstant:48],

        [self.statusLabel.topAnchor constraintEqualToAnchor:buttonStack.bottomAnchor constant:18],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.previewImageView.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.previewImageView.trailingAnchor],
    ]];

    for (UIButton *button in @[chooseButton, self.showButton, self.deleteButton]) {
        button.backgroundColor = UIColor.secondarySystemBackgroundColor;
        button.layer.cornerRadius = 8;
    }

    UIView *settingsView = [UIView new];
    settingsView.translatesAutoresizingMaskIntoConstraints = NO;
    settingsView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    settingsView.layer.cornerRadius = 8;
    [contentView addSubview:settingsView];

    UILabel *toggleLabel = [UILabel new];
    toggleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    toggleLabel.text = @"Toggle Click";
    toggleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [settingsView addSubview:toggleLabel];

    self.toggleClickSwitch = [UISwitch new];
    self.toggleClickSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleClickSwitch addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    [settingsView addSubview:self.toggleClickSwitch];

    UILabel *hideDelayLabel = [UILabel new];
    hideDelayLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hideDelayLabel.text = @"Delay an";
    hideDelayLabel.font = [UIFont systemFontOfSize:14];
    [settingsView addSubview:hideDelayLabel];

    self.hideDelayValueLabel = [UILabel new];
    self.hideDelayValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.hideDelayValueLabel.textAlignment = NSTextAlignmentRight;
    self.hideDelayValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    [settingsView addSubview:self.hideDelayValueLabel];

    self.hideDelaySlider = [UISlider new];
    self.hideDelaySlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.hideDelaySlider.minimumValue = 0;
    self.hideDelaySlider.maximumValue = 2000;
    [self.hideDelaySlider addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    [settingsView addSubview:self.hideDelaySlider];

    UILabel *showDelayLabel = [UILabel new];
    showDelayLabel.translatesAutoresizingMaskIntoConstraints = NO;
    showDelayLabel.text = @"Delay hien";
    showDelayLabel.font = [UIFont systemFontOfSize:14];
    [settingsView addSubview:showDelayLabel];

    self.showDelayValueLabel = [UILabel new];
    self.showDelayValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.showDelayValueLabel.textAlignment = NSTextAlignmentRight;
    self.showDelayValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    [settingsView addSubview:self.showDelayValueLabel];

    self.showDelaySlider = [UISlider new];
    self.showDelaySlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.showDelaySlider.minimumValue = 0;
    self.showDelaySlider.maximumValue = 2000;
    [self.showDelaySlider addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    [settingsView addSubview:self.showDelaySlider];

    UILabel *dimOpacityLabel = [UILabel new];
    dimOpacityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    dimOpacityLabel.text = @"Do mo";
    dimOpacityLabel.font = [UIFont systemFontOfSize:14];
    [settingsView addSubview:dimOpacityLabel];

    self.dimOpacityValueLabel = [UILabel new];
    self.dimOpacityValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimOpacityValueLabel.textAlignment = NSTextAlignmentRight;
    self.dimOpacityValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    [settingsView addSubview:self.dimOpacityValueLabel];

    self.dimOpacitySlider = [UISlider new];
    self.dimOpacitySlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimOpacitySlider.minimumValue = 0.0;
    self.dimOpacitySlider.maximumValue = 1.0;
    [self.dimOpacitySlider addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    [settingsView addSubview:self.dimOpacitySlider];

    UILabel *dimAnimationLabel = [UILabel new];
    dimAnimationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    dimAnimationLabel.text = @"Animation mo";
    dimAnimationLabel.font = [UIFont systemFontOfSize:14];
    [settingsView addSubview:dimAnimationLabel];

    self.dimAnimationValueLabel = [UILabel new];
    self.dimAnimationValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimAnimationValueLabel.textAlignment = NSTextAlignmentRight;
    self.dimAnimationValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    [settingsView addSubview:self.dimAnimationValueLabel];

    self.dimAnimationSlider = [UISlider new];
    self.dimAnimationSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimAnimationSlider.minimumValue = 0;
    self.dimAnimationSlider.maximumValue = 2000;
    [self.dimAnimationSlider addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventValueChanged];
    [settingsView addSubview:self.dimAnimationSlider];

    [NSLayoutConstraint activateConstraints:@[
        [settingsView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:18],
        [settingsView.leadingAnchor constraintEqualToAnchor:self.previewImageView.leadingAnchor],
        [settingsView.trailingAnchor constraintEqualToAnchor:self.previewImageView.trailingAnchor],

        [toggleLabel.topAnchor constraintEqualToAnchor:settingsView.topAnchor constant:14],
        [toggleLabel.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:14],
        [self.toggleClickSwitch.centerYAnchor constraintEqualToAnchor:toggleLabel.centerYAnchor],
        [self.toggleClickSwitch.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-14],

        [hideDelayLabel.topAnchor constraintEqualToAnchor:toggleLabel.bottomAnchor constant:18],
        [hideDelayLabel.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:14],
        [self.hideDelayValueLabel.centerYAnchor constraintEqualToAnchor:hideDelayLabel.centerYAnchor],
        [self.hideDelayValueLabel.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-14],
        [self.hideDelayValueLabel.widthAnchor constraintEqualToConstant:80],
        [self.hideDelaySlider.topAnchor constraintEqualToAnchor:hideDelayLabel.bottomAnchor constant:6],
        [self.hideDelaySlider.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:14],
        [self.hideDelaySlider.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-14],

        [showDelayLabel.topAnchor constraintEqualToAnchor:self.hideDelaySlider.bottomAnchor constant:14],
        [showDelayLabel.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:14],
        [self.showDelayValueLabel.centerYAnchor constraintEqualToAnchor:showDelayLabel.centerYAnchor],
        [self.showDelayValueLabel.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-14],
        [self.showDelayValueLabel.widthAnchor constraintEqualToConstant:80],
        [self.showDelaySlider.topAnchor constraintEqualToAnchor:showDelayLabel.bottomAnchor constant:6],
        [self.showDelaySlider.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:14],
        [self.showDelaySlider.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-14],

        [dimOpacityLabel.topAnchor constraintEqualToAnchor:self.showDelaySlider.bottomAnchor constant:14],
        [dimOpacityLabel.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:14],
        [self.dimOpacityValueLabel.centerYAnchor constraintEqualToAnchor:dimOpacityLabel.centerYAnchor],
        [self.dimOpacityValueLabel.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-14],
        [self.dimOpacityValueLabel.widthAnchor constraintEqualToConstant:80],
        [self.dimOpacitySlider.topAnchor constraintEqualToAnchor:dimOpacityLabel.bottomAnchor constant:6],
        [self.dimOpacitySlider.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:14],
        [self.dimOpacitySlider.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-14],

        [dimAnimationLabel.topAnchor constraintEqualToAnchor:self.dimOpacitySlider.bottomAnchor constant:14],
        [dimAnimationLabel.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:14],
        [self.dimAnimationValueLabel.centerYAnchor constraintEqualToAnchor:dimAnimationLabel.centerYAnchor],
        [self.dimAnimationValueLabel.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-14],
        [self.dimAnimationValueLabel.widthAnchor constraintEqualToConstant:80],
        [self.dimAnimationSlider.topAnchor constraintEqualToAnchor:dimAnimationLabel.bottomAnchor constant:6],
        [self.dimAnimationSlider.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:14],
        [self.dimAnimationSlider.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-14],
        [self.dimAnimationSlider.bottomAnchor constraintEqualToAnchor:settingsView.bottomAnchor constant:-14],
        [settingsView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-28],
    ]];
}

- (void)updateState {
    self.previewImageView.image = self.selectedImage;
    self.showButton.enabled = self.selectedImage != nil;
    self.showButton.alpha = self.selectedImage ? 1.0 : 0.45;
    self.deleteButton.enabled = YES;
    self.deleteButton.alpha = 1.0;

    if (self.selectedImage) {
        self.statusLabel.text = [NSString stringWithFormat:@"Da chon anh %.0fx%.0f", self.selectedImage.size.width, self.selectedImage.size.height];
    } else {
        self.statusLabel.text = @"Chua chon anh";
    }
}

- (void)loadSettings {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:kOverlaySettingsPath];
    self.toggleClickSwitch.on = [settings[@"toggleClickEnabled"] boolValue];
    self.hideDelaySlider.value = settings[@"hideDelayMs"] ? [settings[@"hideDelayMs"] floatValue] : 0.0;
    self.showDelaySlider.value = settings[@"showDelayMs"] ? [settings[@"showDelayMs"] floatValue] : 0.0;
    self.dimOpacitySlider.value = settings[@"dimOpacity"] ? [settings[@"dimOpacity"] floatValue] : 1.0;
    self.dimAnimationSlider.value = settings[@"dimAnimationMs"] ? [settings[@"dimAnimationMs"] floatValue] : 0.0;
    [self updateSettingsLabels];
}

- (void)updateSettingsLabels {
    self.hideDelayValueLabel.text = [NSString stringWithFormat:@"%ld ms", (long)self.hideDelaySlider.value];
    self.showDelayValueLabel.text = [NSString stringWithFormat:@"%ld ms", (long)self.showDelaySlider.value];
    self.dimOpacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", self.dimOpacitySlider.value * 100.0];
    self.dimAnimationValueLabel.text = [NSString stringWithFormat:@"%ld ms", (long)self.dimAnimationSlider.value];
}

- (void)settingsChanged {
    [self updateSettingsLabels];
    NSDictionary *settings = @{
        @"toggleClickEnabled": @(self.toggleClickSwitch.on),
        @"hideDelayMs": @((NSInteger)self.hideDelaySlider.value),
        @"showDelayMs": @((NSInteger)self.showDelaySlider.value),
        @"dimOpacity": @(self.dimOpacitySlider.value),
        @"dimAnimationMs": @((NSInteger)self.dimAnimationSlider.value)
    };

    [NSFileManager.defaultManager createDirectoryAtPath:kOverlayDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [settings writeToFile:kOverlaySettingsPath atomically:YES];
    notify_post(kOverlaySettingsNotification);
}

- (void)resetSettingsForNewImage {
    self.toggleClickSwitch.on = NO;
    self.hideDelaySlider.value = 0;
    self.showDelaySlider.value = 0;
    self.dimOpacitySlider.value = 1.0;
    self.dimAnimationSlider.value = 0;
    [self settingsChanged];
}

- (void)registerSettingsNotification {
    if (self.settingsNotifyToken != 0) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(kOverlaySettingsNotification, &_settingsNotifyToken, dispatch_get_main_queue(), ^(__unused int token) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf loadSettings];
    });
}

- (void)chooseImageTapped {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        self.statusLabel.text = @"Khong mo duoc thu vien anh";
        return;
    }

    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.image"];
    picker.allowsEditing = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)setSelectedImageAndStatus:(UIImage *)image status:(NSString *)status {
    self.selectedImage = image;
    self.selectedImageData = image ? [self pngDataForImage:image] : nil;
    [self updateState];
    if (status.length) {
        self.statusLabel.text = status;
    }
}

- (NSData *)pngDataForImage:(UIImage *)image {
    NSData *pngData = UIImagePNGRepresentation(image);
    if (pngData.length) {
        return pngData;
    }

    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:(CGRect){CGPointZero, image.size}];
    UIImage *renderedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return UIImagePNGRepresentation(renderedImage);
}

- (BOOL)writeFallbackFileForImage:(UIImage *)image {
    NSData *pngData = self.selectedImageData ?: [self pngDataForImage:image];
    if (!pngData.length) {
        return NO;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    [fileManager createDirectoryAtPath:kOverlayDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    return [pngData writeToFile:kOverlayImagePath atomically:YES];
}

- (BOOL)publishImageToPasteboard:(UIImage *)image {
    NSData *pngData = self.selectedImageData ?: [self pngDataForImage:image];
    UIPasteboard *pasteboard = [UIPasteboard pasteboardWithName:kOverlayPasteboardName create:YES];
    if (!pasteboard) {
        return NO;
    }

    if (pngData.length) {
        [pasteboard setData:pngData forPasteboardType:@"public.png"];
    }
    pasteboard.image = image;
    return pasteboard.image != nil || pngData.length > 0;
}

- (void)showImageTapped {
    if (!self.selectedImage) {
        return;
    }

    self.statusLabel.text = @"Dang gui anh...";
    [self resetSettingsForNewImage];
    [self clearPublishedImage];

    BOOL wroteFile = [self writeFallbackFileForImage:self.selectedImage];
    BOOL wrotePasteboard = [self publishImageToPasteboard:self.selectedImage];

    if (!wroteFile && !wrotePasteboard) {
        self.statusLabel.text = @"Khong gui duoc anh";
        notify_post(kOverlayRemoveNotification);
        return;
    }

    notify_post(kOverlayUpdatedNotification);
    self.statusLabel.text = @"Da gui anh den overlay";
}

- (void)clearPublishedImage {
    [UIPasteboard removePasteboardWithName:kOverlayPasteboardName];
    [NSFileManager.defaultManager removeItemAtPath:kOverlayImagePath error:nil];
    [NSFileManager.defaultManager removeItemAtPath:kOverlayStatePath error:nil];
}

- (void)deleteImageTapped {
    [self clearPublishedImage];
    self.selectedImage = nil;
    self.selectedImageData = nil;
    [self updateState];
    self.statusLabel.text = @"Da xoa overlay";
    notify_post(kOverlayRemoveNotification);
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (!image) {
        image = info[UIImagePickerControllerEditedImage];
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        if (image) {
            [self setSelectedImageAndStatus:image status:nil];
        } else {
            [self setSelectedImageAndStatus:nil status:@"Tai anh that bai"];
        }
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end
