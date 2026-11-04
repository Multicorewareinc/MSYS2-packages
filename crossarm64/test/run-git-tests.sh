#!/usr/bin/bash
# Run git's own testsuite (t/t*.sh) with the POSIX layer this shell belongs
# to, in parallel, one result per script.  Runs INSIDE the root under test
# (the ARM64 root, or an x86_64 root with the same tool set, to compare):
#
#   bash run-git-tests.sh <git-build-dir> <results-dir> [jobs] [timeout-s] [t-script ...]
#
# <git-build-dir> is a built Git for Windows tree (make ... all), so test-lib
# finds bin-wrappers/ and t/helper/test-tool.  MSYSTEM decides what uname -s
# reports and therefore which prerequisites test-lib sets for a MinGW git.
G=$1; OUT=$2; JOBS=${3:-8}; TMO=${4:-1800}; shift 4 2>/dev/null
[ -d "$G/t" ] || { echo "usage: $0 <git-build-dir> <results-dir> [jobs] [timeout] [tests...]"; exit 2; }
# Pinned so uname -s says MINGW64_NT on every runtime: test-lib only
# recognises Windows via *MINGW*, and runtimes differ in what they report
# for CLANGARM64.  Same prerequisites on both sides of a comparison.
export MSYSTEM=MINGW64
# git.exe is a MinGW program: its DLLs (zlib, pcre2, curl, ...) are found via
# PATH.  GIT_DLL_DIR is where they live -- clangarm64/bin of the MSYS2 install
# that built it (in MinGit: <mingit>/clangarm64/bin).
GIT_DLL_DIR=${GIT_DLL_DIR:-/c/msys64/clangarm64/bin}
export SHELL=/usr/bin/bash LANG=C LC_ALL=C PATH=/usr/bin:$GIT_DLL_DIR
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_EXEC_PATH GIT_TEMPLATE_DIR
# git.exe is native: the runtime must convert /c/... arguments for it.  A
# launcher that set MSYS2_ARG_CONV_EXCL (to protect its own command line)
# would silently turn that off for every test.
unset MSYS2_ARG_CONV_EXCL MSYS2_ENV_CONV_EXCL
# The chain linter is a perl script that checks the test scripts themselves,
# not git; neither layer ships perl (nor does MinGit).
export GIT_TEST_CHAIN_LINT=0
mkdir -p "$OUT/logs" "$OUT/trash"
cd "$G/t" || exit 1

if [ $# -gt 0 ]; then printf '%s\n' "$@"; else ls t[0-9]*.sh; fi > "$OUT/list.txt"
: > "$OUT/rc.txt"
echo "$(wc -l < "$OUT/list.txt") scripts, $JOBS in parallel, ${TMO}s each, uname -s = $(uname -s)"

run_one() {
  t=$1; n=${t%.sh}
  timeout -k 10 "$TMO" sh "./$t" --root="$OUT/trash/$n" > "$OUT/logs/$n.out" 2>&1
  echo "$? $n" >> "$OUT/rc.txt"
  rm -rf "$OUT/trash/$n"
}
export -f run_one; export OUT TMO
xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {} < "$OUT/list.txt"

# One line per script: STATUS name  passed/failed/skipped/broken counts
pass=0 fail=0 skip=0 tmo=0
sort -k2 "$OUT/rc.txt" | while read -r rc n; do
  l=$OUT/logs/$n.out
  ok=$(grep -c '^ok ' "$l"); nok=$(grep -c '^not ok ' "$l")
  sk=$(grep -c '^ok .* # skip' "$l"); brk=$(grep -c '^not ok .* # TODO' "$l")
  real_fail=$((nok - brk))
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then s=TIMEOUT
  elif grep -q '^1\.\.0 # SKIP' "$l"; then s=SKIP
  elif [ "$rc" = 0 ] && [ $real_fail -eq 0 ]; then s=PASS
  else s=FAIL; fi
  printf '%-7s %-52s ok=%d fail=%d skip=%d known_broken=%d rc=%s\n' "$s" "$n" $((ok - sk)) $real_fail "$sk" "$brk" "$rc"
done > "$OUT/summary.txt"
awk '{print $1}' "$OUT/summary.txt" | sort | uniq -c
