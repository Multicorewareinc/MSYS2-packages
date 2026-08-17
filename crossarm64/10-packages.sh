#!/usr/bin/env bash
# Stage 1 - build and install the whole aarch64-pc-msys package chain.
#
# Order matters: each package is installed into the sysroot as it is built,
# which is what lets the next one's configure find it.  Within a group the
# order is free; the groups themselves are not.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_toolchain
fix_shadowing_headers
fetch_gnupg_sources

# bash and the core userland
BASH_CHAIN=(
  cross-msysarm64-libiconv
  cross-msysarm64-gettext        # needs libiconv
  cross-msysarm64-ncurses
  cross-msysarm64-readline       # needs ncurses
  cross-msysarm64-bash           # needs readline, ncurses
  cross-msysarm64-coreutils      # also provides hostname
  cross-msysarm64-diffutils
  cross-msysarm64-grep
  cross-msysarm64-sed
)

# compression and crypto, then the applications
GIT_CHAIN=(
  cross-msysarm64-zlib
  cross-msysarm64-xz             # needs libiconv, gettext
  cross-msysarm64-zstd
  cross-msysarm64-bzip2
  cross-msysarm64-lz4
  cross-msysarm64-expat
  cross-msysarm64-openssl        # needs zlib
  cross-msysarm64-libarchive     # needs all of the above
  cross-msysarm64-curl           # needs openssl, zlib, zstd
  cross-msysarm64-libgpg-error   # needs libiconv, gettext
  cross-msysarm64-libassuan      # needs libgpg-error
  cross-msysarm64-gpgme          # needs libassuan, libgpg-error
  cross-msysarm64-pacman         # needs bash, curl, libarchive, gpgme; ships makepkg
  cross-msysarm64-git            # needs curl, expat, openssl, zlib, libiconv
)

PKGS=("${BASH_CHAIN[@]}" "${GIT_CHAIN[@]}")
[[ $# -gt 0 ]] && PKGS=("$@")   # or build just the ones named on the command line

msg "building ${#PKGS[@]} packages into ${PKGDEST}"
for p in "${PKGS[@]}"; do
  build_pkg "$p"
done

msg "stage 1 complete - $(ls "${PKGDEST}"/cross-msysarm64-*.pkg.tar.zst 2>/dev/null | wc -l) packages in ${PKGDEST}"
