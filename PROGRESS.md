# Progress Log

Development progress log for kubecon-2026-gitops. Tracks implementation milestones across PRD work.

## PRD #1: OTel-to-Datadog Telemetry Export (Closed 2026-03-08)

**Outcome: Original branch abandoned.** Whitney built a full pipeline on `feature/prd-1-otel-to-datadog` (count connector, Datadog exporter, Flagger canary, validated end-to-end on GKE). Meanwhile, Thomas independently built the pipeline his way (transform+spanmetrics, `service.name` for variant comparison). Rather than merge-conflict the two approaches, Whitney told Thomas to ignore the original branch and will make a new branch with smaller incremental changes on top of Thomas's work.

### What Whitney learned (carries forward)
- Count connector vs transform+spanmetrics tradeoffs
- `deltatocumulative` processor required for count connector + Prometheus
- ServiceMonitor required for Prometheus Operator (not pod annotations)
- Division-by-zero PromQL protection for Flagger MetricTemplates
- Cluster setup/teardown scripts for independent testing
- Canary rollout mechanics validated end-to-end

### What's next (new branch on Thomas's main)
- Add Datadog exporter config to Thomas's collector
- Inject Anthropic API key into existing `anthropic` secret
- Add resource request limits on Knative service
- Add `deltatocumulative` processor

## [Unreleased]

### Added
- (2026-03-11) PRD #2 M1 Research complete: dashboard design, variant tagging strategy, story.part integration plan
  - Variant differentiation works via existing `service.name` (pod label → Datadog `service` tag) — no app change needed
  - `story.part` attribute requires app + collector changes (dependency on companion app image push)
  - Dashboard layout designed: 7 widgets in 3 groups (Vote Totals, Vote Trends, Deep Dive), TV mode, dark theme

### Changed
- (2026-03-12) Knative Service manifest: reduced resource limits (200m/128Mi → 500m/256Mi) and enabled scale-to-zero (min 0, max 5) — app is now stateless
- (2026-03-12) `story.part` dependency resolved — attribute live in rebuilt container images, M2 unblocked

- (2026-03-12) Datadog dashboard created via API — 7 widgets across 3 groups (Vote Totals, Vote Trends, Deep Dive)
  - `scripts/create-dashboard.sh` and `scripts/delete-dashboard.sh` for reproducible dashboard management
  - Dashboard ID: `68y-xeg-j6s`, TV mode URL available for live demo projection
  - Metric: `gen_ai.calls` with dimensions `gen_ai.evaluation.score.label` and `story.part`

### Fixed
- (2026-03-13) Instrumentation CR now deployed to correct namespace — was hardcoded to `observability`, removed so FluxCD `targetNamespace: apps` applies; added to kustomization resources (PRD #3, M1)
- (2026-03-13) runAsUser aligned to 1000 to match Dockerfile `USER 1000` — was 1001 (PRD #3, M2)
- (2026-03-13) Canary metric interval shortened from 5m to 2m — reduces cold-start delay for live demo (PRD #3, M4)

### Added
- (2026-03-13) story-app-1b Knative Service variant for A/B testing — separate service with `app: story-app-1b` label for distinct `service_name` in spanmetrics (PRD #3, M3)
- (2026-03-13) New load test script (`scripts/load-test-votes.sh`) for stateless app — handles warmup, admin advance, responseId capture, configurable vote ratio (PRD #3, M5)
- (2026-03-14) Quarto + Reveal.js presentation project initialized in `slides/` — Mermaid SVG rendering, title slide with architecture overview diagram (PRD #4, M1)
