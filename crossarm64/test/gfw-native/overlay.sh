#!/bin/bash
# For every MSYS-side package Git for Windows lists, overlay our aarch64 build
# of that package: every file of our package whose path exists in the
# official tree replaces it (so .pm files match their XS .dll).
N=/c/gfw-native/native; O=/c/gfw-native/official; X=/c/gfw-native/x; mkdir -p $X
: > /c/gfw-native/overlay-log.txt
pick() { ls -t ${PKGDEST:-$HOME/aarch64-pkgs}/userland/$1-[0-9]*-aarch64.pkg.tar.zst 2>/dev/null | head -1; }
awk '{print $1}' $O/etc/package-versions.txt | grep -v '^mingw-w64' | while read -r name; do
  lname=$(echo "$name" | tr 'A-Z' 'a-z')
  p=$(pick "$name"); [ -z "$p" ] && p=$(pick "$lname")
  [ -z "$p" ] && { echo "nobuild $name" >> /c/gfw-native/overlay-log.txt; continue; }
  rm -rf $X/p; mkdir -p $X/p; tar xf "$p" -C $X/p 2>/dev/null
  n=0
  while IFS= read -r f; do
    [ -f "$O/$f" ] || continue
    cp -f "$X/p/$f" "$N/$f" && n=$((n+1))
  done < <(cd $X/p && find usr -type f)
  echo "overlay $name <- $(basename "$p") ($n files)" >> /c/gfw-native/overlay-log.txt
done
rm -rf $X
grep -c '^overlay' /c/gfw-native/overlay-log.txt; grep '^nobuild' /c/gfw-native/overlay-log.txt | awk '{print $2}' | tr '\n' ' '
