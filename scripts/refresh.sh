#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"

echo "=== Refreshing Work Portfolio ==="
echo ""

echo "Step 1/8: Fetching JIRA data..."
"$SCRIPT_DIR/fetch-jira.sh"
echo ""

echo "Step 2/8: Sanitizing sensitive data..."
"$SCRIPT_DIR/sanitize-data.sh"
echo ""

echo "Step 3/8: Fetching GitHub data..."
"$SCRIPT_DIR/fetch-github.sh"
echo ""

echo "Step 4/8: Aggregating data..."
"$SCRIPT_DIR/aggregate.sh"
echo ""

echo "Step 5/8: Computing stats..."
"$SCRIPT_DIR/compute-stats.sh"
echo ""

echo "Step 6/8: Saving snapshot..."
SNAPSHOT_DATE=$(date +%Y-%m-%d)
mkdir -p "$SCRIPT_DIR/../data/history"
cp "$SCRIPT_DIR/../data/portfolio.json" "$SCRIPT_DIR/../data/history/portfolio-${SNAPSHOT_DATE}.json"
"$SCRIPT_DIR/generate-history.sh"
echo ""

echo "Step 7/8: Generating public data..."
"$SCRIPT_DIR/generate-public-data.sh"
echo ""

echo "Step 8/8: Generating diff report..."
"$SCRIPT_DIR/generate-diff-report.sh"
echo ""

echo "=== Done! ==="
echo ""
echo "To view the site locally:"
echo "  cd $(dirname "$SCRIPT_DIR") && python3 -m http.server 8000"
echo ""
echo "Then open: http://localhost:8000/site/"
