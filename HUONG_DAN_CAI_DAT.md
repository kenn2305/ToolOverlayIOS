# HƯỚNG DẪN CÀI ĐẶT TỪ A ĐẾN Z — OverlayIOSTOOL

Tài liệu này hướng dẫn **từ máy trắng** đến lúc tool chạy trên iPhone.

- Máy build: **Windows 10/11** (dùng WSL Ubuntu).
- iPhone: **đã Jailbreak**, **iOS 14.0 – 16.x**, mọi dòng máy (iPhone 6s → 16).
  Hỗ trợ **cả rootless lẫn rootful** (Dopamine, unc0ver, checkra1n, palera1n...).

> Tool gồm 2 phần, đóng trong **1 file `.deb`**: tweak overlay (chạy nền) + app
> "Overlay Tool" (để chọn ảnh, chỉnh cài đặt).

---

## PHẦN 1 — Chuẩn bị máy Windows (làm 1 lần)

### 1.1 Cài WSL + Ubuntu
Mở **PowerShell** bằng **Run as Administrator**, chạy:
```powershell
wsl --install -d Ubuntu-22.04
```
- Khởi động lại máy nếu được yêu cầu.
- Mở **Ubuntu** từ Start Menu 1 lần, đợi nó cài xong, đặt **username/password** bất kỳ (nhớ để dùng sau).

Kiểm tra đã có WSL:
```powershell
wsl -l -v
```
Thấy `Ubuntu-22.04` là được.

> Bước này cần Internet (tải Ubuntu). Sau khi xong, nếu dùng bản **bundle offline**
> thì các bước build **không cần mạng nữa**.

---

## PHẦN 2 — Lấy project về máy

Chọn **một** trong hai cách:

### Cách A — Tải từ GitHub (khuyến nghị, cần mạng lần đầu)
1. Vào https://github.com/kenn2305/ToolOverlayIOS
2. Bấm **Code ▾ → Download ZIP**, giải nén ra (ví dụ) `E:\OverlayIOSTOOL`.
   (Hoặc dùng git: `git clone https://github.com/kenn2305/ToolOverlayIOS.git`)
3. Lần đầu bấm `BUILD.cmd`, nó **tự tải bundle môi trường (~650MB) từ Releases** rồi
   build. Các lần sau không tải lại.

### Cách B — Nhận folder kèm bundle (build OFFLINE, không cần mạng)
1. Nhận **nguyên thư mục project** (gồm thư mục `buildenv\` ~650MB) qua USB/ổ cứng/Drive.
2. Đặt vào ổ đĩa, ví dụ `E:\OverlayIOSTOOL`.
3. Vì đã có sẵn môi trường trong `buildenv\`, build **không cần Internet**.

> `BUILD.cmd` tự xử lý: có `buildenv\` → build offline; chưa có → tự tải từ Releases;
> nếu không tải được (mất mạng) → tự chuyển build online.

---

## PHẦN 3 — Build ra file .deb

1. Mở thư mục project trong File Explorer.
2. **Double-click `BUILD.cmd`**.
3. Đợi (lần đầu vài phút). Khi xong, cửa sổ `packages\` tự mở, chứa **2 file**:
   ```
   OverlayIOSTOOL_5.8.0_rootless_arm64-arm64e.deb   (Dopamine, XinaA15...)
   OverlayIOSTOOL_5.8.0_rootful_arm64-arm64e.deb    (unc0ver, checkra1n, palera1n-rootful)
   ```
Nếu báo `[LOI] May nay chua co WSL` → quay lại Phần 1.

---

## PHẦN 4 — Cài .deb lên iPhone (máy đã Jailbreak)

**Chọn đúng file theo loại jailbreak:**
- Jailbreak **rootless** (Dopamine, XinaA15) → dùng file **`...rootless...deb`**
- Jailbreak **rootful** (unc0ver, checkra1n, palera1n rootful) → dùng file **`...rootful...deb`**
- Không chắc? Bản **rootless** cho iOS 15–16 máy mới; bản **rootful** cho iOS 14 hoặc palera1n.

Chép file `.deb` đã chọn vào iPhone rồi cài bằng **một** trong các cách:

### Cách 1 — Sileo / Zebra (dễ nhất)
1. Chép `.deb` vào iPhone (AirDrop, hoặc app Files, hoặc Filza).
2. Mở **Filza**, tới file `.deb`, bấm vào → **Install / Cài đặt**.
3. Bấm **Respring** (khởi động lại giao diện) khi xong.

### Cách 2 — Dòng lệnh (SSH)
```bash
# trên máy tính, copy file ĐÚNG LOẠI (rootless hoặc rootful) vào iPhone
scp OverlayIOSTOOL_5.8.0_rootless_arm64-arm64e.deb root@<IP_iPhone>:/var/mobile/
# SSH vào iPhone
ssh root@<IP_iPhone>
dpkg -i /var/mobile/OverlayIOSTOOL_5.8.0_rootless_arm64-arm64e.deb
killall SpringBoard
```

Sau khi cài, trên Home Screen sẽ có app **Overlay Tool**.

---

## PHẦN 5 — Cách sử dụng

1. Mở app **Overlay Tool**.
2. Bấm **Chon anh** → chọn ảnh từ thư viện.
3. Bấm **Hien thi** → ảnh overlay xuất hiện, nổi trên mọi app.
4. Thao tác trên ảnh overlay:
   - **1 ngón kéo**: di chuyển ảnh.
   - **2 ngón chụm**: phóng to / thu nhỏ.
   - **Giữ ~1 giây** lên ảnh: bật/tắt chế độ **khoá tỉ lệ** (hiện bảng chỉnh delay, độ mờ...).
   - **Chạm nhanh** lên ảnh: mở bảng Số dư (nạp/rút).
5. Tắt overlay: trong app bấm **Xoa anh**.

> Khoá màn hình: overlay **tự ẩn** và **hiện lại** khi mở khoá (ảnh không bị mất).

---

## KHẮC PHỤC SỰ CỐ

| Hiện tượng | Cách xử lý |
|---|---|
| `BUILD.cmd` báo chưa có WSL | Làm Phần 1 (cài WSL Ubuntu), khởi động lại máy |
| Build báo `[LỖI]` và dừng | Đọc dòng lỗi — script chỉ dừng khi thật sự thiếu; làm đúng dòng nó báo rồi chạy lại |
| Build online lỗi mạng | Thử lại khi mạng ổn, hoặc dùng Cách B (bundle offline) |
| Cài .deb xong không thấy app | Respring (killall SpringBoard) hoặc khởi động lại máy |
| Treo táo sau khi cài | Tool có cơ chế tự tắt sau 3 lần lỗi/120s; đợi máy tự vào lại. Nếu vẫn kẹt, vào chế độ không-tweak của bản JB để gỡ |
| Overlay không hiện | Mở app bấm **Hien thi** lại; đảm bảo đã chọn ảnh |

---

## Yêu cầu tương thích (đã kiểm tra)

- Tweak build **arm64 + arm64e** → chạy mọi chip A8 → A18 (iPhone 6s → 16).
- **minOS 14.0**, khoá **iOS 14.0–16.x** (`firmware >= 14.0, << 17.0`).
- Xuất **2 bản**: **rootless** (/var/jb) + **rootful** (/) → hợp mọi loại jailbreak.
- Có crash-guard chống treo táo (tự tắt sau 3 lần lỗi/120s).
