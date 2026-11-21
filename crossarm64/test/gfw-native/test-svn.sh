#!/bin/bash
# Subversion and git svn natively on ARM64: svn client/admin/serve on the
# aarch64 build, and Git for Windows 2.56.1 arm64's git-svn on the ARM64
# perl with the Subversion Perl bindings.
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
ko() { echo "FAIL: $1 -- $2"; fail=$((fail+1)); }
G=/home/HCKTest/gfw-tests/t4/gitarm64/clangarm64
T=$(mktemp -d); cd "$T" || exit 1
R=file://$T/repo

# --- svn itself
v=$(svn --version --quiet 2>&1); [ "$v" = 1.14.5 ] && ok "svn --version ($v)" || ko "svn --version" "$v"
svn --version 2>&1 | grep -q "ra_serf" && ok "ra_serf (http/https) module present" || ko "ra_serf" "$(svn --version 2>&1 | grep '^\*')"
svnadmin create repo && ok "svnadmin create" || ko "svnadmin create" ""
svn mkdir -q -m "layout" $R/trunk $R/branches $R/tags && ok "svn mkdir (trunk/branches/tags)" || ko "svn mkdir" ""
svn checkout -q $R/trunk wc && ok "svn checkout" || ko "checkout" ""
( cd wc && printf 'line1\n' > a.txt && svn add -q a.txt && svn commit -q -m "add a" &&
  printf 'line2\n' >> a.txt && svn commit -q -m "edit a" &&
  svn propset -q svn:eol-style native a.txt && svn commit -q -m "prop" ) && ok "svn add/commit/propset (3 commits)" || ko "commits" ""
n=$(svn log -q $R | grep -c '^r'); [ "$n" = 4 ] && ok "svn log ($n revisions)" || ko "svn log" "$n"
out=$(cd wc && svn diff -r2:3 a.txt | grep '^+line2'); [ -n "$out" ] && ok "svn diff" || ko "svn diff" ""
svn copy -q -m "branch" $R/trunk $R/branches/b1 && ok "svn copy (branch)" || ko "svn copy" ""
svnadmin dump -q repo > dump && svnadmin create repo2 && svnadmin load -q repo2 < dump &&
  [ "$(svnlook youngest repo2)" = 5 ] && ok "svnadmin dump/load ($(wc -c < dump) bytes)" || ko "dump/load" "$(svnlook youngest repo2 2>&1)"
svnadmin verify -q repo 2>/dev/null && ok "svnadmin verify" || ko "verify" ""

# svnserve over svn:// (fork + sockets)
port=$((30000 + RANDOM % 20000))
svnserve -d --foreground --listen-host 127.0.0.1 --listen-port $port -r "$T" & sp=$!
sleep 2
n=$(svn log -q svn://127.0.0.1:$port/repo 2>&1 | grep -c '^r'); [ "$n" = 5 ] && ok "svnserve + svn:// log ($n revisions)" || ko "svnserve" "$(svn log -q svn://127.0.0.1:$port/repo 2>&1 | tail -2)"
kill $sp 2>/dev/null; wait $sp 2>/dev/null

# --- Perl bindings
out=$(/usr/bin/perl -MSVN::Core -MSVN::Ra -MSVN::Client -MSVN::Repos -e 'print $SVN::Core::VERSION' 2>&1)
[ "$out" = 1.14.5 ] && ok "Perl SVN::Core/Ra/Client/Repos load ($out)" || ko "SVN perl modules" "$out"
out=$(/usr/bin/perl -MSVN::Core -MSVN::Ra -e 'my $ra = SVN::Ra->new(url => shift); print $ra->get_latest_revnum' $R 2>&1)
[ "$out" = 5 ] && ok "SVN::Ra latest revision ($out)" || ko "SVN::Ra" "$out"

# --- git svn (Git for Windows arm64)
export PATH=$G/bin:/usr/bin:$PATH PERL5LIB=$G/share/perl5
GS="/usr/bin/perl $G/libexec/git-core/git-svn"
out=$($GS --version 2>&1); [[ $out == *"git-svn version"*"svn 1.14.5"* ]] && ok "git svn --version ($out)" || ko "git svn --version" "$out"
$GS clone -q -s $R gclone > gs.log 2>&1 && ok "git svn clone -s" || ko "git svn clone" "$(tail -5 gs.log)"
if [ -d gclone ]; then
  cd gclone
  n=$(git log --oneline | wc -l); [ "$n" = 4 ] && ok "git log after clone ($n commits on trunk)" || ko "git log" "$n"
  git branch -r | grep -q "origin/b1" && ok "branch b1 imported" || ko "branches" "$(git branch -r)"
  [ "$(cat a.txt)" = "$(printf 'line1\nline2')" ] && ok "file content" || ko "content" "$(cat a.txt)"
  git config user.name "Arm Tester"; git config user.email arm@example.com
  printf 'line3\n' >> a.txt && git commit -qam "from git" && $GS dcommit > dc.log 2>&1 && ok "git svn dcommit" || ko "dcommit" "$(tail -5 dc.log)"
  [ "$(svnlook log $T/repo)" = "from git" ] && ok "commit arrived in svn (r$(svnlook youngest $T/repo))" || ko "svn side" "$(svnlook log $T/repo)"
  ( cd $T/wc && svn update -q && printf 'line4\n' >> a.txt && svn commit -q -m "from svn" ) &&
    $GS rebase > rb.log 2>&1 && [ "$(git log -1 --format=%s)" = "from svn" ] && ok "git svn rebase (fetch svn commit)" || ko "rebase" "$(tail -5 rb.log)"
  cd "$T"
fi

cd /; rm -rf "$T"
echo "RESULT: $pass passed, $fail failed"
