/**
 * Captures what the current process decided (SHAD-001.3). Picks ledger entries older than
 * Baseline_Delay_Hours__c (default 24) that have no baseline yet, reads each mapped baseline field and
 * writes one Gavel_Baseline__c per mapped question. Schedule hourly:
 *   System.schedule('Gavel baseline capture', '0 20 * * * ?', new Gavel_BaselineCapture());
 */
public with sharing class Gavel_BaselineCapture implements Database.Batchable<SObject>, Schedulable {
    private static final Set<String> JUDGED = new Set<String>{ 'AUTO', 'REVIEW', 'ESCALATE' };
    private Integer delayHours;

    public Gavel_BaselineCapture() {
        this(null);
    }

    public Gavel_BaselineCapture(Integer delayHours) {
        this.delayHours = delayHours;
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new Gavel_BaselineCapture(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = cutoff();
        Set<String> defs = Gavel_BaselineMapRepo.all().keySet();
        return Database.getQueryLocator([
            SELECT Id, Record_Id__c, Object__c, Definition__c, Version__c, Outcome__c, Answers_JSON__c, Answers_Truncated__c
            FROM Gavel_Decision_Log__c
            WHERE Definition__c IN :defs AND Outcome__c IN :JUDGED AND Run_At__c <= :cutoff
                AND Id NOT IN (SELECT Decision_Log__c FROM Gavel_Baseline__c)
            ORDER BY Run_At__c
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Gavel_Decision_Log__c> scope) {
        capture(scope);
    }

    public void finish(Database.BatchableContext bc) {
        return;
    }

    private Datetime cutoff() {
        Integer hours = delayHours != null ? delayHours : Gavel_Config.ops().baselineDelayHours;
        return System.now().addHours(-hours);
    }

    /** Synchronous capture for a set of entries (also used by tests and the console). */
    public static List<Gavel_Baseline__c> capture(List<Gavel_Decision_Log__c> entries) {
        List<Gavel_Baseline__c> rows = new List<Gavel_Baseline__c>();
        // Group record ids by object and collect the fields to read.
        Map<String, Set<Id>> idsByObject = new Map<String, Set<Id>>();
        Map<String, Set<String>> fieldsByObject = new Map<String, Set<String>>();
        for (Gavel_Decision_Log__c e : entries) {
            Id rid = toId(e.Record_Id__c);
            if (rid == null) {
                continue;
            }
            String obj = rid.getSObjectType().getDescribe().getName();
            if (!idsByObject.containsKey(obj)) {
                idsByObject.put(obj, new Set<Id>());
                fieldsByObject.put(obj, new Set<String>());
            }
            idsByObject.get(obj).add(rid);
            fieldsByObject.get(obj).addAll(Gavel_BaselineMapRepo.fieldsByQuestion(e.Definition__c).values());
        }
        Map<Id, SObject> records = new Map<Id, SObject>();
        for (String obj : idsByObject.keySet()) {
            Map<String, Schema.SObjectField> known = Schema.getGlobalDescribe().get(obj.toLowerCase()).getDescribe().fields.getMap();
            List<String> fields = new List<String>{ 'Id' };
            for (String f : fieldsByObject.get(obj)) {
                if (f != null && known.containsKey(f.toLowerCase()) && !fields.contains(f)) {
                    fields.add(f);
                }
            }
            Set<Id> ids = idsByObject.get(obj);
            for (SObject r : Database.query('SELECT ' + String.join(fields, ', ') + ' FROM ' + obj + ' WHERE Id IN :ids')) {
                records.put(r.Id, r);
            }
        }
        // Fields Gavel itself set (Live actions) make the baseline circular.
        Set<String> gavelSet = new Set<String>();
        Set<String> recordIds = new Set<String>();
        for (Gavel_Decision_Log__c e : entries) {
            recordIds.add(e.Record_Id__c);
        }
        for (Gavel_Action_Log__c a : [
            SELECT Record_Id__c, Target__c FROM Gavel_Action_Log__c
            WHERE Record_Id__c IN :recordIds AND Status__c = 'applied' AND Action_Type__c IN ('set_field', 'assign_queue')
        ]) {
            String field = a.Target__c == null ? 'OwnerId' : (a.Target__c.contains('.') ? a.Target__c.substringAfterLast('.') : a.Target__c);
            gavelSet.add(a.Record_Id__c + '|' + field.toLowerCase());
        }

        for (Gavel_Decision_Log__c e : entries) {
            Map<String, Object> outcomes = outcomesOf(e);
            Map<String, String> fieldByQuestion = Gavel_BaselineMapRepo.fieldsByQuestion(e.Definition__c);
            for (String q : fieldByQuestion.keySet()) {
                Map<String, Object> qo = outcomes.get(q) instanceof Map<String, Object> ? (Map<String, Object>) outcomes.get(q) : new Map<String, Object>();
                Gavel_Baseline__c b = new Gavel_Baseline__c(
                    Decision_Log__c = e.Id,
                    Definition__c = e.Definition__c,
                    Definition_Version__c = e.Version__c,
                    Question_Key__c = q,
                    Gavel_Value__c = qo.get('answer') == null ? null : String.valueOf(qo.get('answer')).abbreviate(255),
                    Gavel_Outcome__c = (String) qo.get('outcome'),
                    Calibration_Value__c = toDecimal(qo.get('calibrationValue')),
                    Would_Auto__c = (String) qo.get('outcome') == 'AUTO',
                    Captured_At__c = System.now()
                );
                String field = fieldByQuestion.get(q);
                SObject rec = records.get(toId(e.Record_Id__c));
                Object raw = null;
                if (rec != null && field != null) {
                    try {
                        raw = rec.get(field);
                    } catch (Exception ex) {
                        raw = null;
                    }
                }
                String value = raw == null ? null : String.valueOf(raw);
                b.Baseline_Value__c = value == null ? null : value.abbreviate(255);
                if (field != null && gavelSet.contains(e.Record_Id__c + '|' + field.toLowerCase())) {
                    b.Status__c = 'circular';
                } else if (String.isBlank(value)) {
                    b.Status__c = 'baseline_missing';
                } else {
                    String mapped = Gavel_BaselineMapRepo.mapValue(e.Definition__c, q, value);
                    if (mapped == null) {
                        b.Status__c = 'baseline_unmapped';
                        b.Agrees__c = false;
                    } else {
                        b.Status__c = 'captured';
                        b.Mapped_Option__c = mapped;
                        b.Agrees__c = mapped.equals(b.Gavel_Value__c);
                    }
                }
                rows.add(b);
            }
        }
        if (!rows.isEmpty()) {
            insert rows;
        }
        return rows;
    }

    public static Map<String, Object> outcomesOf(Gavel_Decision_Log__c e) {
        if (String.isBlank(e.Answers_JSON__c) || e.Answers_Truncated__c == true) {
            return new Map<String, Object>();
        }
        try {
            Map<String, Object> doc = (Map<String, Object>) JSON.deserializeUntyped(e.Answers_JSON__c);
            Object o = doc.get('outcomes');
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
        } catch (Exception ex) {
            return new Map<String, Object>();
        }
    }

    private static Decimal toDecimal(Object v) {
        if (v == null) {
            return null;
        }
        Decimal d = v instanceof Decimal ? (Decimal) v : Decimal.valueOf(String.valueOf(v));
        return d.setScale(4);
    }

    private static Id toId(String value) {
        try {
            return String.isBlank(value) || value == 'none' ? null : Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }
}
