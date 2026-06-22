#!/bin/bash
set -e

echo "============================================"
echo "  Step 1: Tải install-theos script"
echo "============================================"

# Tải script cài đặt Theos về file local (tránh PowerShell can thiệp)
curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos -o /tmp/install-theos.sh
chmod +x /tmp/install-theos.sh

echo "============================================"
echo "  Step 2: Xóa Theos cũ và cài mới"
echo "============================================"

# Xóa Theos cũ bị lỗi
rm -rf ~/theos

# Export THEOS để script biết cài vào đâu
export THEOS=~/theos

# Chạy install-theos (script sẽ tự tải toolchain + SDK)
bash /tmp/install-theos.sh

echo "============================================"
echo "  Step 3: Build project"  
echo "============================================"

export PATH=$THEOS/bin:$PATH
cd /mnt/e/OverlayIOSTOOL

make clean 2>/dev/null || true
make package FINALPACKAGE=1

echo ""
echo "========================================="
echo "  ✅ BUILD THÀNH CÔNG!"
echo "========================================="
ls -la packages/*.deb 2>/dev/null
