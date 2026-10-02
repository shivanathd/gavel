@IsTest
private class Gavel_Redaction_Test {
    private class Fixture {
        public String kind;
        public String token;

        public Fixture(String kind, String token) {
            this.kind = kind;
            this.token = token;
        }
    }

    private static String pad(Integer i, Integer n) {
        return String.valueOf(i).leftPad(n, '0');
    }

    private static String luhnComplete(String prefix) {
        for (Integer d = 0; d < 10; d++) {
            if (Gavel_Redactor.luhnValid(prefix + d)) {
                return prefix + d;
            }
        }
        return null;
    }

    private static String grouped(String num, String sep) {
        List<String> parts = new List<String>();
        for (Integer j = 0; j < num.length(); j += 4) {
            parts.add(num.substring(j, Math.min(j + 4, num.length())));
        }
        return String.join(parts, sep);
    }

    /** 200 synthetic PII strings (STATE-001 compliance fixture). */
    private static List<Fixture> corpus() {
        List<Fixture> fx = new List<Fixture>();
        for (Integer i = 0; i < 40; i++) {
            List<String> v = new List<String>{
                'first.last+' + i + '@mail-' + i + '.co.uk', 'user' + i + '@example.com', 'a_b' + i + '@sub.domain' + i + '.io', 'X' + i + '@corp.org'
            };
            fx.add(new Fixture('email', v[Math.mod(i, 4)]));
        }
        for (Integer i = 0; i < 40; i++) {
            List<String> v = new List<String>{
                '+1 (415) 555-' + pad(i, 4), '415-555-' + pad(100 + i, 4), '+44 20 7946 ' + pad(i, 4), '+91 98765 ' + pad(43210 + i, 5),
                '(212) 555 ' + pad(i, 4), '4155550' + pad(i, 3), '+1.646.555.' + pad(i, 4), 'call +61 2 9374 ' + pad(4000 + i, 4)
            };
            fx.add(new Fixture('phone', v[Math.mod(i, 8)]));
        }
        for (Integer i = 0; i < 40; i++) {
            List<String> bases = new List<String>{ '4111111111' + pad(i, 5), '550000000' + pad(i, 6), '37828224' + pad(i, 6), '601100000' + pad(i, 6) };
            String num = luhnComplete(bases[Math.mod(i, 4)]);
            Integer fmt = Math.mod(i, 3);
            fx.add(new Fixture('payment', fmt == 0 ? num : grouped(num, fmt == 1 ? ' ' : '-')));
        }
        for (Integer i = 0; i < 30; i++) {
            fx.add(new Fixture('gov_id', Math.mod(i, 2) == 0
                ? pad(100 + i, 3) + '-' + pad(10 + i, 2) + '-' + pad(1000 + i * 7, 4)
                : 'SSN: ' + pad(100 + i, 3) + pad(10 + i, 2) + pad(1000 + i, 4)));
        }
        for (Integer i = 0; i < 25; i++) {
            Integer first = 2 + Math.mod(i, 8);
            fx.add(new Fixture('gov_id', Math.mod(i, 2) == 0
                ? String.valueOf(first) + pad(345 + i, 3) + ' 6789 ' + pad(1000 + i, 4)
                : String.valueOf(first) + pad(111 + i, 3) + '-2222-' + pad(3000 + i, 4)));
        }
        String letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        for (Integer i = 0; i < 15; i++) {
            fx.add(new Fixture('gov_id', letters.substring(i, i + 1) + 'BCDE' + pad(1000 + i, 4) + letters.substring(25 - i, 26 - i)));
        }
        for (Integer i = 0; i < 10; i++) {
            fx.add(new Fixture('payment', Math.mod(i, 2) == 0 ? 'CVV: ' + pad(100 + i, 3) : 'cvc2 ' + pad(200 + i, 4)));
        }
        return fx;
    }

    @IsTest
    static void strictRedactsAllTwoHundred() {
        List<Fixture> fx = corpus();
        Assert.areEqual(200, fx.size());
        Integer failures = 0;
        List<String> failed = new List<String>();
        for (Fixture f : fx) {
            String text = 'Hi team, reach me with ' + f.token + ' before Friday. Thanks!';
            Gavel_Redactor.Result r = Gavel_Redactor.redact(text, 'strict');
            String digits = f.token.replaceAll('[^0-9]', '');
            Boolean leaked = r.text.contains(f.token) || (digits.length() >= 6 && r.text.replaceAll('[^0-9]', '').contains(digits));
            if (leaked || !r.counts.containsKey(f.kind)) {
                failures++;
                failed.add(f.kind);
            }
        }
        Assert.areEqual(0, failures, '100% redaction required for strict; failed types: ' + failed);
    }

    @IsTest
    static void luhnGatesPayment() {
        Gavel_Redactor.Result valid = Gavel_Redactor.redact('card 4111 1111 1111 1111 ok', 'payment');
        Assert.areEqual('card [REDACTED:payment] ok', valid.text);
        Assert.areEqual(1, valid.counts.get('payment'));
        Gavel_Redactor.Result invalid = Gavel_Redactor.redact('ref 4111 1111 1111 1112 ok', 'payment');
        Assert.areEqual('ref 4111 1111 1111 1112 ok', invalid.text, '16 digits failing Luhn are not payment');
        Assert.isTrue(invalid.counts.isEmpty());
    }

    @IsTest
    static void profilesAreScoped() {
        String text = 'mail jo@x.com, call 415-555-0100, pan ABCDE1234F, card 4111111111111111';
        Gavel_Redactor.Result none = Gavel_Redactor.redact(text, 'none');
        Assert.areEqual(text, none.text);
        Gavel_Redactor.Result pii = Gavel_Redactor.redact(text, 'pii_basic');
        Assert.isFalse(pii.text.contains('jo@x.com'));
        Assert.isFalse(pii.text.contains('415-555-0100'));
        Assert.isTrue(pii.text.contains('ABCDE1234F'), 'pii_basic does not cover gov ids');
        Gavel_Redactor.Result gov = Gavel_Redactor.redact(text, 'gov_id');
        Assert.isFalse(gov.text.contains('ABCDE1234F'));
        Assert.isTrue(gov.text.contains('jo@x.com'));
        Gavel_Redactor.Result strict = Gavel_Redactor.redact(text, null);
        Assert.areEqual(4, strict.total(), 'blank profile defaults to strict: ' + strict.counts);
        Assert.areEqual('strict', Gavel_Redactor.normalizeProfile('weird'));
    }

    @IsTest
    static void phoneInsideUrlAndDatesUntouched() {
        Gavel_Redactor.Result url = Gavel_Redactor.redact('see https://example.com/call/+14155550100 now', 'pii_basic');
        Assert.areEqual('see https://example.com/call/[REDACTED:phone] now', url.text);
        Gavel_Redactor.Result dates = Gavel_Redactor.redact('Order dated 2026-10-01 for $1,250.00, ticket 42', 'strict');
        Assert.areEqual('Order dated 2026-10-01 for $1,250.00, ticket 42', dates.text);
        Assert.areEqual(0, dates.total());
        Assert.isNull(Gavel_Redactor.redact(null, 'strict').text);
    }
}
