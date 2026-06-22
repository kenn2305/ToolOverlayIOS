#!/bin/bash
D="$(ls -t packages/*.deb 2>/dev/null | head -1)"
echo "DEB: $D"
echo "===== control ====="
dpkg-deb -I "$D"
echo "===== noi dung ====="
dpkg-deb -c "$D" | awk '{print $1, $6, $7, $8}'
