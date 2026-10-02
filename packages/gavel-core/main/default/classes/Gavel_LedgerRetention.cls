/**
 * Deletes ledger entries older than Retention_Days__c (default 365) and writes a purge summary per
 * definition whose last hash anchors the remaining chain (LEDG-001.5). Schedule daily:
 *   System.schedule('Gavel ledger retention', '0 0 3 * * ?', new Gavel_LedgerRetention());
 */
public without sharing class Gavel_LedgerRetention implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
    private Datetime cutoff;
    private Map<String, Integer> counts = new Map<String, Integer>();

    public Gavel_LedgerRetention() {
        this(System.now().addDays(-Gavel_Config.ops().retentionDays));
    }

    public Gavel_LedgerRetention(Datetime cutoff) {
        this.cutoff = cutoff;
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new Gavel_LedgerRetention(), 2000);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime c = cutoff;
        return Database.getQueryLocator([
            SELECT Id, Definition__c, Chain_Seq__c, Entry_Hash__c
            FROM Gavel_Decision_Log__c
            WHERE Run_At__c < :c AND Outcome__c != 'PENDING'
            ORDER BY Definition__c, Chain_Seq__c
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Gavel_Decision_Log__c> scope) {
        Map<String, List<Gavel_Decision_Log__c>> byDef = new Map<String, List<Gavel_Decision_Log__c>>();
        for (Gavel_Decision_Log__c e : scope) {
            if (!byDef.containsKey(e.Definition__c)) {
                byDef.put(e.Definition__c, new List<Gavel_Decision_Log__c>());
            }
            byDef.get(e.Definition__c).add(e);
        }
        for (String def : byDef.keySet()) {
            Gavel_Ledger.purge(def, byDef.get(def), cutoff);
            counts.put(def, (counts.containsKey(def) ? counts.get(def) : 0) + byDef.get(def).size());
        }
    }

    public void finish(Database.BatchableContext bc) {
        return;
    }

    public static Integer runNow(Datetime cutoff) {
        Gavel_LedgerRetention job = new Gavel_LedgerRetention(cutoff);
        List<Gavel_Decision_Log__c> scope = [
            SELECT Id, Definition__c, Chain_Seq__c, Entry_Hash__c
            FROM Gavel_Decision_Log__c
            WHERE Run_At__c < :cutoff AND Outcome__c != 'PENDING'
            ORDER BY Definition__c, Chain_Seq__c
            LIMIT 10000
        ];
        job.execute(null, scope);
        return scope.size();
    }
}
