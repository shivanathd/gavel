# Security Policy

## Reporting a vulnerability

Email the maintainer (see the GitHub profile for `shivanathd`) with the subject `GAVEL SECURITY`. Do not open a public issue. You will get an acknowledgement within 5 working days.

## Rules every change must follow

### Secrets
- The TypeSafe API key lives in exactly one place: the External Credential principal `Gavel_TypeSafe_Auth` / `Gavel_TypeSafe_Principal`. Salesforce injects the `Authorization` header at callout time.
- Never put a key, token or bearer value in Apex, Custom Metadata, Custom Settings, static resources, scripts, docs, test fixtures or CI config. CI reads Dev Hub auth from GitHub secrets only.
- Test fixtures that need a token-shaped string must build it at runtime from fragments so source scans stay clean.

### Logging
- No `System.debug` of state, request bodies, response bodies, headers or exception messages from callouts.
- Ledger fields never hold raw provider error bodies, only typed statuses and HTTP status codes.
- Redaction summaries record `type:count`, never the matched value.

### Data leaving the org
- Only `Gavel_State_Field__mdt` allowlisted paths are read, with `WITH USER_MODE` plus `Security.stripInaccessible`.
- Redaction runs before serialization. Default profile is `strict`.
- `Gavel_Ops_Config__mdt.Egress_Enabled__c` is `false` after install. When false, no provider call is made, including the mock.
- Every definition's fields are listed in `docs/guides/data-leaving-your-org.md`, enforced by `scripts/docs-egress-check.sh`.

### Fail closed
- Provider and runtime errors become typed statuses, then ERROR or SKIP outcomes. Nothing auto-acts on an error.
- Invocable actions never throw into Flow.
- Gavel only ever sets opt-out style fields (`HasOptedOutOfEmail`, `HasOptedOutOfFax`, `DoNotCall`) to `true`.

### Ledger
- `Gavel_Decision_Log__c` is insert-only. Updates and deletes are blocked by trigger for every user, including System Administrators. The only exceptions are the retention purge and the one-time finalization of a PENDING async entry, both inside `Gavel_Ledger`.
- Entries are hash-chained per definition. `Gavel_LedgerVerifier` detects tampering.

## Known limits
- Redaction is best-effort pattern matching, not DLP.
- The Agentforce gate is advisory unless the wrapped action is reachable only through the wrapper (ADR-014).
