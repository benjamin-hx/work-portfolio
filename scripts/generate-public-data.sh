#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
DATA_DIR="$SCRIPT_DIR/../data"
PUBLIC_DIR="$DATA_DIR/public"
PUBLIC_HISTORY="$PUBLIC_DIR/history"

echo "Generating public data (sanitized)..."

mkdir -p "$PUBLIC_DIR"
mkdir -p "$PUBLIC_HISTORY"

# Sanitize portfolio.json - remove repo names, project keys
jq '{
  generated_at: .generated_at,
  profile: {
    name: .profile.name,
    title: .profile.title,
    company: .profile.company,
    email: .profile.email,
    github: .profile.github,
    linkedin: .profile.linkedin,
    start_date: .profile.start_date
  },
  summary: {
    jira: {
      total_issues: .summary.jira.total_issues,
      completed: .summary.jira.completed,
      in_progress: .summary.jira.in_progress,
      total_hours: .summary.jira.total_hours,
      projects_count: (.summary.jira.projects | length)
    },
    github: {
      commits: .summary.github.commits,
      pull_requests: .summary.github.pull_requests,
      reviews: .summary.github.reviews,
      repos_count: (.summary.github.repos | length),
      review_ratio: (if .summary.github.pull_requests > 0 then ((.summary.github.reviews / .summary.github.pull_requests * 10) | floor / 10) else 0 end)
    }
  }
}' "$DATA_DIR/portfolio.json" > "$PUBLIC_DIR/portfolio.json"

# Save sanitized snapshot to history
SNAPSHOT_DATE=$(date +%Y-%m-%d)
cp "$PUBLIC_DIR/portfolio.json" "$PUBLIC_HISTORY/portfolio-${SNAPSHOT_DATE}.json"

# Sanitize stats.json - only time_by_theme and skills, no repo names
jq '{
  time_by_theme: .time_by_theme,
  skills: .skills
}' "$DATA_DIR/stats.json" > "$PUBLIC_DIR/stats.json"

# Copy diff-report as-is (already just numbers)
if [ -f "$DATA_DIR/diff-report.json" ]; then
  cp "$DATA_DIR/diff-report.json" "$PUBLIC_DIR/diff-report.json"
fi

echo "Public data generated in $PUBLIC_DIR"
ls -la "$PUBLIC_DIR"
echo ""
echo "History snapshots:"
ls -la "$PUBLIC_HISTORY"
