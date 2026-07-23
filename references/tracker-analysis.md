# Tracker, analysis, and QA contract

## Sheet schemas

Unless the user supplies a different schema, preserve these exact English columns.

Sheet1:

- Row 1: Total formulas for every numeric column.
- Row 2 A:L: `Platform`, `Publisher`, `Type`, `Topic`, `URL`, `Views`, `Likes`, `Comments`, `Mention in Comments`, `Published Date`, `Sentiment`, `Last Updated`.

Comment Sentiment Analysis:

- Row 1: Total formulas for count fields. Do not sum percentages.
- Row 2 A:T: `Publisher`, `Content Topic`, `Published`, `Page Comments`, `Reviewed`, `Related`, `Relevance %`, `Positive`, `Neutral`, `Negative`, `Positive %`, `Neutral %`, `Negative %`, `Key Positive Themes (EN)`, `Key Positive Themes (ZH)`, `Key Concerns (EN)`, `Key Concerns (ZH)`, `URL`, `Updated`, `Platform`.

Use canonical URL as the unique key in both sheets. Update the matching row in place. Maintain at least 20 blank reserve rows before any Methodology block so future daily entries remain inside the table/chart source range.

## Comment sentiment method

Analyze only comments that were actually retrieved. Separate page comments from reviewed comments and product/brand-related comments.

- Positive: expresses satisfaction, purchase intent, recommendation, praise, excitement, or favorable comparison concerning the product/brand.
- Neutral: asks a factual question, supplies information, tags another person, or mentions the product without a clear favorable/unfavorable stance.
- Negative: expresses dissatisfaction, rejection, defect/performance concern, price/value concern, distrust, or an unfavorable comparison concerning the product/brand.

Compute:

- `Relevance % = Related / Reviewed`.
- Sentiment percentages use `Related` as denominator.
- Positive + Neutral + Negative must equal Related.
- Percentages may remain blank when the denominator is zero.

Summarize positive themes and concerns separately in English and Chinese. Exclude publisher replies from audience totals by default. Preserve a source-visible evidence trail for classifications and note sampling/pagination limitations.

For Sheet1 `Sentiment`, use comment evidence when sufficient. If comments are unavailable or immaterial, assess the published content itself and label the result as content sentiment in the run manifest. Do not fabricate audience sentiment.

## Daily summary and charts

Maintain an English, date-stamped summary that covers:

- Overall exposure and engagement movements.
- New official versus third-party coverage.
- Comment relevance and positive/neutral/negative shifts.
- Emerging positive themes and concerns.
- Material source-access or sampling limitations.

If charts are configured, preserve exactly the configured chart count and update source ranges to include the new daily block. Recommended views are sentiment mix, daily related-comment volume, positive/negative trend, and official versus third-party comparison.

## Feishu write gate

Classify the first failure precisely:

- `runtime_unavailable`: the browser/connector control runtime cannot initialize; Feishu was not reached.
- `auth_required`: the page is reachable but edit authentication is missing.
- `page_loading`: the direct Wiki page never becomes usable.
- `grid_not_interactive`: page chrome loads but the sheet cannot select/read cells.
- `readback_mismatch`: the requested rectangular range cannot be reproduced exactly.
- `write_failure`: a changed cell does not match immediate readback.

Only the last five are Feishu/page/session outcomes. Do not report `runtime_unavailable` as “Feishu failed.”

1. Prefer a structured Feishu connector that supports exact range reads/writes and value readback. Otherwise use the host agent's signed-in interactive browser. First verify that the control runtime initializes, then open one direct Wiki tab and allow at most 15 seconds for title, sheet tabs, name box, and visible grid content.
2. Confirm edit access. A title, login state, formula-bar value, or loading canvas is not sufficient.
3. Read a real rectangular range from both sheets before any write. Batch baseline reads to at most 20 rows/cells.
4. If the primary browser fails, try one fresh authenticated browser session once. Do not loop browser recovery.
5. On failure, leave Feishu and persistent state unchanged and mark the run `blocked_without_mutation`. A compact read-only discovery snapshot may still be staged for replay if source collection is independently safe.

## Single-cell write protocol

For every changed field:

1. Select the exact address through the name box.
2. In a browser canvas, edit the visible formula bar or use the client's equivalent single-cell edit action such as F2.
3. Select all existing content, clear it, type exactly one field, and press Enter.
4. Reselect the same address, wait about 250 ms, and read the formula bar.
5. Require the formula-bar value and visible grid screenshot to agree.

Never paste multiple cells. Validate one rectangular range after each batch.

Use two acceptance layers:

- Data-sync QA: exact changed-cell readback, row alignment, canonical URL uniqueness, and Total formulas covering numeric rows. Passing this layer permits a verified source-state commit.
- Presentation QA: reserve rows, Methodology boundary, chart count/ranges, daily summary, and brief/site consistency. Failure here blocks presentation outputs and deployment but does not erase an already verified source-data checkpoint.

## Downstream gate

Only after data-sync QA may source state be committed. Only after presentation QA may the workflow update charts, generate image/text briefs, rebuild a campaign site, or deploy it. If source data and narrative are unchanged, skip site deployment and return a concise no-change status.
