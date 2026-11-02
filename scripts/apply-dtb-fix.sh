#!/bin/sh
# Apply the SD-card fix to a live postmarketOS install on Xiaomi Redmi 7A (pine)
# by patching the DTB in /boot.  Requires: dtc, python3, root.
#
#   sudo sh apply-dtb-fix.sh            # apply
#   sudo sh apply-dtb-fix.sh --revert   # revert
set -e

DTB=/boot/sdm439-xiaomi-pine.dtb
BAK="${DTB}.bak-xh-sdfix"
TMP=$(mktemp -d)

if [ "$1" = "--revert" ]; then
    [ -f "$BAK" ] || { echo "no backup at $BAK"; exit 1; }
    cp -f "$BAK" "$DTB"
    echo "reverted $DTB"
    exit 0
fi

[ -f "$DTB" ] || { echo "$DTB not found"; exit 1; }
command -v dtc >/dev/null || { echo "install dtc first: apk add dtc"; exit 1; }

[ -f "$BAK" ] || cp -f "$DTB" "$BAK"

dtc -I dtb -O dts -o "$TMP/in.dts" "$DTB" 2>/dev/null
if grep -q "no-1-8-v" "$TMP/in.dts"; then
    echo "already patched"; exit 0
fi

python3 - "$TMP/in.dts" "$TMP/out.dts" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
m = re.search(r'(mmc@7864900\s*\{.*?cd-gpios\s*=\s*<[^>]*>;)(.*?)(vmmc-supply\s*=\s*<0x[0-9a-f]+>;)', s, re.S)
if not m:
    print("mmc@7864900 not found - aborting"); sys.exit(1)
vmmc = m.group(3)
ph = re.search(r'<0x([0-9a-f]+)>', vmmc).group(1)
body = re.sub(r'vqmmc-supply\s*=\s*<0x[0-9a-f]+>;', '', m.group(2))
ins = "\n\t\t\tbroken-cd;\n\t\t\tno-1-8-v;\n\t\t\tvqmmc-supply = <0x%s>;" % ph
s = s[:m.start()] + m.group(1) + body + ins + vmmc + s[m.end():]
open(dst, 'w').write(s)
print("patched: vqmmc -> vmmc rail (0x%s), added no-1-8-v + broken-cd" % ph)
PY

dtc -I dts -O dtb -o "$TMP/out.dtb" "$TMP/out.dts" 2>/dev/null
cp -f "$TMP/out.dtb" "$DTB"
echo "done. reboot to apply.  backup kept at $BAK"
