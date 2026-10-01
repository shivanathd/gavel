trigger Gavel_Feedback_Lead on Lead(after update) {
    Gavel_FeedbackCapture.onRecordUpdate(Trigger.new, Trigger.oldMap);
}
