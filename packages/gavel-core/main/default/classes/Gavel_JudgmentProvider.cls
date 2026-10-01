/**
 * Provider interface (CORE-001.1). Implementations MUST return a typed status and never throw.
 * Resolved by Gavel_Provider_Config__mdt.Provider_Class__c through Type.forName (CORE-001.10).
 */
public interface Gavel_JudgmentProvider {
    Gavel_JudgmentResponse judge(Gavel_JudgmentRequest req);
}
