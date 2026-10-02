/**
 * Shadow -> Live gate (SHAD-001.5, ADR-011, ADR-003). Promotion needs a calibration report for the current
 * version generated within Calibration_Max_Age_Days__c (default 14) with at least Min_Sample__c (default 200)
 * labeled entries, a recommendation that meets the target, and a pinned model.
 * Gavel_Calibration_Report__c lives in gavel-calibrate (which depends on this package), so it is read
 * dynamically; without it the gate stays closed.
 */
public with sharing class Gavel_PromotionGate {
    public class Result {
        @AuraEnabled public Boolean allowed = false;
        @AuraEnabled public String reason;
        @AuraEnabled public Id reportId;
        @AuraEnabled public Decimal labeledCount;
    }

    public static Result canPromote(String definition) {
        Result r = new Result();
        Gavel_Definition def = Gavel_DefinitionRepo.get(definition);
        if (def == null) {
            r.reason = 'definition_not_found';
            return r;
        }
        if (Gavel_DefinitionValidator.isModelAlias(def.model)) {
            r.reason = 'model_alias_not_allowed_live';
            return r;
        }
        Gavel_DefinitionValidator.Result v = Gavel_DefinitionValidator.validate(def);
        if (!v.valid) {
            r.reason = v.firstError();
            return r;
        }
        Gavel_Config.Ops ops = Gavel_Config.ops();
        SObject report = latestReport(def.apiName, def.version);
        Decimal labeled = report != null ? (Decimal) report.get('Labeled_Count__c') : countLabels(def.apiName, def.version);
        r.labeledCount = labeled == null ? 0 : labeled;
        if (r.labeledCount < ops.minSample) {
            r.reason = 'insufficient_calibration_sample';
            r.reportId = report == null ? null : report.Id;
            return r;
        }
        if (report == null) {
            r.reason = 'no_calibration_report';
            return r;
        }
        r.reportId = report.Id;
        Datetime generated = (Datetime) report.get('Generated_At__c');
        if (generated == null || generated < System.now().addDays(-ops.calibrationMaxAgeDays)) {
            r.reason = 'calibration_report_stale';
            return r;
        }
        if ((String) report.get('Recommendation_Status__c') != 'recommended') {
            r.reason = 'no_threshold_meets_target';
            return r;
        }
        r.allowed = true;
        r.reason = 'calibrated';
        return r;
    }

    /** Labeled entries available before any report exists: mapped baselines plus usable feedback. */
    public static Decimal countLabels(String definition, Integer version) {
        Set<Id> labeled = new Set<Id>();
        for (Gavel_Baseline__c b : [
            SELECT Decision_Log__c FROM Gavel_Baseline__c
            WHERE Definition__c = :definition AND Definition_Version__c = :version AND Status__c = 'captured'
            LIMIT 50000
        ]) {
            labeled.add(b.Decision_Log__c);
        }
        if (Schema.getGlobalDescribe().containsKey('gavel_feedback__c')) {
            String soql = 'SELECT Decision_Log__c FROM Gavel_Feedback__c WHERE Unmapped__c = false AND ' +
                'Decision_Log__r.Definition__c = :definition AND Decision_Log__r.Version__c = :version LIMIT 50000';
            for (SObject f : Database.queryWithBinds(soql, new Map<String, Object>{ 'definition' => definition, 'version' => version }, AccessLevel.SYSTEM_MODE)) {
                labeled.add((Id) f.get('Decision_Log__c'));
            }
        }
        return labeled.size();
    }

    private static SObject latestReport(String definition, Integer version) {
        if (!Schema.getGlobalDescribe().containsKey('gavel_calibration_report__c')) {
            return null;
        }
        List<SObject> rows = Database.queryWithBinds(
            'SELECT Id, Labeled_Count__c, Generated_At__c, Recommendation_Status__c FROM Gavel_Calibration_Report__c ' +
            'WHERE Definition__c = :definition AND Definition_Version__c = :version ORDER BY Generated_At__c DESC LIMIT 1',
            new Map<String, Object>{ 'definition' => definition, 'version' => version },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }
}
