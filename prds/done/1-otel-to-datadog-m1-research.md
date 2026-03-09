# PRD #1 Research: OTel-to-Datadog Pipeline

Research findings for PRD #1. Read this before implementing any milestone.

**Agents must read this file before starting M1, M2, or M3 implementation.**

## 1. OpenTelemetryCollector CR v1beta1 Spec

**API Version**: `opentelemetry.io/v1beta1`

### Required Fields

Only `spec.config` is required, containing `receivers`, `exporters`, and `service`. Everything else has defaults.

### Config Format (v1beta1 vs v1alpha1)

v1beta1 uses **structured YAML** (not a raw string). The config is a typed struct:

```yaml
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
    exporters:
      debug: {}          # Use {} for empty config, not blank
    service:
      pipelines:
        traces:
          receivers: [otlp]
          exporters: [debug]
```

### Image Override

```yaml
spec:
  image: otel/opentelemetry-collector-contrib:0.147.0
```

Use a version compatible with the deployed OTel Operator. Operator helm chart v0.74.0 ships operator v0.113.0 and defaults to collector v0.113.0. Using a collector version that's too new (e.g., v0.147.0) causes crashes because the operator injects `service.telemetry.metrics.address` which was removed in newer collector versions (see [operator issue #3730](https://github.com/open-telemetry/opentelemetry-operator/issues/3730)).

Note: otelcol-contrib is fine for a demo. For production, Datadog recommends DDOT (Datadog Distribution of OTel Collector). For a CNCF-focused KubeCon demo, contrib is the right vendor-neutral choice.

### Mode

Set via `spec.mode`: `deployment` (default), `daemonset`, `statefulset`, `sidecar`.

### Environment Variables from Secrets

```yaml
spec:
  env:
    - name: DD_API_KEY
      valueFrom:
        secretKeyRef:
          name: datadog-secret
          key: api-key
```

Reference in collector config: `${env:DD_API_KEY}`. Expansion happens at collector startup. Default values supported: `${GRPC_PORT:-4317}`.

### Ports and Service

The operator auto-creates a Service named `{collector-name}-collector`. Ports are inferred from receiver config (e.g., OTLP gRPC 4317, HTTP 4318). Manual `spec.ports` only needed for ports the operator can't detect.

### Other Notable Fields

- `replicas` (default: 1)
- `resources` (requests/limits)
- `serviceAccount`, `volumes`, `volumeMounts`
- `securityContext`, `podSecurityContext`

## 2. Datadogexporter Config

### Required Fields

Only `api.key` is mandatory. `api.site` defaults to `datadoghq.com`.

```yaml
exporters:
  datadog:
    api:
      key: ${env:DD_API_KEY}
      site: datadoghq.com
      fail_on_invalid_key: true
```

### Traces Config

```yaml
    traces:
      compute_stats_by_span_kind: true    # default since v0.116.0
      peer_tags_aggregation: true          # default since v0.116.0
```

**Important**: The exporter now skips APM stats computation by default. The **datadogconnector** is required for APM stats.

### Metrics Config

```yaml
    metrics:
      histograms:
        mode: distributions    # recommended for Datadog
      summaries:
        mode: gauges
```

### Batching

Datadog recommends the exporter's built-in `sending_queue.batch` over a standalone `batch` processor (trace intake limit is 3.2MB). For a demo, a simple `batch` processor with `timeout: 10s` is fine.

## 3. Datadogconnector (APM Stats)

### Purpose

Derives APM statistics (request rate, error rate, latency percentiles) from trace data and outputs them as metrics. **Required** for services to appear in Datadog APM Service Catalog.

### Config

```yaml
connectors:
  datadog/connector:
    traces:
      compute_stats_by_span_kind: true
      compute_top_level_by_span_kind: true
      peer_tags_aggregation: true
```

### Pipeline Wiring

The connector appears as an **exporter** in a traces pipeline and a **receiver** in a metrics pipeline. It can also forward traces to a downstream traces pipeline.

**Recommended pattern (no sampling)**:

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [datadog/connector, datadog]

    metrics:
      receivers: [otlp, datadog/connector]
      processors: [batch]
      exporters: [datadog]
```

**Pattern with trace forwarding** (enables sampling downstream):

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [datadog/connector]

    traces/datadog:
      receivers: [datadog/connector]
      processors: [batch]
      exporters: [datadog]

    metrics:
      receivers: [otlp, datadog/connector]
      processors: [batch]
      exporters: [datadog]
```

## 4. Count Connector (Span Event Aggregation)

### Purpose

Counts telemetry signals (spans, span events, metrics, data points, logs) and produces metrics. Alpha stability.

### Config for gen_ai.evaluation.result

```yaml
connectors:
  count:
    spanevents:
      gen_ai.evaluation.count:
        description: "Count of user satisfaction evaluation events"
        conditions:
          - 'name == "gen_ai.evaluation.result"'
        attributes:
          - key: vote
            default_value: unknown
```

### Key Details

- **Conditions use OTTL** — bare `name` and `attributes["key"]` syntax (not `spanevent.name`)
- **Multiple conditions are ORed** — matching any one condition counts the event
- **Custom metrics suppress defaults** — defining custom `spanevents` metrics suppresses `trace.span.event.count`
- **Attribute precedence**: span event attrs > scope attrs > resource attrs
- **Output**: monotonic delta Sum metric

### Pipeline Wiring

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [count, datadog/connector]

    metrics/satisfaction:
      receivers: [count]
      processors: [batch]
      exporters: [datadog]
```

## 5. Datadog Trace Query API (for e2e tests)

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v2/spans/events` | Simple list/filter spans |
| POST | `/api/v2/spans/events/search` | Complex search |
| POST | `/api/v2/spans/analytics/aggregate` | Count/stats |

Base URL: `https://api.datadoghq.com` (US1 default)

### Authentication

Two headers required:
- `DD-API-KEY` — identifies account
- `DD-APPLICATION-KEY` — authorizes read access

### Simplest Verification (for e2e tests)

```bash
curl -s -X GET \
  "https://api.datadoghq.com/api/v2/spans/events?filter[query]=service:hello&filter[from]=now-5m&page[limit]=1" \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}"
```

Check `data | length > 0` to confirm traces arrived.

### Rate Limits

300 requests per hour for spans endpoints. Sufficient for e2e polling.

### Ingestion Delay

Traces take 10-30 seconds to appear after being sent. Build a polling loop with ~5s intervals, 60s timeout.

### Polling Pattern

```bash
for i in $(seq 1 12); do
  COUNT=$(curl -s -X GET \
    "https://api.datadoghq.com/api/v2/spans/events?filter[query]=service:hello&filter[from]=now-5m&page[limit]=1" \
    -H "DD-API-KEY: ${DD_API_KEY}" \
    -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
    | jq '.data | length')
  if [ "$COUNT" -gt 0 ]; then
    echo "Traces found!"
    exit 0
  fi
  echo "Waiting for traces... ($i/12)"
  sleep 5
done
echo "Timed out"
exit 1
```

### Secrets Needed

- `DD_API_KEY` — already have
- `DD_APP_KEY` — need to obtain (Application Key, not API key)

## Combined Pipeline Architecture

Putting all components together for the full OTel-to-Datadog pipeline:

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel
spec:
  mode: deployment
  image: otel/opentelemetry-collector-contrib:0.147.0
  env:
    - name: DD_API_KEY
      valueFrom:
        secretKeyRef:
          name: datadog-secret
          key: api-key
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch:
        timeout: 10s

    connectors:
      datadog/connector:
        traces:
          compute_stats_by_span_kind: true
          compute_top_level_by_span_kind: true
          peer_tags_aggregation: true
      count:
        spanevents:
          gen_ai.evaluation.count:
            description: "Count of satisfaction evaluation events"
            conditions:
              - 'name == "gen_ai.evaluation.result"'
            attributes:
              - key: vote
                default_value: unknown

    exporters:
      datadog:
        api:
          key: ${env:DD_API_KEY}
          site: datadoghq.com

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [datadog/connector, count, datadog]

        metrics:
          receivers: [datadog/connector, count]
          processors: [batch]
          exporters: [datadog]
```

Data flow:
1. OTLP traces arrive at the collector
2. Traces are exported to Datadog AND fed into both connectors
3. `datadog/connector` computes APM stats, emits as metrics
4. `count` connector counts `gen_ai.evaluation.result` span events, emits as metrics
5. Both connector outputs merge in the metrics pipeline and export to **both** Datadog and Prometheus

**Note**: The combined architecture above must be updated to include the `prometheus` exporter — see section 8 below.

## 6. Instrumentation CR (Node.js Auto-Instrumentation)

**API Version**: `opentelemetry.io/v1alpha1` (still current as of early 2026)

### Minimal CR

Only `spec.exporter.endpoint` is practically required (everything else has defaults):

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: nodejs-instrumentation
  namespace: apps
spec:
  exporter:
    endpoint: http://otel-collector.apps.svc.cluster.local:4317
  propagators:
    - tracecontext
    - baggage
  sampler:
    type: parentbased_traceidratio
    argument: "1"
```

Note: Using port 4317 (gRPC) matches Node.js auto-instrumentation's default protocol. No `OTEL_EXPORTER_OTLP_PROTOCOL` override needed.

### Key Fields

- **`spec.exporter.endpoint`** — where the injected SDK sends telemetry. Format: `http://<service>:<port>`
- **`spec.propagators`** — trace context propagation. Default: `[tracecontext, baggage]`
- **`spec.sampler`** — sampling strategy. `parentbased_traceidratio` with arg `"1"` = sample everything
- **`spec.resource.resourceAttributes`** — sets `OTEL_RESOURCE_ATTRIBUTES` (service.name, etc.)
- **`spec.nodejs.env`** — Node.js-specific env var overrides

### Node.js Protocol Default: gRPC

The official OTel Operator docs confirm: "By default, the Instrumentation resource that auto-instruments Node.js services uses `otlp` with the `grpc` protocol." This means **use port 4317** for Node.js. No protocol override needed if the collector exposes gRPC on 4317 (which it does by default).

Alternative: Override with `OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf` in `spec.nodejs.env` and use port 4318. But it's simpler to just use the gRPC default.

### Annotation

On the pod template (not the Service/Deployment metadata):

```yaml
instrumentation.opentelemetry.io/inject-nodejs: "true"
```

Values: `"true"` (same-namespace CR), `"my-instrumentation"` (named CR), `"other-ns/my-cr"` (cross-namespace).

### Interaction with Existing `@opentelemetry/api` Usage

The app uses `@opentelemetry/api` v1.9.0 (API only, no SDK). This is the ideal pattern for auto-instrumentation:

1. The operator sets `NODE_OPTIONS=--require /otel-auto-instrumentation-nodejs/autoinstrumentation.js`
2. This loads the SDK and registers a global `TracerProvider` **before** the app starts
3. When the app calls `trace.getTracer()`, it gets the real tracer (not a no-op)
4. Custom spans and span events (`gen_ai.evaluation.result`) are exported normally
5. Custom spans nest correctly within auto-instrumented HTTP spans

**Critical**: The app must NOT register its own `TracerProvider` or `NodeSDK`. Since it depends on the API only (no SDK), this is already correct.

The OTel API uses `Symbol.for('opentelemetry.js.api.1')` for global registration, which works across multiple copies of the package as long as the major API version matches (both are v1.x).

### OTEL_EXPORTER_OTLP_ENDPOINT is Redundant

The Instrumentation CR's `spec.exporter.endpoint` automatically sets `OTEL_EXPORTER_OTLP_ENDPOINT` on the pod. **No need to set it separately as an env var on the Knative Service.**

## 7. Flagger Metric Providers

### Flagger Supports Both Prometheus and Datadog

Flagger has built-in support for 10 metric providers including both Prometheus and Datadog. A single Canary CR can reference metrics from **multiple providers** simultaneously.

### Decision: Dual Export — Prometheus for Flagger, Datadog for Dashboards

- **Prometheus** for Flagger canary decisions: in-cluster, no external API dependency, low latency
- **Datadog** for dashboards and monitoring: rich visualization, alerting, the "wow factor"

Both receive the same metrics from the OTel Collector (fan-out in the metrics pipeline).

### Flagger MetricTemplate for Prometheus

```yaml
apiVersion: flagger.app/v1beta1
kind: MetricTemplate
metadata:
  name: satisfaction-rate
  namespace: apps
spec:
  provider:
    type: prometheus
    address: http://prometheus.monitoring:9090
  query: |
    sum(rate(gen_ai_evaluation_count_total{vote="thumbs_up", namespace="{{ namespace }}"}[{{ interval }}]))
    /
    sum(rate(gen_ai_evaluation_count_total{namespace="{{ namespace }}"}[{{ interval }}]))
    * 100
```

**Metric name translation**: The Prometheus exporter normalizes OTel names — `gen_ai.evaluation.count` becomes `gen_ai_evaluation_count_total` (dots→underscores, `_total` suffix for monotonic sums).

### Flagger MetricTemplate for Datadog (if needed as alternative)

```yaml
apiVersion: flagger.app/v1beta1
kind: MetricTemplate
metadata:
  name: satisfaction-rate-datadog
  namespace: apps
spec:
  provider:
    type: datadog
    address: https://api.datadoghq.com
    secretRef:
      name: datadog
  query: |
    sum:gen_ai.evaluation.count{vote:thumbs_up,kube_namespace:{{ namespace }}}.as_count()
    /
    sum:gen_ai.evaluation.count{kube_namespace:{{ namespace }}}.as_count()
    * 100
```

### Canary CR Analysis Section

```yaml
analysis:
  metrics:
    - name: satisfaction-rate
      templateRef:
        name: satisfaction-rate
        namespace: apps
      thresholdRange:
        min: 60        # At least 60% thumbs-up to promote
      interval: 1m
```

### Open Question: Is Prometheus Already in the Cluster?

Flagger installed with `metricsServer: prometheus` may have deployed `flagger-prometheus`. Need to check the live cluster. If not present, need a Prometheus instance or use Datadog as the Flagger provider instead.

## 8. Prometheus Exporter for OTel Collector

### Config

```yaml
exporters:
  prometheus:
    endpoint: 0.0.0.0:9090
    resource_to_telemetry_conversion:
      enabled: true    # promotes resource attrs to metric labels (simpler PromQL)
```

### Dual Export in Metrics Pipeline

Both exporters in the same pipeline — the collector fans out to both:

```yaml
service:
  pipelines:
    metrics:
      receivers: [datadog/connector, count]
      processors: [batch]
      exporters: [datadog, prometheus]
```

### Port Exposure on the CR

The operator may not auto-detect the Prometheus exporter port for the container. Declare it explicitly:

```yaml
spec:
  ports:
    - name: prometheus
      port: 9090
      protocol: TCP
```

### Prometheus Scrape Discovery

Options (depends on what's in the cluster):
- **ServiceMonitor** (if Prometheus Operator is deployed)
- **Pod annotations** (`prometheus.io/scrape: "true"`, `prometheus.io/port: "9090"`)
- **Static scrape config** (simplest but manual)

## 9. Updated Combined Pipeline Architecture

The full pipeline with dual Datadog + Prometheus export:

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel
spec:
  mode: deployment
  image: otel/opentelemetry-collector-contrib:0.147.0
  ports:
    - name: prometheus
      port: 9090
      protocol: TCP
  env:
    - name: DD_API_KEY
      valueFrom:
        secretKeyRef:
          name: datadog-secret
          key: api-key
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch:
        timeout: 10s

    connectors:
      datadog/connector:
        traces:
          compute_stats_by_span_kind: true
          compute_top_level_by_span_kind: true
          peer_tags_aggregation: true
      count:
        spanevents:
          gen_ai.evaluation.count:
            description: "Count of satisfaction evaluation events"
            conditions:
              - 'name == "gen_ai.evaluation.result"'
            attributes:
              - key: vote
                default_value: unknown

    exporters:
      datadog:
        api:
          key: ${env:DD_API_KEY}
          site: datadoghq.com
      prometheus:
        endpoint: 0.0.0.0:9090
        resource_to_telemetry_conversion:
          enabled: true

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [datadog/connector, count, datadog]

        metrics:
          receivers: [datadog/connector, count]
          processors: [batch]
          exporters: [datadog, prometheus]
```

Data flow:
1. OTLP traces arrive at the collector
2. Traces exported to Datadog AND fed into both connectors
3. `datadog/connector` computes APM stats → metrics
4. `count` connector counts `gen_ai.evaluation.result` span events → metrics
5. Metrics fan out to Datadog (dashboards) AND Prometheus (Flagger canary analysis)
