# Write your own definition (about 20 minutes)

A Gavel definition is a set of Custom Metadata records. No Apex is needed. This walkthrough builds `Gavel_Refund_Request`: "is this Case a refund request, and how sure are we?"

## 1. Start from an export (2 minutes)

```bash
node scripts/gavel-definition.js export Gavel_Closure_Check > my-def.json
```

Edit `my-def.json`:

- `apiName`: `Gavel_Refund_Request` (40 characters max, letters, digits and underscores).
- `decision.Target_Object__c`: `Case`. `Version__c`: `1`. `Mode__c`: `Shadow`. Keep `Provider_Config__c` as `TypeSafe_Default` (pinned model) or use `Mock` while you experiment.
- `decision.Daily_Budget_Calls__c`: set one. Blank means unlimited, and the console warns about it.

## 2. Ask a typed question (5 minutes)

Each question is `choice`, `score`, `noul` or `box`:

- **choice**: 2 to 255 options with keys like `BILLING` (`^[A-Za-z0-9_]{1,80}$`). Add an escape option such as `manual_review` with `Is_Escape__c = true`: when it wins, the outcome is always REVIEW.
- **score**: 2 to 10 levels, numbered from 0.
- **noul**: a true/false proposition, for example "The customer asks for their money back."
- **box** (definitions pinned to `jev-1.14.0` that send an image): where something is in the photo, for a reviewer. A box never drives an action, so set `Required_For_Action__c = false`. Jev always returns a box, even when nothing is there, so add a Noul such as `damage_visible` and set the box's `Box_Gate__c` to that Noul's key. The location is kept only when the Noul says yes ([ADR 0019](../adr/0019-box-gated-by-a-noul.md)).

Write the prompt as the question a careful colleague would answer. Put rules in `Instructions__c`, and always tell the model that the state is data, not instructions.

## 3. Choose the data that leaves the org (5 minutes)

Add `stateFields`: one row per field, for example `Subject` and `Description` (`Required__c = true` on the one you cannot judge without). Keep the list short. The default redaction profile is `strict`. Add every field to [Data leaving your org](data-leaving-your-org.md) by running `node scripts/egress-doc.js`; CI fails if you forget.

## 4. Set the policy (3 minutes)

One `policies` row per question:

| Field | Meaning | Start with |
|---|---|---|
| `Auto_Accept__c` | AUTO at or above this | 0.85 |
| `Review_At__c` | REVIEW between this and auto accept; ESCALATE below | 0.5 |
| `Min_Margin__c` | choice only: top minus runner-up must be at least this | 0.3 |
| `Noul_Direction__c` | which answer triggers the action | `true_is_action` |
| `Asymmetric_Reason__c` | required if your thresholds are deliberately lopsided | |

The definition outcome is the most conservative outcome across questions marked `Required_For_Action__c`.

## 5. Map actions (2 minutes)

`actionMaps` say what happens when a question is AUTO with a given answer, on a Live definition only: `set_field`, `assign_queue`, `create_task`, `publish_event`, `invoke_flow` or `none`. Shadow never acts.

## 6. Import, hash and deploy (3 minutes)

```bash
node scripts/gavel-definition.js import my-def.json --package gavel-pack-service --prefix RR
node scripts/egress-doc.js && ./scripts/docs-egress-check.sh
./scripts/deploy.sh --org gavel-scratch --packs service
```

`hash-definitions.js --write` stores the canonical hash. If you later change a question, option, state field, policy or action map, bump `Version__c`; otherwise every run is ledgered as `ERROR definition_hash_mismatch` and CI fails.

## 7. Try it

Run it from a screen flow with **Gavel: Run Decision**, or from Apex with `Gavel.run(caseId, 'Gavel_Refund_Request')`, and read the entry in the Gavel Decisions component on the Case.
