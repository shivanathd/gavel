# Gavel

Governed AI judgments for Salesforce. Works with TypeSafe Jev.

The model judges. Your org's policy decides. Gavel keeps a record of both.

Gavel is a set of Salesforce packages you can deploy. It runs typed, calibrated judgments (Choice, Score, Noul) from Flow, Apex and Agentforce. Every judgment passes through a policy you set and lands in an immutable ledger. Every decision runs in Shadow mode first and is calibrated against what your people actually do.

> **Status:** v1 is implemented and verified in a scratch org. All task and acceptance evals pass, and the live contract test passes against `api.typesafe.ai` with `jev-1.13.0`. v1 is not released yet: release waits on open questions OQ-1 and OQ-3 and on the OQ-2 versioning policy. Build status and design calls are in [PROGRESS.md](PROGRESS.md). The spec is in [docs/spec/active/2026-10-01-gavel-v1/](docs/spec/active/2026-10-01-gavel-v1/).

## Contents

- [What it can do](#what-it-can-do)
- [How a decision runs](#how-a-decision-runs)
- [Setup, in order](#setup-in-order)
- [The TypeSafe API key](#the-typesafe-api-key)
- [Configuration reference](#configuration-reference)
- [Using Gavel from Flow, Apex and Agentforce](#using-gavel-from-flow-apex-and-agentforce)
- [Packages](#packages)
- [Development and tests](#development-and-tests)

## What it can do

**For any process you define**
- **Ask typed questions about a record:** pick one option (Choice), rate on a scale (Score), or answer yes or no (Noul). Answers come back with probabilities and a confidence value instead of generated text.
- **Decide the outcome with your own policy:** thresholds you set turn every answer into AUTO, REVIEW, ESCALATE, SKIP or ERROR. The model never owns the action.
- **Keep an audit trail:** every run, including skips and errors, lands in an insert-only, hash-chained ledger (`Gavel_Decision_Log__c`). The ledger can be verified, and edits are blocked for admins too.
- **Send only what's allowed:** only allowlisted fields leave the org. They're read in user mode, with field-level security enforced, and redacted (email, phone, card, SSN profiles) before the call.
- **Prove a decision before it goes live:** Shadow mode records what the model would have done next to what your current process did. A promotion gate blocks Live until a calibration report shows enough agreement.
- **Learn from your reviewers:** when people confirm or correct a review item, that becomes calibration feedback. Gavel then recommends thresholds from reliability tables.
- **Stay safe when things fail:** daily call budgets, a circuit breaker, a response cache and an org-wide egress kill switch. Errors go to people, never to automation.

**Ready-made decisions in the packs**

| Pack | Decision | What it does | Ships in |
|---|---|---|---|
| Service | `Gavel_Case_Triage` | Routes a new Case to a queue or reason; flags security and fraud concerns | Shadow |
| Service | `Gavel_Case_Urgency` | Scores real urgency 0 to 4 from the text, regardless of the priority the customer picked | Shadow |
| Service | `Gavel_KB_Coverage` | Checks whether a Knowledge article answers the Case; creates a KB gap record if not | Shadow |
| Service | `Gavel_Closure_Check` | Before closing: did the customer confirm the fix? | Shadow |
| Service | `Gavel_Reply_Check` | Checks an outbound draft against the linked article: supported, contradicted or unsupported | Shadow |
| Sales & Marketing | `Gavel_Lead_Quality` | Separates real buyers from students, job seekers, vendors, competitors, spam and test data | Shadow |
| Sales & Marketing | `Gavel_Reply_Intent` | Reads the intent of an inbound reply to outreach | Shadow |
| Sales & Marketing | `Gavel_Opt_Out_Detect` | Finds opt-out requests hidden in replies. It only ever sets Email Opt Out, never clears it | Live, review only |
| Sales & Marketing | `Gavel_Persona` | Persona and seniority from the job title | Shadow |
| Sales & Marketing | `Gavel_Stage_Evidence` | Checks recent activity for the evidence each Opportunity stage exit needs | Shadow |
| Agentforce Gate | `Gavel_Input_Screen` | Screens inbound text (email, web form, chat) for injected instructions before an agent reads it | Shadow |
| Agentforce Gate | `Gavel_Action_Risk` | Labels an agent action as read-only, reversible or destructive. Destructive actions need a human | Shadow |

Each pack has a guide in [docs/packs/](docs/packs/). To build your own decision, see [docs/guides/write-your-own-definition.md](docs/guides/write-your-own-definition.md).

## How a decision runs

```
Salesforce record
  -> State Builder      allowlisted fields only, user mode, redacted, hashed
  -> Judgment Provider  TypeSafe Jev (pinned model) or the Mock provider
  -> Policy Engine      your thresholds -> AUTO | REVIEW | ESCALATE | SKIP | ERROR
  -> Decision Ledger    insert-only, hash-chained per definition
  -> Action             only when AUTO and Live; otherwise a review item
  -> Feedback           reviewer confirmations and corrections feed calibration
```

All callouts happen before any record is written, so a decision never fails with "uncommitted work pending".

## Setup, in order

You need Salesforce CLI v2 (`sf`) and `jq`. For a scratch org you also need a Dev Hub. A free Developer Edition org works once Dev Hub is turned on in Setup.

**1. Get an org**

```bash
sf org login web --alias devhub --set-default-dev-hub
```

```bash
./scripts/scratch.sh gavel-scratch
```

`scratch.sh` creates a 7-day scratch org with Knowledge and Platform Cache enabled.

**2. Deploy.** Deploy as source:

```bash
./scripts/deploy.sh --org gavel-scratch --packs service,sales-marketing,agentforce-gate --sample-data
```

This deploys core, flow, shadow, calibrate, admin and then the packs you chose. It assigns `Gavel_Admin`, `Gavel_Runtime`, `Gavel_Callout` and the pack permission sets to you, and loads sample data (200 Cases, 50 Leads). Use `--dry-run` to see the plan first. Once released, unlocked packages can be installed in the same order instead (`sf package install --package gavel-core@1.0.0 ...`).

After deploy, no flow is active and egress is off. In this state nothing leaves the org, and every run is recorded as `SKIP egress_disabled`.

**3. Add the TypeSafe API key.** See [the next section](#the-typesafe-api-key).

**4. Assign permission sets** to the people and integration users who need them:

| Permission set | Who gets it |
|---|---|
| `Gavel_Admin` | Admins: console, modes, calibration, read the ledger |
| `Gavel_Runtime` | Anyone whose actions run decisions (Flow or Apex) |
| `Gavel_Callout` | The same users. Grants use of the TypeSafe key, and no record access |
| `Gavel_Reviewer` | People who work review items |
| `Gavel_Auditor` | Read-only access to the ledger, action logs, feedback and calibration |
| `Gavel_Service_Pack`, `Gavel_Sales_Marketing_Pack`, `Gavel_Agentforce_Gate` | Users running that pack's decisions |

**5. Review what leaves the org.** Read [docs/guides/data-leaving-your-org.md](docs/guides/data-leaving-your-org.md). It lists every field each decision sends and how it is redacted.

**6. Turn egress on.** Go to Setup → Custom Metadata Types → **Gavel Ops Config** → Manage Records → **Default** → Edit. Check **Egress Enabled** and save.

**7. Activate a flow**, for example **Case Created: Triage (Async)**. The flows that ship are **Case Created: Triage (Async)**, **Lead Created: Junk Check (Async)** and **Email Received: Reply Intent (Async)**. The Agentforce Gate also ships **Case/Lead Created: Intake Screening (Async)** and **Gavel Guarded Action**.

**8. Schedule the background jobs.** Run this once as anonymous Apex:

```apex
System.schedule('Gavel pending sweeper', '0 5 * * * ?', new Gavel_PendingSweeper());     // reruns stuck PENDING decisions
System.schedule('Gavel baseline capture', '0 20 * * * ?', new Gavel_BaselineCapture());  // records what your old process did
System.schedule('Gavel ledger retention', '0 0 3 * * ?', new Gavel_LedgerRetention());   // purges after Retention_Days__c, keeps the chain anchor
for (Integer m : new List<Integer>{ 0, 15, 30, 45 })
    System.schedule('Gavel alerts :' + m, '0 ' + m + ' * * * ?', new Gavel_AlertMonitor()); // error and escalate rate alerts
```

**9. Run in Shadow, then promote.** Let decisions run in Shadow, map your baseline, run calibration, then promote to Live. See [docs/guides/shadow-to-live.md](docs/guides/shadow-to-live.md).

## The TypeSafe API key

**Get it:** sign in at [console.typesafe.ai/keys](https://console.typesafe.ai/keys) and create a key.

**Where it lives:** in one place only, the External Credential in your org. Gavel's code never reads it, never sets the header itself and never logs it. Never put the key in source, custom metadata or a custom setting.

| Metadata | Name | Role |
|---|---|---|
| Named Credential | `Gavel_TypeSafe` | URL `https://api.typesafe.ai`. **Allow formulas in HTTP header** must stay on, or the key isn't sent and TypeSafe returns 403 |
| External Credential | `Gavel_TypeSafe_Auth` | Custom auth. Sends `Authorization: Bearer {!$Credential.Gavel_TypeSafe_Auth.apiKey}` |
| Principal | `Gavel_TypeSafe_Principal` | Holds the key in an authentication parameter named `apiKey` |
| Permission set | `Gavel_Callout` | Grants users access to that principal |

**Set it**
1. Setup → Named Credentials → **External Credentials** tab → **Gavel TypeSafe Auth**.
2. Under **Principals**, find `Gavel_TypeSafe_Principal`, then choose **Edit** from its row menu.
3. Under **Authentication Parameters**, add a parameter named exactly `apiKey`. Paste the key as its value, then save.
4. Make sure the users who run decisions have `Gavel_Callout`.

**Rotate it:** edit the same `apiKey` parameter and paste the new key. Nothing needs to be redeployed.

**Check it:** with egress on, run the live contract test. It makes one real call to TypeSafe and prints the answers:

```bash
GAVEL_LIVE=1 GAVEL_ORG=gavel-scratch ./scripts/live-contract-test.sh
```

Expected output is `live contract holds`, followed by the model and the answers. If it fails, here's what each error means:
- **403 "Must supply an API key":** the Named Credential's header formula setting is off.
- **401:** the key is wrong or revoked.
- **422:** the request shape changed. See [contracts/provider-contract.md](docs/spec/active/2026-10-01-gavel-v1/contracts/provider-contract.md).

**Without a key:** set a decision's `Provider_Config__c` to `Mock`. The Mock provider answers from the fixtures in the `Gavel_Mock_Fixtures*` static resources and makes no callout.

## Configuration reference

All configuration is Custom Metadata, so it deploys and versions like code. You can edit it in Setup → Custom Metadata Types.

### Gavel Ops Config (`Gavel_Ops_Config__mdt`, record `Default`): org-wide

| Field | Default | Meaning |
|---|---|---|
| `Egress_Enabled__c` | false | Kill switch. When off, nothing leaves the org and every run is SKIP `egress_disabled` |
| `Store_State__c` | false | Also store the redacted state JSON on the ledger row. When off, only the hash and a redaction summary are kept |
| `Breaker_Errors__c` | 20 | Provider errors that open the circuit breaker |
| `Breaker_Cooldown_Min__c` | 10 | Minutes the breaker stays open before a half-open trial call |
| `Cache_TTL_Min__c` | 60 | Minutes an identical judgment (same definition and state hash) is served from cache |
| `Batch_Size__c` | 20 | Records per async or batch chunk; keeps each chunk under the callout limit |
| `Retention_Days__c` | 365 | Ledger rows older than this are purged by `Gavel_LedgerRetention`, which leaves a chain anchor |
| `Error_Alert_Pct__c` | 5 | Alert when the error rate goes above this over 15 minutes |
| `Escalate_Alert_Pct__c` | 20 | Alert when the ESCALATE rate goes above this over 1 hour |
| `Feedback_Window_Hours__c` | 72 | How long after a decision a human edit counts as feedback |
| `Baseline_Delay_Hours__c` | 24 | Wait before capturing what the old process decided |
| `Min_Sample__c` | 200 | Minimum labeled sample before calibration or promotion |
| `Target_Precision__c` | 0.95 | Precision the threshold recommendations aim for |
| `Calibration_Max_Age_Days__c` | 14 | A calibration report older than this can't be used to promote |
| `Integration_Users__c` | empty | Comma-separated usernames whose edits are not treated as human feedback |

### Gavel Provider Config (`Gavel_Provider_Config__mdt`)

| Record | Provider class | Model | Named Credential | Path | Timeout |
|---|---|---|---|---|---|
| `TypeSafe_Default` | `Gavel_TypeSafeProvider` | `jev-1.13.0` | `Gavel_TypeSafe` | `/v1/systemone` | 10000 ms |
| `Mock` | `Gavel_MockProvider` | `mock-1.0.0` | none | none | 10000 ms |

Live decisions must use a pinned model ID such as `jev-1.13.0`. Aliases like `jev-latest` are refused when a decision is Live.

### A decision definition

A decision is one `Gavel_Decision__mdt` record plus child records:

| Type | Holds |
|---|---|
| `Gavel_Decision__mdt` | Target object, `Mode__c` (Draft, Shadow, Live or Retired), `Auto_Apply__c`, `Provider_Config__c`, `Daily_Budget_Calls__c`, `Timeout_Ms__c`, `Review_Queue__c`, `Version__c` and `Definition_Hash__c` |
| `Gavel_State_Field__mdt` | The allowlist: field path, state key, max characters, redaction profile, required |
| `Gavel_Question__mdt` | Key, type (choice, score or noul), prompt, instructions, required for action |
| `Gavel_Option__mdt` | Choice options (key, label, description, escape option) or score levels (0 to n) |
| `Gavel_Policy__mdt` | Per question: `Auto_Accept__c`, `Review_At__c`, `Min_Margin__c`, Noul direction |
| `Gavel_Action_Map__mdt` | What an AUTO answer does on Live: set a field, assign a queue, and so on |
| `Gavel_Baseline_Map__mdt` | How the old process's field value maps to an option, for Shadow comparison |

When you change a definition, bump `Version__c`. Then regenerate the hash and lock file:

```bash
npm run hash:write
```

CI fails if a definition changes without a version bump.

**Modes:**
- **Draft:** not run.
- **Shadow:** judged and ledgered, but no record changes.
- **Live:** AUTO outcomes apply their actions when `Auto_Apply__c` is on; otherwise they create review items.
- **Retired:** not run, history kept.

## Using Gavel from Flow, Apex and Agentforce

**Flow actions (category "Gavel")**

| Action | Use |
|---|---|
| Gavel: Run Decision | Runs now and returns Outcome, Reason, Ledger Id, Top Choice, Top Confidence and Answers JSON. Makes a callout, so use it in an async path or a screen flow |
| Gavel: Run Decision (Async) | Queues the run and returns the PENDING ledger Id. Use it in record-triggered flows |
| Gavel: Apply Outcome | Applies the action map for an AUTO outcome on a Live definition |
| Gavel: Screen Intake / Screen Input / Check Stage Evidence | Pack-specific actions |

**Apex**

```apex
Gavel_Runtime.RunResult r = Gavel.run(caseId, 'Gavel_Case_Triage');            // sync
Id ledgerId              = Gavel.runAsync(caseId, 'Gavel_Case_Triage');         // async
List<Gavel_Runtime.ApplyResult> a = Gavel.applyOutcome(new List<Id>{ ledgerId });
Gavel_Runtime.RunResult t = Gavel.runWithInputs('Gavel_Input_Screen',
    new Map<String, Object>{ 'text' => body }, relatedId);                       // no record, just inputs
```

Gavel calls never throw. Failures come back as an outcome (ERROR or SKIP) with a reason, and they are ledgered too.

**Agentforce:** the Agentforce Gate's Apex invocables are the agent actions. Register them on your agent; see [docs/packs/agentforce-gate.md](docs/packs/agentforce-gate.md). Agent action metadata (`GenAiFunction`) isn't shipped because it needs an Agentforce-enabled org.

## Packages

| Package | What it gives you | Depends on |
|---|---|---|
| `gavel-core` | Provider interface, TypeSafe and Mock providers, state builder, policy engine, ledger, budgets, breaker, cache | none |
| `gavel-flow` | Flow actions, queueable runner, pending sweeper, template flows, `Gavel` Apex facade | core |
| `gavel-shadow` | Shadow mode, baseline capture, disagreement report, promotion gate | core, flow |
| `gavel-calibrate` | Feedback capture, reliability tables, threshold recommendations | core, shadow |
| `gavel-admin` | Gavel app, Decision Console, ledger related list, calibration dashboard, permission sets | all above |
| `gavel-pack-agentforce-gate` | Input screening, action risk, guarded action wrapper, intake screening | core, flow |
| `gavel-pack-service` | Case triage, urgency, KB coverage and gaps, closure check, reply check | core, flow, shadow |
| `gavel-pack-sales-marketing` | Lead quality, reply intent, hidden opt-out, persona, stage evidence | core, flow, shadow, calibrate |

No namespace; everything is prefixed `Gavel_`.

## Development and tests

```bash
npm install
npm run test:unit               # Jest for the admin LWC
npm run hash:check              # definition hashes and lock file, as CI runs it
```

```bash
for f in docs/spec/active/2026-10-01-gavel-v1/evals/tasks/*.sh docs/spec/active/2026-10-01-gavel-v1/evals/acceptance/*.sh; do GAVEL_ORG=gavel-scratch bash "$f" >/dev/null 2>&1; echo "$f exit=$?"; done
```

- Each plan task has an eval at `docs/spec/active/2026-10-01-gavel-v1/evals/tasks/T{N}.sh`, and each feature has one under `evals/acceptance/F{N}.sh`. T6.3 is the release gate. It exits 3 until a maintainer runs it with a live key.
- Apex tests use the Mock provider only. Only `scripts/live-contract-test.sh` calls the real API, and only when you set `GAVEL_LIVE=1`.
- Rules for contributors and coding agents: [CLAUDE.md](CLAUDE.md) and [AGENTS.md](AGENTS.md). Security: [SECURITY.md](SECURITY.md).
- If your machine can't reach the macOS Keychain (some sandboxed shells), prefix `sf` commands with `SF_USE_GENERIC_UNIX_KEYCHAIN=true`.

## Principles

- The model never owns the action. Policy in Salesforce does.
- Fail closed. Errors go to people, never to automation.
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
