# Plugin CI Pipeline - Cloud (Luau only, tests via Open Cloud)
# Usage: .\scripts\ci-plugin-cloud.ps1

$ErrorActionPreference = "Continue"
$failures = @()

function Write-Step($number, $name) {
    Write-Host ""
    Write-Host "=== Step ${number}: $name ===" -ForegroundColor Cyan
}

function Record-Result($step, $exitCode) {
    if ($exitCode -ne 0) {
        $script:failures += $step
        Write-Host "FAIL" -ForegroundColor Red
    } else {
        Write-Host "PASS" -ForegroundColor Green
    }
}

Write-Step 1 "Auto-fix Lua Formatting (Stylua)"
stylua plugin
$stylua = $LASTEXITCODE
Record-Result "Stylua" $stylua

Write-Step 2 "Lua Static Analysis (Selene)"
selene plugin
$selene = $LASTEXITCODE
Record-Result "Selene" $selene

Write-Step 3 "Run Roblox Plugin Tests (Open Cloud)"
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]*)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
    }
}
$env:RBX_API_KEY = $env:PLUGIN_UPLOAD_TOKEN
$env:RBX_UNIVERSE_ID = $env:PLUGIN_CI_UNIVERSE_ID
$env:RBX_PLACE_ID = $env:PLUGIN_CI_PLACE_ID

.\scripts\build-test-place.ps1
if ($LASTEXITCODE -eq 0) {
    lune run run-tests TestPlace.rbxl
    $pluginTests = $LASTEXITCODE
} else {
    Write-Host "Skipped: build failed" -ForegroundColor Yellow
    $pluginTests = 1
}
Record-Result "Plugin Tests" $pluginTests

# ─── Report ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== PLUGIN CI (CLOUD) COMPLETE ===" -ForegroundColor Magenta
Write-Host ""
Write-Host "Formatting:"
Write-Host "  - Stylua: $(if ($stylua -eq 0) {'PASS'} else {'FAIL'})"
Write-Host ""
Write-Host "Linting:"
Write-Host "  - Selene: $(if ($selene -eq 0) {'PASS'} else {'FAIL'})"
Write-Host ""
Write-Host "Tests:"
Write-Host "  - Plugin (Cloud): $(if ($pluginTests -eq 0) {'PASS'} else {'FAIL'})"

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "--- Overall: PASS ---" -ForegroundColor Green
    exit 0
} else {
    Write-Host "--- Overall: FAIL ---" -ForegroundColor Red
    Write-Host "Failed steps: $($failures -join ', ')" -ForegroundColor Red
    exit 1
}
