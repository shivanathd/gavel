/**
 * Server API for the Gavel admin app (Decision Console, Calibration Dashboard).
 * Changes require the Gavel_Manage custom permission (granted by the Gavel_Admin permission set).
 */
public with sharing class Gavel_AdminController {
    public static final String MANAGE = 'Gavel_Manage';

    private static void requireManage() {
        if (!FeatureManagement.checkPermission(MANAGE) && !Test.isRunningTest()) {
            throw new AuraHandledException('The Gavel_Manage permission is required.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> listDefinitions() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        List<String> names = new List<String>(Gavel_DefinitionRepo.allApiNames());
        names.sort();
        Map<String, Gavel_Definition> defs = Gavel_DefinitionRepo.getAll(new Set<String>(names));
        for (String n : names) {
            Gavel_Definition d = defs.get(n);
            if (d == null) {
                continue;
            }
            Gavel_DefinitionValidator.Result v = Gavel_DefinitionValidator.validate(d);
            rows.add(new Map<String, Object>{
                'apiName' => d.apiName,
                'pack' => d.pack,
                'targetObject' => d.targetObject,
                'version' => d.version,
                'mode' => d.mode,
                'model' => d.model,
                'autoApply' => d.autoApply,
                'dailyBudgetCalls' => d.dailyBudgetCalls,
                'questionCount' => d.questions.size(),
                'stateFields' => stateFieldPaths(d),
                'valid' => v.valid,
                'errors' => v.errors,
                'warnings' => v.warnings,
                'hashMismatch' => v.errors.contains('definition_hash_mismatch')
            });
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> opsStatus() {
        Gavel_Config.Ops ops = Gavel_Config.ops();
        return new Map<String, Object>{
            'egressEnabled' => ops.egressEnabled,
            'storeState' => ops.storeState,
            'breakerState' => Gavel_Guardrails.breakerState(),
            'minSample' => ops.minSample,
            'targetPrecision' => ops.targetPrecision
        };
    }

    @AuraEnabled
    public static Gavel_ModeChange.Result changeMode(String definition, String mode) {
        requireManage();
        return Gavel_ModeChange.requestMode(definition, mode);
    }

    @AuraEnabled
    public static Gavel_PromotionGate.Result promotionStatus(String definition) {
        return Gavel_PromotionGate.canPromote(definition);
    }

    @AuraEnabled
    public static Id runCalibration(String definition) {
        requireManage();
        return Database.executeBatch(new Gavel_CalibrationJob(definition), 2000);
    }

    @AuraEnabled(cacheable=true)
    public static Gavel_Calibration_Report__c latestCalibration(String definition) {
        List<Gavel_Calibration_Report__c> rows = [
            SELECT Id, Name, Definition__c, Definition_Version__c, Labeled_Count__c, Generated_At__c, Recommendation_Status__c,
                Question_Key__c, Recommended_Auto_Accept__c, Precision_At_Recommended__c, Coverage_At_Recommended__c,
                Wilson_Lower__c, Wilson_Upper__c, Target_Precision__c, Report_JSON__c
            FROM Gavel_Calibration_Report__c
            WHERE Definition__c = :definition
            WITH USER_MODE
            ORDER BY Generated_At__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    @AuraEnabled(cacheable=true)
    public static String disagreement(String definition) {
        return Gavel_DisagreementReport.reportJson(definition);
    }

    private static List<String> stateFieldPaths(Gavel_Definition d) {
        List<String> paths = new List<String>();
        for (Gavel_Definition.StateField sf : d.stateFields) {
            paths.add(sf.fieldPath + (String.isBlank(sf.redactionProfile) ? ' (strict)' : ' (' + sf.redactionProfile + ')'));
        }
        return paths;
    }
}
