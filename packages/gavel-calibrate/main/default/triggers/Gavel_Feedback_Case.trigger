trigger Gavel_Feedback_Case on Case(after update) {
    Gavel_FeedbackCapture.onRecordUpdate(Trigger.new, Trigger.oldMap);
}
