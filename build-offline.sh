#!/bin/bash
#
# build-offline.sh — Build OFFLINE từ bundle môi trường đã đóng gói sẵn.
# --------------------------------------------------------------------
# Máy khách (Windows + WSL Ubuntu) chỉ cần:
#     cd /mnt/<ổ>/OverlayIOSTOOL
#     sudo ./build-offline.sh
# KHÔNG cần internet. Toàn bộ Theos + toolchain + SDK + ldid + gói apt
# đã nằm trong buildenv/OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUNDLE="${1:-$PROJECT_DIR/buildenv/OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz}"
BUILDER_HOME="/home/builder"
THEOS_DIR="$BUILDER_HOME/theos"
BUILD_DIR="$BUILDER_HOME/OverlayIOSTOOL-build"

log() { echo -e "\033[1;36m[offline]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[  ok  ]\033[0m $*"; }
die() { echo -e "\033[1;31m[ LỖI ]\033[0m $*" >&2; exit 1; }

echo "============================================"
echo "  OverlayIOSTOOL - Offline Build"
echo "============================================"

# 0. Tiền đề
uname -s | grep -qi linux || die "Phải chạy trong WSL/Linux (mở Ubuntu trong WSL)."
[ "$(id -u)" -eq 0 ] || die "Chạy bằng root:  sudo ./build-offline.sh"
[ "$(uname -m)" = "x86_64" ] || die "Bundle dành cho x86_64, máy này là $(uname -m)."
[ -f "$PROJECT_DIR/Makefile" ] || die "Không thấy Makefile trong $PROJECT_DIR."
[ -f "$BUNDLE" ] || die "Không thấy bundle: $BUNDLE (hãy chắc đã copy kèm thư mục buildenv/)."

# 1. User builder
id builder &>/dev/null || useradd -m -s /bin/bash builder
echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder

# 2. Giải nén bundle (nếu chưa có)
if [ ! -f "$THEOS_DIR/makefiles/common.mk" ]; then
    log "Giải nén môi trường build..."
    tar -C "$BUILDER_HOME" -xzf "$BUNDLE"
    chown -R builder:builder "$THEOS_DIR" 2>/dev/null || true
fi
[ -f "$THEOS_DIR/makefiles/common.mk" ] || die "Giải nén thất bại: không thấy Theos trong bundle."
ok "Theos sẵn sàng"

# 3. Cài các gói apt từ bundle (offline) — fakeroot, dpkg-dev...
if ls "$BUILDER_HOME"/apt-debs/*.deb >/dev/null 2>&1; then
    log "Cài gói apt offline..."
    dpkg -i "$BUILDER_HOME"/apt-debs/*.deb >/dev/null 2>&1 || true
fi
command -v fakeroot >/dev/null 2>&1 || die "Thiếu 'fakeroot' (không có trong bundle). Cần cài thủ công: apt-get install fakeroot"
ok "công cụ build sẵn sàng"

# 4. Xác minh toolchain THẬT (chống bundle hỏng)
TC_BIN="$THEOS_DIR/toolchain/linux/iphone/bin/clang"
[ -x "$TC_BIN" ] || die "Bundle thiếu toolchain clang."
[ "$(head -c2 "$TC_BIN")" = "#!" ] && die "Toolchain trong bundle là wrapper hỏng."
ls "$THEOS_DIR"/sdks/iPhoneOS*.sdk >/dev/null 2>&1 || die "Bundle thiếu iOS SDK."
[ -x "$THEOS_DIR/bin/ldid" ] || command -v ldid >/dev/null 2>&1 || die "Bundle thiếu ldid (app sẽ không mở được)."
ok "toolchain + SDK + ldid hợp lệ"

# 5. Build trên ext4 (copy nguồn sạch)
log "Build..."
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
# --chmod chuẩn hoá quyền (drvfs /mnt/e copy ra 777 -> dpkg-deb từ chối control 777)
if command -v rsync >/dev/null 2>&1; then
    rsync -a --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
        --exclude '.theos' --exclude 'packages' --exclude '.git' --exclude 'buildenv' \
        "$PROJECT_DIR"/ "$BUILD_DIR"/
else
    cp -a "$PROJECT_DIR"/. "$BUILD_DIR"/; rm -rf "$BUILD_DIR/.theos" "$BUILD_DIR/packages" "$BUILD_DIR/buildenv" "$BUILD_DIR/.git"
fi
# Chuẩn hoá quyền chắc chắn: thư mục 755, file 644
find "$BUILD_DIR" -type d -exec chmod 0755 {} + 2>/dev/null || true
find "$BUILD_DIR" -type f -exec chmod 0644 {} + 2>/dev/null || true
# Maintainer scripts của deb PHẢI thực thi được (>=0555)
for s in preinst postinst prerm postrm; do
    [ -f "$BUILD_DIR/$s" ] && chmod 0755 "$BUILD_DIR/$s"
    [ -f "$BUILD_DIR/layout/DEBIAN/$s" ] && chmod 0755 "$BUILD_DIR/layout/DEBIAN/$s"
done
chown -R builder:builder "$BUILD_DIR"

su - builder -c "
    set -e
    umask 022
    export THEOS='$THEOS_DIR'
    export PATH='$THEOS_DIR/bin':\$PATH
    cd '$BUILD_DIR'
    make clean >/dev/null 2>&1 || true
    make package FINALPACKAGE=1
" || die "make package THẤT BẠI (xem log phía trên)."

# 6. Kiểm tra output rồi mới báo thành công
DEB="$(ls -t "$BUILD_DIR"/packages/*.deb 2>/dev/null | head -1 || true)"
[ -n "$DEB" ] || die "Build xong nhưng KHÔNG có .deb -> thất bại."

MERGED="$BUILD_DIR/.theos/obj/OverlayIOSTOOL.dylib"
LIPO="$THEOS_DIR/toolchain/linux/iphone/bin/lipo"
if [ -x "$LIPO" ] && [ -f "$MERGED" ]; then
    ARCHS_OUT="$("$LIPO" -info "$MERGED" 2>/dev/null || true)"
    log "$ARCHS_OUT"
    echo "$ARCHS_OUT" | grep -q "arm64e" || die "dylib THIẾU arm64e -> XS Max không chạy."
    echo "$ARCHS_OUT" | grep -qw "arm64"  || die "dylib THIẾU arm64."
    ok "dylib đủ arm64 + arm64e"
fi

mkdir -p "$PROJECT_DIR/packages"
cp -f "$DEB" "$PROJECT_DIR/packages/"
OUT="$PROJECT_DIR/packages/$(basename "$DEB")"

echo ""
echo "============================================"
echo -e "  \033[1;32m✅ BUILD OFFLINE THÀNH CÔNG\033[0m"
echo "============================================"
echo "File .deb: $OUT"
ls -la "$OUT"
