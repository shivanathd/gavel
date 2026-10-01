/**
 * Apex API (FLOW-001.4).
 *   Gavel_Runtime.RunResult r = Gavel.run(caseId, 'Gavel_Case_Triage');   // sync, applies Live AUTO actions
 *   Id pending = Gavel.runAsync(caseId, 'Gavel_Case_Triage');             // queued, PENDING ledger id
 * Sync runs make a callout: call them only where no DML is pending in the transaction.
 */
public with sharing class Gavel {
    public static Gavel_Runtime.RunResult run(Id recordId, String definition) {
        return Gavel_Runtime.run(recordId, definition);
    }

    public static List<Gavel_Runtime.RunResult> run(List<Id> recordIds, String definition) {
        List<Gavel_Runtime.RunRequest> reqs = new List<Gavel_Runtime.RunRequest>();
        for (Id rid : recordIds) {
            reqs.add(new Gavel_Runtime.RunRequest(rid, definition));
        }
        return Gavel_Runtime.runAll(reqs);
    }

    /** Record-less run with direct inputs (for example screening text). */
    public static Gavel_Runtime.RunResult runWithInputs(String definition, Map<String, Object> inputs, Id relatedRecordId) {
        Gavel_Runtime.RunRequest r = new Gavel_Runtime.RunRequest(relatedRecordId, definition);
        r.inputs = inputs;
        return Gavel_Runtime.run(r);
    }

    public static Id runAsync(Id recordId, String definition) {
        return runAsync(new List<Id>{ recordId }, definition)[0];
    }

    public static List<Id> runAsync(List<Id> recordIds, String definition) {
        List<Gavel_AsyncService.Request> reqs = new List<Gavel_AsyncService.Request>();
        for (Id rid : recordIds) {
            reqs.add(new Gavel_AsyncService.Request(rid, definition));
        }
        return Gavel_AsyncService.enqueue(reqs);
    }

    public static List<Gavel_Runtime.ApplyResult> applyOutcome(List<Id> ledgerIds) {
        return Gavel_Runtime.applyOutcome(ledgerIds);
    }
}
