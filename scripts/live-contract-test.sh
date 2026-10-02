#!/usr/bin/env bash
# Live contract test for /v1/systemone (F1, OQ-2). MAINTAINER ONLY: calls the real TypeSafe API with the key
# stored in the External Credential of the target org. Never run in CI or by an agent.
#   GAVEL_LIVE=1 GAVEL_ORG=my-dev-org ./scripts/live-contract-test.sh
# Exit codes: 0 contract holds, 1 contract broken, 3 not enabled (GAVEL_LIVE != 1).
set -uo pipefail
[ "${GAVEL_LIVE:-0}" = "1" ] || { echo "live-contract-test: requires GAVEL_LIVE=1, a key on Gavel_TypeSafe_Principal and OQ-1/OQ-2 resolved"; exit 3; }
ORG="${GAVEL_ORG:?set GAVEL_ORG}"
APEX="$(mktemp -t gavel-live.XXXXXX)"
trap 'rm -f "$APEX"' EXIT
cat > "$APEX" <<'APEXEOF'
Gavel_JudgmentRequest r = new Gavel_JudgmentRequest();
r.definitionApiName = 'Gavel_Live_Contract';
r.definitionVersion = 1;
r.model = [SELECT Model__c FROM Gavel_Provider_Config__mdt WHERE DeveloperName = 'TypeSafe_Default'].Model__c;
r.live = true;
r.state = new Map<String, Object>{ 'text' => 'I was charged twice for my subscription this month.' };
Gavel_Question c = new Gavel_Question('category', 'choice', 'Which team should handle this?');
c.options = new List<Gavel_Option>{ new Gavel_Option('BILLING', 'Billing'), new Gavel_Option('TECHNICAL', 'Technical') };
Gavel_Question n = new Gavel_Question('refund', 'noul', 'The customer asks for a refund.');
Gavel_Question s = new Gavel_Question('urgency', 'score', 'How urgent is this?');
for (Integer i = 0; i <= 4; i++) { Gavel_Option o = new Gavel_Option('L' + i, 'Level ' + i); o.level = i; s.options.add(o); }
r.questions = new List<Gavel_Question>{ c, n, s };
Gavel_JudgmentResponse resp = new Gavel_TypeSafeProvider().judge(r);
System.assertEquals('ok', resp.status, 'status ' + resp.status + ' ' + resp.errorCode);
System.assertNotEquals(null, resp.modelVersion, 'versioned model id must be reported');
System.assertNotEquals(null, resp.answers.get('category').confidence, 'choice confidence');
System.assertNotEquals(null, resp.answers.get('refund').probability, 'noul probability');
System.assertNotEquals(null, resp.answers.get('urgency').score, 'score value');
System.debug(LoggingLevel.ERROR, 'GAVEL_CONTRACT_OK model=' + resp.modelVersion
    + ' category=' + resp.answers.get('category').choice + ' confidence=' + resp.answers.get('category').confidence
    + ' refund=' + resp.answers.get('refund').probability + ' urgency=' + resp.answers.get('urgency').score
    + ' latencyMs=' + resp.latencyMs + ' end');
APEXEOF
out="$(sf apex run --file "$APEX" --target-org "$ORG" --json)"
if echo "$out" | jq -e '.result.success == true' >/dev/null; then
  echo "live contract holds"
  echo "$out" | jq -r '.result.logs // ""' | sed -n 's/.*GAVEL_CONTRACT_OK \(.* end\).*/  \1/p' | sed 's/ end$//' | head -1
  exit 0
fi
echo "live contract broken:"; echo "$out" | jq -r '.result.exceptionMessage // .message'; exit 1
