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
            String raw = (req == null || req.query == null) ? '' : req.query.trim();
            // Neutralize SOSL reserved characters before the FIND — otherwise a natural-language
            // question skews or breaks the search. Most damaging is '-' (the NOT operator): it
            // turned "stop-loss" into "exclude loss". Parens/?/etc. add noise. Keep the words,
            // drop the operators, collapse whitespace.
            String cleaned = raw.replaceAll('[?&|!(){}\\[\\]^~*:"+\\\\-]', ' ').replaceAll('\\s+', ' ').trim();
            // Focus the search on content terms — drop function/question/filler words that dilute
            // SOSL relevance on a full-sentence question (so it matches the on-topic article, not noise).
            Set<String> stop = new Set<String>{
                'a','an','and','are','as','at','be','been','by','can','could','do','does','for','from',
                'get','gets','got','happen','happens','how','i','in','is','it','its','me','my','of','on',
                'or','our','so','that','the','their','them','then','they','this','to','we','what','when',
                'where','which','who','why','will','with','work','works','would','you','your'
            };
            List<String> kept = new List<String>();
            for (String w : cleaned.split(' ')) {
                if (w != '' && !stop.contains(w.toLowerCase())) kept.add(w);
            }
            String focused = String.join(kept, ' ');
            if (focused.length() < 2) focused = cleaned;   // don't blank out a very short query
            String q = String.escapeSingleQuotes(focused);
            if (q.length() < 2) { r.knowledgeResults = 'NO_INTERNAL_ARTICLE_FOUND'; out.add(r); continue; }
            try {
                String returning = 'Knowledge__kav(Title, ArticleNumber, TC_Description__c ' +
                    'WHERE PublishStatus = \'Online\' AND IsVisibleInPkb = false) LIMIT 5';
                // Title-first for precision (topic is usually in the article title), then fall back
                // to all-fields for recall so body-only matches still surface.
                List<List<SObject>> found = Search.query('FIND \'' + q + '\' IN NAME FIELDS RETURNING ' + returning);
                List<SObject> arts = (found == null || found.isEmpty()) ? new List<SObject>() : found[0];
                if (arts.isEmpty()) {
                    found = Search.query('FIND \'' + q + '\' IN ALL FIELDS RETURNING ' + returning);
                    arts = (found == null || found.isEmpty()) ? new List<SObject>() : found[0];
                }
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
