/**
 * Shadow comparison per definition and question (SHAD-001.4): sample size, agreement rate, agreement by
 * confidence band (0.1 bins), top disagreement pairs and the share that would have been AUTO.
 * Agreement with the baseline is not accuracy: a disagreement means "look here", not "Gavel is right".
 * Missing and circular baselines are excluded from agreement; unmapped values count as disagreement.
 */
public with sharing class Gavel_DisagreementReport {
    public class Band {
        public Decimal lower;
        public Decimal upper;
        public Integer n = 0;
        public Integer agree = 0;
        public Decimal rate;
    }

    public class Pair implements Comparable {
        public String gavel;
        public String baseline;
        public Integer count = 0;

        public Integer compareTo(Object other) {
            Pair p = (Pair) other;
            if (count != p.count) {
                return count > p.count ? -1 : 1;
            }
            return (gavel + baseline).compareTo(p.gavel + p.baseline);
        }
    }

    public class QuestionReport {
        public String questionKey;
        public Integer sampleSize = 0;
        public Integer compared = 0;
        public Integer agreed = 0;
        public Decimal agreementRate;
        public Integer missing = 0;
        public Integer unmapped = 0;
        public Integer circular = 0;
        public Integer wouldAuto = 0;
        public Decimal wouldAutoShare;
        public List<Band> bands = new List<Band>();
        public List<Pair> topDisagreements = new List<Pair>();
        public List<String> unmappedValues = new List<String>();
    }

    public class Report {
        public String definition;
        public Integer version;
        public Map<String, QuestionReport> questions = new Map<String, QuestionReport>();
        public String note = 'Agreement with the baseline is not accuracy.';
    }

    public static Report build(String definition) {
        return build(definition, null);
    }

    public static Report build(String definition, Integer version) {
        Report r = new Report();
        r.definition = definition;
        r.version = version;
        List<Gavel_Baseline__c> rows = version == null
            ? [SELECT Question_Key__c, Status__c, Agrees__c, Mapped_Option__c, Baseline_Value__c, Gavel_Value__c, Calibration_Value__c, Would_Auto__c
               FROM Gavel_Baseline__c WHERE Definition__c = :definition WITH SYSTEM_MODE LIMIT 50000]
            : [SELECT Question_Key__c, Status__c, Agrees__c, Mapped_Option__c, Baseline_Value__c, Gavel_Value__c, Calibration_Value__c, Would_Auto__c
               FROM Gavel_Baseline__c WHERE Definition__c = :definition AND Definition_Version__c = :version WITH SYSTEM_MODE LIMIT 50000];
        Map<String, Map<String, Pair>> pairs = new Map<String, Map<String, Pair>>();
        for (Gavel_Baseline__c b : rows) {
            QuestionReport q = r.questions.get(b.Question_Key__c);
            if (q == null) {
                q = new QuestionReport();
                q.questionKey = b.Question_Key__c;
                for (Integer i = 0; i < 10; i++) {
                    Band band = new Band();
                    band.lower = i / 10.0;
                    band.upper = (i + 1) / 10.0;
                    q.bands.add(band);
                }
                r.questions.put(b.Question_Key__c, q);
                pairs.put(b.Question_Key__c, new Map<String, Pair>());
            }
            q.sampleSize++;
            if (b.Would_Auto__c == true) {
                q.wouldAuto++;
            }
            if (b.Status__c == 'baseline_missing') {
                q.missing++;
                continue;
            }
            if (b.Status__c == 'circular') {
                q.circular++;
                continue;
            }
            Boolean agrees = b.Status__c == 'captured' && b.Agrees__c == true;
            if (b.Status__c == 'baseline_unmapped') {
                q.unmapped++;
                if (b.Baseline_Value__c != null && !q.unmappedValues.contains(b.Baseline_Value__c) && q.unmappedValues.size() < 20) {
                    q.unmappedValues.add(b.Baseline_Value__c);
                }
            }
            q.compared++;
            if (agrees) {
                q.agreed++;
            } else {
                String baselineLabel = b.Mapped_Option__c != null ? b.Mapped_Option__c : 'unmapped:' + b.Baseline_Value__c;
                String k = b.Gavel_Value__c + '->' + baselineLabel;
                Pair p = pairs.get(b.Question_Key__c).get(k);
                if (p == null) {
                    p = new Pair();
                    p.gavel = b.Gavel_Value__c;
                    p.baseline = baselineLabel;
                    pairs.get(b.Question_Key__c).put(k, p);
                }
                p.count++;
            }
            if (b.Calibration_Value__c != null) {
                Integer idx = Math.min(9, Math.max(0, Math.floor(b.Calibration_Value__c * 10).intValue()));
                q.bands[idx].n++;
                if (agrees) {
                    q.bands[idx].agree++;
                }
            }
        }
        for (QuestionReport q : r.questions.values()) {
            q.agreementRate = q.compared == 0 ? null : (Decimal.valueOf(q.agreed) / q.compared).setScale(4);
            q.wouldAutoShare = q.sampleSize == 0 ? null : (Decimal.valueOf(q.wouldAuto) / q.sampleSize).setScale(4);
            for (Band band : q.bands) {
                band.rate = band.n == 0 ? null : (Decimal.valueOf(band.agree) / band.n).setScale(4);
            }
            List<Pair> sorted = pairs.get(q.questionKey).values();
            sorted.sort();
            for (Integer i = 0; i < Math.min(5, sorted.size()); i++) {
                q.topDisagreements.add(sorted[i]);
            }
        }
        return r;
    }

    @AuraEnabled(cacheable=true)
    public static String reportJson(String definition) {
        return JSON.serialize(build(definition));
    }
}
