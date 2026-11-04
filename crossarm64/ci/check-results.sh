#!/usr/bin/env bash
# Compare a suite's results with the failures we know about.
#
#   bash crossarm64/ci/check-results.sh <suite> <summary-file>...
#
# Every runner in crossarm64 writes one line per test, result first, name
# second (PASS, FAIL, FAIL(rc=N), TIMEOUT, SKIP, ...).  A test that fails and
# is not listed in crossarm64/ci/expected/<suite>.txt fails the step; a listed
# one that now passes is reported, so the list can be trimmed.  Without a
# list the step only reports.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

suite=$1; shift
list=$REPO/crossarm64/ci/expected/$suite.txt
results=$(cat "$@" | awk '$1 !~ /TOTAL/ && NF >= 2 {print $1, $2}')
failed=$(awk '$1 ~ /^(FAIL|TIMEOUT|ERROR|XPASS)/ {print $2}' <<<"$results" | LC_ALL=C sort -u)
passed=$(awk '$1 == "PASS" {print $2}' <<<"$results" | LC_ALL=C sort -u)
count() { [[ -z $1 ]] && echo 0 || wc -l <<<"$1"; }

summary=${GITHUB_STEP_SUMMARY:-/dev/null}
{
  echo "### $suite"
  echo
  echo "| result | tests |"
  echo "|---|--:|"
  awk '{sub(/\(.*/, "", $1); print $1}' <<<"$results" | sort | uniq -c | awk '{printf "| %s | %d |\n", $2, $1}'
  echo
} >> "$summary"

if [[ ! -f $list ]]; then
  echo "no list of known failures ($list): reporting only"
  echo "$(count "$failed") failing:"; sed 's/^/  /' <<<"$failed"
  echo "No list of known failures yet; $(count "$failed") failing tests reported, not checked." >> "$summary"
  exit 0
fi

known=$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^$' | LC_ALL=C sort -u)
new=$(LC_ALL=C comm -23 <(echo "$failed") <(echo "$known") | grep -v '^$' || true)
fixed=$(LC_ALL=C comm -12 <(echo "$passed") <(echo "$known") | grep -v '^$' || true)

echo "failing: $(count "$failed"), known: $(count "$known"), new: $(count "$new"), known but passing now: $(count "$fixed")"
[[ -z $fixed ]] || { echo "known failures that pass now:"; sed 's/^/  /' <<<"$fixed"; }
{
  [[ -z $fixed ]] || { echo "Known failures that pass now: $(tr '\n' ' ' <<<"$fixed")"; echo; }
  [[ -z $new ]] || { echo "**New failures:** $(tr '\n' ' ' <<<"$new")"; echo; }
} >> "$summary"
if [[ -n $new ]]; then
  echo "new failures:"; sed 's/^/  /' <<<"$new"
  exit 1
fi
