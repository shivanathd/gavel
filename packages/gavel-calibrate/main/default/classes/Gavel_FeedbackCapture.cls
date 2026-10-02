/**
 * Turns human changes into calibration labels (F8).
 *  - Overrides (CAL-001.1): a person changes a field that a definition sets (action map) or compares
 *    against (baseline map) within Feedback_Window_Hours__c (default 72) of an AUTO or REVIEW entry.
 *  - Review resolutions (CAL-001.2): Confirmed / Corrected on Gavel_Review__c.
 * Gavel's own actions, automated processes, async jobs and configured integration users are not human
 * feedback (CAL-001.3). Nothing here is ever sent to the provider.
 */
public without sharing class Gavel_FeedbackCapture {
    private static final Set<String> FEEDBACK_OUTCOMES = new Set<String>{ 'AUTO', 'REVIEW' };

    private class Watch {
        public String definition;
        public String questionKey;
        public String field;
        /** action value (lowercase) -> answer value, for reverse mapping of overrides */
        public Map<String, String> answerByActionValue = new Map<String, String>();
    }

    /** True when the current change cannot be attributed to a person. */
    public static Boolean isAutomated() {
        if (Gavel_ActionExecutor.applying) {
            return true;
        }
        if (System.isBatch() || System.isFuture() || System.isQueueable() || System.isScheduled()) {
            return true;
        }
        if (UserInfo.getUserType() == 'AutomatedProcess') {
            return true;
        }
        return Gavel_Config.ops().integrationUsers.contains(UserInfo.getUserName().toLowerCase()) ||
            Gavel_Config.ops().integrationUsers.contains(String.valueOf(UserInfo.getUserId()).toLowerCase());
    }

    public static void onRecordUpdate(List<SObject> newRows, Map<Id, SObject> oldMap) {
        if (newRows == null || newRows.isEmpty() || isAutomated()) {
            return;
        }
        try {
            capture(newRows, oldMap);
        } catch (Exception e) {
            // Feedback is best-effort and must never block a user's save.
            Gavel_Alerts.raise('feedback_capture_failed', Gavel_Alerts.WARNING, null, 'Feedback capture failed: ' + e.getTypeName());
            Gavel_Alerts.flush();
        }
    }

    private static void capture(List<SObject> newRows, Map<Id, SObject> oldMap) {
        String objectName = newRows[0].getSObjectType().getDescribe().getName();
        Map<String, Schema.SObjectField> fieldMap = newRows[0].getSObjectType().getDescribe().fields.getMap();
        List<Watch> watches = new List<Watch>();
        for (Gavel_Definition def : Gavel_DefinitionRepo.forObject(objectName)) {
            Map<String, Watch> byKey = new Map<String, Watch>();
            for (Gavel_Definition.ActionMap a : def.actionMaps) {
                String field = a.actionType == 'assign_queue' ? 'OwnerId' : (a.actionType == 'set_field' ? fieldOf(a.actionTarget) : null);
                if (field == null || a.actionTarget != null && a.actionTarget.startsWith('$Who.')) {
                    continue;
                }
                Watch w = watchFor(byKey, def.apiName, a.questionKey, field);
                if (a.actionValue != null) {
                    w.answerByActionValue.put(a.actionValue.trim().toLowerCase(), a.answerValue);
                }
            }
            for (Gavel_BaselineMapRepo.Entry e : Gavel_BaselineMapRepo.forDefinition(def.apiName)) {
                watchFor(byKey, def.apiName, e.questionKey, e.fieldName());
            }
            for (Watch w : byKey.values()) {
                if (fieldMap.containsKey(w.field.toLowerCase())) {
                    watches.add(w);
                }
            }
        }
        if (watches.isEmpty()) {
            return;
        }

        Map<Id, List<Watch>> changed = new Map<Id, List<Watch>>();
        Set<String> defs = new Set<String>();
        for (SObject r : newRows) {
            SObject old = oldMap.get(r.Id);
            for (Watch w : watches) {
                if (r.get(w.field) != old.get(w.field)) {
                    if (!changed.containsKey(r.Id)) {
                        changed.put(r.Id, new List<Watch>());
                    }
                    changed.get(r.Id).add(w);
                    defs.add(w.definition);
                }
            }
        }
        if (changed.isEmpty()) {
            return;
        }
        Set<String> recordIds = new Set<String>();
        for (Id i : changed.keySet()) {
            recordIds.add(String.valueOf(i));
        }
        Datetime since = System.now().addHours(-Gavel_Config.ops().feedbackWindowHours);
        Map<String, Gavel_Decision_Log__c> latest = new Map<String, Gavel_Decision_Log__c>();
        for (Gavel_Decision_Log__c e : [
            SELECT Id, Record_Id__c, Definition__c, Version__c, Outcome__c, Answers_JSON__c, Answers_Truncated__c
            FROM Gavel_Decision_Log__c
            WHERE Record_Id__c IN :recordIds AND Definition__c IN :defs AND Outcome__c IN :FEEDBACK_OUTCOMES AND Run_At__c >= :since
            ORDER BY Run_At__c DESC, Chain_Seq__c DESC
        ]) {
            String k = e.Record_Id__c + '|' + e.Definition__c;
            if (!latest.containsKey(k)) {
                latest.put(k, e);
            }
        }
        List<Gavel_Feedback__c> rows = new List<Gavel_Feedback__c>();
        for (SObject r : newRows) {
            if (!changed.containsKey(r.Id)) {
                continue;
            }
            for (Watch w : changed.get(r.Id)) {
                Gavel_Decision_Log__c e = latest.get(String.valueOf(r.Id) + '|' + w.definition);
                if (e == null) {
                    continue;
                }
                Map<String, Object> qo = questionOutcome(e, w.questionKey);
                String gavelValue = qo.get('answer') == null ? null : String.valueOf(qo.get('answer'));
                Object raw = r.get(w.field);
                String human = raw == null ? null : String.valueOf(raw);
                if (String.isBlank(human)) {
                    continue; // blank human value: no feedback (null contract)
                }
                String mapped = Gavel_BaselineMapRepo.mapValue(w.definition, w.questionKey, human);
                if (mapped == null) {
                    mapped = w.answerByActionValue.get(human.trim().toLowerCase());
                }
                rows.add(new Gavel_Feedback__c(
                    Decision_Log__c = e.Id,
                    Type__c = 'override',
                    Definition__c = e.Definition__c,
                    Definition_Version__c = e.Version__c,
                    Question_Key__c = w.questionKey,
                    Field__c = (objectName + '.' + w.field).abbreviate(120),
                    Gavel_Value__c = gavelValue == null ? null : gavelValue.abbreviate(255),
                    Human_Value__c = human.abbreviate(255),
                    Mapped_Option__c = mapped,
                    Unmapped__c = mapped == null,
                    Correct__c = mapped != null && mapped.equals(gavelValue),
                    Calibration_Value__c = toDecimal(qo.get('calibrationValue')),
                    User__c = UserInfo.getUserId()
                ));
            }
        }
        if (!rows.isEmpty()) {
            insert rows;
        }
    }

    /** Review resolutions become confirmed / corrected feedback. */
    public static void onReviewUpdate(List<Gavel_Review__c> newRows, Map<Id, Gavel_Review__c> oldMap) {
        if (newRows == null || isAutomated()) {
            return;
        }
        List<Gavel_Review__c> resolved = new List<Gavel_Review__c>();
        Set<Id> logIds = new Set<Id>();
        for (Gavel_Review__c r : newRows) {
            Gavel_Review__c old = oldMap.get(r.Id);
            if ((r.Status__c == 'Confirmed' || r.Status__c == 'Corrected') && old.Status__c != r.Status__c && r.Decision_Log__c != null) {
                resolved.add(r);
                logIds.add(r.Decision_Log__c);
            }
        }
        if (resolved.isEmpty()) {
            return;
        }
        Map<Id, Gavel_Decision_Log__c> logs = new Map<Id, Gavel_Decision_Log__c>([
            SELECT Id, Definition__c, Version__c, Answers_JSON__c, Answers_Truncated__c FROM Gavel_Decision_Log__c WHERE Id IN :logIds
        ]);
        List<Gavel_Feedback__c> rows = new List<Gavel_Feedback__c>();
        for (Gavel_Review__c r : resolved) {
            Gavel_Decision_Log__c e = logs.get(r.Decision_Log__c);
            if (e == null) {
                continue;
            }
            Map<String, Object> qo = questionOutcome(e, r.Question_Key__c);
            Boolean confirmed = r.Status__c == 'Confirmed';
            String human = confirmed ? r.Gavel_Value__c : r.Resolution_Value__c;
            if (String.isBlank(human)) {
                continue;
            }
            String mapped = optionKey(e.Definition__c, r.Question_Key__c, human);
            rows.add(new Gavel_Feedback__c(
                Decision_Log__c = e.Id,
                Review__c = r.Id,
                Type__c = confirmed ? 'confirmed' : 'corrected',
                Definition__c = e.Definition__c,
                Definition_Version__c = e.Version__c,
                Question_Key__c = r.Question_Key__c,
                Gavel_Value__c = r.Gavel_Value__c,
                Human_Value__c = human.abbreviate(255),
                Mapped_Option__c = mapped,
                Unmapped__c = mapped == null,
                Correct__c = mapped != null && mapped.equals(r.Gavel_Value__c),
                Calibration_Value__c = toDecimal(qo.get('calibrationValue')),
                User__c = UserInfo.getUserId()
            ));
        }
        if (!rows.isEmpty()) {
            insert rows;
        }
    }

    /** A review resolution is an option key, a noul 'true'/'false', or a baseline value. */
    private static String optionKey(String definition, String questionKey, String value) {
        Gavel_Definition def = Gavel_DefinitionRepo.get(definition);
        Gavel_Question q = def == null ? null : def.question(questionKey);
        if (q != null) {
            if (q.isNoul() && (value == 'true' || value == 'false')) {
                return value.toLowerCase();
            }
            if (q.findOption(value.trim()) != null) {
                return value.trim();
            }
        }
        return Gavel_BaselineMapRepo.mapValue(definition, questionKey, value);
    }

    private static Watch watchFor(Map<String, Watch> byKey, String definition, String questionKey, String field) {
        String k = questionKey + '|' + field.toLowerCase();
        if (!byKey.containsKey(k)) {
            Watch w = new Watch();
            w.definition = definition;
            w.questionKey = questionKey;
            w.field = field;
            byKey.put(k, w);
        }
        return byKey.get(k);
    }

    private static String fieldOf(String target) {
        if (String.isBlank(target)) {
            return null;
        }
        return target.contains('.') ? target.substringAfterLast('.') : target;
    }

    private static Map<String, Object> questionOutcome(Gavel_Decision_Log__c e, String questionKey) {
        if (String.isBlank(e.Answers_JSON__c) || e.Answers_Truncated__c == true || questionKey == null) {
            return new Map<String, Object>();
        }
        try {
            Map<String, Object> doc = (Map<String, Object>) JSON.deserializeUntyped(e.Answers_JSON__c);
            Map<String, Object> outcomes = (Map<String, Object>) doc.get('outcomes');
            Object q = outcomes == null ? null : outcomes.get(questionKey);
            return q instanceof Map<String, Object> ? (Map<String, Object>) q : new Map<String, Object>();
        } catch (Exception ex) {
            return new Map<String, Object>();
        }
    }

    private static Decimal toDecimal(Object v) {
        if (v == null) {
            return null;
        }
        return (v instanceof Decimal ? (Decimal) v : Decimal.valueOf(String.valueOf(v))).setScale(4);
    }
}
