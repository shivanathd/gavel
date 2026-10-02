/**
 * Input passed to a Gavel_StateSource.
 */
public with sharing class Gavel_StateContext {
    public Id recordId;
    public String targetObject;
    public String fieldPath;
    public String arg;
    public Integer maxChars;
    /** Direct inputs for record-less runs (for example Agentforce Screen Input text). */
    public Map<String, Object> inputs = new Map<String, Object>();
}
