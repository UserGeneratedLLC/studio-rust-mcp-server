#!/usr/bin/env bash
# Complete CI Pipeline
# Usage: bash scripts/ci.sh

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
cargo clippy -j $THREADS --all-targets --all-features 2>&1
clippy_exit=$?
record "Clippy" $clippy_exit

step 5 "Build Everything"
cargo build --locked --all-targets --all-features
build_exit=$?
record "Build" $build_exit

step 6 "Run ALL Rust Tests"
cargo test --locked --all-features -- --test-threads=$THREADS 2>&1
rust_tests=$?
record "Rust Tests" $rust_tests

step 7 "Run Roblox Plugin Tests"
rojo build test-place.project.json -o TestPlace.rbxl
if [ $? -eq 0 ]; then
    run-in-roblox --script run-tests.server.luau --place TestPlace.rbxl
    plugin_tests=$?
else
    echo "Skipped: build failed"
    plugin_tests=1
fi
record "Plugin Tests" $plugin_tests

# ─── Report ──────────────────────────────────────────────────────────────────

pass_or_fail() { [ "$1" -eq 0 ] && echo "PASS" || echo "FAIL"; }

echo ""
echo "=== CI COMPLETE ==="
echo ""
echo "Formatting:"
echo "  - Stylua: $(pass_or_fail $stylua_exit)"
echo "  - Rustfmt: $(pass_or_fail $rustfmt_exit)"
echo ""
echo "Linting:"
echo "  - Selene: $(pass_or_fail $selene_exit)"
echo "  - Clippy: $(pass_or_fail $clippy_exit)"
echo ""
echo "Build: $(pass_or_fail $build_exit)"
echo ""
echo "Tests:"
echo "  - Rust: $(pass_or_fail $rust_tests)"
echo "  - Plugin: $(pass_or_fail $plugin_tests)"

echo ""
if [ ${#failures[@]} -eq 0 ]; then
    echo "--- Overall: PASS ---"
    exit 0
else
    echo "--- Overall: FAIL ---"
    echo "Failed steps: $(IFS=', '; echo "${failures[*]}")"
    exit 1
fi
