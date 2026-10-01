/**
 * Creates Gavel_Review__c work items for REVIEW/ESCALATE outcomes on Live definitions, and for AUTO outcomes
 * held by Live-Review (Auto_Apply__c off) (POL-001.9). System mode: a review must exist even when the
 * running user cannot create one. Owner = the definition's review queue, default Gavel_Review_Queue.
 */
public without sharing class Gavel_ReviewService {
    public static final String DEFAULT_QUEUE = 'Gavel_Review_Queue';

    public class Item {
        public Gavel_Definition def;
        public Gavel_Decision_Log__c entry;
        public Gavel_Outcome outcome;
    }

    /** Live only. REVIEW/ESCALATE, ERROR, provider-availability SKIPs (fail closed to a human) and Live-Review AUTO. */
    public static Boolean needsReview(Gavel_Definition def, Gavel_Outcome o) {
        if (def == null || o == null || !def.isLive()) {
            return false;
        }
        if (o.needsReview() || o.outcome == Gavel_Outcome.ERROR) {
            return true;
        }
        if (o.outcome == Gavel_Outcome.SKIP && (o.reason == Gavel_JudgmentResponse.CIRCUIT_OPEN || o.reason == Gavel_JudgmentResponse.BUDGET_EXCEEDED)) {
            return true;
        }
        return o.isAuto() && o.suppressReason == Gavel_PolicyEngine.SUPPRESS_AUTO_APPLY_OFF;
    }

    public static Map<Id, Gavel_Review__c> create(List<Item> items) {
        Map<Id, Gavel_Review__c> byEntry = new Map<Id, Gavel_Review__c>();
        if (items == null || items.isEmpty()) {
            return byEntry;
        }
        Set<String> queueNames = new Set<String>{ DEFAULT_QUEUE };
        for (Item i : items) {
            if (String.isNotBlank(i.def.reviewQueue)) {
                queueNames.add(i.def.reviewQueue);
            }
        }
        Map<String, Id> queues = new Map<String, Id>();
        for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue' AND DeveloperName IN :queueNames]) {
            queues.put(g.DeveloperName, g.Id);
        }
        List<Gavel_Review__c> rows = new List<Gavel_Review__c>();
        for (Item i : items) {
            if (i.entry.Id == null) {
                continue;
            }
            String q = String.isNotBlank(i.def.reviewQueue) && queues.containsKey(i.def.reviewQueue) ? i.def.reviewQueue : DEFAULT_QUEUE;
            Gavel_Outcome.QuestionResult deciding = i.outcome.decidingQuestion == null ? null : i.outcome.questions.get(i.outcome.decidingQuestion);
            Gavel_Review__c r = new Gavel_Review__c(
                Decision_Log__c = i.entry.Id,
                Definition__c = i.entry.Definition__c,
                Record_Id__c = i.entry.Record_Id__c,
                Outcome__c = i.outcome.outcome,
                Reason__c = (i.outcome.isAuto() ? i.outcome.suppressReason : i.outcome.reason),
                Question_Key__c = deciding == null ? null : deciding.key,
                Gavel_Value__c = deciding == null || deciding.answerValue == null ? null : deciding.answerValue.abbreviate(255),
                Status__c = 'Open',
                Case__c = i.entry.Case__c,
                Lead__c = i.entry.Lead__c,
                Contact__c = i.entry.Contact__c,
                Opportunity__c = i.entry.Opportunity__c
            );
            if (queues.containsKey(q)) {
                r.OwnerId = queues.get(q);
            }
            rows.add(r);
        }
        if (!rows.isEmpty()) {
            Database.insert(rows, false);
            for (Gavel_Review__c r : rows) {
                if (r.Id != null) {
                    byEntry.put(r.Decision_Log__c, r);
                }
            }
        }
        return byEntry;
    }
}
