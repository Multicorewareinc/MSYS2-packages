#!/usr/bin/env bash
# CI stage 1: the cross toolchain and both runtime stages.
#
# Rebuilt only when one of the toolchain recipes (or the driver script)
# changed since the last successful build, or with FORCE_TOOLCHAIN=true.
# The recipes are built in $STATE/toolchain, not in the checkout, so the
# runtime build tree (which the winsup testsuite runs from, with absolute
# paths in its Makefiles) survives the next run's checkout.  Afterwards the
# sysroot is saved; every run's userland starts from that snapshot.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TC=$STATE/toolchain
STAMP=$STATE/toolchain.sha256
cd "$REPO"
recipes=(cross-msysarm64-* msys2-runtime-aarch64 msys2-runtime-aarch64-stage-2)
hash=$(find "${recipes[@]}" crossarm64/10-build-toolchain.sh -type f | LC_ALL=C sort |
       xargs sha256sum | sha256sum | cut -d' ' -f1)
echo "toolchain recipes: $hash"

if [[ ${FORCE_TOOLCHAIN:-false} != true && -f $STAMP && $(cat "$STAMP") == "$hash" &&
      -f $SNAPSHOT && -d $TC/msys2-runtime-aarch64-stage-2/src ]]; then
  echo "unchanged since the last build: reusing the installed toolchain"
  exit 0
fi
rm -f "$STAMP"

group "Remove the previous toolchain"
installed=$(pacman -Qq | grep -E '^cross-msysarm64-' || true)
[[ -z $installed ]] || pacman -Rdd --noconfirm $installed
rm -rf "$SYSROOT"
endgroup

group "Copy the recipes to $TC"
rm -rf "$TC"; mkdir -p "$TC"
cp -a "${recipes[@]}" crossarm64 "$TC/"
endgroup

# 10-build-toolchain.sh prints one line per recipe; the logs go to the artifact
PKGDEST=$STATE/toolchain-pkgs bash "$TC/crossarm64/10-build-toolchain.sh"
mkdir -p "$RESULTS/logs"; cp -a "$STATE/toolchain-pkgs/logs/." "$RESULTS/logs/"

group "Save the sysroot"
bsdtar -cf "$SNAPSHOT" -C / "${SYSROOT#/}"
ls -l "$SNAPSHOT"
endgroup
echo "$hash" > "$STAMP"
