/**
 * Provider-neutral request (contracts/provider-contract.md). State is built only by Gavel_StateBuilder.
 */
public with sharing class Gavel_JudgmentRequest {
    public String definitionApiName;
    public Integer definitionVersion;
    public String model;
    public Map<String, Object> state;
    public List<Gavel_Question> questions;
    public Integer timeoutMs;

    // Runtime context (not part of the wire body)
    /** Canonical JSON of state (sorted keys, no whitespace); sent as-is so the hash matches what left the org. */
    public String stateJson;
    /** True when the definition is Live: aliases are rejected before any callout (ADR-003). */
    public Boolean live = false;
    /** Retries are only allowed in async context (OPS-001.4). */
    public Boolean allowRetry = false;
    public String namedCredential;
    public String endpointPath;
    /** Images whose references appear in state; sent as multipart parts (Jev 1.14 and later). */
    public List<Gavel_ImageAsset> assets = new List<Gavel_ImageAsset>();

    public Boolean hasImages() {
        return assets != null && !assets.isEmpty();
    }

    public Integer effectiveTimeoutMs() {
        if (timeoutMs == null) {
            return 10000;
        }
        return Math.max(1, Math.min(timeoutMs, 60000));
    }

    public String canonicalState() {
        if (stateJson != null) {
            return stateJson;
        }
        return Gavel_Json.canonical(state == null ? new Map<String, Object>() : state);
    }
}
