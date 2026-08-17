# Shared helpers for the aarch64-pc-msys build scripts.  Sourced, not executed.

set -euo pipefail

CROSSARM64_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${CROSSARM64_DIR}/.." && pwd)"
PROFILE="${CROSSARM64_DIR}/makepkg-crossarm64.conf"

TARGET=aarch64-pc-msys
SYSROOT="/usr/${TARGET}"

# Where built packages land.  Overridable; the makepkg profile honours PKGDEST
# from the environment.
export PKGDEST="${PKGDEST:-${REPO_DIR}/aarch64-pkgs}"
LOGDIR="${LOGDIR:-${PKGDEST}/logs}"

# A gnupg.org mirror.  gnupg.org answers 403 to curl from some networks, and
# three packages take their sources from there; see fetch_gnupg_sources.
GNUPG_MIRROR="${GNUPG_MIRROR:-https://www.mirrorservice.org/sites/ftp.gnupg.org/gcrypt}"

msg()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# The toolchain is not built by these scripts - install it first.  Without this
# check the first package fails with a confusing "compiler cannot create
# executables" a few minutes in.
require_toolchain() {
  local missing=() p
  for p in cross-msysarm64-binutils cross-msysarm64-gcc cross-msysarm64-runtime \
           cross-msysarm64-runtime-devel cross-msysarm64-newlib \
           cross-msysarm64-w32api-headers cross-msysarm64-w32api-runtime; do
    pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '  missing: %s\n' "${missing[@]}" >&2
    die "the aarch64 cross toolchain is not installed; install it before running this"
  fi
  command -v "${TARGET}-gcc" >/dev/null 2>&1 ||
    die "${TARGET}-gcc is not on PATH even though the packages are installed"
  msg "toolchain present: $(${TARGET}-gcc -dumpversion) ($(${TARGET}-gcc -dumpmachine))"
}

# cross-msysarm64-runtime-devel ships newlib headers that shadow the real
# packages - iconv.h at several paths, plus unctrl.h and stdatomic.h.  Left in
# place, anything built afterwards silently links the runtime's iconv instead of
# libiconv, and curl fails to compile outright on the broken stdatomic.h.
#
# See MSYS2-packages#26.  Once that package stops shipping them this becomes a
# no-op, which is why it only reports what it actually removed.
fix_shadowing_headers() {
  local removed=0 f
  for f in "${SYSROOT}"/include/iconv.h \
           "${SYSROOT}"/sys-include/iconv.h \
           "${SYSROOT}"/usr/sys-include/iconv.h \
           "${SYSROOT}"/include/unctrl.h \
           "${SYSROOT}"/sys-include/unctrl.h \
           "${SYSROOT}"/include/stdatomic.h \
           "${SYSROOT}"/sys-include/stdatomic.h \
           "${SYSROOT}"/usr/sys-include/stdatomic.h; do
    [[ -e $f ]] || continue
    rm -f "$f" && removed=$((removed + 1))
  done
  if [[ $removed -gt 0 ]]; then
    msg "removed ${removed} shadowing newlib header(s) - see MSYS2-packages#26"
  fi
}

# Files in the sysroot owned by no package can shadow packaged ones - a stale
# msys-z.dll and six empty w32api stub archives were found this way.  Report
# them rather than deleting anything automatically.
check_unowned_sysroot_files() {
  local f found=0
  for f in "${SYSROOT}"/bin/*.dll "${SYSROOT}"/lib/lib*.a; do
    [[ -e $f ]] || continue
    pacman -Qo "$f" >/dev/null 2>&1 && continue
    [[ $found -eq 0 ]] && warn "files in the sysroot owned by no package (these can shadow packaged ones):"
    printf '    %s\n' "$f" >&2
    found=1
  done
  return 0
}

# Three packages take sources from gnupg.org, which answers 403 to curl from
# some networks.  Pre-fetch them from a mirror so makepkg finds them locally.
# The checksums in the PKGBUILDs are what verify them either way.
fetch_gnupg_sources() {
  local spec dir file
  for spec in \
      "cross-msysarm64-libgpg-error:libgpg-error/libgpg-error-1.61.tar.bz2" \
      "cross-msysarm64-libassuan:libassuan/libassuan-2.5.7.tar.bz2" \
      "cross-msysarm64-libassuan:libassuan/libassuan-3.0.2.tar.bz2" \
      "cross-msysarm64-gpgme:gpgme/gpgme-2.0.1.tar.bz2"; do
    dir="${REPO_DIR}/${spec%%:*}"
    file="${spec#*:}"
    [[ -d $dir ]] || continue
    local base="${dir}/$(basename "$file")"
    for suffix in "" ".sig"; do
      [[ -s "${base}${suffix}" ]] && continue
      if curl -fsSL -m 120 -o "${base}${suffix}" "${GNUPG_MIRROR}/${file}${suffix}"; then
        msg "fetched $(basename "${file}${suffix}") from the mirror"
      else
        warn "could not pre-fetch ${file}${suffix}; makepkg will try gnupg.org"
        rm -f "${base}${suffix}"
      fi
    done
  done
}

# Build one package and install it.  Everything is staged under ${SYSROOT}, so
# installing as we go is what makes the next package's configure find it.
build_pkg() {
  local name="$1"
  local dir="${REPO_DIR}/${name}"
  [[ -d $dir ]] || die "no such recipe: ${name}"
  mkdir -p "$LOGDIR"
  local log="${LOGDIR}/${name}.log"

  if [[ ${SKIP_BUILT:-1} -eq 1 ]] && pacman -Q "$name" >/dev/null 2>&1; then
    msg "${name}: already installed, skipping (SKIP_BUILT=0 to force)"
    return 0
  fi

  msg "building ${name}  (log: ${log})"
  (
    cd "$dir"
    # Stale src/ trees survive -f and mislead every diagnosis that follows.
    rm -rf src pkg
    # --skippgpcheck: the signing keys are not imported on a fresh machine, and
    # the sha256sums in each PKGBUILD are what actually verify the sources.
    makepkg --config "$PROFILE" -d -f --skippgpcheck
  ) > "$log" 2>&1 || {
    tail -25 "$log" >&2
    die "${name} failed - full log at ${log}"
  }

  local pkgfile
  pkgfile=$(ls -t "${PKGDEST}/${name}"-*.pkg.tar.zst 2>/dev/null | head -1)
  [[ -n $pkgfile ]] || die "${name} built but no package appeared in ${PKGDEST}"

  pacman -U --noconfirm "$pkgfile" >> "$log" 2>&1 ||
    die "${name}: pacman -U failed - see ${log}"
  msg "${name}: installed"
}
