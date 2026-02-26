# Watch GitHub Actions CI and retrieve failed logs
# Usage: .\scripts\watch-ci.ps1 [-Commit <sha>] [-Workflow <name>]
#
# With no arguments, finds the latest run for the current branch HEAD.
# When a run fails, prints the failed job logs for easy copy-paste into an AI agent.

param(
    [string]$Commit,
    [string]$Workflow
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: gh CLI not found. Install from https://cli.github.com/" -ForegroundColor Red
    exit 1
}

if (-not $Commit) {
    $Commit = git rev-parse HEAD
}
$ShortSha = $Commit.Substring(0, 7)

Write-Host "Looking for CI runs on commit $ShortSha..." -ForegroundColor Cyan

$listArgs = @("run", "list", "--commit", $Commit, "--json", "databaseId,name,status,conclusion,headBranch,event", "--limit", "20")
if ($Workflow) {
    $listArgs += @("--workflow", $Workflow)
}

$maxAttempts = 30
$attempt = 0
$runs = @()

while ($attempt -lt $maxAttempts) {
    $runsJson = gh @listArgs 2>&1
    $runs = $runsJson | ConvertFrom-Json

    if ($runs.Count -gt 0) {
        break
    }

    $attempt++
    if ($attempt -eq 1) {
        Write-Host "No runs found yet. Waiting for GitHub to pick up the commit..." -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 10
}

if ($runs.Count -eq 0) {
    Write-Host "ERROR: No workflow runs found for commit $ShortSha after ${maxAttempts} attempts." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Found $($runs.Count) run(s):" -ForegroundColor Green
foreach ($run in $runs) {
    Write-Host "  [$($run.status)] $($run.name) (ID: $($run.databaseId))" -ForegroundColor White
}
Write-Host ""

$inProgress = $runs | Where-Object { $_.status -ne "completed" }

if ($inProgress.Count -gt 0) {
    Write-Host "Watching $($inProgress.Count) in-progress run(s)..." -ForegroundColor Cyan
    Write-Host ""

    foreach ($run in $inProgress) {
        Write-Host "--- Watching: $($run.name) (ID: $($run.databaseId)) ---" -ForegroundColor Cyan
        gh run watch $run.databaseId
        Write-Host ""
    }

    $runsJson = gh @listArgs 2>&1
    $runs = $runsJson | ConvertFrom-Json
}

$failed = $runs | Where-Object { $_.conclusion -eq "failure" }
$passed = $runs | Where-Object { $_.conclusion -eq "success" }

Write-Host "=== RESULTS ===" -ForegroundColor Magenta
Write-Host ""

foreach ($run in $passed) {
    Write-Host "  PASS: $($run.name)" -ForegroundColor Green
}
foreach ($run in $failed) {
    Write-Host "  FAIL: $($run.name)" -ForegroundColor Red
}

if ($failed.Count -eq 0) {
    Write-Host ""
    Write-Host "All runs passed." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "=== FAILED JOB LOGS ===" -ForegroundColor Red
Write-Host ""

foreach ($run in $failed) {
    Write-Host "--- $($run.name) (ID: $($run.databaseId)) ---" -ForegroundColor Red
    Write-Host ""
    gh run view $run.databaseId --log-failed
    Write-Host ""
}

exit 1
