#!/usr/bin/bash
# Run OpenSSH's regress suite (unit + t-exec) the way `make tests` does, but
# without make: from the shell under test, one test at a time with a timeout.
#   bash run-ssh-tests.sh <openssh-build-dir> <results-dir> [unit|t-exec|all] [timeout] [test ...]
B=$1; OUT=$2; WHAT=${3:-all}; TMO=${4:-300}; shift 4 2>/dev/null
R=$B/regress
# MSYS2 defaults to deepcopy "symlinks", which fail when the target does not
# exist yet; test-exec.sh links log files before they are written.
export MSYS="winsymlinks:sys${MSYS:+ $MSYS}"
# ssh runs ProxyCommand/LocalCommand via $SHELL; never inherit the launching
# environment's (e.g. Git for Windows' x86_64 bash, which has a different /).
export SHELL=/usr/bin/bash
mkdir -p "$OUT"
cd "$R" || exit 1

run_unit() {
  local res=$OUT/unit-summary.txt; : > "$res"
  local p=0 f=0
  while read -r t d; do
    local args=(); [ -n "$d" ] && args=(-d "$R/unittests/$d/testdata")
    timeout -k 10 "$TMO" "$R/unittests/$t/test_$t" "${args[@]}" > "$OUT/unit-$t.out" 2>&1
    local rc=$?
    if [ $rc -eq 0 ]; then r=PASS; p=$((p+1)); else r="FAIL(rc=$rc)"; f=$((f+1)); fi
    printf '%-12s unit/%s\n' "$r" "$t" | tee -a "$res"
  done <<'EOF'
sshbuf
sshkey sshkey
sshsig sshsig
authopt authopt
bitmap
conversion
kex
hostkeys hostkeys
match
misc
servconf
crypto crypto
utf8
EOF
  printf 'UNIT TOTAL pass=%d fail=%d\n' $p $f | tee -a "$res"
}

run_texec() {
  local res=$OUT/t-exec-summary.txt; : > "$res"
  local tests=("$@")
  if [ ${#tests[@]} -eq 0 ]; then
    # LTESTS from the regress Makefile, in order
    mapfile -t tests < <(sed -n '/^LTESTS=/,/^$/p' Makefile | tr -s ' \t\\' '\n' | grep -v -e '^LTESTS=' -e '^$')
  fi
  export AWK=gawk EGREP='/usr/bin/grep -E' OPENSSL_BIN=/usr/bin/openssl
  export BUILDDIR=$B OBJ=$R PATH="$B:$PATH" TEST_ENV=MALLOC_OPTIONS= TEST_MALLOC_OPTIONS=
  export TEST_SSH_SCP=$B/scp TEST_SSH_SSH=$B/ssh TEST_SSH_SSHD=$B/sshd
  export TEST_SSH_SSHD_SESSION=$B/sshd-session TEST_SSH_SSHD_AUTH=$B/sshd-auth
  export TEST_SSH_SSHAGENT=$B/ssh-agent TEST_SSH_SSHADD=$B/ssh-add TEST_SSH_SSHKEYGEN=$B/ssh-keygen
  export TEST_SSH_SSHPKCS11HELPER=$B/ssh-pkcs11-helper TEST_SSH_SSHKEYSCAN=$B/ssh-keyscan
  export TEST_SSH_SFTP=$B/sftp TEST_SSH_PKCS11_HELPER=$B/ssh-pkcs11-helper TEST_SSH_SK_HELPER=$B/ssh-sk-helper
  export TEST_SSH_SFTPSERVER=$B/sftp-server TEST_SSH_MODULI_FILE=$B/moduli
  export TEST_SSH_PLINK= TEST_SSH_PUTTYGEN= TEST_SSH_CONCH= TEST_SSH_DROPBEAR= TEST_SSH_DROPBEARKEY=
  export TEST_SSH_DROPBEARCONVERT= TEST_SSH_DBCLIENT= TEST_SSH_TMUX=
  export TEST_SSH_IPV6=yes TEST_SSH_UTF8=yes TEST_SHELL=sh EXEEXT=.exe SUDO=
  local p=0 f=0 s=0 t=0
  for T in "${tests[@]}"; do
    local start=$SECONDS
    timeout -k 10 "$TMO" env SUDO= TEST_ENV= sh "$R/test-exec.sh" "$R" "$R/$T.sh" > "$OUT/t-$T.out" 2>&1
    local rc=$? el=$((SECONDS-start))
    if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then r=TIMEOUT; t=$((t+1))
    elif grep -qE '^SKIPPED|skipped' "$OUT/t-$T.out" && [ $rc -eq 0 ]; then r=SKIP; s=$((s+1))
    elif [ $rc -eq 0 ]; then r=PASS; p=$((p+1))
    else r="FAIL(rc=$rc)"; f=$((f+1)); fi
    printf '%-12s %-24s %4ss\n' "$r" "$T" "$el" | tee -a "$res"
    # never leave a test's sshd/agent behind for the next one
    [ -f "$R/pidfile" ] && kill "$(cat "$R/pidfile")" 2>/dev/null
    rm -f "$R/pidfile"
    # never let one test's sshd/agent outlive it and hold the port for the next;
    # /usr/bin/kill -f is TerminateProcess, independent of signal delivery
    for lp in $(ps | awk -v b="$B/" 'index($NF, b) == 1 && $NF ~ /\/(sshd|sshd-session|sshd-auth|ssh-agent)$/ {print $1}'); do
      echo "$T: force-killed leftover $(ps | awk -v p=$lp '$1==p{print $NF}') pid $lp" >> "$OUT/leftovers.log"
      /usr/bin/kill -f "$lp" 2>/dev/null
    done
  done
  printf 'T-EXEC TOTAL pass=%d fail=%d skip=%d timeout=%d\n' $p $f $s $t | tee -a "$res"
}

case $WHAT in
  unit)   run_unit ;;
  t-exec) run_texec "$@" ;;
  all)    run_unit; run_texec "$@" ;;
esac
