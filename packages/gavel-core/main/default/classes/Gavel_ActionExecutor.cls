/**
 * Applies Gavel_Action_Map__mdt actions for AUTO outcomes on Live definitions only (FLOW-001.3, POL-001.7).
 * DML runs in user mode (least privilege, NIST AC-6). Every action is logged in Gavel_Action_Log__c.
 *
 * Action_Target__c:  "Field", "Object.Field" (the run's record) or "$Who.Field" (Lead/Contact linked to an
 *                    EmailMessage or Task). For assign_queue the value is a queue DeveloperName; for
 *                    invoke_flow the target is the flow API name; for publish_event the target is the event type.
 * Action_Value__c:   literal, or {answer} for the judged answer.
 * Opt-out style fields are monotonic: Gavel only ever sets them to true (SM-001.4).
 */
public with sharing class Gavel_ActionExecutor {
    public static final Set<String> MONOTONIC_FIELDS = new Set<String>{ 'hasoptedoutofemail', 'hasoptedoutoffax', 'donotcall' };
    public static final String APPLIED = 'applied';
    public static final String FAILED = 'failed';
    public static final String BLOCKED = 'blocked_monotonic_field';
    public static final String SKIPPED = 'skipped';

    /** True while Gavel's own DML runs, so feedback capture ignores it. */
    public static Boolean applying = false;

    public class Step {
        public Id recordId;
        public Gavel_Definition.ActionMap action;
        public String answerValue;
        public Integer runIndex;
    }

    public class RunActions {
        public List<Gavel_Action_Log__c> logs = new List<Gavel_Action_Log__c>();
        public Integer applied = 0;
        public Integer failed = 0;
        public List<String> summary = new List<String>();

        public String text() {
            if (logs.isEmpty()) {
                return 'none';
            }
            return String.join(summary, '; ').abbreviate(255);
        }
    }

    /** Steps for one AUTO outcome: action maps whose question was AUTO with a matching answer. */
    public static List<Step> plan(Gavel_Definition def, Id recordId, Gavel_Outcome outcome, Integer runIndex) {
        List<Step> steps = new List<Step>();
        if (outcome == null || !outcome.isAuto() || outcome.actionSuppressed) {
            return steps;
        }
        for (Gavel_Outcome.QuestionResult qr : outcome.questions.values()) {
            if (qr.outcome != Gavel_Outcome.AUTO || qr.answerValue == null) {
                continue;
            }
            for (Gavel_Definition.ActionMap a : def.actionsFor(qr.key, qr.answerValue)) {
                if (a.actionType == 'none') {
                    continue;
                }
                Step s = new Step();
                s.recordId = recordId;
                s.action = a;
                s.answerValue = qr.answerValue;
                s.runIndex = runIndex;
                steps.add(s);
            }
        }
        return steps;
    }

    /** Executes steps for many runs. Returns per-run results keyed by runIndex. Never throws. */
    public static Map<Integer, RunActions> execute(List<Step> steps) {
        Map<Integer, RunActions> results = new Map<Integer, RunActions>();
        if (steps == null || steps.isEmpty()) {
            return results;
        }
        Map<Id, Id> whoByRecord = resolveWho(steps);
        Map<String, Id> queues = resolveQueues(steps);
        Map<Id, SObject> updates = new Map<Id, SObject>();
        Map<Id, List<Gavel_Action_Log__c>> logsByUpdate = new Map<Id, List<Gavel_Action_Log__c>>();
        List<SObject> inserts = new List<SObject>();
        List<Gavel_Action_Log__c> insertLogs = new List<Gavel_Action_Log__c>();
        List<SObject> events = new List<SObject>();
        List<Gavel_Action_Log__c> eventLogs = new List<Gavel_Action_Log__c>();

        for (Step s : steps) {
            if (!results.containsKey(s.runIndex)) {
                results.put(s.runIndex, new RunActions());
            }
            RunActions ra = results.get(s.runIndex);
            Gavel_Action_Log__c log = new Gavel_Action_Log__c(
                Record_Id__c = s.recordId == null ? null : String.valueOf(s.recordId),
                Action_Type__c = s.action.actionType,
                Target__c = s.action.actionTarget,
                Value__c = value(s).abbreviate(255),
                Status__c = APPLIED
            );
            ra.logs.add(log);
            try {
                String kind = s.action.actionType;
                if (kind == 'set_field' || kind == 'assign_queue') {
                    Id target = s.recordId;
                    String fieldName;
                    Object fieldValue;
                    if (kind == 'assign_queue') {
                        fieldName = 'OwnerId';
                        fieldValue = queues.get(value(s));
                        if (fieldValue == null) {
                            fail(ra, log, 'queue_not_found');
                            continue;
                        }
                    } else {
                        String path = s.action.actionTarget == null ? '' : s.action.actionTarget.trim();
                        if (path.startsWith('$Who.')) {
                            target = whoByRecord.get(s.recordId);
                            path = path.substringAfter('$Who.');
                            if (target == null) {
                                fail(ra, log, 'who_not_found');
                                continue;
                            }
                        } else if (path.contains('.')) {
                            path = path.substringAfter('.');
                        }
                        fieldName = path;
                        Schema.SObjectField f = target.getSObjectType().getDescribe().fields.getMap().get(fieldName.toLowerCase());
                        if (f == null) {
                            fail(ra, log, 'bad_field');
                            continue;
                        }
                        fieldValue = convert(f.getDescribe(), value(s));
                        if (MONOTONIC_FIELDS.contains(fieldName.toLowerCase()) && !(fieldValue instanceof Boolean && (Boolean) fieldValue)) {
                            log.Status__c = BLOCKED;
                            log.Detail__c = 'Gavel only sets ' + fieldName + ' to true';
                            ra.summary.add(BLOCKED + ':' + fieldName);
                            continue;
                        }
                    }
                    SObject row = updates.containsKey(target) ? updates.get(target) : target.getSObjectType().newSObject(target);
                    row.put(fieldName, fieldValue);
                    updates.put(target, row);
                    if (!logsByUpdate.containsKey(target)) {
                        logsByUpdate.put(target, new List<Gavel_Action_Log__c>());
                    }
                    logsByUpdate.get(target).add(log);
                    ra.applied++;
                    ra.summary.add(kind + ':' + s.action.actionTarget + '=' + value(s));
                } else if (kind == 'create_task') {
                    Task t = new Task(Subject = value(s).abbreviate(255), Status = 'Not Started', Priority = 'Normal');
                    String prefix = String.valueOf(s.recordId).left(3);
                    if (prefix == '00Q' || prefix == '003') {
                        t.WhoId = s.recordId;
                    } else {
                        t.WhatId = s.recordId;
                    }
                    inserts.add(t);
                    insertLogs.add(log);
                    ra.applied++;
                    ra.summary.add('create_task');
                } else if (kind == 'publish_event') {
                    Schema.SObjectType et = Schema.getGlobalDescribe().get(s.action.actionTarget == null ? '' : s.action.actionTarget.toLowerCase());
                    if (et == null || !s.action.actionTarget.endsWith('__e')) {
                        fail(ra, log, 'bad_event_type');
                        continue;
                    }
                    SObject ev = et.newSObject();
                    Map<String, Schema.SObjectField> ef = et.getDescribe().fields.getMap();
                    if (ef.containsKey('message__c')) {
                        ev.put('Message__c', value(s).abbreviate(255));
                    }
                    if (ef.containsKey('record_id__c')) {
                        ev.put('Record_Id__c', String.valueOf(s.recordId));
                    }
                    events.add(ev);
                    eventLogs.add(log);
                    ra.applied++;
                    ra.summary.add('publish_event:' + s.action.actionTarget);
                } else if (kind == 'invoke_flow') {
                    applying = true;
                    try {
                        Flow.Interview.createInterview(s.action.actionTarget, new Map<String, Object>{
                            'recordId' => s.recordId, 'answer' => s.answerValue, 'value' => value(s)
                        }).start();
                        ra.applied++;
                        ra.summary.add('invoke_flow:' + s.action.actionTarget);
                    } finally {
                        applying = false;
                    }
                } else {
                    log.Status__c = SKIPPED;
                }
            } catch (Exception e) {
                fail(ra, log, 'exception:' + e.getTypeName());
            }
        }

        applying = true;
        try {
            if (!updates.isEmpty()) {
                List<SObject> rows = sortByType(updates.values());
                List<Database.SaveResult> res = Database.update(rows, false, AccessLevel.USER_MODE);
                for (Integer i = 0; i < res.size(); i++) {
                    if (!res[i].isSuccess()) {
                        for (Gavel_Action_Log__c l : logsByUpdate.get(rows[i].Id)) {
                            l.Status__c = FAILED;
                            l.Detail__c = firstError(res[i].getErrors());
                        }
                    }
                }
            }
            if (!inserts.isEmpty()) {
                List<Database.SaveResult> res = Database.insert(inserts, false, AccessLevel.USER_MODE);
                for (Integer i = 0; i < res.size(); i++) {
                    if (!res[i].isSuccess()) {
                        insertLogs[i].Status__c = FAILED;
                        insertLogs[i].Detail__c = firstError(res[i].getErrors());
                    }
                }
            }
            if (!events.isEmpty()) {
                List<Database.SaveResult> res = EventBus.publish(events);
                for (Integer i = 0; i < res.size(); i++) {
                    if (!res[i].isSuccess()) {
                        eventLogs[i].Status__c = FAILED;
                    }
                }
            }
        } catch (Exception e) {
            for (RunActions ra : results.values()) {
                for (Gavel_Action_Log__c l : ra.logs) {
                    if (l.Status__c == APPLIED) {
                        l.Status__c = FAILED;
                        l.Detail__c = 'exception:' + e.getTypeName();
                    }
                }
            }
        } finally {
            applying = false;
        }
        for (RunActions ra : results.values()) {
            ra.applied = 0;
            ra.failed = 0;
            for (Gavel_Action_Log__c l : ra.logs) {
                if (l.Status__c == APPLIED) {
                    ra.applied++;
                } else if (l.Status__c == FAILED) {
                    ra.failed++;
                }
            }
        }
        return results;
    }

    /** Writes action logs once ledger ids are known. */
    public static void writeLogs(List<Gavel_Action_Log__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }
        Gavel_Ledger.insertActionLogs(logs);
    }

    private static void fail(RunActions ra, Gavel_Action_Log__c log, String detail) {
        log.Status__c = FAILED;
        log.Detail__c = detail;
        ra.summary.add(FAILED + ':' + detail);
    }

    private static String value(Step s) {
        String v = s.action.actionValue == null ? '' : s.action.actionValue;
        return v.replace('{answer}', s.answerValue == null ? '' : s.answerValue);
    }

    private static Object convert(Schema.DescribeFieldResult f, String v) {
        Schema.DisplayType t = f.getType();
        if (t == Schema.DisplayType.BOOLEAN) {
            return v != null && v.trim().equalsIgnoreCase('true');
        }
        if (String.isBlank(v)) {
            return null;
        }
        if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.PERCENT) {
            return Decimal.valueOf(v.trim());
        }
        if (t == Schema.DisplayType.INTEGER) {
            return Integer.valueOf(v.trim());
        }
        if (t == Schema.DisplayType.DATE) {
            return Date.valueOf(v.trim());
        }
        return v;
    }

    private static List<SObject> sortByType(List<SObject> rows) {
        Map<String, List<SObject>> byType = new Map<String, List<SObject>>();
        for (SObject r : rows) {
            String k = String.valueOf(r.getSObjectType());
            if (!byType.containsKey(k)) {
                byType.put(k, new List<SObject>());
            }
            byType.get(k).add(r);
        }
        List<SObject> sorted = new List<SObject>();
        for (List<SObject> bucket : byType.values()) {
            sorted.addAll(bucket);
        }
        return sorted;
    }

    private static String firstError(List<Database.Error> errors) {
        if (errors == null || errors.isEmpty()) {
            return 'unknown';
        }
        return (String.valueOf(errors[0].getStatusCode()) + ': ' + errors[0].getMessage()).abbreviate(255);
    }

    private static Map<String, Id> resolveQueues(List<Step> steps) {
        Set<String> names = new Set<String>();
        for (Step s : steps) {
            if (s.action.actionType == 'assign_queue') {
                names.add(value(s));
            }
        }
        Map<String, Id> result = new Map<String, Id>();
        if (names.isEmpty()) {
            return result;
        }
        for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue' AND DeveloperName IN :names WITH SYSTEM_MODE]) {
            result.put(g.DeveloperName, g.Id);
        }
        return result;
    }

    /** Lead/Contact behind an EmailMessage (EmailMessageRelation, then Task.WhoId) or a Task. */
    @TestVisible
    private static Map<Id, Id> resolveWho(List<Step> steps) {
        Set<Id> emailIds = new Set<Id>();
        Set<Id> taskIds = new Set<Id>();
        Map<Id, Id> result = new Map<Id, Id>();
        for (Step s : steps) {
            if (s.action.actionTarget == null || !s.action.actionTarget.startsWith('$Who.') || s.recordId == null) {
                continue;
            }
            Schema.SObjectType t = s.recordId.getSObjectType();
            if (t == EmailMessage.SObjectType) {
                emailIds.add(s.recordId);
            } else if (t == Task.SObjectType) {
                taskIds.add(s.recordId);
            } else if (t == Lead.SObjectType || t == Contact.SObjectType) {
                result.put(s.recordId, s.recordId);
            }
        }
        if (!emailIds.isEmpty()) {
            for (EmailMessageRelation r : [
                SELECT EmailMessageId, RelationId, RelationType
                FROM EmailMessageRelation
                WHERE EmailMessageId IN :emailIds AND RelationId != NULL
                WITH SYSTEM_MODE ORDER BY RelationType
            ]) {
                Schema.SObjectType rt = r.RelationId.getSObjectType();
                Boolean person = rt == Lead.SObjectType || rt == Contact.SObjectType;
                if (person && (!result.containsKey(r.EmailMessageId) || r.RelationType == 'FromAddress')) {
                    result.put(r.EmailMessageId, r.RelationId);
                }
            }
            for (EmailMessage e : [SELECT Id, ActivityId, RelatedToId FROM EmailMessage WHERE Id IN :emailIds WITH SYSTEM_MODE]) {
                if (!result.containsKey(e.Id) && e.RelatedToId != null) {
                    Schema.SObjectType rt = e.RelatedToId.getSObjectType();
                    if (rt == Lead.SObjectType || rt == Contact.SObjectType) {
                        result.put(e.Id, e.RelatedToId);
                    }
                }
                if (!result.containsKey(e.Id) && e.ActivityId != null) {
                    taskIds.add(e.ActivityId);
                    result.put(e.Id, null);
                }
            }
        }
        if (!taskIds.isEmpty()) {
            Map<Id, Id> whoByTask = new Map<Id, Id>();
            for (Task t : [SELECT Id, WhoId FROM Task WHERE Id IN :taskIds WITH SYSTEM_MODE]) {
                whoByTask.put(t.Id, t.WhoId);
            }
            for (Id tid : taskIds) {
                if (whoByTask.containsKey(tid)) {
                    result.put(tid, whoByTask.get(tid));
                }
            }
            for (EmailMessage e : emailIds.isEmpty() ? new List<EmailMessage>() : [SELECT Id, ActivityId FROM EmailMessage WHERE Id IN :emailIds]) {
                if (result.get(e.Id) == null && e.ActivityId != null) {
                    result.put(e.Id, whoByTask.get(e.ActivityId));
                }
            }
        }
        return result;
    }
}
