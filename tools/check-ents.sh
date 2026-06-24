#!/bin/bash
LDID=/home/builder/theos/bin/ldid
APP=/home/builder/OverlayIOSTOOL-build/.theos/obj/arm64/OverlayIOSTOOLApp.app/OverlayIOSTOOLApp
echo "=== Entitlements nhung trong app ==="
"$LDID" -e "$APP" 2>/dev/null
echo "=== (kiem tra cac key quan trong) ==="
"$LDID" -e "$APP" 2>/dev/null | grep -iE 'platform-application|no-container|container-required' && echo "-> CO ENTITLEMENTS" || echo "-> THIEU ENTITLEMENTS"
