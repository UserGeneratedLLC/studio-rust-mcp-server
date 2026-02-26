# Docker-based multi-OS CI testing
# Usage: .\scripts\test-docker.ps1
#
# Builds and tests inside Linux containers for x86_64 and aarch64.
# Requires Docker Desktop with QEMU emulation enabled for ARM builds.

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

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: docker not found. Install Docker Desktop from https://www.docker.com/" -ForegroundColor Red
    exit 1
}

Write-Step 1 "Build & Test Linux x86_64"
docker compose -f docker-compose.ci.yml run --rm --build test-linux-x86_64
$x86 = $LASTEXITCODE
Record-Result "Linux x86_64" $x86

Write-Step 2 "Build & Test Linux aarch64"
docker compose -f docker-compose.ci.yml run --rm --build test-linux-aarch64
$arm = $LASTEXITCODE
Record-Result "Linux aarch64" $arm

# ─── Report ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== DOCKER CI COMPLETE ===" -ForegroundColor Magenta
Write-Host ""
Write-Host "Platforms:"
Write-Host "  - Linux x86_64:  $(if ($x86 -eq 0) {'PASS'} else {'FAIL'})"
Write-Host "  - Linux aarch64: $(if ($arm -eq 0) {'PASS'} else {'FAIL'})"

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "--- Overall: PASS ---" -ForegroundColor Green
    exit 0
} else {
    Write-Host "--- Overall: FAIL ---" -ForegroundColor Red
    Write-Host "Failed: $($failures -join ', ')" -ForegroundColor Red
    exit 1
}
