# /ci-plugin-cloud - Plugin CI Pipeline (Cloud)

Run the plugin-only CI pipeline using Open Cloud for tests instead of local run-in-roblox.

## Instructions

### 1. Run the CI Script

**Windows (PowerShell):**
```powershell
.\scripts\ci-plugin-cloud.ps1
```

**macOS/Linux (Bash):**
```bash
bash scripts/ci-plugin-cloud.sh
```

**Monitor the script output as it runs.** After each step completes, check its result. If a step failed, kill the script and switch to manual fixing (step 2) — don't let it continue to the next step.

### 2. Fix Failures Between Steps

When a step fails, stop the script and fix the issue before continuing. Use targeted commands to speed up the feedback loop:

1. **Formatting failures** — auto-fix with `stylua plugin`, then verify with `selene plugin`.

2. **Test failures — investigate the implementation, not just the tests.** For every failing test:
   - Read the failing test to understand what behavior it asserts.
   - Read the implementation code the test exercises.
   - Determine the root cause:
     - **Implementation regression/bug:** The feature is incomplete or broken. **Fix the implementation** so the test passes. Do not weaken or delete the test.
     - **Outdated test fixture:** The test's snapshot or fixture data is stale because of an intentional change. Update the fixture, or regenerate the fixture data. Confirm the new fixture reflects correct behavior.
     - **Incomplete feature:** A new feature was added but doesn't fully handle all cases the tests cover. **Complete the feature implementation** rather than trimming the tests to match a partial implementation.
   - **Never** delete or gut a test just to make CI green. Tests exist for a reason — the code must satisfy them, not the other way around.
   - **Re-run only the plugin tests** to verify fixes quickly (use the cloud test command from `scripts/test-plugin-cloud.ps1`).

3. **After all known issues are fixed**, re-run the full plugin CI script from step 1 to catch any remaining failures.

4. Repeat until the script exits with `Overall: PASS`.

### 3. Report

Once CI passes clean, provide a brief summary of what was fixed (if anything) and confirm the final result.
