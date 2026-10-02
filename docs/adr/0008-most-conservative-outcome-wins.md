# 0008. Most-conservative outcome wins

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-008)

## Context

A definition asks several questions. Averaging probabilities or taking the best one hides risk.

## Decision

The definition outcome is the most conservative outcome among required questions. The order is ERROR > SKIP > ESCALATE > REVIEW > AUTO.

## Consequences

Fewer auto-actions, and each one is easy to defend.

## Alternatives

Weighted composite (harder to explain to auditors, and can dilute one red flag).
