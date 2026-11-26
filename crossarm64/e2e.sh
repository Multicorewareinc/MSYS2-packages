#!/usr/bin/env bash
# Everything from source, in order, on a Windows ARM64 machine with a fresh
# x86_64 MSYS2: host packages -> toolchain -> winsup -> userland -> root ->
# test staging -> MinGit.  Stops at the first failure.
#
#   MSYSTEM=MSYS /c/msys64/usr/bin/bash -lc 'bash ~/MSYS2-packages/crossarm64/e2e.sh'
#   FROM=<step> resumes: prereqs toolchain winsup userland root stage mingit
#   CLEAN=1 lets the toolchain step remove an installed cross-msysarm64-*
#   toolchain and its sysroot first (it refuses otherwise)
#
# Takes roughly 3 h toolchain + 2-3 h userland on a Snapdragon X Elite.
# Same split as the self-hosted CI (crossarm64/ci/build-userland.sh): the
# recipes of PR 6922 build with the PR's makepkg config, the tools only the
# test root needs with crossarm64/makepkg-harness.conf (native configure).
# Afterwards, from Windows PowerShell (not this shell):
#   crossarm64\test\run-root-tests.ps1 -Root C:\upstream-root -Out C:\results\e2e `
#       -MinGit <mingit, printed at the end> -GitBuild C:\gitbuild
# with C:\gitbuild from crossarm64/test/build-git-testtree.sh (CLANGARM64 shell).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT=${ROOT:-/c/upstream-root}
MINGIT=${MINGIT:-$HOME/mingit}
export PKGDEST=${PKGDEST:-$(dirname "$REPO")/aarch64-pkgs}
LOGS=$PKGDEST/logs; mkdir -p "$LOGS"
PR_CONF=$REPO/.ci/makepkg-aarch64-cross.conf
HARNESS_CONF=$REPO/crossarm64/makepkg-harness.conf
SYSROOT=/usr/aarch64-pc-cygwin
FROM=${FROM:-prereqs}
[[ ${MSYSTEM:-} == MSYS ]] || { echo "ERROR: run from an MSYS2 shell (MSYSTEM=MSYS), not Git Bash"; exit 1; }
[[ $(cygpath -w /) != *"Git"* ]] || { echo "ERROR: this is Git for Windows' bash"; exit 1; }

steps=(prereqs toolchain winsup userland root stage mingit)
[[ " ${steps[*]} " == *" $FROM "* ]] || { echo "FROM must be one of: ${steps[*]}"; exit 1; }
go=0
run() {  # run <step> <command...>
  local s=$1; shift
  [[ $s == "$FROM" ]] && go=1
  [[ $go == 1 ]] || { echo "--- skip $s"; return; }
  echo "=== $(date +%T) $s"
  "$@" || { echo "FAILED at step '$s' - fix it, then rerun with FROM=$s"; exit 1; }
}

toolchain() {
  # a rerun must start clean: stage-1 gcc conflicts with an installed stage-2
  # gcc on /usr/bin, and a stale sysroot leaks into every package
  local installed; installed=$(pacman -Qq | grep -E '^cross-msysarm64-' || true)
  if [[ -n $installed || -d $SYSROOT ]]; then
    [[ ${CLEAN:-0} == 1 ]] || { echo "ERROR: a toolchain/sysroot is already installed; rerun with CLEAN=1 to remove it, or FROM=winsup to keep it"; return 1; }
    [[ -z $installed ]] || pacman -Rdd --noconfirm $installed
    rm -rf "$SYSROOT"
  fi
  bash "$REPO/crossarm64/10-build-toolchain.sh"
}
winsup() {
  # report only; compare with crossarm64/ci/expected/winsup.txt
  RT2="$REPO/msys2-runtime-aarch64-stage-2" bash "$REPO/crossarm64/40-winsup-test.sh" 2>&1 | tee "$LOGS/winsup.log"
  return 0
}
userland() {
  CONF=$PR_CONF      bash "$REPO/crossarm64/20-build-userland.sh" libiconv gettext ncurses readline bash gmp coreutils &&
  CONF=$HARNESS_CONF bash "$REPO/crossarm64/20-build-userland.sh" mpfr gawk sed grep diffutils findutils hexdump &&
  CONF=$PR_CONF      bash "$REPO/crossarm64/20-build-userland.sh" zlib openssl libxcrypt libcbor libfido2 libedit db sqlite heimdal openssh &&
  CONF=$HARNESS_CONF bash "$REPO/crossarm64/20-build-userland.sh" dash util-linux rebase
}

run prereqs   bash "$REPO/crossarm64/00-host-prereqs.sh"
run toolchain toolchain
run winsup    winsup
run userland  userland
run root      bash "$REPO/crossarm64/30-mkroot.sh" "$ROOT"
run stage     bash "$REPO/crossarm64/60-stage-test-root.sh" "$ROOT"
run mingit    env ROOT="$ROOT" bash "$REPO/crossarm64/50-mingit-proto1.sh" "$MINGIT"
echo "=== $(date +%T) all built.  Root: $(cygpath -w "$ROOT")  MinGit: $(cygpath -w "$MINGIT")  winsup log: $LOGS/winsup.log"
echo "Next, in PowerShell from $(cygpath -w "$REPO"):"
echo "  powershell -ExecutionPolicy Bypass -File crossarm64\\test\\run-root-tests.ps1 -Root $(cygpath -w "$ROOT") -Out C:\\results\\e2e -MinGit $(cygpath -w "$MINGIT") -GitBuild C:\\gitbuild"
