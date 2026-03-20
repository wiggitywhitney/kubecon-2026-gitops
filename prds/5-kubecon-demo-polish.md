# PRD #5: KubeCon Demo Polish — Slides, Dashboards, QR Codes

**Issue**: [#5](https://github.com/wiggitywhitney/kubecon-2026-gitops/issues/5)
**Status**: Draft
**Priority**: High
**Created**: 2026-03-20

## Problem

Thomas rewrote the demo app in Java/Spring Boot with PostgreSQL persistence, switched from Anthropic to Mistral AI (with Anthropic big coming for the expensive variant), and restructured the GitOps repo. The existing slides, dashboards, and demo assets reference outdated architecture:

- Model names wrong (slides say Sonnet 4 / Haiku 4.5 / Opus 4.6)
- Architecture diagrams show two separate Knative Services per round — now it's one service with Flagger managing the canary
- Metrics use `story_name` label, not `service_name`
- OTel instrumentation shows Node.js injection — Java app handles its own OTel
- Datadog dashboard lacks Flagger and Knative traffic split metrics
- No QR codes for the live app URLs
- Talk structure agreed (premise → demo 1 → how it works → demo 2 → end credits) needs slide reordering
- "Journey of a thumbs up" sequence diagram may not match Java app's telemetry behavior

## Solution

Update all presentation assets to match current architecture and agreed talk flow. Create dashboards that support each talk moment. Generate QR codes. Investigate telemetry differences.

## Design Notes

- Live app URLs: `https://story-app-1.apps.platform.thomasvitale.dev/` and `https://story-app-2.apps.platform.thomasvitale.dev/`
- Speaker split: Whitney = OTel/Metrics (~7 min), Thomas = Flagger/Traffic Splitting (~7 min)
- Each demo ~5 min, ~15 min slides total
- Dashboard should be visible during live demos showing real-time rollout
- Knative metrics available for traffic split visualization
- Flagger metrics now scraped by the OTel Collector (Prometheus receiver)
- Thomas will change models to Anthropic big vs Mistral small (not done yet — use placeholder names until confirmed)

## Milestones

### M1: Slide Corrections
- [ ] Fix model names throughout (remove Sonnet 4, Haiku 4.5, Opus 4.6 references; use current model names or placeholders)
- [ ] Fix architecture diagrams — one Knative Service per story with Flagger canary, not two separate services
- [ ] Update metric label references from `service_name` to `story_name`
- [ ] Remove Node.js OTel injection annotation references — Java app handles its own OTel
- [ ] Update Collector YAML examples to match current config (v0.146.0, `story.name` dimension)
- [ ] Fix container image references (ghcr.io/thomasvitale, not wiggitywhitney Docker Hub)

### M2: Slide Restructuring
- [ ] Reorder slides to match agreed flow: premise → demo 1 → how it works → demo 2 → end credits
- [ ] Add speaker introductions at end (end credits slide)
- [ ] Complete Flagger canary logic slides (M6 TODO currently in deck) — Thomas's section
- [ ] Update "The Reveal" tables with correct variant descriptions
- [ ] Update speaker notes and presenter cues to reflect new flow

### M3: Dashboard Design
- [ ] Map which dashboards appear at which talk moment:
  - Demo 1 voting: live satisfaction scores per variant
  - Whitney's OTel section: trace/span event view (may use existing APM link)
  - Thomas's Flagger section: canary progression, PromQL metric visualization
  - Demo 2 voting: real-time traffic split + canary rollout progression
- [ ] Identify which Flagger and Knative metrics are available in Datadog
- [ ] Decide: update existing dashboard (`68y-xeg-j6s`) vs. create separate dashboards per talk moment

### M4: Dashboard Implementation
- [ ] Create/update Datadog dashboards per the design from M3
- [ ] Add Flagger canary progression widgets (step weight, threshold, rollback events)
- [ ] Add Knative traffic split visualization (% traffic to primary vs canary)
- [ ] Add real-time rollout timeline widget for demo moments
- [ ] Verify dashboards populate correctly with live cluster data (requires Thomas's cluster)

### M5: QR Code Integration
- [ ] Generate QR codes for story-app-1 and story-app-2 live URLs
- [ ] Integrate QR codes into demo slides (replacing "generate QR code in Chrome" presenter cue)
- [ ] Verify QR codes scan correctly on mobile devices

### M6: Journey of a Thumbs Up Investigation
- [ ] Review sequence diagram against Java/Spring Boot OTel behavior
- [ ] Hypothesize what's different (spanContext propagation, span event attachment, auto-instrumentation differences)
- [ ] Get error details from Thomas and diagnose
- [ ] Update sequence diagram slides if the telemetry flow has changed

## Dependencies

- **Thomas's model change**: M1 slide corrections for model names depend on Thomas confirming final model choices (Anthropic big vs Mistral small)
- **Thomas's cluster**: M4 dashboard verification requires live data flowing through the cluster
- **Thomas's error report**: M6 investigation needs Thomas's error details for the thumbs-up journey

## Success Criteria

- Slides accurately reflect current architecture and demo flow
- Dashboards show meaningful real-time data during both live demos
- QR codes work on mobile devices at conference scale
- Presenter can walk through the full talk without referencing outdated information
