# PRD #2: Datadog Dashboard for Live Demo Visualization

**Status**: Not Started
**Priority**: High
**Created**: 2026-03-08
**GitHub Issue**: https://github.com/wiggitywhitney/kubecon-2026-gitops/issues/2

## Problem

The OTel-to-Datadog telemetry pipeline is working (PRD #1) — votes land as `gen_ai.evaluation.count` metrics and traces appear in Datadog APM. But there's no presenter-ready dashboard for the KubeCon talk. During the live demo, Whitney and Thomas need a visual that the audience can see on the projector showing:

1. Votes coming in live (thumbs up vs thumbs down) as the room votes
2. Traffic shifting between app variants as Flagger responds to satisfaction

Without this, the "wow factor" of the demo is invisible — the audience votes but can't see the collective result or the automated traffic shift happening in response.

## Context

- **Talk**: "Scaling on Satisfaction: Automated Rollouts Driven by User Feedback" — Platform Engineering Day, KubeCon EU 2026, March 23
- **Demo rounds**:
  - Round 1: A/B test — 50/50 split between dry (1a) and funny (1b) variants, Flagger shifts toward higher satisfaction
  - Round 2: Canary — 100/0 start, Flagger canary-deploys expensive model (Opus 4.6) alongside cheap (Haiku 4.5)
- **Metrics available in Datadog**: `gen_ai.evaluation.count` with `gen_ai.evaluation.score.label` tag (thumbs_up/thumbs_down)
- **Traffic split**: Managed by Flagger via Knative revision-based routing
- **Audience size**: Conference room, everyone voting on phones simultaneously
- **Dashboard must be readable**: Projected on a large screen, visible from the back of the room

## Solution

Build a Datadog dashboard with widgets optimized for live demo projection:

### Vote Visualization
- **Timeseries**: `gen_ai.evaluation.count` grouped by `gen_ai.evaluation.score.label` — two lines (thumbs_up, thumbs_down) climbing in real-time
- **Query Values**: Large number widgets showing total thumbs_up and thumbs_down counts
- **Pie Chart**: Satisfaction ratio (thumbs_up vs thumbs_down percentage)

### Traffic Split Visualization
- Show request count or percentage per app variant/revision as Flagger shifts traffic
- Requires traces to be distinguishable by variant (different `service.version`, pod name, or custom tag)
- May need the app to emit a `variant` tag on spans so Datadog can differentiate 1a vs 1b

### Presentation Concerns
- Large fonts, high contrast, minimal clutter
- Auto-refresh on short interval (15s or less)
- Time range: "Past 15 Minutes" for live feel
- Dashboard URL shareable so Thomas can also access it

## Dependencies

- **PRD #1 complete**: OTel-to-Datadog pipeline must be working (M1-M4 done, M5 in progress)
- **Flagger + Prometheus**: Traffic shifting requires Prometheus (Thomas enabling `prometheus.install: true`)
- **Variant differentiation in traces**: May need app code change to emit a variant identifier tag
- **GKE cluster**: Need a running cluster to test dashboard with real vote data

## Milestones

### Milestone 1: Research — Dashboard Design and Variant Tagging

- [ ] Determine how Datadog differentiates traffic between Knative revisions (service.version, pod labels, custom tags)
- [ ] Check if the app already emits a variant identifier in traces (VARIANT_STYLE, ROUND, or similar)
- [ ] Research Datadog dashboard best practices for live presentation (widget types, refresh rates, large-screen readability)
- [ ] Decide whether variant tagging requires an app code change or can use existing trace attributes
- [ ] Design dashboard layout (wireframe or description of widget arrangement)

### Milestone 2: Vote Dashboard Widgets

- [ ] Create Datadog dashboard with vote timeseries widget (`gen_ai.evaluation.count` by `gen_ai.evaluation.score.label`)
- [ ] Add query value widgets for total thumbs_up and thumbs_down counts
- [ ] Add satisfaction ratio pie chart or bar chart
- [ ] Configure auto-refresh and appropriate time range
- [ ] Test with real votes on a live cluster

### Milestone 3: Traffic Split Visualization

- [ ] Implement variant tagging if needed (app code change or collector config)
- [ ] Add traffic split widget showing request percentage per variant
- [ ] Test during a simulated Flagger canary rollout (requires Prometheus)
- [ ] Verify traffic shift is visible in dashboard as Flagger adjusts weights

### Milestone 4: Presentation Polish and Dry Run

- [ ] Optimize dashboard for projector readability (font sizes, colors, contrast)
- [ ] Test full demo flow: advance story → audience votes → dashboard updates → Flagger shifts traffic
- [ ] Share dashboard URL with Thomas for review
- [ ] Document dashboard setup for reproducibility (API or JSON export)

## Risks

- **Variant tagging gap**: If traces from both variants look identical to Datadog, the traffic split widget won't work. Mitigation: research first (M1), add variant tag to app if needed.
- **Prometheus dependency**: Traffic shifting requires Flagger + Prometheus. If Thomas hasn't enabled Prometheus by demo time, the traffic visualization falls back to manual demonstration. Vote dashboard still works independently.
- **Dashboard refresh lag**: Datadog metric ingestion has some latency (typically 10-30s). For a live demo, votes may take a moment to appear. Mitigation: test actual latency, adjust presenter pacing.
- **Cluster cost**: Testing requires a running GKE cluster (~$0.19/hr). Use the same cluster as PRD #1 M5 validation when possible.

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-08 | Separate PRD from telemetry pipeline | Dashboard/visualization is presentation layer; PRD #1 is data pipeline. Different scope and timeline. |
| 2026-03-08 | Use Datadog Metrics (not Spans) for vote dashboard | `gen_ai.evaluation.count` already lands as a Datadog metric via the count connector + datadogexporter. Metrics are the right data source for timeseries/aggregation widgets. |
