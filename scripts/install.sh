#!/bin/bash
set -e

MODE="${1:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR/.."
cargo build "--$MODE"
EXE="./target/$MODE/rbx-studio-mcp"
killall rbx-studio-mcp 2>/dev/null || true
sudo killall rbx-studio-mcp 2>/dev/null || true
sudo cp "$EXE" /usr/local/bin/

bash "$SCRIPT_DIR/install-plugin.sh"
