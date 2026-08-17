#!/usr/bin/env bash
# Install the prebuilt aarch64 cross toolchain from a directory of .pkg.tar.zst
# files, in dependency order.
#
#   ./01-install-toolchain.sh [dir]        # default: $HOME, then this directory
#   ./01-install-toolchain.sh --list [dir] # show what would be installed
#   MINGW=0 ./01-install-toolchain.sh      # skip the MinGW-ARM64 cross family
#
# Two separate toolchains live in these files:
#
#   mingw-w64-cross-mingwarm64-*  a MinGW ARM64 cross compiler.  Not needed to
#                                 *use* the msys toolchain - it is a build
#                                 dependency of cross-msysarm64-w32api-runtime,
#                                 so it is only required if you intend to
#                                 rebuild that package.
#   cross-msysarm64-*             the aarch64-pc-msys cross toolchain that
#                                 everything in crossarm64/ builds against.
#
# Order matters: pacman refuses a package whose dependencies are not yet
# present.  Dependencies that live in the msys repos (zlib, mpc, isl, libzstd,
# libiconv, libintl, mingw-w64-cross-common-binutils) are pulled in
# automatically, so the machine needs working repos.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LIST_ONLY=0
[[ ${1:-} == --list ]] && { LIST_ONLY=1; shift; }

PKGDIR="${1:-}"
if [[ -z $PKGDIR ]]; then
  for d in "$HOME" "$(dirname "${BASH_SOURCE[0]}")" .; do
    if ls "$d"/cross-msysarm64-*.pkg.tar.zst >/dev/null 2>&1; then PKGDIR="$d"; break; fi
  done
fi
[[ -n $PKGDIR && -d $PKGDIR ]] ||
  die "no directory with cross-msysarm64-*.pkg.tar.zst found; pass one as an argument"
PKGDIR="$(cd "$PKGDIR" && pwd)"

# --- install order -----------------------------------------------------------
#
# Within each group, every package's dependencies come earlier in the list.
# Derived from the .PKGINFO of the packages themselves, not guessed:
#
#   w32api-runtime  -> w32api-headers
#   mingwarm64-crt  -> mingwarm64-headers
#   winpthreads     -> crt
#   mingwarm64-gcc  -> crt, headers, winpthreads, windows-default-manifest, binutils
#   cross-zlib      -> mingwarm64-zlib
#
# runtime, newlib and runtime-devel declare no dependencies, but they populate
# the sysroot that gcc compiles against, so gcc goes last.

MINGW_ORDER=(
  mingw-w64-cross-mingwarm64-headers
  mingw-w64-cross-mingwarm64-windows-default-manifest
  mingw-w64-cross-mingwarm64-zlib
  mingw-w64-cross-zlib
  mingw-w64-cross-mingwarm64-crt
  mingw-w64-cross-mingwarm64-winpthreads
  mingw-w64-cross-mingwarm64-binutils
  mingw-w64-cross-mingwarm64-gcc
)

MSYS_ORDER=(
  cross-msysarm64-w32api-headers
  cross-msysarm64-w32api-runtime
  cross-msysarm64-binutils
  cross-msysarm64-runtime
  cross-msysarm64-newlib
  cross-msysarm64-runtime-devel
  cross-msysarm64-gcc
)

# Newest file for an exact package name.  The glob <name>-*.pkg.tar.zst also
# matches longer names - cross-msysarm64-runtime-* catches runtime-devel too -
# so each candidate's real name is read back from the package.
# Note the "|| true" on every pacman pipeline below.  lib.sh sets pipefail, and
# `awk ... exit` closes the pipe early enough that pacman takes a SIGPIPE - the
# pipeline then reports failure, and set -e kills the script at a different
# point on every run.
pkg_field() {
  local file="$1" field="$2" out
  out=$(pacman -Qip "$file" 2>/dev/null | awk -F': ' -v f="$field"         '$0 ~ "^"f {gsub(/^ +| +$/, "", $2); print $2; exit}') || true
  printf '%s' "$out"
}

find_pkg() {
  local want="$1" f name best=
  for f in "${PKGDIR}/${want}"-*.pkg.tar.zst; do
    [[ -e $f ]] || continue
    name=$(pkg_field "$f" Name)
    [[ $name == "$want" ]] || continue
    [[ -z $best || $f -nt $best ]] && best="$f"
  done
  printf '%s' "$best"
  return 0
}

install_group() {
  local label="$1"; shift
  local order=("$@")
  local pkg file installed_ver file_ver missing=()

  msg "${label}"
  for pkg in "${order[@]}"; do
    file=$(find_pkg "$pkg")
    if [[ -z $file ]]; then
      missing+=("$pkg")
      printf '  %-52s not found in %s\n' "$pkg" "$PKGDIR"
      continue
    fi
    file_ver=$(pkg_field "$file" Version)
    installed_ver=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}') || true

    if [[ $LIST_ONLY -eq 1 ]]; then
      printf '  %-52s %-14s %s\n' "$pkg" "$file_ver" \
             "${installed_ver:+(installed: ${installed_ver})}"
      continue
    fi
    if [[ $installed_ver == "$file_ver" ]]; then
      printf '  %-52s %-14s already installed\n' "$pkg" "$file_ver"
      continue
    fi
    printf '  %-52s %-14s installing\n' "$pkg" "$file_ver"
    pacman -U --noconfirm "$file" >/dev/null 2>&1 || {
      # Re-run showing the error, so the reason is visible rather than swallowed.
      pacman -U --noconfirm "$file" 2>&1 | tail -8 >&2
      die "failed to install ${pkg}"
    }
  done

  [[ ${#missing[@]} -gt 0 ]] &&
    warn "${label}: ${#missing[@]} package(s) not present in ${PKGDIR}"
  return 0
}

msg "package directory: ${PKGDIR}"

if [[ ${MINGW:-1} -eq 1 ]]; then
  install_group "MinGW ARM64 cross toolchain (only needed to rebuild w32api-runtime)" \
                "${MINGW_ORDER[@]}"
else
  msg "skipping the MinGW ARM64 family (MINGW=0)"
fi

install_group "aarch64-pc-msys cross toolchain" "${MSYS_ORDER[@]}"

if [[ $LIST_ONLY -eq 1 ]]; then
  msg "nothing was installed (--list)"
  exit 0
fi

msg "verifying"
require_toolchain
check_unowned_sysroot_files
fix_shadowing_headers

msg "toolchain ready - run ./10-packages.sh next, or ./build-all.sh"
