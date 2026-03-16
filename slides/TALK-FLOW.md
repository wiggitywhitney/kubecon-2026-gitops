# Scaling on Satisfaction — Talk Flow

**KubeCon EU 2026** | Whitney Lee & Thomas Vitale | 25 minutes

A live feedback loop where audience votes drive infrastructure decisions. The audience participates in two live demo rounds — voting on AI-generated stories — while the platform shifts traffic based on their satisfaction in real time.

---

## The App

**What the audience sees:** Open a URL on your phone. Read a short AI-generated story (5 parts). After each part, vote thumbs up or thumbs down.

**What they don't see:** Two variants of the app are running. Their votes control what happens next.

**The architecture:** Two Knative Services running different container images (not feature flags — actually different apps). For each story part, you might get Variant A or Variant B — it can switch mid-story. Both variants send telemetry to the same OTel Collector. The collector turns telemetry into comparable metrics. The platform uses those metrics to roll out the more popular variant.

---

## Round 1: Live Demo

The audience votes without knowing the setup. They just read and react.

**The variants:** Same model (Sonnet 4), different tone — dry/matter-of-fact vs funny/playful.

**On screen:** Datadog dashboard showing votes and satisfaction rates updating in real time.

**The reveal (after voting):** There were two versions of that story. The platform shifted traffic toward the variant the audience liked more. Now let's look at exactly how.

---

## How It Works (Teaching Scenes)

### Scene 3: How a Vote Becomes Data
You tap thumbs up. The app creates an OpenTelemetry span (`evaluate UserSatisfaction`). Inside that span, the app records a **span event** — OTel's version of a structured log, automatically correlated with the trace. The span event (`gen_ai.evaluation.result`) carries your vote using **gen_ai semantic conventions** — a standard vocabulary so any OTel-compatible tool knows what these fields mean (not custom instrumentation). The event records: thumbs_up, score 1.0, story part 3. Your vote is also linked back to the generation that produced the story, and to which story part you voted on. Then: "here's what this looks like in practice" — link into a Datadog APM trace showing the real span event with its attributes.

### Scene 4: From Events to Metrics
Start with: what's an OTel Collector? (The audience hasn't been introduced to it yet.) Then build the pipeline: traces arrive via OTLP. The transform processor promotes span event attributes to the parent span (spanmetrics reads span attributes, not events — this is the non-obvious trick). The spanmetrics connector converts spans into a counter metric (`gen_ai_calls_total`) with dimensions like `service_name` and `score.label`. Two outputs fork: Prometheus (in-cluster, for Flagger) and Datadog (for dashboards).

### Scene 5: Flagger's Canary Logic
Prometheus scrapes the metrics. Flagger runs a PromQL query: is Variant B's thumbs-up percentage at least 5 points higher than Variant A's? If yes for 3 consecutive checks, advance the traffic split by 10%. If the delta drops, roll back. The threshold is relative — the platform promotes the variant that makes users happier.

---

## Round 2: Live Demo

Now the audience understands the infrastructure. Their votes have new meaning.

**The variants:** Same tone, different models — Haiku 4.5 (cheap) vs Opus 4.6 (expensive).

**The tension:** Does the expensive model actually produce better stories? The outcome is genuinely unknown — and the audience knows their votes are controlling the rollout in real time.

**The reveal:** Does expensive mean better? The platform doesn't care about price tags. It cares about thumbs up.

---

## The Full Loop

The complete cycle: audience votes become span events, the collector transforms them into metrics, Flagger queries the metrics and shifts traffic, the audience gets more of the variant they prefer, and the loop continues. Subjective user experience drives infrastructure decisions. This is what "scaling on satisfaction" means.

---

## Key Technologies

- **OpenTelemetry** gen_ai semantic conventions capture user satisfaction
- **OTel Collector** transforms span events into actionable metrics
- **Flagger** uses those metrics to make canary deployment decisions
- **Knative** serves the app variants and handles traffic splitting
- **Datadog** visualizes the live vote data
- **Prometheus** provides in-cluster metrics for Flagger's decisions
