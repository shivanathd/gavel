# 0006. Data minimization by default

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-006)

## Context

TypeSafe's retention and training terms aren't verified yet (OQ-1). Case, Lead and EmailMessage text often contains PII.

## Decision

Only allowlisted fields are sent. The default redaction profile is `strict`. The ledger stores a state hash, not the state, unless an admin opts in. Egress is off after install.

## Consequences

Setup has one extra step. Safer default posture for security reviews.

## Alternatives

Send the whole record for better judgments (rejected). Only redact when opted in (rejected).
