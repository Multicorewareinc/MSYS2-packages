# Shared settings for the self-hosted Windows-ARM64 CI (.github/workflows/
# arm64-selfhosted.yml).  Sourced by the other scripts in crossarm64/ci, which
# run in the runner's own MSYS2 (C:\ci-msys64, see setup-runner.ps1).
#
#   $STATE            persists between runs: source cache, toolchain build,
#                     sysroot snapshot, Git build tree, MinGit zip
#   $RUN              this run only: packages, logs, the ARM64 root, results
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STATE=${CI_STATE:-/c/ci-state}
RUN=$STATE/run
ROOT=$RUN/root
RESULTS=$RUN/results
SYSROOT=/usr/aarch64-pc-cygwin
SNAPSHOT=$STATE/sysroot-toolchain.tar

# the two gcc recipes clone the same repository; keep one copy across runs
export SRCDEST=$STATE/srcdest
mkdir -p "$SRCDEST" "$RUN" "$RESULTS"

# the recipes of #6922 build with the PR's configuration, the test-root
# tools with crossarm64/makepkg-harness.conf
PR_CONF=$REPO/.ci/makepkg-aarch64-cross.conf
HARNESS_CONF=$REPO/crossarm64/makepkg-harness.conf

group()    { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }

# put the sysroot back to what the toolchain stage left: no userland
restore_sysroot() {
  [[ -f $SNAPSHOT ]] || { echo "no sysroot snapshot at $SNAPSHOT - run the toolchain stage"; exit 1; }
  rm -rf "$SYSROOT"
  bsdtar -xpf "$SNAPSHOT" -C /
}

# build recipes into the sysroot with crossarm64/20-build-userland.sh
build_userland() {
  local conf=$1; shift
  CONF=$conf PKGDEST=$RUN bash "$REPO/crossarm64/20-build-userland.sh" "$@"
}
