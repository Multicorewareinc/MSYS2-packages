#!/usr/bin/env bash
# Put what the test suites need into an ARM64 root made by 30-mkroot.sh:
# OpenSSH's regress tree (cross-built helpers) and the test runners.
#
#   bash crossarm64/60-stage-test-root.sh [root]       (default /c/upstream-root)
#
# Uses the openssh build tree that 20-build-userland.sh left in
# openssh/src/openssh-*/; if there is none, builds openssh first (same conf).
# Afterwards, from Windows PowerShell:
#   crossarm64\test\run-root-tests.ps1 -Root <root as C:\...>
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${1:-/c/upstream-root}"
CONF=${CONF:-$REPO/.ci/makepkg-aarch64-cross.conf}
[[ -f $ROOT/usr/bin/bash.exe ]] || { echo "ERROR: no root at $ROOT - run 30-mkroot.sh first"; exit 1; }

# the bash and ssh runners need these inside the root; a root without them
# makes bash "pass" groups whose diff/grep step cannot run
missing=""
for e in grep sed gawk diff cmp find xargs hexdump timeout; do
  [[ -e $ROOT/usr/bin/$e.exe ]] || missing="$missing $e"
done
[[ -z $missing ]] || { echo "ERROR: missing in the root:$missing (build sed grep gawk diffutils findutils hexdump with 20-build-userland.sh)"; exit 1; }

src=$(ls -d "$REPO"/openssh/src/openssh-*/ 2>/dev/null | head -1)
if [[ -z $src ]] || [[ ! -f $src/ssh.exe && ! -f $src/ssh ]]; then
  echo "=== no openssh build tree: building openssh"
  bash "$REPO/crossarm64/20-build-userland.sh" openssh || exit 1
  src=$(ls -d "$REPO"/openssh/src/openssh-*/ | head -1)
fi
echo "=== openssh regress binaries in $src"
make -C "$src" -j"$(nproc)" regress-binaries regress-unit-binaries > /tmp/ssh-regress-build.log 2>&1 ||
  { echo "FAILED (log /tmp/ssh-regress-build.log)"; tail -20 /tmp/ssh-regress-build.log; exit 1; }
rm -rf "$ROOT/build/openssh"; mkdir -p "$ROOT/build"
cp -a "$src" "$ROOT/build/openssh"
# sk-dummy crashes ssh-sk-helper (README: data symbol import bug); the x86_64
# baseline disables it the same way
mv -f "$ROOT/build/openssh/regress/misc/sk-dummy/sk-dummy.so" \
      "$ROOT/build/openssh/regress/misc/sk-dummy/sk-dummy.so.disabled" 2>/dev/null
mkdir -p "$ROOT/var/empty" "$ROOT/tmp"
cp -f "$REPO"/crossarm64/test/run-bash-tests.sh "$REPO"/crossarm64/test/run-ssh-tests.sh \
      "$REPO"/crossarm64/test/ssh-test-setup.sh "$ROOT/tmp/"
echo "  regress tree: $ROOT/build/openssh"
echo "  runners     : $ROOT/tmp/run-{bash,ssh}-tests.sh"

# what the PR promises: no HIGH_ENTROPY_VA on MSYS binaries (MinGW helpers
# cygwin-console-helper/getprocaddrarm64 keep it, that is expected)
heva=$(find "$ROOT/usr" \( -iname '*.exe' -o -iname '*.dll' \) -print0 |
  xargs -0 -n50 aarch64-pc-cygwin-objdump -p 2>/dev/null |
  awk '/file format/ {f=$1} /HIGH_ENTROPY_VA/ {print f}' | grep -v -e console-helper -e getprocaddr | wc -l)
echo "  MSYS PEs with HIGH_ENTROPY_VA: $heva (expect 0)"
echo "=== done"
