#!/usr/bin/env bash
# ABOUTME: Creates the Datadog dashboard for the KubeCon "Scaling on Satisfaction" live demo.
# ABOUTME: Uses the Datadog API to create a dashboard with vote, satisfaction, and traffic widgets.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
readonly DD_SITE="${DD_SITE:-datadoghq.com}"
readonly DASHBOARD_TITLE="Scaling on Satisfaction — KubeCon EU 2026"
readonly METRIC="gen_ai.calls"
readonly TAG_SCORE="gen_ai.evaluation.score.label"
readonly TAG_PART="story.part"
readonly TAG_SERVICE="service"

# ---------------------------------------------------------------------------
# Validate secrets
# ---------------------------------------------------------------------------
if [[ -z "${DD_API_KEY:-}" ]]; then
  echo "ERROR: DD_API_KEY not set. Run via: vals exec -f .vals.yaml -- $0" >&2
  exit 1
fi
if [[ -z "${DD_APP_KEY:-}" ]]; then
  echo "ERROR: DD_APP_KEY not set. Run via: vals exec -f .vals.yaml -- $0" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Dashboard JSON payload
# ---------------------------------------------------------------------------
read -r -d '' PAYLOAD << 'ENDJSON' || true
{
  "title": "DASHBOARD_TITLE_PLACEHOLDER",
  "description": "Live demo dashboard for KubeCon EU 2026 — Scaling on Satisfaction talk. Shows audience votes, per-part satisfaction, and Flagger traffic shifts in real time.",
  "layout_type": "ordered",
  "widgets": [
    {
      "definition": {
        "type": "group",
        "layout_type": "ordered",
        "title": "Vote Totals",
        "widgets": [
          {
            "definition": {
              "type": "query_value",
              "title": "👍 Thumbs Up",
              "title_size": "16",
              "title_align": "center",
              "requests": [
                {
                  "queries": [
                    {
                      "data_source": "metrics",
                      "name": "query1",
                      "query": "sum:METRIC_PLACEHOLDER{TAG_SCORE_PLACEHOLDER:thumbs_up}.as_count()",
                      "aggregator": "sum"
                    }
                  ],
                  "response_format": "scalar",
                  "formulas": [
                    {
                      "formula": "query1"
                    }
                  ]
                }
              ],
              "autoscale": true,
              "precision": 0
            }
          },
          {
            "definition": {
              "type": "query_value",
              "title": "👎 Thumbs Down",
              "title_size": "16",
              "title_align": "center",
              "requests": [
                {
                  "queries": [
                    {
                      "data_source": "metrics",
                      "name": "query1",
                      "query": "sum:METRIC_PLACEHOLDER{TAG_SCORE_PLACEHOLDER:thumbs_down}.as_count()",
                      "aggregator": "sum"
                    }
                  ],
                  "response_format": "scalar",
                  "formulas": [
                    {
                      "formula": "query1"
                    }
                  ]
                }
              ],
              "autoscale": true,
              "precision": 0
            }
          },
          {
            "definition": {
              "type": "sunburst",
              "title": "Satisfaction Ratio",
              "title_size": "16",
              "title_align": "center",
              "requests": [
                {
                  "queries": [
                    {
                      "data_source": "metrics",
                      "name": "query1",
                      "query": "sum:METRIC_PLACEHOLDER{TAG_SCORE_PLACEHOLDER:*} by {TAG_SCORE_PLACEHOLDER}.as_count()",
                      "aggregator": "sum"
                    }
                  ],
                  "response_format": "scalar",
                  "formulas": [
                    {
                      "formula": "query1"
                    }
                  ]
                }
              ],
              "hide_total": false,
              "legend": {
                "type": "automatic"
              }
            }
          }
        ]
      }
    },
    {
      "definition": {
        "type": "group",
        "layout_type": "ordered",
        "title": "Vote Trends",
        "widgets": [
          {
            "definition": {
              "type": "timeseries",
              "title": "Votes Over Time",
              "title_size": "16",
              "title_align": "left",
              "show_legend": true,
              "legend_layout": "auto",
              "legend_columns": ["avg", "min", "max", "value", "sum"],
              "requests": [
                {
                  "queries": [
                    {
                      "data_source": "metrics",
                      "name": "thumbs_up",
                      "query": "sum:METRIC_PLACEHOLDER{TAG_SCORE_PLACEHOLDER:thumbs_up}.as_count()"
                    }
                  ],
                  "response_format": "timeseries",
                  "formulas": [
                    {
                      "formula": "thumbs_up",
                      "alias": "Thumbs Up"
                    }
                  ],
                  "display_type": "bars",
                  "style": {
                    "palette": "green",
                    "line_type": "solid",
                    "line_width": "thick"
                  }
                },
                {
                  "queries": [
                    {
                      "data_source": "metrics",
                      "name": "thumbs_down",
                      "query": "sum:METRIC_PLACEHOLDER{TAG_SCORE_PLACEHOLDER:thumbs_down}.as_count()"
                    }
                  ],
                  "response_format": "timeseries",
                  "formulas": [
                    {
                      "formula": "thumbs_down",
                      "alias": "Thumbs Down"
                    }
                  ],
                  "display_type": "bars",
                  "style": {
                    "palette": "warm",
                    "line_type": "solid",
                    "line_width": "thick"
                  }
                }
              ],
              "time": {},
              "yaxis": {
                "include_zero": true
              }
            }
          }
        ]
      }
    },
    {
      "definition": {
        "type": "group",
        "layout_type": "ordered",
        "title": "Deep Dive",
        "widgets": [
          {
            "definition": {
              "type": "timeseries",
              "title": "Satisfaction by Story Part",
              "title_size": "16",
              "title_align": "left",
              "show_legend": true,
              "legend_layout": "auto",
              "legend_columns": ["avg", "min", "max", "value", "sum"],
              "requests": [
                {
                  "queries": [
                    {
                      "data_source": "metrics",
                      "name": "up",
                      "query": "sum:METRIC_PLACEHOLDER{TAG_SCORE_PLACEHOLDER:thumbs_up,TAG_PART_PLACEHOLDER:*} by {TAG_PART_PLACEHOLDER}.as_count()"
                    },
                    {
                      "data_source": "metrics",
                      "name": "total",
                      "query": "sum:METRIC_PLACEHOLDER{TAG_SCORE_PLACEHOLDER:*,TAG_PART_PLACEHOLDER:*} by {TAG_PART_PLACEHOLDER}.as_count()"
                    }
                  ],
                  "response_format": "timeseries",
                  "formulas": [
                    {
                      "formula": "(up / total) * 100",
                      "alias": "% Satisfied"
                    }
                  ],
                  "display_type": "bars",
                  "style": {
                    "palette": "cool"
                  }
                }
              ],
              "yaxis": {
                "include_zero": true,
                "max": "100",
                "label": "% Thumbs Up"
              }
            }
          },
          {
            "definition": {
              "type": "timeseries",
              "title": "Traffic Split by Variant",
              "title_size": "16",
              "title_align": "left",
              "show_legend": true,
              "legend_layout": "auto",
              "legend_columns": ["avg", "min", "max", "value", "sum"],
              "requests": [
                {
                  "queries": [
                    {
                      "data_source": "metrics",
                      "name": "query1",
                      "query": "sum:METRIC_PLACEHOLDER{TAG_SCORE_PLACEHOLDER:*} by {TAG_SERVICE_PLACEHOLDER}.as_count()"
                    }
                  ],
                  "response_format": "timeseries",
                  "formulas": [
                    {
                      "formula": "query1",
                      "alias": "Requests"
                    }
                  ],
                  "display_type": "line",
                  "style": {
                    "palette": "dog_classic",
                    "line_type": "solid",
                    "line_width": "thick"
                  }
                }
              ],
              "yaxis": {
                "include_zero": true
              }
            }
          }
        ]
      }
    }
  ],
  "notify_list": [],
  "template_variables": []
}
ENDJSON

# Replace placeholders with actual values
PAYLOAD="${PAYLOAD//DASHBOARD_TITLE_PLACEHOLDER/$DASHBOARD_TITLE}"
PAYLOAD="${PAYLOAD//METRIC_PLACEHOLDER/$METRIC}"
PAYLOAD="${PAYLOAD//TAG_SCORE_PLACEHOLDER/$TAG_SCORE}"
PAYLOAD="${PAYLOAD//TAG_PART_PLACEHOLDER/$TAG_PART}"
PAYLOAD="${PAYLOAD//TAG_SERVICE_PLACEHOLDER/$TAG_SERVICE}"

# ---------------------------------------------------------------------------
# Create dashboard via Datadog API
# ---------------------------------------------------------------------------
echo "Creating Datadog dashboard: ${DASHBOARD_TITLE}..."
echo "  Site: ${DD_SITE}"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "https://api.${DD_SITE}/api/v1/dashboard" \
  -H "Content-Type: application/json" \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
  -d "${PAYLOAD}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  DASHBOARD_URL=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])" 2>/dev/null || true)
  DASHBOARD_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)

  echo "Dashboard created successfully!"
  echo ""
  echo "  ID:  ${DASHBOARD_ID}"
  echo "  URL: https://app.${DD_SITE}${DASHBOARD_URL}"
  echo ""
  echo "To open in TV mode, append ?tv_mode=true to the URL."

  # Save the dashboard ID for future updates
  echo "${DASHBOARD_ID}" > "$(dirname "$0")/../.dashboard-id"
  echo "Dashboard ID saved to .dashboard-id"
else
  echo "ERROR: Failed to create dashboard (HTTP ${HTTP_CODE})" >&2
  echo "$BODY" >&2
  exit 1
fi
