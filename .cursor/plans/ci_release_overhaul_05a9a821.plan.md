---
name: CI/Release Overhaul
overview: "Overhaul CI/CD to match rojo's multi-platform approach: 6-target release artifacts, multi-OS CI testing with debug info, CI log watcher scripts, and Docker-based local multi-OS testing."
todos:
  - id: cargo-profiles
    content: Add release profile with debug = "line-tables-only" to Cargo.toml and aarch64 Windows CRT static to .cargo/config.toml
    status: completed
  - id: ci-workflow
    content: Create .github/workflows/ci.yml with multi-platform build+test matrix, lint, and Luau tests; delete checks.yml
    status: completed
  - id: release-workflow
    content: Rewrite .github/workflows/release.yml with 6-target binary matrix + plugin build; delete build.yml
    status: completed
  - id: watch-ci-scripts
    content: Create scripts/watch-ci.ps1 and scripts/watch-ci.sh for CI log watching/pulling
    status: completed
  - id: docker-testing
    content: Create Dockerfile.ci, docker-compose.ci.yml, and scripts/test-docker.ps1/.sh for containerized multi-OS testing
    status: completed
  - id: docs
    content: Create docs/development.md documenting all scripts, CI workflows, Docker testing, and prerequisites
    status: completed
  - id: cursor-commands
    content: Verify ci.md and format.md are up to date; create .cursor/commands/ci-docker.md for Docker multi-platform CI
    status: completed
isProject: false
---

# CI/CD and Release Overhaul

## Current State

- [checks.yml](.github/workflows/checks.yml): PR-only lint + Luau tests, no Rust build/test
- [build.yml](.github/workflows/build.yml): macOS + Windows only, with code signing, auto-versioning (`0.2.$run_number`), release on every main push
- [release.yml](.github/workflows/release.yml): tag-triggered, plugin-only (no binary artifacts)
- [security-scan.yml](.github/workflows/security-scan.yml): kept as-is (no changes needed)

## Workflow Migration Map

No functionality is lost. Every job from the old workflows moves into the new ones:

- `**checks.yml` (deleted)** -- All jobs move into `ci.yml`:
  - `lint` job (Rustfmt, Clippy, Stylua, Selene) -> `ci.yml` `lint` job (identical)
  - `luau-tests` job (Open Cloud) -> `ci.yml` `luau-tests` job (identical)
- `**build.yml` (deleted)** -- Jobs split across `ci.yml` and `release.yml`:
  - Build-on-PR/push behavior -> `ci.yml` `build-and-test` job (expanded from 2 platforms to 5)
  - Release artifact creation -> `release.yml` `build` matrix (expanded from 2 platforms to 6)
  - macOS/Windows code signing -> dropped (per decision)
  - Auto-release on main push -> replaced by tag-triggered releases (per decision)
  - Auto-versioning (`0.2.$run_number`) -> replaced by tag version (e.g. `v0.3.0`)
- `**release.yml` (rewritten in-place)** -- Expanded:
  - Plugin build + Roblox upload -> kept as `build-plugin` job (unchanged)
  - Added: `create-release` job, 6-target binary `build` matrix
- `**security-scan.yml`** -- Untouched

## 1. Add Release Profile with Debug Info

In [Cargo.toml](Cargo.toml), add a release profile that preserves line tables for stack traces (used by `color-eyre`):

```toml
[profile.release]
debug = "line-tables-only"
```

This gives file/line numbers in backtraces without significant binary size bloat.

## 2. Update `.cargo/config.toml` for ARM Windows

Add CRT static linking for aarch64 Windows target in [.cargo/config.toml](.cargo/config.toml):

```toml
[target.aarch64-pc-windows-msvc]
rustflags = ["-Ctarget-feature=+crt-static"]
```

## 3. Replace `checks.yml` with `ci.yml`

New [.github/workflows/ci.yml](.github/workflows/ci.yml) modeled after [rojo's ci.yml](D:/UserGenerated/rojo/.github/workflows/ci.yml):

- **Triggers:** PR + push to main
- `**build-and-test` job** (matrix): Build + `cargo test` on all 5 OS runners:
  - `ubuntu-22.04`, `ubuntu-22.04-arm`, `windows-latest`, `windows-11-arm`, `macos-latest`
  - With cargo registry/git/target caching (save/restore pattern)
- `**lint` job**: Rustfmt, Clippy, Stylua, Selene (kept from current checks.yml)
- `**luau-tests` job**: Open Cloud test execution (kept from current checks.yml)

Delete `checks.yml` after creating `ci.yml`.

## 4. Overhaul `release.yml` (Replaces Both `release.yml` + `build.yml`)

New [.github/workflows/release.yml](.github/workflows/release.yml) modeled after [rojo's release.yml](D:/UserGenerated/rojo/.github/workflows/release.yml):

- **Trigger:** Tag push (`v`*)
- `**create-release` job:** `gh release create --draft --verify-tag`
- `**build-plugin` job:** Build `.rbxm`, upload to release + Roblox (existing logic)
- `**build` job** (matrix, 6 targets matching rojo exactly):

  | host    | os               | target                    | label           |
  | ------- | ---------------- | ------------------------- | --------------- |
  | linux   | ubuntu-22.04     | x86_64-unknown-linux-gnu  | linux-x86_64    |
  | linux   | ubuntu-22.04-arm | aarch64-unknown-linux-gnu | linux-aarch64   |
  | windows | windows-latest   | x86_64-pc-windows-msvc    | windows-x86_64  |
  | windows | windows-11-arm   | aarch64-pc-windows-msvc   | windows-aarch64 |
  | macos   | macos-latest     | x86_64-apple-darwin       | macos-x86_64    |
  | macos   | macos-latest     | aarch64-apple-darwin      | macos-aarch64   |

  Each job: checkout, install Rust + target, cache, `cargo build --release --locked --target`, zip, `gh release upload`, `upload-artifact`.
  Artifact naming: `rbx-studio-mcp-{version}-{label}.zip` (e.g., `rbx-studio-mcp-0.2.0-linux-x86_64.zip`)

Delete `build.yml` after updating `release.yml`.

## 5. Local CI Scripts (Already Exist)

[scripts/ci.ps1](scripts/ci.ps1) and [scripts/ci.sh](scripts/ci.sh) already cover the full local CI pipeline (Stylua, Rustfmt, Selene, Clippy, Build, Rust Tests, Plugin Tests). No changes needed to these.

## 6. CI Log Watcher Scripts

Create `scripts/watch-ci.ps1` and `scripts/watch-ci.sh` using `gh` CLI:

- `**watch-ci`**: Finds the latest workflow run for the current branch HEAD, watches it in real-time via `gh run watch`, and on failure, retrieves failed job logs via `gh run view --log-failed`. Output is formatted for easy copy-paste into an AI agent.
- Supports flags: `--commit` (specific commit SHA), `--workflow` (specific workflow name)

## 7. Docker-Based Multi-OS Local Testing

Create the following files for containerized cross-platform testing:

- `**Dockerfile.ci`**: Rust + Rokit build environment based on `rust:latest`
- `**docker-compose.ci.yml`**: Two services:
  - `test-linux-x86_64`: native Linux x86_64
  - `test-linux-aarch64`: Linux aarch64 via QEMU emulation (`platform: linux/arm64`)
- `**scripts/test-docker.ps1`** and `**scripts/test-docker.sh`**: Orchestrator scripts that:
  1. Build the CI container image
  2. Run `cargo build --locked && cargo test --locked` inside each platform container
  3. Report per-platform pass/fail

Note: Docker can only test Linux variants. Windows is tested natively, macOS requires a Mac or CI.

## 8. Documentation (`docs/development.md`)

Create [docs/development.md](docs/development.md) covering:

- **Prerequisites**: Rust toolchain, Rokit (Stylua, Selene, Rojo, Wally, Lune, run-in-roblox), Docker (optional), `gh` CLI (optional)
- **Local CI**: `scripts/ci.ps1` / `scripts/ci.sh` -- full pipeline (format, lint, build, test, plugin test)
- **Formatting Only**: `scripts/format.ps1` / `scripts/format.sh` -- Stylua, Rustfmt, Selene, Clippy
- **Plugin Testing**: `scripts/test-plugin.ps1` (local via run-in-roblox), `scripts/test-plugin-cloud.ps1` (via Open Cloud API, requires `.env`)
- **CI Log Watcher**: `scripts/watch-ci.ps1` / `scripts/watch-ci.sh` -- watch GitHub Actions runs, auto-retrieve failed logs
- **Docker Multi-OS Testing**: `scripts/test-docker.ps1` / `scripts/test-docker.sh` -- containerized Linux x86_64 + aarch64 testing
- **GitHub Actions Workflows**: overview of `ci.yml`, `release.yml`, `security-scan.yml`
- **Release Process**: how to tag and trigger a release, what artifacts are produced

## 9. Cursor Commands

- `**ci.md`**: Already up to date -- runs `scripts/ci.ps1`/`scripts/ci.sh` for single-platform local CI. No changes needed.
- `**format.md`**: Already up to date -- runs `scripts/format.ps1`/`scripts/format.sh`. No changes needed.
- `**ci-docker.md`** (new): Cursor command that runs `scripts/test-docker.ps1`/`scripts/test-docker.sh` for Docker-based multi-platform CI. Same failure-handling instructions as `ci.md` but scoped to Docker container output. Explains that this tests Linux x86_64 + aarch64 in containers, and that native Windows testing is covered by the regular `/ci` command.

## Files Changed Summary


| Action  | File                                              |
| ------- | ------------------------------------------------- |
| Modify  | `Cargo.toml` (add release profile)                |
| Modify  | `.cargo/config.toml` (add aarch64 Windows config) |
| Create  | `.github/workflows/ci.yml`                        |
| Rewrite | `.github/workflows/release.yml`                   |
| Delete  | `.github/workflows/checks.yml`                    |
| Delete  | `.github/workflows/build.yml`                     |
| Create  | `scripts/watch-ci.ps1`                            |
| Create  | `scripts/watch-ci.sh`                             |
| Create  | `Dockerfile.ci`                                   |
| Create  | `docker-compose.ci.yml`                           |
| Create  | `scripts/test-docker.ps1`                         |
| Create  | `scripts/test-docker.sh`                          |
| Create  | `docs/development.md`                             |
| Create  | `.cursor/commands/ci-docker.md`                   |
| Verify  | `.cursor/commands/ci.md` (no changes needed)      |
| Verify  | `.cursor/commands/format.md` (no changes needed)  |


