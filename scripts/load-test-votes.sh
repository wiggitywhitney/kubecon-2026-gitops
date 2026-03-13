#!/usr/bin/env bash
# ABOUTME: Load test script for stateless story app. Warms up, advances parts,
# ABOUTME: captures responseIds, and sends votes with configurable thumbs-up ratio.

set -euo pipefail

# --- Configuration ---
BASE_URL="${1:-http://localhost:8080}"
TOTAL_VOTES="${2:-100}"
THUMBS_UP_RATIO="${3:-0.7}"       # 0.0 to 1.0 — fraction of thumbs_up votes
PART="${4:-1}"                     # Which story part to vote on
ADMIN_SECRET="${ADMIN_SECRET:-}"   # Set if admin endpoints require auth

# --- Helpers ---
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

secret_param() {
  if [[ -n "$ADMIN_SECRET" ]]; then
    echo "?secret=${ADMIN_SECRET}"
  fi
}

# --- Step 1: Warm up story generation ---
info "Warming up story generation at ${BASE_URL}..."
warmup_status=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/api/story/warmup")
if [[ "$warmup_status" != "200" ]]; then
  warn "Warmup returned HTTP ${warmup_status} (may already be warm)"
fi

# --- Step 2: Advance to the target part ---
info "Advancing to part ${PART}..."
for ((p = 1; p <= PART; p++)); do
  advance_resp=$(curl -s -X POST "${BASE_URL}/api/admin/advance$(secret_param)")
  current=$(echo "$advance_resp" | grep -o '"currentPart":[0-9]*' | grep -o '[0-9]*' || true)
  if [[ -n "$current" ]] && [[ "$current" -ge "$p" ]]; then
    info "  Advanced to part ${current}"
  else
    warn "  Advance response: ${advance_resp}"
  fi
done

# --- Step 3: Wait for story part to be available ---
info "Waiting for part ${PART} to be available..."
max_wait=120
elapsed=0
while [[ $elapsed -lt $max_wait ]]; do
  status_resp=$(curl -s "${BASE_URL}/api/story/status")
  shared_parts=$(echo "$status_resp" | grep -o '"sharedStoryParts":\[[^]]*\]' || true)

  if echo "$shared_parts" | grep -q "$PART"; then
    info "Part ${PART} is available"
    break
  fi

  sleep 2
  elapsed=$((elapsed + 2))
  printf "  Waiting... (%ds / %ds)\r" "$elapsed" "$max_wait"
done

if [[ $elapsed -ge $max_wait ]]; then
  fail "Timed out waiting for part ${PART} after ${max_wait}s. Status: ${status_resp}"
fi

# --- Step 4: Fetch story part to get responseId ---
info "Fetching story part ${PART}..."
story_resp=$(curl -s "${BASE_URL}/api/story/${PART}")
response_id=$(echo "$story_resp" | grep -o '"responseId":"[^"]*"' | head -1 | cut -d'"' -f4)
span_context=$(echo "$story_resp" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    sc = data.get('spanContext')
    if sc:
        print(json.dumps(sc))
    else:
        print('null')
except:
    print('null')
" 2>/dev/null || echo "null")

if [[ -z "$response_id" ]]; then
  fail "Could not extract responseId from story response: ${story_resp}"
fi
info "Got responseId: ${response_id}"

# --- Step 5: Send votes ---
info "Sending ${TOTAL_VOTES} votes (${THUMBS_UP_RATIO} thumbs_up ratio)..."

thumbs_up_count=0
thumbs_down_count=0
success_count=0
fail_count=0

for ((i = 1; i <= TOTAL_VOTES; i++)); do
  # Determine vote type based on ratio
  threshold=$(echo "$THUMBS_UP_RATIO * 1000" | bc | cut -d. -f1)
  random=$((RANDOM % 1000))
  if [[ $random -lt $threshold ]]; then
    vote="thumbs_up"
    thumbs_up_count=$((thumbs_up_count + 1))
  else
    vote="thumbs_down"
    thumbs_down_count=$((thumbs_down_count + 1))
  fi

  # Build vote payload
  if [[ "$span_context" != "null" ]]; then
    payload="{\"vote\":\"${vote}\",\"responseId\":\"${response_id}\",\"spanContext\":${span_context}}"
  else
    payload="{\"vote\":\"${vote}\",\"responseId\":\"${response_id}\"}"
  fi

  # Send vote
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${BASE_URL}/api/story/${PART}/vote" \
    -H "Content-Type: application/json" \
    -d "$payload")

  if [[ "$http_code" == "200" ]]; then
    success_count=$((success_count + 1))
  else
    fail_count=$((fail_count + 1))
    if [[ $fail_count -le 3 ]]; then
      warn "Vote ${i} failed with HTTP ${http_code}"
    fi
  fi

  # Progress indicator every 10 votes
  if (( i % 10 == 0 )); then
    printf "  Progress: %d/%d votes sent (%d ok, %d failed)\r" "$i" "$TOTAL_VOTES" "$success_count" "$fail_count"
  fi

  # Small delay to avoid overwhelming the server
  sleep 0.05
done

echo ""
info "Done!"
info "Results: ${success_count}/${TOTAL_VOTES} successful (${fail_count} failed)"
info "Breakdown: ${thumbs_up_count} thumbs_up, ${thumbs_down_count} thumbs_down"
