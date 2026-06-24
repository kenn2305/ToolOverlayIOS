TARGET := iphone:latest:14.0
# arm64 + arm64e: build bằng XCODE THẬT trên macOS (GitHub Actions) -> arm64e CHUẨN,
# nạp vào SpringBoard arm64e (A12+, vd iPhone 11) mà KHÔNG PAC-crash. SpringBoard
# render overlay nổi trên mọi app + màn hình chính (như iPhone 6/7). Slice arm64 cho
# chip cũ. (KHÔNG build hướng này trên Linux - toolchain Linux sinh arm64e lỗi PAC.)
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

# Tweak: SpringBoard-hosted raw image overlay.
TWEAK_NAME = OverlayIOSTOOL
OverlayIOSTOOL_FILES = Tweak.x
OverlayIOSTOOL_ARCHS = arm64 arm64e
OverlayIOSTOOL_CFLAGS = -fobjc-arc -O2
OverlayIOSTOOL_FRAMEWORKS = UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

# Companion app: choose an image and publish it to SpringBoard.
# App đứng riêng -> khởi động ở arm64, KHÔNG cần arm64e (tránh cảnh báo ABI thừa).
APPLICATION_NAME = OverlayIOSTOOLApp
OverlayIOSTOOLApp_ARCHS = arm64
OverlayIOSTOOLApp_FILES = App/main.m App/AppDelegate.m App/ViewController.m
OverlayIOSTOOLApp_CFLAGS = -fobjc-arc -O2
OverlayIOSTOOLApp_FRAMEWORKS = UIKit
OverlayIOSTOOLApp_RESOURCE_DIRS = Resources
OverlayIOSTOOLApp_INSTALL_PATH = /Applications
# Ký app với entitlements thoát sandbox để ghi được ảnh ra /var/mobile/Library
# (nếu thiếu, app bị sandbox chặn -> không gửi được ảnh sang SpringBoard).
OverlayIOSTOOLApp_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
