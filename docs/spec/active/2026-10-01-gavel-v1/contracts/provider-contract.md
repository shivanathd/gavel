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
`POST https://api.typesafe.ai/v1/systemone`, header `Authorization: Bearer <key>` injected by the External Credential. Body carries `model`, `state` and `questions`. Shape verified on 2026-10-01 against docs.typesafe.ai/api and the live contract test (model `jev-1.13.0`):

```json
{"model": "jev-1.13.0", "state": {...},
 "questions": {
   "<key>": {"type": "choice", "instructions": "<prompt>", "criteria": {"<option key>": "<description or label>"}},
   "<key>": {"type": "score",  "instructions": "<prompt>", "criteria": ["<level 0>", "<level 1>", "..."]},
   "<key>": {"type": "noul",   "instructions": "<prompt>"}}}
```

`instructions` becomes `{"question": prompt, "rules": instructions}` when the question has rules. Answers come back under the same keys: choice `{choice, probabilities, confidence}`, score `{score, legend, probabilities, confidence}` (probability keys are level indices), noul `{noul}`. Errors: 401 bad key, 422 validation, 429 rate limit, 529 overloaded (429/503/529 retried once in async). The versioning policy is still open (OQ-2).

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
