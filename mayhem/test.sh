#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
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

# RUN the test runner that mayhem/build.sh produced, then map its output to counts.
#   ctest:        (cd build-tests && ctest) ; parse "<P> tests passed, <F> failed out of <T>"
#   gtest binary: ./build-tests/<prog> ; parse "[==========] N ... ran." / "[  PASSED  ] P" / "[ SKIPPED ] S"
#   make/minunit: ./out/<runner> ; parse its pass/fail/total
# Do NOT compile here — if the runner is absent, fail (build.sh should have produced it).

# Runs upstream's own googletest suites for the fuzzed code (src/test/llm/output_parsers/
# partial_json_builder_test.cpp, src/test/audio/audio_utils_test.cpp, src/test/image_decoder_test.cpp, src/test/schema_test.cpp,
# src/test/llm/chat_template_adjuster_test.cpp, src/test/tokenize_parser_test.cpp, src/test/llm/chat_template_analyzer_test.cpp,
# src/test/stringutils_test.cpp, src/test/decoded_image_size_test.cpp; fixtures via /ovms -> /mayhem),
# built by build.sh with normal flags. They assert decoded samples, pixels and JSON values.
BIN="$SRC/mayhem/out/ovms_unit_tests"
if [ ! -x "$BIN" ]; then echo "missing $BIN — run mayhem/build.sh first" >&2; emit_ctrf googletest 0 1; exit 1; fi
REPORT="$(mktemp "${TMPDIR:-/tmp}/ovms-gtest.XXXXXX.json")"
rm -f "$REPORT"
"$BIN" --gtest_output="json:$REPORT"; rc=$?
if [ ! -s "$REPORT" ]; then echo "test runner produced no report (rc=$rc)" >&2; emit_ctrf googletest 0 1; exit 1; fi
read -r total failed skipped < <(python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=f=s=0
for suite in d.get("testsuites",[]):
    for c in suite.get("testsuite",[]):
        t+=1
        if c.get("failures"): f+=1
        elif c.get("result")=="SKIPPED" or c.get("status")=="NOTRUN": s+=1
print(t,f,s)' "$REPORT")
rm -f "$REPORT"
passed=$(( total - failed - skipped ))
[ "$rc" -eq 0 ] || [ "$failed" -gt 0 ] || failed=1
emit_ctrf googletest "$passed" "$failed" "$skipped"
