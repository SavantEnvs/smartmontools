#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer tests for the normal-flag smartctl that mayhem/build.sh built
# (mayhem/_build/test/src/smartctl). Each case feeds one synthetic "smartctl -r ataioctl,2" capture
# (mayhem/test/fixtures, made by mayhem/test/gen_fixtures.py) to `smartctl -`, and/or a tiny drive
# database (mayhem/test/drivedb.h) via -B, and checks exact output lines: identity, drive-database
# match + warning, health verdict, attribute table, error log and self-test log. exit 0 = pass.
#
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


SMARTCTL="$SRC/mayhem/_build/test/src/smartctl"
FIX="$SRC/mayhem/test/fixtures"
DB="$SRC/mayhem/test/drivedb.h"
if [ ! -x "$SMARTCTL" ]; then
  echo "missing $SMARTCTL: mayhem/build.sh did not build it" >&2
  emit_ctrf "smartctl-kat" 0 1 0
  exit 1
fi
export LC_ALL=C TZ=UTC

passed=0 failed=0
# expect <case name> <output> <exact line>
expect() {
  if printf '%s\n' "$2" | grep -qxF -- "$3"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL $1: expected line: $3" >&2
  fi
}

run() { "$SMARTCTL" -B "$DB" -i -H -A -l error -l selftest - < "$FIX/$1.txt" 2>/dev/null; }

out=$(run disk_ok)
expect ok "$out" "Model Family:     Mayhem Test Spinning Disks"
expect ok "$out" "Device Model:     MAYHEMTEST HDD 1TB"
expect ok "$out" "Serial Number:    MH-SN-0001"
expect ok "$out" "Firmware Version: FW1.00"
expect ok "$out" "User Capacity:    1,000,204,886,016 bytes [1.00 TB]"
expect ok "$out" "Rotation Rate:    7200 rpm"
expect ok "$out" "Device is:        In smartctl database"
expect ok "$out" "==> WARNING: Mayhem test warning: sample entry"
expect ok "$out" "SMART overall-health self-assessment test result: PASSED"
expect ok "$out" "  9 Power_On_Minutes        0x0032   099   099   000    Old_age   Always       -       35h+12m"
expect ok "$out" "197 Total_Pending_Sectors   0x0012   100   100   000    Old_age   Always       -       0"
expect ok "$out" "  4 Unknown_Attribute       0x0032   100   100   000    Old_age   Always       -       123"
expect ok "$out" "No Errors Logged"
expect ok "$out" "# 1  Short offline       Completed without error       00%       100         -"

out=$(run disk_failing)
expect failing "$out" "Device Model:     MAYHEMTEST HDD FAIL"
expect failing "$out" "Device is:        Not in smartctl database"
expect failing "$out" "SMART overall-health self-assessment test result: FAILED!"
expect failing "$out" "Drive failure expected in less than 24 hours. SAVE ALL DATA."
expect failing "$out" "  5 Unknown_Attribute       0x0033   001   001   036    Pre-fail  Always   FAILING_NOW 65535"
expect failing "$out" "# 2  Extended offline    Fatal or unknown error        00%      1000         0"

out=$(run disk_ssd)
expect ssd "$out" "Model Family:     Mayhem Test Solid State Drives"
expect ssd "$out" "User Capacity:    256,060,514,304 bytes [256 GB]"
expect ssd "$out" "177 Wear_Leveling_Count     0x0013   090   090   010    Pre-fail  Always       -       150"
expect ssd "$out" "No self-tests have been logged.  [To run self-tests, use: smartctl -t]"

out=$("$SMARTCTL" -B "$DB" -P showall "MAYHEMTEST HDD 1TB" FW1.00 2>/dev/null)
expect drivedb "$out" "MODEL FAMILY:       Mayhem Test Spinning Disks"
expect drivedb "$out" "                    197 Total_Pending_Sectors"
out=$("$SMARTCTL" -B "$DB" -P showall 2>/dev/null)
expect drivedb "$out" "Total number of entries  :    4"

emit_ctrf "smartctl-kat" "$passed" "$failed" 0
