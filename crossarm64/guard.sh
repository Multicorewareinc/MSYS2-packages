# Fail-fast checks for the aarch64-pc-msys cross recipes.
#
# Sourced from build() in every cross-msysarm64-* recipe that cross-compiles
# (NOT the toolchain packages - binutils, gcc, gcc-stage1, w32api-*, runtime-*
# are built by the *native* compiler to produce the cross tools, so their CC is
# supposed to be x86_64).
#
#   source "${startdir}/../crossarm64/guard.sh"
#   crossarm64_assert_env
#
# Why this exists.  makepkg's --config REPLACES /etc/makepkg.conf; without it
# the stock file wins, and this root's /etc/makepkg.conf sets CC=gcc.  ncurses'
# configure honours a pre-set CC before it ever scans PATH for the
# ${host}-prefixed compiler:
#
#     if test -n "$CC"; then
#       ac_cv_prog_CC="$CC" # Let the user override the test.
#
# so `makepkg` without --config silently produces a native x86_64 build wearing
# an --host=aarch64-pc-msys label.  It configures, compiles, links, packages and
# installs without a single error; the damage only surfaces much later when
# something tries to run it on the target.  That is exactly the silent
# degradation the recipes already guard against elsewhere, so guard it here too.
#
# Note this check cannot live in makepkg-crossarm64.conf or lib.sh: the profile
# is what goes missing, and lib.sh always passes --config, so neither is on the
# path that fails.  It has to run inside the PKGBUILD.

_CROSSARM64_TARGET=aarch64-pc-msys

# Assert the cross profile is actually in effect.  Call at the top of build(),
# before configure - the point of this is to fail in seconds rather than after
# a full native build.
crossarm64_assert_env() {
  local bad=()

  # Set only by makepkg-crossarm64.conf.  Empty means the profile was not read.
  [[ -n ${_BUILD:-}        ]] || bad+=("_BUILD is empty")
  [[ -n ${CC_FOR_BUILD:-}  ]] || bad+=("CC_FOR_BUILD is empty")

  # The check that would have caught the ncurses build: ask the compiler what it
  # targets rather than trusting its name.
  if [[ -z ${CC:-} ]]; then
    bad+=("CC is unset")
  else
    local dm
    dm=$(${CC} -dumpmachine 2>/dev/null) || dm="<${CC} failed to run>"
    [[ $dm == "${_CROSSARM64_TARGET}" ]] ||
      bad+=("CC=${CC} targets '${dm}', expected '${_CROSSARM64_TARGET}'")
  fi

  # Deliberately NOT checked: -specs= in CFLAGS.  The profile sets !buildflags,
  # which makes makepkg clear CFLAGS/LDFLAGS before build() runs, so the specs
  # file never reaches the recipe this way - which is precisely why the recipes
  # apply the -e _msys_dll_entry fix by hand.  CFLAGS is empty under a correct
  # build, so asserting on it only produces a false failure.

  [[ ${#bad[@]} -eq 0 ]] && return 0

  error "the aarch64 cross profile is not in effect:"
  printf '      - %s\n' "${bad[@]}" >&2
  plainerr "build with the profile, e.g."
  plainerr "    makepkg --config \"\$(dirname \$PWD)/crossarm64/makepkg-crossarm64.conf\" -d -f --skippgpcheck"
  plainerr "or via crossarm64/10-packages.sh, which passes it and installs the result."
  plainerr "Delete src/ before retrying - a native tree caches native configure answers."
  return 1
}

# Assert the named build outputs are actually AArch64.  Call after make, before
# packaging.  Takes globs; unmatched globs are skipped, but matching zero files
# overall is itself a failure (that is the "shared build silently disabled"
# case).  `file` prints "ARM64" for both PE images and COFF objects here, and
# "x86-64" for the native ones.
crossarm64_assert_arch() {
  local f out checked=0 bad=0
  for f in "$@"; do
    [[ -f $f ]] || continue
    checked=$((checked + 1))
    out=$(file -b "$f" 2>/dev/null)
    case $out in
      *ARM64*|*Aarch64*|*aarch64*) ;;
      *) error "wrong architecture: %s: %s" "$f" "$out"; bad=1 ;;
    esac
  done

  if [[ $checked -eq 0 ]]; then
    error "crossarm64_assert_arch: none of the expected outputs exist: %s" "$*"
    return 1
  fi
  [[ $bad -eq 0 ]] || {
    error "not every output is an ${_CROSSARM64_TARGET} binary - see above"
    plainerr "an x86-64 result here means the cross profile was not in effect;"
    plainerr "delete src/ and rebuild with --config crossarm64/makepkg-crossarm64.conf"
    return 1
  }
  msg2 "architecture check: ${checked} output(s), all ARM64"
  return 0
}
