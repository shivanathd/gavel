#!/usr/bin/env bash
# AS-14.1: every Gavel_State_Field__mdt Field_Path__c must be listed on docs/guides/data-leaving-your-org.md
# under its definition's heading ("## <Definition>"). Fails the build otherwise.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/docs/guides/data-leaving-your-org.md"
[ -f "$DOC" ] || { echo "docs-egress-check: $DOC is missing"; exit 1; }

value() { # value <file> <field>
  perl -0ne 'if (/<field>\Q'"$2"'\E<\/field>\s*<value[^>]*>(.*?)<\/value>/s) { print $1 }' "$1"
}
section() { # section <definition>: lines between "## <definition>" and the next "## "
  awk -v h="## $1" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$DOC"
}

missing=0
checked=0
while IFS= read -r -d '' f; do
  def="$(value "$f" Decision__c)"
  path="$(value "$f" Field_Path__c)"
  [ -z "$def" ] || [ -z "$path" ] && { echo "docs-egress-check: $(basename "$f") has no Decision__c or Field_Path__c"; missing=1; continue; }
  checked=$((checked + 1))
  if ! section "$def" | grep -qF "\`$path\`"; then
    echo "docs-egress-check: $def sends \`$path\` but it is not listed under '## $def' in docs/guides/data-leaving-your-org.md"
    missing=1
  fi
done < <(find "$ROOT/packages" -path '*/customMetadata/Gavel_State_Field.*.md-meta.xml' -print0)

if [ $missing -ne 0 ]; then
  exit 1
fi
echo "docs-egress-check: $checked state fields documented"
