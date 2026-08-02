#!/bin/bash
# Run all dnn functional + regression tests and summarize.
#
# Usage:
#   source ./env.sh && ./tests/dnn/run_all.sh
#
# Exits non-zero if any test fails.

set -e

DNN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "DNN test suite"
echo "============================================================"

overall_pass=0
overall_fail=0
ran=0

run_one() {
    local script="$1"
    echo
    echo "---- $script ----"
    set +e
    "${DNN_DIR}/${script}"
    local rc=$?
    set -e
    ran=$((ran + 1))
    # Each script's own summary line reflects pass/fail; collect via rc.
    if [ ${rc} -ne 0 ]; then
        overall_fail=$((overall_fail + 1))
    else
        overall_pass=$((overall_pass + 1))
    fi
}

# Regression test first -- cheapest signal, catches teardown regressions.
run_one teardown_abort/test.sh

# Functional tests -- require prepared models.
run_one test_brightness.sh
run_one test_denoise.sh
run_one test_super_res.sh

echo
echo "============================================================"
echo "Overall: ${overall_pass}/${ran} test scripts passed, ${overall_fail} failed"
echo "============================================================"
[ "${overall_fail}" -eq 0 ]
