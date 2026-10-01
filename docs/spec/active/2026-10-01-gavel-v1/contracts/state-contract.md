# Contract: Salesforce records -> StateBuilder

**Version:** 1.0.0 | **Owner:** gavel-core

- Input: recordId, definition. Output: StateResult {state, stateHash, truncated, redactionsApplied, missingRequired}.
- Only `Gavel_State_Field__mdt` paths are read, `WITH USER_MODE`, then `Security.stripInaccessible`.
- Null, blank or inaccessible values mean the key is omitted. If a required key is missing, the run SKIPs with `insufficient_state`.
- Redaction runs before serialization. The ledger gets profile:count only, never matched values.
- Canonical JSON: sorted keys, no whitespace, UTF-8. `stateHash` = SHA-256 hex.
- Egress kill switch checked before build.
