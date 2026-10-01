# Contract: Flow / Agentforce -> gavel-flow invocables

**Version:** 1.0.0 | **Owner:** gavel-flow

| Action | Inputs | Outputs | Context |
|---|---|---|---|
| Gavel: Run Decision | recordId, definitionApiName | outcome, reason, ledgerId, topChoice, topConfidence, answersJson | Screen flow, autolaunched with no pending DML (callout=true) |
| Gavel: Run Decision (Async) | recordId, definitionApiName | ledgerId (PENDING) | Record-triggered async path, bulk |
| Gavel: Apply Outcome | ledgerId | applied (Boolean), actions | Any; only acts on AUTO + Live |
| Gavel: Screen Input | text, taskDescription | recommendation (pass/review/block/skip), ledgerId | Agent action, intake flows |
| Gavel: Check Action Risk | actionDescription, targetSummary | label, outcome, ledgerId | Agent action, guarded wrapper |

Invocables never throw. Errors come back as outcome ERROR with a reason.
