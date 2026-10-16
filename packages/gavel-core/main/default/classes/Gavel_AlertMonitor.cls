/**
 * Rate alerts (F1, F5): error rate above Error_Alert_Pct__c over 15 minutes and ESCALATE rate above
 * Escalate_Alert_Pct__c over 1 hour, per definition. Schedule every 15 minutes, for example:
 *   for (Integer m : new List<Integer>{ 0, 15, 30, 45 })
 *       System.schedule('Gavel alerts :' + m, '0 ' + m + ' * * * ?', new Gavel_AlertMonitor());
 */
public without sharing class Gavel_AlertMonitor implements Schedulable {
    public void execute(SchedulableContext sc) {
        check(System.now());
    }

    public static Integer check(Datetime asOf) {
        Gavel_Config.Ops ops = Gavel_Config.ops();
        Integer raised = 0;
        raised += rate(asOf.addMinutes(-15), new Set<String>{ Gavel_Outcome.ERROR }, ops.errorAlertPct, 'error_rate', '15 minutes');
        raised += rate(asOf.addHours(-1), new Set<String>{ Gavel_Outcome.ESCALATE }, ops.escalateAlertPct, 'escalate_rate', '1 hour');
        Gavel_Alerts.flush();
        return raised;
    }

    private static Integer rate(Datetime since, Set<String> outcomes, Decimal thresholdPct, String alertType, String window) {
        Map<String, Integer> total = new Map<String, Integer>();
        Map<String, Integer> hits = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Definition__c def, Outcome__c outcome, COUNT(Id) n
            FROM Gavel_Decision_Log__c
            WHERE Run_At__c >= :since AND Outcome__c != 'PENDING'
            WITH SYSTEM_MODE GROUP BY Definition__c, Outcome__c
        ]) {
            String def = (String) ar.get('def');
            Integer n = (Integer) ar.get('n');
            total.put(def, (total.containsKey(def) ? total.get(def) : 0) + n);
            if (outcomes.contains((String) ar.get('outcome'))) {
                hits.put(def, (hits.containsKey(def) ? hits.get(def) : 0) + n);
            }
        }
        Integer raised = 0;
        for (String def : hits.keySet()) {
            Decimal pct = 100.0 * hits.get(def) / total.get(def);
            if (pct > thresholdPct) {
                Gavel_Alerts.raise(alertType, Gavel_Alerts.WARNING, def, alertType + ' ' + pct.setScale(1) + '% over ' + window);
                raised++;
            }
        }
        return raised;
    }
}
