/**
 * Builds a Gavel_Calibration_Report__c for one definition version (CAL-001.4/.6). Labels come from human
 * feedback first and captured baselines second; unmapped feedback is excluded. The report recommends a
 * threshold; it never changes Gavel_Policy__mdt (CAL-001.5, ADR-012): an admin applies it through a deploy
 * that bumps the definition version.
 *   Database.executeBatch(new Gavel_CalibrationJob('Gavel_Case_Triage'), 2000);
 */
public with sharing class Gavel_CalibrationJob implements Database.Batchable<SObject>, Database.Stateful {
    private String definition;
    private Integer version;
    private Map<String, List<Gavel_CalibrationMath.Point>> points = new Map<String, List<Gavel_CalibrationMath.Point>>();
    private Set<Id> labeledEntries = new Set<Id>();
    public Id reportId;

    public Gavel_CalibrationJob(String definition) {
        this(definition, null);
    }

    public Gavel_CalibrationJob(String definition, Integer version) {
        this.definition = definition;
        Gavel_Definition def = Gavel_DefinitionRepo.get(definition);
        this.version = version != null ? version : (def == null ? null : def.version);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String d = definition;
        Integer v = version;
        return Database.getQueryLocator([
            SELECT Id, Answers_JSON__c, Answers_Truncated__c
            FROM Gavel_Decision_Log__c
            WHERE Definition__c = :d AND Version__c = :v AND Outcome__c IN ('AUTO', 'REVIEW', 'ESCALATE')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Gavel_Decision_Log__c> scope) {
        accumulate(scope);
    }

    public void finish(Database.BatchableContext bc) {
        writeReport();
    }

    /** Synchronous run for small volumes and tests. Returns the report id. */
    public Id runNow() {
        String d = definition;
        Integer v = version;
        accumulate([
            SELECT Id, Answers_JSON__c, Answers_Truncated__c
            FROM Gavel_Decision_Log__c
            WHERE Definition__c = :d AND Version__c = :v AND Outcome__c IN ('AUTO', 'REVIEW', 'ESCALATE')
            LIMIT 50000
        ]);
        return writeReport();
    }

    private void accumulate(List<Gavel_Decision_Log__c> entries) {
        Map<Id, Gavel_Decision_Log__c> byId = new Map<Id, Gavel_Decision_Log__c>(entries);
        Set<Id> ids = byId.keySet();
        // label per entry + question: feedback wins over baseline; latest feedback wins.
        Map<String, Gavel_CalibrationMath.Point> labels = new Map<String, Gavel_CalibrationMath.Point>();
        for (Gavel_Baseline__c b : [
            SELECT Decision_Log__c, Question_Key__c, Agrees__c, Calibration_Value__c
            FROM Gavel_Baseline__c
            WHERE Decision_Log__c IN :ids AND Status__c = 'captured'
        ]) {
            Decimal v = b.Calibration_Value__c != null ? b.Calibration_Value__c : valueFromLedger(byId.get(b.Decision_Log__c), b.Question_Key__c);
            if (v != null) {
                labels.put(b.Decision_Log__c + '|' + b.Question_Key__c, new Gavel_CalibrationMath.Point(v, b.Agrees__c == true));
            }
        }
        for (Gavel_Feedback__c f : [
            SELECT Decision_Log__c, Question_Key__c, Correct__c, Calibration_Value__c
            FROM Gavel_Feedback__c
            WHERE Decision_Log__c IN :ids AND Unmapped__c = false
            ORDER BY CreatedDate ASC
        ]) {
            Decimal v = f.Calibration_Value__c != null ? f.Calibration_Value__c : valueFromLedger(byId.get(f.Decision_Log__c), f.Question_Key__c);
            if (v != null) {
                labels.put(f.Decision_Log__c + '|' + f.Question_Key__c, new Gavel_CalibrationMath.Point(v, f.Correct__c == true));
            }
        }
        for (String k : labels.keySet()) {
            String q = k.substringAfter('|');
            if (!points.containsKey(q)) {
                points.put(q, new List<Gavel_CalibrationMath.Point>());
            }
            points.get(q).add(labels.get(k));
            labeledEntries.add(Id.valueOf(k.substringBefore('|')));
        }
    }

    private Id writeReport() {
        Decimal target = Gavel_Config.ops().targetPrecision;
        Gavel_Definition def = Gavel_DefinitionRepo.get(definition);
        List<Gavel_CalibrationMath.QuestionCalibration> results = new List<Gavel_CalibrationMath.QuestionCalibration>();
        List<String> keys = new List<String>(points.keySet());
        keys.sort();
        for (String q : keys) {
            results.add(Gavel_CalibrationMath.calibrate(q, points.get(q), target));
        }
        // Primary question: the first participating question that has labels.
        Gavel_CalibrationMath.QuestionCalibration primary = null;
        String status = results.isEmpty() ? 'insufficient_data' : 'recommended';
        if (def != null) {
            for (Gavel_Question q : def.participatingQuestions()) {
                for (Gavel_CalibrationMath.QuestionCalibration qc : results) {
                    if (qc.questionKey == q.key) {
                        if (primary == null) {
                            primary = qc;
                        }
                        if (qc.status != 'recommended') {
                            status = qc.status;
                        }
                    }
                }
            }
        }
        if (primary == null && !results.isEmpty()) {
            primary = results[0];
            status = primary.status;
        }
        Gavel_Calibration_Report__c r = new Gavel_Calibration_Report__c(
            Definition__c = definition,
            Definition_Version__c = version,
            Labeled_Count__c = labeledEntries.size(),
            Generated_At__c = System.now(),
            Recommendation_Status__c = status,
            Target_Precision__c = target,
            Question_Key__c = primary == null ? null : primary.questionKey,
            Recommended_Auto_Accept__c = primary == null ? null : primary.recommended,
            Precision_At_Recommended__c = primary == null ? null : primary.precision,
            Coverage_At_Recommended__c = primary == null ? null : primary.coverage,
            Wilson_Lower__c = primary == null || primary.wilson == null ? null : primary.wilson.lower,
            Wilson_Upper__c = primary == null || primary.wilson == null ? null : primary.wilson.upper,
            Report_JSON__c = JSON.serialize(new Map<String, Object>{
                'definition' => definition, 'version' => version, 'targetPrecision' => target,
                'labeled' => labeledEntries.size(), 'questions' => results,
                'note' => 'Recommendation only. Apply through a deploy that bumps Version__c.'
            }).left(131072)
        );
        insert r;
        reportId = r.Id;
        return r.Id;
    }

    private static Decimal valueFromLedger(Gavel_Decision_Log__c e, String questionKey) {
        if (e == null || String.isBlank(e.Answers_JSON__c) || e.Answers_Truncated__c == true) {
            return null;
        }
        try {
            Map<String, Object> doc = (Map<String, Object>) JSON.deserializeUntyped(e.Answers_JSON__c);
            Map<String, Object> q = (Map<String, Object>) ((Map<String, Object>) doc.get('outcomes')).get(questionKey);
            Object v = q == null ? null : q.get('calibrationValue');
            return v == null ? null : (v instanceof Decimal ? (Decimal) v : Decimal.valueOf(String.valueOf(v)));
        } catch (Exception ex) {
            return null;
        }
    }
}
