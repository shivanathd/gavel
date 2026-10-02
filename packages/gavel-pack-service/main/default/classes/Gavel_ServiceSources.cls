/**
 * Service pack state sources.
 */
public with sharing class Gavel_ServiceSources {
    /** Summary of the Knowledge article attached to the email's case (Reply Check). Null without Knowledge. */
    public class LinkedArticle implements Gavel_StateSource {
        public Object resolve(Gavel_StateContext ctx) {
            if (ctx.recordId == null || !Schema.getGlobalDescribe().containsKey('knowledge__kav')) {
                return null;
            }
            try {
                List<EmailMessage> emails = [SELECT ParentId FROM EmailMessage WHERE Id = :ctx.recordId WITH USER_MODE LIMIT 1];
                if (emails.isEmpty() || emails[0].ParentId == null) {
                    return null;
                }
                List<SObject> links = Database.queryWithBinds(
                    'SELECT KnowledgeArticleId FROM CaseArticle WHERE CaseId = :caseId ORDER BY CreatedDate DESC LIMIT 1',
                    new Map<String, Object>{ 'caseId' => emails[0].ParentId }, AccessLevel.USER_MODE);
                if (links.isEmpty()) {
                    return null;
                }
                List<SObject> articles = Database.queryWithBinds(
                    'SELECT Summary FROM Knowledge__kav WHERE KnowledgeArticleId = :aid AND PublishStatus = \'Online\' LIMIT 1',
                    new Map<String, Object>{ 'aid' => links[0].get('KnowledgeArticleId') }, AccessLevel.USER_MODE);
                return articles.isEmpty() ? null : (String) articles[0].get('Summary');
            } catch (Exception e) {
                return null;
            }
        }
    }
}
