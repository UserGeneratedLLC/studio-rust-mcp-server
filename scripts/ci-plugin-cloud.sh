#!/usr/bin/env bash
# Plugin CI Pipeline - Cloud (Luau only, tests via Open Cloud)
# Usage: bash scripts/ci-plugin-cloud.sh

set -o pipefail

failures=()

step() {
    echo ""
    echo "=== Step $1: $2 ==="
}

record() {
    if [ "$2" -ne 0 ]; then
        failures+=("$1")
        echo "FAIL"
    else
        echo "PASS"
    fi
}

step 1 "Auto-fix Lua Formatting (Stylua)"
stylua plugin
stylua_exit=$?
record "Stylua" $stylua_exit

step 2 "Lua Static Analysis (Selene)"
selene plugin
selene_exit=$?
record "Selene" $selene_exit

step 3 "Run Roblox Plugin Tests (Open Cloud)"
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi
export RBX_API_KEY="$PLUGIN_UPLOAD_TOKEN"
export RBX_UNIVERSE_ID="$PLUGIN_CI_UNIVERSE_ID"
export RBX_PLACE_ID="$PLUGIN_CI_PLACE_ID"

bash scripts/build-test-place.sh
if [ $? -eq 0 ]; then
    lune run run-tests TestPlace.rbxl
    plugin_tests=$?
else
    echo "Skipped: build failed"
    plugin_tests=1
fi
record "Plugin Tests" $plugin_tests

# ─── Report ──────────────────────────────────────────────────────────────────

pass_or_fail() { [ "$1" -eq 0 ] && echo "PASS" || echo "FAIL"; }

echo ""
echo "=== PLUGIN CI (CLOUD) COMPLETE ==="
echo ""
echo "Formatting:"
echo "  - Stylua: $(pass_or_fail $stylua_exit)"
echo ""
echo "Linting:"
echo "  - Selene: $(pass_or_fail $selene_exit)"
echo ""
echo "Tests:"
echo "  - Plugin (Cloud): $(pass_or_fail $plugin_tests)"

echo ""
if [ ${#failures[@]} -eq 0 ]; then
    echo "--- Overall: PASS ---"
    exit 0
else
    echo "--- Overall: FAIL ---"
    echo "Failed steps: $(IFS=', '; echo "${failures[*]}")"
    exit 1
fi
