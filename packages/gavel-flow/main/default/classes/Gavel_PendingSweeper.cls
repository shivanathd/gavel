/**
 * Picks up ledger entries still PENDING after 5 minutes (enqueue limits, chain depth, failed jobs) and runs
 * them (F4 edge case). Batch scope = Batch_Size__c so each execute stays under the callout limit.
 *   System.schedule('Gavel pending sweeper', '0 5 * * * ?', new Gavel_PendingSweeper());
 */
public with sharing class Gavel_PendingSweeper implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
    private Integer minAgeMinutes;

    public Gavel_PendingSweeper() {
        this(5);
    }

    public Gavel_PendingSweeper(Integer minAgeMinutes) {
        this.minAgeMinutes = minAgeMinutes;
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new Gavel_PendingSweeper(), Gavel_Config.ops().batchSize);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = System.now().addMinutes(-minAgeMinutes);
        return Database.getQueryLocator([
            SELECT Id FROM Gavel_Decision_Log__c
            WHERE Outcome__c = 'PENDING' AND CreatedDate <= :cutoff
            ORDER BY CreatedDate
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Gavel_Decision_Log__c> scope) {
        List<Id> ids = new List<Id>();
        for (Gavel_Decision_Log__c e : scope) {
            ids.add(e.Id);
        }
        Gavel_DecisionQueueable.process(ids);
    }

    public void finish(Database.BatchableContext bc) {
        return;
    }
}
