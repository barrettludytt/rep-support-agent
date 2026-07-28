# Rep Support Agent (Salesforce Agentforce)

A native Salesforce **Agentforce Employee Agent** (employee-only) that answers frontline support
reps' questions from Salesforce Knowledge, files bugs, drafts articles, and escalates — built and
validated in a sandbox.

## What makes it work

- **Grounded on a custom Apex search action** (`RepKnowledgeSearch`, SOSL over `Knowledge__kav`)
  instead of a Data Cloud Data Library. The Data Library path never bound / retrieved in this org,
  so the agent grounds through Apex and **actually answers**.
  - Searches **all published (Online) articles** — the public Help Center **plus** non-public
    internal KB articles. It's an employee-only agent, so it grounds on everything a customer can
    see plus internal material. (Non-public articles are kept off the customer-facing Help Center by
    a dedicated non-public **data category** — that isolation lives on the Help Center side, not in
    this search. A customer-facing bot is a separate system.)
  - **Query distillation** (search concise concepts, not the full sentence) + an **anti-fabrication
    guardrail** (relevance-check the result, retry once with conceptual keywords on a tangential hit,
    never extrapolate an eligibility/policy conclusion from an off-topic article, calibrate
    confidence < 40% on indirect content).
- **Multi-subagent router** (`Atlas__ConcurrentMultiAgentOrchestration`):
  - `answer_rep_questions` — cited answers with a self-assessed **confidence score**, using a
    source-authority hierarchy (Help Center → Raptor/Confluence → ticket-derived cards).
  - `file_bug_to_jira` — files a Jira bug and returns the issue key.
  - `draft_knowledge_article` — drafts a KB article (draft, human-reviewed).
  - `escalate_to_lead` — hands off to a team lead with context.
- **Self-monitoring ops:** a scheduled Apex **weekly training-gap digest** (`RepAgentWeeklyDigest`)
  that reads the agent's own conversation analytics and emails managers a styled report.

Authored in **Agent Script** (`aiAuthoringBundles/Rep_Support_Lightning/Rep_Support_Lightning.agent`)
and published with `sf agent publish authoring-bundle`.

> The multi-subagent structure was adapted from **George Waked's SF Internal Support Agent** —
> his topic/sub-agent architecture on top of this project's working Apex grounding.

## Layout

```
force-app/main/default/
  aiAuthoringBundles/Rep_Support_Lightning/       Agent Script source (edit here)
  genAiPlannerBundles/Rep_Support_Lightning_v12/  Compiled planner (published output, current)
  bots/Rep_Support_Lightning/                     Bot + versions
  classes/                                        RepKnowledgeSearch, KnowledgeDraftBuilder,
                                                  SFSupport_JiraClient, RepAgentWeeklyDigest
  flows/AF_SFSupport_Create_Jira_Bug             Jira-bug flow (file_bug_to_jira target)
  customMetadata/SF_Support_Agent_Setting.Default Jira project/issue-type/active config
  namedCredentials/Jira_Egress                    Jira Basic-auth NC — TEMPLATE, no token
specs/                                            Bulk test suite (AiEvaluationDefinition spec, 29 cases)
docs/Support-Knowledge-Agent.md                   Full write-up
STAGING-CHECKLIST.md                              Promotion runbook + post-deploy steps
```

## Build / publish

```bash
# validate the Agent Script, then publish (deactivate → publish → activate for an active agent)
sf agent validate authoring-bundle --api-name Rep_Support_Lightning --target-org <sandbox>
sf agent deactivate --api-name Rep_Support_Lightning --target-org <sandbox>
sf agent publish authoring-bundle --api-name Rep_Support_Lightning --target-org <sandbox>
sf agent activate --api-name Rep_Support_Lightning --target-org <sandbox>
```

See **[STAGING-CHECKLIST.md](STAGING-CHECKLIST.md)** for the full promotion runbook.
