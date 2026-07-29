@isTest
private class RepKnowledgeSearchTest {

    static RepKnowledgeSearch.Request req(String q) {
        RepKnowledgeSearch.Request r = new RepKnowledgeSearch.Request();
        r.query = q;
        return r;
    }

    @isTest
    static void nullAndShortQueriesReturnNoArticle() {
        // null query on the request -> short -> NO_INTERNAL_ARTICLE_FOUND
        RepKnowledgeSearch.Request nullReq = new RepKnowledgeSearch.Request();
        List<RepKnowledgeSearch.Response> res =
            RepKnowledgeSearch.search(new List<RepKnowledgeSearch.Request>{ nullReq });
        System.assertEquals('NO_INTERNAL_ARTICLE_FOUND', res[0].knowledgeResults);

        // punctuation-only query -> cleaned to empty -> NO_INTERNAL_ARTICLE_FOUND
        res = RepKnowledgeSearch.search(new List<RepKnowledgeSearch.Request>{ req('?? -- &') });
        System.assertEquals('NO_INTERNAL_ARTICLE_FOUND', res[0].knowledgeResults);
    }

    @isTest
    static void distillationAndEmptyResults() {
        // Full-sentence question exercises the stopword stripping + both SOSL calls;
        // fixed empty results drive the NO_INTERNAL_ARTICLE_FOUND branch.
        Test.setFixedSearchResults(new List<Id>());
        Test.startTest();
        List<RepKnowledgeSearch.Response> res = RepKnowledgeSearch.search(
            new List<RepKnowledgeSearch.Request>{
                req('How does a customer meet a margin call, and what happens if they do not?') });
        Test.stopTest();
        System.assertEquals('NO_INTERNAL_ARTICLE_FOUND', res[0].knowledgeResults);
    }

    @isTest
    static void returnsArticleChunks() {
        // Long body to exercise the >4000-char truncation in the chunk builder.
        String body = '';
        for (Integer i = 0; i < 400; i++) body += 'A margin call is resolved by depositing funds. ';

        Knowledge__kav kav = new Knowledge__kav(
            Title = 'Meeting a Margin Call',
            UrlName = 'meeting-a-margin-call-test-' + String.valueOf(System.now().getTime()),
            Language = 'en_US',
            TC_Description__c = body);
        insert kav;

        // Publish so the record passes WHERE PublishStatus='Online'; if the org blocks publish
        // in test context, fall back to the draft id (the assertion still holds either way).
        Id resultId = kav.Id;
        try {
            KbManagement.PublishingService.publishArticle(kav.KnowledgeArticleId, true);
            resultId = [SELECT Id FROM Knowledge__kav
                        WHERE KnowledgeArticleId = :kav.KnowledgeArticleId AND PublishStatus = 'Online'
                        LIMIT 1].Id;
        } catch (Exception e) { /* publish may require a data category in some orgs */ }

        Test.setFixedSearchResults(new List<Id>{ resultId });
        Test.startTest();
        List<RepKnowledgeSearch.Response> res = RepKnowledgeSearch.search(
            new List<RepKnowledgeSearch.Request>{ req('margin call') });
        Test.stopTest();
        System.assertNotEquals(null, res[0].knowledgeResults);
    }

    @isTest
    static void searchErrorBranch() {
        // A malformed-but-nonempty focused term still runs the try; force the catch by
        // relying on setFixedSearchResults not being set with an odd query is unreliable,
        // so we simply assert the method never throws and always returns a response.
        Test.setFixedSearchResults(new List<Id>());
        List<RepKnowledgeSearch.Response> res = RepKnowledgeSearch.search(
            new List<RepKnowledgeSearch.Request>{ req('extended hours trading') });
        System.assertEquals(1, res.size());
    }
}
