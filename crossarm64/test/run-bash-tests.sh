#!/bin/sh
# Run bash's own testsuite the way tests/run-all does, but one group at a time
# with a timeout, keeping each group's output.  Runs INSIDE the shell under test.
#   sh run-bash-tests.sh <tests-dir> <results-dir> [timeout-seconds]
# A group passes when it prints nothing but its own "warning:" notes
TESTS=$1; OUT=$2; TMO=${3:-300}
cd "$TESTS" || exit 1
mkdir -p "$OUT"; rm -f "$OUT"/*.out "$OUT"/summary.txt
: ${TMPDIR:=/tmp}; export TMPDIR
: ${THIS_SH:=/usr/bin/bash}; export THIS_SH
BUILD_DIR=$TESTS; export BUILD_DIR
PATH=.:$PATH; export PATH
[ "${BASH_ENV+set}" = set ] && unset BASH_ENV
"$THIS_SH" ./version > "$OUT/version.txt" 2>&1
pass=0 fail=0 tmo=0
for x in run-*; do
  case $x in run-all|run-minimal|run-gprof|*.orig|*~) continue ;; esac
  BASH_TSTOUT=$TMPDIR/bashtst-$$-$x; export BASH_TSTOUT
  timeout -k 10 "$TMO" sh "$x" > "$OUT/$x.out" 2>&1
  rc=$?
  rm -f "$BASH_TSTOUT"
  if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
    r=TIMEOUT; tmo=$((tmo+1))
  elif grep -qvE "^warning:" "$OUT/$x.out"; then
    r=FAIL; fail=$((fail+1))
  else
    r=PASS; pass=$((pass+1))
  fi
  printf '%-8s %s\n' "$r" "$x" | tee -a "$OUT/summary.txt"
done
printf 'TOTAL pass=%d fail=%d timeout=%d\n' $pass $fail $tmo | tee -a "$OUT/summary.txt"
