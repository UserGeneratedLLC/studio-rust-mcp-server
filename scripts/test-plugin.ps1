$ErrorActionPreference = "Stop"

Write-Host "Building test place..." -ForegroundColor Cyan
.\scripts\build-test-place.ps1

Write-Host "Running tests in Roblox..." -ForegroundColor Cyan
run-in-roblox --script run-tests.server.luau --place TestPlace.rbxl
