# Staging Promotion Checklist — Rep Support Agent

Promotion follows the standard flow: **your sandbox (devtt) → develop (DEVTT) → staging → main**,
all via pull requests (auto validate-on-open / deploy-on-merge). **Agentforce agents must be
published + previewed in DEVTT first** — they don't validate like ordinary metadata.

## 1. Metadata that deploys (in the PR)

- [ ] Apex: `RepKnowledgeSearch` (grounding search), `KnowledgeDraftBuilder` (draft-article),
      `SFSupport_JiraClient` (Jira create), `RepAgentWeeklyDigest` (scheduled digest)
- [ ] Agent Script authoring bundle: `Rep_Support_Lightning` (`aiAuthoringBundles/`)
- [ ] GenAiPlannerBundle: `Rep_Support_Lightning_v9` (current published version — includes the
      query-distillation instruction in `answer_rep_questions`)
- [ ] Flow: `AF_SFSupport_Create_Jira_Bug` (target of the `file_bug_to_jira` sub-agent)
- [ ] CustomMetadata: `SF_Support_Agent_Setting.Default` (Jira project/issue-type/active config)
- [ ] NamedCredential: `Jira_Egress` — **template only, no secret** (fill username/token per org; see §6)
- [ ] Bot: `Rep_Support_Lightning`
- [ ] (Optional) AiEvaluationDefinition: `Rep_Support_Tests` (bulk regression suite; see `specs/`)

## 2. Publish + activate the agent (per target org)

Agents are published, not just deployed. An **active** agent blocks in-place updates, so:

```bash
sf agent deactivate --api-name Rep_Support_Lightning --target-org <org>
sf agent publish authoring-bundle --api-name Rep_Support_Lightning --target-org <org>
sf agent activate  --api-name Rep_Support_Lightning --target-org <org>
```

## 3. Post-deploy MANUAL steps

- [ ] Grant reps **Apex-execute** on `RepKnowledgeSearch`, `KnowledgeDraftBuilder`, `SFSupport_JiraClient`.
- [ ] Grant reps **Knowledge read** + visibility of the internal data category.
- [ ] **Knowledge visibility — VERIFY BEFORE PROD.** `RepKnowledgeSearch` filters
      `IsVisibleInPkb = false` (internal-only articles). In devtt the rep articles the agent
      searches are internal-visible, so this works as-is. **Prod's Help Center articles are
      customer-facing (`IsVisibleInPkb = true`)** — confirm which set reps should be answered from:
      - If reps should answer from the **public HC** articles, change the WHERE clause to drop the
        `IsVisibleInPkb = false` filter (or `= true`), or point at whatever internal category holds
        rep-support content.
      - No article *import* is needed — prod already contains the full Help Center. This was a
        **recall** problem (verbose queries returned the wrong article), not a content gap; the
        query-distillation step in agent v9 is the fix. Do **not** re-create "gap" articles that
        already exist in prod.
- [ ] Confirm the org-wide email address `no-reply@tastytrade.com` exists (used by the digest);
      then schedule the weekly digest **only at rollout**:
      `System.schedule('Rep Support Weekly Digest','0 0 8 ? * MON *', new RepAgentWeeklyDigest());`
- [ ] (Optional) Wire a **Slack channel** for the `escalate_to_lead` topic in Agentforce Studio → Channels.
- [ ] Draft-article topic uses **`KnowledgeDraftBuilder`** Apex (sets body → `TC_Description__c`
      and generates the `TC_Html_File` HTML the Help Center needs). It does **not** assign a data
      category — the reviewer assigns the right rep category on publish (add a default in the builder
      if the org requires a category to publish).

## 4. Dependencies that must exist in the target org

- [ ] Apex `KnowledgeDraftBuilder` + `Knowledge__kav` with the `TC_Description__c` and `TC_Html_File` fields.
- [ ] Jira-maker infra (see **section 6**) for the `file_bug_to_jira` topic.
- [ ] Internal Knowledge articles (see step 3).

## 5. Smoke test after deploy

- [ ] Preview the agent → a known rep question returns a **cited** answer ending in a `Confidence: N%` line.
- [ ] Try "file a bug…", "document this…", and "I need a lead" to exercise the sub-agents.

## 6. Jira-ticket maker (`file_bug_to_jira`) — must be dealt with per environment

The chain is `file_bug_to_jira` → flow `AF_SFSupport_Create_Jira_Bug` → `SFSupport_JiraClient`
→ `callout:Jira_Egress`. Getting it firing in devtt required fixes that are **George's shared
infra in `tastyworks/salesforce`** and must be promoted / re-done per org:

- [ ] **`SFSupport_JiraClient`** — patched to read the project key + issue type from
      `SF_Support_Agent_Setting__mdt` instead of hardcoding `IS` / `Bug`. Promote this fix.
- [ ] **`SF_Support_Agent_Setting__mdt.Default`** — set `Jira_Project_Key__c` / `Jira_Issue_Type__c`
      to the target board's real values (devtt = **SK / Task**; SK is a Work-Management project with
      no "Bug" type) and `Is_Active__c = true`.
- [ ] **`Jira_Egress` Named Credential** — provision per org (Basic auth to
      `https://project-soho.atlassian.net`). **Use a service-account Atlassian token in staging/prod**,
      not a personal one. Never committed to any repo (secret).
- [ ] Confirm the target project's **required fields** — the create 400s if a required custom field
      isn't provided (e.g. the IS project requires "Team Resource"; SK's Task type needs none).

## Known follow-on (not a blocker)

- **Dedup / check-asked-before** — not yet ported; needs a `Support_Log__c` logging layer to be useful.
