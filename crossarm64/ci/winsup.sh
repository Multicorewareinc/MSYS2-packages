#!/usr/bin/env bash
# CI stage 2: Cygwin's own testsuite against the runtime the toolchain stage
# built (crossarm64/40-winsup-test.sh), then one line per test for
# check-results.sh.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

OUT=$RESULTS/winsup
rm -rf "$OUT"; mkdir -p "$OUT"
# the testsuite installs its own copy of the DLL and needs the toolchain's
# sysroot without any userland in it
restore_sysroot
RT2=$STATE/toolchain/msys2-runtime-aarch64-stage-2 \
  bash "$REPO/crossarm64/40-winsup-test.sh" 2>&1 | tee "$OUT/run.log"

TS=$(find "$STATE/toolchain/msys2-runtime-aarch64-stage-2/src" -type d -path '*runtime-build/testsuite' | head -1)
find "$TS" -name '*.trs' | LC_ALL=C sort | while read -r trs; do
  r=$(sed -n 's/^:test-result: //p' "$trs" | head -1)
  printf '%-7s %s\n' "$r" "${trs#"$TS"/}"
done > "$OUT/summary.txt"
( cd "$TS" && find . -name '*.log' -print0 | bsdtar -cf "$OUT/logs.tar" --null -T - )
# cygserver was started for the SysV IPC tests
taskkill //F //IM cygserver.exe >/dev/null 2>&1 || true
