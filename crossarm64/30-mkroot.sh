#!/usr/bin/env bash
# Assemble a runnable Windows-ARM64 root from the aarch64-pc-cygwin sysroot.
#   bash crossarm64/30-mkroot.sh [root]     (default /c/upstream-root, what 50-mingit-proto1.sh reads)
#
# An ARM64 process takes / from where msys-2.0.dll sits, so the DLL has to be in
# ROOT/usr/bin next to the binaries, and nothing x86_64 may be on its PATH.
set -euo pipefail
SYSROOT=/usr/aarch64-pc-cygwin
ROOT="${1:-/c/upstream-root}"

[[ -f $SYSROOT/bin/msys-2.0.dll ]] || { echo "no runtime in $SYSROOT/bin"; exit 1; }
[[ -f $SYSROOT/usr/bin/bash.exe ]] || { echo "no bash in $SYSROOT/usr/bin - build the userland first"; exit 1; }

echo "=== assembling $ROOT"
mkdir -p "$ROOT"/{usr/bin,etc,tmp,var/tmp,home,dev}
# refreshing an existing root: some packaged files are read-only (bashbug, ...)
chmod -R u+w "$ROOT/usr" 2>/dev/null || true
chmod 1777 "$ROOT/tmp" "$ROOT/var/tmp" 2>/dev/null || true
# userland (bash, coreutils, ...) staged as usr/...
cp -a "$SYSROOT/usr/." "$ROOT/usr/"
# runtime: msys-2.0.dll plus the winsup utilities (locale, tzset, mount, ...).
# $SYSROOT/bin also holds cross binutils' tooldir copies (ar, as, ld, ...),
# which are x86-64 host tools -- skip anything that is not an ARM64 PE.
for f in "$SYSROOT"/bin/*; do
  case "$(file -b "$f")" in
    *x86-64*) ;;
    *) cp -a "$f" "$ROOT/usr/bin/" ;;
  esac
done
[[ -d $SYSROOT/etc ]] && cp -a "$SYSROOT/etc/." "$ROOT/etc/"
# zoneinfo is architecture-independent; bash's printf %(...)T tests need it
[[ -d $ROOT/usr/share/zoneinfo ]] || cp -a /usr/share/zoneinfo "$ROOT/usr/share/"
# sh: MSYS2 ships /usr/bin/sh.exe as a copy of bash
[[ -f $ROOT/usr/bin/sh.exe ]] || cp -f "$ROOT/usr/bin/bash.exe" "$ROOT/usr/bin/sh.exe"
# awk: gawk installs gawk.exe; scripts call awk
[[ -f $ROOT/usr/bin/awk.exe || ! -f $ROOT/usr/bin/gawk.exe ]] || cp -f "$ROOT/usr/bin/gawk.exe" "$ROOT/usr/bin/awk.exe"

# bash's testsuite helpers (recho, zecho, ...) sit in usr/share/bash/tests and
# load msys-2.0.dll from their own directory first.  It must be a HARDLINK of
# usr/bin/msys-2.0.dll: a copy - or a link left over from an older runtime -
# puts two different runtimes in one process tree and the helpers segfault.
if [[ -d $ROOT/usr/share/bash/tests ]]; then
  rm -f "$ROOT/usr/share/bash/tests/msys-2.0.dll"
  ln "$ROOT/usr/bin/msys-2.0.dll" "$ROOT/usr/share/bash/tests/msys-2.0.dll"
fi

# MSYS2's drive prefix is /, so C: is /c (the runtime default is /cygdrive/c)
[[ -f $ROOT/etc/fstab ]] || printf 'none / cygdrive binary,posix=0,noacl,user 0 0\n' > "$ROOT/etc/fstab"

cat > "$ROOT/etc/profile" <<'PROFILE'
export PATH=/usr/bin:/usr/local/bin
export SHELL=/usr/bin/bash
# a real per-user home, as sshd and getpwnam see it (tests compare the two)
export HOME=/home/$(/usr/bin/id -un)
[ -d "$HOME" ] || mkdir -p "$HOME"
export TMPDIR=/tmp
export TERMINFO=/usr/share/terminfo
: "${TERM:=xterm-256color}"; export TERM
test -z "$TZ" && export TZ=$(/usr/bin/tzset 2>/dev/null)
PS1='\[\e[1;32m\]aarch64\[\e[0m\]:\w\$ '
PROFILE

cat > "$ROOT/aarch64-shell.cmd" <<'CMD'
@echo off
rem Start a Windows-ARM64 msys shell in this root.
set "PATH=%~dp0usr\bin;%SystemRoot%\system32;%SystemRoot%"
"%~dp0usr\bin\bash.exe" --login -i
CMD

echo "  executables : $(ls "$ROOT"/usr/bin/*.exe | wc -l)"
echo "  dlls        : $(ls "$ROOT"/usr/bin/*.dll | wc -l)"
x86=$(for f in "$ROOT"/usr/bin/*.exe "$ROOT"/usr/bin/*.dll; do file "$f"; done | grep -c 'x86-64' || true)
echo "  x86-64 PEs  : $x86 (must be 0)"
[[ $x86 -eq 0 ]] || { echo "ERROR: x86-64 binaries in the ARM64 root"; exit 1; }
echo "=== done - shell: $(cygpath -w "$ROOT")\\aarch64-shell.cmd"
