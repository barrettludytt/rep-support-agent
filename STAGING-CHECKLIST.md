# Staging Promotion Checklist — Rep Support Agent

Promotion follows the standard flow: **your sandbox (devtt) → develop (DEVTT) → staging → main**,
all via pull requests (auto validate-on-open / deploy-on-merge). **Agentforce agents must be
published + previewed in DEVTT first** — they don't validate like ordinary metadata.

## 1. Metadata that deploys (in the PR)

- [ ] Apex: `RepKnowledgeSearch` (grounding search), `KnowledgeDraftBuilder` (draft-article),
      `SFSupport_JiraClient` (Jira create), `RepAgentWeeklyDigest` (scheduled digest)
- [ ] Agent Script authoring bundle: `Rep_Support_Lightning` (`aiAuthoringBundles/`)
- [ ] GenAiPlannerBundle: `Rep_Support_Lightning_v11` (current published version — query
      distillation + anti-fabrication guardrail in `answer_rep_questions`)
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
- [ ] Grant reps **Knowledge read** on every category the agent should answer from (public HC +
      internal Raptor/ticket categories).
- [ ] **Knowledge visibility — DECIDED (implemented).** `RepKnowledgeSearch` searches **all published
      articles** — the public Help Center (`IsVisibleInPkb = true`) AND internal Raptor/ticket docs
      (`IsVisibleInPkb = false`). This is an INTERNAL rep tool, so it grounds on everything a customer
      can see plus internal material. No `IsVisibleInPkb` filter, and no article import needed (prod
      already has the full HC).
      - ⚠️ **Customer-facing bots must do the INVERSE:** any customer-facing agent that searches
        Knowledge must filter to `IsVisibleInPkb = true` ONLY, so internal docs can never leak to a
        customer. Do not reuse `RepKnowledgeSearch` as-is for a customer bot.
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
- [ ] Published Knowledge articles (public HC + internal) — prod already has these (see step 3).

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

## Resolved during testing

- **Eligibility-by-country answers** (e.g. "Can customers in India trade options?") — originally
  failed because the search was scoped internal-only, hiding the public HC article that carries the
  answer. **Resolved** by widening the scope to all published articles (§3). The agent now cites
  *Supported Countries for International Accounts* (public) + *Trading Levels and Allowed Strategies*
  (internal) and answers correctly ("India = cash accounts only; buy options / covered calls /
  cash-secured puts; no spreads or naked"). Verified in the regression suite.

## Known follow-on (not a blocker)

- **Dedup / check-asked-before** — not yet ported; needs a `Support_Log__c` logging layer to be useful.
- **Agent version:** current published/active version is **v11** — query distillation +
  anti-fabrication guardrail in `answer_rep_questions` (relevance-check the search result, enforce a
  second conceptual search on tangential hits, never extrapolate a directional/eligibility conclusion
  from an off-topic article, calibrate confidence < 40% on indirect content) + grounding across all
  published articles. Regression case "Can customers in India trade options?" is in
  `specs/rep-support-tests.yaml`.
