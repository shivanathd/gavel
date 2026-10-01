/**
 * Async-first execution (ADR-007, FLOW-001.2/.5). Writes one PENDING ledger entry per record, then enqueues
 * Gavel_DecisionQueueable jobs of at most Batch_Size__c (default 20) records. Runs that are already known to
 * end without a callout (unknown, retired or invalid definition, duplicate in flight, egress off) are
 * finished immediately instead. Records beyond the available queueable slots stay PENDING and are picked up
 * by the chained job or by Gavel_PendingSweeper.
 */
public with sharing class Gavel_AsyncService {
    public class Request {
        public Id recordId;
        public String definitionApiName;

        public Request(Id recordId, String definitionApiName) {
            this.recordId = recordId;
            this.definitionApiName = definitionApiName;
        }
    }

    /** Returns one ledger id per request (PENDING, or final when the run ended immediately). */
    public static List<Id> enqueue(List<Request> requests) {
        List<Id> ledgerIds = new List<Id>();
        Set<String> names = new Set<String>();
        for (Request r : requests) {
            names.add(r.definitionApiName);
            ledgerIds.add(null);
        }
        Map<String, Gavel_Definition> defs = Gavel_DefinitionRepo.getAll(names);
        Map<String, Boolean> validByName = new Map<String, Boolean>();
        for (String n : defs.keySet()) {
            validByName.put(n, Gavel_DefinitionValidator.validate(defs.get(n)).valid);
        }

        Set<String> keys = new Set<String>();
        Map<Integer, String> keyByIndex = new Map<Integer, String>();
        for (Integer i = 0; i < requests.size(); i++) {
            Gavel_Definition def = defs.get(requests[i].definitionApiName);
            if (def != null && requests[i].recordId != null) {
                String k = Gavel_Runtime.idempotencyKey(new Gavel_Runtime.RunRequest(requests[i].recordId, requests[i].definitionApiName), def);
                keyByIndex.put(i, k);
                keys.add(k);
            }
        }
        Set<String> recent = keys.isEmpty() ? new Set<String>() : Gavel_Ledger.recentKeys(keys, Gavel_Runtime.DUPLICATE_WINDOW_SECONDS);
        Set<String> seen = new Set<String>();
        Boolean egress = Gavel_Config.ops().egressEnabled;

        List<Gavel_Runtime.RunRequest> immediate = new List<Gavel_Runtime.RunRequest>();
        List<Integer> immediateIndex = new List<Integer>();
        List<Gavel_Decision_Log__c> pending = new List<Gavel_Decision_Log__c>();
        List<Integer> pendingIndex = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            Request r = requests[i];
            Gavel_Definition def = defs.get(r.definitionApiName);
            String k = keyByIndex.get(i);
            Boolean terminal = def == null || r.recordId == null || def.mode == Gavel_Definition.MODE_RETIRED ||
                validByName.get(r.definitionApiName) != true || !egress ||
                (k != null && (recent.contains(k) || seen.contains(k)));
            if (k != null) {
                seen.add(k);
            }
            if (terminal) {
                // The runtime ends these before any callout: SKIP/ERROR, ledgered.
                immediate.add(new Gavel_Runtime.RunRequest(r.recordId, r.definitionApiName));
                immediateIndex.add(i);
            } else {
                pending.add(Gavel_Ledger.newEntry(def, def.apiName, r.recordId, k));
                pendingIndex.add(i);
            }
        }
        if (!immediate.isEmpty()) {
            List<Gavel_Runtime.RunResult> results = Gavel_Runtime.runAll(immediate);
            for (Integer j = 0; j < results.size(); j++) {
                ledgerIds[immediateIndex[j]] = results[j].ledgerId;
            }
        }
        if (!pending.isEmpty()) {
            Gavel_Ledger.insertPending(pending);
            List<Id> pendingIds = new List<Id>();
            for (Integer j = 0; j < pending.size(); j++) {
                ledgerIds[pendingIndex[j]] = pending[j].Id;
                pendingIds.add(pending[j].Id);
            }
            schedule(pendingIds);
        }
        return ledgerIds;
    }

    /** Splits pending ids into chunks and enqueues as many jobs as the transaction allows. */
    public static Integer schedule(List<Id> pendingIds) {
        Integer size = Gavel_Config.ops().batchSize;
        List<List<Id>> chunks = new List<List<Id>>();
        for (Integer i = 0; i < pendingIds.size(); i += size) {
            List<Id> chunk = new List<Id>();
            for (Integer j = i; j < Math.min(i + size, pendingIds.size()); j++) {
                chunk.add(pendingIds[j]);
            }
            chunks.add(chunk);
        }
        Integer slots = Limits.getLimitQueueableJobs() - Limits.getQueueableJobs();
        Integer jobs = 0;
        for (Integer c = 0; c < chunks.size() && jobs < slots; c++) {
            List<Id> backlog = new List<Id>();
            if (jobs == slots - 1) {
                // Last available slot: carry everything left so the job can chain (outside tests) or leave it for the sweeper.
                for (Integer rest = c + 1; rest < chunks.size(); rest++) {
                    backlog.addAll(chunks[rest]);
                }
            }
            System.enqueueJob(new Gavel_DecisionQueueable(chunks[c], backlog));
            jobs++;
            if (!backlog.isEmpty()) {
                break;
            }
        }
        return jobs;
    }
}
