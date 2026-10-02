# 0013. Budgets and circuit breaker in core

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-013)

## Context

A runaway flow or data load can burn money and hammer a failing API.

## Decision

Per-definition daily budgets and an org-level breaker live in core. Every run passes through them.

## Consequences

A small overhead on each run.

## Alternatives

Leave it to admins (rejected).
