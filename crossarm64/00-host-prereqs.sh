#!/usr/bin/env bash
# Install the x86_64 MSYS2 host packages the aarch64-pc-cygwin chain needs.
#
#   bash crossarm64/00-host-prereqs.sh
#
# Run from an MSYS2 shell (MSYSTEM=MSYS).  The list is what a fresh install
# was actually missing; each non-obvious entry says who needs it.
set -euo pipefail

pkgs=(
  base-devel gcc autotools git lndir gperf flex bison texinfo perl groff
  help2man python perl-JSON cmake ninja
  gmp-devel mpc-devel mpfr-devel isl-devel zlib-devel libzstd-devel
  libiconv-devel gettext-devel
  autoconf-archive                       # mpfr
  tcl-devel                              # sqlite
  ncurses-devel                          # heimdal: native asn1_compile/slc build (bundled libedit)
  cocom                                  # msys2-runtime-aarch64 (stage 1)
  mingw-w64-cross-mingwarm64-gcc         # cross-msysarm64-w32api-runtime, cygrun.exe
  mingw-w64-cross-mingwarm64-binutils
  mingw-w64-cross-mingwarm64-zlib        # msys2-runtime-aarch64 (stage 1)
  busybox                                # 40-winsup-test.sh (LTP tests)
)
pacman -S --needed --noconfirm "${pkgs[@]}"

# Networks that block git:// (port 9418) cannot clone windows-default-manifest
# from sourceware.  HTTPS works everywhere, so rewrite it.  Harmless otherwise.
git config --global url."https://sourceware.org/git/".insteadOf "git://sourceware.org/git/"
echo "host prerequisites installed"
