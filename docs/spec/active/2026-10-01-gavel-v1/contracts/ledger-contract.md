# Contract: Runtime -> Gavel_Decision_Log__c

**Version:** 1.0.0 | **Owner:** gavel-core | **Consumers:** shadow, calibrate, admin, auditors

Required on every entry: Record_Id__c, Object__c, Definition__c, Version__c, Definition_Hash__c, Mode__c, Outcome__c, Reason__c, Idempotency_Key__c, Running_User__c, CreatedDate.
Required when a callout happened: Model_Version__c, State_Hash__c, Answers_JSON__c, Latency_Ms__c, Http_Status__c.
Optional: Redaction_Summary__c, State_Truncated__c, Cache_Hit__c, Action_Taken__c, Action_Suppressed__c, Asymmetric_Reason__c, Prev_Hash__c, Entry_Hash__c, State_JSON__c (only if Store_State__c = true).
Immutability: insert-only except the retention process. Retention default 365 days.
