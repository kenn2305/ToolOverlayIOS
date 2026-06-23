#!/bin/bash
RL="$(ls -t packages/*rootless*.deb 2>/dev/null | head -1)"
RF="$(ls -t packages/*rootful*.deb 2>/dev/null | head -1)"
for tag in ROOTLESS ROOTFUL; do
    if [ "$tag" = ROOTLESS ]; then D="$RL"; else D="$RF"; fi
    echo "===== $tag: $D ====="
    [ -f "$D" ] || { echo "  (khong co)"; continue; }
    echo "--- Architecture ---"
    dpkg-deb -f "$D" Architecture
    echo "--- duong dan cai (thu muc dau) ---"
    dpkg-deb -c "$D" | awk '{print $6}' | grep -E "Applications|DynamicLibraries|\.dylib" | sort -u
    echo ""
done