#!/bin/bash
N=/c/gfw-native/native; S=/usr/aarch64-pc-cygwin
isarm() { local o; o=$(od -An -tx1 -j60 -N4 "$1" | awk '{print $4$3$2$1}'); od -An -tx1 -j$((16#$o+4)) -N2 "$1" | grep -q "64 aa"; }
# 1. runtime utilities (the sysroot's bin/ also has the x86 cross binutils: machine-checked)
while read -r f; do b=${f##*/}
  if [ -f "$S/bin/$b" ] && isarm "$S/bin/$b"; then cp -f "$S/bin/$b" "$N/$f" && echo "$f" >> /c/gfw-native/swap-replaced.txt && sed -i "\|^$f\$|d" /c/gfw-native/swap-missing.txt; fi
done < <(cp /c/gfw-native/swap-missing.txt /tmp/m.txt; cat /tmp/m.txt)
# 2. the ARM64 runtime's own helper (getprocaddr64 stays: it serves x64 processes)
cp -f $S/libexec/getprocaddrarm64.exe $N/usr/libexec/ && echo "added usr/libexec/getprocaddrarm64.exe"
# 3. new runtime DLLs our builds import
for d in msys-cbor-0.14.dll cyggcc_s-seh-1.dll; do cp -f $S/usr/bin/$d $N/usr/bin/ && echo "added usr/bin/$d"; done
# 4. lesskey: not in less 710 (ours, and MSYS2's current x86 package)
rm -f $N/usr/bin/lesskey.exe && sed -i '\|^usr/bin/lesskey.exe$|d' /c/gfw-native/swap-missing.txt && echo "removed usr/bin/lesskey.exe (less 704 -> 710)"
echo "still missing:"; cat /c/gfw-native/swap-missing.txt
