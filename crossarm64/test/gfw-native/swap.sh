#!/bin/bash
# Replace each x64 file of the official tree's usr/ with the ARM64 build at
# the same path in the aarch64 sysroot.  Logs replaced / missing.
N=/c/gfw-native/native; S=/usr/aarch64-pc-cygwin
: > /c/gfw-native/swap-replaced.txt; : > /c/gfw-native/swap-missing.txt
grep '^x64 ' /c/gfw-native/scan-official.txt | cut -d' ' -f2- | while IFS= read -r f; do
  src="$S/$f"
  if [ -f "$src" ] && od -An -tx1 -j$((16#$(od -An -tx1 -j60 -N4 "$src" | awk '{print $4$3$2$1}')+4)) -N2 "$src" | grep -q "64 aa"; then
    cp -f "$src" "$N/$f" && echo "$f" >> /c/gfw-native/swap-replaced.txt
  else
    echo "$f" >> /c/gfw-native/swap-missing.txt
  fi
done
echo "replaced: $(wc -l < /c/gfw-native/swap-replaced.txt)  missing: $(wc -l < /c/gfw-native/swap-missing.txt)"
