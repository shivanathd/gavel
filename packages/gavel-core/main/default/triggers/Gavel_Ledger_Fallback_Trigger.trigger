trigger Gavel_Ledger_Fallback_Trigger on Gavel_Ledger_Fallback__e(after insert) {
    Gavel_Ledger.replay(Trigger.new);
}
