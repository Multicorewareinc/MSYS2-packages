#!/usr/bin/env bash
# Put the stage-1 runtime into the sysroot when the toolchain came from
# PACKAGES (CI artifacts, a repo) instead of 10-build-toolchain.sh.
#
#   bash crossarm64/15-prestage-sysroot.sh
#
# cross-msysarm64-gcc's build() copies lib/bootstrap-stage1/{crt0.o, gcrt0.o,
# libmsys-2.0.a, libc.a, libm.a, libg.a} into /usr/aarch64-pc-cygwin/lib and
# links libcygwin.a -> libmsys-2.0.a.  Those copies belong to no package, so
# on a machine that only INSTALLED the toolchain packages they are missing and
# msys2-runtime-aarch64-stage-2 fails with "cannot find crt0.o".  This does
# the same copy.  Not needed after 10-build-toolchain.sh (gcc's build() did it).
set -uo pipefail
L=/usr/aarch64-pc-cygwin/lib
B=$L/bootstrap-stage1
[[ -d $B ]] || { echo "ERROR: $B missing - install cross-msysarm64-runtime (stage 1) first"; exit 1; }
for f in libmsys-2.0.a libc.a libm.a libg.a crt0.o gcrt0.o; do
  [[ -f $B/$f ]] && cp -f "$B/$f" "$L/$f" && echo "staged $f"
done
ln -sf libmsys-2.0.a "$L/libcygwin.a"
# a stub crt0.o (see msys2-runtime-aarch64's prepare()) makes every program
# linked with it hang at startup
if aarch64-pc-cygwin-nm "$L/crt0.o" | grep -q 'U msys_crt0'; then
  echo "crt0.o is the real one"
else
  echo "ERROR: $L/crt0.o is a stub"; exit 1
fi
