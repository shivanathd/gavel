/**
 * Loads decision definitions from Custom Metadata (ADR-004) into Gavel_Definition models.
 * Results are cached per transaction. Tests register in-memory definitions instead.
 */
public with sharing class Gavel_DefinitionRepo {
    @TestVisible
    private static Map<String, Gavel_Definition> overrides = new Map<String, Gavel_Definition>();
    private static Map<String, Gavel_Definition> cache = new Map<String, Gavel_Definition>();
    private static Set<String> missing = new Set<String>();

    /** Register an in-memory definition. Only allowed from tests. */
    public static void registerForTest(Gavel_Definition def) {
        if (!Test.isRunningTest()) {
            throw new GavelException('registerForTest is only available in Apex tests');
        }
        overrides.put(def.apiName, def);
    }

    public static void clearCache() {
        cache.clear();
        missing.clear();
    }

    public static Gavel_Definition get(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        return getAll(new Set<String>{ apiName }).get(apiName);
    }

    public static Map<String, Gavel_Definition> getAll(Set<String> apiNames) {
        Map<String, Gavel_Definition> result = new Map<String, Gavel_Definition>();
        Set<String> toLoad = new Set<String>();
        for (String n : apiNames) {
            if (n == null) {
                continue;
            }
            if (overrides.containsKey(n)) {
                result.put(n, overrides.get(n));
            } else if (cache.containsKey(n)) {
                result.put(n, cache.get(n));
            } else if (!missing.contains(n)) {
                toLoad.add(n);
            }
        }
        if (!toLoad.isEmpty()) {
            Map<String, Gavel_Definition> loaded = load(toLoad);
            for (String n : toLoad) {
                if (loaded.containsKey(n)) {
                    cache.put(n, loaded.get(n));
                    result.put(n, loaded.get(n));
                } else {
                    missing.add(n);
                }
            }
        }
        return result;
    }

    /** Every shipped definition API name (CMDT plus test overrides). */
    public static Set<String> allApiNames() {
        Set<String> names = new Set<String>(overrides.keySet());
        for (Gavel_Decision__mdt d : [SELECT DeveloperName FROM Gavel_Decision__mdt]) {
            names.add(d.DeveloperName);
        }
        return names;
    }

    /** Definitions whose target is the given SObject (used by feedback capture). */
    public static List<Gavel_Definition> forObject(String sobjectName) {
        Set<String> names = new Set<String>();
        for (Gavel_Definition d : overrides.values()) {
            if (d.targetObject != null && d.targetObject.equalsIgnoreCase(sobjectName)) {
                names.add(d.apiName);
            }
        }
        for (Gavel_Decision__mdt d : [SELECT DeveloperName FROM Gavel_Decision__mdt WHERE Target_Object__c = :sobjectName]) {
            names.add(d.DeveloperName);
        }
        return names.isEmpty() ? new List<Gavel_Definition>() : getAll(names).values();
    }

    private static Map<String, Gavel_Definition> load(Set<String> names) {
        Map<String, Gavel_Definition> defs = new Map<String, Gavel_Definition>();
        Set<String> configNames = new Set<String>();
        List<Gavel_Decision__mdt> rows = [
            SELECT DeveloperName, Target_Object__c, Version__c, Mode__c, Provider_Config__c, Description__c,
                Owner_Email__c, Daily_Budget_Calls__c, Definition_Hash__c, Pack__c, Review_Queue__c, Auto_Apply__c,
                Timeout_Ms__c
            FROM Gavel_Decision__mdt
            WHERE DeveloperName IN :names
        ];
        if (rows.isEmpty()) {
            return defs;
        }
        for (Gavel_Decision__mdt r : rows) {
            Gavel_Definition d = new Gavel_Definition();
            d.apiName = r.DeveloperName;
            d.targetObject = r.Target_Object__c;
            d.version = toInt(r.Version__c);
            d.mode = String.isBlank(r.Mode__c) ? Gavel_Definition.MODE_SHADOW : r.Mode__c;
            d.providerConfig = r.Provider_Config__c;
            d.description = r.Description__c;
            d.ownerEmail = r.Owner_Email__c;
            d.dailyBudgetCalls = r.Daily_Budget_Calls__c;
            d.definitionHash = r.Definition_Hash__c;
            d.pack = r.Pack__c;
            d.reviewQueue = r.Review_Queue__c;
            d.autoApply = r.Auto_Apply__c == true;
            d.timeoutMs = toInt(r.Timeout_Ms__c);
            defs.put(d.apiName, d);
            if (String.isNotBlank(r.Provider_Config__c)) {
                configNames.add(r.Provider_Config__c);
            }
        }

        Map<String, Gavel_Question> questionsByDevName = new Map<String, Gavel_Question>();
        for (Gavel_Question__mdt r : [
            SELECT DeveloperName, Decision__c, Key__c, Type__c, Prompt__c, Instructions__c, Order__c,
                Required_For_Action__c, Stage__c, Option_Source__c
            FROM Gavel_Question__mdt
            WHERE Decision__c IN :names
        ]) {
            Gavel_Definition d = defs.get(r.Decision__c);
            if (d == null) {
                continue;
            }
            Gavel_Question q = new Gavel_Question(r.Key__c, r.Type__c, r.Prompt__c);
            q.instructions = r.Instructions__c;
            q.sortOrder = toInt(r.Order__c);
            q.requiredForAction = r.Required_For_Action__c == true;
            q.stage = r.Stage__c;
            q.optionSource = r.Option_Source__c;
            q.developerName = r.DeveloperName;
            d.questions.add(q);
            questionsByDevName.put(r.DeveloperName, q);
        }

        if (!questionsByDevName.isEmpty()) {
            Set<String> qNames = questionsByDevName.keySet();
            for (Gavel_Option__mdt r : [
                SELECT Question__c, Key__c, Label__c, Description__c, Level__c, Is_Escape__c, Order__c
                FROM Gavel_Option__mdt
                WHERE Question__c IN :qNames
            ]) {
                Gavel_Question q = questionsByDevName.get(r.Question__c);
                if (q == null) {
                    continue;
                }
                Gavel_Option o = new Gavel_Option(r.Key__c, r.Label__c);
                o.description = r.Description__c;
                o.level = toInt(r.Level__c);
                o.isEscape = r.Is_Escape__c == true;
                o.sortOrder = toInt(r.Order__c);
                q.options.add(o);
            }
        }

        for (Gavel_State_Field__mdt r : [
            SELECT Decision__c, Field_Path__c, State_Key__c, Required__c, Max_Chars__c, Redaction_Profile__c,
                Zero_Is_Meaningful__c, Source__c, Order__c
            FROM Gavel_State_Field__mdt
            WHERE Decision__c IN :names
        ]) {
            Gavel_Definition d = defs.get(r.Decision__c);
            if (d == null) {
                continue;
            }
            Gavel_Definition.StateField sf = new Gavel_Definition.StateField(r.Field_Path__c, r.State_Key__c, r.Required__c == true);
            sf.maxChars = toInt(r.Max_Chars__c);
            sf.redactionProfile = r.Redaction_Profile__c;
            sf.zeroIsMeaningful = r.Zero_Is_Meaningful__c == true;
            sf.source = r.Source__c;
            sf.sortOrder = toInt(r.Order__c);
            d.stateFields.add(sf);
        }

        for (Gavel_Policy__mdt r : [
            SELECT Decision__c, Question_Key__c, Auto_Accept__c, Review_At__c, Min_Margin__c, Noul_Direction__c,
                Asymmetric_Reason__c
            FROM Gavel_Policy__mdt
            WHERE Decision__c IN :names
        ]) {
            Gavel_Definition d = defs.get(r.Decision__c);
            if (d == null) {
                continue;
            }
            Gavel_Definition.Policy p = new Gavel_Definition.Policy(r.Question_Key__c, r.Auto_Accept__c, r.Review_At__c, r.Min_Margin__c);
            p.noulDirection = r.Noul_Direction__c;
            p.asymmetricReason = r.Asymmetric_Reason__c;
            d.policies.add(p);
        }

        for (Gavel_Action_Map__mdt r : [
            SELECT Decision__c, Question_Key__c, Answer_Value__c, Action_Type__c, Action_Target__c, Action_Value__c
            FROM Gavel_Action_Map__mdt
            WHERE Decision__c IN :names
        ]) {
            Gavel_Definition d = defs.get(r.Decision__c);
            if (d == null) {
                continue;
            }
            d.actionMaps.add(new Gavel_Definition.ActionMap(r.Question_Key__c, r.Answer_Value__c, r.Action_Type__c, r.Action_Target__c, r.Action_Value__c));
        }

        if (!configNames.isEmpty()) {
            Map<String, Gavel_Provider_Config__mdt> configs = new Map<String, Gavel_Provider_Config__mdt>();
            for (Gavel_Provider_Config__mdt c : [
                SELECT DeveloperName, Provider_Class__c, Model__c, Named_Credential__c, Endpoint_Path__c, Timeout_Ms__c
                FROM Gavel_Provider_Config__mdt
                WHERE DeveloperName IN :configNames
            ]) {
                configs.put(c.DeveloperName, c);
            }
            for (Gavel_Definition d : defs.values()) {
                Gavel_Provider_Config__mdt c = configs.get(d.providerConfig);
                if (c == null) {
                    continue;
                }
                d.providerClass = c.Provider_Class__c;
                d.model = c.Model__c;
                d.namedCredential = c.Named_Credential__c;
                d.endpointPath = c.Endpoint_Path__c;
                if (d.timeoutMs == null) {
                    d.timeoutMs = toInt(c.Timeout_Ms__c);
                }
            }
        }
        for (Gavel_Definition d : defs.values()) {
            sortChildren(d);
        }
        return defs;
    }

    /** Deterministic order: explicit Order__c first, then key. */
    public static void sortChildren(Gavel_Definition d) {
        d.questions.sort(new QuestionOrder());
        for (Gavel_Question q : d.questions) {
            if (q.options != null) {
                q.options.sort(new OptionOrder());
            }
        }
        d.stateFields.sort(new StateFieldOrder());
    }

    private static Integer compareOrdered(Integer a, Integer b, String ka, String kb) {
        Integer x = a == null ? 2147483647 : a;
        Integer y = b == null ? 2147483647 : b;
        if (x != y) {
            return x < y ? -1 : 1;
        }
        String sa = ka == null ? '' : ka;
        String sb = kb == null ? '' : kb;
        return sa.compareTo(sb);
    }

    private class QuestionOrder implements System.Comparator<Gavel_Question> {
        public Integer compare(Gavel_Question a, Gavel_Question b) {
            return compareOrdered(a.sortOrder, b.sortOrder, a.key, b.key);
        }
    }

    private class OptionOrder implements System.Comparator<Gavel_Option> {
        public Integer compare(Gavel_Option a, Gavel_Option b) {
            Integer oa = a.sortOrder != null ? a.sortOrder : a.level;
            Integer ob = b.sortOrder != null ? b.sortOrder : b.level;
            return compareOrdered(oa, ob, a.key, b.key);
        }
    }

    private class StateFieldOrder implements System.Comparator<Gavel_Definition.StateField> {
        public Integer compare(Gavel_Definition.StateField a, Gavel_Definition.StateField b) {
            return compareOrdered(a.sortOrder, b.sortOrder, a.stateKey, b.stateKey);
        }
    }

    private static Integer toInt(Decimal v) {
        return v == null ? null : v.intValue();
    }

    public class GavelException extends Exception {
    }
}
