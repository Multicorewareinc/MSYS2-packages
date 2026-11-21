#!/bin/bash
# Native ARM64 checks for the installed perl (sysroot root): configuration,
# every XS module, and some real work.
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
ko() { echo "FAIL: $1 -- $2"; fail=$((fail+1)); }
P=/usr/bin/perl

out=$($P -e 'print "$^O $] "' 2>&1); [[ $out == "cygwin 5.042003 " ]] && ok "perl starts ($out)" || ko "perl starts" "$out"
out=$($P -MConfig -e 'print join " ", map {"$_=$Config{$_}"} qw(archname cc ld ar libpth osvers usethreads ivsize longdblsize)' 2>&1)
echo "  $out"
echo "$out" | grep -q 'archname=aarch64-cygwin-thread-multi cc=gcc ld=g++ ar=ar libpth=/usr/lib' && ok "%Config native values" || ko "%Config" "$out"
echo "$out" | grep -q 'aarch64-pc-cygwin-\|/usr/aarch64-pc-cygwin' && ko "%Config cross leftovers" "$out"

# Every XS module that ships: map auto/Foo/Bar/Bar.dll -> Foo::Bar and load it.
mods=$(cd /usr/lib/perl5/core_perl/auto && find . -name '*.dll' | sed 's|^\./||; s|/[^/]*\.dll$||; s|/|::|g' | sort)
n=0; bad=""
for m in $mods; do
  case $m in XS::APItest|XS::Typemap) continue ;; esac   # test-only modules
  n=$((n+1))
  e=$($P -e "require $m; 1" 2>&1) || bad="$bad $m(${e%%$'\n'*})"
done
[ -z "$bad" ] && ok "all $n XS modules load" || ko "XS modules" "$bad"

# Real work
out=$(printf abc | $P -MDigest::SHA=sha256_hex -e 'print sha256_hex(<STDIN>)'); [[ $out == ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad ]] && ok "Digest::SHA" || ko "Digest::SHA" "$out"
out=$($P -MDigest::MD5=md5_hex -e 'print md5_hex("abc")'); [[ $out == 900150983cd24fb0d6963f7d28e17f72 ]] && ok "Digest::MD5" || ko "Digest::MD5" "$out"
out=$($P -MPOSIX=floor,strftime -e 'print floor(-2.5), " ", strftime("%Y", gmtime(0))'); [[ $out == "-3 1970" ]] && ok "POSIX" || ko "POSIX" "$out"
out=$($P -MTime::HiRes=time -e 'printf "%d", (time - int(time)) >= 0'); [[ $out == 1 ]] && ok "Time::HiRes" || ko "Time::HiRes" "$out"
out=$($P -MStorable=dclone -e '$x=dclone({a=>[1,2,{b=>3}]}); print $x->{a}[2]{b}'); [[ $out == 3 ]] && ok "Storable" || ko "Storable" "$out"
out=$($P -MEncode -e 'print length(encode("UTF-8", "\x{fc}bung"))'); [[ $out == 6 ]] && ok "Encode" || ko "Encode" "$out"
out=$($P -MCompress::Zlib -e '$c=Compress::Zlib::memGzip("hello" x 100); print Compress::Zlib::memGunzip($c) eq "hello" x 100 ? "rt" : "bad"'); [[ $out == rt ]] && ok "Compress::Zlib round trip" || ko "Compress::Zlib" "$out"
out=$($P -MList::Util=sum,max -e 'print sum(1..100), " ", max(3,9,2)'); [[ $out == "5050 9" ]] && ok "List::Util" || ko "List::Util" "$out"
out=$($P -e 'my $s = "x" x 1000; my $n = () = $s =~ /(x)/g; print $n'); [[ $out == 1000 ]] && ok "regex engine" || ko "regex" "$out"
T=$(mktemp -d)
out=$($P -MDB_File -MFcntl -e 'tie %h, "DB_File", "'$T'/t.db", O_RDWR|O_CREAT, 0644 or die $!; $h{k}="v"; untie %h; tie %g, "DB_File", "'$T'/t.db" or die; print $g{k}' 2>&1); [[ $out == v ]] && ok "DB_File (libdb)" || ko "DB_File" "$out"
out=$($P -MGDBM_File -MFcntl -e 'tie %h, "GDBM_File", "'$T'/g.db", &GDBM_WRCREAT, 0644 or die $!; $h{k}="v"; untie %h; tie %g, "GDBM_File", "'$T'/g.db", &GDBM_READER, 0 or die; print $g{k}' 2>&1); [[ $out == v ]] && ok "GDBM_File (libgdbm)" || ko "GDBM_File" "$out"
rm -rf "$T"

# Threads, fork, signals, sockets
out=$($P -Mthreads -e 'my @t = map { threads->create(sub { $_[0] * 2 }, $_) } 1..4; print join ",", map { $_->join } @t' 2>&1); [[ $out == "2,4,6,8" ]] && ok "threads" || ko "threads" "$out"
out=$($P -e 'my $p = fork // die; if (!$p) { exit 7 } waitpid($p, 0); print $? >> 8' 2>&1); [[ $out == 7 ]] && ok "fork/waitpid" || ko "fork" "$out"
out=$($P -e '$SIG{USR1} = sub { print "got" }; kill USR1 => $$; sleep 1' 2>&1); [[ $out == got ]] && ok "signal handler" || ko "signals" "$out"
out=$($P -e '$SIG{ALRM} = sub { die "alarm\n" }; alarm 1; eval { sleep 5 }; print $@' 2>&1); [[ $out == alarm ]] && ok "alarm" || ko "alarm" "$out"
out=$($P -e 'pipe(R, W); if (!fork) { close R; print W "via pipe"; exit } close W; print scalar <R>' 2>&1); [[ $out == "via pipe" ]] && ok "pipe + fork" || ko "pipe" "$out"
out=$($P -MIO::Socket::INET -e '$s = IO::Socket::INET->new(Listen => 1, LocalAddr => "127.0.0.1", LocalPort => 0) or die; $p = $s->sockport; if (!fork) { $c = IO::Socket::INET->new("127.0.0.1:$p") or die; print $c "hi\n"; exit } $a = $s->accept; print scalar <$a>' 2>&1 | tr -d '\n'); [[ $out == hi ]] && ok "TCP socket loopback" || ko "socket" "$out"
out=$($P -e 'print `echo backtick`; system("sh", "-c", "exit 3"); print $? >> 8' 2>&1 | tr -d '\n'); [[ $out == backtick3 ]] && ok "backticks / system" || ko "system" "$out"

# Tools
out=$(/usr/bin/core_perl/perldoc -T -t Carp 2>&1 | head -3 | tr -d '\n'); [[ -n $out ]] && ok "perldoc renders" || ko "perldoc" "$out"
out=$(/usr/bin/core_perl/prove --version 2>&1); [[ $out == *TAP::Harness* ]] && ok "prove runs" || ko "prove" "$out"
out=$(/usr/bin/core_perl/cpan -v 2>&1); [[ $out == *"cpan script version"* ]] && ok "cpan script runs" || ko "cpan" "$out"

echo "RESULT: $pass passed, $fail failed"
