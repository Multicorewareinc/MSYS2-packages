#!/usr/bin/env bash
# Stage 0 - host prerequisites, and a check that the cross toolchain is present.
#
# The aarch64 toolchain itself (binutils, gcc, runtime, newlib, w32api) is NOT
# built here; install it first.  This only verifies it.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Host-side build tools.  These are all x86_64 msys packages that run on the
# build machine; none of them ends up in the target.
HOST_PKGS=(
  base-devel        # makepkg itself, plus the usual build utilities
  autotools         # autoconf/automake/libtool - most recipes autoreconf
  gettext-devel     # autopoint's /usr/share/gettext/archive.dir.tar.xz.
                    # NOT pulled in by autotools, which depends only on
                    # gettext (the runtime).  Without it any recipe whose
                    # prepare() runs autoreconf on a package using AM_GNU_GETTEXT
                    # - coreutils is the first - dies in autopoint with
                    # "infrastructure files for version 0.19.2 not found".
  gcc               # the *build* compiler, for helper programs
  patch
  git               # pacman's source is a git clone
  meson ninja       # pacman is a meson build
  perl              # openssl's Configure, and git's build
  texinfo           # makeinfo, for packages that install info pages
)

msg "installing host prerequisites"
pacman -S --needed --noconfirm "${HOST_PKGS[@]}"

msg "checking the cross toolchain"
require_toolchain

msg "installing the cross gcc default specs (msys2-runtime#7: no HIGH_ENTROPY_VA)"
install_default_specs

msg "checking the sysroot for files that could shadow packaged ones"
check_unowned_sysroot_files

msg "removing shadowing newlib headers if present"
fix_shadowing_headers

msg "stage 0 complete"
