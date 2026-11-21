#!/bin/bash
# For every ARM64 PE under usr/: imports that are neither in usr/bin nor Windows system DLLs.
N=/c/gfw-native/native; cd $N
bash /c/gfw-native/pescan.sh $N > /c/gfw-native/scan-native.txt
ls usr/bin | tr 'A-Z' 'a-z' > /tmp/have.txt
: > /c/gfw-native/deps-missing.txt; : > /c/gfw-native/deps-users.txt
grep '^arm64 usr/' /c/gfw-native/scan-native.txt | cut -d' ' -f2- | while IFS= read -r f; do
  aarch64-pc-cygwin-objdump -p "$f" 2>/dev/null | sed -n 's/^\tDLL Name: //p' | while read -r d; do
    l=$(echo "$d" | tr 'A-Z' 'a-z')
    echo "$l $f" >> /c/gfw-native/deps-users.txt
    case $l in msys-*|cyg*) grep -qx "$l" /tmp/have.txt || echo "$f -> $d" >> /c/gfw-native/deps-missing.txt;; esac
  done
done
echo "unresolved msys-/cyg imports: $(wc -l < /c/gfw-native/deps-missing.txt)"; sort -u /c/gfw-native/deps-missing.txt | head -20
echo "importers of msys-cbor-0.11.dll / msys-gcc_s-seh-1.dll:"; grep -E "^(msys-cbor-0.11.dll|msys-gcc_s-seh-1.dll) " /c/gfw-native/deps-users.txt | head
echo "importers of cyggcc_s-seh-1.dll: $(grep -c '^cyggcc_s-seh-1.dll ' /c/gfw-native/deps-users.txt)"
