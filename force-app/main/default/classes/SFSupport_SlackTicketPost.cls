/**
 * Posts a support "ticket" (bug report or content-update request) to the #help-center-updates
 * Slack channel via an Incoming Webhook (callout:Slack_HelpCenterUpdates). The team flags it as a
 * Jira ticket from Slack, and it doubles as the content department's audit trail.
 *
 * Replaces the direct Jira REST callout (SFSupport_JiraClient) in the agent path — that required
 * a personal Atlassian credential / service-user OAuth we don't have. A Slack incoming webhook is a
 * channel-scoped URL secret (no user identity), so no service user is needed.
 *
 * Called by the Rep Support agent's log-ticket sub-agent (target apex://SFSupport_SlackTicketPost).
 */
public with sharing class SFSupport_SlackTicketPost {

    public class Request {
        @InvocableVariable(required=true label='Summary') public String summary;
        @InvocableVariable(label='Description') public String description;
        @InvocableVariable(label='Ticket Type') public String ticketType;   // e.g. Bug, Content update
        @InvocableVariable(label='Reporter') public String reporter;
    }

    public class Result {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String formattedResponse;
    }

    @InvocableMethod(label='Post Ticket to Slack (#help-center-updates)'
        description='Posts a bug/content ticket to #help-center-updates via incoming webhook for manual Jira flagging and content-team audit.')
    public static List<Result> post(List<Request> reqs) {
        List<Result> out = new List<Result>();
        for (Request r : reqs) {
            Result res = new Result();
            try {
                String type = String.isBlank(r.ticketType) ? 'Bug' : r.ticketType;
                String text = ':ticket: *New ticket for review* — _flag as Jira from Slack_\n'
                    + '*Type:* ' + type + '\n'
                    + '*Summary:* ' + (r.summary == null ? '' : r.summary) + '\n'
                    + '*Details:* ' + (r.description == null ? '(none provided)' : r.description);
                if (String.isNotBlank(r.reporter)) text += '\n*Reported by:* ' + r.reporter;
                text += '\n_Logged by the Rep Support agent._';

                HttpRequest req = new HttpRequest();
                req.setEndpoint('callout:Slack_HelpCenterUpdates');
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setBody(JSON.serialize(new Map<String, Object>{ 'text' => text }));

                HttpResponse resp = new Http().send(req);
                // Slack incoming webhooks return HTTP 200 with body "ok" on success.
                if (resp.getStatusCode() == 200) {
                    res.success = true;
                    res.formattedResponse = 'Posted the ticket to #help-center-updates for review and Jira flagging.';
                } else {
                    res.success = false;
                    res.formattedResponse = 'Slack post failed (' + resp.getStatusCode() + '): ' + resp.getBody();
                }
            } catch (Exception e) {
                res.success = false;
                res.formattedResponse = 'Error posting to Slack: ' + e.getMessage();
            }
            out.add(res);
        }
        return out;
    }
}
