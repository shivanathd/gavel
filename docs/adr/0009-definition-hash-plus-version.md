# 0009. Definition hash plus explicit version

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-009)

## Context

A ledger entry has to point to exactly what the model was asked. Admins forget to bump version numbers.

## Decision

CI computes a canonical hash over the definition and its children and stores it in `Definition_Hash__c`. At runtime Gavel recomputes the hash, and rejects the run if it doesn't match the stored value for that version.

## Consequences

Editing CMDT directly in Setup without a version bump makes Live runs ERROR until it's fixed. Documented loudly in the admin app.

## Alternatives

Version only (trusts humans). Hash only (not readable).
