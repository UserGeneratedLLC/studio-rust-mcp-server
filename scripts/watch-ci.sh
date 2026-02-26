#!/usr/bin/env bash
# Watch GitHub Actions CI and retrieve failed logs
# Usage: bash scripts/watch-ci.sh [--commit <sha>] [--workflow <name>]
#
# With no arguments, finds the latest run for the current branch HEAD.
# When a run fails, prints the failed job logs for easy copy-paste into an AI agent.

set -euo pipefail

COMMIT=""
WORKFLOW=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) COMMIT="$2"; shift 2 ;;
        --workflow) WORKFLOW="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI not found. Install from https://cli.github.com/"
    exit 1
fi

if [ -z "$COMMIT" ]; then
    COMMIT=$(git rev-parse HEAD)
fi
SHORT_SHA="${COMMIT:0:7}"

echo "Looking for CI runs on commit $SHORT_SHA..."

LIST_ARGS=(run list --commit "$COMMIT" --json "databaseId,name,status,conclusion,headBranch,event" --limit 20)
if [ -n "$WORKFLOW" ]; then
    LIST_ARGS+=(--workflow "$WORKFLOW")
fi

MAX_ATTEMPTS=30
ATTEMPT=0
RUNS="[]"

while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
    RUNS=$(gh "${LIST_ARGS[@]}" 2>&1 || true)
    COUNT=$(echo "$RUNS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)

    if [ "$COUNT" -gt 0 ]; then
        break
    fi

    ATTEMPT=$((ATTEMPT + 1))
    if [ "$ATTEMPT" -eq 1 ]; then
        echo "No runs found yet. Waiting for GitHub to pick up the commit..."
    fi
    sleep 10
done

if [ "$COUNT" -eq 0 ]; then
    echo "ERROR: No workflow runs found for commit $SHORT_SHA after $MAX_ATTEMPTS attempts."
    exit 1
fi

echo ""
echo "Found $COUNT run(s):"
echo "$RUNS" | python3 -c "
import sys, json
for r in json.load(sys.stdin):
    print(f'  [{r[\"status\"]}] {r[\"name\"]} (ID: {r[\"databaseId\"]})')
"
echo ""

IN_PROGRESS_IDS=$(echo "$RUNS" | python3 -c "
import sys, json
for r in json.load(sys.stdin):
    if r['status'] != 'completed':
        print(r['databaseId'])
")

if [ -n "$IN_PROGRESS_IDS" ]; then
    IP_COUNT=$(echo "$IN_PROGRESS_IDS" | wc -l | tr -d ' ')
    echo "Watching $IP_COUNT in-progress run(s)..."
    echo ""

    while IFS= read -r run_id; do
        echo "--- Watching run ID: $run_id ---"
        gh run watch "$run_id"
        echo ""
    done <<< "$IN_PROGRESS_IDS"

    RUNS=$(gh "${LIST_ARGS[@]}" 2>&1 || true)
fi

echo "=== RESULTS ==="
echo ""

echo "$RUNS" | python3 -c "
import sys, json
runs = json.load(sys.stdin)
for r in runs:
    if r['conclusion'] == 'success':
        print(f'  PASS: {r[\"name\"]}')
for r in runs:
    if r['conclusion'] == 'failure':
        print(f'  FAIL: {r[\"name\"]}')
"

FAILED_IDS=$(echo "$RUNS" | python3 -c "
import sys, json
for r in json.load(sys.stdin):
    if r.get('conclusion') == 'failure':
        print(f'{r[\"databaseId\"]} {r[\"name\"]}')
" 2>/dev/null || true)

if [ -z "$FAILED_IDS" ]; then
    echo ""
    echo "All runs passed."
    exit 0
fi

echo ""
echo "=== FAILED JOB LOGS ==="
echo ""

while IFS= read -r line; do
    run_id=$(echo "$line" | cut -d' ' -f1)
    run_name=$(echo "$line" | cut -d' ' -f2-)
    echo "--- $run_name (ID: $run_id) ---"
    echo ""
    gh run view "$run_id" --log-failed
    echo ""
done <<< "$FAILED_IDS"

exit 1
