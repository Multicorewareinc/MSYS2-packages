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
# the rest of what MinGit ships in usr/bin: dash, getopt (util-linux), rebase
MINGIT_EXTRA=(dash util-linux rebase)
ORDER=("${BASH_CHAIN[@]}" "${SSH_CHAIN[@]}" "${MINGIT_EXTRA[@]}")
[[ $# -gt 0 ]] && ORDER=("$@")


# The sysroot's bare include directory is searched before usr/include, so a
# stray newlib header there silently changes every package: refuse to build
# unless it holds runtime-devel's configured newlib.h and none of the
# headers that belong to libiconv or ncurses (#26).
for h in include sys-include usr/include usr/sys-include; do
  if ! grep -q _HAVE_LONG_DOUBLE "$SYSROOT/$h/newlib.h" 2>/dev/null; then
    echo "ERROR: $SYSROOT/$h/newlib.h is not the configured one (reinstall cross-msysarm64-runtime-devel)"; exit 1
  fi
done
for f in include/iconv.h include/unctrl.h sys-include/iconv.h sys-include/unctrl.h; do
  [[ -e $SYSROOT/$f ]] && { echo "ERROR: $SYSROOT/$f shadows the libiconv/ncurses header; remove it"; exit 1; }
done
# configure runs its test programs natively (crossarm64/config.site).  They
# run on the ARM64 runtime with the sysroot as their root: msys-2.0.dll in
# $SYSROOT/usr/bin (found at the end of PATH, set in the makepkg config) makes
# $SYSROOT "/", and an fstab, /tmp and sh give the test programs the usual
# environment (gnulib's pthread_sigmask check, for one, runs "sh -c 'kill
# ...'" through system()).  The Windows loader skips DLLs built for another
# machine, so the x86-64 build tools still load their own from /usr/bin.
prepare_cfgroot() {
  cp -f "$SYSROOT"/bin/msys-2.0.dll "$SYSROOT"/usr/bin/ || exit 1
  mkdir -p "$SYSROOT"/tmp "$SYSROOT"/etc
  [[ -f $SYSROOT/etc/fstab ]] ||
    printf 'none / cygdrive binary,posix=0,noacl,user 0 0\n' > "$SYSROOT"/etc/fstab
  if [[ -f $SYSROOT/usr/bin/bash.exe ]]; then
    cp -f "$SYSROOT"/usr/bin/bash.exe "$SYSROOT"/usr/bin/sh.exe
  fi
}

for d in "${ORDER[@]}"; do
  echo "=== $(date +%T) building $d"
  cd "$REPO/$d" || exit 1
  prepare_cfgroot
  if ! makepkg --config "$CONF" -f -C -d --noconfirm --skippgpcheck --nocheck \
       >"$LOGS/$d.log" 2>&1; then
    echo "FAILED: $d (log: $LOGS/$d.log)"; tail -30 "$LOGS/$d.log"; exit 1
  fi
  # every autoconf configure should have run natively, with nothing guessed
  logs=$(find "$REPO/$d/src" -name config.log 2>/dev/null)
  if [[ -n $logs ]]; then
    cross=$(grep -l "^cross_compiling='\?yes'\?$" $logs | wc -l)
    guess=$(cat $logs | grep -c "guessing")
    echo "  configure: $(echo "$logs" | wc -l) config.log, still cross: $cross, guessed checks: $guess"
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
