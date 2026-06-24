# Cách đọc log để tìm lỗi "overlay không hiện ngoài app"

Bản 5.9.2 ghi log vào file:

```
/var/mobile/Library/OverlayIOSTOOL/tweak.log
```

**Chỉ SpringBoard mới ghi file này.** Nên: nếu sau khi respring + bấm "Hiển thị" mà file
này KHÔNG tồn tại → tweak chưa hề chạy trong SpringBoard (đây đã là một manh mối lớn).

## Cách mở log

### Cách 1 — Filza (dễ nhất, không cần máy tính)
1. Mở **Filza**.
2. Vào đường dẫn: `/var/mobile/Library/OverlayIOSTOOL/`
3. Mở `tweak.log` (chạm → Text Viewer).
4. Kéo xuống cuối để xem dòng mới nhất.

### Cách 2 — SSH (từ máy tính)
```
ssh mobile@<IP-iPhone>
cat /var/mobile/Library/OverlayIOSTOOL/tweak.log
```

### Cách 3 — idevicesyslog qua USB (xem log của CẢ app + tiến trình relay)
Trên Windows, cài libimobiledevice rồi:
```
idevicesyslog.exe | findstr OverlayIOSTOOL
```
Lệnh này xem được cả log của app tool và hook trong app khác (những thứ không ghi vào file).

## Quy trình test chuẩn
1. Cài bản `OverlayIOSTOOL_5.9.2_rootless_arm64.deb` (Dopamine) → respring.
2. Mở app **OverlayIOSTOOL** → Chọn ảnh → bấm **Hiển thị**.
3. Bấm nút Home/vuốt ra màn hình chính, rồi mở 1 app khác.
4. Mở `tweak.log` đọc theo bảng dưới.

## Đọc kết quả (cây quyết định)

| Log thấy được | Nghĩa là | Hướng xử lý |
|---|---|---|
| **File `tweak.log` KHÔNG tồn tại** | Tweak không nạp vào SpringBoard | ElleKit không nạp dylib arm64 vào SpringBoard arm64e → cần build arm64e, hoặc tweak bị tắt trong app quản lý jb |
| `[ctor] CRASH-GUARD chan!` | Tweak tự tắt do SpringBoard từng crash | Xoá file `/var/mobile/Library/OverlayIOSTOOL/disabled-after-crash` rồi respring |
| `[ctor] dylib DA NAP` nhưng KHÔNG có `host SAN SANG` | Chưa kịp khởi tạo | Đợi vài giây/respring rồi đọc lại |
| Bấm Hiển thị nhưng KHÔNG có `Nhan notification 'image-updated'` | Lệnh không tới SpringBoard | App không post được notify, hoặc SB chưa đăng ký |
| `KHONG doc duoc anh ...` | SB không đọc được file ảnh | Sai đường dẫn/quyền (báo mình ngay) |
| `KHONG co UIWindowScene` + `dung initWithFrame` | SpringBoard không cấp scene | Đã tự fallback; xem dòng tiếp theo |
| `WINDOW SAN SANG ...` + `Overlay HIEN ... windowHidden=0` **nhưng mắt vẫn không thấy** | Cửa sổ tạo ra OK nhưng KHÔNG nổi trên app | Cần đổi kỹ thuật nổi (windowLevel/layer) — báo mình, mình chỉnh tiếp |

## Gửi mình cái gì
Copy **toàn bộ nội dung** `tweak.log` (hoặc chụp màn hình) sau khi làm quy trình test,
đặc biệt các dòng từ lúc bấm "Hiển thị" trở đi. Mình sẽ biết chính xác kẹt ở bước nào.
