#!/bin/bash
echo "===== WHOAMI / ARCH ====="; whoami; uname -m
echo "===== THEOS LOCATIONS ====="
for d in /home/builder/theos "$HOME/theos" /opt/theos /usr/local/theos /root/theos; do
  [ -f "$d/makefiles/common.mk" ] && echo "FOUND theos: $d"
done
echo "===== TOOLCHAIN ====="
for d in /home/builder/theos "$HOME/theos" /opt/theos /root/theos; do
  c="$d/toolchain/linux/iphone/bin/clang"
  if [ -x "$c" ]; then
    printf "clang: %s  type: " "$c"
    if head -c2 "$c" | grep -q "#!"; then echo "WRAPPER(hong)"; else echo "ELF-that"; fi
  fi
done
echo "===== SDKs ====="
for d in /home/builder/theos "$HOME/theos" /opt/theos /root/theos; do
  ls -d "$d"/sdks/iPhoneOS*.sdk 2>/dev/null
done
echo "===== ldid ====="
command -v ldid 2>/dev/null
for d in /home/builder/theos "$HOME/theos" /opt/theos /root/theos; do
  [ -x "$d/bin/ldid" ] && echo "$d/bin/ldid"
done
echo "===== build tools ====="
for t in make perl fakeroot dpkg-deb dpkg-dev rsync zstd curl git; do
  printf "%-10s " "$t"; command -v "$t" 2>/dev/null || echo MISSING
done
echo "===== sizes ====="
for d in /home/builder/theos "$HOME/theos" /opt/theos /root/theos; do
  [ -d "$d" ] && du -sh "$d" 2>/dev/null
  [ -d "$d/toolchain" ] && du -sh "$d/toolchain" 2>/dev/null
  [ -d "$d/sdks" ] && du -sh "$d/sdks" 2>/dev/null
done
