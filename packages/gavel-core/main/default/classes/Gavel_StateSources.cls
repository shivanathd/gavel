/**
 * Built-in Gavel_StateSource implementations. Referenced from Gavel_State_Field__mdt.Source__c,
 * e.g. "Gavel_StateSources.InboundEmails:3". Every query runs WITH USER_MODE.
 */
public with sharing class Gavel_StateSources {
    public static final Integer PER_ITEM_CHARS = 2000;
    private static final Pattern REPLY_HEADER = Pattern.compile('(?im)^\\s*(On .{0,200}wrote:|-{2,}\\s*Original Message\\s*-{2,}|From:\\s.+\\n(?:.*\\n){0,4}?Subject:)');

    /** Removes quoted reply chains: "On ... wrote:", "Original Message" blocks and "> " lines (STATE-001.8). */
    public static String stripQuoted(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        String t = text.replace('\r\n', '\n');
        Matcher m = REPLY_HEADER.matcher(t);
        if (m.find()) {
            t = t.substring(0, m.start());
        }
        List<String> kept = new List<String>();
        for (String line : t.split('\n')) {
            if (!line.trim().startsWith('>')) {
                kept.add(line);
            }
        }
        return String.join(kept, '\n').trim();
    }

    public static String bodyText(String textBody, String htmlBody) {
        String body = String.isNotBlank(textBody) ? textBody : (htmlBody == null ? null : htmlBody.stripHtmlTags());
        return stripQuoted(body);
    }

    private static Integer argInt(Gavel_StateContext ctx, Integer dflt) {
        if (String.isNotBlank(ctx.arg) && ctx.arg.isNumeric()) {
            return Math.max(1, Math.min(Integer.valueOf(ctx.arg), 50));
        }
        return dflt;
    }

    private static String joinItems(List<String> items) {
        List<String> cleaned = new List<String>();
        for (String s : items) {
            if (String.isNotBlank(s)) {
                cleaned.add(s.abbreviate(PER_ITEM_CHARS));
            }
        }
        return cleaned.isEmpty() ? null : String.join(cleaned, '\n---\n');
    }

    /** Direct input value (record-less runs). Arg or last path segment is the input key. */
    public class Input implements Gavel_StateSource {
        public Object resolve(Gavel_StateContext ctx) {
            String key = String.isNotBlank(ctx.arg) ? ctx.arg : ctx.fieldPath.substringAfterLast('.');
            if (String.isBlank(key)) {
                key = ctx.fieldPath;
            }
            return ctx.inputs == null ? null : ctx.inputs.get(key);
        }
    }

    /** Last N inbound EmailMessage bodies for a Case (ParentId) or other record (RelatedToId), quotes stripped. */
    public class InboundEmails implements Gavel_StateSource {
        public Object resolve(Gavel_StateContext ctx) {
            if (ctx.recordId == null) {
                return null;
            }
            Integer n = argInt(ctx, 3);
            Id rid = ctx.recordId;
            try {
                List<String> bodies = new List<String>();
                for (EmailMessage e : [
                    SELECT TextBody, HtmlBody
                    FROM EmailMessage
                    WHERE (ParentId = :rid OR RelatedToId = :rid) AND Incoming = TRUE
                    WITH USER_MODE
                    ORDER BY MessageDate DESC NULLS LAST, CreatedDate DESC
                    LIMIT :n
                ]) {
                    bodies.add(bodyText(e.TextBody, e.HtmlBody));
                }
                return joinItems(bodies);
            } catch (Exception e) {
                return null;
            }
        }
    }

    /** Body of the target EmailMessage itself (TextBody, or stripped HtmlBody), quotes stripped. */
    public class EmailBody implements Gavel_StateSource {
        public Object resolve(Gavel_StateContext ctx) {
            if (ctx.recordId == null) {
                return null;
            }
            Id rid = ctx.recordId;
            try {
                List<EmailMessage> rows = [SELECT TextBody, HtmlBody FROM EmailMessage WHERE Id = :rid WITH USER_MODE LIMIT 1];
                return rows.isEmpty() ? null : bodyText(rows[0].TextBody, rows[0].HtmlBody);
            } catch (Exception e) {
                return null;
            }
        }
    }

    /** Domain part only of an email field (default Email). The full address never leaves the org. */
    public class EmailDomain implements Gavel_StateSource {
        public Object resolve(Gavel_StateContext ctx) {
            if (ctx.recordId == null || String.isBlank(ctx.targetObject)) {
                return null;
            }
            String field = String.isNotBlank(ctx.arg) ? ctx.arg : 'Email';
            if (!Pattern.matches('[A-Za-z0-9_]+', field) || !Pattern.matches('[A-Za-z0-9_]+', ctx.targetObject)) {
                return null;
            }
            try {
                List<SObject> rows = Database.queryWithBinds(
                    'SELECT ' + field + ' FROM ' + ctx.targetObject + ' WHERE Id = :rid LIMIT 1',
                    new Map<String, Object>{ 'rid' => ctx.recordId },
                    AccessLevel.USER_MODE
                );
                if (rows.isEmpty()) {
                    return null;
                }
                String email = (String) rows[0].get(field);
                if (String.isBlank(email) || !email.contains('@')) {
                    return null;
                }
                return email.substringAfterLast('@').trim().toLowerCase();
            } catch (Exception e) {
                return null;
            }
        }
    }

    /** Last N Task/Event descriptions and EmailMessage bodies on the record within 90 days (Stage Evidence). */
    public class RecentActivity implements Gavel_StateSource {
        public Object resolve(Gavel_StateContext ctx) {
            if (ctx.recordId == null) {
                return null;
            }
            Integer n = argInt(ctx, 10);
            Id rid = ctx.recordId;
            List<String> items = new List<String>();
            try {
                for (Task t : [
                    SELECT Description FROM Task
                    WHERE WhatId = :rid AND CreatedDate = LAST_N_DAYS:90
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC LIMIT :n
                ]) {
                    items.add(t.Description);
                }
            } catch (Exception e) {
                items.add(null);
            }
            try {
                for (Event ev : [
                    SELECT Description FROM Event
                    WHERE WhatId = :rid AND CreatedDate = LAST_N_DAYS:90
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC LIMIT :n
                ]) {
                    items.add(ev.Description);
                }
            } catch (Exception e) {
                items.add(null);
            }
            try {
                for (EmailMessage e : [
                    SELECT TextBody, HtmlBody FROM EmailMessage
                    WHERE RelatedToId = :rid AND CreatedDate = LAST_N_DAYS:90
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC LIMIT :n
                ]) {
                    items.add(bodyText(e.TextBody, e.HtmlBody));
                }
            } catch (Exception e) {
                items.add(null);
            }
            List<String> top = new List<String>();
            for (String s : items) {
                if (String.isNotBlank(s) && top.size() < n) {
                    top.add(s);
                }
            }
            return joinItems(top);
        }
    }
}
