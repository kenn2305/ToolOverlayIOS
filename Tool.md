# OverlayIOSTOOL v2.0 - Snapper2-style Image Overlay Tweak

Một iOS Jailbreak Tweak hoàn chỉnh cho **iOS 15+** được xây dựng bằng **Theos**, cung cấp khả năng hiển thị hình ảnh trên tất cả các ứng dụng như Snapper2 nhưng với tính năng điều khiển qua ứng dụng companion đơn giản.

## 🎯 Tính Năng Chính

### 1. **Hiển Thị Ảnh Overlay (Snapper2-style)**
- Chọn ảnh từ thư viện Photos
- Hiển thị ảnh gốc mà không có nền hoặc bóng đổ
- Tự động cấp quyền thông qua PHPickerViewController
- Hỗ trợ PNG, JPG với channel alpha (trong suốt)

### 2. **Gesture Controls**
- **Drag (Kéo)**: Di chuyển ảnh tự do trên màn hình
- **Pinch (Nhéo)**: Phóng to/thu nhỏ ảnh mượt mà (0.1x - 10x)
- **Touch Outside**: Toggle ẩn/hiện đan xen với delay

### 3. **Drawing & Annotation (Snapper2-like)**
- ✏️ **Công Cụ Vẽ**: Bật/tắt chế độ vẽ lên overlay
- 🎨 **Màu Sắc Tùy Chỉnh**: Chọn từ 8 màu cơ bản (Đỏ, Xanh, Lá cây, v.v.)
- 🖍️ **Độ Dày Nét Vẽ**: Điều chỉnh từ 1px - 20px
- 🗑️ **Xóa Bản Vẽ**: Xóa tất cả annotation chỉ bằng 1 cú nhấn

### 4. **Tính Năng Khác**
- ⚡ **Bật/Tắt Overlay**: Toggle nhanh các lúc
- 👆 **Toggle Click Mode**: Tự động ẩn/hiện khi chạm bên ngoài ảnh
- 🕐 **Điều Chỉnh Delay**: Tùy chỉnh độ trễ ẩn/hiện (0-2000ms)
- 🔄 **Khôi Phục Vị Trí**: Đặt lại ảnh về giữa màn hình
- 🗑️ **Xóa Hoàn Toàn & Giải Phóng RAM**: Tắt tweak sạch sẽ

## 📂 Cấu Trúc File

```
OverlayIOSTOOL/
├── Tweak.x                    # Mã nguồn Logos (tweak chính)
├── App/
│   ├── ViewController.m       # Giao diện ứng dụng companion
│   ├── ViewController.h       # Header
│   ├── AppDelegate.m          # App initialization
│   └── main.m                 # Entry point
├── Resources/
│   └── Info.plist            # App metadata
├── OverlayIOSTOOL.plist      # Tweak filter (UIKit)
├── control                    # Debian package info
├── Makefile                   # Theos build config
├── build.ps1                  # Windows build script (PowerShell)
├── build_and_install.sh       # macOS/Linux build script
└── Tool.md                    # Tài liệu này
```

## 🏗️ Kiến Trúc Theos

### Tweak Structure (Tweak.x)
1. **OverlayImageWindow**: Cửa sổ custom để hiển thị ảnh, chỉ nhận touch khi chạm vào ảnh (pass-through cho app bên dưới)
2. **DrawingView**: View để vẽ annotation trên top của ảnh
3. **OverlayGestureHandler**: Xử lý Pan & Pinch gesture đồng thời
4. **Darwin Notifications**: IPC giữa app, tweak, và SpringBoard

### IPC via Darwin Notifications

| Notification | Mục Đích |
|---|---|
| `com.vietanh.overlayiostool.updated` | Load settings từ file, update overlay |
| `com.vietanh.overlayiostool.remove` | Xóa overlay hoàn toàn |
| `com.vietanh.overlayiostool.toggle` | Toggle ẩn/hiện ảnh |
| `com.vietanh.overlayiostool.clear_drawing` | Xóa bản vẽ |

### Companion App (OverlayToolApp)
- UIKitNavigationController UI (iOS 15+)
- Chọn ảnh: `PHPickerViewController` (không cần quyền cụ thể)
- Lưu settings: `~/Documents/settings.plist`
- Lưu ảnh: `~/Documents/overlay.png`

## ⚙️ Hướng Dẫn Biên Dịch & Cài Đặt

### Yêu Cầu
- **macOS hoặc Linux hoặc Windows** với WSL/Cygwin
- **Theos** được cài đặt (https://github.com/theos/theos)
- **Xcode Command Line Tools** (macOS)
- **iPhone** đã jailbreak với **Dopamine**
- **OpenSSH** cài trên iPhone (để SSH access)

### Bước 1: Cài Đặt Theos (Nếu Chưa Có)

#### macOS/Linux:
```bash
git clone --recursive https://github.com/theos/theos.git ~/theos
export THEOS=~/theos
```

#### Windows (với WSL):
```bash
# Trong WSL
git clone --recursive https://github.com/theos/theos.git ~/theos
echo 'export THEOS=~/theos' >> ~/.bashrc
source ~/.bashrc
```

### Bước 2: Setup Device IP

```bash
# Terminal
export THEOS_DEVICE_IP=192.168.1.X    # Thay X bằng IP iPhone
export THEOS_DEVICE_PORT=22
export THEOS_DEVICE_USERNAME=root
export THEOS_DEVICE_PASSWORD=alpine   # Mật khẩu SSH mặc định
```

### Bước 3: Build & Install

#### macOS/Linux:
```bash
cd /path/to/OverlayIOSTOOL
./build_and_install.sh
```

#### Windows (PowerShell):
```powershell
cd C:\path\to\OverlayIOSTOOL
$env:THEOS = "C:\theos"
$env:THEOS_DEVICE_IP = "192.168.1.X"
.\build.ps1
```

#### Manual (mọi OS):
```bash
make package FINALPACKAGE=1
make install
```

## 📱 Cách Sử Dụng

### Trên iPhone

1. **Mở OverlayToolApp** từ Home Screen
2. **Chọn ảnh** → Nhấn "Chọn Ảnh Từ Thư Viện"
3. **Bật Overlay** → Toggle "⚡ Bật Overlay"
4. **Điều Chỉnh**:
   - 👆 Bật "Toggle Click" để ẩn/hiện tự động
   - 🕐 Điều chỉnh delay ẩn/hiện
   - ✏️ Bật "Công Cụ Vẽ" để vẽ annotation
   - 🎨 Chọn màu sắc
   - 🖍️ Điều chỉnh độ dày nét
5. **Xử Dụng**:
   - Kéo ảnh: Drag với 1 ngón tay
   - Zoom: Pinch với 2 ngón tay
   - Ẩn/Hiện: Chạm bất kỳ nơi nào ngoài ảnh (nếu bật Toggle)
   - Vẽ: Chạm vào ảnh để vẽ (nếu bật Công Cụ Vẽ)

### Trên Jailbreak

Overlay sẽ **luôn nổi** trên tất cả các ứng dụng:
- Safari, Facebook, Instagram, TikTok, v.v. đều thấy ảnh overlay
- Không ảnh hưởng performance
- Tắt trong app companion hoặc từ Settings > Tweaks

## 🔧 Dopamine Compatibility

### Cấu Hình Cho Dopamine (Rootless)

1. **THEOS_PACKAGE_SCHEME = rootless** ✓ (Đã set trong Makefile)
2. **Target iOS**: 15.0+ (hỗ trợ rootless)
3. **Frameworks**: UIKit, CoreGraphics, QuartzCore, AVFoundation
4. **Bundle ID**: `com.vietanh.overlayiostool`

### Kiểm Tra Cài Đặt

```bash
# SSH vào iPhone
ssh root@192.168.1.X

# Kiểm tra tweak
ls -la /Library/MobileSubstrate/DynamicLibraries/ | grep -i overlay

# Kiểm tra app
ls -la /Applications/ | grep -i overlay

# Xem logs
tail -f /var/log/syslog
```

## ⚠️ Troubleshooting

### Build Error: "THEOS not found"
```bash
export THEOS=/path/to/theos
# Hoặc thêm vào ~/.bashrc / ~/.zshrc
```

### Device Connection Failed
```bash
# Kiểm tra IP
ping 192.168.1.X

# Test SSH
ssh -v root@192.168.1.X

# Đặt lại mật khẩu SSH
# Trên iPhone: Settings > SSH > Reset Password
```

### Tweak Not Loaded
```bash
# Kiểm tra filter
cat /Library/MobileSubstrate/DynamicLibraries/OverlayIOSTOOL.plist

# Restart SpringBoard
killall SpringBoard

# Hoặc respring từ app companion
```

### App Không Launch
```bash
# Kiểm tra quyền
chmod 755 /Applications/OverlayToolApp.app

# Rebuild app
make package FINALPACKAGE=1 && make install
```

## 🔒 Quyền & Privacy

- ✓ **Không cần Photo Library permission** (dùng PHPickerViewController)
- ✓ **Không cần Network** (toàn bộ local)
- ✓ **Không ghi dữ liệu ra ngoài** (chỉ ~/Documents/)
- ✓ **Rootless-safe** (Dopamine 2.x+)

## 📝 Notes

- Ảnh được lưu dưới dạng **PNG full resolution** trong `~/Documents/overlay.png`
- Settings lưu trong `~/Documents/settings.plist`
- Overlay window **luôn chạy trong SpringBoard** (không flicker khi chuyển app)
- Drawing layer **render real-time** trên top của image
- Xóa bản vẽ không xóa ảnh gốc

## 🚀 Sắp Tới

- [ ] Screenshot capture from SpringBoard
- [ ] Multiple image layers
- [ ] Shape tools (rectangle, circle, arrow)
- [ ] Undo/Redo for drawing
- [ ] Export drawn image
- [ ] Custom color picker

## 📧 Support

Nếu gặp issue, vui lòng:
1. Kiểm tra logs: `tail -f /var/log/syslog | grep -i overlay`
2. Rebuild tweak: `make clean && make package FINALPACKAGE=1`
3. Reinstall: `make install`

---

**Version**: 2.0.0  
**Last Updated**: 2024  
**Author**: Viet Anh  
**License**: MIT  
**Jailbreak**: Dopamine 2.x+ (rootless iOS 15+)
