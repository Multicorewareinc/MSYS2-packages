#!/bin/bash
# Native ARM64 checks for the Perl modules Git for Windows ships: the four XS
# modules and the pure-Perl ones (libwww, MIME, mail, TLS stack).
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
ko() { echo "FAIL: $1 -- $2"; fail=$((fail+1)); }
P=/usr/bin/perl
T=$(mktemp -d); cd "$T" || exit 1

# Every module loads
mods="Clone HTML::Parser HTML::Entities Term::ReadKey Net::SSLeay IO::Socket::SSL
 Authen::SASL Convert::BinHex Encode::Locale Error File::Listing HTML::Tagset
 HTTP::CookieJar HTTP::Cookies HTTP::Daemon HTTP::Date HTTP::Message HTTP::Request
 HTTP::Response HTTP::Negotiate IO::HTML IO::Stringy IO::Scalar JSON LWP LWP::UserAgent
 LWP::MediaTypes Mail::Address Mail::Header MIME::Parser MIME::Entity Net::HTTP
 Net::SMTP::SSL Date::Parse Date::Format Try::Tiny URI URI::Escape WWW::RobotRules"
bad=""; n=0
for m in $mods; do n=$((n+1)); e=$($P -e "use $m; 1" 2>&1) || bad="$bad $m(${e%%$'\n'*})"; done
[ -z "$bad" ] && ok "all $n modules load" || ko "modules" "$bad"

# XS modules
out=$($P -MClone=clone -e '$a={x=>[1,{y=>2}]}; $b=clone($a); $b->{x}[1]{y}=3; print $a->{x}[1]{y}, $b->{x}[1]{y}'); [ "$out" = 23 ] && ok "Clone deep copy" || ko "Clone" "$out"
out=$($P -MHTML::Parser -e 'my @t; HTML::Parser->new(start_h=>[sub{push @t,shift},"tagname"])->parse("<html><body><a href=x>l</a><p>t</p></body></html>"); print "@t"'); [ "$out" = "html body a p" ] && ok "HTML::Parser" || ko "HTML::Parser" "$out"
out=$($P -MHTML::Entities -e 'print decode_entities("&lt;&eacute;&#65;&gt;") eq "<\x{e9}A>" ? "ok" : "bad"'); [ "$out" = ok ] && ok "HTML::Entities (XS decode)" || ko "HTML::Entities" "$out"
out=$($P -MTerm::ReadKey -e 'print defined(&ReadMode) && defined(&GetControlChars) ? "ok" : "bad"' 2>&1); [ "$out" = ok ] && ok "Term::ReadKey functions" || ko "Term::ReadKey" "$out"
out=$(printf 'x' | $P -MTerm::ReadKey -e 'my $k = ReadKey(0); print "got=$k"' 2>&1); [ "$out" = "got=x" ] && ok "Term::ReadKey ReadKey from a pipe" || ko "ReadKey" "$out"
out=$($P -MNet::SSLeay -e 'print Net::SSLeay::SSLeay_version(0)' 2>&1); [[ $out == "OpenSSL 3."* ]] && ok "Net::SSLeay ($out)" || ko "Net::SSLeay" "$out"
out=$($P -MNet::SSLeay -e 'Net::SSLeay::randomize(); my $c = Net::SSLeay::CTX_new() or die; print $c ? "ctx" : ""' 2>&1); [ "$out" = ctx ] && ok "Net::SSLeay CTX_new" || ko "CTX_new" "$out"

# TLS loopback: IO::Socket::SSL server (forked) and client
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 2 -subj /CN=localhost >/dev/null 2>&1
out=$(timeout 60 $P -MIO::Socket::SSL -e '
  my $s = IO::Socket::SSL->new(Listen=>1, LocalAddr=>"127.0.0.1", LocalPort=>0, ReuseAddr=>1,
          SSL_cert_file=>"cert.pem", SSL_key_file=>"key.pem") or die "listen: $SSL_ERROR";
  my $port = $s->sockport;
  if (!fork) { my $c = $s->accept or die "accept: $SSL_ERROR"; print $c "hello over ", $c->get_sslversion, "\n"; close $c; exit }
  my $c = IO::Socket::SSL->new(PeerAddr=>"127.0.0.1", PeerPort=>$port, SSL_ca_file=>"cert.pem",
          SSL_verifycn_name=>"localhost") or die "connect: $SSL_ERROR";
  print scalar <$c>; wait' 2>&1 | tr -d '\n')
[[ $out == "hello over TLSv1_3" ]] && ok "IO::Socket::SSL loopback ($out)" || ko "IO::Socket::SSL" "$out"

# libwww: HTTP::Daemon (forked) + LWP::UserAgent, cookies, dates
out=$(timeout 60 $P -MHTTP::Daemon -MLWP::UserAgent -MHTTP::Cookies -MHTTP::Date=time2str -e '
  my $d = HTTP::Daemon->new(LocalAddr=>"127.0.0.1") or die;
  if (!fork) { my $c = $d->accept; my $r = $c->get_request;
    my $res = HTTP::Response->new(200); $res->header("Set-Cookie"=>"k=v; path=/");
    $res->header("Last-Modified"=>time2str(0)); $res->content("path=".$r->uri->path); $c->send_response($res); exit }
  my $ua = LWP::UserAgent->new(cookie_jar=>HTTP::Cookies->new, timeout=>20);
  my $r = $ua->get($d->url."hello");
  print $r->code, " ", $r->decoded_content, " ", ($ua->cookie_jar->as_string =~ /k=v/ ? "cookie" : "nocookie"),
        " ", HTTP::Date::str2time($r->header("Last-Modified")); wait' 2>&1)
[ "$out" = "200 path=/hello cookie 0" ] && ok "LWP + HTTP::Daemon over loopback" || ko "LWP" "$out"

# Pure-Perl modules doing real work
out=$($P -MJSON -e 'my $j = JSON->new->canonical; print $j->encode($j->decode(q({"b":[1,2],"a":"x"})))'); [ "$out" = '{"a":"x","b":[1,2]}' ] && ok "JSON round trip" || ko "JSON" "$out"
out=$($P -MURI -e 'print URI->new("http://Ex.com:80/a/../b?q=1")->canonical'); [ "$out" = "http://ex.com/a/../b?q=1" ] && ok "URI canonical" || ko "URI" "$out"
out=$($P -MURI::Escape -e 'print uri_escape("a b&c")'); [ "$out" = "a%20b%26c" ] && ok "URI::Escape" || ko "URI::Escape" "$out"
out=$($P -MDate::Parse -e 'print str2time("Thu, 01 Jan 1970 00:01:00 GMT")'); [ "$out" = 60 ] && ok "TimeDate" || ko "TimeDate" "$out"
out=$($P -MMail::Address -e 'my ($a) = Mail::Address->parse(q("Jo Doe" <jo@example.com>)); print $a->address, " ", $a->phrase'); [ "$out" = "jo@example.com \"Jo Doe\"" ] && ok "MailTools" || ko "MailTools" "$out"
out=$($P -MMIME::Entity -MMIME::Parser -e '
  my $e = MIME::Entity->build(Type=>"multipart/mixed", From=>"a\@b", Subject=>"s");
  $e->attach(Data=>"hello attachment\n", Type=>"text/plain", Encoding=>"base64");
  my $p = MIME::Parser->new; $p->output_to_core(1);
  my $m = $p->parse_data($e->stringify); print $m->parts(0)->bodyhandle->as_string' 2>&1)
[ "$out" = "hello attachment" ] && ok "MIME-tools build + parse (base64)" || ko "MIME-tools" "$out"
out=$($P -MTry::Tiny -e 'try { die "boom\n" } catch { print "caught $_" }'); [ "$out" = "caught boom" ] && ok "Try::Tiny" || ko "Try::Tiny" "$out"
out=$($P -MError=:try -e 'try { throw Error::Simple("e1") } catch Error::Simple with { print "caught ", shift->text };'); [ "$out" = "caught e1" ] && ok "Error" || ko "Error" "$out"
out=$($P -MIO::Scalar -e 'my $s = ""; my $f = IO::Scalar->new(\$s); print $f "in mem"; print $s'); [ "$out" = "in mem" ] && ok "IO::Stringy" || ko "IO::Stringy" "$out"
out=$($P -MAuthen::SASL -e 'my $c = Authen::SASL->new(mechanism=>"PLAIN", callback=>{user=>"u",pass=>"p"})->client_new("smtp","h"); print length $c->client_start') ; [ "$out" = 4 ] && ok "Authen::SASL PLAIN" || ko "Authen::SASL" "$out"
out=$($P -MWWW::RobotRules -e 'my $r = WWW::RobotRules->new("bot/1"); $r->parse("http://h/robots.txt", "User-agent: *\nDisallow: /p\n"); print $r->allowed("http://h/p/x") ? "a" : "d", $r->allowed("http://h/q") ? "a" : "d"'); [ "$out" = da ] && ok "WWW::RobotRules" || ko "RobotRules" "$out"
out=$($P -MLWP::MediaTypes -e 'print guess_media_type("x.html")'); [ "$out" = text/html ] && ok "LWP::MediaTypes" || ko "MediaTypes" "$out"

cd /; rm -rf "$T"
echo "RESULT: $pass passed, $fail failed"
