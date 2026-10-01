/**
 * Org-level operations config (Gavel_Ops_Config__mdt, record "Default") with safe defaults.
 * A missing record means egress stays off.
 */
public with sharing class Gavel_Config {
    public class Ops {
        public Boolean egressEnabled = false;
        public Boolean storeState = false;
        public Decimal errorAlertPct = 5;
        public Decimal escalateAlertPct = 20;
        public Integer breakerErrors = 20;
        public Integer breakerCooldownMin = 10;
        public Integer cacheTtlMin = 60;
        public Integer retentionDays = 365;
        public Integer batchSize = 20;
        public Integer feedbackWindowHours = 72;
        public Integer baselineDelayHours = 24;
        public Integer minSample = 200;
        public Decimal targetPrecision = 0.95;
        public Integer calibrationMaxAgeDays = 14;
        public Set<String> integrationUsers = new Set<String>();
    }

    @TestVisible
    private static Ops opsOverride;
    private static Ops cached;

    public static Ops ops() {
        if (opsOverride != null) {
            return opsOverride;
        }
        if (cached == null) {
            cached = load();
        }
        return cached;
    }

    private static Ops load() {
        Ops o = new Ops();
        Gavel_Ops_Config__mdt rec = Gavel_Ops_Config__mdt.getInstance('Default');
        if (rec == null) {
            return o;
        }
        o.egressEnabled = rec.Egress_Enabled__c == true;
        o.storeState = rec.Store_State__c == true;
        o.errorAlertPct = nvl(rec.Error_Alert_Pct__c, o.errorAlertPct);
        o.escalateAlertPct = nvl(rec.Escalate_Alert_Pct__c, o.escalateAlertPct);
        o.breakerErrors = nvlInt(rec.Breaker_Errors__c, o.breakerErrors);
        o.breakerCooldownMin = nvlInt(rec.Breaker_Cooldown_Min__c, o.breakerCooldownMin);
        o.cacheTtlMin = nvlInt(rec.Cache_TTL_Min__c, o.cacheTtlMin);
        o.retentionDays = nvlInt(rec.Retention_Days__c, o.retentionDays);
        o.batchSize = Math.max(1, Math.min(nvlInt(rec.Batch_Size__c, o.batchSize), 50));
        o.feedbackWindowHours = nvlInt(rec.Feedback_Window_Hours__c, o.feedbackWindowHours);
        o.baselineDelayHours = nvlInt(rec.Baseline_Delay_Hours__c, o.baselineDelayHours);
        o.minSample = nvlInt(rec.Min_Sample__c, o.minSample);
        o.targetPrecision = nvl(rec.Target_Precision__c, o.targetPrecision);
        o.calibrationMaxAgeDays = nvlInt(rec.Calibration_Max_Age_Days__c, o.calibrationMaxAgeDays);
        if (String.isNotBlank(rec.Integration_Users__c)) {
            for (String u : rec.Integration_Users__c.split('[,;\\s]+')) {
                if (String.isNotBlank(u)) {
                    o.integrationUsers.add(u.trim().toLowerCase());
                }
            }
        }
        return o;
    }

    private static Decimal nvl(Decimal v, Decimal dflt) {
        return v == null ? dflt : v;
    }

    private static Integer nvlInt(Decimal v, Integer dflt) {
        return v == null ? dflt : v.intValue();
    }
}
