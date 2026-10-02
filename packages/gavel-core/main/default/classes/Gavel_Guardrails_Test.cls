@IsTest
private class Gavel_Guardrails_Test {
    private static Gavel_Definition live(String name, Decimal budget) {
        Gavel_Definition d = Gavel_TestFactory.triage(name);
        d.mode = Gavel_Definition.MODE_LIVE;
        d.dailyBudgetCalls = budget;
        return Gavel_TestFactory.register(d);
    }

    private static List<Case> cases(Integer n) {
        List<Case> cs = new List<Case>();
        for (Integer i = 0; i < n; i++) {
            cs.add(Gavel_TestFactory.newCase('Case ' + i, 'Description number ' + i));
        }
        insert cs;
        return cs;
    }

    private static List<Gavel_Runtime.RunRequest> requests(List<Case> cs, String def) {
        List<Gavel_Runtime.RunRequest> reqs = new List<Gavel_Runtime.RunRequest>();
        for (Case c : cs) {
            reqs.add(new Gavel_Runtime.RunRequest(c.Id, def));
        }
        return reqs;
    }

    // AS-9.1 Budget stops calls
    @IsTest
    static void budgetStopsCalls() {
        Gavel_TestFactory.ops(true);
        live('Budgeted', 100);
        String key = 'budget:Budgeted:' + System.now().formatGmt('yyyyMMdd');
        insert new Gavel_Counter__c(Name = key, Key__c = key, Count__c = 100);
        Case c = cases(1)[0];
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(c.Id, 'Budgeted');
        Assert.areEqual('SKIP', r.outcome);
        Assert.areEqual('budget_exceeded', r.reason);
        Assert.areEqual(0, Gavel_MockProvider.callCount, 'no callout');
        Assert.areEqual('budget_exceeded', [SELECT Reason__c FROM Gavel_Decision_Log__c WHERE Id = :r.ledgerId].Reason__c, 'ledgered');
        Assert.areEqual(1, [SELECT COUNT() FROM Gavel_Review__c WHERE Decision_Log__c = :r.ledgerId], 'Live budget SKIP goes to a person');
    }

    @IsTest
    static void budgetCountsWithinATransactionAndAlertsAt80Pct() {
        Gavel_TestFactory.ops(true);
        live('Small_Budget', 5);
        List<Gavel_Runtime.RunResult> rs = Gavel_Runtime.runAll(requests(cases(6), 'Small_Budget'));
        Integer called = 0;
        for (Gavel_Runtime.RunResult r : rs) {
            if (r.reason != 'budget_exceeded') {
                called++;
            }
        }
        Assert.areEqual(5, called);
        Assert.areEqual('budget_exceeded', rs[5].reason);
        Assert.areEqual(5, Gavel_MockProvider.callCount);
        String key = 'budget:Small_Budget:' + System.now().formatGmt('yyyyMMdd');
        Assert.areEqual(5, [SELECT Count__c FROM Gavel_Counter__c WHERE Key__c = :key].Count__c, 'persisted to the counter object');
        Assert.isTrue(Gavel_Alerts.wasRaised('budget_80pct'));
    }

    // AS-9.2 Breaker opens and closes
    @IsTest
    static void breakerOpensAndCloses() {
        Gavel_Config.Ops ops = Gavel_TestFactory.ops(true);
        ops.breakerErrors = 20;
        ops.breakerCooldownMin = 10;
        live('Breaker_Def', null);
        Gavel_MockProvider.failWith('Breaker_Def', 'http_error', 500);
        List<Case> cs = cases(23);
        List<Case> first21 = new List<Case>();
        for (Integer i = 0; i < 21; i++) {
            first21.add(cs[i]);
        }
        List<Gavel_Runtime.RunResult> rs = Gavel_Runtime.runAll(requests(first21, 'Breaker_Def'));
        for (Integer i = 0; i < 20; i++) {
            Assert.areEqual('http_error', rs[i].reason, 'run ' + i);
        }
        Assert.areEqual('SKIP', rs[20].outcome);
        Assert.areEqual('circuit_open', rs[20].reason, 'after 20 consecutive 500s the next run is not attempted');
        Assert.areEqual(20, Gavel_MockProvider.callCount);
        Assert.isTrue(Gavel_Alerts.wasRaised('breaker_open'));
        Assert.isTrue([SELECT Value__c FROM Gavel_Counter__c WHERE Key__c = 'breaker'].Value__c.startsWith('OPEN'), 'state persisted');

        // Still open before cooldown (fresh transaction state, read back from storage)
        Gavel_Guardrails.reset();
        Gavel_Guardrails.nowOverride = System.now().addMinutes(5);
        Assert.areEqual('circuit_open', Gavel_Guardrails.preflight(Gavel_DefinitionRepo.get('Breaker_Def')).reason);

        // After cooldown: exactly one half-open trial; it succeeds and closes the breaker.
        Gavel_Guardrails.reset();
        Gavel_Guardrails.nowOverride = System.now().addMinutes(11);
        Gavel_MockProvider.respondWith('Breaker_Def', new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.95, 'FRAUD' => 0.02, 'TECHNICAL' => 0.02, 'ACCOUNT' => 0.01 }, 0.9)
            .noul('fraud_concern', 0.02).json());
        List<Gavel_Runtime.RunResult> after = Gavel_Runtime.runAll(new List<Gavel_Runtime.RunRequest>{
            new Gavel_Runtime.RunRequest(cs[21].Id, 'Breaker_Def'), new Gavel_Runtime.RunRequest(cs[22].Id, 'Breaker_Def')
        });
        Assert.areEqual('AUTO', after[0].outcome, 'half-open trial attempted');
        Assert.areEqual('AUTO', after[1].outcome, 'closed again after a successful trial');
        Assert.areEqual('CLOSED', Gavel_Guardrails.breakerState());
    }

    @IsTest
    static void halfOpenFailureReopens() {
        Gavel_Config.Ops ops = Gavel_TestFactory.ops(true);
        ops.breakerErrors = 2;
        live('Flaky', null);
        Gavel_MockProvider.failWith('Flaky', 'timeout', null);
        Gavel_Runtime.runAll(requests(cases(2), 'Flaky'));
        Assert.areEqual('OPEN', Gavel_Guardrails.breakerState());
        Gavel_Guardrails.reset();
        Gavel_Guardrails.nowOverride = System.now().addMinutes(11);
        Gavel_Definition d = Gavel_DefinitionRepo.get('Flaky');
        Assert.isTrue(Gavel_Guardrails.preflight(d).allowed, 'one trial');
        Assert.areEqual('circuit_open', Gavel_Guardrails.preflight(d).reason, 'only one trial while half-open');
        Gavel_Guardrails.record(d, Gavel_JudgmentResponse.failure('timeout', null, null));
        Assert.areEqual('OPEN', Gavel_Guardrails.breakerState(), 'failed trial reopens');
    }

    @IsTest
    static void cacheHitAvoidsCallAndVersionChangeMisses() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = live('Cached_Def', null);
        Case a = Gavel_TestFactory.newCase('Same subject', 'Same description');
        Case b = Gavel_TestFactory.newCase('Same subject', 'Same description');
        insert new List<Case>{ a, b };
        Gavel_Runtime.RunResult first = Gavel_Runtime.run(a.Id, 'Cached_Def');
        Gavel_Runtime.RunResult second = Gavel_Runtime.run(b.Id, 'Cached_Def');
        Assert.isFalse(first.cacheHit);
        Assert.isTrue(second.cacheHit, 'same definition hash + state hash');
        Assert.areEqual(1, Gavel_MockProvider.callCount);
        Assert.isTrue([SELECT Cache_Hit__c FROM Gavel_Decision_Log__c WHERE Id = :second.ledgerId].Cache_Hit__c);
        Assert.areEqual(first.outcome, second.outcome);

        // New version -> new definition hash -> cache miss
        d.version = 2;
        Gavel_TestFactory.register(d);
        Case c = Gavel_TestFactory.newCase('Same subject', 'Same description');
        insert c;
        Assert.isFalse(Gavel_Runtime.run(c.Id, 'Cached_Def').cacheHit);
        Assert.areEqual(2, Gavel_MockProvider.callCount);
    }

    @IsTest
    static void cacheUnavailableFallsBackToCounterObject() {
        Gavel_TestFactory.ops(true);
        Gavel_CacheStore.MemoryStore off = new Gavel_CacheStore.MemoryStore();
        off.enabled = false;
        Gavel_Guardrails.store = off;
        live('No_Cache', 1);
        List<Gavel_Runtime.RunResult> rs = Gavel_Runtime.runAll(requests(cases(2), 'No_Cache'));
        Assert.areEqual('budget_exceeded', rs[1].reason, 'budget enforced without cache');
        Assert.isFalse(off.available());
        Assert.isNull(off.get('x'));
        Assert.areEqual('gavelbx1', Gavel_CacheStore.key('gavelb', 'x:1'));
    }

    @IsTest
    static void platformStoreNeverThrows() {
        Gavel_CacheStore.PlatformStore p = new Gavel_CacheStore.PlatformStore();
        p.put('gaveltestkey', 'v', 600);
        Object v = p.get('gaveltestkey');
        Assert.isTrue(v == null || String.valueOf(v) == 'v');
        Assert.isNotNull(p.available());
    }

    @IsTest
    static void alertMonitorRates() {
        Gavel_Config.Ops ops = Gavel_TestFactory.ops(true);
        ops.errorAlertPct = 5;
        ops.escalateAlertPct = 20;
        List<Gavel_Decision_Log__c> rows = new List<Gavel_Decision_Log__c>();
        for (Integer i = 0; i < 10; i++) {
            Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(null, 'Noisy', null, 'n' + i);
            e.Outcome__c = i < 2 ? 'ERROR' : (i < 5 ? 'ESCALATE' : 'AUTO');
            rows.add(e);
        }
        Gavel_Ledger.write(rows);
        Integer raised = Gavel_AlertMonitor.check(System.now().addSeconds(5));
        Assert.areEqual(2, raised);
        Assert.isTrue(Gavel_Alerts.wasRaised('error_rate'));
        Assert.isTrue(Gavel_Alerts.wasRaised('escalate_rate'));
        new Gavel_AlertMonitor().execute(null);
    }
}
