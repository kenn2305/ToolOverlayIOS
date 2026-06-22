TARGET := iphone:14.5:15.0
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
APPLICATION_NAME = OverlayIOSTOOLApp
OverlayIOSTOOLApp_ARCHS = arm64
OverlayIOSTOOLApp_FILES = App/main.m App/AppDelegate.m App/ViewController.m
OverlayIOSTOOLApp_CFLAGS = -fobjc-arc -O2
OverlayIOSTOOLApp_FRAMEWORKS = UIKit
OverlayIOSTOOLApp_RESOURCE_DIRS = Resources
OverlayIOSTOOLApp_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
