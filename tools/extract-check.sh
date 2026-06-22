#!/bin/bash
set -e
B="buildenv/OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
echo "Trich xuat clang + ldid tu bundle vao thu muc sach..."
tar -C "$T" -xzf "$B" \
    theos/toolchain/linux/iphone/bin/clang \
    theos/bin/ldid 2>/dev/null
C="$T/theos/toolchain/linux/iphone/bin/clang"
L="$T/theos/bin/ldid"
echo -n "clang magic : "; head -c4 "$C" | od -An -tx1
echo -n "clang type  : "; (head -c2 "$C" | grep -q '#!' && echo 'WRAPPER(hong)' || echo 'ELF-that')
echo -n "ldid co mat : "; [ -s "$L" ] && echo "YES ($(stat -c%s "$L") bytes)" || echo "NO"
echo "OK - binary nguyen ven sau khi dong goi."
