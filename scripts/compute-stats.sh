#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
DATA_DIR="$SCRIPT_DIR/../data"
OUTPUT_FILE="$DATA_DIR/stats.json"

echo "Computing advanced stats..."

JIRA_FILE="$DATA_DIR/jira/jira-history.json"
GITHUB_FILE="$DATA_DIR/github/summary.json"
JIRA_THEMED="$DATA_DIR/jira/jira-by-theme.json"

# Compute all stats
jq -n \
  --slurpfile jira "$JIRA_FILE" \
  --slurpfile github "$GITHUB_FILE" \
  --slurpfile themes "$JIRA_THEMED" \
'{
  # Activity timeline (weekly)
  activity_timeline: (
    [$jira[0][] | {
      week: (.fields.created[0:10] | strptime("%Y-%m-%d") | strftime("%Y-W%W")),
      type: "jira_created"
    }] +
    [$jira[0][] | select(.fields.resolutiondate) | {
      week: (.fields.resolutiondate[0:10] | strptime("%Y-%m-%d") | strftime("%Y-W%W")),
      type: "jira_closed"
    }] +
    [$github[0].commits[]? | {
      week: (.date[0:10] | strptime("%Y-%m-%d") | strftime("%Y-W%W")),
      type: "commit"
    }] +
    [$github[0].pull_requests[]? | {
      week: (.created_at[0:10] | strptime("%Y-%m-%d") | strftime("%Y-W%W")),
      type: "pr"
    }]
    | group_by(.week)
    | map({
        week: .[0].week,
        jira_created: [.[] | select(.type == "jira_created")] | length,
        jira_closed: [.[] | select(.type == "jira_closed")] | length,
        commits: [.[] | select(.type == "commit")] | length,
        prs: [.[] | select(.type == "pr")] | length
      })
    | sort_by(.week)
  ),

  # Time distribution by theme (hours)
  time_by_theme: (
    $themes[0] | to_entries | map({
      theme: .key,
      hours: ([.value[]?.hours // 0] | add // 0),
      count: (.value | length)
    }) | sort_by(-.hours)
  ),

  # Top repos by activity
  top_repos: (
    ([$github[0].commits[]?.repo] + [$github[0].pull_requests[]?.repo // empty | . as $r | $github[0].commits[0].repo | $r])
    | map(split("/") | .[-1])
    | group_by(.)
    | map({repo: .[0], count: length})
    | sort_by(-.count)
    | .[0:15]
  ),

  # Completion rate
  completion_rate: {
    total_assigned: ($jira[0] | length),
    completed: ([$jira[0][] | select(.fields.status.name == "Done" or .fields.status.name == "Closed")] | length),
    in_progress: ([$jira[0][] | select(.fields.status.name == "In Progress")] | length),
    rate: ((([$jira[0][] | select(.fields.status.name == "Done" or .fields.status.name == "Closed")] | length) * 100) / (if ($jira[0] | length) == 0 then 1 else ($jira[0] | length) end) | floor)
  },

  # PR stats
  pr_stats: {
    total: ($github[0].totals.pull_requests // 0),
    merged: ($github[0].totals.prs_merged // 0),
    merge_rate: (if ($github[0].totals.pull_requests // 0) > 0 then (($github[0].totals.prs_merged // 0) / ($github[0].totals.pull_requests // 1) * 100 | floor) else 0 end),
    reviews_given: ($github[0].totals.reviews // 0)
  },

  # Activity heatmap (day of week + hour patterns from dates)
  activity_heatmap: (
    [$jira[0][] | .fields.created[0:10]] +
    [$github[0].commits[]?.date[0:10]]
    | map(. as $d | try (strptime("%Y-%m-%d") | strftime("%u")) catch "0")
    | group_by(.)
    | map({day: (.[0] | tonumber), count: length})
    | sort_by(.day)
  ),

  # Monthly activity for velocity trend
  velocity_trend: (
    [$jira[0][] | select(.fields.resolutiondate) | {
      month: (.fields.resolutiondate[0:7]),
      hours: ((.fields.timespent // 0) / 3600)
    }]
    | group_by(.month)
    | map({
        month: .[0].month,
        issues_closed: length,
        hours: ([.[].hours] | add | floor)
      })
    | sort_by(.month)
  ),

  # Cycle time (days from created to resolved)
  cycle_time: {
    average_days: (
      [$jira[0][] | select(.fields.resolutiondate) |
        ((.fields.resolutiondate[0:10] | strptime("%Y-%m-%d") | mktime) -
         (.fields.created[0:10] | strptime("%Y-%m-%d") | mktime)) / 86400
      ] | if length > 0 then (add / length | floor) else 0 end
    ),
    fastest: (
      [$jira[0][] | select(.fields.resolutiondate) |
        ((.fields.resolutiondate[0:10] | strptime("%Y-%m-%d") | mktime) -
         (.fields.created[0:10] | strptime("%Y-%m-%d") | mktime)) / 86400
      ] | if length > 0 then min | floor else 0 end
    ),
    slowest: (
      [$jira[0][] | select(.fields.resolutiondate) |
        ((.fields.resolutiondate[0:10] | strptime("%Y-%m-%d") | mktime) -
         (.fields.created[0:10] | strptime("%Y-%m-%d") | mktime)) / 86400
      ] | if length > 0 then max | floor else 0 end
    )
  },

  # Tech/skills extraction from issue summaries
  skills: (
    [$jira[0][].fields.summary | ascii_downcase] | join(" ") |
    [
      {skill: "Terraform", pattern: "terraform"},
      {skill: "Kubernetes", pattern: "k8s|kubernetes|gke|cluster"},
      {skill: "Python", pattern: "python"},
      {skill: "Node.js", pattern: "node|nodejs"},
      {skill: "Docker", pattern: "docker|container"},
      {skill: "AWS", pattern: "aws|s3|ec2|lambda"},
      {skill: "GCP", pattern: "gcp|google cloud|cloudsql"},
      {skill: "Cloudflare", pattern: "cloudflare|zero trust"},
      {skill: "CI/CD", pattern: "ci/cd|pipeline|deploy|argocd"},
      {skill: "MySQL", pattern: "mysql"},
      {skill: "PostgreSQL", pattern: "postgres"},
      {skill: "Grafana", pattern: "grafana"},
      {skill: "Security", pattern: "security|vulnerability|auth"}
    ] | map(select(. as $s | $jira[0][].fields.summary | ascii_downcase | test($s.pattern)) | .skill) | unique
  ),

  # Impact score (weighted combination)
  impact_score: {
    components: {
      issues_completed: ([$jira[0][] | select(.fields.status.name == "Done" or .fields.status.name == "Closed")] | length),
      hours_logged: ([$jira[0][] | .fields.timespent // 0] | add / 3600 | floor),
      prs_merged: ($github[0].totals.prs_merged // 0),
      reviews_given: ($github[0].totals.reviews // 0),
      repos_touched: ($github[0].repos_contributed_to | length)
    },
    formula: "issues×10 + hours×0.5 + PRs×5 + reviews×3 + repos×2",
    total: (
      ([$jira[0][] | select(.fields.status.name == "Done" or .fields.status.name == "Closed")] | length) * 10 +
      ([$jira[0][] | .fields.timespent // 0] | add / 3600 | floor) * 0.5 +
      ($github[0].totals.prs_merged // 0) * 5 +
      ($github[0].totals.reviews // 0) * 3 +
      ($github[0].repos_contributed_to | length) * 2
    | floor)
  },

  # Collaboration (from PR reviews)
  collaboration: {
    reviews_given: ($github[0].totals.reviews // 0),
    prs_created: ($github[0].totals.pull_requests // 0),
    unique_repos_reviewed: ([$github[0].reviews[]?.repo] | unique | length)
  }
}' > "$OUTPUT_FILE"

echo "Generated: $OUTPUT_FILE"
echo ""
echo "Stats summary:"
jq '{
  completion_rate: .completion_rate.rate,
  pr_merge_rate: .pr_stats.merge_rate,
  avg_cycle_time_days: .cycle_time.average_days,
  impact_score: .impact_score.total,
  skills_detected: (.skills | length),
  weeks_tracked: (.activity_timeline | length)
}' "$OUTPUT_FILE"
