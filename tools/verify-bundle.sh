#!/bin/bash
B="buildenv/OverlayIOSTOOL-buildenv-linux-x86_64.tar.gz"
echo "===== gzip integrity ====="
gzip -t "$B" && echo "GZIP OK" || echo "GZIP HONG"
echo "===== size ====="
ls -la "$B" | awk '{print $5" bytes"}'
echo "===== thanh phan quan trong ====="
tar -tzf "$B" | grep -E 'theos/makefiles/common.mk|theos/toolchain/linux/iphone/bin/clang$|theos/bin/ldid$|theos/sdks/iPhoneOS16.5.sdk/SDKSettings.plist|MANIFEST.txt' | sed 's/^/  ok: /'
echo "===== thong ke ====="
printf "Tong entry : "; tar -tzf "$B" | wc -l
printf "So SDK dir : "; tar -tzf "$B" | grep -cE 'theos/sdks/iPhoneOS[0-9.]+\.sdk/$'
printf "So apt deb : "; tar -tzf "$B" | grep -cE 'apt-debs/.*\.deb$'
