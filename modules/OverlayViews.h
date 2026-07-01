@implementation OverlayPassthroughView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    // Trong UIView subclass, "rootView" chính là container này (self).

    if (gQuickActionsVisible) {
        return hitView ?: self;
    }

    if (gScaleLockModeEnabled) {
        // Viền xanh: bắt toàn màn. Nếu chạm trúng UI con (slider/toolbar/nút, ảnh) thì
        // trả về nó để nhận chạm; vùng trống trả về root (xử lý chọn/kéo trong sendEvent).
        if (!hitView || hitView == self) {
            return self;
        }
        return hitView;
    }

    // KHÔNG viền xanh: chỉ NHẬN chạm khi NGÓN nằm TRÊN ảnh ĐANG HIỆN RÕ (chưa mờ). Ảnh
    // đang MỜ/ẩn (gOverlayDimmed) coi như KHÔNG có ở đó -> chạm xuyên xuống app + relay
    // (để hitbox của ảnh khác kích hoạt). Chạm ngoài ảnh cũng xuyên xuống app.
    if (gOverlayVisible && !gOverlayDimmed) {
        UIImageView *active = activeImageView();
        if (active && !active.hidden) {
            CGPoint imagePoint = [active convertPoint:point fromView:self];
            if ([active pointInside:imagePoint withEvent:event]) {
                return active;
            }
        }
    }

    if (hitView == self) {
        // Vùng trống của container -> để touch xuyên xuống app bên dưới.
        return nil;
    }
    return hitView;
}

@end

// Cửa sổ host (SpringBoard) ở windowLevel rất cao để NỔI trên mọi app + màn hình
// chính. Vùng trống trả về nil -> touch xuyên xuống app bên dưới (giống AssistiveTouch).
@interface OverlayHostWindow : UIWindow
@end

@implementation OverlayHostWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // Nếu không có view con nào nhận (chạm vào vùng trống) -> super trả về chính
    // window. Chuyển thành nil để hệ thống chuyển touch xuống app foreground.
    if (hit == self) {
        return nil;
    }
    return hit;
}

@end

@interface OverlayGestureHandler : NSObject <UIGestureRecognizerDelegate>
@end

static OverlayGestureHandler *gGestureHandler = nil;

// Heartbeat: ghi trạng thái app hiện tại vào pasteboard "báo danh" để app tool đọc.
// status: "loaded" (tweak đã vào app), "img-ok" (đọc được ảnh + đã vẽ), "no-img"
// (vào được nhưng chưa có ảnh trên pasteboard).
