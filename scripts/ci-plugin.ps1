# Plugin CI Pipeline (Luau only)
# Usage: .\scripts\ci-plugin.ps1

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

Write-Step 3 "Run Roblox Plugin Tests"
rojo build test-place.project.json -o TestPlace.rbxl
if ($LASTEXITCODE -eq 0) {
    run-in-roblox --script run-tests.server.luau --place TestPlace.rbxl
    $pluginTests = $LASTEXITCODE
} else {
    Write-Host "Skipped: build failed" -ForegroundColor Yellow
    $pluginTests = 1
}
Record-Result "Plugin Tests" $pluginTests

# ─── Report ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== PLUGIN CI COMPLETE ===" -ForegroundColor Magenta
Write-Host ""
Write-Host "Formatting:"
Write-Host "  - Stylua: $(if ($stylua -eq 0) {'PASS'} else {'FAIL'})"
Write-Host ""
Write-Host "Linting:"
Write-Host "  - Selene: $(if ($selene -eq 0) {'PASS'} else {'FAIL'})"
Write-Host ""
Write-Host "Tests:"
Write-Host "  - Plugin: $(if ($pluginTests -eq 0) {'PASS'} else {'FAIL'})"

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "--- Overall: PASS ---" -ForegroundColor Green
    exit 0
} else {
    Write-Host "--- Overall: FAIL ---" -ForegroundColor Red
    Write-Host "Failed steps: $($failures -join ', ')" -ForegroundColor Red
    exit 1
}
