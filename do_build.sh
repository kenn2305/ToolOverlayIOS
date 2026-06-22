#!/bin/bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export THEOS="${THEOS:-$HOME/theos}"
export PATH="$THEOS/bin:$PATH"

BUILD_DIR=""
ALLEMANDE_REVISION="43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9"
ALLEMANDE_DIR="$HOME/.local/share/overlayiostool/allemande"
ALLEMANDE="$ALLEMANDE_DIR/allemande"

cleanup() {
    if [ -n "$BUILD_DIR" ] && [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi
}

trap cleanup EXIT

ensure_allemande() {
    if [ -x "$ALLEMANDE" ] &&
       [ -f "$ALLEMANDE_DIR/.overlay-revision" ] &&
       [ "$(cat "$ALLEMANDE_DIR/.overlay-revision")" = "$ALLEMANDE_REVISION" ]; then
        return 0
    fi

    command -v git >/dev/null 2>&1 || {
        echo "ERROR: git is required to install allemande."
        return 1
    }
    command -v g++ >/dev/null 2>&1 || {
        echo "ERROR: g++ is required to build allemande."
        return 1
    }

    rm -rf "$ALLEMANDE_DIR"
    mkdir -p "$(dirname "$ALLEMANDE_DIR")"
    git clone https://github.com/p0358/allemande "$ALLEMANDE_DIR" || return 1
    (
        cd "$ALLEMANDE_DIR"
        git checkout --detach "$ALLEMANDE_REVISION"
        g++ -std=c++20 -O2 -o allemande main.cpp
        printf '%s\n' "$ALLEMANDE_REVISION" >.overlay-revision
    ) || return 1
}

convert_arm64e_binary() {
    local binary="$1"
    local before_hash
    local after_hash

    if [ ! -f "$binary" ]; then
        echo "ERROR: Missing tweak binary: $binary"
        return 1
    fi
    if [ ! -x "$ALLEMANDE" ]; then
        echo "ERROR: allemande is required for iOS 15 arm64e compatibility."
        return 1
    fi

    if ! "$THEOS/toolchain/linux/iphone/bin/lipo" -archs "$binary" | grep -qw arm64e; then
        echo "ERROR: The tweak does not contain an arm64e slice."
        return 1
    fi

    echo "Converting arm64e ABI: $binary"
    before_hash="$(sha256sum "$binary" | awk '{print $1}')"
    "$ALLEMANDE" "$binary"
    after_hash="$(sha256sum "$binary" | awk '{print $1}')"
    if [ "$before_hash" = "$after_hash" ]; then
        echo "ERROR: arm64e ABI conversion did not modify the tweak binary."
        return 1
    fi

    command -v ldid >/dev/null 2>&1 || {
        echo "ERROR: ldid is required to sign the converted tweak."
        return 1
    }
    ldid -S "$binary"
}

audit_package() {
    local package="$1"
    local audit_dir
    local tweak_binary
    local app_binary
    local tweak_archs
    local app_archs

    audit_dir="$(mktemp -d "$HOME/OverlayIOSTOOL_audit.XXXXXX")"
    dpkg-deb -R "$package" "$audit_dir"
    tweak_binary="$audit_dir/var/jb/Library/MobileSubstrate/DynamicLibraries/OverlayIOSTOOL.dylib"
    app_binary="$audit_dir/var/jb/Applications/OverlayIOSTOOLApp.app/OverlayIOSTOOLApp"

    tweak_archs="$("$THEOS/toolchain/linux/iphone/bin/lipo" -archs "$tweak_binary")"
    app_archs="$("$THEOS/toolchain/linux/iphone/bin/lipo" -archs "$app_binary")"

    echo "$tweak_archs" | grep -qw arm64 ||
        { echo "ERROR: audit failed: tweak is missing arm64."; rm -rf "$audit_dir"; return 1; }
    echo "$tweak_archs" | grep -qw arm64e ||
        { echo "ERROR: audit failed: tweak is missing arm64e."; rm -rf "$audit_dir"; return 1; }
    [ "$app_archs" = "arm64" ] ||
        { echo "ERROR: audit failed: companion app must be arm64 only."; rm -rf "$audit_dir"; return 1; }
    grep -q '^Architecture: iphoneos-arm64$' "$audit_dir/DEBIAN/control" ||
        { echo "ERROR: audit failed: package is not rootless."; rm -rf "$audit_dir"; return 1; }
    grep -q 'firmware (>= 15.0)' "$audit_dir/DEBIAN/control" ||
        { echo "ERROR: audit failed: iOS 15 minimum dependency is missing."; rm -rf "$audit_dir"; return 1; }
    "$THEOS/toolchain/linux/iphone/bin/otool" -l "$tweak_binary" |
        grep -q 'minos 15.0' ||
        { echo "ERROR: audit failed: tweak deployment target is not iOS 15.0."; rm -rf "$audit_dir"; return 1; }
    "$THEOS/toolchain/linux/iphone/bin/otool" -L "$tweak_binary" |
        grep -q '@rpath/CydiaSubstrate.framework/CydiaSubstrate' ||
        { echo "ERROR: audit failed: rootless substrate rpath is missing."; rm -rf "$audit_dir"; return 1; }
    ldid -h "$tweak_binary" >/dev/null ||
        { echo "ERROR: audit failed: tweak signature is invalid."; rm -rf "$audit_dir"; return 1; }
    ldid -h "$app_binary" >/dev/null ||
        { echo "ERROR: audit failed: app signature is invalid."; rm -rf "$audit_dir"; return 1; }
    if grep -Eiq '\b(reboot|ldrestart|killall|sbreload)\b' "$audit_dir/DEBIAN/postinst"; then
        echo "ERROR: audit failed: postinst contains a forced restart command."
        rm -rf "$audit_dir"
        return 1
    fi

    rm -rf "$audit_dir"
    echo "Package audit passed: tweak=[$tweak_archs], app=[$app_archs], signed rootless iOS 15-16"
}

if [ ! -x "$THEOS/toolchain/linux/iphone/bin/clang" ]; then
    echo "ERROR: Theos iOS toolchain was not found at $THEOS"
    echo "Run SETUP_ENVIRONMENT.cmd first."
    exit 1
fi

if ! find "$THEOS/sdks" -maxdepth 1 -type d -name 'iPhoneOS*.sdk' -print -quit 2>/dev/null | grep -q .; then
    echo "ERROR: No iPhoneOS SDK was found in $THEOS/sdks"
    echo "Run SETUP_ENVIRONMENT.cmd again to install the patched SDK."
    exit 1
fi

# Build on the native Linux filesystem so ldid does not operate on NTFS.
BUILD_DIR="$(mktemp -d "$HOME/OverlayIOSTOOL_build.XXXXXX")"
rsync -a \
    --exclude '.git/' \
    --exclude '.theos/' \
    --exclude 'dist/' \
    --exclude 'packages/' \
    --exclude 'setup-logs/' \
    "$SOURCE_DIR/" "$BUILD_DIR/"
cd "$BUILD_DIR"

find "$BUILD_DIR" -type d -exec chmod 755 {} +
find "$BUILD_DIR" -type f -exec chmod 644 {} +
find "$BUILD_DIR" -type f \( -name '*.sh' -o -name '*.cmd' -o -name 'postinst' \) -exec chmod 755 {} +

rm -rf packages
make clean 2>/dev/null || true
make package FINALPACKAGE=1

cd packages
ensure_allemande
echo "Allemande ready: $ALLEMANDE ($ALLEMANDE_REVISION)"

for DEB_FILE in *.deb; do
    [ -f "$DEB_FILE" ] || continue
    rm -rf extract
    mkdir -p extract
    dpkg-deb -R "$DEB_FILE" extract/
    convert_arm64e_binary "extract/var/jb/Library/MobileSubstrate/DynamicLibraries/OverlayIOSTOOL.dylib"
    dpkg-deb -Zxz -b extract/ "$DEB_FILE"
    rm -rf extract/
    audit_package "$DEB_FILE"
done

mkdir -p "$SOURCE_DIR/packages"
rm -f "$SOURCE_DIR/packages/"*.deb
cp ./*.deb "$SOURCE_DIR/packages/"

echo ""
echo "========================================="
echo "  BUILD THANH CONG"
echo "========================================="
ls -la "$SOURCE_DIR/packages/"*.deb
