# PRD #3: PR #2 Integration Fixes

**GitHub Issue**: [#3](https://github.com/wiggitywhitney/kubecon-2026-gitops/issues/3)
**Priority**: High
**Target**: KubeCon EU 2026 demo (March 16, 2026)
**Branch**: `feature/prd-2-datadog-dashboard` (existing PR #2 — do NOT create a new branch)

## Problem

A cross-repo audit on March 12, 2026 identified 6 integration issues between Whitney's stateless app (scaling-on-satisfaction) and Thomas's gitops manifests. These issues will cause silent failures during the live demo — no telemetry, broken load testing, container permission errors, missing A/B variant, and canary cold-start delays.

## Solution

Fix all 6 issues on the existing `feature/prd-2-datadog-dashboard` branch and update PR #2 (currently draft) before marking it ready for Thomas's review.

## Branch Strategy

**This PRD executes on `feature/prd-2-datadog-dashboard`** — the branch already backing PR #2 on Thomas's repo. Do NOT create a new feature branch. All commits land on this branch and push to the existing draft PR. When all milestones are complete, mark PR #2 ready for review.

## Milestones

- [ ] **M1: Fix Instrumentation CR deployment** — Add `instrumentation.yml` to `apps/base/story-app-1/kustomization.yml` resources list. Remove hardcoded `namespace: observability` so FluxCD's `targetNamespace: apps` applies it to the correct namespace. Verify the annotation in service.yml (`otel-instrumentation`) matches the CR name. Without this fix, the OTel SDK is never injected and the entire telemetry pipeline is dead.

- [ ] **M2: Fix runAsUser mismatch** — Change `runAsUser: 1001` to `runAsUser: 1000` in `apps/base/story-app-1/service.yml` to match the Dockerfile's `USER 1000` / `chown 1000:1000`. Mismatched UIDs can cause permission errors on temp file writes during pre-generation under load.

- [ ] **M3: Add story-app-1b variant** — Create `apps/base/story-app-1/service-1b.yml` as a separate Knative Service with `name: story-app-1b`, `app: story-app-1b` pod label, and `image: wiggitywhitney/story-app-1b:latest`. Add to kustomization.yml. The 1b label feeds into `OTEL_SERVICE_NAME` via the Instrumentation CR's `metadata.labels['app']` fieldRef, giving spanmetrics a distinct `service_name` dimension. This is required for the A/B comparison in the Canary MetricTemplate.

- [ ] **M4: Shorten canary metric interval** — Change the MetricTemplate PromQL `rate()` window from `5m` to `2m` in `apps/base/story-app-1/metrics.yml`. Update the Canary `interval` in `canary.yml` from `5m` to `2m`. The 5-minute window means Flagger can't advance the canary for the first 5 minutes of the demo — too long for a live presentation. A 2-minute window fills faster while still smoothing out noise.

- [ ] **M5: Write new load test script** — Create `scripts/load-test-votes.sh` that works with the current stateless app. Must: (a) call `/api/story/warmup` to trigger pre-generation, (b) poll `/api/status` checking `sharedStoryParts` (not the old `generatedParts`), (c) fetch a story part to capture `responseId` from the response, (d) send votes with `{"vote":"thumbs_up","responseId":"..."}` payload. No session cookies. Support configurable vote count, thumbs-up ratio, and target URL.

- [ ] **M6: Mark PR #2 ready for review** — Push all changes, convert PR #2 from draft back to ready (`gh pr ready 2`), update PR description to summarize the new changes. Start CodeRabbit review timer.

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-13 | Execute on existing PR #2 branch, not a new branch | Avoids merge conflicts and keeps Thomas's review surface to one PR |
| 2026-03-13 | Convert PR #2 to draft during development | Signals to Thomas not to review yet |
| 2026-03-13 | Shorten canary interval to 2m (from 5m) | 5m cold-start too long for live demo; 2m is a pragmatic compromise |
| 2026-03-13 | Separate Knative Service for 1b (not revision) | Flagger needs distinct `service_name` labels in spanmetrics for A/B comparison |

## Out of Scope

- **max_tokens reduction** — scaling-on-satisfaction repo, not this repo
- **Round 2 variants (2a/2b)** — separate manifests needed later, Round 1 is the priority
- **Delete prd-1 branch** — ask Thomas during PR review
- **Anthropic secret creation** — already exists on Thomas's cluster
