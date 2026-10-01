# 0000. Name the project Gavel, not JevForce

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-000)

## Context

Ravi Narayanan published JevForce, an Apache 2.0 Apex SDK for calling Jev from Salesforce ([JevForce](https://github.com/ravinarayanan89/JevForce)). Reusing that name would confuse users and look like a fork. "Jev" is TypeSafe's product name, and putting it in our project name implies an affiliation we don't have. A GitHub search for `gavel+salesforce` returned no repos (2026-10-01).

## Decision

The project is called **Gavel**. Repo `shivanathd/gavel`. Tagline: "Governed AI judgments for Salesforce." Package descriptions say "works with TypeSafe Jev", never "Jev for Salesforce". Metadata prefix is `Gavel_`.

## Consequences

Clean identity and room for more providers later. A small discoverability cost for people searching "Jev Salesforce", which the README and topics (`jev`, `typesafe`, `salesforce`, `agentforce`) cover.

## Alternatives

"Verdict" (taken by several Salesforce repos), "Arbiter" (existing Salesforce ORM repo), "JevGuard" (Jev in the name), "Decision Ledger" (too narrow).
