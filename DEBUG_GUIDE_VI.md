# 🔍 Hướng dẫn Debug - Vấn đề Chọn Ảnh & Hiển Thị Overlay

## Tóm tắt Sửa Chữa

Build v2.0.1 này chứa **logging toàn diện** để debug vấn đề "bấm chọn ảnh nó không chọn không có ảnh nào được hiển thị lên overlay".

### Những Thay Đổi Trong v2.0.1:

#### 1. **App ViewController.m** - Cải thiện xử lý ảnh:
   - ✅ Tự động **tạo Documents folder** nếu chưa tồn tại
   - ✅ Thêm **NSLog chi tiết** ở mỗi bước:
     - Khi PHPickerViewController được presents
     - Khi image được load
     - Khi image được convert thành PNG
     - Khi ảnh được save vào file
     - Xác nhận file tồn tại sau khi save
   - ✅ Error handling: Báo lỗi nếu ảnh load thất bại hoặc save thất bại

#### 2. **Tweak.x** - Debug overlay creation:
   - ✅ NSLog khi tweak được load
   - ✅ NSLog khi setupOverlay() được gọi
   - ✅ NSLog khi image path được lấy
   - ✅ Kiểm tra file tồn tại trước khi load
   - ✅ NSLog khi image được load từ file
   - ✅ NSLog khi Darwin notification được nhận
   - ✅ NSLog khi overlay window được tạo

---

## Cách Thu Thập Logs

### **Phương Pháp 1: SSH từ Mac/Linux (Khuyên Dùng)**

```bash
# 1. SSH vào iPhone qua Dopamine SSH
ssh root@<IP_IPHONE>

# 2. Xem logs real-time (tất cả processes)
log stream --predicate 'message contains "OverlayIOSTool"' --level debug

# 3. Hoặc filter theo process cụ thể:
# - App logs:
log stream --predicate 'process == "OverlayToolApp" AND message contains "OverlayIOSTool"' --level debug

# - Tweak logs (SpringBoard):
log stream --predicate 'process == "SpringBoard" AND message contains "OverlayIOSTool"' --level debug

# 4. Copy toàn bộ logs từ hôm nay:
log collect --output ~/overlay_logs_$(date +%Y%m%d_%H%M%S).logarchive
scp -r root@<IP_IPHONE>:~/overlay_logs*.logarchive ~/Desktop/
```

### **Phương Pháp 2: Xcode Console (Nếu Có Mac)**

```
1. Xcode → Window → Devices and Simulators
2. Chọn iPhone
3. Klik biểu tượng ▶ (Open Console)
4. Filter: OverlayIOSTool
5. Tap "Chọn Ảnh" trong OverlayToolApp
6. Copy toàn bộ logs
```

### **Phương Pháp 3: Console.app (Mac)**

```
1. Console.app → Chọn iPhone device
2. Action → Include System Logs
3. Tìm "OverlayIOSTool"
4. Tap "Chọn Ảnh" trong app
5. Theo dõi logs real-time
```

### **Phương Pháp 4: iCloud Logs (Nếu App Crash)**

```
iPhone Settings → Privacy & Security → Analytics & Improvements
→ Analytics Data → Tìm OverlayToolApp → Copy logs
```

---

## Quy Trình Debug Step-by-Step

### **Step 1: Cài Đặt v2.0.1 Mới**

```bash
# Xóa version cũ trước
ssh root@<IP_IPHONE> "apt-get remove -y com.vietanh.overlayiostool"
ssh root@<IP_IPHONE> "rm -rf /Applications/OverlayToolApp.app"
ssh root@<IP_IPHONE> "rm -rf /var/mobile/Containers/Data/Application/*/Documents/overlay.png"

# Cài v2.0.1
scp com.vietanh.overlayiostool_2.0.0_iphoneos-arm64.deb root@<IP_IPHONE>:/tmp/
ssh root@<IP_IPHONE> "dpkg -i /tmp/com.vietanh.overlayiostool_2.0.0_iphoneos-arm64.deb"
ssh root@<IP_IPHONE> "uicache"

# Respring để tweak được load
ssh root@<IP_IPHONE> "killall -9 SpringBoard"
```

### **Step 2: Kiểm Tra Tweak Được Load**

Mở SSH terminal và chạy:
```bash
log stream --predicate 'message contains "Tweak loaded in bundle"' --level debug
```

**Mong đợi log:**
```
[OverlayIOSTool] Tweak loaded in bundle: com.apple.springboard
[OverlayIOSTool] Is SpringBoard: 1
[OverlayIOSTool] Registering Darwin notification observers
[OverlayIOSTool] Initial setupOverlay call after 1.5s
[OverlayIOSTool] setupOverlay called
```

Nếu **KHÔNG thấy logs**: Tweak chưa được load → Kiểm tra `/var/lib/dpkg/info/` và reinstall

### **Step 3: Kiểm Tra Companion App**

Mở App "OverlayToolApp" và chạy:
```bash
log stream --predicate 'process == "OverlayToolApp"' --level debug
```

**Mong đợi log:**
```
[OverlayToolApp] Settings loaded at startup
```

Nếu **KHÔNG thấy**: App đã crash → Kiểm tra `/var/log/system.log`

### **Step 4: Test Chọn Ảnh (Critical)**

Trong SSH terminal chạy:
```bash
log stream --predicate 'message contains "OverlayIOSTool" AND (message contains "Image" OR message contains "picker")' --level debug
```

Rồi ở app, tap "Chọn Ảnh" button, chọn 1 cái ảnh từ Photos.

**Mong đợi logs:**

**From App:**
```
[OverlayToolApp] User cancelled image picker
  OR
[OverlayToolApp] Selected item provider: <PHAssetResource: 0x...>
[OverlayToolApp] Item provider can load UIImage
[OverlayToolApp] Image loaded: <UIImage: 0x...>, size: 3024 x 4032
[OverlayToolApp] Saving image to: /var/mobile/Containers/Data/Application/<UUID>/Documents/overlay.png
[OverlayToolApp] Image saved: SUCCESS
[OverlayToolApp] Image file exists: YES
[OverlayToolApp] UI updated with image preview
[OverlayToolApp] Settings loaded at startup
[OverlayToolApp] Settings saved to /var/mobile/Containers/Data/Application/<UUID>/Documents/settings.plist: SUCCESS
```

**From Tweak (SpringBoard):**
```
[OverlayIOSTool] NOTIF_UPDATED received, calling setupOverlay
[OverlayIOSTool] setupOverlay called
[OverlayIOSTool] Settings loaded: isEnabled=1
[OverlayIOSTool] Image path: /var/mobile/Containers/Data/Application/<UUID>/Documents/overlay.png
[OverlayIOSTool] Image file exists at ...: YES
[OverlayIOSTool] Image loaded: <UIImage: 0x...>, size: 3024 x 4032
[OverlayIOSTool] Creating overlay window
```

---

## Các Kịch Bản Debug Phổ Biến

### ❌ **Kịch Bản 1: "Image picker không hiển thị ảnh"**

**Logs sẽ thấy:**
```
[OverlayToolApp] Selected item provider: ...
[OverlayToolApp] Item provider CANNOT load UIImage  ← ❌ BUG
```

**Nguyên nhân**: PHPickerConfiguration không match với ảnh được select

**Fix**: Thay `PHPickerFilter imagesFilter` thành wildcard filter

---

### ❌ **Kịch Bản 2: "Image save thất bại"**

**Logs sẽ thấy:**
```
[OverlayToolApp] Image loaded: <UIImage: ...>
[OverlayToolApp] Saving image to: ...
[OverlayToolApp] Image saved: FAILED  ← ❌ BUG
[OverlayToolApp] Failed to write image to /var/.../overlay.png
```

**Nguyên nhân**: 
- Không có quyền write vào Documents folder
- Folder chưa được tạo (v2.0.1 đã fix)
- UIImagePNGRepresentation() trả về nil

**Fix**: Kiểm tra quyền file: `ls -la /var/mobile/Containers/Data/Application/<UUID>/Documents/`

---

### ❌ **Kịch Bản 3: "Tweak không load ảnh"**

**Logs sẽ thấy:**
```
[OverlayIOSTool] Settings loaded: isEnabled=1
[OverlayIOSTool] Image path: /var/.../overlay.png
[OverlayIOSTool] Image file exists at ...: NO  ← ❌ BUG
[OverlayIOSTool] Image loaded: (null), size: 0 x 0
[OverlayIOSTool] Failed to load image from ..., removing overlay
```

**Nguyên nhân**:
- App và Tweak dùng khác path (LSApplicationProxy bundle ID sai)
- File permission issue
- File bị corrupt

**Fix**: So sánh path ở app logs và tweak logs

---

### ❌ **Kịch Bản 4: "Darwin notification không được nhận"**

**Logs sẽ thấy:**
```
[OverlayToolApp] Settings saved: SUCCESS
[OverlayToolApp] Overlay enabled and settings saved
(❌ KHÔNG thấy "[OverlayIOSTool] NOTIF_UPDATED received")
```

**Nguyên nhân**:
- notify_post() thất bại
- SpringBoard không lắng nghe notification

**Fix**: Kiểm tra SpringBoard có running: `ssh root@<IP> "ps aux | grep SpringBoard"`

---

### ❌ **Kịch Bản 5: "Overlay window không hiện"**

**Logs sẽ thấy:**
```
[OverlayIOSTool] Image loaded: <UIImage: ...>
[OverlayIOSTool] Creating overlay window
(❌ Overlay không hiện trên screen)
```

**Nguyên nhân**:
- g_imageWindow.hidden = YES
- Window không được added vào scene
- hitTest vô tình chặn touch

**Fix**: Kiểm tra `g_imageWindow.isKeyWindow`

---

## Lệnh Hữu Ích

```bash
# Xem documents path của app
ssh root@<IP> "find /var/mobile/Containers -name 'overlay.png' 2>/dev/null"

# Xem file size & timestamp
ssh root@<IP> "ls -lah /var/mobile/Containers/Data/Application/*/Documents/overlay.png"

# Xem settings.plist content
ssh root@<IP> "cat /var/mobile/Containers/Data/Application/*/Documents/settings.plist"

# Xem tweak được load trong springboard
ssh root@<IP> "grep -a 'OverlayIOSTool' /Library/MobileSubstrate/DynamicLibraries/OverlayIOSTool.plist" 2>/dev/null || echo "Check if .plist exists"

# Clear app logs
ssh root@<IP> "log erase --all"

# Restart SpringBoard
ssh root@<IP> "killall -9 SpringBoard"

# Restart app
ssh root@<IP> "killall -9 OverlayToolApp"
```

---

## Gửi Debug Report

Khi gửi report, vui lòng bao gồm:

1. **Logs từ Step 2-4 trên** (copy-paste từ console)
2. **File paths** (so sánh app path vs tweak path)
3. **Screenshots** của:
   - App UI (trước khi tap "Chọn Ảnh")
   - Photo picker (khi select ảnh)
   - Settings page
4. **Device info**:
   ```bash
   ssh root@<IP> "uname -a"
   ssh root@<IP> "cat /etc/os-release"
   ssh root@<IP> "dpkg -l | grep overlay"
   ```

---

## Nếu Vẫn Không Hoạt Động

Nếu sau khi thực hiện tất cả các bước trên mà vẫn gặp vấn đề, vui lòng:

1. **Collect logs từ tất cả processes**: `log collect --output overlay_logs.logarchive`
2. **Copy logs**: `scp root@<IP>:overlay_logs.logarchive ~/Desktop/`
3. **Unzip**: `cd ~/Desktop && log show overlay_logs.logarchive > overlay_logs.txt`
4. **Gửi file `overlay_logs.txt`** cùng với debug report

---

**Status**: ✅ v2.0.1 - Ready for debugging
**Last Updated**: 2024 Jun 13
