#!/usr/bin/env bash
# Verify CI-built packages on a Windows ARM64 machine without building the
# toolchain: what was done for PR 6661/6922 v11 on 25 Nov 2026 (fork run
# 44039994489's artifacts, on a fresh MSYS2).
#
#   bash crossarm64/test/verify-ci-packages.sh <artifacts-dir> [root]
#
# <artifacts-dir> holds the CI's cross-msysarm64-*.pkg.tar.zst and the
# *-aarch64.pkg.tar.zst userland (download with gh run download).  Run from a
# fresh MSYS2 shell after crossarm64/00-host-prereqs.sh.  Steps:
#   1 install the CI toolchain (not gcc-stage1, not the runtime yet)
#   2 prestage the stage-1 runtime (15-prestage-sysroot.sh), rebuild the
#     stage-2 runtime here (winsup needs its build tree), run winsup
#   3 install the CI runtime package (what ships) + unpack the CI userland
#   4 build what the PR package set lacks but the test runners need
#     (mpfr gawk sed grep diffutils findutils hexdump, harness conf, as the
#     self-hosted CI does) and openssh's build tree (PR conf)
#   5 mkroot + stage the test root
# Then from PowerShell: crossarm64\test\run-root-tests.ps1 -Root <root> -Out <dir>.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
A=${1:?usage: verify-ci-packages.sh <artifacts-dir> [root]}
ROOT=${2:-/c/upstream-root}
SYSROOT=/usr/aarch64-pc-cygwin
PR_CONF=$REPO/.ci/makepkg-aarch64-cross.conf
HARNESS_CONF=$REPO/crossarm64/makepkg-harness.conf
L=${LOGS:-$HOME/verify-logs}; mkdir -p "$L"; : > "$L/status.txt"
st() { echo "$(date +%T) $*" | tee -a "$L/status.txt"; }
cd "$REPO" || exit 1
st "repo $(git log --oneline -1)"

pacman -U --noconfirm $(ls "$A"/cross-msysarm64-*.pkg.tar.zst | grep -v gcc-stage1 | grep -v 'cross-msysarm64-runtime-3') \
  > "$L/toolchain-install.log" 2>&1 || { st "FAILED toolchain install"; exit 1; }
st "CI toolchain: $(pacman -Q | grep cross-msysarm64 | tr '\n' ' ')"
bash crossarm64/15-prestage-sysroot.sh >> "$L/status.txt" 2>&1 || { st "FAILED prestage"; exit 1; }

cd "$REPO/msys2-runtime-aarch64-stage-2"
makepkg -sCf --noconfirm > "$L/runtime-stage-2.log" 2>&1 || { st "FAILED stage-2 runtime"; tail -25 "$L/runtime-stage-2.log"; exit 1; }
pacman -U --noconfirm $(makepkg --packagelist) >> "$L/runtime-stage-2.log" 2>&1 ||
  pacman -U --noconfirm --overwrite "$SYSROOT/*" $(makepkg --packagelist) >> "$L/runtime-stage-2.log" 2>&1 ||
  { st "FAILED stage-2 runtime install"; exit 1; }
st "stage-2 runtime rebuilt and installed; winsup testsuite   [25 Nov baseline: 266 pass / 3 fail (link04 cancel11 systemcall) / 3 XPASS]"
cd "$REPO"
RT2="$REPO/msys2-runtime-aarch64-stage-2" bash crossarm64/40-winsup-test.sh > "$L/winsup.log" 2>&1
tail -12 "$L/winsup.log" >> "$L/status.txt"

pacman -U --noconfirm "$A"/cross-msysarm64-runtime-3*.pkg.tar.zst > "$L/ci-runtime.log" 2>&1 ||
  pacman -U --noconfirm --overwrite "$SYSROOT/*" "$A"/cross-msysarm64-runtime-3*.pkg.tar.zst >> "$L/ci-runtime.log" 2>&1 ||
  { st "FAILED CI runtime install"; exit 1; }
st "CI runtime installed"
n=0
for f in "$A"/*-aarch64.pkg.tar.zst; do
  bsdtar -xf "$f" -C $SYSROOT --exclude .PKGINFO --exclude .BUILDINFO --exclude .MTREE --exclude .INSTALL --exclude .CHANGELOG ||
    { st "STAGE FAILED $f"; exit 1; }
  n=$((n+1))
done
st "unpacked $n CI aarch64 packages into the sysroot"

need=()
for p in mpfr gawk sed grep diffutils findutils hexdump; do
  ls "$A"/$p-[0-9]*-aarch64.pkg.tar.zst >/dev/null 2>&1 || need+=("$p")
done
st "building locally: ${need[*]:-nothing} (harness conf) + openssh (PR conf, for its regress tree)"
if [[ ${#need[@]} -gt 0 ]]; then
  CONF=$HARNESS_CONF bash crossarm64/20-build-userland.sh "${need[@]}" > "$L/userland.log" 2>&1 ||
    { st "FAILED userland"; tail -30 "$L/userland.log"; exit 1; }
fi
CONF=$PR_CONF bash crossarm64/20-build-userland.sh openssh >> "$L/userland.log" 2>&1 ||
  { st "FAILED openssh"; tail -30 "$L/userland.log"; exit 1; }

bash crossarm64/30-mkroot.sh "$ROOT" > "$L/mkroot.log" 2>&1 || { st "FAILED mkroot"; tail "$L/mkroot.log"; exit 1; }
bash crossarm64/60-stage-test-root.sh "$ROOT" > "$L/stage-root.log" 2>&1 || { st "FAILED stage-test-root"; tail "$L/stage-root.log"; exit 1; }
tail -4 "$L/stage-root.log" >> "$L/status.txt"
st "STAGING DONE - now in PowerShell: crossarm64\\test\\run-root-tests.ps1 -Root $(cygpath -w "$ROOT") -Out <dir>"
