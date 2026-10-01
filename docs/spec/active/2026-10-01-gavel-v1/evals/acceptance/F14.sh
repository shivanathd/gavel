#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F14 REQ-DOC-001 acceptance. Test methods required in scripts:
#   AS-14.1 egressPageComplete
#   AS-14.2 adrFormat
"$ROOT/scripts/docs-egress-check.sh" && bash "$(dirname "$0")/../tasks/T6.2.sh"
