/**
 * Changes a definition's Mode__c through a Metadata API deploy (ADR-004). Promotion to Live is refused unless
 * Gavel_PromotionGate allows it (SHAD-001.5). Leaving Live (to Shadow, Draft or Retired) is always allowed.
 * Mode is not part of the definition hash, so a mode change needs no version bump; threshold changes do.
 */
public with sharing class Gavel_ModeChange {
    private static final Set<String> MODES = new Set<String>{ 'Draft', 'Shadow', 'Live', 'Retired' };

    public class Result {
        @AuraEnabled public Boolean accepted = false;
        @AuraEnabled public String reason;
        @AuraEnabled public String jobId;
        @AuraEnabled public Id calibrationReportId;
    }

    /** Deploys are not possible from Apex tests; tests inspect the captured container instead. */
    @TestVisible
    private static List<Metadata.DeployContainer> captured = new List<Metadata.DeployContainer>();

    @AuraEnabled
    public static Result requestMode(String definition, String newMode) {
        Result r = new Result();
        if (!MODES.contains(newMode)) {
            r.reason = 'invalid_mode';
            return r;
        }
        Gavel_Definition def = Gavel_DefinitionRepo.get(definition);
        if (def == null) {
            r.reason = 'definition_not_found';
            return r;
        }
        if (newMode == Gavel_Definition.MODE_LIVE && def.mode != Gavel_Definition.MODE_LIVE) {
            Gavel_PromotionGate.Result gate = Gavel_PromotionGate.canPromote(definition);
            r.calibrationReportId = gate.reportId;
            if (!gate.allowed) {
                r.reason = gate.reason;
                return r;
            }
        }
        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(record(def, newMode));
        if (Test.isRunningTest()) {
            captured.add(container);
            r.jobId = 'test';
        } else {
            r.jobId = Metadata.Operations.enqueueDeployment(container, null);
        }
        r.accepted = true;
        r.reason = 'deploy_enqueued';
        return r;
    }

    /** Full record copy with the new mode, so a partial deploy never blanks other fields. */
    @TestVisible
    private static Metadata.CustomMetadata record(Gavel_Definition def, String newMode) {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = 'Gavel_Decision.' + def.apiName;
        md.label = def.apiName.abbreviate(40);
        List<Gavel_Decision__mdt> rows = [
            SELECT MasterLabel, Target_Object__c, Version__c, Provider_Config__c, Description__c, Owner_Email__c,
                Daily_Budget_Calls__c, Definition_Hash__c, Pack__c, Review_Queue__c, Auto_Apply__c, Timeout_Ms__c
            FROM Gavel_Decision__mdt
            WHERE DeveloperName = :def.apiName
            WITH SYSTEM_MODE LIMIT 1
        ];
        if (!rows.isEmpty()) {
            md.label = rows[0].MasterLabel;
        }
        add(md, 'Target_Object__c', def.targetObject);
        add(md, 'Version__c', def.version);
        add(md, 'Mode__c', newMode);
        add(md, 'Provider_Config__c', def.providerConfig);
        add(md, 'Description__c', def.description);
        add(md, 'Owner_Email__c', def.ownerEmail);
        add(md, 'Daily_Budget_Calls__c', def.dailyBudgetCalls);
        add(md, 'Definition_Hash__c', def.definitionHash);
        add(md, 'Pack__c', def.pack);
        add(md, 'Review_Queue__c', def.reviewQueue);
        add(md, 'Auto_Apply__c', def.autoApply == true);
        add(md, 'Timeout_Ms__c', rows.isEmpty() ? null : rows[0].Timeout_Ms__c);
        return md;
    }

    private static void add(Metadata.CustomMetadata md, String field, Object value) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = field;
        v.value = value;
        md.values.add(v);
    }
}
