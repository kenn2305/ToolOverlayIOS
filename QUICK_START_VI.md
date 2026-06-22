# 🚀 HƯỚNG DẪN NHANH - OverlayIOSTOOL v2.0

## Bước 1️⃣: Chuẩn Bị

### Trên Mac/Linux:
```bash
# Cài Theos
git clone --recursive https://github.com/theos/theos.git ~/theos

# Thiết lập môi trường
echo 'export THEOS=~/theos' >> ~/.zshrc  # hoặc ~/.bashrc
source ~/.zshrc
```

### Trên Windows:
1. Cài WSL2 + Ubuntu
2. Chạy các lệnh trên trong WSL

## Bước 2️⃣: Biên Dịch

### Tìm IP iPhone:
- Settings > Wi-Fi > Chọn Wi-Fi hiện tại > Bấn vào thông tin > Tìm IP

### Biên Dịch & Cài:

**Mac/Linux:**
```bash
cd /path/to/OverlayIOSTOOL
export THEOS_DEVICE_IP=192.168.1.XX  # Thay XX
./build_and_install.sh
```

**Windows (PowerShell):**
```powershell
cd C:\OverlayIOSTOOL
$env:THEOS = "C:\theos"
$env:THEOS_DEVICE_IP = "192.168.1.XX"
.\build.ps1
```

## Bước 3️⃣: Sử Dụng

1. **Mở OverlayToolApp** trên iPhone
2. **Nhấn "Chọn Ảnh Từ Thư Viện"**
3. **Chọn ảnh** → OK
4. **Bật "⚡ Bật Overlay"**
5. Xong! Ảnh sẽ hiển thị ở tất cả ứng dụng

## 🎮 Điều Khiển

| Hành Động | Mô Tả |
|---------|-------|
| Kéo 1 ngón | Di chuyển ảnh |
| Pinch 2 ngón | Zoom in/out |
| Chạm bên ngoài ảnh | Toggle ẩn/hiện (nếu bật) |
| Chạm vào ảnh + vẽ | Vẽ annotation (nếu bật) |

## ⚙️ Cài Đặt Chính

- **⚡ Bật Overlay**: Bật/tắt hình ảnh
- **👆 Toggle Click**: Tự động ẩn/hiện khi chạm
- **✏️ Công Cụ Vẽ**: Vẽ annotation
- **🎨 Màu sắc**: Chọn từ 8 màu
- **🖍️ Độ dày nét**: 1-20 pixels
- **🕐 Thời gian ẩn/hiện**: 0-2000ms

## ✔️ Kiểm Tra Cài Đặt

```bash
# SSH vào iPhone
ssh root@192.168.1.XX

# Kiểm tra tweak được cài chưa
ls /Library/MobileSubstrate/DynamicLibraries/ | grep -i overlay

# Kiểm tra app
ls /Applications/ | grep -i overlay
```

## 🆘 Fix Lỗi Thường Gặp

### Overlay không hiển thị:
```bash
# SSH vào iPhone
killall SpringBoard
```

### Không thể connect SSH:
1. iPhone > Settings > SSH > Bật SSH
2. iPhone > Settings > SSH > Reset Password (nếu cần)
3. Thử lại: `ssh root@192.168.1.XX`

### Build error:
```bash
make clean
make package FINALPACKAGE=1
```

## 📱 Dopamine Jailbreak Support

✅ Hỗ trợ đầy đủ Dopamine 2.x+ (rootless)
✅ iOS 15, 16, 17, 18
✅ Không cần file system rw-mount

---

**Cần giúp?** Xem [Tool.md](Tool.md) để tài liệu chi tiết.
