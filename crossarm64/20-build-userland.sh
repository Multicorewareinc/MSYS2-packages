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
CONF=${CONF:-$REPO/.ci/makepkg-aarch64-cross.conf}
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
  mkdir -p "$SYSROOT"/usr/bin
  cp -f "$SYSROOT"/bin/msys-2.0.dll "$SYSROOT"/usr/bin/ || exit 1
  # GCC's runtime DLLs (C++ test programs, e.g. gmp's, need cygstdc++-6.dll)
  local gccdir; gccdir=$(dirname "$(aarch64-pc-cygwin-gcc -print-libgcc-file-name)")
  cp -f "$gccdir"/cyg*.dll "$gccdir"/../cyg*.dll "$SYSROOT"/usr/bin/ 2>/dev/null
  mkdir -p "$SYSROOT"/tmp "$SYSROOT"/etc
  [[ -f $SYSROOT/etc/fstab ]] ||
    printf 'none / cygdrive binary,posix=0,noacl,user 0 0\n' > "$SYSROOT"/etc/fstab
  # Programs the build runs on the ARM64 runtime (perl's miniperl reading
  # the header paths the cross preprocessor prints, "make install" with a
  # DESTDIR under /home) are handed the build shell's absolute paths; mount
  # the sysroot and /home at the same paths, so both runtimes resolve them
  # to the same files.
  local m w
  for m in /usr/aarch64-pc-cygwin /home; do
    w=$(cygpath -m "$m")
    grep -q "^[^#]* $m ntfs " "$SYSROOT"/etc/fstab ||
      printf '%s %s ntfs binary,posix=0,noacl 0 0\n' "$w" "$m" >> "$SYSROOT"/etc/fstab
  done
  if [[ -f $SYSROOT/usr/bin/bash.exe ]]; then
    cp -f "$SYSROOT"/usr/bin/bash.exe "$SYSROOT"/usr/bin/sh.exe
  fi
}

for d in "${ORDER[@]}"; do
  echo "=== $(date +%T) building $d"
  cd "$REPO/$d" || exit 1
  # MSYS2's makepkg only checks arch=() in its opt-in lint, so a recipe
  # without an aarch64 arm would be built for the build machine's triplet
  # with the cross compiler and still be named -aarch64 (#55).
  # (Capture first: under pipefail, grep -q exiting early would SIGPIPE
  # makepkg and fail the pipeline even on a match.)
  srcinfo=$(makepkg --config "$CONF" --printsrcinfo 2>/dev/null)
  if ! grep -qE '^[[:space:]]*arch = (aarch64|any)$' <<<"$srcinfo"; then
    echo "FAILED: $d has no aarch64 (or any) in arch=()"; exit 1
  fi
  prepare_cfgroot
  # makepkg (or a tool under it) sometimes just stops, with no error and
  # often with status 0; not understood yet.  Try such a build once more,
  # keeping the first log.
  for try in 1 2; do
    makepkg --config "$CONF" -f -C -d --noconfirm --skippgpcheck --nocheck \
      >"$LOGS/$d.log" 2>&1
    rc=$?
    [[ $rc == 0 ]] && grep -q '^==> Finished making' "$LOGS/$d.log" && break
    [[ $try == 1 ]] || { echo "FAILED: $d (status $rc, log: $LOGS/$d.log)"; tail -30 "$LOGS/$d.log"; exit 1; }
    mv -f "$LOGS/$d.log" "$LOGS/$d.try1.log"
    echo "::warning::$d: makepkg stopped without finishing (status $rc, log: $LOGS/$d.try1.log); trying again"
    tail -5 "$LOGS/$d.try1.log"
  done
  # ld leaves relocations it cannot apply to bfd's generic code, which
  # warns and writes a wrong value (a call to a weak function used to land
  # in another function this way).  The link still succeeds: fail here.
  if grep -q 'relocation not currently supported' "$LOGS/$d.log"; then
    echo "FAILED: $d: ld could not apply some relocations (log: $LOGS/$d.log)"
    grep 'relocation not currently supported' "$LOGS/$d.log" | sort | uniq -c | head
    exit 1
  fi
  # every autoconf configure should have run natively, with nothing guessed
  logs=$(find "$REPO/$d/src" -name config.log 2>/dev/null)
  if [[ -n $logs ]]; then
    cross=$(grep -l "^cross_compiling='\?yes'\?$" $logs | wc -l)
    guess=$(cat $logs | grep -c "guessing")
    echo "  configure: $(echo "$logs" | wc -l) config.log, still cross: $cross, guessed checks: $guess"
  fi
  for p in $(makepkg --config "$CONF" --packagelist 2>/dev/null); do
    [[ -f $p ]] || { echo "FAILED: $d did not create $p (log: $LOGS/$d.log)"; tail -30 "$LOGS/$d.log"; exit 1; }
    bsdtar -xf "$p" -C "$SYSROOT" --exclude '.PKGINFO' --exclude '.BUILDINFO' \
      --exclude '.MTREE' --exclude '.INSTALL' --exclude '.CHANGELOG' ||
      { echo "STAGE FAILED: $p"; exit 1; }
    echo "  staged $(basename "$p")"
    # A DLL or program must use its own startup code: one that imports
    # _msys_dll_entry & co. from another DLL registers that DLL's data with
    # the runtime and loses its own across fork() (#57).
    for f in $(bsdtar -tf "$p" | grep -iE '\.(dll|exe)$'); do
      borrowed=$(aarch64-pc-cygwin-objdump -p "$SYSROOT/$f" 2>/dev/null |
        sed -n '/^The Import Tables/,/^The Export Tables/p' |
        awk '/DLL Name/ {d = $3}
             $NF ~ /^(_msys_dll_entry|_msys_crt0_common|msys_attach_dll|DllMain|_cygwin_dll_entry)$/ {print d ":" $NF}')
      [[ -z $borrowed ]] ||
        { echo "FAILED: $f imports runtime startup symbols: $borrowed (#57)"; exit 1; }
    done
  done
done
echo "=== $(date +%T) userland done"
