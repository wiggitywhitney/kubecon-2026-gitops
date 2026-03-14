# PRD #4: KubeCon EU 2026 Presentation Slides

**GitHub Issue**: [#4](https://github.com/wiggitywhitney/kubecon-2026-gitops/issues/4)
**Priority**: High
**Target**: KubeCon EU 2026 (March 2026)
**Directory**: `slides/`

## Problem

The "Scaling on Satisfaction" talk at KubeCon EU 2026 needs a slide deck that teaches complex concepts (OTel, gen_ai semantic conventions, collector pipelines, Flagger canary logic) through architectural diagrams, and supports two live demo rounds where the audience votes on AI-generated stories while watching the Datadog dashboard in real time.

## Solution

Build a Quarto + Reveal.js presentation with incrementally-built Mermaid diagrams across 6 teaching scenes. The talk interleaves teaching with live demos: Round 1 near the beginning (audience experiences the magic), teaching scenes in the middle (pull back the curtain), Round 2 near the end (now they know the stakes).

## Talk Structure

**Format**: 25-minute co-presentation with Thomas Vitale
**Slides**: Standalone — readable without a presenter (enough context for async consumption)
**Live demos**: Two rounds with Datadog dashboard on screen as votes come in

### Flow

```text
Intro → App Overview → Round 1 Live Demo → Teaching Scenes (Telemetry, Collector, Flagger) → Round 2 Live Demo → Full Loop Recap → Wrap-up
```

### Presenter Roles (to be refined with Thomas)

Whitney and Thomas co-present. Exact handoff points TBD, but the natural split is:
- **Whitney**: App UX, telemetry instrumentation, Datadog dashboard, live demo operation
- **Thomas**: Infrastructure (OTel Collector config, Flagger, FluxCD GitOps model)

## Scene Inventory

### Scene 1: The App — What the Audience Sees
**Purpose**: Ground the audience in the user experience before any infrastructure talk.
**Content**:
- Phone screen showing story text with thumbs up/down buttons
- Two variants exist — audience doesn't know which one they're getting
- Round 1: same story, different tones (dry vs funny), same model
- Round 2: same story, same tone, different models (cheap vs expensive)
**Diagram**: Simple flow — phone → story → vote buttons. Show the two variants side by side.

### Scene 2: The App Architecture
**Purpose**: Show how the app is built to be instrumentation-friendly and scalable.
**Content**:
- Stateless design — no per-user sessions, any replica can serve any request
- Knative scales 0→N (min 1 for the demo)
- Variant differentiation via container images (not feature flags) — different Docker images with different env vars (`VARIANT_STYLE`, `VARIANT_MODEL`)
- `service.name` OTel attribute (from pod label) is what the metrics pipeline uses to distinguish A from B
- SpanContext round-trip: generation span context returned to client, sent back with vote, so evaluation links to generation
- Coordinated admin panel: one button press advances all variants via `VARIANT_URLS`
**Diagram**: Container architecture showing the two Knative Services, shared admin panel, and the spanContext flow between client and server.

### Scene 3: The Telemetry — How a Vote Becomes Data
**Purpose**: Introduce OpenTelemetry and gen_ai semantic conventions.
**Content** (builds incrementally):
1. User taps thumbs up
2. App creates span: `evaluate UserSatisfaction`
3. Span event: `gen_ai.evaluation.result` with attributes:
   - `gen_ai.evaluation.score.label`: `thumbs_up`
   - `gen_ai.evaluation.score.value`: `1.0`
   - `story.part`: `3`
4. Link back to generation span (`chat claude-sonnet-4`) via `gen_ai.response.id`
**Key teaching points**: Span events (not just spans). Gen_ai semantic conventions. Linking evaluation to generation — the OTel-native way to capture user feedback on AI output.
**Diagram**: Span hierarchy showing the HTTP span → evaluate span → span event, with the link arrow back to the generation span.

### Scene 4: The Collector — From Events to Metrics
**Purpose**: Show how the OTel Collector transforms raw telemetry into actionable metrics.
**Content** (builds incrementally):
1. Traces arrive at Collector via OTLP
2. **Transform processor**: promotes span event attributes up to parent span (spanmetrics reads span attributes, not events — this is the non-obvious trick)
3. **Spanmetrics connector**: converts spans into counter metric `gen_ai_calls_total` with dimensions: `service_name`, `span_name`, `gen_ai.evaluation.score.label`, `story.part`
4. Two outputs fork: Prometheus exporter (in-cluster, for Flagger) and Datadog exporter (for dashboards)
**Key teaching points**: The transform "promotion" trick. Spanmetrics as the bridge between traces and metrics. Dual export decouples in-cluster decisions from visualization.
**Diagram**: Pipeline flow — OTLP receiver → transform → spanmetrics → fork to Prometheus + Datadog.

### Scene 5: The Decision — Flagger's Canary Logic
**Purpose**: Show how metrics drive automated rollout decisions.
**Content** (builds incrementally):
1. Prometheus scrapes `gen_ai_calls_total` from collector every 3 seconds
2. Flagger runs PromQL query: `(B's thumbs_up %) - (A's thumbs_up %)`
3. If delta >= 5 percentage points for 3 consecutive checks → advance traffic weight by 10%
4. Traffic split changes: 90/10 → 80/20 → 70/30 → ... → 0/100
5. If delta drops below threshold → rollback to 100% A
**Key teaching point**: Threshold is *relative* (B must be 5pp better than A), not absolute. The system promotes the variant that makes users happier.
**Diagram**: Flagger decision loop — Prometheus → PromQL → threshold check → Knative traffic split → back to users.

### Scene 6: The Full Loop — Closing the Feedback Loop
**Purpose**: Show the complete cycle — audience votes are literally controlling the infrastructure.
**Content**: The full pipeline as one connected flow:
```text
Audience votes → App span events → Collector transforms → Prometheus metrics
  → Flagger queries → Knative traffic split → Audience gets more of the better variant
  → More votes → ...
```
**Key teaching point**: This is a closed-loop system. Subjective user experience (thumbs up/down) drives infrastructure decisions. This is what "scaling on satisfaction" means.
**Diagram**: Full architecture diagram with the feedback loop highlighted.

## Live Demo Moments

### Round 1 (near beginning, after Scene 1-2)
- **What**: Audience opens URL, reads story parts, votes thumbs up/down
- **Variants**: 1a (dry tone) vs 1b (funny tone), same model (Sonnet 4)
- **On screen**: Datadog dashboard showing votes coming in, satisfaction rates per variant
- **Expected outcome**: Funny variant wins, Flagger shifts traffic
- **Duration**: ~3-4 minutes of active voting across 2-3 story parts

### Round 2 (near end, after teaching scenes)
- **What**: Same audience interaction, but now they understand the infrastructure
- **Variants**: 2a (Haiku 4.5, cheap) vs 2b (Opus 4.6, expensive)
- **On screen**: Datadog dashboard + Flagger canary progression
- **Expected outcome**: Expensive model wins on satisfaction, canary promotes it
- **Duration**: ~3-4 minutes
- **Dramatic tension**: The audience now knows their votes are controlling the rollout

## Technical Stack

- **Quarto** for slide generation (actively maintained, native Mermaid support)
- **Reveal.js** output format (web-based, works on any projector)
- **Mermaid** diagrams for architecture visualizations
- **Speaker notes** for presenter cues and handoff points

## Milestones

- [ ] **M1: Quarto project setup** — Initialize `slides/` directory with Quarto config, Reveal.js output format, Mermaid support, and a basic title slide. Verify `quarto preview` works locally.

- [ ] **M2: Talk skeleton with all sections** — Create the full slide outline with section headers, speaker notes placeholders, and empty diagram placeholders for all 6 scenes plus intro/outro. Establish the horizontal flow (sections) and vertical drill-down pattern.

- [ ] **M3: Scene 1-2 slides (App UX + Architecture)** — Build the app overview and architecture diagrams. These set context before Round 1.

- [ ] **M4: Live demo slides (Round 1 + Round 2)** — Create the "demo time" slides with Datadog dashboard placeholder/instructions, audience URL display, and presenter cue notes for both rounds.

- [ ] **M5: Scene 3-4 slides (Telemetry + Collector)** — Build the OTel telemetry and collector pipeline diagrams with incremental reveal. These are the technical core of the talk.

- [ ] **M6: Scene 5-6 slides (Flagger + Full Loop)** — Build the Flagger canary logic and full feedback loop diagrams. Scene 6 ties everything together.

- [ ] **M7: Polish and standalone readability** — Ensure slides are self-contained (readable without presenter). Add context text, refine speaker notes, verify all diagrams render correctly in Quarto Reveal.js.

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-14 | Use Quarto + Reveal.js (not reveal-md) | Quarto is actively maintained, has native Mermaid support, and a richer ecosystem. reveal-md is no longer actively maintained. |
| 2026-03-14 | Slides live in this repo (not a new repo) | The slides are about this demo's architecture — co-locating them keeps everything together. Visible to Thomas, which is fine for a co-presentation. |
| 2026-03-14 | Standalone slides (not visual-aid-only) | Slides should be readable async, so attendees (and Thomas) can review without the presenter. |
| 2026-03-14 | Two live demo rounds interleaved with teaching | Audience experiences the magic first (Round 1), then learns how it works, then experiences it again with understanding (Round 2). More engaging than explain-then-demo. |
| 2026-03-14 | Mermaid for diagrams (not custom SVG or images) | Mermaid is version-controllable, diffable, and editable in markdown. Known Quarto+Reveal.js rendering quirks exist but basic flowcharts work fine. |

## Out of Scope

- **Datadog dashboard modifications** — the dashboard already exists (`68y-xeg-j6s`), slides just display it
- **App changes** — scaling-on-satisfaction repo is separate
- **Infrastructure changes** — no manifest modifications needed for the talk
- **Video recording or export** — live presentation only (PDF export as backup is fine)
- **KubeCon branding/template** — no required template
- **Round 2 manifests** — 2a/2b Knative Services are a separate task if not already deployed
