# Build Offline 1-Click — Máy khách bấm 1 nút ra file .deb

Toàn bộ môi trường (Theos + iOS toolchain arm64e + iOS SDK 16.5 + ldid + gói
apt) được gói sẵn trong `buildenv/`. Máy khách **không cần cài Theos, không cần
internet** để build — chỉ cần WSL Ubuntu rồi **bấm `BUILD.cmd`**.

---

## A. TRÊN MÁY BẠN — tạo bundle (1 lần, cần internet)

Đã có sẵn môi trường ở `/home/builder/theos` trong WSL. Chỉ cần đóng gói:

```powershell
wsl --cd /mnt/e/OverlayIOSTOOL -u root -- bash tools/pack-build-env.sh
```

Ra file: `buildenv/OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz`

---

## B. GỬI CHO MÁY KHÁCH

Copy **nguyên thư mục** `OverlayIOSTOOL\` (gồm cả `buildenv\`, `BUILD.cmd`,
`build-offline.sh`). Gửi qua USB / ổ cứng / Google Drive (file ~1GB nên không
gửi qua GitHub được).

---

## C. TRÊN MÁY KHÁCH — bấm 1 nút

### Điều kiện 1 lần duy nhất: có WSL Ubuntu
Nếu máy khách **chưa có WSL**, mở **PowerShell (Run as Administrator)** chạy:
```powershell
wsl --install -d Ubuntu-22.04
```
Khởi động lại máy, mở Ubuntu 1 lần để nó hoàn tất cài (đặt user/pass bất kỳ).
> Bước này cần mạng để tải Ubuntu. Sau đó việc build hoàn toàn offline.

### Build:
**Double-click `BUILD.cmd`** trong thư mục project.
- Lần đầu: tự giải nén môi trường vào WSL rồi build (vài phút).
- Các lần sau: build thẳng, nhanh.
- Xong: tự mở thư mục `packages\` chứa file **`.deb`**.

Copy file `.deb` vào iPhone JB → cài bằng Filza/Sileo (hoặc `dpkg -i file.deb`).

---

## Vì sao "không thiếu gì / không lỗi"

| Thành phần | Trong bundle |
|---|---|
| Theos + makefiles | ✅ |
| iOS toolchain arm64e (đã verify ELF thật) | ✅ |
| iOS SDK 16.5 (deploy target 15.0 → chạy iOS 15–16) | ✅ |
| ldid (ký app → app mở được) | ✅ |
| fakeroot, dpkg-dev, ... (cài offline) | ✅ |

`build-offline.sh` tự kiểm tra: toolchain phải thật, có `.deb`, dylib phải đủ
`arm64 + arm64e`. Sai bất kỳ đâu là **dừng báo lỗi rõ ràng**, không bao giờ ra
file hỏng (chống treo táo / app không mở được).

---

## Giới hạn

- Bundle là **Linux x86_64** → dùng cho **WSL Ubuntu / Linux x86_64**. Không
  dùng cho macOS hay Windows ARM.
- File bundle (~1GB) bị `.gitignore` loại khỏi git — phải gửi riêng, không qua
  GitHub.
