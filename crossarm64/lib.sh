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

# Verify a finished package really contains AArch64 binaries.
#
# The per-recipe crossarm64_assert_env in guard.sh stops a native build before
# it starts, which is the cheap check.  This is the backstop: it looks at what
# was actually produced, so it covers every package with one implementation
# rather than 23 hand-written output globs, and it catches any route to a
# wrong-architecture artifact that the environment check does not model.
#
# It matters because a wrong-architecture package is otherwise completely
# silent - it builds, packages, installs, and gets picked up by the next
# package's configure without one error - and build_pkg installs each result
# into the sysroot, so a single bad package quietly poisons everything after it.
#
# `file` reports "ARM64" for target PE images here and "x86-64" for native ones.
assert_pkg_arch() {
  local pkgfile="$1" tmp f out checked=0 bad=0
  tmp=$(mktemp -d)
  # Only the PE members; .a archives report as "current ar archive" either way,
  # so they tell us nothing.
  bsdtar -xf "$pkgfile" -C "$tmp" --include='*.dll' --include='*.exe' 2>/dev/null || true

  while IFS= read -r f; do
    checked=$((checked + 1))
    out=$(file -b "$f" 2>/dev/null)
    case $out in
      *ARM64*|*Aarch64*|*aarch64*) ;;
      *) warn "wrong architecture: ${f#$tmp/}: ${out}"; bad=1 ;;
    esac
  done < <(find "$tmp" \( -name '*.dll' -o -name '*.exe' \) -type f)

  rm -rf "$tmp"

  if [[ $bad -ne 0 ]]; then
    die "$(basename "$pkgfile") contains non-${TARGET} binaries - refusing to install it.
    This means the build did not use the cross toolchain.  Delete the package's
    src/ tree and rebuild; a stale src/ caches native configure answers."
  fi
  if [[ $checked -eq 0 ]]; then
    # Not fatal: a package can legitimately ship only headers or static libs.
    warn "$(basename "$pkgfile") contains no .dll/.exe - architecture unverified"
  else
    msg "$(basename "$pkgfile"): ${checked} PE file(s), all ARM64"
  fi
}

# Verify a package puts nothing outside the sysroot.
#
# These are host-side cross packages: every file they own belongs under
# ${SYSROOT}.  A build system that takes a directory from a *host* .pc file
# rather than from --prefix escapes that, and the result collides with the
# host's own packages - cross-msysarm64-pacman shipped
# /usr/share/bash-completion/completions/pacman, which pacman -U rejected as
# "exists in filesystem (owned by pacman)".
#
# The rejection is the good case.  The dangerous one is an escaped path the
# host does not already own: pacman would install it happily, and a cross
# package would then be writing target files into the host root.
assert_pkg_paths() {
  local pkgfile="$1" stray
  # .PKGINFO/.BUILDINFO/.MTREE are metadata, not payload.
  # The trailing "|| true" is load-bearing.  grep exits 1 when it matches
  # nothing, which is exactly the case where the package is CLEAN, and this file
  # runs under set -euo pipefail - so without it a good package aborts the whole
  # run, silently, at the assignment.
  stray=$(bsdtar -tf "$pkgfile" 2>/dev/null |
            grep -v "^usr/${TARGET}/" |
            grep -vE '^\.[A-Z]|^\./?$|/$' || true)

  if [[ -n $stray ]]; then
    warn "$(basename "$pkgfile") installs files outside ${SYSROOT}:"
    printf '    %s\n' $stray >&2
    die "refusing to install - these would land in the host root"
  fi
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

  # Before installing, not after: build_pkg installs into the sysroot, so a bad
  # package caught here is one that never gets a chance to mislead the next
  # package's configure.
  assert_pkg_arch "$pkgfile"
  assert_pkg_paths "$pkgfile"

  pacman -U --noconfirm "$pkgfile" >> "$log" 2>&1 ||
    die "${name}: pacman -U failed - see ${log}"
  msg "${name}: installed"
}
