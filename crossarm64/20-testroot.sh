#!/usr/bin/env bash
# Stage 2 - assemble a runnable Windows-ARM64 root from the built packages.
#
#   ./20-testroot.sh [/c/aarch64-root]
#
# Why a separate root is needed: an ARM64 process takes its idea of "/" from
# where msys-2.0.dll sits.  Run from the staging sysroot inside the x86_64
# installation, it resolves / to the *host* root, so the only /bin/sh it can
# find is x86_64 - and msys's fork emulation cannot clone an ARM64 parent's
# cygheap into an x86_64 child.  Anything that spawns a helper (git clone, a
# shell alias) dies with "child_copy: cygheap read copy failed".
#
# In a root whose usr/bin holds the ARM64 msys-2.0.dll, / is that directory,
# /bin maps to /usr/bin automatically, and everything works.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="${1:-/c/aarch64-root}"

[[ -d ${SYSROOT}/usr/bin ]] || die "sysroot looks empty - run 10-packages.sh first"

msg "assembling ${ROOT}"
mkdir -p "${ROOT}"/{usr,etc,tmp,var,home}

# Everything the packages installed.
cp -a "${SYSROOT}/usr/." "${ROOT}/usr/"

# The runtime DLL lives in ${SYSROOT}/bin, not usr/bin, and the binaries need it
# beside them.  Copy only msys-2.0.dll: that directory also collects leftovers
# owned by no package - a stale msys-z.dll there once overwrote the packaged
# zlib in a test root and bsdtar quietly started reporting the older version.
cp -f "${SYSROOT}/bin/msys-2.0.dll" "${ROOT}/usr/bin/"

# The target's /etc, if the packages shipped one.
[[ -d ${SYSROOT}/etc ]] && cp -a "${SYSROOT}/etc/." "${ROOT}/etc/"

cat > "${ROOT}/aarch64-shell.cmd" <<'CMD'
@echo off
rem Start a Windows-ARM64 msys shell in this root.
set "ROOT=%~dp0"
set "PATH=%ROOT%usr\bin;%PATH%"
"%ROOT%usr\bin\bash.exe" --login -i
CMD

msg "checking the result"
printf '  executables : %s\n' "$(ls "${ROOT}"/usr/bin/*.exe 2>/dev/null | wc -l)"
printf '  dlls        : %s\n' "$(ls "${ROOT}"/usr/bin/*.dll 2>/dev/null | wc -l)"
[[ -f ${ROOT}/usr/bin/msys-2.0.dll ]] || die "msys-2.0.dll missing from ${ROOT}/usr/bin"
[[ -f ${ROOT}/usr/bin/bash.exe ]]     || die "bash.exe missing from ${ROOT}/usr/bin"

# Anything in the root that differs from the sysroot means a stale file survived.
diffs=0
for f in "${SYSROOT}"/usr/bin/*.exe "${SYSROOT}"/usr/bin/*.dll; do
  b=$(basename "$f")
  cmp -s "$f" "${ROOT}/usr/bin/${b}" || { warn "differs from sysroot: ${b}"; diffs=$((diffs+1)); }
done
[[ $diffs -eq 0 ]] && msg "root matches the sysroot exactly"

msg "stage 2 complete - open a shell with ${ROOT}/aarch64-shell.cmd"
