# Gavel

Governed AI judgments for Salesforce. Works with TypeSafe Jev.

The model judges. Your org's policy decides. Gavel keeps a record of both.

Gavel is a set of Salesforce components you can deploy: typed, calibrated judgments (Choice, Score, Noul) run from Flow, Apex and Agentforce. Every judgment passes through policy you set, lands in an immutable ledger, runs in shadow mode first, and gets calibrated against what your people actually do.

> Status: v1 implementation in progress (spec v1.0.0, 2026-10-01). Not released. The spec lives in `docs/spec/active/2026-10-01-gavel-v1/`; build status is in `PROGRESS.md`.

## Why this exists

Jev gives fast, typed answers with probabilities in place of generated text ([TypeSafe docs](https://docs.typesafe.ai/introduction)). On Salesforce so far that means an Apex SDK and a few demos. Before a model touches production routing, an enterprise needs:

- Decisions admins can configure without writing Apex
- A ledger that shows what was asked, what came back, which policy applied and what changed
- A shadow mode that compares against today's rules or Einstein
- Calibration based on human overrides
- Budget, circuit breaker and fail-closed behavior
- A gate in front of Agentforce

Gavel covers all of these.

## What's in the box

| Package | What it gives you | Depends on |
|---|---|---|
| `gavel-core` | Provider interface, TypeSafe and mock providers, state builder with field allowlist and redaction, policy engine, decision ledger, budgets and circuit breaker | none |
| `gavel-flow` | Flow actions: Run Decision, Run Decision (Async), Apply Outcome. Queueable runner, flow templates | core |
| `gavel-shadow` | Shadow mode, baseline capture, disagreement report, promotion gate | core, flow |
| `gavel-calibrate` | Override capture, reliability tables, threshold recommendations | core, shadow |
| `gavel-admin` | Lightning app, Decision Console, ledger related list, calibration dashboard, permission sets | all above |
| `gavel-pack-agentforce-gate` | Input screening, action risk labels, guarded action wrapper, Email-to-Case and Web-to-Lead intake screening | core, flow |
| `gavel-pack-service` | Case triage, real urgency, KB coverage and gap detection, closure check, reply check | core, flow, shadow |
| `gavel-pack-sales-marketing` | Lead quality and junk detection, reply intent, hidden opt-out detection, persona, stage evidence | core, flow, shadow, calibrate |

Every pack installs in Shadow mode. Nothing changes a record until you say so.

## How a decision runs

```
Salesforce record
  -> State Builder      (allowlisted fields only, user-mode, redacted)
  -> Judgment Provider  (TypeSafe Jev, pinned model, typed answers)
  -> Policy Engine      (your thresholds: AUTO | REVIEW | ESCALATE | SKIP | ERROR)
  -> Decision Ledger    (immutable, hash-chained)
  -> Action             (only AUTO + Live; otherwise a review item)
  -> Feedback           (human overrides feed calibration)
```

## Install

### Option A: unlocked packages (real orgs)

Install from the release install links in this order: core, flow, shadow, calibrate, admin, then any packs.

```bash
sf package install --package gavel-core@1.0.0 --target-org myorg --wait 20
# repeat for each package, see release notes for IDs
```

### Option B: source deploy (demos and learning)

```bash
git clone https://github.com/shivanathd/gavel && cd gavel
./scripts/scratch.sh gavel-scratch            # optional: new scratch org
./scripts/deploy.sh --org gavel-scratch --packs service,sales-marketing,agentforce-gate --sample-data
```

### After install

1. Setup, then Named Credentials, then External Credentials, then `Gavel_TypeSafe_Auth`. Add your API key to the principal. The key is stored in this one place only.
2. Assign `Gavel_Admin` to yourself and `Gavel_Runtime` to users or integration users that run decisions.
3. Open the Gavel app. Review "Data leaving your org". Turn Egress on.
4. Activate a template flow, for example "Case Created: Triage (Async)".
5. Let it run in Shadow, map the baseline, run calibration, then promote.

## Repository layout

```
gavel/
  sfdx-project.json
  config/project-scratch-def.json
  packages/
    gavel-core/main/default/{classes,objects,customMetadata,triggers,platformEvents,permissionsets}
    gavel-flow/main/default/{classes,flows}
    gavel-shadow/main/default/{classes,objects,customMetadata}
    gavel-calibrate/main/default/{classes,objects}
    gavel-admin/main/default/{applications,lwc,flexipages,tabs,permissionsets}
    gavel-pack-agentforce-gate/main/default/{customMetadata,classes,flows,genAiFunctions}
    gavel-pack-service/main/default/{customMetadata,flows,objects}  + data/
    gavel-pack-sales-marketing/main/default/{customMetadata,flows}  + data/
  scripts/
    deploy.sh  scratch.sh  hash-definitions.js  docs-egress-check.sh  live-contract-test.sh
  docs/
    adr/0000-name-gavel.md ... 0018-license.md
    spec/active/2026-10-01-gavel-v1/   (control plane: requirements, scenarios, plan, ADRs, contracts, evals)
    guides/  write-your-own-definition.md  shadow-to-live.md  data-leaving-your-org.md
    packs/   agentforce-gate.md  service.md  sales-marketing.md
  .github/workflows/  ci.yml  release.yml
  LICENSE (Apache 2.0)  NOTICE  SECURITY.md  CONTRIBUTING.md  CODE_OF_CONDUCT.md  CLAUDE.md  AGENTS.md
```

## Principles

- The model never owns the action. Policy in Salesforce does.
- Fail closed. Errors route to people, never to automation.
- Shadow before Live, and Live only with a calibration report.
- Send the minimum. Fields not on the allowlist don't leave the org.
- Everything is ledgered, including skips and errors.
- No accuracy claims without a reproducible eval.

## Prior art and credits

- [JevForce](https://github.com/ravinarayanan89/JevForce) by Ravi Narayanan: the first Apex SDK for Jev. Gavel is an independent codebase and does not copy JevForce code.
- [jev-mcp](https://github.com/jkudish/jev-mcp): the composed judgment patterns (screen, verify, find, decide) that inspired the packs.
- [typed-decisions-shadow-layer](https://github.com/alonsuare/typed-decisions-shadow-layer): the shadow-first pattern for CRM.

Gavel is not affiliated with TypeSafe AI or Salesforce. Jev is a product of TypeSafe AI. Salesforce, Agentforce and Flow are trademarks of Salesforce, Inc.

## License

Apache 2.0. Contributions need DCO sign-off.
