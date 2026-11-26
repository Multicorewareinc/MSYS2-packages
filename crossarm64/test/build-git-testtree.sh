#!/usr/bin/env bash
# Build the Git for Windows tree the git testsuite needs (t/, test-tool.exe,
# bin-wrappers) - the -GitBuild of run-git-tests-mingit.ps1.  MinGit ships no
# test helpers, so this must be the SAME version as the MinGit/GfW under test.
#
#   MSYSTEM=CLANGARM64 /c/msys64/usr/bin/bash -lc \
#     'bash ~/MSYS2-packages/crossarm64/test/build-git-testtree.sh /c/gitbuild'
#
# Native ARM64 clang (MSYS2 CLANGARM64), the toolchain family MinGit's own
# git.exe is built with (same flags as the 21 Oct 2026 testsuite runs).
# Build it at a /c/... path:
# GIT-BUILD-OPTIONS and bin-wrappers record the build path, and /home differs
# between roots.  (crossarm64/ci/setup-runner.ps1 -GitBuildFrom copies an
# existing tree instead and rewrites those paths.)
set -euo pipefail
DEST=${1:?usage: build-git-testtree.sh /c/<dir>}
TAG=${TAG:-v2.55.0.windows.5}
VER=${TAG#v}
[[ $DEST == /[a-z]/* ]] || { echo "ERROR: build under a drive path like /c/gitbuild, not $DEST"; exit 1; }
[[ ${MSYSTEM:-} == CLANGARM64 ]] || { echo "ERROR: run with MSYSTEM=CLANGARM64"; exit 1; }

pacman -S --needed --noconfirm make tar \
  mingw-w64-clang-aarch64-{clang,curl,expat,openssl,zlib,pcre2,libiconv}

if [[ ! -f $DEST/Makefile ]]; then
  mkdir -p "$DEST"
  curl -fsSL "https://github.com/git-for-windows/git/archive/refs/tags/$TAG.tar.gz" |
    tar -xz -C "$DEST" --strip-components=1
fi
cd "$DEST"
make -j"$(nproc)" CC=clang GIT_VERSION="$VER" \
  NO_RUST=YesPlease NO_PERL=YesPlease NO_PYTHON=YesPlease NO_TCLTK=YesPlease NO_GETTEXT=YesPlease all
for f in git.exe t/helper/test-tool.exe GIT-BUILD-OPTIONS bin-wrappers/git; do
  [[ -e $f ]] || { echo "ERROR: $f was not built"; exit 1; }
done
echo "git test tree ready: $(cygpath -w "$DEST")  ($(./git.exe version))"
