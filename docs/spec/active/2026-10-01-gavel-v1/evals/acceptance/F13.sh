#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F13 REQ-PKG-001 acceptance. Test methods required in scripts:
#   AS-13.1 sourceDeploy
#   AS-13.2 packageInstall
"$ROOT/scripts/deploy.sh" --org "$ORG" --packs service --sample-data || exit 1
sf data query -q "SELECT count() FROM Case" --target-org "$ORG" --json | jq -e ".result.totalSize >= 200" >/dev/null
