# Hướng dẫn dành cho AI Agent (Tác vụ: Build & Chỉnh sửa dự án)

> [!IMPORTANT]
> Đây là tài liệu tóm tắt kiến trúc của dự án OverlayIOSTOOL. Bất kỳ Agent nào tiếp quản dự án này trong tương lai đều phải đọc kỹ để không làm vỡ kiến trúc hoặc gặp lại các lỗi Sandbox/Entitlements cũ.

## 1. Môi trường Build
- Hệ điều hành: Chạy thông qua **WSL (Windows Subsystem for Linux)**.
- Script build: `do_build.sh` nằm ở thư mục gốc của dự án.
- Câu lệnh chính xác để kích hoạt build (sử dụng user `builder` trong WSL):
  ```bash
  wsl -e bash -c "su - builder -c 'bash /mnt/e/OverlayIOSTOOL/do_build.sh'"
  ```

## 2. Kiến trúc Dự án (Snapper 2 Style)
Dự án được chia làm 2 thành phần hoạt động song song để tạo ra trải nghiệm Overlay mượt mà, không bị nháy khi chuyển App.

### A. Companion App (`OverlayToolApp`)
- Vị trí: `/App/`
- Vai trò: Là một ứng dụng hệ thống cài đặt vào `/Applications`. Chứa giao diện người dùng để chọn ảnh và bật tắt tính năng.
- **Lưu ý về Sandbox (RẤT QUAN TRỌNG):**
  - Tuyệt đối **KHÔNG** sử dụng file `entitlements.plist` với cờ `com.apple.private.security.no-container` hay `no-sandbox` cho App.
  - Lý do: Việc gỡ Sandbox sẽ làm phá vỡ cơ chế truyền file qua XPC của `PHPickerViewController` (iOS 15+), khiến quá trình chọn ảnh thất bại hoàn toàn.
  - App phải được lưu file ảnh (`overlay.png`) và cài đặt (`settings.plist`) vào **chính thư mục Documents mặc định** của nó.

### B. Tweak (`OverlayIOSTOOL.dylib`)
- Vị trí: `Tweak.x`
- Vai trò: Xử lý hiển thị ảnh và lắng nghe thao tác Touch.
- **Kiến trúc phân luồng (Logic Hooking):**
  1. **Luồng SpringBoard (`com.apple.springboard`):** 
     - Chỉ duy nhất process này được phép tạo cửa sổ hiển thị (`UIWindowLevelAlert + 10000`).
     - Nó dùng `LSApplicationProxy` để chủ động lấy đường dẫn tới thư mục `Documents` của Companion App, từ đó đọc `overlay.png` và `settings.plist`. Việc này giúp vượt qua rào cản Sandbox mà không cần thiết lập quyền phức tạp.
     - Luồng này chứa các tính năng Pinch (thu phóng) và Pan (kéo thả).
  2. **Luồng UIKit (`com.apple.UIKit`):** 
     - Được tiêm vào **mọi ứng dụng**.
     - Không vẽ bất kỳ giao diện nào. Chỉ dùng để hook `-[UIApplication sendEvent:]` nhằm bắt thao tác chạm của người dùng ra ngoài bức ảnh.
     - Khi phát hiện thao tác chạm ngoài, luồng này gửi Darwin Notification (`com.vietanh.overlayiostool.toggle`) về cho SpringBoard để thực hiện hiệu ứng Fade ẩn/hiện.

## 3. Quá trình đóng gói (Packaging)
- **Đóng gói file Debian:**
  Được định nghĩa trong `Makefile`. Cần đảm bảo sử dụng `dpkg-deb` với thuật toán nén `xz` (hoặc `gzip`) thông qua `dm.pl` của Theos để tương thích tốt nhất với Sileo.
- **Postinst Script:**
  File `postinst` hiện tại chỉ chứa `uicache -p /Applications/OverlayToolApp.app`. Không cần thiết phải tạo các thư mục Sandbox chia sẻ như các phiên bản trước do kiến trúc mới đã tự động hóa việc đọc dữ liệu qua App Proxy.

## 4. Gợi ý Debug
- Nếu Tweak không hiện, hãy kiểm tra lại Bundle ID trong `LSApplicationProxy` có khớp với App (`com.vietanh.overlaytoolapp`) không.
- Nếu App không hiện ảnh sau khi chọn, hãy đảm bảo App không bị gắn Entitlements can thiệp vào Container.

Chúc may mắn!
