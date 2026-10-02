/**
 * Read API for the ledger record LWC (LEDG-001.6). Runs with the user's sharing and FLS:
 * people see entries only through Gavel_Auditor / Gavel_Admin access.
 */
public with sharing class Gavel_LedgerController {
    @AuraEnabled(cacheable=true)
    public static List<Gavel_Decision_Log__c> entriesForRecord(String recordId, Integer limitSize) {
        Integer n = limitSize == null ? 50 : Math.max(1, Math.min(limitSize, 200));
        return [
            SELECT Id, Name, Definition__c, Version__c, Mode__c, Outcome__c, Reason__c, Top_Choice__c, Top_Confidence__c,
                Model_Version__c, Action_Taken__c, Action_Suppressed__c, Cache_Hit__c, Latency_Ms__c, Run_At__c, CreatedDate
            FROM Gavel_Decision_Log__c
            WHERE Record_Id__c = :recordId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :n
        ];
    }

    @AuraEnabled
    public static Map<String, Object> verifyChain(String definition) {
        if (!Schema.sObjectType.Gavel_Decision_Log__c.isAccessible()) {
            throw new AuraHandledException('Ledger access required');
        }
        Gavel_LedgerVerifier.Result r = Gavel_LedgerVerifier.verify(definition);
        return new Map<String, Object>{ 'ok' => r.ok, 'checked' => r.checked, 'brokenAtSeq' => r.brokenAtSeq, 'reason' => r.reason };
    }
}
