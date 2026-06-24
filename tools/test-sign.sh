#!/bin/bash
LDID=/home/builder/theos/bin/ldid
ENTS=/home/builder/OverlayIOSTOOL-build/entitlements.plist
APP=/home/builder/OverlayIOSTOOL-build/.theos/obj/arm64/OverlayIOSTOOLApp.app/OverlayIOSTOOLApp

echo "=== ldid version ==="; "$LDID" 2>&1 | head -2
echo "=== ky tay voi -S<ents> ==="
"$LDID" -S"$ENTS" "$APP" && echo "ky OK" || echo "ky LOI"
echo "=== kiem tra lai ==="
"$LDID" -e "$APP" 2>/dev/null | grep -iE 'platform-application|no-container' && echo "-> NHUNG DUOC" || echo "-> VAN THIEU"
