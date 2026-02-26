# /watch-ci - Watch GitHub Actions CI

Watch the GitHub Actions workflow runs for the current branch and automatically retrieve failed job logs.

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)

## Instructions

### 1. Run the Watch Script

**Windows (PowerShell):**
```powershell
.\scripts\watch-ci.ps1
```

**macOS/Linux (Bash):**
```bash
bash scripts/watch-ci.sh
```

**Let the script run.** It will find the latest CI run for HEAD, wait if GitHub hasn't picked it up yet, then stream live status updates. When all runs complete, it prints a summary.

### 2. Handle Failures

If any workflow run fails, the script automatically prints the full failed job logs. Read the logs and fix the issues:

1. **Identify the failing job and step** from the log output.
2. **Read the relevant source code** to understand the failure.
3. **Fix the implementation**, not the test (unless the test is genuinely wrong).
4. **Push the fix** -- the script can be re-run to watch the new run.

### 3. Report

Once all runs pass (or failures are identified and fixed), provide a brief summary of the results.
