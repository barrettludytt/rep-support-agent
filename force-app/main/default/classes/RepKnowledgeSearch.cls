/**
 * Native Salesforce Knowledge search for the Rep Support (Lightning) agent.
 * SOSL over Knowledge__kav, scoped to INTERNAL-ONLY articles (IsVisibleInPkb=false =
 * never surfaced to the website/customers). No Data Cloud / Data Library. Returns the
 * top matching article bodies for the agent to synthesize an answer + cite.
 */
public with sharing class RepKnowledgeSearch {

    public class Request {
        @InvocableVariable(required=true label='Question' description='The rep question or search keywords')
        public String query;
    }

    public class Response {
        @InvocableVariable(label='Knowledge Results' description='Top matching internal knowledge articles (title, article number, body) for grounding the answer; NO_INTERNAL_ARTICLE_FOUND if none.')
        public String knowledgeResults;
    }

    @InvocableMethod(label='Search Rep Knowledge' description='Searches internal Salesforce Knowledge (internal-only articles, never website content) for the rep question and returns matching article content.')
    public static List<Response> search(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            String q = (req == null || req.query == null) ? '' : String.escapeSingleQuotes(req.query.trim());
            if (q.length() < 2) { r.knowledgeResults = 'NO_INTERNAL_ARTICLE_FOUND'; out.add(r); continue; }
            try {
                List<List<SObject>> found = Search.query(
                    'FIND \'' + q + '\' IN ALL FIELDS RETURNING Knowledge__kav(' +
                    'Title, ArticleNumber, TC_Description__c ' +
                    'WHERE PublishStatus = \'Online\' AND IsVisibleInPkb = false) LIMIT 5');
                List<SObject> arts = (found == null || found.isEmpty()) ? new List<SObject>() : found[0];
                if (arts.isEmpty()) {
                    r.knowledgeResults = 'NO_INTERNAL_ARTICLE_FOUND';
                } else {
                    List<String> chunks = new List<String>();
                    for (SObject a : arts) {
                        String body = (String)a.get('TC_Description__c');
                        if (body != null && body.length() > 4000) body = body.substring(0, 4000);
                        chunks.add('### ' + (String)a.get('Title') + ' (Article ' + (String)a.get('ArticleNumber') + ')\n' + body);
                    }
                    r.knowledgeResults = String.join(chunks, '\n\n---\n\n');
                }
            } catch (Exception e) {
                r.knowledgeResults = 'SEARCH_ERROR: ' + e.getMessage();
            }
            out.add(r);
        }
        return out;
    }
}
