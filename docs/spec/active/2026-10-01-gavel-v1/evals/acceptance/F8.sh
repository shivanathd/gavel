#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F8 REQ-CAL-001 acceptance. Test methods required in Gavel_Calibration_Test:
#   AS-8.1 overrideCaptured
#   AS-8.2 recommendationMeetsTarget
#   AS-8.3 noAutoChange
sf apex run test --tests "Gavel_Calibration_Test.overrideCaptured,Gavel_Calibration_Test.recommendationMeetsTarget,Gavel_Calibration_Test.noAutoChange" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F8.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F8.json)" = "Passed" ]
