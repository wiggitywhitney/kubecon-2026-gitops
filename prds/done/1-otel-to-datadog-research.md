# OTel-to-Datadog Research Document

**PRD**: #1 — OTel-to-Datadog Telemetry Export
**Date**: 2026-03-05
**Status**: Complete

## Table of Contents

1. [The Application (scaling-on-satisfaction)](#1-the-application-scaling-on-satisfaction)
2. [The OpenTelemetry Operator](#2-the-opentelemetry-operator)
3. [Datadog Integration Options](#3-datadog-integration-options)
4. [Integration Architecture](#4-integration-architecture)

---

## 1. The Application (scaling-on-satisfaction)

### Telemetry Emitted

The app is a Node.js/Express application using `@opentelemetry/api` v1.9.0 **API only** (no SDK bundled). All telemetry calls are currently no-ops because no SDK is initialized.

**`src/story/generator.js` — LLM generation spans:**

- `tracer.startActiveSpan('generate chat response', { kind: SpanKind.CLIENT })` — creates a span per LLM call
- Span attributes: `gen_ai.operation.name`, `gen_ai.request.model`, `gen_ai.response.id`
- `span.recordException(error)` — logs exceptions as span events
- `span.spanContext()` — extracts SpanContext (traceId, spanId) for propagation to evaluation

**`src/telemetry.js` — User satisfaction evaluation:**

- `tracer.startActiveSpan('evaluate UserSatisfaction', { links: [...] })` — linked to the generation span
- `span.addEvent('gen_ai.evaluation.result', { attributes })` — the critical signal:
  - `gen_ai.evaluation.name`: "UserSatisfaction"
  - `gen_ai.evaluation.score.label`: "thumbs_up" or "thumbs_down"
  - `gen_ai.evaluation.score.value`: 1.0 or 0.0
  - `gen_ai.evaluation.response_id`: links to the AI response

**`src/routes/api.js` — Vote endpoint:**

- `POST /story/:part/vote` calls `emitEvaluationEvent()` with vote data and captured spanContext

### Signals That Need to Reach Datadog

| Signal | Source | Purpose |
|--------|--------|---------|
| **Traces** | Generation spans + evaluation spans | End-to-end visibility of LLM calls and user votes |
| **Span Events** | `gen_ai.evaluation.result` on evaluation spans | User satisfaction data — drives Flagger canary decisions |
| **Metrics** (derived) | OTel Collector count connector aggregates span events | Prometheus metrics for Flagger (vote counts per variant) |
| **Exception Events** | `span.recordException()` on generation spans | Error visibility |

The `gen_ai.evaluation.result` span events are the most critical signal. They feed Flagger's canary traffic decisions.

### Auto-Instrumentation and API-Only Code

The OTel Operator's auto-instrumentation solves the "API without SDK" problem:

1. Operator webhook detects `instrumentation.opentelemetry.io/inject-nodejs: "true"` annotation
2. Injects an init container that copies instrumentation files to a shared volume
3. Sets `NODE_OPTIONS="--require /otel-auto-instrumentation-nodejs/autoinstrumentation.js"` on the app container
4. The SDK initializes **before** application code loads
5. When the app calls `trace.getTracer()`, it gets a **real tracer** (not a no-op) because the global tracer provider is already initialized

The app's existing API calls become functional without any code changes. Additionally, auto-instrumentation adds spans for Express HTTP handling, outgoing HTTP requests, and other supported libraries.

---

## 2. The OpenTelemetry Operator

### Current Cluster State

The OTel Operator is deployed in `opentelemetry-operator-system` with the `ClusterObservability` feature gate enabled:

```yaml
# infrastructure/observability/opentelemetry-operator-patch.yml
args:
  - --feature-gates=+operator.clusterobservability
```

The `ClusterObservability` CRD is installed (`infrastructure/observability/cluster-observability.yml`) but no instance of it exists in the manifests yet.

### ClusterObservability CRD (v1alpha1)

- **Scope**: Namespaced (despite the "Cluster" prefix)
- **Status**: Alpha — requires explicit feature gate
- **Purpose**: Declares cluster-wide observability policy (where telemetry goes)
- **Key spec fields**:
  - `exporter.endpoint` — main OTLP receiver endpoint
  - Per-signal endpoints: `traces_endpoint`, `metrics_endpoint`, `logs_endpoint`
  - `headers` — custom headers (e.g., API keys)
  - `tls`, `retry_on_failure`, `sending_queue` — transport configuration
- **What it deploys**: When reconciled, the operator creates OTel Collector infrastructure based on the exporter configuration. The exact deployment topology depends on the operator version.

### Instrumentation CRD

- **Scope**: Namespaced
- **Status**: Mature, well-established
- **Purpose**: Configures per-language auto-instrumentation SDK injection
- **How it works**:
  1. Create an `Instrumentation` CR in the target namespace
  2. Annotate pods with `instrumentation.opentelemetry.io/inject-nodejs: "true"`
  3. Operator webhook mutates pod spec: adds init container + environment variables
  4. SDK is injected at pod startup, before application code runs
- **Requirement**: The `Instrumentation` CR must exist **before** annotated pods are created. Otherwise, injection is skipped on first deployment (requires pod restart).

### Relationship: ClusterObservability vs. Instrumentation

They are **complementary, not overlapping**:

- **ClusterObservability** defines the **export pipeline** — where telemetry data goes
- **Instrumentation** defines the **collection mechanism** — how telemetry is gathered from workloads
- Neither manages the other. They work together through the operator.

### Knative Serving Compatibility

**Known issue**: OTel Operator webhook can conflict with Knative's pod creation ([opentelemetry-operator#1514](https://github.com/open-telemetry/opentelemetry-operator/issues/1514)):

- Webhook may create invalid pod specs when pods already have init containers
- Symptom: duplicate `name` fields in init container array, pods stuck in terminating state
- Knative creates init containers for its own purposes

**Mitigations**:

- Ensure the `Instrumentation` CR exists before the Knative Service is created
- Test pod creation/deletion in a staging environment before the demo
- Monitor for orphaned pods with invalid init containers

---

## 3. Datadog Integration Options

### Option 1: Datadog Agent with OTLP Intake

The Datadog Agent runs as a DaemonSet and accepts OTLP over gRPC/HTTP.

| Signal | Status | Notes |
|--------|--------|-------|
| Traces | **GA** | gRPC and HTTP, since Agent 7.32+ |
| Metrics | **GA** | gRPC and HTTP |
| Logs | **GA** | Disabled by default (opt-in to prevent billing surprises) |

**How it works**: Apps export OTLP to `localhost:4317` (gRPC) or `localhost:4318` (HTTP). The Agent receives, processes, and forwards to Datadog using its configured API key.

**Infrastructure required (Thomas's scope)**:
- Datadog Agent DaemonSet (via Datadog Operator or Helm)
- RBAC: ServiceAccount, ClusterRole, ClusterRoleBinding
- Host mounts: `/proc`, `/sys`, etc.
- Network: hostPorts or `hostNetwork: true`

**Whitney's scope**: Set `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` on app containers.

**Pros**: All signals GA. Well-documented. Agent provides additional Datadog features (APM, infrastructure monitoring).

**Cons**: Heaviest infrastructure footprint. Requires Datadog-specific DaemonSet. `hostNetwork: true` is a security relaxation. Agent is outside OTel ecosystem.

### Option 2: Datadog Direct OTLP Intake (No Agent)

Apps export OTLP directly to Datadog's managed endpoints over HTTPS.

| Signal | Status | Notes |
|--------|--------|-------|
| Traces | **Preview** | Requires CSM approval to enable |
| Metrics | **GA** | Delta temporality only (cumulative rejected with HTTP 400) |
| Logs | **GA** | HTTP Protobuf |

**How it works**: Apps set `OTEL_EXPORTER_OTLP_ENDPOINT=https://opentelemetry.datadoghq.com` with API key in headers.

**Infrastructure required**: None (zero cluster infrastructure). Egress firewall rules to Datadog endpoints.

**Whitney's scope**: OTLP exporter env vars, API key secret management, SDK delta temporality configuration.

**Pros**: Simplest infrastructure. Entirely within Whitney's scope. No cluster components needed.

**Cons**: Traces are Preview (needs CSM approval — likely explains why Thomas got logs but not traces). Metrics must be delta (OTel SDK defaults may not match). No local processing (sampling, enrichment). API key must be distributed to every pod.

### Option 3: OTel Collector with Datadog Exporter

A standalone OTel Collector uses the `datadogexporter` from `opentelemetry-collector-contrib` to export to Datadog APIs.

| Signal | Status | Notes |
|--------|--------|-------|
| Traces | **Beta** (stable, production-ready) | Fully supported |
| Metrics | **Beta** (stable, production-ready) | Fully supported |
| Logs | **Beta** (stable, production-ready) | Fully supported |

**How it works**: Apps export OTLP to the Collector (in-cluster). The Collector processes data (batching, enrichment, aggregation) and exports to Datadog using the `datadogexporter`.

**Infrastructure required**: OTel Operator must be deployed (already done). The `OpenTelemetryCollector` CR can live in any namespace the operator watches (all namespaces by default). Requires the contrib image (`otel/opentelemetry-collector-contrib`) specified via `spec.image`.

**Whitney's scope**: Everything — `OpenTelemetryCollector` CR, collector config, API key Secret, `OTEL_EXPORTER_OTLP_ENDPOINT` env var. All deployed under `apps/` via FluxCD.

**Key configuration requirements**:
- `datadogconnector` needed for APM stats computation
- `batch` processor with `timeout: 10s` required for trace processing
- Hostname detection can timeout before liveness probes — needs careful tuning

**Pros**: All signals supported. Stays within OTel ecosystem. Local processing (sampling, batching, enrichment). No Datadog-specific infrastructure (Agent). Collector can also aggregate span events into metrics via the `count` connector (critical for Flagger).

**Cons**: `datadogexporter` is beta (though stable and actively maintained). Additional component to manage. Requires contrib image (operator default is core).

### Comparison Matrix

| Factor | Agent + OTLP | Direct Intake | OTel Collector |
|--------|-------------|---------------|----------------|
| Traces status | GA | **Preview** | Beta (stable) |
| All signals working | Yes | No (traces blocked) | Yes |
| Infrastructure needed | DaemonSet | None | Collector deployment |
| Whitney's scope | Env vars only | Full config + secrets | **Everything (Collector CR + app config)** |
| Thomas's scope | Heavy (DaemonSet, RBAC) | Firewall only | **None (Operator already deployed)** |
| Span event aggregation | No | No | **Yes (count connector)** |
| OTel-native | No | Partial | **Yes** |
| Flagger integration | Needs custom metrics | Needs custom metrics | **Built-in via count connector** |

---

## 4. Integration Architecture

### Recommended Approach: OTel Collector with Datadog Exporter

**Decision**: Use the OTel Collector with `datadogexporter` (Option 3).

**Rationale**:

1. **Traces work**: Direct intake (Option 2) has traces in Preview requiring CSM approval — this likely explains Thomas's failed attempt. The Collector approach avoids this entirely.
2. **Count connector**: The Collector's `count` connector can aggregate `gen_ai.evaluation.result` span events into Prometheus metrics that Flagger consumes for canary decisions. This is the only option that supports this without custom application code.
3. **OTel-native**: Uses standard OTel components. No vendor-specific DaemonSets. Aligns with the demo's OTel-centric narrative.
4. **Lighter than Agent**: No DaemonSet, host mounts, or `hostNetwork`. Just a Collector Deployment or Sidecar.
5. **Entirely within Whitney's scope**: The OTel Operator watches all namespaces by default. An `OpenTelemetryCollector` CR deployed in the `apps` namespace (via FluxCD) is reconciled without any infrastructure changes. The CR supports custom images (`spec.image: otel/opentelemetry-collector-contrib`) and arbitrary collector config.

### End-to-End Data Flow

```text
[Knative Service: scaling-on-satisfaction]
    |
    | (OTel Operator injects SDK via Instrumentation CR)
    | (App's @opentelemetry/api calls become functional)
    |
    v
[OTLP Export (gRPC :4317)]
    |
    v
[OTel Collector (OpenTelemetryCollector CR in apps namespace)]
    |
    |-- datadogconnector --> APM stats
    |-- count connector --> gen_ai.evaluation.result metrics --> Prometheus (for Flagger)
    |-- batch processor (timeout: 10s)
    |
    v
[datadogexporter]
    |
    v
[Datadog] (traces, metrics, logs)
```

### Scope Division — Revised

**Key finding**: The OTel Operator watches all namespaces by default (`WATCH_NAMESPACE` defaults to empty = all). The `OpenTelemetryCollector` CR is namespaced and supports custom images via `spec.image`. This means Whitney can deploy the entire pipeline under `apps/`.

**Whitney's scope (apps/) — everything:**

| Resource | Purpose |
|----------|---------|
| `OpenTelemetryCollector` CR | Deploy Collector with contrib image, datadogexporter, datadogconnector, count connector |
| `Instrumentation` CR | Configure Node.js auto-instrumentation |
| Knative Service annotation | `instrumentation.opentelemetry.io/inject-nodejs: "true"` |
| OTLP endpoint env var | Point app at Collector service |
| Datadog API key Secret | Referenced by Collector for export auth |
| Flagger `Canary` CR | Define metric check using count-connector-derived metrics |

**Thomas's scope**: None. The OTel Operator is already deployed and watching all namespaces.

### Datadog API Key Management

The Datadog API key needs to reach the OTel Collector. Options:

1. **Kubernetes Secret** (recommended): Whitney creates a Secret in the `apps` namespace. Collector config references it via `${DD_API_KEY}` environment variable. The Secret manifest in Git uses a placeholder; the actual key is applied separately (or via External Secrets Operator if available).
2. **Direct in Collector config**: Not recommended (secret in plain text in Git).

The app does **not** need the API key. The app exports OTLP to the Collector; the Collector handles Datadog authentication.

### ClusterObservability: Not Used

The cluster has the `ClusterObservability` CRD and feature gate enabled, but the CRD schema only supports OTLP-style export configuration (endpoint, headers, TLS). It does not support custom exporters like `datadogexporter` or arbitrary collector config. Using the `OpenTelemetryCollector` CR directly is the better approach.

### Knative Compatibility Plan

1. Create `Instrumentation` CR in `apps` namespace **before** deploying annotated Knative Services
2. Test in a staging cluster: create Knative Service with annotation, verify init container injection
3. Monitor for the duplicate init container name bug ([#1514](https://github.com/open-telemetry/opentelemetry-operator/issues/1514))
4. If issues arise, fall back to manual SDK configuration in the container image (last resort)

---

## Sources

- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/kubernetes/operator/)
- [Auto-Instrumentation with OTel Operator](https://opentelemetry.io/docs/platforms/kubernetes/operator/automatic/)
- [Datadog OTLP Ingestion by the Agent](https://docs.datadoghq.com/opentelemetry/setup/otlp_ingest_in_the_agent/)
- [Datadog OTLP Intake Endpoint](https://docs.datadoghq.com/opentelemetry/setup/otlp_ingest/)
- [Datadog OTel Collector Exporter](https://docs.datadoghq.com/opentelemetry/otel_collector_datadog_exporter/)
- [opentelemetry-collector-contrib datadogexporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/exporter/datadogexporter/README.md)
- [OTel Operator Issue #1514: Webhook invalid pod spec](https://github.com/open-telemetry/opentelemetry-operator/issues/1514)
- [Datadog Node.js OTel API Support](https://docs.datadoghq.com/opentelemetry/instrument/api_support/nodejs/)
