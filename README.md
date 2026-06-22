# 📸 OverlayIOSTOOL v2.0

**Snapper2-style Image Overlay Tweak for Jailbroken iOS**

A powerful iOS 15+ jailbreak tweak that displays images as floating overlays on your home screen and apps, with full pan/pinch gesture support, drawing tools, and color annotation features - fully compatible with **Dopamine jailbreak**.

---

## ✨ Features

### 🖼️ Image Overlay Display
- Pick images from Photos library
- Display with transparent background (PNG alpha channel)
- Always-on-top floating window (no flickering between apps)
- Original image resolution support

### ✋ Gesture Controls
- **Pan**: Drag images freely across the screen
- **Pinch**: Zoom in/out (0.1x - 10x)
- **Tap**: Toggle visibility outside image area

### ✏️ Drawing & Annotation
- **Draw Mode**: Toggle annotation drawing on/off
- **8 Colors**: Red, Blue, Green, Yellow, Purple, Cyan, Gray, White
- **Variable Width**: Adjust line thickness (1-20px)
- **Clear Drawing**: Remove annotations with one tap

### ⚙️ Advanced Controls
- **Toggle Visibility**: Auto-hide/show on tap (with customizable delay)
- **Delay Settings**: Configure hide/show delay (0-2000ms)
- **Reset Position**: Restore image to center with original size
- **Companion App**: Full-featured control app on home screen

---

## 🚀 Quick Start

### Requirements
- iPhone/iPad with **iOS 15+**
- **Dopamine** jailbreak installed
- **OpenSSH** on device
- Theos installed on build machine
- Mac, Linux, or Windows (WSL)

### Build & Install

**Mac/Linux:**
```bash
cd /path/to/OverlayIOSTOOL
export THEOS_DEVICE_IP=192.168.X.X
./build_and_install.sh
```

**Windows (PowerShell):**
```powershell
$env:THEOS = "C:\theos"
$env:THEOS_DEVICE_IP = "192.168.X.X"
.\build.ps1
```

### First Use
1. Tap **OverlayToolApp** on home screen
2. Tap "**Pick Image From Library**"
3. Select an image
4. Toggle "**⚡ Enable Overlay**"
5. Done! Image appears on screen

---

## 🎮 Controls

| Gesture | Action |
|---------|--------|
| 1-finger drag | Move image |
| 2-finger pinch | Zoom in/out |
| Tap outside image | Toggle visibility (if enabled) |
| Draw on image | Annotate (if drawing mode on) |

---

## ⚙️ App Settings

| Setting | Range | Default |
|---------|-------|---------|
| Enable Overlay | ON/OFF | ON |
| Toggle Click Mode | ON/OFF | OFF |
| Hide Delay (ms) | 0-2000 | 300 |
| Show Delay (ms) | 0-2000 | 300 |
| Drawing Mode | ON/OFF | OFF |
| Line Width | 1-20 px | 2 |
| Color | 8 colors | Red |

---

## 📱 System Architecture

### Tweak Components

**SpringBoard-only Rendering:**
- All UI elements run exclusively in SpringBoard
- No app-specific drawing (no flickering when switching apps)
- Ultra-high window level (`UIWindowLevelAlert + 10000`)

**Drawing View:**
- Custom `DrawingView` class for annotations
- Real-time brush stroke rendering
- Supports multiple simultaneous touches

**IPC via Darwin Notifications:**
- `com.vietanh.overlayiostool.updated` - Reload settings
- `com.vietanh.overlayiostool.remove` - Remove overlay
- `com.vietanh.overlayiostool.toggle` - Toggle visibility
- `com.vietanh.overlayiostool.clear_drawing` - Clear annotations

### Companion App
- **Bundle ID**: `com.vietanh.overlaytoolapp`
- **Location**: `/Applications/OverlayToolApp.app`
- **UIKit-based**: Responsive iOS 15+ design
- **Storage**: `~/Documents/overlay.png` + `settings.plist`

---

## 🔧 Building from Source

### System Requirements
- **Theos**: https://github.com/theos/theos
- **Xcode Command Line Tools** (macOS)
- **iOS SDK** 15.0+

### Build Steps

1. **Clone Theos** (if not installed):
```bash
git clone --recursive https://github.com/theos/theos.git ~/theos
export THEOS=~/theos
```

2. **Set Device IP**:
```bash
export THEOS_DEVICE_IP=192.168.X.X
```

3. **Build Package**:
```bash
make package FINALPACKAGE=1
```

4. **Install to Device**:
```bash
make install
```

---

## 📖 Documentation

- **[Tool.md](Tool.md)** - Comprehensive Vietnamese documentation
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and updates
- **[QUICK_START_VI.md](QUICK_START_VI.md)** - Vietnamese quick start guide
- **[AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md)** - Developer notes

---

## 🆘 Troubleshooting

### Overlay not appearing?
```bash
ssh root@192.168.X.X
killall SpringBoard
```

### Can't install package?
1. Check `THEOS_DEVICE_IP` is correct
2. Verify SSH access: `ssh root@192.168.X.X`
3. Rebuild: `make clean && make package FINALPACKAGE=1`

### Drawing not working?
- Ensure "✏️ Drawing Mode" is enabled
- Check color selection is visible
- Restart SpringBoard: `killall SpringBoard`

### Companion app won't launch?
```bash
ssh root@192.168.X.X
chmod 755 /Applications/OverlayToolApp.app
uicache -p /Applications/OverlayToolApp.app
```

---

## 🔒 Privacy & Security

✅ **Local-only operation**: All data stored on device  
✅ **No network access**: Tweak never contacts external servers  
✅ **No permission prompts**: Uses `PHPickerViewController` (no photo library access)  
✅ **Sandbox-compatible**: Works with rootless Dopamine  
✅ **Open source**: Full source code transparency  

---

## 📊 Technical Details

| Component | Technology |
|-----------|-----------|
| Tweak | Logos + Objective-C |
| Build System | Theos |
| UI Framework | UIKit |
| IPC Method | Darwin Notifications |
| Jailbreak Support | Dopamine (rootless) |
| iOS Version | 15.0+ |
| Architecture | arm64 |

---

## 🎯 Compatibility

### Tested On
- ✅ iOS 15-17
- ✅ Dopamine 2.x
- ✅ iPhone 8 and newer
- ✅ iPad (6th generation and newer)

### Known Limitations
- iPad OS: Overlay layer may not sync perfectly (WIP)
- Very large images (>10MB): May cause memory issues (use PNG compression)

---

## 🚀 Future Features (v2.1+)

- [ ] Screenshot capture tool
- [ ] Multiple image layers
- [ ] Shape tools (rectangles, circles, arrows)
- [ ] Text annotation
- [ ] Undo/Redo system
- [ ] Export annotations to Photos
- [ ] Gesture presets
- [ ] Custom brush styles
- [ ] Built-in magnifier tool
- [ ] Blur/pixelate tool

---

## 📝 Version History

| Version | Date | Notes |
|---------|------|-------|
| 2.0.0 | 2024 | ✨ Drawing tools, color picker, line width, Dopamine support |
| 1.0.0 | 2024 | 🎉 Initial release - basic overlay + pan/pinch |

---

## 📧 Support & Issues

For bugs or feature requests:
1. Check [CHANGELOG.md](CHANGELOG.md) for known issues
2. Check logs: `ssh root@[IP] "tail -f /var/log/syslog | grep -i overlay"`
3. Try rebuilding: `make clean && make package FINALPACKAGE=1`

---

## 📜 License

MIT License - See LICENSE file for details

---

## 🙏 Credits

- **Theos Team**: Build system
- **Dopamine Team**: Jailbreak platform
- **Community**: Feedback and testing

---

## 🔗 Links

- **Theos**: https://github.com/theos/theos
- **Dopamine**: https://github.com/opa334/Dopamine
- **Sileo**: https://sileo.app

---

**OverlayIOSTOOL** v2.0 - Build amazing image overlays on your jailbroken iPhone! 🎉

*Made with ❤️ for the jailbreak community*
