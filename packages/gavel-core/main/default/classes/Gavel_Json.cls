/**
 * Canonical JSON: keys sorted (UTF-16 code unit order), no whitespace, UTF-8 when hashed.
 * Used for state (contracts/state-contract.md) and ledger hashing.
 */
public with sharing class Gavel_Json {
    private static final Lexical LEXICAL = new Lexical();

    private class Lexical implements System.Comparator<String> {
        public Integer compare(String a, String b) {
            return a.compareTo(b);
        }
    }

    public static String canonical(Object value) {
        return write(normalize(value));
    }

    public static String sha256Hex(String text) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(text == null ? '' : text)));
    }

    private static Object normalize(Object value) {
        if (value == null || value instanceof String || value instanceof Boolean || value instanceof Decimal ||
            value instanceof Integer || value instanceof Long || value instanceof Double) {
            return value;
        }
        // Typed collections (Map<String,Decimal>, List<String>, ...) become untyped maps and lists.
        return JSON.deserializeUntyped(JSON.serialize(value));
    }

    private static String write(Object v) {
        if (v == null) {
            return 'null';
        }
        if (v instanceof String) {
            return JSON.serialize((String) v);
        }
        if (v instanceof Boolean) {
            return ((Boolean) v) ? 'true' : 'false';
        }
        if (v instanceof Decimal || v instanceof Integer || v instanceof Long || v instanceof Double) {
            return JSON.serialize(v);
        }
        if (v instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) v;
            List<String> keys = new List<String>(m.keySet());
            keys.sort(LEXICAL);
            List<String> parts = new List<String>();
            for (String k : keys) {
                parts.add(JSON.serialize(k) + ':' + write(m.get(k)));
            }
            return '{' + String.join(parts, ',') + '}';
        }
        if (v instanceof List<Object>) {
            List<String> parts = new List<String>();
            for (Object o : (List<Object>) v) {
                parts.add(write(o));
            }
            return '[' + String.join(parts, ',') + ']';
        }
        return JSON.serialize(v);
    }
}
