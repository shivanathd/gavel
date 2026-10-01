/**
 * Ops guardrails (F9, ADR-013): per-definition daily budget, org-level circuit breaker, judgment cache.
 *
 * Reads happen before callouts; all writes are buffered and persisted by flush() after the last callout of
 * the transaction. Counters live in Platform Cache with a Gavel_Counter__c mirror; when the cache is
 * unavailable the counter object is the source of truth (never fail open on budget).
 *
 * Breaker: CLOSED -> OPEN after Breaker_Errors__c consecutive provider failures; OPEN for
 * Breaker_Cooldown_Min__c; then HALF_OPEN lets exactly one trial run. Success closes it, failure reopens it.
 */
public without sharing class Gavel_Guardrails {
    public static final String CLOSED = 'CLOSED';
    public static final String OPEN = 'OPEN';
    public static final String HALF_OPEN = 'HALF_OPEN';
    private static final String BREAKER_KEY = 'breaker';

    @TestVisible
    private static Datetime nowOverride;
    @TestVisible
    private static Gavel_CacheStore.Store store = Test.isRunningTest()
        ? (Gavel_CacheStore.Store) new Gavel_CacheStore.MemoryStore()
        : (Gavel_CacheStore.Store) new Gavel_CacheStore.PlatformStore();

    // Transaction state
    private static Breaker current;
    private static Boolean breakerDirty = false;
    private static Boolean trialInFlight = false;
    private static Map<String, Decimal> budgetBase = new Map<String, Decimal>();
    private static Map<String, Integer> budgetDelta = new Map<String, Integer>();
    private static Set<String> budgetAlerted = new Set<String>();
    private static Boolean breakerSucceeded = false;
    private static Integer breakerErrorsSinceSuccess = 0;

    public class Decision {
        public Boolean allowed = true;
        public String reason;
    }

    private class Breaker {
        public String state = CLOSED;
        public Integer consecutive = 0;
        public Long openedAt = 0;
    }

    public static Datetime now() {
        return nowOverride != null ? nowOverride : System.now();
    }

    /** Budget and breaker check before any state is built (runs before F3). */
    public static Decision preflight(Gavel_Definition def) {
        Decision d = new Decision();
        Breaker b = loadBreaker();
        Integer cooldownMs = Gavel_Config.ops().breakerCooldownMin * 60000;
        if (b.state == OPEN || b.state == HALF_OPEN) {
            Boolean cooled = now().getTime() - b.openedAt >= cooldownMs;
            if (!cooled || trialInFlight) {
                d.allowed = false;
                d.reason = Gavel_JudgmentResponse.CIRCUIT_OPEN;
                return d;
            }
            // Half-open: this run is the single trial.
            b.state = HALF_OPEN;
            b.openedAt = now().getTime();
            breakerDirty = true;
            trialInFlight = true;
        }
        if (def.dailyBudgetCalls != null) {
            Decimal used = budgetUsed(def.apiName);
            if (used == null || used >= def.dailyBudgetCalls) {
                d.allowed = false;
                d.reason = Gavel_JudgmentResponse.BUDGET_EXCEEDED;
                if (trialInFlight && b.state == HALF_OPEN) {
                    trialInFlight = false; // no call was made; the next run may try
                }
                return d;
            }
        }
        return d;
    }

    /** Counts a real provider call and updates the breaker. Cache hits are not recorded. */
    public static void record(Gavel_Definition def, Gavel_JudgmentResponse resp) {
        if (def.dailyBudgetCalls != null) {
            String k = budgetKey(def.apiName);
            budgetDelta.put(k, (budgetDelta.containsKey(k) ? budgetDelta.get(k) : 0) + 1);
            Decimal used = budgetUsed(def.apiName);
            if (used != null && used >= def.dailyBudgetCalls * 0.8 && !budgetAlerted.contains(k)) {
                budgetAlerted.add(k);
                Gavel_Alerts.raise('budget_80pct', Gavel_Alerts.WARNING, def.apiName, 'Daily budget 80% used (' + used + ' of ' + def.dailyBudgetCalls + ')');
            }
        }
        Breaker b = loadBreaker();
        Boolean failure = resp != null && Gavel_JudgmentResponse.PROVIDER_FAILURES.contains(resp.status);
        if (failure) {
            b.consecutive++;
            breakerErrorsSinceSuccess++;
            if (b.state == HALF_OPEN || b.consecutive >= Gavel_Config.ops().breakerErrors) {
                if (b.state != OPEN) {
                    Gavel_Alerts.raise('breaker_open', Gavel_Alerts.CRITICAL, def.apiName, 'Provider circuit breaker opened after ' + b.consecutive + ' consecutive errors');
                }
                b.state = OPEN;
                b.openedAt = now().getTime();
                trialInFlight = false;
            }
        } else if (resp != null && resp.isOk()) {
            b.consecutive = 0;
            b.state = CLOSED;
            b.openedAt = 0;
            trialInFlight = false;
            breakerSucceeded = true;
            breakerErrorsSinceSuccess = 0;
        }
        breakerDirty = true;
    }

    public static String breakerState() {
        return loadBreaker().state;
    }

    // ---- judgment cache (OPS-001.3) ----

    public static String cacheKey(Gavel_Definition def, String stateHash) {
        String h = Gavel_Json.sha256Hex(String.valueOf(def.definitionHash) + String.valueOf(stateHash)).left(40);
        return Gavel_CacheStore.key('gavelj', h);
    }

    public static Gavel_JudgmentResponse cached(Gavel_Definition def, String stateHash) {
        try {
            Object v = store.get(cacheKey(def, stateHash));
            if (v instanceof String) {
                return (Gavel_JudgmentResponse) JSON.deserialize((String) v, Gavel_JudgmentResponse.class);
            }
        } catch (Exception e) {
            return null;
        }
        return null;
    }

    public static void cachePut(Gavel_Definition def, String stateHash, Gavel_JudgmentResponse resp) {
        if (resp == null || !resp.isOk()) {
            return;
        }
        store.put(cacheKey(def, stateHash), JSON.serialize(resp), Gavel_Config.ops().cacheTtlMin * 60);
    }

    // ---- persistence ----

    /** Persist buffered counters. Call after the last callout of the transaction. Never throws. */
    public static void flush() {
        if (budgetDelta.isEmpty() && !breakerDirty) {
            return;
        }
        try {
            Set<String> keys = new Set<String>(budgetDelta.keySet());
            if (breakerDirty) {
                keys.add(BREAKER_KEY);
            }
            Map<String, Gavel_Counter__c> rows = new Map<String, Gavel_Counter__c>();
            for (Gavel_Counter__c c : [SELECT Id, Key__c, Count__c, Value__c FROM Gavel_Counter__c WHERE Key__c IN :keys FOR UPDATE]) {
                rows.put(c.Key__c, c);
            }
            for (String k : budgetDelta.keySet()) {
                Gavel_Counter__c c = rows.containsKey(k) ? rows.get(k) : new Gavel_Counter__c(Name = k.abbreviate(80), Key__c = k, Count__c = 0);
                c.Count__c = (c.Count__c == null ? 0 : c.Count__c) + budgetDelta.get(k);
                c.Updated_At__c = System.now();
                rows.put(k, c);
                store.put(Gavel_CacheStore.key('gavelb', k), c.Count__c, 86400);
            }
            if (breakerDirty) {
                Breaker b = loadBreaker();
                Gavel_Counter__c c = rows.containsKey(BREAKER_KEY) ? rows.get(BREAKER_KEY) : new Gavel_Counter__c(Name = BREAKER_KEY, Key__c = BREAKER_KEY, Count__c = 0);
                if (!breakerSucceeded && c.Count__c != null && b.state != OPEN) {
                    // Other transactions may have recorded failures meanwhile: add ours to theirs.
                    b.consecutive = Integer.valueOf(c.Count__c) + breakerErrorsSinceSuccess;
                    if (b.consecutive >= Gavel_Config.ops().breakerErrors) {
                        b.state = OPEN;
                        b.openedAt = now().getTime();
                    }
                }
                c.Count__c = b.consecutive;
                c.Value__c = b.state + '|' + b.openedAt;
                c.Updated_At__c = System.now();
                rows.put(BREAKER_KEY, c);
                store.put(Gavel_CacheStore.key('gavel', BREAKER_KEY), c.Value__c + '|' + c.Count__c, 86400);
            }
            upsert rows.values() Gavel_Counter__c.Key__c;
        } catch (Exception e) {
            Gavel_Alerts.raise('guardrail_persist_failed', Gavel_Alerts.WARNING, null, 'Guardrail counters could not be saved');
        } finally {
            for (String k : budgetDelta.keySet()) {
                budgetBase.put(k, (budgetBase.containsKey(k) && budgetBase.get(k) != null ? budgetBase.get(k) : 0) + budgetDelta.get(k));
            }
            budgetDelta.clear();
            breakerDirty = false;
            breakerSucceeded = false;
            breakerErrorsSinceSuccess = 0;
        }
    }

    /** Clears transaction state (tests and long-running jobs). */
    public static void reset() {
        current = null;
        breakerDirty = false;
        trialInFlight = false;
        budgetBase.clear();
        budgetDelta.clear();
        budgetAlerted.clear();
        breakerSucceeded = false;
        breakerErrorsSinceSuccess = 0;
    }

    private static String budgetKey(String definition) {
        return 'budget:' + definition + ':' + now().formatGmt('yyyyMMdd');
    }

    /** Calls used today including this transaction. Null means the count could not be read (deny). */
    private static Decimal budgetUsed(String definition) {
        String k = budgetKey(definition);
        if (!budgetBase.containsKey(k)) {
            Decimal base = null;
            Object cachedCount = store.get(Gavel_CacheStore.key('gavelb', k));
            if (cachedCount instanceof Decimal) {
                base = (Decimal) cachedCount;
            } else {
                try {
                    List<Gavel_Counter__c> rows = [SELECT Count__c FROM Gavel_Counter__c WHERE Key__c = :k LIMIT 1];
                    base = rows.isEmpty() || rows[0].Count__c == null ? 0 : rows[0].Count__c;
                } catch (Exception e) {
                    base = null;
                }
            }
            budgetBase.put(k, base);
        }
        Decimal base = budgetBase.get(k);
        if (base == null) {
            return null;
        }
        return base + (budgetDelta.containsKey(k) ? budgetDelta.get(k) : 0);
    }

    private static Breaker loadBreaker() {
        if (current != null) {
            return current;
        }
        current = new Breaker();
        String raw = null;
        Object c = store.get(Gavel_CacheStore.key('gavel', BREAKER_KEY));
        if (c instanceof String) {
            raw = (String) c;
        } else {
            List<Gavel_Counter__c> rows = [SELECT Count__c, Value__c FROM Gavel_Counter__c WHERE Key__c = :BREAKER_KEY LIMIT 1];
            if (!rows.isEmpty() && rows[0].Value__c != null) {
                raw = rows[0].Value__c + '|' + (rows[0].Count__c == null ? 0 : rows[0].Count__c.intValue());
            }
        }
        if (raw != null) {
            List<String> parts = raw.split('\\|');
            current.state = parts.size() > 0 ? parts[0] : CLOSED;
            current.openedAt = parts.size() > 1 && parts[1].isNumeric() ? Long.valueOf(parts[1]) : 0;
            current.consecutive = parts.size() > 2 ? Decimal.valueOf(parts[2]).intValue() : 0;
        }
        return current;
    }
}
