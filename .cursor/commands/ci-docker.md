# /ci-docker - Docker Multi-Platform CI

Run the containerized multi-platform CI by executing the Docker test script. This builds and tests on Linux x86_64 and Linux aarch64 inside Docker containers.

Native Windows testing is covered by the regular `/ci` command. macOS requires a Mac or GitHub Actions.

## Prerequisites

- Docker Desktop installed and running
- QEMU emulation enabled (Docker Desktop enables this automatically on Windows/macOS)

## Instructions

### 1. Run the Docker Test Script

**Windows (PowerShell):**
```powershell
.\scripts\test-docker.ps1
```

**macOS/Linux (Bash):**
```bash
bash scripts/test-docker.sh
```

**Monitor the script output as it runs.** Each platform builds and tests sequentially.

### 2. Fix Failures

When a platform fails, check the container output for the error. Common issues:

1. **Compilation errors on Linux** -- platform-specific code paths (e.g., `cfg(target_os)` blocks) may have issues that don't surface on Windows. Fix the code and re-run.

2. **Test failures** -- same investigation approach as `/ci`: read the failing test, read the implementation, fix the root cause. Re-run only the failing platform to verify:

   ```powershell
   docker compose -f docker-compose.ci.yml run --rm --build test-linux-x86_64
   docker compose -f docker-compose.ci.yml run --rm --build test-linux-aarch64
   ```

3. **Docker/QEMU issues** -- if aarch64 builds fail with emulation errors, ensure Docker Desktop has QEMU support enabled. On Linux, install `qemu-user-static` and run `docker run --rm --privileged multiarch/qemu-user-static --reset -p yes`.

### 3. Report

Once all platforms pass, provide a brief summary and confirm the final result.
