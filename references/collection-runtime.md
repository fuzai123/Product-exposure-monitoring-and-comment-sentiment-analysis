# Collection and runtime contract

## Platform coverage

Search all platforms allowed by the campaign contract, including YouTube, Facebook, Instagram, TikTok, Reddit, Threads, blogs, news/media, retailer pages, forums, podcasts, newsletters, Bilibili, and product pages. Apply exclusions explicitly; do not silently narrow “全网” to search-engine-indexed YouTube and Reddit results.

Use three discovery lanes:

1. Brand lane: official accounts, regional accounts, campaign hashtags, teaser/launch/product links.
2. Partner lane: known creators, retailers, media partners, and their recent feeds.
3. Open-web lane: product aliases plus review, teaser, first look, unboxing, test, comparison, giveaway, launch, and link variants.

Use a 48-hour overlap around the last successful cursor. Search the full campaign window for late-indexed pages. Persist per-platform cursor, query, access status, and coverage gaps.

Before claiming coverage, build a capability matrix with one row per platform:

- `direct_authenticated`: native API/connector/CLI or logged-in item page can expose canonical content and metrics.
- `public_direct`: canonical public item pages are readable but comments or metrics may be partial.
- `indexed_only`: only search-engine or open-web discovery is available.
- `unavailable`: no safe backend is reachable.

“All-platform search” means every in-scope platform was attempted and its lane/status was recorded. It never means complete coverage when a platform is `indexed_only` or `unavailable`.

## Deterministic backend resolution

Run diagnostics once per run and record the resolved executable and version. For Agent Reach:

1. Try `agent-reach` from `PATH`.
2. On Windows, try `%USERPROFILE%\.agent-reach-venv\Scripts\agent-reach.exe`.
3. If neither exists, use host-native tools and mark Agent Reach unavailable.

Do not repeatedly retry a missing backend. An update check is informational and must not silently change the runtime during a monitoring run.

## Inclusion and identity

Include an item when the product is directly mentioned, visibly shown, discussed in transcript/comments, or linked from the content. Inspect the item body/media context when the title is inconclusive.

Use canonical URL as the unique identifier. Normalize YouTube Shorts and `youtu.be` to a watch URL and strip tracking parameters. Retain the original source URL only as provenance.

## Metrics and comments

Read item-level Views/Plays, Likes/Reactions, and Comments from canonical pages. Leave inaccessible or undisclosed values blank. Never infer engagement from search snippets or use zero for missing data.

On each daily run:

- Refresh visible metrics for every tracked item.
- Fetch comment bodies only if the visible count changed or unseen comment IDs appear.
- Run a full comment audit every third day, when counts decrease, or when platform pagination was previously incomplete.
- Deduplicate by platform comment ID; if absent, use a stable hash of canonical URL, author, timestamp, and normalized text.
- Save comment evidence with author type, timestamp, language, text, source URL, and relevance decision.

## YouTube transcripts

For new videos, transcript gaps, or changed transcript fingerprints, obtain manual captions, automatic captions, or speech-to-text in that order. Normalize VTT locally, search product aliases locally, and send only timestamped hit windows to the model. Store transcript availability, language, caption type, fingerprint, and evidence timestamps. Transcript evidence supports content relevance/sentiment but never audience-comment counts.

## Compact snapshot

Each item should contain:

```json
{
  "url": "canonical URL",
  "platform": "YouTube",
  "publisher": "Publisher",
  "publisher_type": "Official or Third-party",
  "published": "ISO date/time",
  "type": "Video/Post/Article",
  "topic": "short English topic",
  "metrics": {"views": null, "likes": null, "comments": null},
  "comment_ids": [],
  "transcript_status": "available/gap/not-applicable",
  "transcript_fingerprint": null,
  "coverage_gap": null
}
```

Keep full raw payloads out of model context. Store compact manifests and only changed comment bodies/transcript windows.

## Pending discovery and baseline recovery

Keep committed source state, retryable discovery, and presentation state separate:

- `state.json`: only canonical items whose tracker rows passed exact readback.
- `pending-snapshot.json`: normalized read-only discovery or metrics collected while the tracker gate was unavailable.
- `presentation-status.json`: reserve-row, formula, chart, summary, and site QA.

When tracker access recovers, pre-read both sheets, reconcile the pending snapshot against live canonical URLs, and replay only the delta. Do not repeat public discovery merely because a write tool failed.

If committed state is empty while the verified tracker is non-empty, enter `baseline_required`. Export the complete canonical URL/metric set from Sheet1 and run the helper’s verified `reconcile` mode. Do not treat all tracker rows as newly discovered.

## Token and disk controls

- Run backend diagnostics once, not once per platform.
- Batch platform searches and reuse canonical URL/state indexes.
- Use local regex/hash/diff/sum operations; reserve model calls for judgment.
- Do not resend unchanged rows, full transcripts, complete comment histories, or raw HTML.
- Retain successful run manifests/summaries for 7 days and failed/blocked evidence for 48 hours.
- After a successful run, remove screenshots, raw HTML, downloaded media, subtitles, and intermediate JSON; retain manifest and run summary.
- Keep the run root under 500 MB. Preview cleanup and verify the resolved root before applying deletion.
