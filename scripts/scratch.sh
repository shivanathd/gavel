#!/usr/bin/env bash
# Creates a Gavel scratch org (PKG-001.3): Knowledge and Platform Cache enabled, admin made a Knowledge user.
#   ./scripts/scratch.sh gavel-scratch [--devhub devhub] [--days 7]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALIAS="${1:-gavel-scratch}"
shift || true
DEVHUB="devhub"
DAYS=7
while [ $# -gt 0 ]; do
  case "$1" in
    --devhub) DEVHUB="${2:-}"; shift 2 ;;
    --days) DAYS="${2:-7}"; shift 2 ;;
    -h|--help) echo "Usage: scripts/scratch.sh <alias> [--devhub <alias>] [--days <n>]"; exit 0 ;;
    *) echo "scratch.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
command -v sf >/dev/null 2>&1 || { echo "scratch.sh: sf CLI v2 is required" >&2; exit 2; }

sf org create scratch -d -a "$ALIAS" -f "$ROOT/config/project-scratch-def.json" -v "$DEVHUB" --duration-days "$DAYS" --wait 30 || exit 1
USERNAME="$(sf org display --target-org "$ALIAS" --json | jq -r '.result.username')"
# Knowledge user, so KB Coverage can search articles.
sf data update record --sobject User --where "Username='$USERNAME'" --values "UserPermissionsKnowledgeUser=true" --target-org "$ALIAS" >/dev/null 2>&1 \
  && echo "Made $USERNAME a Knowledge user." \
  || echo "Could not enable Knowledge user (Knowledge may be off); KB Coverage will SKIP knowledge_unavailable."
echo "Scratch org '$ALIAS' ready. Next: ./scripts/deploy.sh --org $ALIAS --packs service,sales-marketing,agentforce-gate --sample-data"
