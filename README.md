# Rep Support Agent (Salesforce Agentforce)

A native Salesforce **Agentforce Employee Agent** that answers frontline support reps'
questions from internal Knowledge, files bugs, drafts articles, and escalates — built and
validated in a sandbox.

## What makes it work

- **Grounded on a custom Apex search action** (`RepKnowledgeSearch`, SOSL over internal-only
  Knowledge articles) instead of a Data Cloud Data Library. The Data Library path never bound /
  retrieved in this org, so the agent grounds through Apex and **actually answers** — internal-only
  by construction (`IsVisibleInPkb=false`).
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
  aiAuthoringBundles/Rep_Support_Lightning/   Agent Script source (edit here)
  genAiPlannerBundles/Rep_Support_Lightning_v6/  Compiled planner (published output)
  bots/Rep_Support_Lightning/                 Bot + versions
  classes/                                    RepKnowledgeSearch, RepAgentWeeklyDigest
docs/Support-Knowledge-Agent.md               Full write-up
STAGING-CHECKLIST.md                          Promotion runbook + post-deploy steps
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
