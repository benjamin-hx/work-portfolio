#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.json}"

# Load config or use environment variables
if [ -f "$CONFIG_FILE" ]; then
  GITHUB_ORG="${GITHUB_ORG:-$(jq -r '.github.org' "$CONFIG_FILE")}"
  GITHUB_USER="${GITHUB_USER:-$(jq -r '.github.username' "$CONFIG_FILE")}"
  SINCE_DATE="${SINCE_DATE:-$(jq -r '.profile.start_date' "$CONFIG_FILE")}"
else
  echo "Warning: config.json not found. Using environment variables." >&2
  GITHUB_ORG="${GITHUB_ORG:?Error: GITHUB_ORG not set}"
  GITHUB_USER="${GITHUB_USER:?Error: GITHUB_USER not set}"
  SINCE_DATE="${SINCE_DATE:-2024-01-01}"
fi

GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-$HOME/.github-token}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/../data/github}"

# Validate token
if [ ! -f "$GITHUB_TOKEN_FILE" ]; then
  echo "Error: GitHub token file not found at $GITHUB_TOKEN_FILE" >&2
  echo "Create one at: https://github.com/settings/tokens" >&2
  exit 1
fi

GITHUB_TOKEN=$(tr -d '\n' < "$GITHUB_TOKEN_FILE")
mkdir -p "$OUTPUT_DIR"

AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"

echo "Fetching GitHub data for $GITHUB_USER in $GITHUB_ORG since $SINCE_DATE..."

# Function to fetch all pages from GitHub Search API
fetch_all_pages() {
  local url="$1"
  local output_file="$2"
  local jq_filter="$3"
  local page=1
  local per_page=100
  local total_fetched=0

  echo '[]' > "$output_file"

  while true; do
    local response=$(curl -s -H "$AUTH_HEADER" "${url}&per_page=${per_page}&page=${page}")
    local total_count=$(echo "$response" | jq '.total_count // 0')
    local items=$(echo "$response" | jq "$jq_filter")
    local count=$(echo "$items" | jq 'length')

    if [ "$count" -eq 0 ]; then
      break
    fi

    # Merge with existing results
    jq -s '.[0] + .[1]' "$output_file" <(echo "$items") > "${output_file}.tmp"
    mv "${output_file}.tmp" "$output_file"

    total_fetched=$((total_fetched + count))

    # Stop if we've fetched all or hit reasonable limit (1000)
    if [ "$total_fetched" -ge "$total_count" ] || [ "$total_fetched" -ge 1000 ]; then
      break
    fi

    page=$((page + 1))
  done

  echo "$total_fetched"
}

# Fetch commits by user across the org
echo "Fetching commits..."
COMMITS_FILE="$OUTPUT_DIR/commits.json"
COMMIT_COUNT=$(fetch_all_pages \
  "https://api.github.com/search/commits?q=author:$GITHUB_USER+org:$GITHUB_ORG+committer-date:>=$SINCE_DATE&sort=committer-date&order=desc" \
  "$COMMITS_FILE" \
  '[.items[] | {sha: .sha, message: .commit.message, date: .commit.committer.date, repo: .repository.full_name, url: .html_url}]')
echo "  Found $COMMIT_COUNT commits"

# Fetch PRs authored by user
echo "Fetching pull requests..."
PRS_FILE="$OUTPUT_DIR/pull-requests.json"
PR_COUNT=$(fetch_all_pages \
  "https://api.github.com/search/issues?q=author:$GITHUB_USER+org:$GITHUB_ORG+type:pr+created:>=$SINCE_DATE&sort=created&order=desc" \
  "$PRS_FILE" \
  '[.items[] | {number: .number, title: .title, state: .state, created_at: .created_at, closed_at: .closed_at, repo: (.repository_url | split("/") | .[-1]), url: .html_url, labels: [.labels[].name]}]')
echo "  Found $PR_COUNT pull requests"

# Fetch PR reviews by user
echo "Fetching PR reviews..."
REVIEWS_FILE="$OUTPUT_DIR/reviews.json"
REVIEW_COUNT=$(fetch_all_pages \
  "https://api.github.com/search/issues?q=reviewed-by:$GITHUB_USER+org:$GITHUB_ORG+type:pr+created:>=$SINCE_DATE&sort=created&order=desc" \
  "$REVIEWS_FILE" \
  '[.items[] | {number: .number, title: .title, state: .state, created_at: .created_at, repo: (.repository_url | split("/") | .[-1]), url: .html_url}]')
echo "  Found $REVIEW_COUNT PR reviews"

# Fetch issues assigned to user
echo "Fetching assigned issues..."
ISSUES_FILE="$OUTPUT_DIR/issues.json"
ISSUE_COUNT=$(fetch_all_pages \
  "https://api.github.com/search/issues?q=assignee:$GITHUB_USER+org:$GITHUB_ORG+type:issue+created:>=$SINCE_DATE&sort=created&order=desc" \
  "$ISSUES_FILE" \
  '[.items[] | {number: .number, title: .title, state: .state, created_at: .created_at, closed_at: .closed_at, repo: (.repository_url | split("/") | .[-1]), url: .html_url, labels: [.labels[].name]}]')
echo "  Found $ISSUE_COUNT assigned issues"

# Generate summary
echo "Generating summary..."
SUMMARY_FILE="$OUTPUT_DIR/summary.json"

jq -n \
  --slurpfile commits "$COMMITS_FILE" \
  --slurpfile prs "$PRS_FILE" \
  --slurpfile reviews "$REVIEWS_FILE" \
  --slurpfile issues "$ISSUES_FILE" \
  --arg since "$SINCE_DATE" \
  '{
    generated_at: (now | todate),
    since: $since,
    totals: {
      commits: ($commits[0] | length),
      pull_requests: ($prs[0] | length),
      prs_merged: ([$prs[0][] | select(.state == "closed")] | length),
      reviews: ($reviews[0] | length),
      issues: ($issues[0] | length)
    },
    repos_contributed_to: ([$commits[0][].repo, $prs[0][].repo] | unique)
  }' > "$SUMMARY_FILE"

echo ""
echo "Done. GitHub summary:"
jq '.totals' "$SUMMARY_FILE"
