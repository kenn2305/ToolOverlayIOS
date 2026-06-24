#!/bin/bash
#
# OverlayIOSTOOL - Robust one-shot build (WSL / Linux)
# ----------------------------------------------------
# Triết lý: "từ build đến chạy không lỗi".
#   - Môi trường ĐỦ  -> build ra .deb chạy được (tweak arm64+arm64e + app đã ký).
#   - Môi trường THIẾU -> DỪNG NGAY với thông báo rõ ràng.
#   - KHÔNG bao giờ tạo binary hỏng rồi báo "thành công" (lỗi của script cũ).
#
set -euo pipefail

# --- Đường dẫn tự động, không hard-code ổ đĩa ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUILDER_HOME="/home/builder"
THEOS_DIR="$BUILDER_HOME/theos"
# Build trên ext4 (home), KHÔNG build thẳng trên /mnt/e (drvfs) để tránh
# lỗi quyền/symlink/exec của Windows filesystem.
BUILD_DIR="$BUILDER_HOME/OverlayIOSTOOL-build"

log() { echo -e "\033[1;36m[build]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[ ok ]\033[0m $*"; }
die() { echo -e "\033[1;31m[LỖI]\033[0m $*" >&2; exit 1; }

echo "============================================"
echo "  OverlayIOSTOOL - Robust Build"
echo "============================================"

# ----------------------------------------------------
# 0. Kiểm tra tiền đề
# ----------------------------------------------------
uname -s | grep -qi linux || die "Phải chạy trong WSL/Linux (không phải PowerShell/cmd)."
[ "$(id -u)" -eq 0 ] || die "Chạy bằng quyền root:  sudo ./build.sh"
[ -f "$PROJECT_DIR/Makefile" ] || die "Không thấy Makefile trong $PROJECT_DIR."
HOST_ARCH="$(uname -m)"

# ----------------------------------------------------
# 1. User builder (theos không build dưới root)
# ----------------------------------------------------
log "[1/8] Chuẩn bị user builder..."
id builder &>/dev/null || useradd -m -s /bin/bash builder
echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder
ok "builder"

# ----------------------------------------------------
# 2. Dependencies
# ----------------------------------------------------
log "[2/8] Cài dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || die "apt-get update thất bại (kiểm tra mạng)."
apt-get install -y -qq git perl curl wget make fakeroot xz-utils liblzma-dev sudo zstd rsync dpkg-dev >/dev/null 2>&1 \
    || die "Cài dependencies thất bại."
ok "dependencies"

# ----------------------------------------------------
# 3. Theos
# ----------------------------------------------------
log "[3/8] Theos..."
if [ ! -f "$THEOS_DIR/makefiles/common.mk" ]; then
    rm -rf "$THEOS_DIR"
    su - builder -c "git clone --quiet --recursive https://github.com/theos/theos.git '$THEOS_DIR'" \
        || die "Clone Theos thất bại (mạng?)."
fi
ok "Theos"

# ----------------------------------------------------
# 4. iOS toolchain THẬT (clang 13, ABI arm64e MỚI cho iOS 14+).
#    PHẢI dùng toolchain clang >= 12. Toolchain cũ (CRKatri swift-5.3.2 = clang 11)
#    sinh arm64e ABI CŨ -> PAC crash treo táo trên iOS 14.2+/15. kabiroberai
#    swift-5.8 (clang 13) sinh arm64e ABI mới đúng chuẩn.
# ----------------------------------------------------
log "[4/8] iOS toolchain (clang 13, arm64e ABI mới)..."
TC_BIN="$THEOS_DIR/toolchain/linux/iphone/bin/clang"
# Nếu đang có toolchain CŨ (clang < 12) -> xoá để tải lại bản mới (tránh PAC crash).
if [ -x "$TC_BIN" ]; then
    TC_VER="$("$TC_BIN" --version 2>/dev/null | grep -oiE 'clang version [0-9]+' | grep -oE '[0-9]+' | head -1 || echo 0)"
    if [ "${TC_VER:-0}" -lt 12 ]; then
        log "  -> phát hiện toolchain cũ (clang ${TC_VER}) -> xoá, tải bản clang 13"
        rm -rf "$THEOS_DIR/toolchain/linux"
    fi
fi
if [ ! -x "$TC_BIN" ]; then
    cd /tmp
    # Tarball giải nén thẳng ra cấu trúc linux/iphone/... khớp Theos.
    SWIFT_TC_URL="https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu22.04.tar.xz"
    log "  -> tải $(basename "$SWIFT_TC_URL") (~620MB)"
    curl -fSL --retry 3 -o swift-tc.tar.xz "$SWIFT_TC_URL" \
        || die "Không tải được Swift toolchain (clang 13). Kiểm tra mạng rồi chạy lại."
    rm -rf "$THEOS_DIR/toolchain/linux"
    mkdir -p "$THEOS_DIR/toolchain"
    tar -xJf swift-tc.tar.xz -C "$THEOS_DIR/toolchain" \
        || die "Giải nén Swift toolchain thất bại."
    rm -f swift-tc.tar.xz
    [ -x "$TC_BIN" ] || die "Toolchain tải về thiếu clang tại $TC_BIN."
    chown -R builder:builder "$THEOS_DIR/toolchain"
fi
# Chặn wrapper hỏng: clang thật là ELF (bắt đầu bằng 0x7F 'ELF'), wrapper là script '#!'.
if [ "$(head -c2 "$TC_BIN")" = "#!" ]; then
    die "Toolchain tại $TC_BIN là WRAPPER script (clang hệ thống) -> build sẽ hỏng. Xóa '$THEOS_DIR/toolchain' rồi chạy lại."
fi
ok "toolchain thật"

# ----------------------------------------------------
# 5. ldid (KÝ app - thiếu nó app cài xong KHÔNG mở được)
# ----------------------------------------------------
log "[5/8] ldid (ký nhị phân)..."
if ! command -v ldid >/dev/null 2>&1 && [ ! -x "$THEOS_DIR/bin/ldid" ]; then
    case "$HOST_ARCH" in
        aarch64|arm64) LD_ASSET="ldid_linux_aarch64" ;;
        *)             LD_ASSET="ldid_linux_x86_64" ;;
    esac
    if ! apt-get install -y -qq ldid >/dev/null 2>&1; then
        mkdir -p "$THEOS_DIR/bin"
        curl -fsSL -o "$THEOS_DIR/bin/ldid" \
            "https://github.com/ProcursusTeam/ldid/releases/latest/download/$LD_ASSET" \
            && chmod +x "$THEOS_DIR/bin/ldid" \
            || die "Không cài được ldid. Thiếu ldid -> app không mở được. Hãy cài thủ công."
        chown builder:builder "$THEOS_DIR/bin/ldid"
    fi
fi
command -v ldid >/dev/null 2>&1 || [ -x "$THEOS_DIR/bin/ldid" ] || die "ldid vẫn không khả dụng."
ok "ldid"

# ----------------------------------------------------
# 6. iOS SDKs (cần SDK >= 15 cho deployment 15.0)
# ----------------------------------------------------
log "[6/8] iOS SDKs..."
if ! ls "$THEOS_DIR/sdks"/iPhoneOS*.sdk >/dev/null 2>&1; then
    mkdir -p "$THEOS_DIR/sdks"
    cd /tmp
    curl -fsSL -o sdks.tar.gz "https://github.com/theos/sdks/archive/refs/heads/master.tar.gz" \
        || die "Tải iOS SDK thất bại."
    tar -xzf sdks.tar.gz
    mv sdks-master/*.sdk "$THEOS_DIR/sdks/" 2>/dev/null || true
    rm -rf sdks-master sdks.tar.gz
    chown -R builder:builder "$THEOS_DIR/sdks"
fi
ls "$THEOS_DIR/sdks"/iPhoneOS*.sdk >/dev/null 2>&1 || die "Không có iOS SDK nào trong $THEOS_DIR/sdks."
ok "SDK: $(ls -d "$THEOS_DIR"/sdks/iPhoneOS*.sdk 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"

# ----------------------------------------------------
# 7. Build trên ext4 (copy nguồn sạch, bỏ artifact cũ)
# ----------------------------------------------------
log "[7/8] Build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
# --chmod chuẩn hoá quyền (drvfs /mnt/e copy ra 777 -> dpkg-deb từ chối control 777)
rsync -a --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
    --exclude '.theos' --exclude 'packages' --exclude '.git' --exclude 'buildenv' \
    "$PROJECT_DIR"/ "$BUILD_DIR"/
find "$BUILD_DIR" -type d -exec chmod 0755 {} + 2>/dev/null || true
find "$BUILD_DIR" -type f -exec chmod 0644 {} + 2>/dev/null || true
for s in preinst postinst prerm postrm; do
    [ -f "$BUILD_DIR/$s" ] && chmod 0755 "$BUILD_DIR/$s"
    [ -f "$BUILD_DIR/layout/DEBIAN/$s" ] && chmod 0755 "$BUILD_DIR/layout/DEBIAN/$s"
done
chown -R builder:builder "$BUILD_DIR"

# Bảo đảm thư viện runtime cho toolchain (Ubuntu mới đổi soname, vd libz3.so.4)
CLANG_BIN="$THEOS_DIR/toolchain/linux/iphone/bin/clang"
MISS="$(ldd "$CLANG_BIN" 2>/dev/null | awk '/not found/{print $1}')"
if [ -n "$MISS" ]; then
    log "Toolchain thiếu thư viện:$MISS — đang cài/đối chiếu..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    for p in libz3-4 z3 libncurses6 libncursesw6 libtinfo6 zlib1g libxml2t64 libxml2; do
        apt-get install -y -qq "$p" >/dev/null 2>&1 || true
    done
    for lib in $MISS; do
        ldconfig -p | grep -q "$lib" && continue
        base="${lib%%.so*}"
        cand="$(find /usr/lib /lib -name "${base}.so*" 2>/dev/null | sort -V | tail -1)"
        [ -n "$cand" ] && ln -sf "$cand" "/usr/lib/x86_64-linux-gnu/$lib"
    done
    ldconfig
    ldd "$CLANG_BIN" 2>/dev/null | grep -q 'not found' && die "Toolchain vẫn thiếu thư viện. Cài gói tương ứng rồi chạy lại."
    ok "đã bù đủ thư viện toolchain"
fi

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

# ----------------------------------------------------
# 8. Kiểm tra OUTPUT thật sự đúng rồi mới báo thành công
# ----------------------------------------------------
log "[8/8] Kiểm tra sản phẩm..."
ROOTLESS_DEB="$BUILD_DIR/out/rootless.deb"
ROOTFUL_DEB="$BUILD_DIR/out/rootful.deb"
[ -f "$ROOTLESS_DEB" ] || die "Không tạo được bản ROOTLESS."
[ -f "$ROOTFUL_DEB" ]  || die "Không tạo được bản ROOTFUL."

# Re-ký app companion với entitlements thoát sandbox (theos không áp CODESIGN_FLAGS).
LDID_BIN="$THEOS_DIR/bin/ldid"; [ -x "$LDID_BIN" ] || LDID_BIN="$(command -v ldid || true)"
resign_app_in_deb() {
    local deb="$1" tmp appbin
    [ -f "$PROJECT_DIR/entitlements.plist" ] || return 0
    [ -n "$LDID_BIN" ] || return 0
    tmp="$(mktemp -d)"
    if dpkg-deb -R "$deb" "$tmp" 2>/dev/null; then
        appbin="$(find "$tmp" -name OverlayIOSTOOLApp -type f 2>/dev/null | head -1)"
        if [ -n "$appbin" ]; then
            "$LDID_BIN" -S"$PROJECT_DIR/entitlements.plist" "$appbin" 2>/dev/null || true
            chmod 0755 "$appbin"
            chmod 0755 "$tmp/DEBIAN" 2>/dev/null || true
            find "$tmp/DEBIAN" -type f -exec chmod 0755 {} + 2>/dev/null || true
            dpkg-deb -b "$tmp" "$deb" >/dev/null 2>&1 || true
        fi
    fi
    rm -rf "$tmp"
}
resign_app_in_deb "$ROOTLESS_DEB"
resign_app_in_deb "$ROOTFUL_DEB"

# Per-app: dylib CHỈ cần arm64 (nạp vào app App Store = arm64). KHÔNG có arm64e ->
# không nạp vào SpringBoard -> không treo táo.
MERGED="$BUILD_DIR/.theos/obj/OverlayIOSTOOL.dylib"
LIPO="$THEOS_DIR/toolchain/linux/iphone/bin/lipo"
if [ -x "$LIPO" ] && [ -f "$MERGED" ]; then
    ARCHS_OUT="$("$LIPO" -info "$MERGED" 2>/dev/null || true)"
    log "  -> $ARCHS_OUT"
    echo "$ARCHS_OUT" | grep -qw "arm64"   || die "dylib THIẾU slice arm64."
    ok "dylib arm64 (per-app, không đụng SpringBoard -> không treo)"
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
