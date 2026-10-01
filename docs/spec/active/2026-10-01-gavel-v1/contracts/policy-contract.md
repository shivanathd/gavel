# Contract: JudgmentResponse -> PolicyEngine -> Outcome

**Version:** 1.0.0 | **Owner:** gavel-core

| Input condition | Outcome | Reason |
|---|---|---|
| status != ok | ERROR | status value |
| confidence null (choice/score) | REVIEW | unknown_confidence |
| escape option wins | REVIEW | escape_selected |
| top >= auto_accept AND margin >= min_margin | AUTO | accepted |
| margin < min_margin | REVIEW | margin_below_min |
| review_at <= value < auto_accept | REVIEW | confidence_below_auto_accept |
| value < review_at | ESCALATE | confidence_below_review |
| Mode = Shadow | outcome computed, action suppressed | action_suppressed_shadow |

Definition outcome = most conservative across required questions: ERROR > SKIP > ESCALATE > REVIEW > AUTO.
