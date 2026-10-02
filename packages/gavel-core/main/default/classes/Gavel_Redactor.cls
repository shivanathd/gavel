/**
 * Pattern redaction before any text leaves the org (STATE-001.3). Best-effort, not DLP.
 * Matches become [REDACTED:<type>]; callers only ever see type counts, never matched values.
 *
 * Profiles: none | pii_basic (email, phone) | payment (Luhn-valid PAN, CVV) |
 *           gov_id (US SSN, India Aadhaar and PAN) | strict (all). Unknown or blank profile = strict.
 */
public with sharing class Gavel_Redactor {
    public static final String T_PAYMENT = 'payment';
    public static final String T_GOV_ID = 'gov_id';
    public static final String T_EMAIL = 'email';
    public static final String T_PHONE = 'phone';

    private static final Pattern CARD = Pattern.compile('(?<![0-9])(?:[0-9][ \\-]?){12,18}[0-9](?![0-9])');
    private static final Pattern CVV = Pattern.compile('(?i)\\b(?:cvv2?|cvc2?|cid|csc|security code)\\s*[:#=]?\\s*[0-9]{3,4}\\b');
    private static final Pattern SSN = Pattern.compile('(?<![0-9])[0-9]{3}-[0-9]{2}-[0-9]{4}(?![0-9])');
    private static final Pattern SSN_LABELED = Pattern.compile('(?i)\\b(?:ssn|social security(?: number)?)\\s*[:#]?\\s*[0-9]{9}\\b');
    private static final Pattern AADHAAR = Pattern.compile('(?<![0-9])[2-9][0-9]{3}[ \\-]?[0-9]{4}[ \\-]?[0-9]{4}(?![0-9])');
    private static final Pattern IN_PAN = Pattern.compile('\\b[A-Z]{5}[0-9]{4}[A-Z]\\b');
    private static final Pattern EMAIL = Pattern.compile('[A-Za-z0-9._%+\\-]+@[A-Za-z0-9\\-]+(?:\\.[A-Za-z0-9\\-]+)*\\.[A-Za-z]{2,}');
    private static final Pattern PHONE = Pattern.compile('(?<![A-Za-z0-9_])(?:\\+?[0-9]{1,3}[ .\\-]?)?(?:\\([0-9]{1,4}\\)[ .\\-]?)?[0-9]{2,5}(?:[ .\\-]?[0-9]{2,5}){1,4}(?![A-Za-z0-9_])');

    public class Result {
        public String text;
        public Map<String, Integer> counts = new Map<String, Integer>();

        public Integer total() {
            Integer n = 0;
            for (Integer c : counts.values()) {
                n += c;
            }
            return n;
        }
    }

    private interface Check {
        Boolean accept(String match);
    }

    private class Always implements Check {
        public Boolean accept(String match) {
            return true;
        }
    }

    private class Luhn implements Check {
        public Boolean accept(String match) {
            String digits = match.replaceAll('[^0-9]', '');
            return digits.length() >= 13 && digits.length() <= 19 && luhnValid(digits);
        }
    }

    private class PhoneDigits implements Check {
        public Boolean accept(String match) {
            Integer n = match.replaceAll('[^0-9]', '').length();
            return n >= 9 && n <= 15;
        }
    }

    public static String normalizeProfile(String profile) {
        if (profile == 'none' || profile == 'pii_basic' || profile == 'payment' || profile == 'gov_id' || profile == 'strict') {
            return profile.toLowerCase();
        }
        return 'strict';
    }

    public static Result redact(String text, String profile) {
        Result r = new Result();
        r.text = text;
        if (String.isEmpty(text)) {
            return r;
        }
        String p = normalizeProfile(profile);
        Boolean pay = p == 'payment' || p == 'strict';
        Boolean gov = p == 'gov_id' || p == 'strict';
        Boolean pii = p == 'pii_basic' || p == 'strict';
        if (pay) {
            apply(r, CARD, T_PAYMENT, new Luhn());
            apply(r, CVV, T_PAYMENT, new Always());
        }
        if (gov) {
            apply(r, SSN, T_GOV_ID, new Always());
            apply(r, SSN_LABELED, T_GOV_ID, new Always());
            apply(r, AADHAAR, T_GOV_ID, new Always());
            apply(r, IN_PAN, T_GOV_ID, new Always());
        }
        if (pii) {
            apply(r, EMAIL, T_EMAIL, new Always());
            apply(r, PHONE, T_PHONE, new PhoneDigits());
        }
        return r;
    }

    private static void apply(Result r, Pattern pat, String kind, Check check) {
        Matcher m = pat.matcher(r.text);
        List<Integer> starts = new List<Integer>();
        List<Integer> ends = new List<Integer>();
        while (m.find()) {
            if (check.accept(m.group())) {
                starts.add(m.start());
                ends.add(m.end());
            }
        }
        if (starts.isEmpty()) {
            return;
        }
        String placeholder = '[REDACTED:' + kind + ']';
        List<String> parts = new List<String>();
        Integer cursor = 0;
        for (Integer i = 0; i < starts.size(); i++) {
            parts.add(r.text.substring(cursor, starts[i]));
            parts.add(placeholder);
            cursor = ends[i];
        }
        parts.add(r.text.substring(cursor));
        r.text = String.join(parts, '');
        Integer prior = r.counts.containsKey(kind) ? r.counts.get(kind) : 0;
        r.counts.put(kind, prior + starts.size());
    }

    public static Boolean luhnValid(String digits) {
        Integer sum = 0;
        Boolean doubleIt = false;
        for (Integer i = digits.length() - 1; i >= 0; i--) {
            Integer d = Integer.valueOf(digits.substring(i, i + 1));
            if (doubleIt) {
                d *= 2;
                if (d > 9) {
                    d -= 9;
                }
            }
            sum += d;
            doubleIt = !doubleIt;
        }
        return Math.mod(sum, 10) == 0;
    }
}
