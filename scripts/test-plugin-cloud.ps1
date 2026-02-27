$ErrorActionPreference = "Stop"

Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]*)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
    }
}

$env:RBX_API_KEY = $env:PLUGIN_UPLOAD_TOKEN
$env:RBX_UNIVERSE_ID = $env:PLUGIN_CI_UNIVERSE_ID
$env:RBX_PLACE_ID = $env:PLUGIN_CI_PLACE_ID

Write-Host "Building test place..." -ForegroundColor Cyan
.\scripts\build-test-place.ps1

Write-Host "Running tests via Open Cloud..." -ForegroundColor Cyan
lune run run-tests TestPlace.rbxl
