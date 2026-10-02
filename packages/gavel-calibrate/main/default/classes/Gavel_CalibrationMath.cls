/**
 * Calibration math (CAL-001.4/.6): reliability table in 0.1 bins, precision and coverage at candidate
 * thresholds 0.50..0.95 (step 0.05), the recommended Auto_Accept__c (lowest threshold meeting the target
 * precision, which maximizes coverage), and a Wilson 95% interval:
 *   (p + z^2/2n +/- z*sqrt(p(1-p)/n + z^2/4n^2)) / (1 + z^2/n), z = 1.96
 */
public with sharing class Gavel_CalibrationMath {
    public static final Decimal Z = 1.96;
    public static final Integer LOW_SAMPLE = 50;

    public class Point {
        public Decimal value;
        public Boolean correct;

        public Point(Decimal value, Boolean correct) {
            this.value = value;
            this.correct = correct;
        }
    }

    public class Bin {
        public Decimal lower;
        public Decimal upper;
        public Integer n = 0;
        public Integer correct = 0;
        public Decimal observed;
        public Boolean lowSample = true;
    }

    public class Candidate {
        public Decimal threshold;
        public Integer covered = 0;
        public Integer correct = 0;
        public Decimal precision;
        public Decimal coverage;
    }

    public class Interval {
        public Decimal lower;
        public Decimal upper;
    }

    public class QuestionCalibration {
        public String questionKey;
        public Integer n = 0;
        public List<Bin> reliability = new List<Bin>();
        public List<Candidate> candidates = new List<Candidate>();
        /** recommended | none_meets_target | insufficient_data */
        public String status;
        public Decimal recommended;
        public Decimal precision;
        public Decimal coverage;
        public Interval wilson;
    }

    public static QuestionCalibration calibrate(String questionKey, List<Point> points, Decimal targetPrecision) {
        QuestionCalibration qc = new QuestionCalibration();
        qc.questionKey = questionKey;
        qc.n = points.size();
        for (Integer i = 0; i < 10; i++) {
            Bin b = new Bin();
            b.lower = i / 10.0;
            b.upper = (i + 1) / 10.0;
            qc.reliability.add(b);
        }
        for (Point p : points) {
            Integer idx = Math.min(9, Math.max(0, Math.floor(p.value * 10).intValue()));
            qc.reliability[idx].n++;
            if (p.correct) {
                qc.reliability[idx].correct++;
            }
        }
        for (Bin b : qc.reliability) {
            b.observed = b.n == 0 ? null : ratio(b.correct, b.n);
            b.lowSample = b.n < LOW_SAMPLE;
        }
        for (Integer i = 0; i < 10; i++) {
            Candidate c = new Candidate();
            c.threshold = 0.50 + 0.05 * i;
            for (Point p : points) {
                if (p.value >= c.threshold) {
                    c.covered++;
                    if (p.correct) {
                        c.correct++;
                    }
                }
            }
            c.precision = c.covered == 0 ? null : ratio(c.correct, c.covered);
            c.coverage = qc.n == 0 ? null : ratio(c.covered, qc.n);
            qc.candidates.add(c);
        }
        if (qc.n == 0) {
            qc.status = 'insufficient_data';
            return qc;
        }
        qc.status = 'none_meets_target';
        for (Candidate c : qc.candidates) {
            if (c.precision != null && c.precision >= targetPrecision) {
                qc.status = 'recommended';
                qc.recommended = c.threshold.setScale(2);
                qc.precision = c.precision;
                qc.coverage = c.coverage;
                qc.wilson = wilson(c.correct, c.covered);
                break;
            }
        }
        return qc;
    }

    public static Interval wilson(Integer successes, Integer n) {
        Interval iv = new Interval();
        if (n == null || n == 0) {
            return iv;
        }
        Double s = successes;
        Double nd = n;
        Double p = s / nd;
        Double zd = Z.doubleValue();
        Double z2 = zd * zd;
        Double one = 1;
        Double denom = one + z2 / nd;
        Double center = (p + z2 / (2 * nd)) / denom;
        Double half = zd * Math.sqrt(p * (one - p) / nd + z2 / (4 * nd * nd)) / denom;
        iv.lower = Decimal.valueOf(Math.max(one - one, center - half)).setScale(4);
        iv.upper = Decimal.valueOf(Math.min(one, center + half)).setScale(4);
        return iv;
    }

    private static Decimal ratio(Integer a, Integer b) {
        return (Decimal.valueOf(a) / b).setScale(4);
    }
}
