/**
 * OverlayIOSTOOL - entry point. Code da tach theo module trong thu muc modules/.
 * File nay CHI giu phan Logos (%hook/%ctor) vi bo tien xu ly Logos KHONG quet file
 * #import. Cac module include dung THU TU goc -> don vi bien dich giong het truoc.
 */
#import "modules/OverlayCommon.h"
#import "modules/OverlayViews.h"
#import "modules/OverlayProcess.h"
#import "modules/OverlayState.h"
#import "modules/OverlayDisplay.h"
#import "modules/OverlayWindow.h"
#import "modules/OverlayStateApply.h"
#import "modules/OverlaySettings.h"
#import "modules/OverlayImageIO.h"
#import "modules/OverlayLifecycle.h"
#import "modules/OverlayHitbox.h"
#import "modules/OverlayScaleLock.h"
#import "modules/OverlayGestures.h"

%group OverlayUIApplicationHooks

%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    if (!gOverlayProcessEnabled) {
        %orig(event);
        // App relay: gửi TOẠ ĐỘ cú chạm sang SpringBoard khi NHẢ TAY (Ended) -> kích hoạt
        // lúc thả tay, không phải lúc chạm. SpringBoard biết vị trí ảnh/hitbox nên tự quyết.
        if (gAppTouchRelayEnabled && event.type == UIEventTypeTouches) {
            for (UITouch *touch in event.allTouches) {
                if (touch.phase == UITouchPhaseEnded) {
                    if (overlayToggleActiveForApp()) {
                        CGPoint p = [touch locationInView:nil];   // toạ độ cửa sổ = màn hình (app full-screen)
                        uint32_t xi = (uint32_t)MAX(0.0, p.x);
                        uint32_t yi = (uint32_t)MAX(0.0, p.y);
                        uint64_t packed = ((uint64_t)xi << 32) | (uint64_t)yi;
                        if (gAppTouchLocToken != 0) {
                            notify_set_state(gAppTouchLocToken, packed);
                        }
                        notify_post(kOverlayAppTouchNotification);
                    }
                    break;
                }
            }
        }
        return;
    }

    BOOL quickActionsWereVisible = gQuickActionsVisible;

    if (event.type == UIEventTypeTouches && gScaleLockModeEnabled && gOverlayImageView) {
        BOOL overlayTouch = NO;
        for (UITouch *touch in event.allTouches) {
            if (gOverlayRoot && (touch.view == gOverlayRoot || [touch.view isDescendantOfView:gOverlayRoot])) {
                overlayTouch = YES;
                break;
            }
        }

        if (!overlayTouch) {
            return;
        }

        %orig(event);
        overlayHandleScaleLockSelect(event);   // viền xanh: chạm để CHỌN ảnh/hitbox
        overlayHandleManualPan(event);         // viền xanh: kéo 1 ngón -> dời phần tử đang chọn
        overlayHandleManualLongPress(event);   // viền xanh: giữ-lâu TRÊN ẢNH -> thoát
        return;
    }

    %orig(event);

    if (quickActionsWereVisible || gQuickActionsVisible) {
        return;
    }

    handleHiddenImageDoubleTapIfNeeded(event);

    // Chế độ thường: giữ-lâu 1 ngón trên ảnh -> vào viền xanh; tap trên ảnh -> panel.
    // (Bỏ nhúm 2 ngón phóng to: ảnh chỉ chỉnh kích thước trong viền xanh bằng 2 thanh X/Y.)
    overlayHandleManualLongPress(event);
    overlayHandleManualTap(event);
}

%end

%end

%ctor {
    @autoreleasepool {
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
        gIsSpringBoardProcess = [bundleIdentifier isEqualToString:@"com.apple.springboard"];
        if (gIsSpringBoardProcess) {
            overlayLog(@"[ctor] dylib DA NAP vao SpringBoard (bat dau)");
        }
        if (gIsSpringBoardProcess && springBoardCrashGuardShouldDisable()) {
            overlayLog(@"[ctor] CRASH-GUARD chan! (co file disabled-after-crash hoac SpringBoard vua crash lien tuc) -> tweak TU TAT trong SpringBoard");
            return;
        }
        gOverlayProcessEnabled = shouldEnableOverlayInCurrentProcess();
        gAppTouchRelayEnabled = !gOverlayProcessEnabled && shouldRelayAppTouches();
        if (!gOverlayProcessEnabled && !gAppTouchRelayEnabled) {
            return;
        }

        %init(OverlayUIApplicationHooks);

        // App relay: chỉ cần hook sendEvent + token đọc state. KHÔNG vẽ, KHÔNG đọc file.
        if (gAppTouchRelayEnabled) {
            notify_register_check(kOverlayToggleActiveState, &gAppToggleStateToken);
            notify_register_check(kOverlayAppTouchLocState, &gAppTouchLocToken);
            NSLog(@"[OverlayIOSTOOL] App touch relay in %@", bundleIdentifier ?: NSProcessInfo.processInfo.processName);
            return;
        }

        overlayLog(@"[ctor] host khoi tao xong, cho DidBecomeActive + retry");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gObserversInstalled) {
                return;
            }
            gObserversInstalled = YES;

            // BÁO DANH NGAY khi dylib nạp (không chờ app active) -> app tool thấy
            // ngay "loaded" để biết tweak ĐÃ vào app này.
            reportAppStatus(@"loaded");

            // DÙNG CHUỖI LITERAL thay cho hằng số import của UIKit. Crash log cho thấy
            // PAC-crash xảy ra đúng tại `[name copy]` trên hằng số NSString import
            // (UIApplicationDidBecomeActiveNotification...). Giá trị của các hằng này
            // BẰNG đúng tên symbol -> dùng @"..." là chuỗi của TA, không import -> né
            // hẳn điểm crash (lớp phòng thủ kèm với clang 13).
            [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidBecomeActiveNotification"
                                                              object:nil
                                                               queue:NSOperationQueue.mainQueue
                                                          usingBlock:^(__unused NSNotification *notification) {
                activateOverlayHost();
            }];
            if (gIsSpringBoardProcess) {
                [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationProtectedDataWillBecomeUnavailable"
                                                                  object:nil
                                                                   queue:NSOperationQueue.mainQueue
                                                              usingBlock:^(__unused NSNotification *notification) {
                    gDataUnavailable = YES;          // khoá máy -> chỉ ẩn, giữ ảnh
                    refreshOverlayWindowVisibility();
                }];
                [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationProtectedDataDidBecomeAvailable"
                                                                  object:nil
                                                                   queue:NSOperationQueue.mainQueue
                                                              usingBlock:^(__unused NSNotification *notification) {
                    gDataUnavailable = NO;           // mở khoá -> hiện lại
                    refreshOverlayWindowVisibility();
                }];
            }
        });

        // KÍCH HOẠT DỰ PHÒNG + thử lại tới ~24s: app có thể đã ACTIVE trước khi
        // observer kịp thêm, hoặc ảnh được đăng muộn -> thử lại liên tục cho chắc.
        scheduleActivationRetry(0);
    }
}
