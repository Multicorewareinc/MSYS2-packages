#!/usr/bin/env bash
# Stage 3 - test the assembled root.
#
#   ./30-test.sh [/c/aarch64-root]
#
# Two passes: every executable is run once (does it load and reach main?), then
# functional checks that do real work and verify the result.
#
# PATH is the root's directories ONLY - the host's x86_64 tools are deliberately
# not on it.  An earlier version appended $PATH, and the "gzip round-trip" it
# reported as passing was in fact exercising the host's x86-64 gzip; gzip is not
# part of this chain at all.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +e   # a failing check must not abort the run

ROOT="${1:-/c/aarch64-root}"
[[ -d ${ROOT}/usr/bin ]] || die "no root at ${ROOT} - run 20-testroot.sh first"

export PATH="${ROOT}/usr/bin:${ROOT}/usr/lib/git-core"
export HOME="${ROOT}/home" TMPDIR="${ROOT}/tmp"
W="${ROOT}/tmp/selftest"; rm -rf "$W"; mkdir -p "$W"; cd "$W" || exit 1

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %-32s %s\n' "$1" "$2"; fail=$((fail+1)); }
chk() { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "got '$2' want '$3'"; }

msg "pass 1: every executable runs"
# Exit codes >= 128 are ambiguous: a signal death is 128+n, but plenty of tools
# legitimately return 128 or 129 for "unknown option" when they have no
# --version.  So anything >= 128 is retried, and only a repeated SIGSEGV (139)
# or SIGABRT (134) counts as a crash.  Retrying also filters the intermittent
# spawn failures this runtime shows under load - envsubst crashed once in a
# full sweep and then passed 20 consecutive runs.
crashed=0; hung=0; total=0; flaky=0
for exe in "${ROOT}"/usr/bin/*.exe; do
  name=$(basename "$exe")
  case $name in login.exe|sulogin.exe|passwd.exe|su.exe) continue ;; esac
  total=$((total+1))
  timeout -k 2 10 "$exe" --version </dev/null >/dev/null 2>&1; st=$?
  if [[ $st -eq 124 || $st -eq 137 ]]; then
    bad "$name" "HUNG"; hung=$((hung+1)); continue
  fi
  if [[ $st -ge 128 ]]; then
    timeout -k 2 10 "$exe" --version </dev/null >/dev/null 2>&1; st2=$?
    if [[ $st2 -eq 139 || $st2 -eq 134 ]]; then
      bad "$name" "CRASH rc=$st2"; crashed=$((crashed+1))
    elif [[ $st2 -lt 128 ]]; then
      flaky=$((flaky+1))   # failed once, fine on retry
    fi
  fi
done
printf '  %s executables, %s crashed, %s hung, %s failed once then passed\n' \
       "$total" "$crashed" "$hung" "$flaky"
[[ $crashed -eq 0 && $hung -eq 0 ]] && ok "no executable crashed or hung"
[[ $flaky -gt 0 ]] && warn "${flaky} intermittent spawn failure(s) - this runtime is known to do that under load"

msg "pass 2: functional checks"

chk "bash arithmetic"    "$(bash -c 'a=(1 2 3); echo $(( ${a[0]} + ${a[2]} ))')" "4"
chk "bash MACHTYPE"      "$(bash -c 'echo $MACHTYPE')" "aarch64-pc-msys"
chk "bash forks a child" "$(bash -c 'ls.exe --version | head -1 | cut -d" " -f1-2')" "ls (GNU"

printf 'delta\nalpha\ncharlie\n' > f.txt
chk "sort"      "$(sort f.txt | head -1)" "alpha"
chk "sed"       "$(sed -n 2p f.txt)" "alpha"
chk "grep -c"   "$(grep -c a f.txt)" "3"
chk "sha256sum" "$(printf abc | sha256sum | cut -c1-16)" "ba7816bf8f01cfea"
cp f.txt g.txt; echo more >> g.txt; diff f.txt g.txt >/dev/null 2>&1
chk "diff detects change" "$?" "1"

# Real data, and an empty checksum can never pass: an earlier version used
# /dev/urandom, which produced nothing here, so every round-trip compared
# empty-to-empty and reported success.
#
# gzip is absent on purpose - this chain builds zlib the library, not the gzip
# package, so there is no ARM64 gzip to test.
cat "${ROOT}"/usr/bin/*.dll > blob.bin 2>/dev/null
sum=$(sha256sum blob.bin 2>/dev/null | cut -d' ' -f1)
if [[ ! -s blob.bin || -z $sum ]]; then
  bad "compression test data" "could not build blob.bin"
else
  printf '  (test blob: %s bytes)\n' "$(stat -c%s blob.bin)"
  for tool in bzip2 xz zstd lz4; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      bad "${tool} round-trip" "${tool} is not in the root"; continue
    fi
    cp blob.bin c.bin
    case $tool in
      bzip2) bzip2 -f c.bin && bzip2 -d c.bin.bz2 ;;
      xz)    xz -f c.bin    && xz -d c.bin.xz ;;
      zstd)  zstd -q -f c.bin -o c.bin.zst && rm -f c.bin && zstd -q -d c.bin.zst -o c.bin ;;
      lz4)   lz4 -q -f c.bin c.bin.lz4 && rm -f c.bin && lz4 -q -d c.bin.lz4 c.bin ;;
    esac
    got=$(sha256sum c.bin 2>/dev/null | cut -d' ' -f1); [[ -z $got ]] && got=__missing__
    chk "${tool} round-trip" "$got" "$sum"
    rm -f c.bin c.bin.*
  done
  # zlib is exercised through libarchive and git below rather than a gzip CLI.
fi

mkdir -p d && cp f.txt d/
bsdtar -cJf a.tar.xz d && bsdtar -tf a.tar.xz >/dev/null
chk "bsdtar create+list" "$?" "0"
chk "bsdtar extract"     "$(bsdtar -xOf a.tar.xz d/f.txt | head -1)" "delta"
bsdtar -czf a.tar.gz d && bsdtar -tf a.tar.gz >/dev/null
chk "bsdtar gzip filter (zlib)" "$?" "0"

chk "openssl sha256" "$(printf abc | openssl dgst -sha256 | sed 's/.*= //' | cut -c1-16)" "ba7816bf8f01cfea"
openssl genrsa -out k.pem 2048 >/dev/null 2>&1 &&
  openssl rsa -in k.pem -pubout -out p.pem >/dev/null 2>&1 &&
  printf 'data' > m.txt &&
  openssl dgst -sha256 -sign k.pem -out m.sig m.txt >/dev/null 2>&1 &&
  openssl dgst -sha256 -verify p.pem -signature m.sig m.txt >/dev/null 2>&1
chk "openssl rsa sign+verify" "$?" "0"

printf '<?xml version="1.0"?><r><c a="1"/></r>' > t.xml; xmlwf t.xml >/dev/null 2>&1
chk "xmlwf valid xml" "$?" "0"

printf 'curl-local-ok' > src.txt
chk "curl file://" "$(curl -sS file:///tmp/selftest/src.txt)" "curl-local-ok"

# Expectations are what the native x86_64 pacman returns for the same inputs,
# checked side by side - not what they "ought" to be.
chk "vercmp older"  "$(vercmp 1.0 1.1)" "-1"
chk "vercmp epoch"  "$(vercmp 1:1.0 1.0)" "1"
chk "vercmp pkgrel" "$(vercmp 1.0-2 1.0-1)" "1"
bash "${ROOT}/usr/bin/makepkg" --version >/dev/null 2>&1
chk "makepkg runs" "$?" "0"

git init -q repo && cd repo
git config user.email t@e.st; git config user.name Tester
echo one > a.txt; git add a.txt; git commit -q -m first
echo two >> a.txt; git commit -q -am second
chk "git commits" "$(git log --oneline | wc -l | tr -d ' ')" "2"
git checkout -q -b topic; echo t > b.txt; git add b.txt; git commit -q -m topic
git checkout -q master 2>/dev/null || git checkout -q main
git merge -q --no-ff topic -m merge >/dev/null 2>&1
chk "git merge" "$?" "0"
git fsck >/dev/null 2>&1; chk "git fsck" "$?" "0"
git gc -q >/dev/null 2>&1; chk "git gc (zlib + sha1dc)" "$?" "0"
cd ..
git clone -q repo clone2 >/dev/null 2>&1
chk "git clone (forks a helper)" "$?" "0"
chk "git alias exec" "$(git -c alias.x='!echo aliased' x 2>&1)" "aliased"

echo
msg "PASS: ${pass}   FAIL: ${fail}"
if [[ $fail -eq 0 ]]; then
  msg "all checks passed"
else
  warn "network transfers are not tested and are expected to fail until msys2-runtime#5"
fi
exit $(( fail > 0 ? 1 : 0 ))
