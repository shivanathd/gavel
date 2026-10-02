/**
 * Immutability for Gavel_Decision_Log__c and Gavel_Action_Log__c (LEDG-001.2).
 * Applies to every user, including System Administrators. The only writes allowed are the ones
 * Gavel_Ledger performs: runtime inserts, one PENDING -> final finalization, and retention deletes.
 */
public without sharing class Gavel_LedgerGuard {
    public static void enforce(System.TriggerOperation op, List<SObject> newRows, Map<Id, SObject> oldMap) {
        String bypass = Gavel_Ledger.activeBypass();
        switch on op {
            when BEFORE_INSERT {
                if (!Gavel_Ledger.isRuntimeInsert()) {
                    for (SObject r : newRows) {
                        r.addError(Gavel_Ledger.RUNTIME_ONLY);
                    }
                }
            }
            when BEFORE_UPDATE {
                if (bypass == Gavel_Ledger.BYPASS_RETENTION) {
                    return;
                }
                for (SObject r : newRows) {
                    SObject old = oldMap.get(r.Id);
                    Boolean finalizing = bypass == Gavel_Ledger.BYPASS_FINALIZE &&
                        old.getSObjectType() == Gavel_Decision_Log__c.SObjectType &&
                        (String) old.get('Outcome__c') == Gavel_Outcome.PENDING &&
                        (String) r.get('Outcome__c') != Gavel_Outcome.PENDING &&
                        (String) r.get('Idempotency_Key__c') == (String) old.get('Idempotency_Key__c') &&
                        (String) r.get('Definition__c') == (String) old.get('Definition__c') &&
                        (String) r.get('Record_Id__c') == (String) old.get('Record_Id__c');
                    if (!finalizing) {
                        r.addError(Gavel_Ledger.IMMUTABLE);
                    }
                }
            }
            when BEFORE_DELETE {
                if (bypass != Gavel_Ledger.BYPASS_RETENTION) {
                    for (SObject r : oldMap.values()) {
                        r.addError(Gavel_Ledger.IMMUTABLE);
                    }
                }
            }
        }
    }
}
