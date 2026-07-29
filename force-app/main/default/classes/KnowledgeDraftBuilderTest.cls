@isTest
private class KnowledgeDraftBuilderTest {

    static KnowledgeDraftBuilder.Request rq(String title, String summary, String body) {
        KnowledgeDraftBuilder.Request r = new KnowledgeDraftBuilder.Request();
        r.InputTitle = title;
        r.InputSummary = summary;
        r.InputBody = body;
        return r;
    }

    @isTest
    static void createsDraftFromHtmlBody() {
        // HTML body passes through toHtml unchanged; success path inserts the draft + HTML file.
        List<KnowledgeDraftBuilder.Result> res = KnowledgeDraftBuilder.create(
            new List<KnowledgeDraftBuilder.Request>{
                rq('Meeting an FM Call', 'How to meet a futures maintenance call.',
                   '<h2>Meeting an FM Call</h2><p>Deposit funds or close positions.</p><ul><li>Deposit</li></ul>') });
        System.assertEquals(true, res[0].OutputSuccess, res[0].OutputFormattedResponse);
        System.assertNotEquals(null, res[0].OutputArticleId);
    }

    @isTest
    static void plainTextBodyAndLongTitleSlug() {
        // Plain-text body -> wrapped in <p> (paragraph split); very long title -> slug (>80) +
        // file-name (>34) truncation branches.
        // ~120 chars: long enough to trip the slug (>80) + file-name (>34) truncation, but
        // under the Knowledge Title field's 255-char limit so the insert still succeeds.
        String longTitle = '';
        for (Integer i = 0; i < 5; i++) longTitle += 'Very Long Title Segment ';
        List<KnowledgeDraftBuilder.Result> res = KnowledgeDraftBuilder.create(
            new List<KnowledgeDraftBuilder.Request>{
                rq(longTitle, 'summary', 'First plain paragraph.\n\nSecond plain paragraph.') });
        System.assertEquals(true, res[0].OutputSuccess, res[0].OutputFormattedResponse);
    }

    @isTest
    static void blankBodyAndFailureBranch() {
        // Blank body -> toHtml returns '<p></p>' (success). Null title -> insert fails on the
        // required Title field -> the catch branch returns OutputSuccess=false.
        List<KnowledgeDraftBuilder.Result> res = KnowledgeDraftBuilder.create(
            new List<KnowledgeDraftBuilder.Request>{
                rq('Blank Body Article', 'summary', ''),
                rq(null, null, null) });
        System.assertEquals(true, res[0].OutputSuccess, res[0].OutputFormattedResponse);
        System.assertEquals(false, res[1].OutputSuccess);
        System.assert(res[1].OutputFormattedResponse.startsWith('Could not create draft'));
    }
}
