/**
 * Creates a COMPLETE draft internal Knowledge article the way this org's Help Center needs it:
 * Title, Summary, a slugged UrlName, the body in TC_Description__c (rich HTML), AND the
 * TC_Html_File file field (an HTML rendering of the body wrapped in the article-content div,
 * which HC requires for the article to populate). Draft only — never published; human reviews.
 * Called by the Rep Support agent's draft_knowledge_article sub-agent (target apex://KnowledgeDraftBuilder).
 */
public with sharing class KnowledgeDraftBuilder {

    public class Request {
        @InvocableVariable(required=true label='Title') public String InputTitle;
        @InvocableVariable(required=true label='Summary') public String InputSummary;
        @InvocableVariable(label='Body') public String InputBody;
    }
    public class Result {
        @InvocableVariable(label='Success') public Boolean OutputSuccess;
        @InvocableVariable(label='Article Id') public String OutputArticleId;
        @InvocableVariable(label='Message') public String OutputFormattedResponse;
    }

    @InvocableMethod(label='Draft Knowledge Article (full)' category='Knowledge')
    public static List<Result> create(List<Request> reqs) {
        List<Result> out = new List<Result>();
        for (Request req : reqs) {
            Result r = new Result();
            try {
                String slug = slugify(req.InputTitle);
                String htmlBody = toHtml(req.InputBody);
                Knowledge__kav kav = new Knowledge__kav(
                    Title = req.InputTitle,
                    Summary = req.InputSummary,
                    Language = 'en_US',
                    UrlName = slug,
                    TC_Description__c = htmlBody
                );
                String fileHtml = '<div class="article-content t1" id="article-content">' + htmlBody + '</div>';
                // Html File Name field is capped at 40 chars — keep it short.
                String fileName = slug.length() > 34 ? slug.substring(0, 34).replaceAll('-+$', '') : slug;
                kav.put('TC_Html_File__Name__s', fileName + '.html');
                kav.put('TC_Html_File__ContentType__s', 'text/html');
                kav.put('TC_Html_File__Body__s', Blob.valueOf(fileHtml));   // File field takes a Blob
                insert kav;
                r.OutputSuccess = true;
                r.OutputArticleId = kav.Id;
                r.OutputFormattedResponse = 'Draft created: "' + req.InputTitle +
                    '" — body + HTML file attached. DRAFT pending human review; not published.';
            } catch (Exception e) {
                r.OutputSuccess = false;
                r.OutputFormattedResponse = 'Could not create draft: ' + e.getMessage();
            }
            out.add(r);
        }
        return out;
    }

    static String slugify(String t) {
        String s = (t == null ? '' : t).toLowerCase().replaceAll('[^a-z0-9]+', '-')
                    .replaceAll('^-+', '').replaceAll('-+$', '');
        if (s.length() > 80) s = s.substring(0, 80).replaceAll('-+$', '');
        if (String.isBlank(s)) s = 'article';
        return s + '-' + String.valueOf(Datetime.now().getTime());
    }

    // Use as-is if the body already looks like HTML; otherwise wrap plain-text paragraphs.
    static String toHtml(String body) {
        if (String.isBlank(body)) return '<p></p>';
        String bl = body.toLowerCase();
        if (bl.contains('<p>') || bl.contains('<h2') || bl.contains('<h3') || bl.contains('<ul')
            || bl.contains('<li') || bl.contains('<div') || bl.contains('<br')) {
            return body;
        }
        List<String> paras = new List<String>();
        for (String p : body.split('\\n\\s*\\n')) {
            if (String.isNotBlank(p)) paras.add('<p>' + p.trim().replace('\n', '<br/>') + '</p>');
        }
        return paras.isEmpty() ? '<p>' + body + '</p>' : String.join(paras, '');
    }
}
