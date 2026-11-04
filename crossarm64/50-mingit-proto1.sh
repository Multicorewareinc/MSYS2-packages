#!/usr/bin/env bash
# Assemble MinGit prototype #1 - native ARM64 shell layer.
#
#   bash crossarm64/50-mingit-proto1.sh [outdir]
#
# Git for Windows already ships a native ARM64 git.exe, but the POSIX layer it
# shells out to is still x86-64 and runs under emulation: of the 84 files in
# usr/bin of MinGit-*-arm64.zip, 82 are x86-64 and none are ARM64.  This takes
# the official zip and replaces that layer with our aarch64-pc-cygwin build.
#
# clangarm64/ is left untouched.  It is already native and carries git's whole
# transport stack (libcurl, libssl, libcrypto, git-remote-https), so HTTPS
# clone and push need nothing from usr/bin.
#
# Scope is prototype #1 per the GFW plan: "(bash, coreutils)".  The OpenSSH and
# Kerberos cluster is deliberately NOT ported here -- see PRUNE below.
set -uo pipefail

OUT="${1:-$HOME/mingit-proto1}"
ROOT="${ROOT:-/c/upstream-root}"          # our built ARM64 userland
VER="${VER:-2.55.0.5}"
TAG="${TAG:-v2.55.0.windows.5}"
URL="https://github.com/git-for-windows/git/releases/download/${TAG}/MinGit-${VER}-arm64.zip"
CACHE="${CACHE:-$HOME/.cache/mingit}"

say()  { printf '  %s\n' "$*"; }
warn() { printf '  WARNING: %s\n' "$*" >&2; }
die()  { printf '  ERROR: %s\n' "$*" >&2; exit 1; }

# Binaries that only exist to support ssh://.  git.exe does HTTPS itself from
# clangarm64, so prototype #1 drops them rather than shipping x86-64 copies:
# once msys-2.0.dll is ARM64 an x86-64 .exe cannot load it, so leaving them
# behind produces confusing load failures instead of a clean absence.
PRUNE="
ssh.exe ssh-add.exe ssh-agent.exe
msys-krb5-26.dll msys-gssapi-3.dll msys-hcrypto-4.dll msys-hx509-5.dll
msys-roken-18.dll msys-asn1-8.dll msys-wind-0.dll msys-heimbase-1.dll
msys-heimntlm-0.dll msys-com_err-1.dll msys-fido2-1.dll msys-cbor-0.11.dll
msys-crypt-2.dll
"

echo "=== MinGit prototype #1 ==="
[ -d "$ROOT/usr/bin" ] || die "ARM64 userland not found at $ROOT/usr/bin (run mkroot.sh first)"

mkdir -p "$CACHE"
ZIP="$CACHE/MinGit-${VER}-arm64.zip"
if [ ! -f "$ZIP" ]; then
  say "downloading $(basename "$ZIP")"
  curl -sL -o "$ZIP" "$URL" || die "download failed"
fi
say "source zip    : $ZIP ($(stat -c%s "$ZIP") bytes)"

rm -rf "$OUT"; mkdir -p "$OUT"
# unzip is not in a base MSYS2 install; bsdtar is (makepkg depends on it) and
# reads zip archives, so prefer whichever is present.
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$ZIP" -d "$OUT" || die "unzip failed"
elif command -v bsdtar >/dev/null 2>&1; then
  ( cd "$OUT" && bsdtar -xf "$ZIP" ) || die "bsdtar failed"
else
  die "need unzip or bsdtar to unpack $ZIP"
fi
say "unpacked to   : $OUT"

BIN="$OUT/usr/bin"
before=$(ls "$BIN" | wc -l)

# 1. swap in every ARM64 binary we have
swapped=0; missing=""
for f in "$BIN"/*; do
  b=$(basename "$f")
  if [ -f "$ROOT/usr/bin/$b" ]; then
    cp -f "$ROOT/usr/bin/$b" "$BIN/$b" && swapped=$((swapped + 1))
  else
    missing="$missing $b"
  fi
done
say "swapped ARM64 : $swapped"

# 1b. pull in runtime DLLs our builds need but MinGit never shipped (newer
#     sonames such as msys-cbor-0.14, or cygncursesw6 from our ncurses).
#     Step 1 only replaces files already in the zip; repeat until closed.
OBJDUMP="${OBJDUMP:-aarch64-pc-cygwin-objdump}"
added=0
while :; do
  new=0
  for f in "$BIN"/*.exe "$BIN"/*.dll; do
    case "$(file -b "$f")" in *ARM64*|*Aarch64*) ;; *) continue ;; esac
    for d in $("$OBJDUMP" -p "$f" 2>/dev/null | awk '/DLL Name/{print $3}'); do
      case "$d" in msys-*|cyg*) ;; *) continue ;; esac
      [ -e "$BIN/$d" ] && continue
      [ -f "$ROOT/usr/bin/$d" ] || { warn "$(basename "$f") needs $d, not in $ROOT/usr/bin"; continue; }
      cp -f "$ROOT/usr/bin/$d" "$BIN/$d" && added=$((added + 1)) && new=1
    done
  done
  [ $new -eq 0 ] && break
done
say "added deps    : $added"

# 1c. binaries outside usr/bin: the ssh helpers in usr/lib/ssh, and the
#     runtime's getprocaddr helpers in usr/libexec.  The runtime picks the
#     getprocaddr helper by the TARGET process's architecture, so the zip's
#     getprocaddr32/64 stay (x86/x64 targets) and getprocaddrarm64 is added.
others=0
while IFS= read -r f; do
  r="${f#"$OUT"/}"
  [ -f "$ROOT/$r" ] || continue
  case "$(file -b "$ROOT/$r")" in *ARM64*|*Aarch64*) ;; *) continue ;; esac
  cp -f "$ROOT/$r" "$f" && others=$((others + 1))
done < <(find "$OUT/usr" -path "$BIN" -prune -o -type f \( -iname '*.exe' -o -iname '*.dll' \) -print)
if [ -f "$ROOT/usr/libexec/getprocaddrarm64.exe" ]; then
  mkdir -p "$OUT/usr/libexec"
  cp -f "$ROOT/usr/libexec/getprocaddrarm64.exe" "$OUT/usr/libexec/" && others=$((others + 1))
else
  warn "no getprocaddrarm64.exe in $ROOT/usr/libexec: Ctrl+C to git.exe will hard-kill it"
fi
say "outside bin   : $others"

# 2. drop whatever of the ssh/kerberos cluster we have no ARM64 build of.
#    Once the openssh chain is cross-built, step 1 has already swapped those
#    in, and they stay.
pruned=0
for b in $PRUNE; do
  [ -e "$ROOT/usr/bin/$b" ] && continue
  [ -e "$BIN/$b" ] && rm -f "$BIN/$b" && pruned=$((pruned + 1))
done
say "pruned (ssh)  : $pruned"

# 2b. drop x86-64 DLLs that nothing in usr/bin imports any more: older
#     sonames our builds replaced (msys-cbor-0.11 -> 0.14) and libraries only
#     the x86-64 builds used (msys-gcc_s-seh-1 for sort, msys-pcre-1 for
#     grep -P).  An x86-64 DLL cannot load with the ARM64 msys-2.0.dll anyway.
imported=$(for f in "$BIN"/*.exe "$BIN"/*.dll; do
             case "$(file -b "$f")" in *ARM64*|*Aarch64*) ;; *) continue ;; esac
             "$OBJDUMP" -p "$f" 2>/dev/null | awk '/DLL Name/{print $3}'
           done | sort -u)
dropped=""
for f in "$BIN"/*.dll; do
  case "$(file -b "$f")" in *x86-64*) ;; *) continue ;; esac
  b=$(basename "$f")
  echo "$imported" | grep -qx "$b" && continue
  rm -f "$f" && dropped="$dropped $b"
done
say "dropped unused x86-64 DLLs:${dropped:- none}"

# 3. whatever is left is still x86-64 and will fail to load the ARM64 runtime
left=""
for b in $missing; do
  [ -e "$BIN/$b" ] && left="$left $b"
done
if [ -n "$left" ]; then
  warn "still x86-64 (will not load the ARM64 msys-2.0.dll):"
  printf '      %s\n' $left
fi

# 4. report
echo "=== result ==="
a=0; x=0
for f in "$BIN"/*; do
  case "$(file "$f" 2>/dev/null)" in
    *Aarch64*|*ARM64*) a=$((a + 1)) ;;
    *x86-64*)          x=$((x + 1)) ;;
  esac
done
say "usr/bin       : $before -> $(ls "$BIN" | wc -l) files"
say "  ARM64       : $a"
say "  x86-64      : $x"
rest=$(find "$OUT/usr" -path "$BIN" -prune -o -type f \( -iname '*.exe' -o -iname '*.dll' \) -print |
       grep -v '/usr/libexec/getprocaddr\(32\|64\)\.exe$' |
       while IFS= read -r f; do
         case "$(file -b "$f")" in *ARM64*|*Aarch64*) ;; *) echo "${f#"$OUT"/}" ;; esac
       done)
say "rest of usr/  : ${rest:-all ARM64 (getprocaddr32/64 are per-target, kept)}"
say "clangarm64/   : untouched (already native)"
echo
say "try it:"
say "  $OUT/cmd/git.exe --version"
say "  $OUT/cmd/git.exe clone https://github.com/git-for-windows/git-sdk-arm64 /tmp/t"
