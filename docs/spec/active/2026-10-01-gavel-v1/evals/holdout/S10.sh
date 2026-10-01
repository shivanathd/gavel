#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }
# Holdout S10: Contributor adds undocumented definition
# Prints SATISFIED | PARTIAL | NOT_SATISFIED | MANUAL_REVIEW
tmp=$(mktemp -d); cp -r "$ROOT" "$tmp/r"; cp "$(dirname "$0")/fixtures/undocumented_state_field.md-meta.xml" "$tmp/r/packages/gavel-pack-service/main/default/customMetadata/" 2>/dev/null; (cd "$tmp/r" && ./scripts/docs-egress-check.sh >/dev/null 2>&1) && echo NOT_SATISFIED || echo SATISFIED
