# Staging Promotion Checklist — Rep Support Agent

Promotion follows the standard flow: **your sandbox (devtt) → develop (DEVTT) → staging → main**,
all via pull requests (auto validate-on-open / deploy-on-merge). **Agentforce agents must be
published + previewed in DEVTT first** — they don't validate like ordinary metadata.

## 1. Metadata that deploys (in the PR)

- [ ] Apex: `RepKnowledgeSearch` (grounding search), `KnowledgeDraftBuilder` (draft-article),
      `SFSupport_JiraClient` (Jira create), `RepAgentWeeklyDigest` (scheduled digest)
- [ ] Agent Script authoring bundle: `Rep_Support_Lightning` (`aiAuthoringBundles/`)
- [ ] GenAiPlannerBundle: `Rep_Support_Lightning_v12` (current published version — query
      distillation + anti-fabrication guardrail + two-part-question decomposition in `answer_rep_questions`)
- [ ] Flow: `AF_SFSupport_Create_Jira_Bug` (target of the `file_bug_to_jira` sub-agent)
- [ ] CustomMetadata: `SF_Support_Agent_Setting.Default` (Jira project/issue-type/active config)
- [ ] NamedCredential: `Jira_Egress` — **template only, no secret** (fill username/token per org; see §7)
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

- [ ] **Permission set — OWNED BY THE SALESFORCE TEAM (not built here, by decision).** Create a
      `Rep_Support_Agent` permission set granting **Apex-execute** on `RepKnowledgeSearch`,
      `KnowledgeDraftBuilder`, `SFSupport_JiraClient`; **`Knowledge__kav` Create + Read**; and
      **data-category visibility** on every category the agent answers from (public HC + internal).
      - ⚠️ **Assign it to BOTH the reps AND the agent's run-as user** (the `Einstein Agent User`,
        e.g. `rep_support_agent@…`). Verified in devtt (2026-07-28): that agent user currently
        LACKS `Knowledge__kav` Create **and** Apex-execute on `KnowledgeDraftBuilder` (it has execute
        on `RepKnowledgeSearch`, which is why Q&A works). Because of this, the **draft-article
        sub-agent silently fails** — the `apex://KnowledgeDraftBuilder` action can't run as the agent
        user, yet the agent reported "draft created." (The `file_bug_to_jira` path is unaffected
        because it runs through a Flow, i.e. system context, not a direct `apex://` action.)
      - The auto-generated agent permset (`Rep_Support_Agent…​ Permissions`) is incomplete — it did
        not include `KnowledgeDraftBuilder` execute or Knowledge Create. Re-generate/extend it.
- [ ] **Knowledge scope — DECIDED (implemented).** `RepKnowledgeSearch` searches **all published
      (Online) articles** with no visibility/category filter — both public Help Center content AND
      non-public internal KB articles. This is an INTERNAL, employee-only agent, so it grounds on
      everything a customer can see plus internal material. No article import needed (prod already
      has the full HC).
      - Non-public rep articles are isolated from the customer-facing Help Center by tagging them
        with a dedicated **non-public data category** (the Help Center / production customer bot only
        surface public-category content). That isolation lives on the Help Center side, not in this
        search — this agent is employee-only and can't expose anything to customers.
      - Requirement: **reps must have Knowledge data-category visibility** to the internal category,
        or SOSL won't return those articles.
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
- [ ] Jira-maker infra (see **section 7**) for the `file_bug_to_jira` topic.
- [ ] Published Knowledge articles (public HC + internal) — prod already has these (see step 3).

## 5. Smoke test after deploy

- [ ] Preview the agent → a known rep question returns a **cited** answer ending in a `Confidence: N%` line.
- [x] **Live multi-turn preview — verified in devtt (v12).** The bulk suite (§6) fires only the first
      turn, so these action-completing paths were confirmed by hand in the Builder preview:
      - [x] "file a bug…" → gathered details on turn 1, filed **real Jira SK-322** on turn 2 via the
            full flow → `SFSupport_JiraClient` → `Jira_Egress` callout chain (test ticket deleted).
            Confirms the devtt Jira token/callout works.
      - [x] "I need a lead" → clean escalation hand-off; carried context across the session (referenced
            the earlier bug + draft request), confirming multi-turn session memory.
      - [x] "document this…" → RUN LIVE and exposed a real bug: the agent claimed "draft created" but
            NO article was created. Root cause: the agent run-as user lacks `KnowledgeDraftBuilder`
            Apex-execute + `Knowledge__kav` Create (see §3 permission note). The Apex action works when
            invoked directly. **Blocked until the agent user gets those perms; the draft path cannot be
            confirmed end-to-end until then.** Secondary (DONE in v13): the draft sub-agent now requires
            a real `OutputArticleId` before claiming success, so this gap fails loudly, not silently —
            re-verify live once the agent user has the perms.

## 6. Automated regression suite (already passing)

- [ ] `specs/rep-support-tests.yaml` → `Rep_Support_Tests` (29 cases). Create/run with:
      `sf agent test create --spec specs/rep-support-tests.yaml --api-name Rep_Support_Tests --force-overwrite --target-org <org>`
      then `sf agent test run --api-name Rep_Support_Tests --target-org <org>`.
      Last run in devtt on **v12 = 29/29** (topic + action routing + output validation), including the
      "Can customers in India trade options?" grounding regression. Re-run after promoting to a new org.

## 7. Ticket logging (`file_bug_to_jira`) → posts to Slack #help-center-updates

**Pivot (decision):** the agent no longer creates Jira directly (that needed a personal Atlassian
credential / service-user OAuth we don't have). Instead, when a ticket is needed the agent **posts the
ticket to the `#help-center-updates` Slack channel**; the team flags it as a Jira ticket from Slack, and
it doubles as the content team's audit trail.

**Mechanism (final): the native Agentforce Slack action** — no webhook, no Apex, no new credential.
`file_bug_to_jira` sub-agent → `SendMessageToSlackChannel` (`source: Slack__SendMessageToSlackChannel`,
`target: slack://slackAgentDynamic__SendMessageToSlackChannel`), posting to `#help-center-updates`
(channel ID `C0ARLTST3C2`, hardcoded in the sub-agent).

- [ ] **Slack ↔ Agentforce integration must be enabled** (the "General Slack Actions" set). It's what
      exposes `SendMessageToSlackChannel`. Gotcha: those bundled actions import with a broken `target`
      (`slack://X`); the correct form is `slack://slackAgentDynamic__X` — already fixed in our bundle.
- [ ] **Reconnect Slack** on the active agent version and confirm the connection can post to
      `#help-center-updates`. Grant the agent user access to the Slack action.
- [ ] Preview "file a bug…" and confirm the formatted ticket lands in `#help-center-updates`.

> We removed the whole "General Slack" subagent Salesforce adds (it also brings create-channel,
> archive, add-users, share-canvas, etc. — a rep agent must NOT have those). Only the single
> send-message action is kept, folded into `file_bug_to_jira`.
> **Deprecated / out of the agent path** (safe to delete): the webhook approach `SFSupport_SlackTicketPost`
> + `Slack_HelpCenterUpdates` NC, and the old Jira-callout infra (`SFSupport_JiraClient`, flow
> `AF_SFSupport_Create_Jira_Bug`, `SF_Support_Agent_Setting__mdt`, `Jira_Egress`). Left in the repo for history.
> Cosmetic: sub-agent still labeled `file_bug_to_jira` (kept to avoid breaking the router + test suites).

## Data Library grounding (added — needs Builder verification)

The agent now also wires in the **native Agentforce Data Library** path, mirroring George's
SF Internal Support agent: a top-level `knowledge:` block (`rag_feature_config_id:
ARFPC_1JDdi000001WtIXGA0`, the "Rep Support KB" library) + an `AnswerQuestionsWithKnowledge`
action (`EmployeeCopilot__AnswerQuestionsWithKnowledge` → `standardInvocableAction://streamKnowledgeSearch`).
It is wired **primary, with the Apex `RepKnowledgeSearch` as fallback**, so grounding is guaranteed
either way.

- ✅ **Confirmed:** the wiring **validates with 0 errors** (the RAG config resolves — the thing that
  was broken when we first built this) and the `answer_with_knowledge` action **fires** in every test.
- ⚠️ **Not yet confirmable via CLI:** whether the Data Library actually *returns content*. Attempts to
  isolate it failed because `sf agent test` kept invoking the Apex action even after it was removed
  from the source and republished (BotVersion 18 active, yet the harness ran an older action set —
  the known "committed ≠ active" publish/version-propagation disconnect). So CLI testing can't prove
  DL content-serving here.
- ▶️ **To verify:** open the agent in **Agentforce Builder → Preview** (authoritative for the live
  version) and ask a known question; confirm the answer carries a Data Library `knowledgeSummary`
  with citations rather than silently riding the Apex fallback. If the DL serves well, drop the Apex
  fallback; if not, the Apex path already carries it (proven 29/29 + 100/100).

## Resolved during testing

- **Eligibility-by-country answers** (e.g. "Can customers in India trade options?") — originally
  failed because the search was scoped internal-only, hiding the public HC article that carries the
  answer. **Resolved** by widening the scope to all published articles (§3). The agent now cites
  *Supported Countries for International Accounts* (public) + *Trading Levels and Allowed Strategies*
  (internal) and answers correctly ("India = cash accounts only; buy options / covered calls /
  cash-secured puts; no spreads or naked"). Verified in the regression suite.

## Known follow-on (not a blocker)

- **Dedup / check-asked-before** — not yet ported; needs a `Support_Log__c` logging layer to be useful.
- **Agent version:** current published/active version is **v13**. v13 adds: the **`Confidence: N%`
  line is scoped to knowledge answers only** (bug/draft/escalate responses no longer append it —
  verified) and the **draft sub-agent requires a real `OutputArticleId`** before claiming success (so
  a permission gap fails loudly instead of silently — pending agent-user perms to verify live).
  `answer_rep_questions` also does
  query distillation + grounds across all published articles + an anti-fabrication guardrail
  (relevance-check the result, retry once with conceptual keywords on a tangential hit, never
  extrapolate a directional/eligibility conclusion from an off-topic article, calibrate confidence
  < 40% on indirect content) + **two-part-question decomposition** ("can customers in <place> trade
  <product>?" → search eligibility/account-type AND what that account type can trade, then
  synthesize) + a **no-injected-premise rule** (never bridge to a conclusion with a fact you didn't
  retrieve — e.g. the false "options require a margin account"). Regression case "Can customers in
  India trade options?" is in `specs/rep-support-tests.yaml`; verified 6/6 on a repeated-run
  reliability check.
