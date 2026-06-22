#!/bin/bash
# Mo phong may khach "trang": doi ten env hien co, ep build-offline.sh
# tu giai nen tu bundle roi build. PASS = khach bam 1 nut ra .deb that.
set -e
ORIG=/home/builder/theos
BAK=/home/builder/theos.orig

echo "===== CLEAN-TEST: gia lap may khach chua co Theos ====="
[ -d "$BAK" ] && rm -rf "$BAK"
[ -d "$ORIG" ] && mv "$ORIG" "$BAK"
rm -rf /home/builder/OverlayIOSTOOL-build
rm -f /mnt/e/OverlayIOSTOOL/packages/*.deb 2>/dev/null || true

cd /mnt/e/OverlayIOSTOOL
if bash build-offline.sh; then
    echo "===== CLEAN-TEST: PASS — bundle tu du de build ====="
    rm -rf "$BAK"
    exit 0
else
    echo "===== CLEAN-TEST: FAIL — khoi phuc env goc ====="
    rm -rf "$ORIG"
    [ -d "$BAK" ] && mv "$BAK" "$ORIG"
    exit 1
fi
