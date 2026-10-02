/**
 * Flow action "Gavel: Run Decision (Async)" (FLOW-001.2). Use from the asynchronous path of record-triggered
 * flows and for bulk loads. Returns the PENDING ledger id; the queueable applies AUTO actions on Live
 * definitions when it finishes. Never throws.
 */
public with sharing class Gavel_RunDecisionAsync {
    public class AsyncInput {
        @InvocableVariable(label='Record Id' required=true)
        public Id recordId;
        @InvocableVariable(label='Definition API Name' required=true)
        public String definitionApiName;
    }

    public class AsyncOutput {
        @InvocableVariable(label='Outcome' description='PENDING when queued; SKIP/ERROR when it ended immediately')
        public String outcome;
        @InvocableVariable(label='Ledger Id')
        public Id ledgerId;
    }

    @InvocableMethod(label='Gavel: Run Decision (Async)' description='Queues a Gavel decision and returns the pending ledger entry id.' category='Gavel')
    public static List<AsyncOutput> run(List<AsyncInput> inputs) {
        List<AsyncOutput> outputs = new List<AsyncOutput>();
        if (inputs == null) {
            return outputs;
        }
        try {
            List<Gavel_AsyncService.Request> requests = new List<Gavel_AsyncService.Request>();
            for (AsyncInput i : inputs) {
                requests.add(new Gavel_AsyncService.Request(i == null ? null : i.recordId, i == null ? null : i.definitionApiName));
            }
            List<Id> ledgerIds = Gavel_AsyncService.enqueue(requests);
            Map<Id, Gavel_Decision_Log__c> entries = Gavel_Ledger.load(new Set<Id>(ledgerIds));
            for (Id lid : ledgerIds) {
                AsyncOutput o = new AsyncOutput();
                o.ledgerId = lid;
                o.outcome = lid != null && entries.containsKey(lid) ? entries.get(lid).Outcome__c : Gavel_Outcome.ERROR;
                outputs.add(o);
            }
        } catch (Exception e) {
            outputs.clear();
            for (Integer i = 0; i < inputs.size(); i++) {
                AsyncOutput o = new AsyncOutput();
                o.outcome = Gavel_Outcome.ERROR;
                outputs.add(o);
            }
        }
        return outputs;
    }
}
