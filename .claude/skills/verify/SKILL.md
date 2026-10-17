---
name: verify
description: Verify Gavel end to end in a scratch org, from released packages or this branch, against real TypeSafe Jev.
---

# Verifying Gavel at its surface

The surface is the public Apex API (`Gavel.run(recordId, definition)`) running in an org, with records, files, and the
real provider. Apex tests are CI's job; this recipe drives the installed product.

## Org

- Dev Hub alias `devhub` (personal Developer Edition, not a work org). On the mini every `sf` call needs
  `SF_USE_GENERIC_UNIX_KEYCHAIN=true`. Limits: 6 scratch orgs a day, 3 active, 6 package versions a day.
- `sf org create scratch -a gavel-verify -f config/project-scratch-def.json -v devhub --duration-days 1`
- Released build: `sf package install --package <04t> --security-type AdminsOnly --no-prompt --wait 30` for the
  eight IDs in the release notes, in order. Branch build: `./scripts/deploy.sh --org gavel-verify --packs ...`.
- `sf org assign permset --name` Gavel_Admin, Gavel_Runtime, Gavel_Callout and the pack permission sets.

## Turn it on

- Egress is off after install. Every run is `SKIP egress_disabled` with no callout, which is worth checking first.
  To turn it on, deploy `Gavel_Ops_Config.Default` with `Egress_Enabled__c = true` from a throwaway sfdx project.
  Add `--ignore-conflicts` when the org was deployed with `deploy.sh`, or the deploy stops on a source conflict. Read
  `Gavel_Config.ops().egressEnabled` back to confirm it took.
- Put the API key on the principal through the Connect API, never through Apex. Anonymous Apex source lands in debug
  logs. POST `/services/data/v64.0/named-credentials/credential` with
  `{"externalCredential":"Gavel_TypeSafe_Auth","principalName":"Gavel_TypeSafe_Principal","principalType":"NamedPrincipal","credentials":{"apiKey":{"value":"…","encrypted":true}}}`.
  Pipe the key from the keychain into a 0600 temp file, send it with `sf api request rest … --body - < file`, then
  delete the file.
- To go Live, deploy the `Gavel_Decision` record with `Mode__c = Live` the same way.

## Drive

- One `Gavel.run` per `sf apex run` call. A callout after DML in the same transaction fails with "uncommitted work
  pending".
- Print results with `System.debug(LoggingLevel.ERROR, 'VERIFY …')` and grep `.result.logs`. Read
  `Gavel_Decision_Log__c` for `Model_Version__c`, `Http_Status__c` and `Answers_JSON__c`. The outcome's
  `probabilities` keys show which options were offered.
- Files: anonymous Apex is capped at 32 KB, so upload photos with REST:
  `sf api request rest /services/data/v64.0/sobjects/ContentVersion --method POST --body - < cv.json`, where the
  body has `VersionData` (base64) and `FirstPublishLocationId`. `--body <path>` sends the path text, not the file.
- The response cache keys on the state hash for `Cache_TTL_Min__c` (60). Use a new record to force a fresh call.
- zsh does not word-split `$var`, so pass arguments explicitly.

## Flows worth driving (returns)

- Photo check, then triage, on: a damaged photo; a wrong or intact photo (expect `matches_claim` false, a Box below
  Review_At, and `box_not_found`); no photo (`SKIP insufficient_state`); and a photo replaced after the check
  (triage `REVIEW`).
- Triage only: purchased 45 days ago (refund and replace not offered), $900 (`refund` goes to `REVIEW`), and Live
  (`Case.Gavel_Return_Outcome__c` is set).
- Image limits: TypeSafe accepts 280–1568 px per side. Smaller or larger images must `SKIP image_size_unsupported`
  before any callout.
