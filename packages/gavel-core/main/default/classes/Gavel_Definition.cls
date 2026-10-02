/**
 * In-memory model of one decision definition and its children (F2).
 * Built from Custom Metadata by Gavel_DefinitionRepo, or directly by tests.
 */
public with sharing class Gavel_Definition {
    public static final String MODE_DRAFT = 'Draft';
    public static final String MODE_SHADOW = 'Shadow';
    public static final String MODE_LIVE = 'Live';
    public static final String MODE_RETIRED = 'Retired';
    public static final String TARGET_NONE = 'None';

    public String apiName;
    public String targetObject;
    public Integer version;
    public String mode = MODE_SHADOW;
    public String providerConfig;
    public String providerClass;
    public String model;
    public String namedCredential;
    public String endpointPath;
    public Integer timeoutMs;
    public String definitionHash;
    public Decimal dailyBudgetCalls;
    public String pack;
    public String reviewQueue;
    public Boolean autoApply = true;
    public String description;
    public String ownerEmail;

    public List<Gavel_Question> questions = new List<Gavel_Question>();
    public List<StateField> stateFields = new List<StateField>();
    public List<Policy> policies = new List<Policy>();
    public List<ActionMap> actionMaps = new List<ActionMap>();

    public class StateField {
        public String fieldPath;
        public String stateKey;
        public Boolean required = false;
        public Integer maxChars;
        public String redactionProfile;
        public Boolean zeroIsMeaningful = false;
        public String source;
        public Integer sortOrder;

        public StateField() {
        }

        public StateField(String fieldPath, String stateKey, Boolean required) {
            this.fieldPath = fieldPath;
            this.stateKey = stateKey;
            this.required = required;
        }
    }

    public class Policy {
        public String questionKey;
        public Decimal autoAccept;
        public Decimal reviewAt;
        public Decimal minMargin;
        public String noulDirection;
        public String asymmetricReason;

        public Policy() {
        }

        public Policy(String questionKey, Decimal autoAccept, Decimal reviewAt, Decimal minMargin) {
            this.questionKey = questionKey;
            this.autoAccept = autoAccept;
            this.reviewAt = reviewAt;
            this.minMargin = minMargin;
        }
    }

    public class ActionMap {
        public String questionKey;
        public String answerValue;
        public String actionType;
        public String actionTarget;
        public String actionValue;

        public ActionMap() {
        }

        public ActionMap(String questionKey, String answerValue, String actionType, String actionTarget, String actionValue) {
            this.questionKey = questionKey;
            this.answerValue = answerValue;
            this.actionType = actionType;
            this.actionTarget = actionTarget;
            this.actionValue = actionValue;
        }
    }

    /** Shallow copy with a different question list (runtime options). */
    public Gavel_Definition copyWithQuestions(List<Gavel_Question> newQuestions) {
        Gavel_Definition d = new Gavel_Definition();
        d.apiName = apiName;
        d.targetObject = targetObject;
        d.version = version;
        d.mode = mode;
        d.providerConfig = providerConfig;
        d.providerClass = providerClass;
        d.model = model;
        d.namedCredential = namedCredential;
        d.endpointPath = endpointPath;
        d.timeoutMs = timeoutMs;
        d.definitionHash = definitionHash;
        d.dailyBudgetCalls = dailyBudgetCalls;
        d.pack = pack;
        d.reviewQueue = reviewQueue;
        d.autoApply = autoApply;
        d.description = description;
        d.ownerEmail = ownerEmail;
        d.questions = newQuestions;
        d.stateFields = stateFields;
        d.policies = policies;
        d.actionMaps = actionMaps;
        return d;
    }

    public Boolean isLive() {
        return mode == MODE_LIVE;
    }

    public Boolean hasTargetRecord() {
        return String.isNotBlank(targetObject) && targetObject != TARGET_NONE;
    }

    public Gavel_Question question(String key) {
        for (Gavel_Question q : questions) {
            if (key != null && key.equals(q.key)) {
                return q;
            }
        }
        return null;
    }

    public Policy policy(String questionKey) {
        for (Policy p : policies) {
            if (questionKey != null && questionKey.equals(p.questionKey)) {
                return p;
            }
        }
        return null;
    }

    /** Questions whose outcomes combine into the definition outcome (POL-001.6). */
    public List<Gavel_Question> participatingQuestions() {
        List<Gavel_Question> required = new List<Gavel_Question>();
        for (Gavel_Question q : questions) {
            if (q.requiredForAction == true) {
                required.add(q);
            }
        }
        return required.isEmpty() ? questions : required;
    }

    public List<ActionMap> actionsFor(String questionKey, String answerValue) {
        List<ActionMap> result = new List<ActionMap>();
        for (ActionMap a : actionMaps) {
            if (questionKey != null && questionKey.equals(a.questionKey) && answerValue != null && answerValue.equals(a.answerValue)) {
                result.add(a);
            }
        }
        return result;
    }
}
