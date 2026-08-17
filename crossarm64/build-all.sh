#!/usr/bin/env bash
# Build the whole aarch64-pc-msys chain end to end on a fresh MSYS2 install.
#
#   ./build-all.sh [root]        # default root: /c/aarch64-root
#
# The aarch64 cross toolchain must already be installed; stage 0 checks for it
# and stops if it is missing.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="${1:-/c/aarch64-root}"
here="$(dirname "${BASH_SOURCE[0]}")"

msg "stage 0/3 - host prerequisites and toolchain check"
bash "${here}/00-prereqs.sh"

msg "stage 1/3 - building the package chain (this is the long one)"
bash "${here}/10-packages.sh"

msg "stage 2/3 - assembling the ARM64 root at ${ROOT}"
bash "${here}/20-testroot.sh" "${ROOT}"

msg "stage 3/3 - testing"
bash "${here}/30-test.sh" "${ROOT}" || warn "some checks failed - see above"

msg "done.  Packages: ${PKGDEST}   Root: ${ROOT}"
