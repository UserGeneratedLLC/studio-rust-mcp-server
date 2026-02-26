# Auto-fix Formatting & Static Analysis
# Usage: .\scripts\format.ps1

$Threads = [Environment]::ProcessorCount

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

Write-Step 2 "Auto-fix Rust Formatting"
cargo fmt
$rustfmt = $LASTEXITCODE
Record-Result "Rustfmt" $rustfmt

Write-Step 3 "Lua Static Analysis (Selene)"
selene plugin
$selene = $LASTEXITCODE
Record-Result "Selene" $selene

Write-Step 4 "Rust Linting (Clippy) - Auto-fix"
cargo clippy -j $Threads --fix --allow-dirty --allow-staged 2>&1 | Out-Null
Write-Host "Verifying..." -ForegroundColor Yellow
cargo clippy -j $Threads --all-targets --all-features 2>&1
$clippy = $LASTEXITCODE
Record-Result "Clippy" $clippy

# ─── Report ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== FORMAT COMPLETE ===" -ForegroundColor Magenta
Write-Host ""
Write-Host "Formatting:"
Write-Host "  - Stylua: $(if ($stylua -eq 0) {'PASS'} else {'FAIL'})"
Write-Host "  - Rustfmt: $(if ($rustfmt -eq 0) {'PASS'} else {'FAIL'})"
Write-Host ""
Write-Host "Linting:"
Write-Host "  - Selene: $(if ($selene -eq 0) {'PASS'} else {'FAIL'})"
Write-Host "  - Clippy: $(if ($clippy -eq 0) {'PASS'} else {'FAIL'})"

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "--- Overall: PASS ---" -ForegroundColor Green
    exit 0
} else {
    Write-Host "--- Overall: FAIL ---" -ForegroundColor Red
    Write-Host "Failed steps: $($failures -join ', ')" -ForegroundColor Red
    exit 1
}
