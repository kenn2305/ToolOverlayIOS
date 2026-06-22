#!/bin/bash

# DEBUG_QUICK_START.sh - Hướng dẫn nhanh debug OverlayIOSTool
# Cách dùng: 
#   1. SSH vào iPhone: ssh root@<IP>
#   2. Chạy: bash debug_quick_start.sh
#   3. Tap "Chọn Ảnh" ở app, chọn ảnh
#   4. Copy logs vào report

echo "=========================================="
echo "OverlayIOSTool v2.0.1 - DEBUG QUICK START"
echo "=========================================="
echo ""

# Check if running on iPhone
if ! command -v log &> /dev/null; then
    echo "❌ Error: This script must be run on iPhone via SSH"
    echo "Run: ssh root@<IP> 'bash -c \"$(cat debug_quick_start.sh)\"'"
    exit 1
fi

echo "📱 Device Info:"
echo "  - iOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'N/A')"
echo "  - Device: $(getprop ro.product.model 2>/dev/null || echo 'N/A')"
echo ""

echo "🔍 Checking tweak installation..."
if [ -f "/Library/MobileSubstrate/DynamicLibraries/OverlayIOSTool.dylib" ]; then
    echo "  ✅ Tweak installed"
else
    echo "  ❌ Tweak NOT found at /Library/MobileSubstrate/DynamicLibraries/"
fi

if [ -d "/Applications/OverlayToolApp.app" ]; then
    echo "  ✅ Companion app installed"
else
    echo "  ❌ Companion app NOT found at /Applications/OverlayToolApp.app"
fi

echo ""
echo "📂 Checking file permissions..."
APP_DOCS=$(find /var/mobile/Containers/Data/Application -type d -name "Documents" | head -1)
if [ -n "$APP_DOCS" ]; then
    echo "  📁 App Documents: $APP_DOCS"
    ls -lah "$APP_DOCS" 2>/dev/null | head -5
else
    echo "  ⚠️  App Documents folder not found yet (will be created on first launch)"
fi

echo ""
echo "=========================================="
echo "🚀 LIVE LOG STREAM (Press Ctrl+C to stop)"
echo "=========================================="
echo ""
echo "Instructions:"
echo "  1. Keep this terminal open"
echo "  2. Open OverlayToolApp on your iPhone"
echo "  3. Tap 'Chọn Ảnh' button"
echo "  4. Select an image from Photos"
echo "  5. Watch logs appear below"
echo ""
echo "Starting log stream..."
echo "=========================================="
echo ""

log stream --predicate 'message contains "OverlayIOSTool"' --level debug

echo ""
echo "=========================================="
echo "📋 To save logs to file:"
echo "  log collect --output overlay_logs_$(date +%Y%m%d_%H%M%S).logarchive"
echo ""
echo "Then on Mac/Linux:"
echo "  scp root@<IP>:overlay_logs*.logarchive ~/Desktop/"
echo "=========================================="
