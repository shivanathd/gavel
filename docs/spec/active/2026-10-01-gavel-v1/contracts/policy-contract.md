# Contract: JudgmentResponse -> PolicyEngine -> Outcome

**Version:** 1.1.0 | **Owner:** gavel-core

| Input condition | Outcome | Reason |
|---|---|---|
| status != ok | ERROR | status value |
| confidence null (choice/score) | REVIEW | unknown_confidence |
| escape option wins | REVIEW | escape_selected |
| top >= auto_accept AND margin >= min_margin | AUTO | accepted |
| margin < min_margin | REVIEW | margin_below_min |
| review_at <= value < auto_accept | REVIEW | confidence_below_auto_accept |
| value < review_at | ESCALATE | confidence_below_review |
| box, no Box_Gate__c, confidence < review_at | ESCALATE, no location | box_not_found |
| box with Box_Gate__c, gate Noul probability < 0.5 or invalid | ESCALATE, no location | box_not_found |
| box with Box_Gate__c, gate >= 0.5, confidence < review_at | REVIEW, location kept | box_low_confidence |
| Mode = Shadow | outcome computed, action suppressed | action_suppressed_shadow |

Definition outcome = most conservative across required questions: ERROR > SKIP > ESCALATE > REVIEW > AUTO.
