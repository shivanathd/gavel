/**
 * Validates a definition before it may run or activate (F2, DEF-001.3/.5, ADR-003, ADR-009).
 * Returns error codes, never throws.
 */
public with sharing class Gavel_DefinitionValidator {
    public static final Pattern KEY_PATTERN = Pattern.compile('^[A-Za-z0-9_]{1,80}$');
    private static final Pattern VERSIONED_MODEL = Pattern.compile('.*\\d+\\.\\d+.*');
    private static final Set<String> MODES = new Set<String>{ 'Draft', 'Shadow', 'Live', 'Retired' };
    private static final Set<String> TYPES = new Set<String>{ 'choice', 'score', 'noul', 'box' };
    private static final Set<String> PROFILES = new Set<String>{ 'none', 'pii_basic', 'payment', 'gov_id', 'strict' };
    private static final Set<String> DIRECTIONS = new Set<String>{ 'true_is_action', 'false_is_action' };
    private static final Set<String> ACTION_TYPES = new Set<String>{ 'set_field', 'assign_queue', 'create_task', 'publish_event', 'invoke_flow', 'none' };

    public class Result {
        public Boolean valid = true;
        public List<String> errors = new List<String>();
        public List<String> warnings = new List<String>();
        public String computedHash;

        public String firstError() {
            return errors.isEmpty() ? null : errors[0];
        }

        public void add(String code) {
            if (!errors.contains(code)) {
                errors.add(code);
            }
            valid = false;
        }
    }

    /** True when a model ID is an alias rather than a pinned version (ADR-003). */
    public static Boolean isModelAlias(String model) {
        if (String.isBlank(model)) {
            return true;
        }
        String m = model.toLowerCase();
        if (m.contains('latest') || m.contains('preview') || m.contains('default')) {
            return true;
        }
        return !VERSIONED_MODEL.matcher(m).matches();
    }

    public static Result validate(Gavel_Definition d) {
        Result r = new Result();
        if (d == null) {
            r.add('definition_not_found');
            return r;
        }
        if (String.isBlank(d.targetObject)) {
            r.add('target_object_missing');
        } else if (d.hasTargetRecord() && !Schema.getGlobalDescribe().containsKey(d.targetObject.toLowerCase())) {
            r.add('unknown_target_object');
        }
        if (d.version == null || d.version < 1) {
            r.add('invalid_version');
        }
        if (d.mode == null || !MODES.contains(d.mode)) {
            r.add('invalid_mode');
        }
        if (d.dailyBudgetCalls != null && d.dailyBudgetCalls < 0) {
            r.add('negative_budget');
        } else if (d.dailyBudgetCalls == null) {
            r.warnings.add('budget_unlimited');
        }
        if (d.timeoutMs != null && (d.timeoutMs < 1 || d.timeoutMs > 60000)) {
            r.add('timeout_out_of_range');
        }
        if (String.isBlank(d.providerClass)) {
            r.add('provider_missing');
        }
        if (d.isLive() && isModelAlias(d.model)) {
            r.add('model_alias_not_allowed_live');
        }

        validateQuestions(d, r);
        validatePolicies(d, r);
        validateStateFields(d, r);
        validateActions(d, r);

        r.computedHash = Gavel_DefinitionHasher.compute(d);
        if (String.isBlank(d.definitionHash) || !r.computedHash.equalsIgnoreCase(d.definitionHash)) {
            r.add('definition_hash_mismatch');
        }
        return r;
    }

    private static void validateQuestions(Gavel_Definition d, Result r) {
        if (d.questions == null || d.questions.isEmpty() || d.questions.size() > 64) {
            r.add('question_count_out_of_range');
            return;
        }
        Set<String> keys = new Set<String>();
        for (Gavel_Question q : d.questions) {
            if (q.key == null || !KEY_PATTERN.matcher(q.key).matches()) {
                r.add('invalid_question_key');
            } else if (keys.contains(q.key)) {
                r.add('duplicate_question_key');
            } else {
                keys.add(q.key);
            }
            if (q.questionType == null || !TYPES.contains(q.questionType)) {
                r.add('invalid_question_type');
                continue;
            }
            if (String.isBlank(q.prompt)) {
                r.add('empty_prompt');
            }
            // A box only locates something for a reviewer; it may not decide or trigger anything.
            if (q.isBox() && q.requiredForAction == true) {
                r.add('box_cannot_drive_action');
            }
            validateOptions(q, r);
        }
    }

    /** Option rules shared with request validation (choice 2..255, score 2..10 from 0). */
    public static void validateOptions(Gavel_Question q, Result r) {
        List<Gavel_Option> opts = q.options == null ? new List<Gavel_Option>() : q.options;
        Boolean dynamic = String.isNotBlank(q.optionSource);
        Set<String> optKeys = new Set<String>();
        for (Gavel_Option o : opts) {
            if (o.key == null || !KEY_PATTERN.matcher(o.key).matches()) {
                r.add('invalid_option_key');
            } else if (optKeys.contains(o.key)) {
                r.add('duplicate_option_key');
            } else {
                optKeys.add(o.key);
            }
        }
        if (q.isBox()) {
            if (!opts.isEmpty() || dynamic) {
                r.add('box_options_not_allowed');
            }
        } else if (q.isChoice()) {
            if (!dynamic && (opts.size() < 2 || opts.size() > 255)) {
                r.add('choice_option_count_out_of_range');
            }
        } else if (q.isScore()) {
            if (opts.size() < 2 || opts.size() > 10) {
                r.add('score_level_count_out_of_range');
            }
            Set<Integer> levels = new Set<Integer>();
            Integer minLevel = null;
            for (Gavel_Option o : opts) {
                if (o.level == null) {
                    r.add('score_level_missing');
                    continue;
                }
                levels.add(o.level);
                if (minLevel == null || o.level < minLevel) {
                    minLevel = o.level;
                }
            }
            if (minLevel != null && minLevel != 0) {
                r.add('score_levels_must_start_at_zero');
            } else if (minLevel != null) {
                for (Integer i = 0; i < levels.size(); i++) {
                    if (!levels.contains(i)) {
                        r.add('score_levels_not_contiguous');
                        break;
                    }
                }
            }
        }
    }

    private static void validatePolicies(Gavel_Definition d, Result r) {
        for (Gavel_Definition.Policy p : d.policies) {
            Gavel_Question q = d.question(p.questionKey);
            if (q == null) {
                r.add('policy_unknown_question');
                continue;
            }
            if (p.autoAccept == null || p.reviewAt == null) {
                r.add('threshold_missing');
            }
            if (outOfUnit(p.autoAccept) || outOfUnit(p.reviewAt) || outOfUnit(p.minMargin)) {
                r.add('threshold_out_of_range');
            }
            if (p.autoAccept != null && p.reviewAt != null && p.reviewAt > p.autoAccept) {
                r.add('review_above_auto_accept');
            }
            if (q.isChoice() && p.minMargin == null) {
                r.add('threshold_missing');
            }
            if (q.isNoul() && (p.noulDirection == null || !DIRECTIONS.contains(p.noulDirection))) {
                r.add('noul_direction_missing');
            }
            if (p.autoAccept == 0 || p.reviewAt == 0) {
                r.warnings.add('threshold_zero_everything_passes');
            }
        }
    }

    private static void validateStateFields(Gavel_Definition d, Result r) {
        Set<String> keys = new Set<String>();
        for (Gavel_Definition.StateField sf : d.stateFields) {
            if (sf.stateKey == null || !KEY_PATTERN.matcher(sf.stateKey).matches()) {
                r.add('invalid_state_key');
            } else if (keys.contains(sf.stateKey)) {
                r.add('duplicate_state_key');
            } else {
                keys.add(sf.stateKey);
            }
            if (String.isBlank(sf.fieldPath)) {
                r.add('bad_field_path');
            }
            if (sf.maxChars != null && sf.maxChars < 1) {
                r.add('invalid_max_chars');
            }
            if (sf.redactionProfile != null && !PROFILES.contains(sf.redactionProfile)) {
                r.add('invalid_redaction_profile');
            }
        }
    }

    private static void validateActions(Gavel_Definition d, Result r) {
        for (Gavel_Definition.ActionMap a : d.actionMaps) {
            Gavel_Question q = d.question(a.questionKey);
            if (q == null) {
                r.add('action_unknown_question');
            } else if (q.isBox()) {
                r.add('action_on_box_question');
            }
            if (a.actionType == null || !ACTION_TYPES.contains(a.actionType)) {
                r.add('invalid_action_type');
            }
        }
    }

    private static Boolean outOfUnit(Decimal v) {
        return v != null && (v < 0 || v > 1);
    }
}
