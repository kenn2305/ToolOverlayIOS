#!/bin/bash
# Kiem tra binary da build: kien truc + minOS + frameworks
TC="/home/builder/theos/toolchain/linux/iphone/bin"
DYLIB="$(ls -t /home/builder/OverlayIOSTOOL-build/.theos/obj/OverlayIOSTOOL.dylib 2>/dev/null | head -1)"
APP="$(ls -t /home/builder/OverlayIOSTOOL-build/.theos/obj/arm64/OverlayIOSTOOLApp.app/OverlayIOSTOOLApp 2>/dev/null | head -1)"

echo "===== TWEAK dylib: $DYLIB ====="
"$TC/lipo" -info "$DYLIB" 2>/dev/null
echo "--- minOS / platform (moi slice) ---"
"$TC/otool" -l "$DYLIB" 2>/dev/null | grep -A4 -E "LC_BUILD_VERSION|LC_VERSION_MIN_IPHONEOS" | grep -E "platform|minos|version|sdk" | sed 's/^/  /'
echo "--- frameworks lien ket ---"
"$TC/otool" -L "$DYLIB" 2>/dev/null | grep -oE "/System/Library/Frameworks/[A-Za-z]+\.framework" | sort -u | sed 's/^/  /'

echo ""
echo "===== APP: $APP ====="
"$TC/lipo" -info "$APP" 2>/dev/null
"$TC/otool" -l "$APP" 2>/dev/null | grep -A4 -E "LC_BUILD_VERSION|LC_VERSION_MIN_IPHONEOS" | grep -E "platform|minos|version|sdk" | sed 's/^/  /'
