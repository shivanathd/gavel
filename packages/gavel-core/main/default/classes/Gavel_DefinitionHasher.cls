/**
 * Canonical hash of a definition and its children (ADR-009).
 * MUST stay byte-identical with scripts/hash-definitions.js (format "gavel-def-v1").
 *
 *   line   := tag ' ' field (';' field)*
 *   field  := name '=' length ':' value       (length in UTF-16 code units)
 *   strings are trimmed of chars <= U+0020, null -> ''
 *   numbers: minimal plain form (0.850 -> 0.85, 2.0 -> 2), null -> ''
 *   booleans: 'true' | 'false' (null -> 'false')
 * Children are sorted by length-prefixed keys so the order never depends on record names.
 */
public with sharing class Gavel_DefinitionHasher {
    private static final Lexical LEXICAL = new Lexical();

    /** Case-sensitive UTF-16 code unit order, same as JavaScript's default sort. */
    private class Lexical implements System.Comparator<String> {
        public Integer compare(String a, String b) {
            return a.compareTo(b);
        }
    }

    public static String compute(Gavel_Definition d) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(canonical(d))));
    }

    public static String canonical(Gavel_Definition d) {
        List<String> lines = new List<String>{ 'gavel-def-v1' };
        lines.add(rec('decision', new List<String>{
            'DeveloperName', str(d.apiName),
            'Target_Object__c', str(d.targetObject),
            'Version__c', num(d.version),
            'Provider_Config__c', str(d.providerConfig),
            'Model__c', str(d.model)
        }));

        Map<String, Gavel_Question> qByKey = new Map<String, Gavel_Question>();
        for (Gavel_Question q : d.questions) {
            qByKey.put(sortKey(new List<String>{ str(q.key) }), q);
        }
        List<String> qKeys = new List<String>(qByKey.keySet());
        qKeys.sort(LEXICAL);
        for (String k : qKeys) {
            Gavel_Question q = qByKey.get(k);
            List<String> qPairs = new List<String>{
                'Key__c', str(q.key),
                'Type__c', str(q.questionType),
                'Prompt__c', str(q.prompt),
                'Instructions__c', str(q.instructions),
                'Order__c', num(q.sortOrder),
                'Required_For_Action__c', bool(q.requiredForAction),
                'Stage__c', str(q.stage),
                'Option_Source__c', str(q.optionSource)
            };
            // Added in 1.2.1: hashed only when set, so definitions without a gate keep their hash.
            if (String.isNotBlank(q.boxGate)) {
                qPairs.addAll(new List<String>{ 'Box_Gate__c', str(q.boxGate) });
            }
            lines.add(rec('question', qPairs));
            Map<String, Gavel_Option> oByKey = new Map<String, Gavel_Option>();
            if (q.options != null) {
                for (Gavel_Option o : q.options) {
                    oByKey.put(sortKey(new List<String>{ str(o.key) }), o);
                }
            }
            List<String> oKeys = new List<String>(oByKey.keySet());
            oKeys.sort(LEXICAL);
            for (String ok : oKeys) {
                Gavel_Option o = oByKey.get(ok);
                lines.add(rec('option', new List<String>{
                    'Question_Key__c', str(q.key),
                    'Key__c', str(o.key),
                    'Label__c', str(o.label),
                    'Description__c', str(o.description),
                    'Level__c', num(o.level),
                    'Is_Escape__c', bool(o.isEscape),
                    'Order__c', num(o.sortOrder)
                }));
            }
        }

        Map<String, Gavel_Definition.StateField> sfByKey = new Map<String, Gavel_Definition.StateField>();
        for (Gavel_Definition.StateField sf : d.stateFields) {
            sfByKey.put(sortKey(new List<String>{ str(sf.stateKey), str(sf.fieldPath) }), sf);
        }
        List<String> sfKeys = new List<String>(sfByKey.keySet());
        sfKeys.sort(LEXICAL);
        for (String k : sfKeys) {
            Gavel_Definition.StateField sf = sfByKey.get(k);
            lines.add(rec('state', new List<String>{
                'Field_Path__c', str(sf.fieldPath),
                'State_Key__c', str(sf.stateKey),
                'Required__c', bool(sf.required),
                'Max_Chars__c', num(sf.maxChars),
                'Redaction_Profile__c', str(sf.redactionProfile),
                'Zero_Is_Meaningful__c', bool(sf.zeroIsMeaningful),
                'Source__c', str(sf.source),
                'Order__c', num(sf.sortOrder)
            }));
        }

        Map<String, Gavel_Definition.Policy> pByKey = new Map<String, Gavel_Definition.Policy>();
        for (Gavel_Definition.Policy p : d.policies) {
            pByKey.put(sortKey(new List<String>{ str(p.questionKey) }), p);
        }
        List<String> pKeys = new List<String>(pByKey.keySet());
        pKeys.sort(LEXICAL);
        for (String k : pKeys) {
            Gavel_Definition.Policy p = pByKey.get(k);
            lines.add(rec('policy', new List<String>{
                'Question_Key__c', str(p.questionKey),
                'Auto_Accept__c', num(p.autoAccept),
                'Review_At__c', num(p.reviewAt),
                'Min_Margin__c', num(p.minMargin),
                'Noul_Direction__c', str(p.noulDirection),
                'Asymmetric_Reason__c', str(p.asymmetricReason)
            }));
        }

        Map<String, Gavel_Definition.ActionMap> aByKey = new Map<String, Gavel_Definition.ActionMap>();
        for (Gavel_Definition.ActionMap a : d.actionMaps) {
            aByKey.put(sortKey(new List<String>{ str(a.questionKey), str(a.answerValue), str(a.actionType), str(a.actionTarget), str(a.actionValue) }), a);
        }
        List<String> aKeys = new List<String>(aByKey.keySet());
        aKeys.sort(LEXICAL);
        for (String k : aKeys) {
            Gavel_Definition.ActionMap a = aByKey.get(k);
            lines.add(rec('action', new List<String>{
                'Question_Key__c', str(a.questionKey),
                'Answer_Value__c', str(a.answerValue),
                'Action_Type__c', str(a.actionType),
                'Action_Target__c', str(a.actionTarget),
                'Action_Value__c', str(a.actionValue)
            }));
        }
        return String.join(lines, '\n');
    }

    private static String rec(String tag, List<String> pairs) {
        List<String> parts = new List<String>();
        for (Integer i = 0; i < pairs.size(); i += 2) {
            String v = pairs[i + 1];
            parts.add(pairs[i] + '=' + v.length() + ':' + v);
        }
        return tag + ' ' + String.join(parts, ';');
    }

    private static String sortKey(List<String> values) {
        List<String> parts = new List<String>();
        for (String v : values) {
            parts.add(v.length() + ':' + v);
        }
        return String.join(parts, ';');
    }

    @TestVisible
    private static String str(String v) {
        return v == null ? '' : v.trim();
    }

    @TestVisible
    private static String num(Decimal v) {
        if (v == null) {
            return '';
        }
        if (v == 0) {
            return '0';
        }
        return v.stripTrailingZeros().toPlainString();
    }

    private static String num(Integer v) {
        return v == null ? '' : String.valueOf(v);
    }

    private static String bool(Boolean v) {
        return v == true ? 'true' : 'false';
    }
}
