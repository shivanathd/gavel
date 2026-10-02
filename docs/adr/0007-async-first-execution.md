# 0007. Async-first execution

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-007)

## Context

Callouts can't run after uncommitted DML, and record-triggered flows need the async path for callouts. Bulk loads of 200 records would hit callout limits in a single transaction.

## Decision

The primary path is a Queueable with `Database.AllowsCallouts`, chunked at 20 records. A sync invocable exists only for screen flows and Apex callers that have no pending DML.

## Consequences

Results arrive seconds after save, not inside it, and the UI shows a PENDING state. Record-triggered templates use the async path.

## Alternatives

Platform Event subscriber (more moving parts, harder to debug). Continuations (UI only).
