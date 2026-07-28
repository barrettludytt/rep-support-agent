public class SFSupport_JiraClient {

    public class Request {
        @InvocableVariable(required=true label='Summary') public String summary;
        @InvocableVariable(label='Description') public String description;
        @InvocableVariable(label='Flow Context') public String flowContext;
        @InvocableVariable(label='Slack User') public String slackUser;
        @InvocableVariable(label='Slack Thread Ts') public String slackThreadTs;
    }

    public class Result {
        @InvocableVariable(label='Issue Key') public String issueKey;
        @InvocableVariable(label='Formatted Response') public String formattedResponse;
        @InvocableVariable(label='Success') public Boolean success;
    }

    @InvocableMethod(label='Create Jira Bug Ticket' description='Creates a bug ticket in the IS Jira project via REST API. Uses callout:Jira_Egress.')
    public static List<Result> createBugTicket(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(callJira(req));
        }
        return results;
    }

    private static Result callJira(Request req) {
        Result res = new Result();
        // Read the project + issue type from config instead of hardcoding — the target board
        // and its valid issue types differ (SK uses "Task", not "Bug").
        SF_Support_Agent_Setting__mdt cfg = SF_Support_Agent_Setting__mdt.getInstance('Default');
        String projectKey = (cfg != null && String.isNotBlank(cfg.Jira_Project_Key__c)) ? cfg.Jira_Project_Key__c : 'SK';
        String issueType  = (cfg != null && String.isNotBlank(cfg.Jira_Issue_Type__c))  ? cfg.Jira_Issue_Type__c  : 'Task';
        try {
            String bodyText = buildBodyText(req);
            String requestBody = JSON.serialize(new Map<String, Object>{
                'fields' => new Map<String, Object>{
                    'project' => new Map<String, Object>{ 'key' => projectKey },
                    'summary' => req.summary,
                    'description' => new Map<String, Object>{
                        'type' => 'doc',
                        'version' => 1,
                        'content' => new List<Object>{
                            new Map<String, Object>{
                                'type' => 'paragraph',
                                'content' => new List<Object>{
                                    new Map<String, Object>{
                                        'type' => 'text',
                                        'text' => bodyText
                                    }
                                }
                            }
                        }
                    },
                    'issuetype' => new Map<String, Object>{ 'name' => issueType }
                }
            });

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint('callout:Jira_Egress/rest/api/3/issue');
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setHeader('Accept', 'application/json');
            httpReq.setBody(requestBody);

            HttpResponse httpRes = new Http().send(httpReq);

            if (httpRes.getStatusCode() == 201) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
                res.issueKey = (String) parsed.get('key');
                res.formattedResponse = 'Filed ' + res.issueKey + ' in Jira. https://project-soho.atlassian.net/browse/' + res.issueKey;
                res.success = true;
            } else {
                res.success = false;
                res.formattedResponse = 'Jira returned ' + httpRes.getStatusCode() + ': ' + httpRes.getBody();
            }
        } catch (Exception e) {
            res.success = false;
            res.formattedResponse = 'Error filing Jira ticket: ' + e.getMessage();
        }
        return res;
    }

    private static String buildBodyText(Request req) {
        String text = req.description != null ? req.description : '';
        if (String.isNotBlank(req.flowContext)) {
            text += '\n\nFlow Context: ' + req.flowContext;
        }
        if (String.isNotBlank(req.slackUser)) {
            text += '\n\nReported by Slack user: ' + req.slackUser;
        }
        return text;
    }
}