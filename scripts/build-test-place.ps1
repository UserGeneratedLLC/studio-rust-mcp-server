# Build test place with darklua require transformation
# Usage: .\scripts\build-test-place.ps1
# Prereq: wally install must have run so DevPackages/ exists for the sourcemap

$ErrorActionPreference = "Stop"

rojo sourcemap test-place.project.json -o sourcemap.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

darklua process --config .darklua.json plugin plugin-build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

rojo build test-place-build.project.json -o TestPlace.rbxl
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
