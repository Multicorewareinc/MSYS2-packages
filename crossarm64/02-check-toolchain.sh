#!/usr/bin/env bash
# Check that the aarch64 cross toolchain actually works, before spending two
# hours on the package chain.
#
#   ./02-check-toolchain.sh
#
# Compile-and-link checks run here; runtime checks live in toolchain-check.c,
# which is built and executed (ARM64 binaries run natively on a Windows-ARM64
# host, so this only works there).
#
# Known defects are reported as KNOWN rather than failing the run - they are
# filed, the recipes work around them, and the chain builds with them present.
# Only something that would actually stop the build is a FAIL.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +e

SPECS="${CROSSARM64_DIR}/aarch64-pc-msys.specs"
CC="${TARGET}-gcc"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

pass=0; fail=0; known=0
ok()    { printf '  PASS   %-30s %s\n' "$1" "${2:-}"; pass=$((pass+1)); }
bad()   { printf '  FAIL   %-30s %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
note()  { printf '  KNOWN  %-30s %s\n' "$1" "${2:-}"; known=$((known+1)); }

require_toolchain
[[ -f $SPECS ]] || die "specs file not found: ${SPECS}"
cd "$W" || die "cannot use temp dir"

printf 'int f(void){return 1;}\n'            > lib.c
printf 'int main(void){return 0;}\n'         > min.c

msg "compile and link"

$CC -O0 -specs="$SPECS" -o min.exe min.c 2>err.txt
if [[ -f min.exe ]]; then ok "compiles an executable"; else bad "compiles an executable" "$(head -1 err.txt)"; fi

if ${TARGET}-objdump -f min.exe 2>/dev/null | grep -q 'pei-aarch64'; then
  ok "output is ARM64 PE" "$(${TARGET}-objdump -f min.exe | awk '/file format/{print $NF}')"
else
  bad "output is ARM64 PE" "wrong object format"
fi

# The one that matters most: with the stock specs the linker cannot find
# _cygwin_dll_entry, only warns, and emits a DLL whose initialisation never
# runs.  MSYS2-packages#22.
$CC -shared -specs="$SPECS" -o good.dll lib.c 2>/dev/null
entry=$(${TARGET}-objdump -p good.dll 2>/dev/null | awk '/AddressOfEntryPoint/{print $2}')
if [[ -n $entry && $entry != 0000000000000000 ]]; then
  ok "DLL entry point (with specs)" "0x${entry#"${entry%%[!0]*}"}"
else
  bad "DLL entry point (with specs)" "AddressOfEntryPoint is 0 - the DLL would never initialise"
fi

$CC -shared -o stock.dll lib.c 2>/dev/null
entry0=$(${TARGET}-objdump -p stock.dll 2>/dev/null | awk '/AddressOfEntryPoint/{print $2}')
if [[ $entry0 == 0000000000000000 ]]; then
  note "DLL entry point (stock specs)" "0 as expected - MSYS2-packages#22, why -specs is mandatory"
else
  ok "DLL entry point (stock specs)" "non-zero - #22 appears to be fixed"
fi

# __thread needs -lgcc_eh on this target: emulated TLS, and
# __emutls_get_address lives in libgcc_eh.a.  MSYS2-packages#31.
$CC -O0 -specs="$SPECS" -DCHECK_TLS -o tls_no.exe "${CROSSARM64_DIR}/toolchain-check.c" \
    -lm 2>tls_err.txt
if [[ -f tls_no.exe ]]; then
  ok "__thread links without -lgcc_eh" "#31 appears to be fixed"
else
  if grep -q '__emutls_get_address' tls_err.txt; then
    note "__thread needs -lgcc_eh" "MSYS2-packages#31"
  else
    bad "__thread" "$(grep -m1 . tls_err.txt)"
  fi
fi
$CC -O0 -specs="$SPECS" -DCHECK_TLS -o tls_yes.exe "${CROSSARM64_DIR}/toolchain-check.c" \
    -lm -lgcc_eh 2>/dev/null
if [[ -f tls_yes.exe ]]; then ok "__thread links with -lgcc_eh"
else bad "__thread links with -lgcc_eh" "still unresolved - gpgme and pacman will not link"; fi

# Win32 import libraries are in ${SYSROOT}/lib/w32api, which is not searched.
# MSYS2-packages#32.
$CC -O0 -specs="$SPECS" -o gdi_no.exe min.c -lgdi32 2>/dev/null
if [[ -f gdi_no.exe ]]; then
  ok "-lgdi32 without -L" "#32 appears to be fixed"
else
  $CC -O0 -specs="$SPECS" -o gdi_yes.exe min.c -L"${SYSROOT}/lib/w32api" -lgdi32 2>/dev/null
  if [[ -f gdi_yes.exe ]]; then
    note "-lgdi32 needs -L lib/w32api" "MSYS2-packages#32"
  else
    bad "-lgdi32" "does not link even with -L ${SYSROOT}/lib/w32api"
  fi
fi

# windows.h is where the compiler has crashed on five different headers.
printf '#include <windows.h>\nint main(void){return 0;}\n' > win.c
if $CC -O0 -specs="$SPECS" -fsyntax-only win.c 2>win_err.txt; then
  ok "windows.h parses"
elif grep -q 'internal compiler error' win_err.txt; then
  bad "windows.h parses" "ICE - MSYS2-packages#30"
else
  ok "windows.h parses" "(with warnings)"
fi

msg "run on the target"

$CC -O0 -g -specs="$SPECS" -o check.exe "${CROSSARM64_DIR}/toolchain-check.c" \
    -lm 2>run_err.txt
if [[ ! -f check.exe ]]; then
  bad "build toolchain-check.c" "$(head -3 run_err.txt | tr '\n' ' ')"
else
  PATH="${SYSROOT}/bin:${SYSROOT}/usr/bin:$PATH" ./check.exe
  rc=$?
  if [[ $rc -eq 0 ]]; then ok "toolchain-check.exe" "all runtime checks passed"
  elif [[ $rc -ge 128 ]]; then bad "toolchain-check.exe" "died with signal (rc=$rc)"
  else bad "toolchain-check.exe" "reported failures (rc=$rc)"; fi
fi

echo
msg "PASS: ${pass}   FAIL: ${fail}   KNOWN ISSUES: ${known}"
if [[ $fail -eq 0 ]]; then
  msg "toolchain is usable - run ./10-packages.sh next"
  exit 0
fi
warn "the toolchain has problems the recipes do not work around; fix these first"
exit 1
