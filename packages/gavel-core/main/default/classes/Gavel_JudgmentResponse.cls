/**
 * Provider response after validation. status is one of the contract values; answers only when ok.
 */
public with sharing class Gavel_JudgmentResponse {
    public static final String OK = 'ok';
    public static final String INVALID_REQUEST = 'invalid_request';
    public static final String INVALID_RESPONSE = 'invalid_response';
    public static final String CONTRACT_MISMATCH = 'contract_mismatch';
    public static final String TIMEOUT = 'timeout';
    public static final String HTTP_ERROR = 'http_error';
    public static final String CIRCUIT_OPEN = 'circuit_open';
    public static final String BUDGET_EXCEEDED = 'budget_exceeded';

    /** Statuses that count as provider failures for the circuit breaker. */
    public static final Set<String> PROVIDER_FAILURES = new Set<String>{ INVALID_RESPONSE, CONTRACT_MISMATCH, TIMEOUT, HTTP_ERROR };

    public String status;
    public String modelVersion;
    public Map<String, Gavel_Answer> answers;
    public Integer httpStatus;
    public Long latencyMs;
    public Map<String, Object> usage;
    /** Machine-readable detail for non-ok statuses (e.g. model_alias_not_allowed_live). Never contains payload text. */
    public String errorCode;
    public List<String> warnings = new List<String>();
    public Integer attempts = 0;

    public Boolean isOk() {
        return status == OK;
    }

    public static Gavel_JudgmentResponse failure(String status, Integer httpStatus, String errorCode) {
        Gavel_JudgmentResponse r = new Gavel_JudgmentResponse();
        r.status = status;
        r.httpStatus = httpStatus;
        r.errorCode = errorCode;
        return r;
    }
}
