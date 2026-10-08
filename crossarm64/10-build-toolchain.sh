#!/usr/bin/env bash
# Build and install the aarch64-pc-cygwin cross toolchain in bootstrap order.
#
#   bash crossarm64/10-build-toolchain.sh [recipe-dir ...]
#
# Each recipe is built with makepkg and pacman -U'd before the next one, since
# every step configures against what the previous ones installed.  Packages
# go to $PKGDEST (default: ../aarch64-pkgs next to the repo), logs to
# $PKGDEST/logs/<recipe>.log.  Run crossarm64/40-winsup-test.sh after the
# stage-2 runtime.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PKGDEST="${PKGDEST:-$(dirname "$REPO")/aarch64-pkgs}"
LOGS=$PKGDEST/logs
mkdir -p "$LOGS"

ORDER=(
  cross-msysarm64-w32api-headers
  cross-msysarm64-runtime-devel
  cross-msysarm64-binutils
  cross-msysarm64-windows-default-manifest
  cross-msysarm64-w32api-runtime
  cross-msysarm64-gcc-stage1
  msys2-runtime-aarch64
  cross-msysarm64-gcc
  msys2-runtime-aarch64-stage-2
)
[[ $# -gt 0 ]] && ORDER=("$@")

for d in "${ORDER[@]}"; do
  echo "=== $(date +%T) building $d"
  cd "$REPO/$d" || exit 1
  # -C: always start from a clean src/.  Re-applying the woarm64 series over
  # a reused working copy fails on files the previous run's patches created.
  if ! makepkg -f -C --noconfirm --skippgpcheck --nocheck >"$LOGS/$d.log" 2>&1; then
    echo "FAILED: $d (log: $LOGS/$d.log)"; tail -30 "$LOGS/$d.log"; exit 1
  fi
  pkgs=$(makepkg --packagelist 2>/dev/null)
  echo "  built: $(echo $pkgs | xargs -n1 basename | tr '\n' ' ')"
  # stage-2 gcc ships the same /usr/bin drivers as stage 1, which declares no
  # conflicts; stage 1 is a bootstrap intermediate, so retire it first.
  if [[ $d == cross-msysarm64-gcc ]] && pacman -Q cross-msysarm64-gcc-stage1 >/dev/null 2>&1; then
    pacman -R --noconfirm cross-msysarm64-gcc-stage1 >>"$LOGS/$d.log" 2>&1 &&
      echo "  removed cross-msysarm64-gcc-stage1 (superseded)"
  fi
  if ! pacman -U --noconfirm $pkgs >>"$LOGS/$d.log" 2>&1; then
    echo "  retrying install with --overwrite on the sysroot"
    pacman -U --noconfirm --overwrite '/usr/aarch64-pc-cygwin/*' $pkgs >>"$LOGS/$d.log" 2>&1 ||
      { echo "INSTALL FAILED: $d"; tail -20 "$LOGS/$d.log"; exit 1; }
  fi
  echo "  installed"
done
echo "=== $(date +%T) toolchain done"
