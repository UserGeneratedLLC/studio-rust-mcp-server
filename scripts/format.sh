#!/usr/bin/env bash
# Auto-fix Formatting & Static Analysis
# Usage: bash scripts/format.sh

set -o pipefail

THREADS=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)

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

step 2 "Auto-fix Rust Formatting"
cargo fmt
rustfmt_exit=$?
record "Rustfmt" $rustfmt_exit

step 3 "Lua Static Analysis (Selene)"
selene plugin
selene_exit=$?
record "Selene" $selene_exit

step 4 "Rust Linting (Clippy) - Auto-fix"
cargo clippy -j $THREADS --fix --allow-dirty --allow-staged >/dev/null 2>&1
echo "Verifying..."
cargo clippy -j $THREADS --all-targets --all-features -- -D warnings 2>&1
clippy_exit=$?
record "Clippy" $clippy_exit

# ─── Report ──────────────────────────────────────────────────────────────────

pass_or_fail() { [ "$1" -eq 0 ] && echo "PASS" || echo "FAIL"; }

echo ""
echo "=== FORMAT COMPLETE ==="
echo ""
echo "Formatting:"
echo "  - Stylua: $(pass_or_fail $stylua_exit)"
echo "  - Rustfmt: $(pass_or_fail $rustfmt_exit)"
echo ""
echo "Linting:"
echo "  - Selene: $(pass_or_fail $selene_exit)"
echo "  - Clippy: $(pass_or_fail $clippy_exit)"

echo ""
if [ ${#failures[@]} -eq 0 ]; then
    echo "--- Overall: PASS ---"
    exit 0
else
    echo "--- Overall: FAIL ---"
    echo "Failed steps: $(IFS=', '; echo "${failures[*]}")"
    exit 1
fi
