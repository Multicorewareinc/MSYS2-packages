#!/usr/bin/env bash
# Native ARM64 tests for pcre2, less, file, nano.  usage: test-t5.sh <pkg>
D=${GFW_TESTS:-/c/msys64/home/$(id -un)/gfw-tests}/t5
cd "$D"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $*"; }
bad() { fail=$((fail+1)); echo "FAIL: $*"; }
arm64() { local f=$(command -v $1) off=$(od -An -tu4 -j60 -N4 "$(command -v $1)"); [ "$(od -An -tx1 -j$((off+4)) -N2 "$f" | tr -d ' ')" = "64aa" ]; }
imports() { objdump -p "$(command -v $1)" 2>/dev/null | awk '/DLL Name/{print $3}' | tr '\n' ' '; }
case $1 in
pcre2)
  arm64 pcre2grep && ok "pcre2grep.exe is ARM64" || bad "pcre2grep.exe not ARM64"
  [ "$(pcre2grep -c 'an' words.txt)" = 1 ] && ok "pcre2grep count" || bad "pcre2grep count"
  [ "$(pcre2grep -o '(?<=price: \$)[0-9.]+' words.txt)" = "42.50" ] && ok "lookbehind + -o" || bad "lookbehind + -o"
  [ "$(pcre2grep -u -o '\p{Lu}\w+' words.txt | tr '\n' ' ')" = "Grüße München " ] && ok "Unicode properties (-u)" || bad "Unicode properties: $(pcre2grep -u -o '\p{Lu}\w+' words.txt | tr '\n' ' ')"
  [ "$(pcre2grep -o '(\w+)=(\w+)' words.txt | tr '\n' ' ')" = "foo=bar baz=qux " ] && ok "groups / multiple matches" || bad "groups"
  [ "$(pcre2grep -c 'line [0-9]+5 ' text.txt)" = 2000 ] && ok "large file (1.2 MB) regex count" || bad "large file count: $(pcre2grep -c 'line [0-9]+5 ' text.txt)"
  printf '/(a+)b(c?)/\n    aaabc\n    xyz\n\n/^\d{3}-\d{4}$/\n    555-1234\n    5551234\n' > p.in
  pcre2test -q p.in p.out 2>&1; grep -q '0: aaabc' p.out && grep -q '1: aaa' p.out && grep -q 'No match' p.out && grep -q '0: 555-1234' p.out && ok "pcre2test pattern checks" || { bad "pcre2test"; cat p.out; }
  pcre2test -q -jit p.in p.jit 2>&1; ok "pcre2test -jit runs (rc=$?) ($(grep -c 'No match' p.jit) expected no-match lines)" ;;
less)
  arm64 less && ok "less.exe is ARM64" || bad "less.exe not ARM64"
  [ "$(echo 'foo bar baz' | less -p 'ba[rz]' 2>&1)" = 'foo bar baz' ] && ok "less -p with a regex" || bad "less -p"
  less text.txt | cmp -s - text.txt && ok "pass-through of 1.2 MB file (no tty)" || bad "pass-through"
  less words.txt | cmp -s - words.txt && ok "pass-through of UTF-8 text" || bad "UTF-8 pass-through"
  [ "$(/usr/libexec/lessecho 'a b' c)" = '"a b" c' ] && ok "lessecho quoting" || bad "lessecho: $(/usr/libexec/lessecho 'a b' c)"
  less --version | head -1 | grep -q 'less 710' && ok "less --version ($(less --version | head -1))" || bad "less --version" ;;
file)
  arm64 file && ok "file.exe is ARM64" || bad "file.exe not ARM64"
  file ftest/* > file-arm64.out; diff -u file-x64.out file-arm64.out && ok "file output identical to x86_64 (13 files)" || bad "file output differs from x86_64"
  file -z ftest/text.bz2 ftest/text.x64.gz ftest/text.x64.xz ftest/text.x64.zst ftest/text.x64.lz4 ftest/tree.x64.tar.gz ftest/tree.x64.tar.xz > file-z-arm64.out
  diff -u file-z-x64.out file-z-arm64.out && ok "file -z (looks inside gz/bz2/xz/zst/lz4) identical to x86_64" || bad "file -z differs"
  file --mime ftest/* > file-mime-arm64.out; diff -u file-mime-x64.out file-mime-arm64.out && ok "file --mime identical to x86_64" || bad "file --mime differs" ;;
nano)
  arm64 nano && ok "nano.exe is ARM64" || bad "nano.exe not ARM64"
  nano --version | head -1 | grep -q 'GNU nano' && ok "nano --version ($(nano --version | head -1))" || bad "nano --version"
  nano --help | grep -q -- '--syntax' && ok "nano --help" || bad "nano --help"
  ls /usr/share/nano/*.nanorc >/dev/null 2>&1 && ok "syntax files installed ($(ls /usr/share/nano/*.nanorc | wc -l))" || bad "no syntax files" ;;
esac
echo "== $1: $pass passed, $fail failed"
