$ErrorActionPreference = "Stop"

Write-Host "Building test place..." -ForegroundColor Cyan
rojo build test-place.project.json -o TestPlace.rbxl

Write-Host "Running tests in Roblox..." -ForegroundColor Cyan
run-in-roblox --script run-tests.server.luau --place TestPlace.rbxl
