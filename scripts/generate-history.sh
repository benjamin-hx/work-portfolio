#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
DATA_DIR="$SCRIPT_DIR/../data"
HISTORY_DIR="$DATA_DIR/history"
OUTPUT_FILE="$DATA_DIR/history-summary.json"

mkdir -p "$HISTORY_DIR"

echo "Generating history summary..."

# Collect all snapshots into a single timeline
jq -n '
  [inputs | {
    date: (input_filename | capture("portfolio-(?<d>[0-9-]+)\\.json").d),
    data: .summary
  }]
  | sort_by(.date)
  | {
    snapshots: .,
    latest: .[-1],
    earliest: .[0],
    trends: {
      jira_issues: [.[].data.jira.total_issues],
      jira_completed: [.[].data.jira.completed],
      jira_hours: [.[].data.jira.total_hours],
      github_commits: [.[].data.github.commits],
      github_prs: [.[].data.github.pull_requests],
      github_reviews: [.[].data.github.reviews]
    }
  }
' "$HISTORY_DIR"/portfolio-*.json > "$OUTPUT_FILE" 2>/dev/null || echo '{"snapshots":[],"trends":{}}' > "$OUTPUT_FILE"

SNAPSHOT_COUNT=$(jq '.snapshots | length' "$OUTPUT_FILE")
echo "Generated history with $SNAPSHOT_COUNT snapshots"
