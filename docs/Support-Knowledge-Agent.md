# Rep Support Knowledge Agent — from mined tickets to a native Salesforce AI agent

**One-liner:** Turned 28,000+ historical support responses into a curated knowledge base, then built AI agents that answer frontline reps' questions in real time — first as a Slack bot, then as a native Salesforce Agentforce agent grounded in that knowledge.

**Role:** Architect & builder (design, data pipeline, retrieval/grounding, agent build, ops tooling)

---

## The problem
tastytrade support reps repeatedly asked the same policy/procedure questions (margin calls, funding, options assignment, tax documents, account access) and waited on senior staff to answer. The institutional knowledge existed — but it was locked inside tens of thousands of closed support tickets and scattered across the Help Center, internal Confluence, and Slack.

## What I built

### 1. Knowledge corpus (the foundation)
- Mined **28,768 authored support responses** from Salesforce (by authorship, not case ownership — the true footprint of one senior rep's expertise).
- Distilled them through a multi-agent synthesis pipeline into **1,090 curated, PII-scrubbed knowledge cards** across 13 themes.
- Unified with two more sources into a single **3,106-record corpus**: 1,090 mined cards + 1,164 Help Center article chunks + 835 Confluence (Raptor) chunks + a growing set of team-taught lessons.
- Built an automated nightly refresh (idempotent rebuild, atomic swap, freshness reporting) so the corpus stays current without manual re-runs.

### 2. Slack support bot (live in production)
- Dependency-free **BM25 retrieval** over the corpus + LLM answer generation via CLI (no API-key dependency).
- **Independent verifier pass** that grades how well retrieved sources support each answer, blended into a **confidence score** shown to reps ("thinly sourced — double-check this").
- **Internal/external answer split** — separates customer-relayable text from internal-only procedures (escalation routes, gating).
- **Multi-source answers with citations**, live on **16 Slack channels**.
- **Resilience engineering:** catch-up sweeps to recover questions dropped during Socket Mode disconnects, persisted dedup, watchdog auto-restart.
- Extended into a **shared 3-instance architecture** — one git-committed "shared brain" run by three operators, splitting load across token pools via a daily primary/secondary/tertiary roster.

### 3. Native Salesforce Agentforce agent (built & validated end-to-end)
- Migrated the mined/internal knowledge into **~1,940 Salesforce Knowledge articles** (1,090 cards + 850 Confluence pages) as non-public content, kept off the customer-facing Help Center by a dedicated non-public **data category**. The employee-only rep agent grounds across **both** these internal articles and the public Help Center — everything a customer can see plus internal material — while a separate customer-facing bot is scoped to public content only.
- Stood up a **native internal Agentforce Employee Agent** authored in the modern **Lightning builder** (Agent Script / DSL), replacing the fragile always-on local bot with Salesforce-hosted infrastructure.
- **Solved a hard grounding problem the "supported" way couldn't:** the standard Lightning knowledge action is hardwired to Data Cloud, and the Data-Library-to-agent binding was broken in the org. Rather than fight it, engineered a **custom Apex SOSL search action** over native Salesforce Knowledge — no Data Cloud dependency, searching all published articles (public Help Center + internal), and fully controllable. Same answer quality, far simpler and more portable.
- Worked through real Agentforce platform constraints hands-on: agent-type mismatches (the CLI kept producing customer *service* agents), capped agent templates, and data-category visibility — recreating the agent correctly via metadata + Agent Script when the tooling wouldn't.
- Added a **source-authority hierarchy** (official Help Center → internal docs → ticket-derived cards, with citations) and **self-assessed confidence scoring** on every answer.
- Built a **self-monitoring operations layer, fully native to Salesforce:**
  - **Weekly training-gap digest** — a scheduled **Apex class** that reads the agent's own conversation data from the Agentforce analytics data model, buckets questions into ~26 topics via regex, and emails a **styled HTML digest** (topic mix + the biggest low-confidence "training gaps") to trade-desk managers from a verified org-wide address. No external process.
  - **Knowledge-gap tickets** — low-confidence answers auto-filed to the team's Jira board for follow-up.
- **Validated end-to-end** in a sandbox: a real rep question ("How can a customer meet an FM call?") returned the correct answer from the exact knowledge article with a citation, in real user context; the native Apex digest rendered and delivered the manager report identically.

## Impact
- Removed answer latency for the most common rep questions; gave reps instant, sourced, confidence-scored answers.
- Converted a single senior rep's undocumented expertise into a reusable, queryable, continuously-refreshed asset.
- Created a closed feedback loop: the agent surfaces its own knowledge gaps as Jira tickets and reports training holes to management — automatically, inside the platform.
- Moved a business-critical AI service off a personal machine onto managed Salesforce infrastructure, removing single-point-of-failure risk.

## Status
- **Slack bot:** live in production, 16 channels, shared 3-instance model.
- **Salesforce-native agent + ops layer:** built and validated end-to-end in sandbox (Lightning agent, native-Knowledge grounding, self-scoring, native Apex weekly digest); production rollout scoped and documented as a clean recipe (handoff to Salesforce admin).

## Tech
Salesforce (Knowledge, **Agentforce / Agent Script (Lightning) DSL**, Apex — invocable actions, `Schedulable`, `Messaging.SingleEmailMessage`, **SOSL over `Knowledge__kav`**, querying Agentforce analytics DMOs, Metadata API, `sf` CLI), Python, BM25 retrieval, LLM orchestration (RAG, independent-verifier grounding), Slack (Socket Mode / Bolt), Jira REST, Confluence REST, git.

## Résumé bullets (drop-in)
- Mined and distilled **28,000+ historical support responses** into a curated, PII-scrubbed knowledge base powering AI agents that answer frontline reps in real time.
- Built a production Slack support bot (retrieval-augmented, independent-verifier confidence scoring, multi-source citations, live on 16 channels), then rebuilt it as a **native Salesforce Agentforce (Lightning) agent** grounded in native Salesforce Knowledge (public Help Center + internal articles) via a **custom Apex Knowledge-search action** — bypassing a broken Data Cloud dependency.
- Engineered a **fully-native, self-monitoring ops layer**: a scheduled Apex class that reads the agent's conversation analytics, emails managers a styled weekly training-gap digest, and auto-files Jira tickets for low-confidence answers.
