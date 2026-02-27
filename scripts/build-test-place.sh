#!/usr/bin/env bash
# Build test place with darklua require transformation
# Usage: bash scripts/build-test-place.sh
# Prereq: wally install must have run so DevPackages/ exists for the sourcemap

set -e

rojo sourcemap test-place.project.json -o sourcemap.json
rm -rf plugin-build
darklua process --config .darklua.json plugin plugin-build
rojo build test-place-build.project.json -o TestPlace.rbxl
