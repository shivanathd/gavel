/**
 * Builds the only data that may leave the org for a decision (F3, contracts/state-contract.md).
 *  - kill switch first (STATE-001.9)
 *  - only Gavel_State_Field__mdt paths (STATE-001.1), read WITH USER_MODE then stripInaccessible (STATE-001.2)
 *  - redaction before serialization, default profile strict (STATE-001.3/.4)
 *  - truncation at Max_Chars__c (default 2,000) with a [truncated] marker (STATE-001.7)
 *  - canonical JSON keyed by State_Key__c; stateHash = SHA-256 hex (STATE-001.5/.6)
 *  - images (Gavel_ImageAsset) appear in state as content-addressed references; their bytes go only in the
 *    request, never into the ledger, and cannot be redacted
 */
public with sharing class Gavel_StateBuilder {
    public static final Integer DEFAULT_MAX_CHARS = 2000;
    public static final String TRUNCATED_MARKER = ' [truncated]';

    public static final String EGRESS_DISABLED = 'egress_disabled';
    public static final String RECORD_NOT_FOUND = 'record_not_found';
    public static final String BAD_FIELD_PATH = 'bad_field_path';
    public static final String INSUFFICIENT_STATE = 'insufficient_state';
    /** Two image fields resolved to the same file: comparing a photo with itself proves nothing. */
    public static final String DUPLICATE_IMAGE = 'duplicate_image';

    public class StateResult {
        public Map<String, Object> state = new Map<String, Object>();
        public String stateJson;
        public String stateHash;
        public Boolean truncated = false;
        public List<String> redactionsApplied = new List<String>();
        public List<String> missingRequired = new List<String>();
        /** Set when the run must not call the provider: egress_disabled | record_not_found | bad_field_path | insufficient_state. */
        public String blockedReason;
        public List<String> badPaths = new List<String>();
        /** Images from state sources; state holds their references, the request sends the bytes. */
        public List<Gavel_ImageAsset> assets = new List<Gavel_ImageAsset>();
        public Boolean duplicateImage = false;

        public String redactionSummary() {
            return String.join(redactionsApplied, ',');
        }
    }

    private class FieldRef {
        public Gavel_Definition.StateField sf;
        public String relationship; // null for a field on the target
        public String fieldName;
        public Schema.DescribeFieldResult describe;
        public Boolean accessible = false;
    }

    private static Map<String, Map<String, Schema.SObjectField>> fieldMaps = new Map<String, Map<String, Schema.SObjectField>>();

    public static StateResult build(Id recordId, Gavel_Definition def) {
        return build(recordId, def, null);
    }

    public static StateResult build(Id recordId, Gavel_Definition def, Map<String, Object> inputs) {
        StateResult result = new StateResult();
        if (!Gavel_Config.ops().egressEnabled) {
            result.blockedReason = EGRESS_DISABLED;
            return result;
        }
        Map<String, Integer> redactionCounts = new Map<String, Integer>();
        List<FieldRef> direct = new List<FieldRef>();
        List<Gavel_Definition.StateField> sourced = new List<Gavel_Definition.StateField>();
        for (Gavel_Definition.StateField sf : def.stateFields) {
            if (String.isNotBlank(sf.source)) {
                sourced.add(sf);
            } else {
                FieldRef ref = resolve(def.targetObject, sf);
                if (ref == null) {
                    result.badPaths.add(sf.fieldPath);
                } else {
                    direct.add(ref);
                }
            }
        }
        if (!result.badPaths.isEmpty()) {
            result.blockedReason = BAD_FIELD_PATH;
            return result;
        }

        SObject row = null;
        if (def.hasTargetRecord()) {
            if (recordId == null) {
                result.blockedReason = RECORD_NOT_FOUND;
                return result;
            }
            List<String> selects = new List<String>{ 'Id' };
            for (FieldRef ref : direct) {
                if (ref.accessible) {
                    String path = ref.relationship == null ? ref.fieldName : ref.relationship + '.' + ref.fieldName;
                    if (!selects.contains(path)) {
                        selects.add(path);
                    }
                }
            }
            List<SObject> rows;
            try {
                rows = Database.queryWithBinds(
                    'SELECT ' + String.join(selects, ', ') + ' FROM ' + def.targetObject + ' WHERE Id = :rid LIMIT 1',
                    new Map<String, Object>{ 'rid' => recordId },
                    AccessLevel.USER_MODE
                );
            } catch (QueryException e) {
                // No object access in user mode: treat every value as unreadable.
                rows = null;
            }
            if (rows != null) {
                if (rows.isEmpty()) {
                    result.blockedReason = RECORD_NOT_FOUND;
                    return result;
                }
                row = Security.stripInaccessible(AccessType.READABLE, rows).getRecords()[0];
            }
        }

        Map<String, Object> values = new Map<String, Object>();
        for (FieldRef ref : direct) {
            Object raw = null;
            if (row != null && ref.accessible) {
                try {
                    raw = readValue(row, ref);
                } catch (SObjectException e) {
                    raw = null;
                }
            }
            Object v = normalize(raw, ref.sf, ref.describe, redactionCounts, result);
            if (v != null) {
                values.put(ref.sf.stateKey, v);
            }
        }
        String sourceSkip = null;
        for (Gavel_Definition.StateField sf : sourced) {
            Object raw = null;
            try {
                raw = runSource(sf, recordId, def.targetObject, inputs);
            } catch (Gavel_SkipException e) {
                sourceSkip = sourceSkip == null ? e.getMessage() : sourceSkip; // e.g. image_too_large
            } catch (Exception e) {
                raw = null; // fail closed: drop the field
            }
            Object v = normalize(raw, sf, null, redactionCounts, result);
            if (v != null) {
                values.put(sf.stateKey, v);
            }
        }
        for (Gavel_Definition.StateField sf : def.stateFields) {
            if (sf.required == true && !values.containsKey(sf.stateKey)) {
                result.missingRequired.add(sf.stateKey);
            }
        }
        List<String> types = new List<String>(redactionCounts.keySet());
        types.sort();
        for (String t : types) {
            result.redactionsApplied.add(t + ':' + redactionCounts.get(t));
        }
        result.state = values;
        result.stateJson = Gavel_Json.canonical(values);
        result.stateHash = Gavel_Json.sha256Hex(result.stateJson);
        if (!result.missingRequired.isEmpty()) {
            result.blockedReason = sourceSkip == null ? INSUFFICIENT_STATE : sourceSkip;
        } else if (result.duplicateImage) {
            result.blockedReason = DUPLICATE_IMAGE;
        }
        return result;
    }

    private static Object runSource(Gavel_Definition.StateField sf, Id recordId, String targetObject, Map<String, Object> inputs) {
        String className = sf.source.substringBefore(':').trim();
        String arg = sf.source.contains(':') ? sf.source.substringAfter(':').trim() : null;
        Type t = Type.forName(className);
        if (t == null) {
            return null;
        }
        Object instance = t.newInstance();
        if (!(instance instanceof Gavel_StateSource)) {
            return null;
        }
        Gavel_StateContext ctx = new Gavel_StateContext();
        ctx.recordId = recordId;
        ctx.targetObject = targetObject;
        ctx.fieldPath = sf.fieldPath;
        ctx.arg = arg;
        ctx.maxChars = sf.maxChars;
        if (inputs != null) {
            ctx.inputs = inputs;
        }
        return ((Gavel_StateSource) instance).resolve(ctx);
    }

    /** Null contract: null/blank omitted; 0 omitted unless Zero_Is_Meaningful__c; text redacted then truncated. */
    private static Object normalize(Object raw, Gavel_Definition.StateField sf, Schema.DescribeFieldResult describe,
        Map<String, Integer> counts, StateResult result) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof Gavel_ImageAsset) {
            Gavel_ImageAsset img = (Gavel_ImageAsset) raw;
            Boolean seen = false;
            for (Gavel_ImageAsset a : result.assets) {
                seen = seen || a.reference == img.reference;
            }
            if (seen) {
                result.duplicateImage = true;
            } else {
                result.assets.add(img);
            }
            return img.reference;
        }
        if (raw instanceof Decimal || raw instanceof Integer || raw instanceof Long || raw instanceof Double) {
            Decimal d = raw instanceof Decimal ? (Decimal) raw : Decimal.valueOf(String.valueOf(raw));
            if (d == 0 && sf.zeroIsMeaningful != true) {
                return null;
            }
            return d;
        }
        if (raw instanceof Boolean) {
            return raw;
        }
        String text;
        if (raw instanceof Datetime) {
            text = ((Datetime) raw).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        } else if (raw instanceof Date) {
            text = String.valueOf((Date) raw);
        } else {
            text = String.valueOf(raw);
        }
        if (describe != null && describe.isHtmlFormatted()) {
            text = text.stripHtmlTags();
        }
        if (String.isBlank(text)) {
            return null;
        }
        Integer max = sf.maxChars == null ? DEFAULT_MAX_CHARS : sf.maxChars;
        try {
            // Bound regex input but keep a margin so a value cut at the boundary is still fully redacted.
            String bounded = text.length() > max + 200 ? text.left(max + 200) : text;
            Gavel_Redactor.Result r = Gavel_Redactor.redact(bounded, sf.redactionProfile);
            for (String k : r.counts.keySet()) {
                counts.put(k, (counts.containsKey(k) ? counts.get(k) : 0) + r.counts.get(k));
            }
            text = r.text;
        } catch (Exception e) {
            return null; // redaction failure: drop the field (fail closed)
        }
        if (text.length() > max) {
            text = text.left(max) + TRUNCATED_MARKER;
            result.truncated = true;
        }
        return text;
    }

    private static Object readValue(SObject row, FieldRef ref) {
        if (ref.relationship == null) {
            return row.get(ref.fieldName);
        }
        SObject parent = row.getSObject(ref.relationship);
        return parent == null ? null : parent.get(ref.fieldName);
    }

    /** Resolves "Field" or "Parent.Field" (one level, DEF-001.4). Returns null for an unknown path. */
    private static FieldRef resolve(String targetObject, Gavel_Definition.StateField sf) {
        if (String.isBlank(sf.fieldPath) || String.isBlank(targetObject)) {
            return null;
        }
        Map<String, Schema.SObjectField> fields = fieldsOf(targetObject);
        if (fields == null) {
            return null;
        }
        List<String> parts = sf.fieldPath.trim().split('\\.');
        FieldRef ref = new FieldRef();
        ref.sf = sf;
        if (parts.size() == 1) {
            Schema.SObjectField f = fields.get(parts[0].toLowerCase());
            if (f == null) {
                return null;
            }
            ref.describe = f.getDescribe();
            ref.fieldName = ref.describe.getName();
            ref.accessible = ref.describe.isAccessible();
            return ref;
        }
        if (parts.size() != 2) {
            return null;
        }
        for (Schema.SObjectField f : fields.values()) {
            Schema.DescribeFieldResult lookup = f.getDescribe();
            if (lookup.getRelationshipName() != null && lookup.getRelationshipName().equalsIgnoreCase(parts[0]) && !lookup.getReferenceTo().isEmpty()) {
                Map<String, Schema.SObjectField> parentFields = lookup.getReferenceTo()[0].getDescribe().fields.getMap();
                Schema.SObjectField pf = parentFields.get(parts[1].toLowerCase());
                if (pf == null) {
                    return null;
                }
                ref.describe = pf.getDescribe();
                ref.relationship = lookup.getRelationshipName();
                ref.fieldName = ref.describe.getName();
                ref.accessible = lookup.isAccessible() && ref.describe.isAccessible();
                return ref;
            }
        }
        return null;
    }

    private static Map<String, Schema.SObjectField> fieldsOf(String objectName) {
        String key = objectName.toLowerCase();
        if (!fieldMaps.containsKey(key)) {
            Schema.SObjectType t = Schema.getGlobalDescribe().get(key);
            fieldMaps.put(key, t == null ? null : t.getDescribe().fields.getMap());
        }
        return fieldMaps.get(key);
    }
}
