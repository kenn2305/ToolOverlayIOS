#!/bin/bash
# Tu tai bundle moi truong build tu GitHub Release (neu chua co).
# Chay trong WSL, cwd = thu muc project.
set -e
URL="https://github.com/kenn2305/ToolOverlayIOS/releases/download/v5.8.0/OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz"
OUT="buildenv/OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz"

if [ -f "$OUT" ] && gzip -t "$OUT" 2>/dev/null; then
    echo "Bundle da co san, bo qua tai."
    exit 0
fi

mkdir -p buildenv
echo "Tai bundle moi truong (~650MB) tu GitHub Release..."
if ! curl -fL --retry 3 -o "$OUT.part" "$URL"; then
    echo "Khong tai duoc bundle (mang?). Se chuyen sang build ONLINE."
    rm -f "$OUT.part"
    exit 1
fi
mv "$OUT.part" "$OUT"

if ! gzip -t "$OUT" 2>/dev/null; then
    echo "Bundle tai ve bi hong."
    rm -f "$OUT"
    exit 1
fi
echo "Tai bundle thanh cong."
