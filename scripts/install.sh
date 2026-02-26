#!/bin/bash
set -e

MODE="${1:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR/.."
cargo build "--$MODE"
EXE="./target/$MODE/rbx-studio-mcp"
pkill -f rbx-studio-mcp || true
sudo cp "$EXE" /usr/local/bin/
