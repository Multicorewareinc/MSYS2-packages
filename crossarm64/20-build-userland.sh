#!/usr/bin/env bash
# Cross-build the aarch64-pc-cygwin userland -- the bash chain, then the ssh
# chain -- with the native recipes' aarch64 arms.
#
#   bash crossarm64/20-build-userland.sh [recipe-dir ...]
#
# The recipes look for their dependencies under /usr/aarch64-pc-cygwin/usr,
# so each package is unpacked into the toolchain sysroot before the next one
# configures.  -d: their depends name host packages (ncurses-devel, ...).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF=$REPO/.ci/makepkg-aarch64-cross.conf
SYSROOT=/usr/aarch64-pc-cygwin
OUTDIR="${PKGDEST:-$(dirname "$REPO")/aarch64-pkgs}"
export PKGDEST=$OUTDIR/userland
LOGS=$OUTDIR/logs
mkdir -p "$PKGDEST" "$LOGS"

BASH_CHAIN=(libiconv gettext ncurses readline bash gmp coreutils
            mpfr gawk sed grep diffutils findutils hexdump)
SSH_CHAIN=(zlib openssl libxcrypt libcbor libfido2 libedit db sqlite heimdal openssh)
ORDER=("${BASH_CHAIN[@]}" "${SSH_CHAIN[@]}")
[[ $# -gt 0 ]] && ORDER=("$@")

for d in "${ORDER[@]}"; do
  echo "=== $(date +%T) building $d"
  cd "$REPO/$d" || exit 1
  if ! makepkg --config "$CONF" -f -C -d --noconfirm --skippgpcheck --nocheck \
       >"$LOGS/$d.log" 2>&1; then
    echo "FAILED: $d (log: $LOGS/$d.log)"; tail -30 "$LOGS/$d.log"; exit 1
  fi
  for p in $(makepkg --config "$CONF" --packagelist 2>/dev/null); do
    [[ -f $p ]] || { echo "  missing $p"; continue; }
    bsdtar -xf "$p" -C "$SYSROOT" --exclude '.PKGINFO' --exclude '.BUILDINFO' \
      --exclude '.MTREE' --exclude '.INSTALL' --exclude '.CHANGELOG' ||
      { echo "STAGE FAILED: $p"; exit 1; }
    echo "  staged $(basename "$p")"
  done
done
echo "=== $(date +%T) userland done"
