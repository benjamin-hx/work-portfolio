#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
DATA_DIR="$SCRIPT_DIR/../data"
CONFIG_FILE="$SCRIPT_DIR/../config.json"
OUTPUT_FILE="$DATA_DIR/portfolio.json"

echo "Aggregating data..."

# Check required files exist
if [ ! -f "$DATA_DIR/jira/jira-history.json" ]; then
  echo "Error: JIRA data not found. Run fetch-jira.sh first." >&2
  exit 1
fi

if [ ! -f "$DATA_DIR/github/summary.json" ]; then
  echo "Warning: GitHub data not found. Run fetch-github.sh first." >&2
  echo '{}' > /tmp/github-empty.json
  GITHUB_FILE="/tmp/github-empty.json"
else
  GITHUB_FILE="$DATA_DIR/github/summary.json"
fi

JIRA_FILE="$DATA_DIR/jira/jira-history.json"
JIRA_THEMED_FILE="$DATA_DIR/jira/jira-by-theme.json"

if [ ! -f "$JIRA_THEMED_FILE" ]; then
  echo '{}' > /tmp/jira-themed-empty.json
  JIRA_THEMED_FILE="/tmp/jira-themed-empty.json"
fi

# Load config if available
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_DATA=$(cat "$CONFIG_FILE")
else
  CONFIG_DATA='{}'
fi

# Build unified portfolio using file inputs
jq -n \
  --slurpfile jira "$JIRA_FILE" \
  --slurpfile jira_themed "$JIRA_THEMED_FILE" \
  --slurpfile github "$GITHUB_FILE" \
  --argjson config "$CONFIG_DATA" \
  '{
    generated_at: (now | todate),

    profile: $config.profile,

    summary: {
      jira: {
        total_issues: ($jira[0] | length),
        completed: ([$jira[0][] | select(.fields.status.name | test("^(Done|Closed|Will not do|Won.t Do)$"))] | length),
        in_progress: ([$jira[0][] | select(.fields.status.name == "In Progress")] | length),
        total_hours: ([$jira[0][] | .fields.timespent // 0] | add / 3600 | floor),
        projects: ([$jira[0][] | .fields.project.key] | unique),
        date_range: {
          earliest: ($jira[0] | sort_by(.fields.created) | .[0].fields.created // null),
          latest: ($jira[0] | sort_by(.fields.created) | reverse | .[0].fields.created // null)
        }
      },
      github: {
        commits: ($github[0].totals.commits // 0),
        pull_requests: ($github[0].totals.pull_requests // 0),
        reviews: ($github[0].totals.reviews // 0),
        repos: ($github[0].repos_contributed_to // [])
      }
    },

    theme_config: $config.themes,
    themes: $jira_themed[0]
  }' > "$OUTPUT_FILE"

echo "Generated: $OUTPUT_FILE"
echo ""
echo "Portfolio summary:"
jq '.summary' "$OUTPUT_FILE"
