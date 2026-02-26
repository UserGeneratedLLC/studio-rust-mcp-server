#!/bin/bash
set -e

# Builds and installs the Roblox Studio plugin (MCPStudioPlugin.rbxm)
# Usage: bash scripts/install-plugin.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

PLUGINS_DIR="$HOME/Documents/Roblox/Plugins"

rojo build plugin.project.json -o MCPStudioPlugin.rbxm

mkdir -p "$PLUGINS_DIR"
cp MCPStudioPlugin.rbxm "$PLUGINS_DIR/"

echo "Installed MCPStudioPlugin.rbxm to $PLUGINS_DIR"
