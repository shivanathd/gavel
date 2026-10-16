/**
 * Loads Gavel_Baseline_Map__mdt rows per definition. Tests register in-memory maps.
 */
public with sharing class Gavel_BaselineMapRepo {
    public class Entry {
        public String definition;
        public String questionKey;
        public String baselineField;
        public String baselineValue;
        public String optionKey;

        public Entry(String definition, String questionKey, String baselineField, String baselineValue, String optionKey) {
            this.definition = definition;
            this.questionKey = questionKey;
            this.baselineField = baselineField;
            this.baselineValue = baselineValue;
            this.optionKey = optionKey;
        }

        /** Field name on the target record ("Case.Type" -> "Type"). */
        public String fieldName() {
            return baselineField != null && baselineField.contains('.') ? baselineField.substringAfter('.') : baselineField;
        }
    }

    @TestVisible
    private static Map<String, List<Entry>> overrides = new Map<String, List<Entry>>();
    private static Map<String, List<Entry>> cache;

    public static void registerForTest(List<Entry> entries) {
        if (!Test.isRunningTest()) {
            throw new IllegalArgumentException('registerForTest is only available in Apex tests');
        }
        for (Entry e : entries) {
            if (!overrides.containsKey(e.definition)) {
                overrides.put(e.definition, new List<Entry>());
            }
            overrides.get(e.definition).add(e);
        }
    }

    public static Map<String, List<Entry>> all() {
        if (cache == null) {
            cache = new Map<String, List<Entry>>();
            for (Gavel_Baseline_Map__mdt r : [
                SELECT Decision__c, Question_Key__c, Baseline_Field__c, Baseline_Value__c, Option_Key__c
                FROM Gavel_Baseline_Map__mdt WITH SYSTEM_MODE
            ]) {
                if (!cache.containsKey(r.Decision__c)) {
                    cache.put(r.Decision__c, new List<Entry>());
                }
                cache.get(r.Decision__c).add(new Entry(r.Decision__c, r.Question_Key__c, r.Baseline_Field__c, r.Baseline_Value__c, r.Option_Key__c));
            }
        }
        Map<String, List<Entry>> result = new Map<String, List<Entry>>(cache);
        result.putAll(overrides);
        return result;
    }

    public static List<Entry> forDefinition(String definition) {
        List<Entry> e = all().get(definition);
        return e == null ? new List<Entry>() : e;
    }

    /** question key -> baseline field (first map wins). */
    public static Map<String, String> fieldsByQuestion(String definition) {
        Map<String, String> result = new Map<String, String>();
        for (Entry e : forDefinition(definition)) {
            if (!result.containsKey(e.questionKey)) {
                result.put(e.questionKey, e.fieldName());
            }
        }
        return result;
    }

    /** Maps a baseline value to an option key, or null when unmapped. Comparison ignores case and spaces. */
    public static String mapValue(String definition, String questionKey, String value) {
        if (value == null) {
            return null;
        }
        String v = value.trim();
        for (Entry e : forDefinition(definition)) {
            if (e.questionKey == questionKey && e.baselineValue != null && e.baselineValue.trim().equalsIgnoreCase(v)) {
                return e.optionKey;
            }
        }
        return null;
    }
}
