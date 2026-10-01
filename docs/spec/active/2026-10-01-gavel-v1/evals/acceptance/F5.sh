#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F5 REQ-POL-001 acceptance. Test methods required in Gavel_PolicyEngine_Test:
#   AS-5.1 marginBlocksAuto
#   AS-5.2 escapeOption
#   AS-5.3 shadowNeverActs
#   AS-5.4 conservativeCombination
sf apex run test --tests "Gavel_PolicyEngine_Test.marginBlocksAuto,Gavel_PolicyEngine_Test.escapeOption,Gavel_PolicyEngine_Test.shadowNeverActs,Gavel_PolicyEngine_Test.conservativeCombination" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F5.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F5.json)" = "Passed" ]
