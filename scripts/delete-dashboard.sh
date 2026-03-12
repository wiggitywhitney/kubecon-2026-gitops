#!/usr/bin/env bash
# ABOUTME: Deletes the Datadog dashboard created by create-dashboard.sh.
# ABOUTME: Reads the dashboard ID from .dashboard-id file.

set -euo pipefail

readonly DD_SITE="${DD_SITE:-datadoghq.com}"
readonly ID_FILE="$(dirname "$0")/../.dashboard-id"

if [[ -z "${DD_API_KEY:-}" ]]; then
  echo "ERROR: DD_API_KEY not set. Run via: vals exec -f .vals.yaml -- $0" >&2
  exit 1
fi
if [[ -z "${DD_APP_KEY:-}" ]]; then
  echo "ERROR: DD_APP_KEY not set. Run via: vals exec -f .vals.yaml -- $0" >&2
  exit 1
fi

if [[ ! -f "$ID_FILE" ]]; then
  echo "ERROR: No .dashboard-id file found. Nothing to delete." >&2
  exit 1
fi

readonly DASHBOARD_ID=$(cat "$ID_FILE")
echo "Deleting dashboard ${DASHBOARD_ID}..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  "https://api.${DD_SITE}/api/v1/dashboard/${DASHBOARD_ID}" \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}")

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "Dashboard ${DASHBOARD_ID} deleted."
  rm -f "$ID_FILE"
else
  echo "ERROR: Failed to delete dashboard (HTTP ${HTTP_CODE})" >&2
  exit 1
fi
