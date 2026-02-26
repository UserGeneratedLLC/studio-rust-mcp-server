#!/usr/bin/env bash
# Docker-based multi-OS CI testing
# Usage: bash scripts/test-docker.sh
#
# Builds and tests inside Linux containers for x86_64 and aarch64.
# Requires Docker with QEMU emulation enabled for ARM builds.

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

if ! command -v docker &>/dev/null; then
    echo "ERROR: docker not found. Install Docker from https://www.docker.com/"
    exit 1
fi

step 1 "Build & Test Linux x86_64"
docker compose -f docker-compose.ci.yml run --rm --build test-linux-x86_64
x86_exit=$?
record "Linux x86_64" $x86_exit

step 2 "Build & Test Linux aarch64"
docker compose -f docker-compose.ci.yml run --rm --build test-linux-aarch64
arm_exit=$?
record "Linux aarch64" $arm_exit

# ─── Report ──────────────────────────────────────────────────────────────────

pass_or_fail() { [ "$1" -eq 0 ] && echo "PASS" || echo "FAIL"; }

echo ""
echo "=== DOCKER CI COMPLETE ==="
echo ""
echo "Platforms:"
echo "  - Linux x86_64:  $(pass_or_fail $x86_exit)"
echo "  - Linux aarch64: $(pass_or_fail $arm_exit)"

echo ""
if [ ${#failures[@]} -eq 0 ]; then
    echo "--- Overall: PASS ---"
    exit 0
else
    echo "--- Overall: FAIL ---"
    echo "Failed: $(IFS=', '; echo "${failures[*]}")"
    exit 1
fi
