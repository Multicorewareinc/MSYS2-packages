#!/usr/bin/env bash
# CI stages 3, 5 and 7: cross-build one chain of the userland into the
# sysroot, then assemble the ARM64 root from it (crossarm64/30-mkroot.sh).
#
#   bash crossarm64/ci/build-userland.sh bash|ssh|mingit
#
#   bash    the bash chain of #6922, plus the tools the test suites call
#           (from a clean sysroot; starts the run's $RUN)
#   ssh     the ssh chain of #6922, plus OpenSSH's regress helpers
#   mingit  the rest of MinGit's usr/bin, then MinGit itself
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

case ${1:?bash, ssh or mingit} in
bash)
  group "Start from the toolchain's sysroot"
  restore_sysroot
  rm -rf "$RUN"/{userland,logs,root,openssh-build,mingit}
  endgroup
  build_userland "$PR_CONF" libiconv gettext ncurses readline bash gmp coreutils
  build_userland "$HARNESS_CONF" mpfr gawk sed grep diffutils findutils hexdump
  ;;
ssh)
  build_userland "$PR_CONF" zlib openssl libxcrypt libcbor libfido2 libedit db sqlite heimdal openssh
  group "OpenSSH regress helpers"
  B=$(ls -d "$REPO"/openssh/src/openssh-*/ | head -1)
  make -C "$B" regress-binaries regress-unit-binaries > "$RUN/logs/openssh-regress.log" 2>&1 ||
    { tail -30 "$RUN/logs/openssh-regress.log"; exit 1; }
  # the sk-dummy provider reads data from msys-2.0.dll without dllimport,
  # which does not work on ARM64 yet (crossarm64/README.md); disable those tests
  mv -f "$B/regress/misc/sk-dummy/sk-dummy.so" "$B/regress/misc/sk-dummy/sk-dummy.so.disabled" 2>/dev/null || true
  rm -rf "$RUN/openssh-build"; cp -a "$B" "$RUN/openssh-build"
  endgroup
  ;;
mingit)
  build_userland "$HARNESS_CONF" dash util-linux rebase
  ;;
*) echo "unknown chain $1"; exit 2 ;;
esac

group "Assemble the ARM64 root"
bash "$REPO/crossarm64/30-mkroot.sh" "$ROOT"
mkdir -p "$ROOT/ci"
cp -f "$REPO"/crossarm64/test/run-*-tests.sh "$REPO/crossarm64/test/ssh-test-setup.sh" "$ROOT/ci/"
if [[ -d $RUN/openssh-build ]]; then
  rm -rf "$ROOT/build/openssh"; mkdir -p "$ROOT/build"
  cp -a "$RUN/openssh-build" "$ROOT/build/openssh"
fi
endgroup

if [[ $1 == mingit ]]; then
  group "Assemble MinGit"
  ROOT=$ROOT CACHE=$STATE/cache bash "$REPO/crossarm64/50-mingit-proto1.sh" "$RUN/mingit"
  endgroup
fi
