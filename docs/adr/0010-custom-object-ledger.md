# 0010. Custom object ledger in v1, Big Object later

- Status: Accepted, Revisit at v1.1
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-010)

## Context

Big Objects scale better but are hard to report on and can't have triggers. v1 users need related lists, reports and an immutability trigger.

## Decision

`Gavel_Decision_Log__c` custom object with a retention batch. Big Object archive in v1.1.

## Consequences

Storage cost in high-volume orgs, mitigated by retention.

## Alternatives

Big Object now. External log (sends more data out of the org).
