# 📦 v2.0.1 Release - Debug Build

## 🎯 Mục Đích

Build này được tạo để debug vấn đề: **"Bấm chọn ảnh nó không chọn, không có ảnh nào được hiển thị lên overlay"**

Tất cả mã có thêm **logging chi tiết** để truy tìm vị trí xảy ra lỗi.

---

## 📝 Những Thay Đổi

### **1. App (ViewController.m)**

#### Tự động tạo Documents folder
```objc
// OLD: Chỉ lấy path
return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;

// NEW: Lấy path + tạo folder nếu chưa tồn tại
[[NSFileManager defaultManager] createDirectoryAtPath:docsPath withIntermediateDirectories:YES attributes:nil error:nil];
```

#### Thêm logging toàn diện
```objc
NSLog(@"[OverlayToolApp] Image loaded: %@, size: %.0f x %.0f", image, image.size.width, image.size.height);
NSLog(@"[OverlayToolApp] Saving image to: %@", imagePath);
NSLog(@"[OverlayToolApp] Image saved: %@", writeSuccess ? @"SUCCESS" : @"FAILED");
NSLog(@"[OverlayToolApp] Image file exists: %@", fileExists ? @"YES" : @"NO");
```

#### Error handling
```objc
if (!pngData) {
    NSLog(@"[OverlayToolApp] Failed to convert image to PNG");
    return;
}

if (!writeSuccess) {
    NSLog(@"[OverlayToolApp] Failed to write image to %@", imagePath);
    return;
}
```

### **2. Tweak (Tweak.x)**

#### Logging khi tweak được load
```objc
NSLog(@"[OverlayIOSTool] Tweak loaded in bundle: %@", g_ownBundleID);
NSLog(@"[OverlayIOSTool] Is SpringBoard: %@", @(g_isSpringBoard));
```

#### Logging khi setupOverlay() được gọi
```objc
NSLog(@"[OverlayIOSTool] setupOverlay called");
NSLog(@"[OverlayIOSTool] Image path: %@", imagePath);
BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
NSLog(@"[OverlayIOSTool] Image file exists at %@: %@", imagePath, fileExists ? @"YES" : @"NO");
NSLog(@"[OverlayIOSTool] Image loaded: %@, size: %.0f x %.0f", image, image ? image.size.width : 0, image ? image.size.height : 0);
```

#### Logging Darwin notifications
```objc
NSLog(@"[OverlayIOSTool] NOTIF_UPDATED received, calling setupOverlay");
NSLog(@"[OverlayIOSTool] NOTIF_REMOVE received, removing overlay");
NSLog(@"[OverlayIOSTool] NOTIF_CLEAR_DRAWING received, clearing drawing");
```

---

## 🔧 Cách Sử Dụng

### **Step 1: Cài Đặt Package**

```bash
# Xóa package cũ
ssh root@<IP> "apt-get remove -y com.vietanh.overlayiostool"

# Cài package mới
scp com.vietanh.overlayiostool_2.0.0_iphoneos-arm64.deb root@<IP>:/tmp/
ssh root@<IP> "dpkg -i /tmp/com.vietanh.overlayiostool_2.0.0_iphoneos-arm64.deb"

# Refresh UI + respring
ssh root@<IP> "uicache"
ssh root@<IP> "killall -9 SpringBoard"
```

### **Step 2: Thu Thập Logs**

**Phương pháp A - Nhanh nhất (SSH Terminal):**

```bash
# Terminal 1: Mở SSH và stream logs
ssh root@<IP>
log stream --predicate 'message contains "OverlayIOSTool"' --level debug

# Terminal 2: Trên Mac, cài app và test
# Hoặc trên iPhone, mở OverlayToolApp
```

**Phương pháp B - Lưu vào file:**

```bash
# SSH vào iPhone
ssh root@<IP>

# Lưu logs vào archive
log collect --output overlay_logs_$(date +%Y%m%d_%H%M%S).logarchive

# Copy về Mac
scp root@<IP>:overlay_logs*.logarchive ~/Desktop/

# Extract trên Mac
log show overlay_logs*.logarchive > overlay_debug.txt
```

**Phương pháp C - Auto script:**

```bash
# Copy script vào iPhone
scp debug_quick_start.sh root@<IP>:~/

# Chạy script (nó sẽ tự stream logs)
ssh root@<IP> "bash ~/debug_quick_start.sh"
```

### **Step 3: Reproduce Issue**

Khi stream logs đang chạy:

1. Mở app **OverlayToolApp** trên iPhone
2. Tap button **"Chọn Ảnh"**
3. Chọn 1 ảnh từ Photos
4. Quan sát logs xuất hiện
5. Xem ảnh có hiển thị trên overlay không

### **Step 4: Gửi Report**

Copy-paste logs + gửi kèm:

**Required:**
- Toàn bộ logs (từ khi tap "Chọn Ảnh" đến khi reload)
- Device: iPhone model + iOS version

**Optional:**
- Screenshot app UI
- Screenshot của PHPickerViewController
- File size của overlay.png (nếu được tạo):
  ```bash
  ssh root@<IP> "find /var/mobile/Containers -name 'overlay.png' -exec ls -lah {} \;"
  ```

---

## 🔍 Cách Đọc Logs

### **Good Path** ✅

```
[OverlayToolApp] Selected item provider: <PHAssetResource: ...>
[OverlayToolApp] Item provider can load UIImage
[OverlayToolApp] Image loaded: <UIImage: ...>, size: 1080 x 1920
[OverlayToolApp] Saving image to: /var/mobile/Containers/Data/Application/.../overlay.png
[OverlayToolApp] Image saved: SUCCESS
[OverlayToolApp] Image file exists: YES
[OverlayToolApp] Settings saved to ...: SUCCESS

[OverlayIOSTool] NOTIF_UPDATED received, calling setupOverlay
[OverlayIOSTool] setupOverlay called
[OverlayIOSTool] Settings loaded: isEnabled=1
[OverlayIOSTool] Image path: /var/mobile/Containers/...
[OverlayIOSTool] Image file exists at ...: YES
[OverlayIOSTool] Image loaded: <UIImage: ...>, size: 1080 x 1920
[OverlayIOSTool] Creating overlay window
```

### **Bad Path** ❌

#### Scenario 1: PHPickerViewController không load được image
```
[OverlayToolApp] Selected item provider: ...
[OverlayToolApp] Item provider CANNOT load UIImage  ← ❌
```
→ PHPickerFilter configuration issue

#### Scenario 2: Image save failed
```
[OverlayToolApp] Image saved: FAILED  ← ❌
[OverlayToolApp] Failed to write image to ...
```
→ Permission issue hoặc không đủ space

#### Scenario 3: Tweak không nhận notification
```
[OverlayToolApp] Settings saved: SUCCESS
[OverlayToolApp] Overlay enabled and settings saved
(❌ Không thấy "[OverlayIOSTool] NOTIF_UPDATED received")
```
→ notify_post() hoặc Darwin notification issue

#### Scenario 4: File path mismatch
```
[OverlayToolApp] Image file exists: YES
[OverlayIOSTool] Image file exists at ...: NO  ← ❌
```
→ App và Tweak dùng khác path

---

## 📊 Build Info

- **Version**: 2.0.1-debug
- **Build Date**: June 13, 2024
- **Package Size**: 34.7 KB
- **Architectures**: arm64, arm64e
- **Compatibility**: iOS 15+ (Dopamine)

---

## 📚 Documentation Files

1. **DEBUG_GUIDE_VI.md** - Hướng dẫn debug chi tiết (5 scenarios, lệnh hữu ích)
2. **debug_quick_start.sh** - Script auto stream logs trên iPhone
3. **CHANGELOG.md** - Lịch sử tất cả thay đổi
4. **Tool.md** - Tài liệu kiến trúc chi tiết

---

## ⚡ Quick Commands Reference

```bash
# Stream logs real-time
log stream --predicate 'message contains "OverlayIOSTool"' --level debug

# Filter app logs only
log stream --predicate 'process == "OverlayToolApp"' --level debug

# Filter tweak logs only (SpringBoard)
log stream --predicate 'process == "SpringBoard" AND message contains "OverlayIOSTool"' --level debug

# Find app Documents path
find /var/mobile/Containers/Data/Application -name 'overlay.png' 2>/dev/null

# Check file size
ls -lah /var/mobile/Containers/Data/Application/*/Documents/overlay.png

# View settings plist
cat /var/mobile/Containers/Data/Application/*/Documents/settings.plist

# Restart app
killall -9 OverlayToolApp

# Restart SpringBoard
killall -9 SpringBoard

# Reinstall package
dpkg -i --force-all /tmp/com.vietanh.overlayiostool_2.0.0_iphoneos-arm64.deb
uicache
```

---

## 🆘 Nếu Vẫn Gặp Vấn Đề

1. **Collect comprehensive logs**: `log collect --output overlay_logs.logarchive`
2. **Copy to Mac**: `scp root@<IP>:overlay_logs.logarchive ~/Desktop/`
3. **Extract**: `log show overlay_logs.logarchive > overlay_debug.txt`
4. **Share**: Send `overlay_debug.txt` + device info + screenshots

---

**Status**: ✅ Ready for testing  
**Last Updated**: 2024-06-13  
**Contact**: For issues, attach full DEBUG_GUIDE_VI.md output + logs
