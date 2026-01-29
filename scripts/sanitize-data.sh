#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
DATA_DIR="$SCRIPT_DIR/../data"

echo "Sanitizing sensitive data from JIRA exports..."

# Cross-platform sed -i (macOS vs Linux)
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

for file in "$DATA_DIR"/jira/*.json; do
  if [ -f "$file" ]; then
    echo "Processing: $file"

    # Google API keys
    sedi 's/AIza[0-9A-Za-z_-]\{35\}/[REDACTED_GOOGLE_API_KEY]/g' "$file"

    # Vault tokens (hvs. and s. formats)
    sedi 's/hvs\.[a-zA-Z0-9]\{24,\}/[REDACTED_VAULT_TOKEN]/g' "$file"
    sedi 's/"id": *"s\.[a-zA-Z0-9]\{24\}"/"id": "[REDACTED_VAULT_TOKEN]"/g' "$file"

    # AWS keys
    sedi 's/AKIA[0-9A-Z]\{16\}/[REDACTED_AWS_KEY]/g' "$file"

    # URL tokens (Google Chat webhooks, etc)
    sedi 's/\&token=[a-zA-Z0-9_-]\{20,\}/\&token=[REDACTED]/g' "$file"

    # Bearer tokens
    sedi 's/Bearer [a-zA-Z0-9_-]\{20,\}/Bearer [REDACTED]/g' "$file"

    # Slack webhooks
    sedi 's|hooks.slack.com/services/[A-Z0-9/]*|hooks.slack.com/services/[REDACTED]|g' "$file"
  fi
done

echo "Done."
