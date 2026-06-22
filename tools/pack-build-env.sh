#!/bin/bash
#
# pack-build-env.sh — Đóng gói TOÀN BỘ môi trường build thành 1 file .tar.gz
# -------------------------------------------------------------------------
# Chạy 1 LẦN trên WSL/Linux x86_64 ĐÃ build được (máy của bạn, có internet).
# Gom: Theos + iOS toolchain (arm64e) + iOS SDK + ldid + gói apt cần thiết
# -> buildenv/OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz
#
# Tối ưu: tar TRỰC TIẾP từ nguồn (không copy 2.9G), chỉ giữ 1 SDK mới nhất.
# Dùng:  sudo bash tools/pack-build-env.sh
#        KEEP_ALL_SDKS=1  -> giữ hết SDK
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$PROJECT_DIR/buildenv"
OUT="$OUT_DIR/OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

log() { echo -e "\033[1;36m[pack]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[ ok ]\033[0m $*"; }
die() { echo -e "\033[1;31m[LỖI]\033[0m $*" >&2; exit 1; }

uname -s | grep -qi linux || die "Phải chạy trong WSL/Linux."
[ "$(uname -m)" = "x86_64" ] || die "Bundle dành cho x86_64. Máy: $(uname -m)."
[ "$(id -u)" -eq 0 ] || die "Chạy bằng root:  sudo bash tools/pack-build-env.sh"

# 1. Tìm Theos thật (ưu tiên /home/builder/theos đã verify)
THEOS_DIR="${THEOS:-}"
if [ -z "$THEOS_DIR" ] || [ ! -f "$THEOS_DIR/makefiles/common.mk" ]; then
    for c in /home/builder/theos "$HOME/theos" /opt/theos /usr/local/theos; do
        [ -f "$c/makefiles/common.mk" ] && THEOS_DIR="$c" && break
    done
fi
[ -n "${THEOS_DIR:-}" ] && [ -f "$THEOS_DIR/makefiles/common.mk" ] || die "Không tìm thấy Theos."
log "Theos: $THEOS_DIR ($(du -sh "$THEOS_DIR" 2>/dev/null | cut -f1))"

# 2. Verify toolchain THẬT + SDK + ldid
TC_BIN="$THEOS_DIR/toolchain/linux/iphone/bin/clang"
[ -x "$TC_BIN" ] || die "Thiếu toolchain: $TC_BIN"
[ "$(head -c2 "$TC_BIN")" = "#!" ] && die "Toolchain là WRAPPER hỏng — không gói."
ok "toolchain thật"

# SDK phải KHỚP với TARGET trong Makefile và khả năng của toolchain cũ.
# Toolchain Swift-5.3.2 KHÔNG biên dịch được SDK >= 15 (NS_SWIFT_SENDABLE...),
# nên mặc định gói iPhoneOS14.5.sdk (đúng theo Makefile: iphone:14.5:15.0).
SDK_KEEP="${SDK_KEEP_NAME:-iPhoneOS14.5.sdk}"
[ -d "$THEOS_DIR/sdks/$SDK_KEEP" ] || die "Không thấy SDK cần gói: $THEOS_DIR/sdks/$SDK_KEEP"
ok "SDK giữ lại: $SDK_KEEP (khớp Makefile + toolchain)"

if [ ! -x "$THEOS_DIR/bin/ldid" ]; then
    sys="$(command -v ldid || true)"
    [ -n "$sys" ] && cp "$sys" "$THEOS_DIR/bin/ldid" && chmod +x "$THEOS_DIR/bin/ldid" \
        || die "Không thấy ldid (cần để ký app)."
fi
ok "ldid: $THEOS_DIR/bin/ldid"

# 3. Tải sẵn gói apt cho build offline (gồm dpkg-dev đang thiếu)
log "Tải sẵn gói apt (fakeroot, dpkg-dev, ...)..."
mkdir -p "$STAGE/apt-debs"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || true
rm -f /var/cache/apt/archives/*.deb 2>/dev/null || true
apt-get install -y --download-only --reinstall \
    fakeroot libfakeroot dpkg-dev xz-utils perl make rsync zstd >/dev/null 2>&1 || \
apt-get install -y --download-only \
    fakeroot dpkg-dev xz-utils perl make rsync zstd >/dev/null 2>&1 || true
cp /var/cache/apt/archives/*.deb "$STAGE/apt-debs/" 2>/dev/null || true
ok "apt debs: $(ls "$STAGE/apt-debs" 2>/dev/null | wc -l) gói"

# 4. Manifest
{
    echo "OverlayIOSTOOL build environment bundle"
    echo "created  : $(date -u '+%Y-%m-%d %H:%M:%SZ')"
    echo "host     : $(uname -srm)"
    echo "theos    : $THEOS_DIR"
    echo "sdk      : $SDK_KEEP"
    echo "platform : linux-x86_64 (WSL Ubuntu)"
} > "$STAGE/MANIFEST.txt"

# 5. Tar trực tiếp (loại .git + các SDK thừa) -> 1 file .tar.gz
log "Nén bundle (gzip nhanh, có thể vài phút)..."
PARENT="$(dirname "$THEOS_DIR")"
BASENAME="$(basename "$THEOS_DIR")"   # = theos
EXCL=( --exclude="$BASENAME/.git" --exclude="$BASENAME/.git/*" )
if [ "${KEEP_ALL_SDKS:-0}" != "1" ]; then
    for s in "$THEOS_DIR"/sdks/iPhoneOS*.sdk; do
        b="$(basename "$s")"
        [ "$b" != "$SDK_KEEP" ] && EXCL+=( --exclude="$BASENAME/sdks/$b" )
    done
fi

mkdir -p "$OUT_DIR"
tar "${EXCL[@]}" -cf - -C "$PARENT" "$BASENAME" -C "$STAGE" apt-debs MANIFEST.txt \
    | gzip -1 > "$OUT"

echo ""
echo "============================================"
echo -e "  \033[1;32m✅ ĐÓNG GÓI XONG\033[0m"
echo "============================================"
echo "Bundle: $OUT"
echo "Dung lượng: $(du -h "$OUT" | cut -f1)"
