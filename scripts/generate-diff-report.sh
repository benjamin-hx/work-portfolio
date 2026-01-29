#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
DATA_DIR="$SCRIPT_DIR/../data"
PUBLIC_DIR="$DATA_DIR/public"
HISTORY_DIR="$PUBLIC_DIR/history"
CURRENT_FILE="$PUBLIC_DIR/portfolio.json"
OUTPUT_FILE="$PUBLIC_DIR/diff-report.json"

echo "Generating diff report..."

# Get today's date
TODAY=$(date +%Y-%m-%d)

# Find snapshots (excluding today)
SNAPSHOTS=$(ls "$HISTORY_DIR"/portfolio-*.json 2>/dev/null | sort -r | grep -v "$TODAY" || true)

if [ -z "$SNAPSHOTS" ]; then
  echo "No previous snapshots found. Creating empty report."
  echo '{"has_previous": false, "message": "No previous data to compare"}' > "$OUTPUT_FILE"
  exit 0
fi

# Find week-ago snapshot (7 days back) - prefer this for meaningful diffs
WEEK_AGO=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d)
WEEK_SNAPSHOT=$(ls "$HISTORY_DIR"/portfolio-*.json 2>/dev/null | sort -r | while read f; do
  FDATE=$(basename "$f" | sed 's/portfolio-//' | sed 's/.json//')
  if [[ "$FDATE" < "$WEEK_AGO" ]] || [[ "$FDATE" == "$WEEK_AGO" ]]; then
    echo "$f"
    break
  fi
done)

# Use week-ago snapshot if available, otherwise fall back to oldest available
if [ -n "$WEEK_SNAPSHOT" ]; then
  PREV_SNAPSHOT="$WEEK_SNAPSHOT"
else
  # Fall back to oldest snapshot (for more meaningful diff when < 7 days of history)
  PREV_SNAPSHOT=$(echo "$SNAPSHOTS" | tail -1)
fi
PREV_DATE=$(basename "$PREV_SNAPSHOT" | sed 's/portfolio-//' | sed 's/.json//')

echo "Current: $CURRENT_FILE"
echo "Comparing against: $PREV_SNAPSHOT ($PREV_DATE)"

# Generate diff report using jq
jq -n \
  --slurpfile current "$CURRENT_FILE" \
  --slurpfile prev "$PREV_SNAPSHOT" \
  --arg prev_date "$PREV_DATE" \
  --arg today "$TODAY" '
def calc_diff(curr; prev):
  {
    value: curr,
    previous: prev,
    delta: (curr - prev),
    pct_change: (if prev == 0 then null else (((curr - prev) / prev) * 100 | round) end)
  };

{
  generated_at: now | strftime("%Y-%m-%dT%H:%M:%SZ"),
  has_previous: true,
  current_date: $today,
  comparison_date: $prev_date,
  days_between: ((($today | strptime("%Y-%m-%d") | mktime) - ($prev_date | strptime("%Y-%m-%d") | mktime)) / 86400 | floor),

  summary: {
    issues_worked: calc_diff($current[0].summary.jira.total_issues; $prev[0].summary.jira.total_issues),
    issues_completed: calc_diff($current[0].summary.jira.completed; $prev[0].summary.jira.completed),
    hours_logged: calc_diff($current[0].summary.jira.total_hours; $prev[0].summary.jira.total_hours),
    commits: calc_diff($current[0].summary.github.commits; $prev[0].summary.github.commits),
    pull_requests: calc_diff($current[0].summary.github.pull_requests; $prev[0].summary.github.pull_requests),
    reviews: calc_diff($current[0].summary.github.reviews; $prev[0].summary.github.reviews),
    repos_touched: calc_diff($current[0].summary.github.repos_count; $prev[0].summary.github.repos_count)
  },

  highlights: (
    [
      (if ($current[0].summary.jira.completed - $prev[0].summary.jira.completed) > 0
       then "Completed \($current[0].summary.jira.completed - $prev[0].summary.jira.completed) issues" else null end),
      (if ($current[0].summary.github.pull_requests - $prev[0].summary.github.pull_requests) > 0
       then "Opened \($current[0].summary.github.pull_requests - $prev[0].summary.github.pull_requests) pull requests" else null end),
      (if ($current[0].summary.github.reviews - $prev[0].summary.github.reviews) > 0
       then "Reviewed \($current[0].summary.github.reviews - $prev[0].summary.github.reviews) PRs" else null end),
      (if ($current[0].summary.github.commits - $prev[0].summary.github.commits) > 0
       then "Made \($current[0].summary.github.commits - $prev[0].summary.github.commits) commits" else null end),
      (if ($current[0].summary.jira.total_hours - $prev[0].summary.jira.total_hours) > 0
       then "Logged \($current[0].summary.jira.total_hours - $prev[0].summary.jira.total_hours) hours" else null end)
    ] | map(select(. != null))
  )
}
' > "$OUTPUT_FILE"

echo ""
echo "Diff report generated: $OUTPUT_FILE"
echo ""
echo "Summary:"
jq '.highlights[]' "$OUTPUT_FILE" 2>/dev/null || echo "No changes detected"
