/**
 * OverlayIOSTOOL - SpringBoard visual host with guarded app proxies.
 *
 * The companion app publishes a selected image through a named pasteboard and
 * posts a Darwin notification. SpringBoard is the only process that renders
 * the image; user apps get a guarded transparent proxy for input forwarding.
 * Hooks are initialized only after process validation to avoid system UIKit
 * process crash loops on arm64e/Dopamine.
 */

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <unistd.h>
#import <string.h>
#import <stdio.h>

static NSString * const kOverlayDirectory = @"/var/mobile/Library/OverlayIOSTOOL";
static NSString * const kOverlayImagePath = @"/var/mobile/Library/OverlayIOSTOOL/overlay.png";
static NSString * const kOverlayImage2Path = @"/var/mobile/Library/OverlayIOSTOOL/overlay2.png";
static NSString * const kOverlaySettingsPath = @"/var/mobile/Library/OverlayIOSTOOL/settings.plist";
static NSString * const kOverlayStatePath = @"/var/mobile/Library/OverlayIOSTOOL/state.plist";
static NSString * const kOverlayPasteboardName = @"com.vietanh.overlayiostool.image";
static NSString * const kOverlayPasteboard2Name = @"com.vietanh.overlayiostool.image2";
// Pasteboard "báo danh": mỗi app tweak chạy vào ghi 1 dòng "<bundleid> <status>"
// -> app tool đọc để biết tweak ĐÃ vào app nào (chẩn đoán, không phải đoán mò).
static NSString * const kOverlayActiveAppsPasteboard = @"com.vietanh.overlayiostool.active-apps";
static const char *kOverlayUpdatedNotification = "com.vietanh.overlayiostool.image-updated";
static const char *kOverlayRemoveNotification = "com.vietanh.overlayiostool.image-remove";
static const char *kOverlayUpdated2Notification = "com.vietanh.overlayiostool.image2-updated";
static const char *kOverlayRemove2Notification = "com.vietanh.overlayiostool.image2-remove";
static const char *kOverlaySettingsNotification = "com.vietanh.overlayiostool.settings-updated";
static const char *kOverlayStateNotification = "com.vietanh.overlayiostool.state-updated";
static const char *kOverlayDepositActionNotification = "com.vietanh.overlayiostool.action.deposit";
static const char *kOverlayWithdrawActionNotification = "com.vietanh.overlayiostool.action.withdraw";
// Toggle-click xuyên app: app phát hiện chạm + gửi TOẠ ĐỘ -> SpringBoard tự quyết
// (trúng ảnh -> panel nạp/rút; ngoài ảnh -> dim) vì app không biết vị trí ảnh.
static const char *kOverlayAppTouchNotification = "com.vietanh.overlayiostool.app-touch";
// Kênh state mang toạ độ chạm (x<<32 | y, theo điểm màn hình) từ app sang SpringBoard.
static const char *kOverlayAppTouchLocState = "com.vietanh.overlayiostool.app-touch-loc";
// Kênh state (notify_set_state/get_state, không dính sandbox) để app biết có cần relay.
static const char *kOverlayToggleActiveState = "com.vietanh.overlayiostool.toggle-active";
static const char *kOverlayRealtimeSocketPath = "/var/mobile/Library/OverlayIOSTOOL/realtime.sock";
static const uint32_t kOverlayRealtimeMagic = 0x4F495254;

// Hằng số font-weight CỦA TA (không phải symbol import UIKit) — tránh PAC-crash khi
// arm64e clang 11 truy cập hằng số import. Giá trị bằng đúng UIFontWeight* của Apple.
static const CGFloat kOverlayFontWeightRegular = 0.0;     // = UIFontWeightRegular
static const CGFloat kOverlayFontWeightSemibold = 0.3;    // = UIFontWeightSemibold

static BOOL gOverlayHostReady = NO;
static BOOL gToggleClickEnabled = NO;
static BOOL gOverlayVisible = YES;
static BOOL gOverlayDimmed = NO;
static BOOL gScaleLockModeEnabled = NO;
static BOOL gApplyingRemoteState = NO;
static BOOL gIsSpringBoardProcess = NO;
static BOOL gOverlayProcessEnabled = NO;
static BOOL gAppTouchRelayEnabled = NO;
static BOOL gObserversInstalled = NO;
static BOOL gQuickActionsVisible = NO;
static BOOL gScreenBlanked = NO;
static BOOL gScreenLocked = NO;
static BOOL gDataUnavailable = NO;
static BOOL gManualPinchActive = NO;        // đang nhúm 2 ngón (tự tính, không qua recognizer)
static CGFloat gManualPinchInitialDistance = 0;
static CGSize gManualPinchInitialBounds = {0, 0};
static BOOL gLongPressTracking = NO;        // đang đếm giờ giữ-lâu 1 ngón (tự tính)
static BOOL gLongPressConsumed = NO;        // đã toggle bằng lần giữ này -> chờ nhấc tay
static int gLongPressGeneration = 0;
static CGPoint gLongPressStart = {0, 0};
static BOOL gTapCandidate = NO;             // chạm 1 ngón, có thể là tap (mở panel / dim)
static BOOL gTapOnImage = NO;               // tap đó bắt đầu TRÊN ảnh hay ngoài ảnh
static CGPoint gTapStart = {0, 0};
static BOOL gManualPanActive = NO;          // đang kéo 1 ngón di chuyển ảnh (viền xanh, tự tính)
static CGPoint gManualPanLast = {0, 0};
static NSUInteger gToggleGeneration = 0;
static NSInteger gHideDelayMs = 300;
static NSInteger gShowDelayMs = 300;
static NSInteger gDimAnimationMs = 0;
static CGFloat gDimOpacity = 1.0;
static CFTimeInterval gLastRealtimeStateSync = 0;
static int gRealtimeClientSocket = -1;
static CFSocketRef gRealtimeServerSocket = NULL;
static CFRunLoopSourceRef gRealtimeServerSource = NULL;
static __weak UIWindow *gOverlayHostWindow = nil;
static UIWindow *gOverlayWindow = nil;
@class OverlayPassthroughView;
static OverlayPassthroughView *gOverlayRoot = nil;
static UIImageView *gOverlayImageView = nil;     // ẢNH 1 (bắt buộc)
static UIImageView *gOverlayImageView2 = nil;    // ẢNH 2 (tùy chọn, có thể nil)
static NSInteger gActiveImageIndex = 0;          // chế độ thường: ảnh đang HIỆN (0/1). -1 = không
static NSInteger gEditingImageIndex = 0;         // viền xanh: ảnh đang FOCUS để chỉnh (0/1)
static UIControl *gQuickActionsBackdrop = nil;
static UIView *gQuickActionsPanel = nil;
static UIButton *gQuickActionsCancelButton = nil;
static UIView *gScaleLockControlsPanel = nil;
static UISlider *gOverlayHideDelaySlider = nil;
static UISlider *gOverlayShowDelaySlider = nil;
static UISlider *gOverlayDimOpacitySlider = nil;
static UISlider *gOverlayDimAnimationSlider = nil;
static UILabel *gOverlayHideDelayValueLabel = nil;
static UILabel *gOverlayShowDelayValueLabel = nil;
static UILabel *gOverlayDimOpacityValueLabel = nil;
static UILabel *gOverlayDimAnimationValueLabel = nil;
static UIButton *gToggleClickButton = nil;
static UIButton *gHideImageButton = nil;
static UIPanGestureRecognizer *gImagePanGesture = nil;    // pan ảnh 1 (chế độ thường)
static UIPanGestureRecognizer *gImagePanGesture2 = nil;   // pan ảnh 2 (chế độ thường)
static UIPinchGestureRecognizer *gImagePinchGesture = nil;
static UILongPressGestureRecognizer *gImageLongPressGesture = nil;
static UITapGestureRecognizer *gQuickActionsTapGesture = nil;
static UIPinchGestureRecognizer *gExpandedPinchGesture = nil;
static UIPanGestureRecognizer *gRelativePanGesture = nil;
static UITapGestureRecognizer *gInputBlockTapGesture = nil;
static int gNotifyToken = 0;
static int gRemoveToken = 0;
static int gNotify2Token = 0;
static int gRemove2Token = 0;
static int gSettingsToken = 0;
static int gStateToken = 0;
static int gBlankedScreenToken = 0;
static int gLockStateToken = 0;
static int gAppTouchToken = 0;          // SpringBoard: nhận tín hiệu chạm từ app
static int gSbToggleStateToken = 0;     // SpringBoard: set state toggle-active
static int gAppToggleStateToken = 0;    // App: đọc state toggle-active
static int gAppTouchLocToken = 0;       // App: set toạ độ chạm; SpringBoard: đọc toạ độ chạm

// ===== HITBOX =====
// Hitbox = vùng "trigger" trong toạ độ root (màn hình). type 0 = Hiện (ảnh đang mờ ->
// rõ), type 1 = Mờ (ảnh đang rõ -> mờ). Tàng hình ở chế độ thường, hiện + chỉnh ở viền
// xanh. Tối đa 8 mỗi loại.
static NSString * const kOverlayHitboxesPath = @"/var/mobile/Library/OverlayIOSTOOL/hitboxes.plist";
static const NSInteger kOverlayMaxHitboxesPerType = 8;
static NSMutableArray<NSMutableDictionary *> *gHitboxes = nil;   // dữ liệu {type,x,y,w,h}
static NSMutableArray<UIView *> *gHitboxViews = nil;             // ô hiển thị (viền xanh)
static NSInteger gSelectedIndex = -1;   // -1 = ảnh, >=0 = chỉ số hitbox đang chọn
static UISlider *gSizeXSlider = nil;     // chiều RỘNG (cạnh dưới)
static UISlider *gSizeYSlider = nil;     // chiều CAO (cạnh phải)
static UIView *gHitboxToolbar = nil;     // thanh +Hiện / +Mờ / Xoá / Xong
static UIView *gImageFocusBar = nil;     // thanh chọn focus "Ảnh 1" / "Ảnh 2" (chỉ khi có ảnh 2)
static UIButton *gFocusImage1Button = nil;
static UIButton *gFocusImage2Button = nil;

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t version;
    uint32_t kind;
    double x;
    double y;
    double width;
    double height;
    double dimOpacity;
    double dimAnimationMs;
    uint8_t visible;
    uint8_t dimmed;
    uint8_t scaleLock;
} OverlayRealtimeMessage;

@interface OverlayPassthroughView : UIView
@end

static void refreshOverlayWindowVisibility(void);
static void updateScaleLockControlsVisibility(void);
static void updateOverlayControlValues(void);
static UIWindowScene *foregroundOverlayScene(void);
static void applyScaleLockMode(BOOL enabled);
static void persistOverlayState(BOOL broadcast);
static void loadHitboxes(void);
static void saveHitboxes(void);
static void clearAllHitboxes(void);
static void rebuildHitboxViews(void);
static void updateHitboxEditUIForSelection(void);
static void applyOverlayDimmed(BOOL dimmed);
static void applyActiveImageDisplay(void);
static void scheduleShowImage(NSInteger index, BOOL dimmed);

// ===== ĐA-ẢNH: bộ truy cập =====
// Ảnh theo chỉ số (0 = ảnh 1 bắt buộc, 1 = ảnh 2 tùy chọn). Trả nil nếu chưa có.
static inline UIImageView *imageViewAtIndex(NSInteger index) {
    if (index == 0) return gOverlayImageView;
    if (index == 1) return gOverlayImageView2;
    return nil;
}
// Ảnh đang HIỆN ở chế độ thường.
static inline UIImageView *activeImageView(void) {
    return imageViewAtIndex(gActiveImageIndex);
}
// Ảnh đang FOCUS để chỉnh trong viền xanh.
static inline UIImageView *editingImageView(void) {
    return imageViewAtIndex(gEditingImageIndex);
}
static inline BOOL hasSecondImage(void) {
    return gOverlayImageView2 != nil;
}

static NSString * const kOverlayLogPath = @"/var/mobile/Library/OverlayIOSTOOL/tweak.log";

// Ghi log ra file để đọc bằng Filza (chỉ SpringBoard ghi file -> nếu file KHÔNG
// tồn tại nghĩa là tweak chưa hề chạy trong SpringBoard). Mọi tiến trình vẫn NSLog.
static void overlayLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[OverlayIOSTOOL] %@", msg);

    if (!gIsSpringBoardProcess) {
        return;  // app thứ ba bị sandbox chặn ghi -> chỉ NSLog
    }

    @try {
        NSString *line = [NSString stringWithFormat:@"%.3f SB %@\n",
                          NSDate.date.timeIntervalSince1970, msg];
        [NSFileManager.defaultManager createDirectoryAtPath:kOverlayDirectory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kOverlayLogPath];
        if (!handle) {
            [line writeToFile:kOverlayLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    } @catch (__unused id exception) {
    }
}

