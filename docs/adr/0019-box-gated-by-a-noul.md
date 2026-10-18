# 0019. A Box location is kept when its Noul says the thing is there

- Status: Accepted
- Date: 2026-10-18
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-019)

## Context

A Jev 1.14 Box answer is always a box, even when the thing it locates is not in the image. Gavel 1.1.1 kept a
location only when the box's own confidence cleared `Review_At__c` (0.5 in the shipped photo decisions), and recorded
`box_not_found` otherwise.

A live run on 49 labelled photos (22 real Wikimedia Commons photos, 21 `gpt-image-2.5` images, through released
1.2.0 against `jev-1.14.0`) showed that box confidence is a poor signal for presence:

- Correct boxes scored low: the damage on three real cracked phones (0.31 to 0.49) and the totals on two clearly
  legible receipts (0.20 and 0.44). Gavel discarded all five.
- Ghost boxes, on intact mugs, empty doorways and a handwritten note, scored 0.03 to 0.18.
- A box on a torn receipt with no total sat on a line item at 0.44, close to the correct ones.
- The Noul asked next to each box ("damage visible", "parcel visible", "total visible") was right on all 26 of these
  images, at 0.90 or more when present and 0.23 or less when absent.

Keeping a location when its Noul says yes handled 26 of 26 boxes correctly; box confidence alone handled 21 of 26.

## Decision

`Gavel_Question__mdt.Box_Gate__c` names the Noul in the same definition that says whether the thing is there. On a
gated Box:

- gate probability below 0.5, or no valid gate answer: no location, `ESCALATE box_not_found`;
- gate probability 0.5 or more: the location is recorded; box confidence still bands the outcome, and below
  `Review_At__c` the outcome is `REVIEW box_low_confidence` instead of discarding the box.

An ungated Box keeps the 1.1.1 behaviour. Validation rejects a gate on a non-box (`box_gate_on_non_box`) and a gate
that is not a Noul in the definition (`box_gate_not_noul`). `Box_Gate__c` enters the definition hash only when set, so
definitions without a gate keep their hash. The three shipped boxes (Return Photo Check, Delivery Proof, Proof of
Purchase) are gated and move to version 2.

## Consequences

Reviewers see the location whenever Jev says the thing is there, including the low-confidence cases that were
correct. A Box still never drives an action (ADR 0008 is unchanged: boxes are not required for action). The gate
threshold is a fixed 0.5 ("Jev says yes"), not a policy value; if real-photo calibration shows a need, it can move to
the policy later.

## Alternatives

- Lower the box `Review_At__c` to about 0.2 (rejected: it would keep the line-item box on the torn receipt at 0.44,
  and it rests on a signal that is not calibrated for presence).
- Pair boxes with Nouls by naming convention, such as `damage_area` with `damage_visible` (rejected: implicit, and
  breaks on any other key).
