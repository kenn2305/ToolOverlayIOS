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

# 3. Cài công cụ build.
#    QUAN TRỌNG: gói trong bundle là của Ubuntu 22.04 (jammy). CHỈ được dpkg -i
#    khi máy đúng jammy; cài đè lên bản Ubuntu khác (24.04/26.04...) sẽ HỎNG hệ
#    thống gói (xung đột perl/libc...). Bản khác -> bỏ qua, dùng apt online.
. /etc/os-release 2>/dev/null || true
if ls "$BUILDER_HOME"/apt-debs/*.deb >/dev/null 2>&1 && [ "${VERSION_CODENAME:-}" = "jammy" ]; then
    log "Ubuntu 22.04 (jammy) -> cài gói từ bundle (offline)..."
    dpkg -i "$BUILDER_HOME"/apt-debs/*.deb >/dev/null 2>&1 || true
    # Chữa trạng thái dpkg/apt nếu gói bundle để lại phụ thuộc dở dang
    dpkg --configure -a >/dev/null 2>&1 || true
    apt-get -f install -y -qq >/dev/null 2>&1 || true
else
    log "Ubuntu '${VERSION_CODENAME:-?}' (khác 22.04) -> bỏ qua gói bundle, dùng apt online."
fi

NEED=""
for t in fakeroot make perl rsync; do
    command -v "$t" >/dev/null 2>&1 || NEED="$NEED $t"
done
if [ -n "$NEED" ]; then
    log "Thiếu:$NEED — thử cài qua apt (cần mạng cho bước này)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq $NEED >/dev/null 2>&1 || true
fi

command -v fakeroot >/dev/null 2>&1 || die "Thiếu 'fakeroot' và không cài được qua apt. Hãy chạy: sudo apt-get install -y fakeroot make"
command -v make >/dev/null 2>&1 || die "Thiếu 'make'. Hãy chạy: sudo apt-get install -y make"
ok "công cụ build sẵn sàng"

# 4. Xác minh toolchain THẬT (chống bundle hỏng)
TC_BIN="$THEOS_DIR/toolchain/linux/iphone/bin/clang"
[ -x "$TC_BIN" ] || die "Bundle thiếu toolchain clang."
[ "$(head -c2 "$TC_BIN")" = "#!" ] && die "Toolchain trong bundle là wrapper hỏng."
ls "$THEOS_DIR"/sdks/iPhoneOS*.sdk >/dev/null 2>&1 || die "Bundle thiếu iOS SDK."
[ -x "$THEOS_DIR/bin/ldid" ] || command -v ldid >/dev/null 2>&1 || die "Bundle thiếu ldid (app sẽ không mở được)."
ok "toolchain + SDK + ldid hợp lệ"

# 4b. Bảo đảm thư viện runtime cho toolchain clang.
#     Ubuntu mới (24.04/26.04) đổi soname (vd thiếu libz3.so.4) -> tự cài/symlink.
ensure_toolchain_libs() {
    local clang="$THEOS_DIR/toolchain/linux/iphone/bin/clang"
    local miss
    miss="$(ldd "$clang" 2>/dev/null | awk '/not found/{print $1}')"
    [ -z "$miss" ] && return 0
    log "Toolchain thiếu thư viện:$miss — đang cài/đối chiếu..."
    export DEBIAN_FRONTEND=noninteractive
    dpkg --configure -a >/dev/null 2>&1 || true
    apt-get -f install -y -qq >/dev/null 2>&1 || true
    apt-get update -qq >/dev/null 2>&1 || true
    # Cài TỪNG gói riêng: 1 tên không có (khác bản Ubuntu) sẽ không chặn các gói khác.
    for p in libz3-4 z3 libncurses6 libncursesw6 libtinfo6 zlib1g libxml2t64 libxml2; do
        apt-get install -y -qq "$p" >/dev/null 2>&1 || true
    done
    for lib in $miss; do
        ldconfig -p | grep -q "$lib" && continue
        local base cand
        base="${lib%%.so*}"
        cand="$(find /usr/lib /lib -name "${base}.so*" 2>/dev/null | sort -V | tail -1)"
        [ -n "$cand" ] && ln -sf "$cand" "/usr/lib/x86_64-linux-gnu/$lib"
    done
    ldconfig
    if ldd "$clang" 2>/dev/null | grep -q 'not found'; then
        ldd "$clang" 2>/dev/null | grep 'not found' | sed 's/^/  /'
        die "Toolchain vẫn thiếu thư viện (ở trên). Cài gói tương ứng rồi chạy lại."
    fi
    ok "đã bù đủ thư viện toolchain"
}
ensure_toolchain_libs

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

log "Build 2 biến thể: ROOTLESS + ROOTFUL..."
su - builder -c "
    set -e
    umask 022
    export THEOS='$THEOS_DIR'
    export PATH='$THEOS_DIR/bin':\$PATH
    cd '$BUILD_DIR'
    rm -rf out; mkdir -p out

    echo '=== [1/2] ROOTLESS (Dopamine, XinaA15...) ==='
    make clean >/dev/null 2>&1 || true
    make package FINALPACKAGE=1
    cp -f packages/*.deb out/rootless.deb

    echo '=== [2/2] ROOTFUL (unc0ver, checkra1n, palera1n-rootful...) ==='
    make clean >/dev/null 2>&1 || true
    make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=
    cp -f packages/*.deb out/rootful.deb
" || die "make package THẤT BẠI (xem log phía trên)."

# 6. Kiểm tra output rồi mới báo thành công
ROOTLESS_DEB="$BUILD_DIR/out/rootless.deb"
ROOTFUL_DEB="$BUILD_DIR/out/rootful.deb"
[ -f "$ROOTLESS_DEB" ] || die "Không tạo được bản ROOTLESS."
[ -f "$ROOTFUL_DEB" ]  || die "Không tạo được bản ROOTFUL."

# Verify kiến trúc dylib (đủ arm64 + arm64e cho mọi chip A8+)
MERGED="$BUILD_DIR/.theos/obj/OverlayIOSTOOL.dylib"
LIPO="$THEOS_DIR/toolchain/linux/iphone/bin/lipo"
if [ -x "$LIPO" ] && [ -f "$MERGED" ]; then
    ARCHS_OUT="$("$LIPO" -info "$MERGED" 2>/dev/null || true)"
    log "$ARCHS_OUT"
    echo "$ARCHS_OUT" | grep -qw "arm64"  || die "dylib THIẾU arm64."
    ok "dylib arm64 (chạy mọi chip A8+; A12+ qua ElleKit, tránh lỗi PAC arm64e)"
fi

VER="$(grep -i '^Version:' "$PROJECT_DIR/control" | awk '{print $2}')"
[ -n "$VER" ] || VER="dev"
mkdir -p "$PROJECT_DIR/packages"
ROOTLESS_OUT="$PROJECT_DIR/packages/OverlayIOSTOOL_${VER}_rootless_arm64.deb"
ROOTFUL_OUT="$PROJECT_DIR/packages/OverlayIOSTOOL_${VER}_rootful_arm64.deb"
cp -f "$ROOTLESS_DEB" "$ROOTLESS_OUT"
cp -f "$ROOTFUL_DEB" "$ROOTFUL_OUT"

echo ""
echo "============================================"
echo -e "  \033[1;32m✅ BUILD THÀNH CÔNG (rootless + rootful)\033[0m"
echo "============================================"
echo "ROOTLESS (Dopamine...): $ROOTLESS_OUT"
echo "ROOTFUL  (unc0ver...) : $ROOTFUL_OUT"
ls -la "$ROOTLESS_OUT" "$ROOTFUL_OUT"
