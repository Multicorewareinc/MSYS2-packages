#!/usr/bin/env bash
# Bound `ar` so a hung archive step fails fast instead of stalling the build.
#
# Archiving libdll.a can wedge silently for ~3h15m at "CCAS sigfe.o" on the
# aarch64 cross build.  build() therefore passes
#     AR="bash ar-watchdog.sh ${AR}"
# so every ar invocation runs under a timeout and a stall becomes a loud,
# quick failure rather than a build that appears to hang forever.
#
# Args: the real ar program followed by its arguments.
set -u

_timeout=${AR_WATCHDOG_TIMEOUT:-900}

if [ "$#" -eq 0 ]; then
  echo "ar-watchdog.sh: no ar command given" >&2
  exit 2
fi

timeout --signal=TERM --kill-after=30 "${_timeout}" "$@"
_rc=$?

if [ "${_rc}" -eq 124 ] || [ "${_rc}" -eq 137 ]; then
  echo "FATAL: ar exceeded ${_timeout}s watchdog and was killed: $*" >&2
  exit 1
fi

exit "${_rc}"
