trigger Gavel_Action_Log_Trigger on Gavel_Action_Log__c(before insert, before update, before delete) {
    Gavel_LedgerGuard.enforce(Trigger.operationType, Trigger.new, Trigger.oldMap);
}
