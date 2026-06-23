#!/bin/bash
TC="/home/builder/theos/toolchain/linux/iphone/bin"
DY="/home/builder/OverlayIOSTOOL-build/.theos/obj/OverlayIOSTOOL.dylib"
echo "===== minOS cua dylib (moi slice) ====="
"$TC/otool" -l "$DY" 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep -E "minos|platform" | sed 's/^/  /'
echo "===== Architecture ====="
"$TC/lipo" -info "$DY" 2>/dev/null
echo ""
for D in packages/*rootless*.deb packages/*rootful*.deb; do
    echo "===== $D ====="
    dpkg-deb -f "$D" Package Architecture Depends
    echo ""
done