---
name: product-global-exposure-monitoring-comment-analysis
description: Monitor a product campaign across web and social platforms, refresh item-level exposure metrics, collect transcripts and audience comments, perform bilingual sentiment and trend analysis, safely upsert Feishu tracker rows, produce daily briefs, and clean temporary run artifacts. Use when the user asks for 全网曝光监控、产品舆情、社媒传播追踪、评论情感分析、上市 campaign 日报、飞书监控表更新，or a recurring multi-platform monitoring workflow.
---

# 产品全网曝光监控及评论分析

Build and operate a source-backed product monitoring pipeline. Treat official and third-party content equally, use canonical content URLs as record keys, update existing records in place, and minimize model context by processing deterministic deltas locally.

## Start with a campaign contract

Confirm or infer these fields before collecting:

- Product names, model variants, aliases, common misspellings, and visual identifiers.
- Official brand and campaign accounts, known creators, retailers, and media partners.
- Monitoring start/end dates, timezone, cadence, and excluded platforms.
- Feishu Wiki URL, tracker tab names, optional briefing project, and output paths.
- Inclusion rule: title, caption, body, media, transcript, comment, or attached product link can establish relevance. Never rely on title alone.

Write a compact `campaign-config.json` in the run workspace. Do not hardcode one product into this skill.

## Execute the daily workflow

1. Load `references/collection-runtime.md` and `references/tracker-analysis.md`. Load `references/agent-compatibility.md` only for installation or client adaptation.
2. If Agent Reach is installed, run `agent-reach doctor --json` once and use its current backend routing. Otherwise use the host agent's browser, web search, API, or connector tools and record the same platform coverage gaps. Do not assume any one vendor-specific tool exists.
3. Preflight Feishu before expensive collection. Require authenticated edit access plus rectangular readback from both tracker tabs. Stop without mutation if the write gate fails.
4. Search every in-scope platform with a 48-hour overlap and poll known official/partner channels. Keep late-indexed older candidates eligible.
5. Open canonical item pages and evaluate title, caption/body, visible media context, product links, transcript, and comments. Include both official and non-official content.
6. Save a compact source snapshot. Keep unavailable metrics null; use zero only when the item page explicitly shows zero.
7. Run the bundled delta helper in `scripts/delta_state.py` or its PowerShell fallback. Send only new items, changed metrics, new/changed comments, transcript hit windows, and relevance edge cases to the model.
8. Refresh Views/Plays, Likes/Reactions, and Comments for every tracked URL. Fetch comment bodies only when count/IDs change, plus a periodic full audit.
9. Collect YouTube subtitles for new items, transcript gaps, or changed fingerprints. Preserve timestamped evidence; never count transcript text as audience comments.
10. Analyze only real available comments. Produce counts, ratios, bilingual themes, concerns, and an evidence-based content-level sentiment.
11. Upsert by canonical URL. Update an existing row in place; never append a second daily row for the same content.
12. Write one cell at a time and validate immediately. After each batch, perform rectangular readback and totals/chart QA.
13. Generate the text/image/site brief only after tracker QA. Commit state only after verified synchronization.
14. Preview cleanup, then apply it after success.

## Use deterministic state and cleanup

Prefer the cross-platform Python helper. Use the PowerShell helper on Windows when Python is unavailable:

```bash
python <skill-dir>/scripts/delta_state.py init --state <state.json>
python <skill-dir>/scripts/delta_state.py diff --snapshot <snapshot.json> --delta <delta.json> --state <state.json>
python <skill-dir>/scripts/delta_state.py commit --snapshot <snapshot.json> --state <state.json>
python <skill-dir>/scripts/delta_state.py cleanup --runs-root <runs-root>
python <skill-dir>/scripts/delta_state.py cleanup --runs-root <runs-root> --apply
```

Windows PowerShell alternative:

```powershell
& <skill-dir>/scripts/delta_state.ps1 -Mode Init -StatePath <state.json>
& <skill-dir>/scripts/delta_state.ps1 -Mode Diff -SnapshotPath <snapshot.json> -DeltaPath <delta.json> -StatePath <state.json>
& <skill-dir>/scripts/delta_state.ps1 -Mode Commit -SnapshotPath <snapshot.json> -StatePath <state.json>
& <skill-dir>/scripts/delta_state.ps1 -Mode Cleanup -RunsRoot <runs-root>
& <skill-dir>/scripts/delta_state.ps1 -Mode Cleanup -RunsRoot <runs-root> -Apply
```

Never commit before Feishu QA. Preview cleanup first. Resolve every deletion target under the explicit run root.

## Keep the skill portable

- Follow the Agent Skills `SKILL.md` structure and use relative paths for bundled resources.
- Keep business logic platform-neutral. Treat `agents/openai.yaml` as optional Codex UI metadata; other clients may ignore it safely.
- Use `.agents/skills/` as the preferred shared installation directory when the client supports it. Use a client-specific directory only when required.
- Use the host agent's native browser, shell, scheduler, spreadsheet connector, and approval controls. Preserve the workflow gates even when tool names differ.
- If the client cannot safely edit Feishu, produce a validated update manifest for manual import instead of claiming the tracker was updated.

## Enforce hard acceptance gates

- Treat a signed-in page as insufficient: the grid must be interactive and readable.
- Preserve exact English schemas, Total rows, historical blocks, formulas, reserve rows, and configured charts.
- Never multi-cell paste into Feishu. Write and verify each cell independently.
- Use canonical/direct item pages for metrics; do not substitute search snippets, channel totals, or inferred values.
- Record inaccessible sources as coverage gaps, not zero activity.
- Exclude publisher-authored replies from audience sentiment unless the campaign contract explicitly requests them.
- Skip downstream briefs and state commit after any write/readback failure.

## Report the run compactly

Return:

- Platforms searched and source-access gaps.
- New items, refreshed items, changed comments, transcript checks, and unchanged items.
- Verified Sheet1/Sheet2 ranges and totals status.
- Brief/site output status.
- Cleanup actions and retained disk size.
- Any blocker stated as `blocked_without_mutation` when no safe write occurred.
