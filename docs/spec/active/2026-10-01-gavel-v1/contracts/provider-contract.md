# Contract: StateBuilder / Policy <-> JudgmentProvider

**Version:** 1.0.0 | **Owner:** gavel-core | **Consumers:** F4, F5, F7, F10, F11, F12

## Request (Gavel side, provider-neutral)
| Field | Type | Required | Rule |
|---|---|---|---|
| definitionApiName | String | yes | Matches `Gavel_Decision__mdt.DeveloperName` |
| definitionVersion | Integer | yes | >= 1 |
| model | String | yes | Pinned ID when Mode = Live (ADR-003) |
| state | Map<String,Object> | yes | Built only by F3; canonical JSON <= 150,000 chars |
| questions | List | yes | 1..64; keys unique `^[A-Za-z0-9_]{1,80}$` |
| questions[].type | enum | yes | choice, score, noul |
| questions[].options | List | choice/score | choice 2..255; score 2..10 levels starting at 0 |
| timeoutMs | Integer | no | default 10000, max 60000 |

## Wire (TypeSafe)
`POST https://api.typesafe.ai/v1/systemone`, header `Authorization: Bearer <key>` injected by the External Credential. Body carries `model`, `state` and `questions`. Exact question object field names are [UNVERIFIED] (OQ-2) and get pinned by the live contract test before release.

## Response guarantees (after provider validation)
| Field | Guarantee |
|---|---|
| status | One of ok, invalid_request, invalid_response, contract_mismatch, timeout, http_error, circuit_open, budget_exceeded |
| answers | Present only when status = ok; one entry per question key, or that key marked invalid_response |
| choice.probabilities | Keys == option keys; sum 1 +/- 0.01; each in [0,1] |
| confidence | [0,1] or null (null forces REVIEW) |
| noul.probability | [0,1] |
| modelVersion | Versioned ID reported by provider, or null plus a warning |

## Breaking change policy
Any change to status values or answer shape is a major version bump of gavel-core.
