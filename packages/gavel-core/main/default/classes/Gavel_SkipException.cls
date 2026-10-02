/**
 * Thrown by a Gavel_OptionSource or Gavel_StateSource to end a run as SKIP with the message as the reason
 * (for example knowledge_not_enabled, no_kb_candidates). The run is still ledgered.
 */
public with sharing class Gavel_SkipException extends Exception {
}
