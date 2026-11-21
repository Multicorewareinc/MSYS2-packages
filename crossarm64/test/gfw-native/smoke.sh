#!/bin/bash
# Smoke test of an assembled Git for Windows tree, run from that tree's own
# login shell (git-bash's environment).
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
ko() { echo "FAIL: $1 -- $2"; fail=$((fail+1)); }
t() { local name=$1; shift; local out; out=$("$@" 2>&1) && ok "$name: $(echo "$out" | head -1 | cut -c1-70)" || ko "$name" "$(echo "$out" | tail -2)"; }

echo "uname: $(uname -a)"
echo "runtime: $(cygpath -w /usr/bin/msys-2.0.dll)"
case "$(uname -m)" in aarch64) ok "uname -m aarch64";; *) ko "uname -m" "$(uname -m)";; esac
t "git" git --version
t "bash" bash --version
t "cygpath" cygpath -w /usr/bin
t "mount" mount
t "ps" ps
t "perl" perl -e 'print "perl $^V"'
t "perl modules" perl -MIO::Socket::SSL -MNet::SSLeay -MLWP::UserAgent -MMIME::Parser -MTerm::ReadKey -e 'print "ok"'
t "ssh" ssh -V
t "gpg" gpg --version
t "svn" svn --version --quiet
t "tig" tig --version
t "less" less --version
t "vim" vim --version
t "nano" nano --version
t "tar/xz/zstd/bzip2/gzip/unzip" sh -c 'cd /tmp && echo hi > s.txt && tar cJf s.txz s.txt && zstd -q -f s.txt && bzip2 -kf s.txt && gzip -kf s.txt && tar xJf s.txz -O && zstd -dc s.txt.zst && rm -f s.*'
t "file" file /usr/bin/bash.exe
t "psl" psl --version
t "openssl" openssl version
t "getopt (util-linux)" getopt -o a -- -a
t "dash" dash -c 'echo dash ok'
t "awk/sed/grep/find/diff" sh -c 'echo abc | awk "{print \$1}" | sed s/b/B/ | grep -q aBc && find /etc -maxdepth 1 -name profile | grep -q profile && diff /etc/profile /etc/profile && echo ok'

# git end to end
T=$(mktemp -d); cd "$T"
git config --global user.name "Arm Tester" 2>/dev/null; git config --global user.email arm@example.com 2>/dev/null
t "git init/commit" sh -c 'git init -q r && cd r && echo a > a && git add a && git commit -qm one && git log --oneline'
t "git rebase -i (sequence editor)" sh -c 'cd r && echo b >> a && git commit -qam two && GIT_SEQUENCE_EDITOR="sed -i s/^pick/reword/" GIT_EDITOR=true git rebase -q -i HEAD~1 && git log --oneline | wc -l'
t "git bisect run" sh -c 'cd r && git bisect start -q HEAD HEAD~1 >/dev/null && git bisect run sh -c "! grep -q b a" | grep -q "is the first bad commit" && git bisect reset -q && echo ok'
t "git clone https (native curl)" git clone -q --depth 1 https://github.com/git-for-windows/build-extra gc
t "git svn (perl + SVN bindings)" git svn --version
t "git send-email --dry-run" sh -c 'cd r && git send-email --dry-run --confirm=never --to=a@b.c --smtp-server=127.0.0.1 HEAD~1 2>&1 | grep -c "Dry-OK"'
t "gpg-signed commit" sh -c 'export GNUPGHOME=$PWD/gh; mkdir -m700 $GNUPGHOME; gpg -q --batch --passphrase "" --quick-gen-key "Arm <arm@example.com>" ed25519 sign 2>/dev/null; cd r && echo c >> a && git -c user.signingkey=arm@example.com commit -qS -am signed && git verify-commit HEAD 2>&1 | grep -c "Good signature"'
cd /; rm -rf "$T"
echo "RESULT: $pass passed, $fail failed"
