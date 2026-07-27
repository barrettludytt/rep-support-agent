# Staging Promotion Checklist — Rep Support Agent

Promotion follows the standard flow: **your sandbox (devtt) → develop (DEVTT) → staging → main**,
all via pull requests (auto validate-on-open / deploy-on-merge). **Agentforce agents must be
published + previewed in DEVTT first** — they don't validate like ordinary metadata.

## 1. Metadata that deploys (in the PR)

- [ ] Apex: `RepKnowledgeSearch`, `RepAgentWeeklyDigest`
- [ ] Agent Script authoring bundle: `Rep_Support_Lightning` (`aiAuthoringBundles/`)
- [ ] GenAiPlannerBundle: `Rep_Support_Lightning_v6`
- [ ] Bot: `Rep_Support_Lightning`

## 2. Publish + activate the agent (per target org)

Agents are published, not just deployed. An **active** agent blocks in-place updates, so:

```bash
sf agent deactivate --api-name Rep_Support_Lightning --target-org <org>
sf agent publish authoring-bundle --api-name Rep_Support_Lightning --target-org <org>
sf agent activate  --api-name Rep_Support_Lightning --target-org <org>
```

## 3. Post-deploy MANUAL steps

- [ ] Grant reps **Apex-execute** on `RepKnowledgeSearch`.
- [ ] Grant reps **Knowledge read** + visibility of the internal data category.
- [ ] Migrate the internal Knowledge articles into the target org on the **internal channel**
      (`IsVisibleInPkb=false`) so the SOSL action can find them.
- [ ] Confirm the org-wide email address `no-reply@tastytrade.com` exists (used by the digest);
      then schedule the weekly digest **only at rollout**:
      `System.schedule('Rep Support Weekly Digest','0 0 8 ? * MON *', new RepAgentWeeklyDigest());`
- [ ] (Optional) Wire a **Slack channel** for the `escalate_to_lead` topic in Agentforce Studio → Channels.
- [ ] Retarget the `AF_SFSupport_Draft_Knowledge_Article` flow's data category away from
      `SF_Internal_Support` before reps use the draft-article topic.

## 4. Dependencies that must exist in the target org

- [ ] Reused flows: `AF_SFSupport_Create_Jira_Bug`, `AF_SFSupport_Draft_Knowledge_Article`
- [ ] Internal Knowledge articles (see step 3).

## 5. Smoke test after deploy

- [ ] Preview the agent → a known rep question returns a **cited** answer ending in a `Confidence: N%` line.
- [ ] Try "file a bug…", "document this…", and "I need a lead" to exercise the sub-agents.

## Known follow-on (not a blocker)

- **Dedup / check-asked-before** — not yet ported; needs a `Support_Log__c` logging layer to be useful.
