#!/bin/bash
set -e

echo "============================================"
echo "  Sửa lỗi WSL và Build Theos Project"
echo "============================================"

PROJECT_DIR="/mnt/e/OverlayIOSTOOL"
BUILDER_HOME="/home/builder"
THEOS_DIR="$BUILDER_HOME/theos"
TOOLCHAIN_DIR="$THEOS_DIR/toolchain/linux/iphone"

echo "[1/4] Đảm bảo cài đặt các gói giải nén (zstd)..."
apt-get update -qq > /dev/null 2>&1
apt-get install -y -qq zstd curl wget > /dev/null 2>&1

echo "[2/4] Tải và cài đặt iOS Toolchain (CRKatri)..."
if [ ! -f "$TOOLCHAIN_DIR/bin/clang" ]; then
    echo "  -> Đang tải Toolchain từ GitHub..."
    mkdir -p "$TOOLCHAIN_DIR"
    cd /tmp
    
    # Tải toolchain chính xác
    wget -q --show-progress "https://github.com/CRKatri/llvm-project/releases/download/swift-5.3.2-RELEASE/swift-5.3.2-RELEASE-ubuntu20.04.tar.zst" -O toolchain.tar.zst
    
    echo "  -> Đang giải nén Toolchain..."
    zstd -d toolchain.tar.zst -o toolchain.tar
    tar -xf toolchain.tar -C "$TOOLCHAIN_DIR"
    rm -f toolchain.tar.zst toolchain.tar
    
    # Phân quyền lại cho user builder
    chown -R builder:builder "$THEOS_DIR/toolchain"
    echo "  -> Cài đặt Toolchain hoàn tất!"
else
    echo "  -> Toolchain đã tồn tại."
fi

echo "[3/4] Kiểm tra SDKs..."
SDK_CHECK=$(find "$THEOS_DIR/sdks" -maxdepth 1 -name "*.sdk" -type d 2>/dev/null | head -1)
if [ -z "$SDK_CHECK" ]; then
    echo "  -> Lỗi: Chưa có SDKs. Đang tải..."
    mkdir -p "$THEOS_DIR/sdks"
    cd /tmp
    curl -sL -o sdks.tar.gz "https://github.com/theos/sdks/archive/master.tar.gz"
    tar -xzf sdks.tar.gz
    mv sdks-master/*.sdk "$THEOS_DIR/sdks/" 2>/dev/null || true
    rm -rf sdks-master sdks.tar.gz
    chown -R builder:builder "$THEOS_DIR/sdks"
    echo "  -> Tải SDKs hoàn tất."
else
    echo "  -> SDKs đã sẵn sàng."
fi

echo "[4/4] Build Project bằng Theos..."
cd "$PROJECT_DIR"
rm -rf .theos/obj packages

# Build dưới quyền user builder
su - builder -c "
    export THEOS=$THEOS_DIR
    export PATH=$THEOS_DIR/bin:\$PATH
    cd $PROJECT_DIR
    make clean 2>/dev/null || true
    make package FINALPACKAGE=1
"

echo "========================================="
echo "  Hoàn tất quá trình!"
echo "========================================="
ls -la packages/*.deb 2>/dev/null || echo "Không tìm thấy file .deb"
