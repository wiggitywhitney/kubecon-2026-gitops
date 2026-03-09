# PRD #1: OTel-to-Datadog Telemetry Export

**Status**: Complete
**Completed**: 2026-03-08
**Priority**: High
**Created**: 2026-03-06
**GitHub Issue**: https://github.com/wiggitywhitney/kubecon-2026-gitops/issues/1

## Problem

The demo app (scaling-on-satisfaction) is instrumented with the OpenTelemetry API (`@opentelemetry/api`) but has no SDK — telemetry is not being collected or exported. Thomas attempted to get OTel data to Datadog but only managed logs, not metrics or traces (because Datadog's direct OTLP intake has traces in Preview, requiring CSM approval). The cluster has the OTel Operator deployed, but no collector or auto-instrumentation is configured yet.

## Context

- **App**: Node.js/Express app using `@opentelemetry/api` v1.9.0 (API only, no SDK)
- **Telemetry emitted**: Custom spans and `gen_ai.evaluation.result` span events (thumbs up/down votes)
- **Cluster infrastructure** (Thomas manages):
  - OTel Operator deployed in `opentelemetry-operator-system` (watches all namespaces by default)
  - Flagger for canary deployments
  - Knative Serving for serverless runtime
- **Target backend**: Datadog (traces, metrics, and events)
- **Deployment model**: FluxCD GitOps — manifests pushed to `apps/` auto-deploy to cluster within 1 minute

## Solution

Deploy the entire OTel-to-Datadog pipeline under `apps/` using resources the OTel Operator reconciles:

1. **Instrumentation CR** (`v1alpha1`) — injects Node.js SDK into the app at pod startup
2. **OpenTelemetryCollector CR** (`v1beta1`) — deploys a Collector with the contrib image, configured with:
   - `datadogexporter` — sends traces and metrics to Datadog (dashboards, APM)
   - `datadogconnector` — computes APM stats from traces
   - `count` connector — aggregates `gen_ai.evaluation.result` span events into satisfaction metrics
   - `prometheusexporter` — exposes metrics for Prometheus scraping (Flagger reads these)
3. **Knative Service annotations** — triggers auto-instrumentation
4. **Flagger Canary CR + MetricTemplate** — queries satisfaction metrics from Prometheus for canary traffic decisions

The OTel Operator watches all namespaces by default, so CRs in the `apps` namespace are reconciled without infrastructure changes. Whitney owns the entire pipeline — no dependency on Thomas.

Metrics flow to **both** Datadog (for dashboards and the "wow factor") and Prometheus (for CNCF-native Flagger integration).

## Testing Strategy

Local end-to-end testing using a Kind cluster with the OTel Operator installed. Whitney has a Datadog API key and can obtain an APP key, enabling full pipeline validation (traces appearing in Datadog).

**Test-first approach**: Write the Kind test script as a scaffold defining what "working" looks like, then build manifests to pass it.

### Test layers

1. **Kind integration tests** (`test/e2e/`) — the primary validation:
   - Script creates Kind cluster, installs OTel Operator (helm), applies manifests
   - Verifies `OpenTelemetryCollector` CR reconciles and Collector pod starts
   - Verifies `Instrumentation` CR is accepted
   - Deploys a test pod with auto-instrumentation annotation, sends test spans
   - Confirms traces arrive in Datadog via API query
   - Teardown: deletes Kind cluster
   - Datadog API key injected via `vals exec` (never committed)

2. **Manifest validation** (`kustomize build` + `kubeconform`) — fast, runs pre-commit:
   - Verifies YAML renders correctly and conforms to K8s/CRD schemas
   - Catches syntax errors, missing fields, structural issues

3. **Production deployment** — FluxCD reconciles on push to Thomas's repo:
   - Incremental: Collector first, then Instrumentation, then annotations
   - Failures isolated per resource

### What the Kind tests skip

- Knative Serving (heavy to install on Kind, fragile) — tested on real cluster only
- Flagger canary rollouts — requires Prometheus + traffic, tested on real cluster
- The test uses a plain Pod with auto-instrumentation annotation instead of a Knative Service

## Milestones

### Milestone 0: Research — How to Get OTel Data to Datadog

Research completed. See `prds/1-otel-to-datadog-research.md` for full analysis.

**Deliverables:**
- [x] Research document written to `prds/1-otel-to-datadog-research.md`
- [x] Architecture decision recorded in Decision Log below
- [x] Milestones 1–N below updated to reflect the chosen approach

### Milestone 1: Kind Test Scaffold + OTel Collector Manifests

**Read first:** `prds/1-otel-to-datadog-m1-research.md` sections 1-5, 8-9 (Collector CR, exporters, connectors, pipeline architecture).

Write the test infrastructure first, then build manifests to pass it.

**Research (before writing manifests):**
- [x] Research `OpenTelemetryCollector` CR v1beta1 spec: required fields, config format, image override
- [x] Research `datadogexporter` collector config: required fields, API key reference, batch processor settings
- [x] Research `datadogconnector` config for APM stats
- [x] Research `count` connector config for span event aggregation
- [x] Research Datadog API for querying traces (to verify export in tests)

**Test scaffold:**
- [x] Create `test/e2e/setup-kind.sh` — creates Kind cluster, installs OTel Operator via helm
- [x] Create `test/e2e/test-collector.sh` — applies Collector CR, verifies pod starts and is ready
- [x] Create `test/e2e/test-instrumentation.sh` — applies Instrumentation CR, deploys test pod, verifies SDK injection
- [x] Create `test/e2e/test-datadog-export.sh` — sends test spans, queries Datadog API to confirm traces arrived
- [x] Create `test/e2e/teardown.sh` — deletes Kind cluster
- [x] Create `test/e2e/run-all.sh` — orchestrates full test suite
- [x] Add `.vals.yaml` entries for Datadog API key and APP key

**Manifests (built to pass the tests):**
- [x] Create `OpenTelemetryCollector` CR with contrib image (`otel/opentelemetry-collector-contrib`)
- [x] Configure collector pipeline: OTLP receiver, batch processor, datadogexporter
- [x] Configure `datadogconnector` for APM stats computation
- [x] Configure `count` connector to aggregate `gen_ai.evaluation.result` span events into metrics
- [x] Add `prometheusexporter` to metrics pipeline (dual export: Datadog for dashboards, Prometheus for Flagger)
- [x] Declare `spec.ports` for Prometheus exporter (port 9090) on the Collector CR
- [x] Reference Datadog API key Secret in collector config
- [x] Create placeholder/template for Datadog API key Secret (actual key provided separately)
- [x] Add to Kustomize overlays (`apps/base/hello/` and `apps/cloud/hello/`)
- [x] Validate manifests with `kustomize build`

### Milestone 2: Auto-Instrumentation Setup

Configure the OTel Operator to inject the Node.js SDK into the scaling-on-satisfaction app.

**Read first:** `prds/1-otel-to-datadog-m1-research.md` section 6 (Instrumentation CR spec).

- [x] Create `Instrumentation` CR (`opentelemetry.io/v1alpha1`) in `apps/base/hello/` for Node.js auto-instrumentation
- [x] Set `spec.exporter.endpoint` to `http://otel-collector.apps.svc.cluster.local:4317` (gRPC, matches Node.js default protocol)
- [x] Add `instrumentation.opentelemetry.io/inject-nodejs: "true"` annotation to Knative Service pod template
- [x] Update Kustomize overlays to include the new resources
- [x] Validate manifests with `kustomize build`
- [x] Kind e2e test passes: test pod gets init container injected, sends traces to Collector

Note: `OTEL_EXPORTER_OTLP_ENDPOINT` does NOT need to be set separately on the Knative Service — the Instrumentation CR sets it automatically via the operator webhook.

### Milestone 3: Flagger Canary with Satisfaction Metrics

Define a Flagger Canary resource that uses the count-connector-derived satisfaction metrics for traffic decisions.

**Read first:** `prds/1-otel-to-datadog-m1-research.md` sections 7-8 (Flagger MetricTemplate, Prometheus exporter).

**Research (before writing manifests):**
- [x] Confirm whether Prometheus is already deployed in the cluster (check Flagger helm values, `flagger-prometheus`)
- [x] Determine Prometheus scrape discovery method (ServiceMonitor, annotations, or static config)

**Manifests:**
- [x] Create `MetricTemplate` CR with Prometheus provider querying `gen_ai_evaluation_count_total` (note: OTel→Prometheus name translation adds underscores and `_total` suffix)
- [x] Create `Canary` CR for the hello Knative Service
- [x] Configure canary analysis with satisfaction-rate metric (threshold, interval, iterations)
- [x] If needed: create ServiceMonitor or add Prometheus scrape annotations on the Collector Service
- [x] Update Kustomize overlays
- [x] Validate manifests with `kustomize build`

### Milestone 4: Cluster Setup/Teardown Scripts

Create scripts to provision a test cluster (Kind or GKE) with all prerequisites installed, and tear it down afterward. Adapted from spider-rainbows `setup-platform.sh` / `destroy.sh` patterns.

**Reference:** `/Users/whitney.lee/Documents/Repositories/spider-rainbows/setup-platform.sh` (Kind + GCP dual-mode), `destroy.sh`

- [x] Create `scripts/setup-cluster.sh` supporting `kind` and `gcp` modes
- [x] Kind mode: create cluster, install OTel Operator (helm), install Knative Serving, install Contour, install Flagger + Prometheus (`prometheus.install: true`)
- [x] GCP mode: create GKE cluster in `demoo-ooclock` project, install same components
- [x] Apply manifests from `apps/cloud/hello/` (via `kubectl kustomize | kubectl apply`)
- [x] Create `scripts/teardown-cluster.sh` to clean up Kind or GKE clusters
- [x] Inject Datadog API key via `vals exec` (never hardcoded)
- [x] Test: Kind cluster comes up, Collector pod runs, Instrumentation CR accepted
- [x] Test: GKE cluster comes up with full stack (Knative + Flagger + OTel pipeline)

### Milestone 5: End-to-End Validation on Test Cluster

Verify the full pipeline works on a provisioned test cluster. Validate from phone and in Datadog UI.

- [x] Provision test cluster using `scripts/setup-cluster.sh gcp`
- [x] Verify OTel Collector pod is running in `apps` namespace
- [x] Verify auto-instrumentation init container injection on Knative Service pods
- [x] Load app on phone, submit votes
- [x] Confirm traces appear in Datadog APM
- [x] Confirm `gen_ai.evaluation.result` span events are visible in Datadog
- [x] Confirm satisfaction metrics appear in Datadog dashboard (dual export working)
- [x] Confirm Flagger reads satisfaction metrics from Prometheus — validated: `rate(gen_ai_evaluation_count_total[1m])` returns non-NaN with sustained vote traffic. Required `deltatocumulative` processor fix and ServiceMonitor for Prometheus Operator scraping.
- [x] Pin Knative Service to exactly 1 replica (`min-scale: "1"`, `max-scale: "1"`). Knative has no sticky sessions, so scaling up would break in-memory state. One Node.js instance handles 500 concurrent users easily (Express benchmarks ~15k req/s; vote POSTs are trivial). Add resource requests/limits (cpu: 500m/1000m, memory: 256Mi/512Mi) to sustain live demo audience load.
- [x] Test canary rollout with thumbs up/down votes — canary successfully promoted on GKE cluster: Progressing (10→20→30→40→50) → Promoting → Finalising → Succeeded. Satisfaction-rate metric at 100% (all thumbs_up), threshold 60% passed. Required fixes: `deltatocumulative` processor, ServiceMonitor, MetricTemplate address update to `prometheus-prometheus.observability:9090`, division-by-zero PromQL protection.
- [x] **PRD EXIT GATE**: Tear down test cluster using `scripts/teardown-cluster.sh` — teardown initiated 2026-03-08

## Dependencies

- **Datadog API key**: Whitney has this. Required for Collector's datadogexporter.
- **Datadog APP key**: Needed for e2e test trace verification only (not in production manifests). Whitney can create one in Datadog org settings.
- **Container images**: Published on Docker Hub: `wiggitywhitney/story-app-1a:latest`, `wiggitywhitney/story-app-1b:latest`, `wiggitywhitney/story-app-2a:latest`, `wiggitywhitney/story-app-2b:latest`
- **Local tools**: `kind`, `helm`, `kubectl`, `kustomize`, `kubeconform` for local testing
- **Prometheus in cluster**: Needed for Flagger to read satisfaction metrics. May already be deployed with Flagger — needs verification (M3 research item).
- **No infrastructure dependencies**: OTel Operator already deployed on Thomas's cluster

## Risks

- **Knative + auto-instrumentation**: OTel Operator webhook may conflict with Knative init containers ([#1514](https://github.com/open-telemetry/opentelemetry-operator/issues/1514)). Mitigation: create Instrumentation CR before annotating Knative Service; Kind tests use plain Pods; real cluster validates Knative compatibility.
- **Contrib image availability**: The `otel/opentelemetry-collector-contrib` image must be pullable. Public Docker Hub image — should be fine.
- **Kind vs real cluster divergence**: Kind tests skip Knative/Flagger. Some issues only surface on the real cluster. Mitigated by incremental deployment on push.
- **Collector resource usage**: Running a Collector Deployment in the `apps` namespace adds resource overhead. A single-replica Deployment should be sufficient for a demo.
- **Prometheus availability**: Flagger needs Prometheus to read satisfaction metrics. If Prometheus isn't in the cluster, fallback is to use Flagger's Datadog provider directly (supported but adds external API dependency to canary decisions). M3 research item will verify.

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-06 | Use OTel Operator auto-instrumentation | App uses API-only (no SDK), operator can inject SDK at runtime |
| 2026-03-06 | Track PRD on fork | Whitney can't create issues on Thomas's repo; fork keeps workflow invisible |
| 2026-03-06 | Research-first approach | Multiple viable integration paths; need to investigate before committing to implementation milestones |
| 2026-03-05 | OTel Collector + datadogexporter | Direct OTLP intake has traces in Preview (needs CSM approval — explains Thomas's failure). Collector approach: all signals work, count connector enables span-event-to-metric aggregation for Flagger, stays OTel-native. See `prds/1-otel-to-datadog-research.md`. |
| 2026-03-05 | Deploy everything under apps/ | OTel Operator watches all namespaces by default. OpenTelemetryCollector CR supports custom images (contrib) and arbitrary collector config. No infrastructure changes needed — Whitney owns the entire pipeline. |
| 2026-03-05 | Kind e2e tests with real Datadog export | Whitney has Datadog API key. Kind cluster + OTel Operator tests full pipeline locally. Skips Knative/Flagger (tested on real cluster). Test-first: write test scaffold, then build manifests to pass it. |
| 2026-03-07 | Dual export: Prometheus for Flagger, Datadog for dashboards | Count connector metrics fan out to both exporters in the same pipeline. Prometheus keeps Flagger in-cluster (no external API dependency for canary decisions). Datadog provides rich dashboards and monitoring. No architectural conflict — OTel Collector supports multiple exporters per pipeline. |
| 2026-03-07 | Instrumentation CR sets OTEL_EXPORTER_OTLP_ENDPOINT automatically | Research confirmed the operator webhook injects the env var from `spec.exporter.endpoint`. No need to set it separately on the Knative Service. Removed redundant M2 item. |
| 2026-03-07 | Use gRPC (port 4317) for Node.js auto-instrumentation | Official OTel Operator docs confirm Node.js defaults to gRPC protocol. Using port 4317 avoids needing a protocol override. The Collector exposes both 4317 (gRPC) and 4318 (HTTP) by default. |
| 2026-03-07 | Custom spans work with auto-instrumentation | App uses `@opentelemetry/api` v1.9.0 (API only, no SDK). Auto-injected SDK registers a global TracerProvider; app's `trace.getTracer()` picks it up via shared `Symbol.for('opentelemetry.js.api.1')`. Custom spans and span events export normally. |
| 2026-03-07 | Pin collector image to v0.113.0 (match operator) | Operator helm chart v0.74.0 injects `service.telemetry.metrics.address` which was removed in collector v0.123.0+. Using v0.113.0 (the operator's default) avoids the crash. Real cluster may need a different version depending on its operator version. |
| 2026-03-08 | Prometheus not deployed; proceed with assumption | Flagger HelmRelease has `prometheus.install: false` (default). Whitney asked Thomas to enable it. Kind tests install Prometheus. Manifests target `http://flagger-prometheus.flagger-system:9090`. |
| 2026-03-08 | Annotation-based Prometheus scrape discovery | Flagger's bundled Prometheus uses `prometheus.io/scrape` pod annotations. Added `podAnnotations` to Collector CR instead of ServiceMonitor (simpler, no Prometheus Operator dependency). |
| 2026-03-08 | Flagger Knative provider for canary rollouts | Canary CR uses `provider: knative` with `targetRef` pointing to Knative Service. No `spec.service` section needed — Flagger manages traffic via Knative revision-based splitting. |
| 2026-03-08 | Simplified PromQL query (no namespace filter) | Single-app demo doesn't need namespace filtering in MetricTemplate query. Can add label filtering once actual metric labels are visible in test cluster. |
| 2026-03-08 | Fix count connector attribute: `gen_ai.evaluation.score.label` not `vote` | Cross-referenced scaling-on-satisfaction README. The app emits `gen_ai.evaluation.score.label` = `thumbs_up`/`thumbs_down` on span events. Count connector and MetricTemplate updated to match actual attribute name. |
| 2026-03-08 | Build container images for amd64 | GKE nodes are amd64; images built on Apple Silicon were arm64-only. Added `--platform linux/amd64` to build scripts in companion repo. |
| 2026-03-08 | Setup script handles all secrets via vals exec | Script creates `datadog-secret`, `datadog-app-key`, and `anthropic-api-key` secrets after kustomize apply (overwriting placeholders). PATH/HOME restored for vals exec compatibility. |
| 2026-03-08 | ANTHROPIC_API_KEY wired to Knative Service | App requires this env var to start. Added secretKeyRef to service.yml pointing at `anthropic-api-key` secret. |
| 2026-03-08 | Querying span events in Datadog requires two-step search | Span events (like `gen_ai.evaluation.result`) are not standalone spans — they're embedded in parent spans. The Datadog spans search API (`/api/v2/spans/events/search`) won't find them by event name. Method: (1) search for the HTTP span by URL pattern (`@http.url:*vote*`), (2) get its `trace_id`, (3) search all spans in that trace (`trace_id:<id>`), (4) find the `evaluate UserSatisfaction` span from the `scaling-on-satisfaction` library — its `events` field contains the span event with `gen_ai.evaluation.score.label` (thumbs_up/thumbs_down). |
| 2026-03-08 | Prometheus metrics from count connector are ephemeral | The collector's `/metrics` endpoint exposes count connector counters, but they disappear after Prometheus scrapes them (counter resets). Prometheus is the persistent store for these metrics. Don't rely on the collector endpoint for verification — use Datadog traces or Prometheus queries. |
| 2026-03-08 | Count connector is superior to transform+spanmetrics for span event metrics | Researched both approaches. The count connector has a first-class `spanevents` section that filters directly by event name and attributes — purpose-built for this. Thomas's approach (transform processor copying event attrs to parent span + spanmetrics connector) is a 2-component workaround for spanmetrics' inability to natively access event attributes (see closed issue #27451). Count connector is simpler, more correct (counts events not spans), and handles multiple events per span correctly. |
| 2026-03-08 | Dual export confirmed: Prometheus for Flagger, Datadog for dashboards | Prometheus Operator stores data locally on the cluster (emptyDir by default). Flagger's Datadog provider has a 5-second HTTP timeout per query — at a conference with flaky WiFi, an API outage halts the canary ("no values found" = halt advancement). In-cluster Prometheus has zero network dependency. Use Prometheus for the canary decision loop (reliability), Datadog for audience-facing dashboards (visualization). |
| 2026-03-08 | Upgrade setup script to Prometheus Operator (match Thomas's stack) | Thomas installed the full Prometheus Operator with ServiceMonitor CRs instead of Flagger's bundled Prometheus. Whitney's setup script should match to learn and validate the full stack. ServiceMonitor-based scraping is more robust than annotation-based. Requires updating `scripts/setup-cluster.sh` to install Prometheus Operator helm chart and switching from `podAnnotations` to ServiceMonitor for collector scraping. |
| 2026-03-08 | Thomas restructured repo: `apps/platform/story-app-1/` replaces `apps/cloud/hello/` | Thomas renamed the app from `hello` to `story-app-1`, moved infrastructure (Collector, Instrumentation CR) to `infrastructure/observability/`, and added `clusters/platform/` + `apps/platform/` paths. Feature branch manifests need reconciliation with new structure before PR. Collector is now in `observability` namespace (not `apps`), endpoint is HTTP 4318 (not gRPC 4317). |
| 2026-03-08 | Prometheus Operator stores data locally on the cluster | By default, Prometheus Operator uses `emptyDir` volumes (ephemeral — data lost on pod restart). PersistentVolumeClaims must be explicitly configured for data retention. For the demo, ephemeral is fine — only need enough data for the canary check window, not long-term retention. Prometheus is an in-cluster time-series database, not a relay — it doesn't send data elsewhere. |
| 2026-03-08 | Setup/teardown scripts need Prometheus Operator support | Current setup script installs Flagger's bundled Prometheus (`prometheus.install: true`). Need to replace with: (1) install Prometheus Operator via helm (`prometheus-community/kube-prometheus-stack` or `prometheus-operator/prometheus-operator`), (2) create ServiceMonitor for OTel Collector scraping instead of pod annotations, (3) update MetricTemplate address from `flagger-prometheus.flagger-system:9090` to `prometheus-prometheus.observability:9090` (or whatever Thomas's Prometheus service is named). Teardown script should be fine as-is (cluster deletion cleans up everything). |
| 2026-03-08 | Tear down GKE cluster — validation complete | Pipeline confirmed working: `gen_ai_evaluation_count_total` metric in Prometheus (value=1 after vote, with `gen_ai_evaluation_score_label=thumbs_up`), `gen_ai.evaluation.count` metric in Datadog. Flagger canary rollout not yet tested (blocked on sustained vote traffic for rate() to produce non-NaN values — will test on Thomas's cluster with access). Tearing down to stop costs (~$0.57/hr). |
| 2026-03-08 | Pin Knative Service to exactly 1 replica | Knative has no sticky session / session affinity support (issue #8160, Icebox since 2020). Scaling to multiple replicas would break in-memory sessions (story state, vote tracking). One Node.js instance easily handles 500 concurrent users — Express benchmarks at ~15k req/s, and vote POSTs are trivial. Bottleneck is Anthropic API calls (I/O-bound). Add `autoscaling.knative.dev/min-scale: "1"` and `max-scale: "1"` annotations. Resource recommendation: cpu 500m/1000m, memory 256Mi/512Mi. |
| 2026-03-08 | Count connector requires `deltatocumulative` processor | The count connector emits delta temporality metrics. In v0.113.0, it doesn't set `StartTimestamp` (known bug, issues #19931 and #30203), so the Prometheus exporter's internal delta-to-cumulative conversion fails — each scrape replaces the previous value instead of accumulating. Fix: add `deltatocumulative: {}` processor to the metrics pipeline between the count connector receiver and prometheus exporter. Confirmed working: counter properly accumulates across batches. |
| 2026-03-08 | ServiceMonitor required for Prometheus Operator scraping | Pod annotations (`prometheus.io/scrape`) are ignored by Prometheus Operator — it uses ServiceMonitor CRs. Created ServiceMonitor selecting `app.kubernetes.io/component: opentelemetry-collector` label, targeting the `prometheus` named port (9090), with 15s scrape interval. MetricTemplate address updated from `flagger-prometheus.flagger-system:9090` to `prometheus-prometheus.observability:9090`. |
| 2026-03-08 | Canary rollout validated end-to-end | Triggered canary by changing image from story-app-1b to story-app-1a. Flagger detected new revision, started analysis, advanced weight 10→20→30→40→50, promoted, finalized. Satisfaction-rate metric returned 100% (all thumbs_up votes from load test script), passing the 60% threshold. Full pipeline: app→OTel auto-instrumentation→Collector→count connector→deltatocumulative→prometheus exporter→Prometheus→Flagger MetricTemplate→canary promotion. |
| 2026-03-08 | Division-by-zero protection for MetricTemplate query | Added `> 0` guard on denominator and `or vector(0)` fallback to PromQL query. Without this, periods with no vote traffic return NaN, which Flagger treats as a metric check failure (contributes to failedChecks threshold). CodeRabbit review caught this. |
