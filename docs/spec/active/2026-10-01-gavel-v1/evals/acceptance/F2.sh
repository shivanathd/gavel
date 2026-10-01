#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F2 REQ-DEF-001 acceptance. Test methods required in Gavel_DefinitionValidator_Test:
#   AS-2.1 validDefinitionActivates
#   AS-2.2 hashMismatchRejected
#   AS-2.3 scoreLevelsMustStartAtZero
sf apex run test --tests "Gavel_DefinitionValidator_Test.validDefinitionActivates,Gavel_DefinitionValidator_Test.hashMismatchRejected,Gavel_DefinitionValidator_Test.scoreLevelsMustStartAtZero" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F2.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F2.json)" = "Passed" ]
