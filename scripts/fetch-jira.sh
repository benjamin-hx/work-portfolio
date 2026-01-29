#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.json}"

# Load config or use environment variables
if [ -f "$CONFIG_FILE" ]; then
  JIRA_EMAIL="${JIRA_EMAIL:-$(jq -r '.jira.email' "$CONFIG_FILE")}"
  JIRA_DOMAIN="${JIRA_DOMAIN:-$(jq -r '.jira.domain' "$CONFIG_FILE")}"
  SINCE_DATE="${SINCE_DATE:-$(jq -r '.profile.start_date' "$CONFIG_FILE")}"
else
  echo "Warning: config.json not found. Using environment variables." >&2
  JIRA_EMAIL="${JIRA_EMAIL:?Error: JIRA_EMAIL not set}"
  JIRA_DOMAIN="${JIRA_DOMAIN:?Error: JIRA_DOMAIN not set}"
  SINCE_DATE="${SINCE_DATE:-2024-01-01}"
fi

JIRA_TOKEN_FILE="${JIRA_TOKEN_FILE:-$HOME/.jira-token}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/../data/jira}"

# Validate token
if [ ! -f "$JIRA_TOKEN_FILE" ]; then
  echo "Error: JIRA token file not found at $JIRA_TOKEN_FILE" >&2
  echo "Create one at: https://id.atlassian.com/manage-profile/security/api-tokens" >&2
  exit 1
fi

JIRA_TOKEN=$(tr -d '\n' < "$JIRA_TOKEN_FILE")
mkdir -p "$OUTPUT_DIR"

echo "Fetching JIRA data for $JIRA_EMAIL since $SINCE_DATE..."

# Fetch issues assigned to or reported by user
JQL="(assignee was currentUser() OR reporter = currentUser()) AND created >= $SINCE_DATE ORDER BY created DESC"
OUTPUT_FILE="$OUTPUT_DIR/jira-history.json"

echo "[]" > "$OUTPUT_FILE"
PAGE_TOKEN=""
PAGE=1

while true; do
  echo "  Fetching page $PAGE..." >&2

  if [ -z "$PAGE_TOKEN" ]; then
    PAYLOAD=$(jq -n --arg jql "$JQL" '{
      jql: $jql,
      fields: ["key", "summary", "status", "created", "updated", "resolutiondate", "timespent", "issuetype", "project", "description", "comment"],
      maxResults: 100
    }')
  else
    PAYLOAD=$(jq -n --arg jql "$JQL" --arg token "$PAGE_TOKEN" '{
      jql: $jql,
      fields: ["key", "summary", "status", "created", "updated", "resolutiondate", "timespent", "issuetype", "project", "description", "comment"],
      maxResults: 100,
      nextPageToken: $token
    }')
  fi

  RESPONSE=$(curl -s -X POST -u "$JIRA_EMAIL:$JIRA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "https://$JIRA_DOMAIN/rest/api/3/search/jql")

  echo "$RESPONSE" | jq '.issues' > /tmp/page_issues.json
  jq -s '.[0] + .[1]' "$OUTPUT_FILE" /tmp/page_issues.json > /tmp/merged.json
  mv /tmp/merged.json "$OUTPUT_FILE"

  IS_LAST=$(echo "$RESPONSE" | jq -r '.isLast')
  if [ "$IS_LAST" = "true" ]; then
    break
  fi

  PAGE_TOKEN=$(echo "$RESPONSE" | jq -r '.nextPageToken')
  if [ -z "$PAGE_TOKEN" ] || [ "$PAGE_TOKEN" = "null" ]; then
    break
  fi

  ((PAGE++))
done

# Also fetch issues user commented on (but wasn't assigned/reporter)
echo "Fetching commented issues..."
COMMENT_JQL="comment ~ currentUser() AND created >= $SINCE_DATE AND NOT (assignee was currentUser() OR reporter = currentUser()) ORDER BY created DESC"

RESPONSE=$(curl -s -X POST -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg jql "$COMMENT_JQL" '{
    jql: $jql,
    fields: ["key", "summary", "status", "created", "updated", "resolutiondate", "timespent", "issuetype", "project", "description", "comment"],
    maxResults: 100
  }')" \
  "https://$JIRA_DOMAIN/rest/api/3/search/jql")

echo "$RESPONSE" | jq '.issues' > /tmp/commented_issues.json
jq -s '.[0] + .[1] | unique_by(.key)' "$OUTPUT_FILE" /tmp/commented_issues.json > /tmp/all_issues.json
mv /tmp/all_issues.json "$OUTPUT_FILE"

TOTAL=$(jq 'length' "$OUTPUT_FILE")
echo "Done. Total unique issues: $TOTAL"

# Generate completed issues view
jq '[.[] | select(.fields.status.name == "Done" or .fields.status.name == "Closed") | {
  key: .key,
  summary: .fields.summary,
  project: .fields.project.key,
  type: .fields.issuetype.name,
  created: .fields.created[0:10],
  resolved: (.fields.resolutiondate // "N/A")[0:10],
  hours_logged: ((.fields.timespent // 0) / 3600 | floor)
}] | sort_by(.resolved) | reverse' "$OUTPUT_FILE" > "$OUTPUT_DIR/jira-completed.json"

echo "Generated: $OUTPUT_DIR/jira-completed.json"

# Generate themed view using config patterns
if [ -f "$CONFIG_FILE" ]; then
  THEMES=$(jq -r '.themes | to_entries | map("\"" + .key + "\": [.[] | select(.fields.summary | test(\"" + (.value.patterns | join("|")) + "\"; \"i\")) | {key, summary: .fields.summary, hours: ((.fields.timespent // 0) / 3600 | floor)}]") | join(", ")' "$CONFIG_FILE")
fi

# Fallback to default themes
jq '[.[] | select(.fields.status.name == "Done" or .fields.status.name == "Closed")] | {
  "cloudflare": [.[] | select(.fields.summary | test("cloudflare|zero trust|WARP|access|gateway"; "i")) | {key, summary: .fields.summary, hours: ((.fields.timespent // 0) / 3600 | floor)}],
  "kubernetes": [.[] | select(.fields.summary | test("GKE|kubernetes|k8s|cluster|dockyard|node|pod"; "i")) | {key, summary: .fields.summary, hours: ((.fields.timespent // 0) / 3600 | floor)}],
  "cicd": [.[] | select(.fields.summary | test("ci-service|deploy|pipeline|github|terraform|argocd"; "i")) | {key, summary: .fields.summary, hours: ((.fields.timespent // 0) / 3600 | floor)}],
  "database": [.[] | select(.fields.summary | test("sql|database|postgres|mysql|cloudsql"; "i")) | {key, summary: .fields.summary, hours: ((.fields.timespent // 0) / 3600 | floor)}],
  "security": [.[] | select(.fields.summary | test("security|vulnerability|scanning|posture|auth"; "i")) | {key, summary: .fields.summary, hours: ((.fields.timespent // 0) / 3600 | floor)}],
  "aws": [.[] | select(.fields.summary | test("AWS|S3|EC2|lambda"; "i")) | {key, summary: .fields.summary, hours: ((.fields.timespent // 0) / 3600 | floor)}],
  "monitoring": [.[] | select(.fields.summary | test("grafana|monitoring|alert|log|metric"; "i")) | {key, summary: .fields.summary, hours: ((.fields.timespent // 0) / 3600 | floor)}]
}' "$OUTPUT_FILE" > "$OUTPUT_DIR/jira-by-theme.json"

echo "Generated: $OUTPUT_DIR/jira-by-theme.json"
