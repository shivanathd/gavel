# 0005. Fail closed, never throw into Flow

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-005)

## Context

An unhandled exception in a flow shows users a fault screen or rolls back the transaction. An AI dependency must never break a Case save, and it must never auto-act when it isn't sure.

## Decision

Every provider and runtime error becomes a typed status. The policy engine maps these to ERROR or SKIP, and both route to review or to no action. Invocable actions always return normally.

## Consequences

Admins have to watch ERROR rates (alerts in F9). The business transaction always succeeds.

## Alternatives

Throw and let Flow fault paths handle it (rejected: too easy to misconfigure).
