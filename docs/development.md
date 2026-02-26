# Development Guide

## Prerequisites

### Required

- **Rust** -- Install via [rustup](https://rustup.rs/). The stable toolchain is used for all builds.
- **Rokit** -- Manages Roblox toolchain binaries. Install from [github.com/rojo-rbx/rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in the repo root. This provides:
  - **Rojo** -- Roblox project builder
  - **Selene** -- Luau linter
  - **Stylua** -- Luau formatter
  - **Wally** -- Luau package manager
  - **Lune** -- Luau script runner
  - **run-in-roblox** -- Local Roblox test runner

### Optional

- **Docker** -- Required for containerized multi-OS testing. Install [Docker Desktop](https://www.docker.com/). Enable QEMU emulation for ARM builds (Docker Desktop does this automatically on Windows/macOS).
- **GitHub CLI (`gh`)** -- Required for the CI log watcher script. Install from [cli.github.com](https://cli.github.com/). Authenticate with `gh auth login`.

---

## Scripts

All scripts are provided in both PowerShell (`.ps1`) and Bash (`.sh`) variants. PowerShell scripts are for Windows, Bash scripts are for macOS/Linux.

### Full CI Pipeline

Runs formatting, linting, building, Rust tests, and Roblox plugin tests.

```powershell
# Windows
.\scripts\ci.ps1

# macOS/Linux
bash scripts/ci.sh
```

Steps executed:
1. Stylua (auto-fix Luau formatting)
2. Rustfmt (auto-fix Rust formatting)
3. Selene (Luau static analysis)
4. Clippy (Rust linting with auto-fix, then verify)
5. `cargo build --locked`
6. `cargo test --locked`
7. Build test place and run plugin tests via `run-in-roblox`

### Formatting Only

Runs only the formatting and linting steps (no build or tests).

```powershell
# Windows
.\scripts\format.ps1

# macOS/Linux
bash scripts/format.sh
```

### Plugin Testing (Local)

Builds the test place and runs tests locally via `run-in-roblox`. Requires Roblox Studio installed.

```powershell
.\scripts\test-plugin.ps1
```

### Plugin Testing (Open Cloud)

Builds the test place and runs tests via the Roblox Open Cloud API. Requires a `.env` file with `PLUGIN_UPLOAD_TOKEN`, `PLUGIN_CI_PLACE_ID`, and `PLUGIN_CI_UNIVERSE_ID`.

```powershell
.\scripts\test-plugin-cloud.ps1
```

### CI Log Watcher

Watches GitHub Actions workflow runs for the current branch and automatically retrieves failed job logs. Requires `gh` CLI.

```powershell
# Watch the latest run for HEAD
.\scripts\watch-ci.ps1

# Watch a specific commit
.\scripts\watch-ci.ps1 -Commit abc1234

# Watch a specific workflow
.\scripts\watch-ci.ps1 -Workflow "CI"
```

```bash
# Watch the latest run for HEAD
bash scripts/watch-ci.sh

# Watch a specific commit
bash scripts/watch-ci.sh --commit abc1234

# Watch a specific workflow
bash scripts/watch-ci.sh --workflow "CI"
```

The script will:
1. Find workflow runs for the given commit (or HEAD)
2. Wait if no runs exist yet (polls every 10s)
3. Stream live status updates via `gh run watch`
4. On failure, print the full failed job logs

### Docker Multi-OS Testing

Builds and tests inside Linux containers for x86_64 and aarch64. Requires Docker with QEMU emulation.

```powershell
# Windows
.\scripts\test-docker.ps1

# macOS/Linux
bash scripts/test-docker.sh
```

This runs `cargo build --locked && cargo test --locked` inside containers for each Linux architecture. Docker can only test Linux variants -- Windows is tested natively, macOS requires a Mac or GitHub Actions.

---

## GitHub Actions Workflows

### CI (`ci.yml`)

Runs on every pull request and push to `main`.

| Job | Runners | What it does |
|---|---|---|
| `build-and-test` | ubuntu-22.04, ubuntu-22.04-arm, windows-latest, windows-11-arm, macos-latest | `cargo build` + `cargo test` |
| `lint` | ubuntu-latest | Rustfmt, Clippy, Stylua, Selene |
| `luau-tests` | ubuntu-latest | Build test place, run plugin tests via Open Cloud |

### Release (`release.yml`)

Triggered automatically on every push to `main`. Version is auto-incremented as `0.2.$run_number`.

| Job | What it does |
|---|---|
| `create-release` | Creates a draft GitHub release |
| `build-plugin` | Builds `MCPStudioPlugin.rbxm`, uploads to release and Roblox |
| `build` (matrix) | Builds binaries for 6 targets, zips and uploads to release |

Release targets:

| Label | Target | Runner |
|---|---|---|
| linux-x86_64 | x86_64-unknown-linux-gnu | ubuntu-22.04 |
| linux-aarch64 | aarch64-unknown-linux-gnu | ubuntu-22.04-arm |
| windows-x86_64 | x86_64-pc-windows-msvc | windows-latest |
| windows-aarch64 | aarch64-pc-windows-msvc | windows-11-arm |
| macos-x86_64 | x86_64-apple-darwin | macos-latest |
| macos-aarch64 | aarch64-apple-darwin | macos-latest |

Artifact naming: `rbx-studio-mcp-{version}-{label}.zip`

### Security Scan (`security-scan.yml`)

Runs on every pull request and push to `main`. Uses Roblox's OSS security SAST workflow.

---

## Release Process

Releases are fully automated. Every push to `main` triggers the release workflow:

1. A tag `v0.2.{run_number}` is created and pushed automatically.
2. A GitHub release is created with:
   - `MCPStudioPlugin.rbxm` (Roblox plugin)
   - 6 platform binary archives (Linux/Windows/macOS, x86_64/aarch64)
3. The plugin is uploaded to Roblox via Open Cloud.

No manual tagging is needed. The version increments automatically with each CI run.
