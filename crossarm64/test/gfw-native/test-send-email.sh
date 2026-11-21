#!/bin/bash
# git send-email (Git for Windows 2.56.1 arm64: native git.exe + its Perl
# script and Git.pm) on the ARM64 MSYS perl, against a local SMTP server over
# implicit TLS with AUTH PLAIN.
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
ko() { echo "FAIL: $1 -- $2"; fail=$((fail+1)); }
G=/home/HCKTest/gfw-tests/t4/gitarm64/clangarm64
export PATH=$G/bin:/usr/bin:$PATH PERL5LIB=$G/share/perl5
SE="/usr/bin/perl $G/libexec/git-core/git-send-email"
T=$(mktemp -d); cd "$T" || exit 1

git --version | grep -q "2.56.1" && ok "native git.exe runs ($(git --version))" || ko "git" "$(git --version 2>&1)"
git init -q repo && cd repo && git config user.name "Arm Tester" && git config user.email arm@example.com
echo one > f && git add f && git commit -qm "first commit" && echo two >> f && git commit -qam "add a line"
git format-patch -q -1 -o ../out && ok "format-patch" || ko "format-patch" ""
patch=$(ls ../out/*.patch)

# --dry-run: Git.pm, MailTools, Term::ReadLine, all module loading
out=$($SE --dry-run --confirm=never --to=dev@example.com --smtp-server=127.0.0.1 "$patch" 2>&1)
echo "$out" | grep -q "Dry-OK. Log says:" && ok "send-email --dry-run" || ko "dry-run" "$(echo "$out" | tail -5)"

# Local SMTP server over implicit TLS (IO::Socket::SSL), one connection
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout ../key.pem -out ../cert.pem -days 2 -subj /CN=localhost >/dev/null 2>&1
/usr/bin/perl -MIO::Socket::SSL -MMIME::Base64 -e '
  my $s = IO::Socket::SSL->new(Listen=>1, LocalAddr=>"127.0.0.1", LocalPort=>0, ReuseAddr=>1,
          SSL_cert_file=>"../cert.pem", SSL_key_file=>"../key.pem") or die "listen: $SSL_ERROR";
  open my $pf, ">", "../port" or die; print $pf $s->sockport; close $pf;
  my $c = $s->accept or die "accept: $SSL_ERROR";
  open my $log, ">", "../smtp.log" or die; select((select($log), $|=1)[0]);
  sub out { print $c "$_[0]\r\n"; print $log "S: $_[0]\n" }
  out("220 localhost ESMTP test");
  while (my $l = <$c>) { $l =~ s/\r?\n$//; print $log "C: $l\n";
    if    ($l =~ /^EHLO/i) { print $c "250-localhost\r\n250-AUTH PLAIN\r\n250 8BITMIME\r\n" }
    elsif ($l =~ /^AUTH PLAIN (\S+)/i) { my (undef,$u,$p) = split /\0/, decode_base64($1);
          print $log "AUTH user=$u pass=$p\n"; out($u eq "tester" && $p eq "s3cret" ? "235 ok" : "535 no") }
    elsif ($l =~ /^(MAIL|RCPT)/i) { out("250 ok") }
    elsif ($l =~ /^DATA/i) { out("354 go"); while (my $d = <$c>) { print $log "D: $d"; last if $d =~ /^\.\r?\n$/ } out("250 queued") }
    elsif ($l =~ /^QUIT/i) { out("221 bye"); last }
    else { out("250 ok") } }' > ../server.out 2>&1 &
spid=$!
for i in $(seq 1 40); do [ -s ../port ] && break; sleep 0.5; done
port=$(cat ../port 2>/dev/null)
out=$(timeout 120 $SE --confirm=never --to=dev@example.com --from="Arm Tester <arm@example.com>" \
      --smtp-server=localhost --smtp-server-port="$port" --smtp-encryption=ssl \
      --smtp-ssl-cert-path="$PWD/../cert.pem" --smtp-user=tester --smtp-pass=s3cret "$patch" 2>&1)
wait $spid
echo "$out" | grep -q "^OK. Log says:" && ok "send-email over TLS (port $port)" || ko "send-email" "$(echo "$out" | tail -6) // server: $(cat ../server.out)"
grep -q "AUTH user=tester pass=s3cret" ../smtp.log && ok "AUTH PLAIN credentials (Authen::SASL)" || ko "AUTH" "$(grep -m3 AUTH ../smtp.log)"
grep -q "^C: RCPT TO:<dev@example.com>" ../smtp.log && ok "RCPT TO" || ko "RCPT" "$(grep -m2 RCPT ../smtp.log)"
grep -q "^D: Subject: \[PATCH\] add a line" ../smtp.log && ok "patch subject delivered" || ko "subject" "$(grep -m2 Subject ../smtp.log)"
grep -q "^D: +two" ../smtp.log && ok "patch body delivered" || ko "body" ""

cd /; rm -rf "$T"
echo "RESULT: $pass passed, $fail failed"
