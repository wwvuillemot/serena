# Changelog

All notable changes to `dev-ai-tools` are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). While the project is pre-1.0, minor versions may include breaking changes.

To update to a specific version:

```bash
make update VERSION=v0.5.1
```

## [Unreleased]

## [0.5.4] - 2026-04-24

### Added
- `make preflight` target for pre-push QA. Checks: (1) working tree clean, (2) `make lint` passes, (3) local branch is in sync with (or ahead of) `origin`, (4) all local tags are pushed. Treats lint failures, divergence, and "behind origin" as blocking; unpushed tags print a warning rather than blocking.
- `make preflight` documented in the Commands table.

## [0.5.3] - 2026-04-24

### Added
- `make lint` target runs ShellCheck locally with the same `severity=warning` config as CI, so you can catch lint findings before pushing. Exits with a clear hint if ShellCheck isn't installed.

## [0.5.2] - 2026-04-24

### Added
- **CI**: ShellCheck workflow (`.github/workflows/ci.yml`) runs on every push to `main`, PR, and tag starting with `v`. Uses `severity: warning` — real bugs surface, style-only findings stay quiet.
- **LICENSE**: MIT.
- README badges: CI status, latest release, license.
- "License" section at the bottom of the README noting that bundled tools retain their own licenses.

### Fixed
- Removed dead variable `WIN_SETTINGS` in `install.sh` — leftover from the v0.1.0 VS Code `settings.json` → `mcp.json` migration. Surfaced by ShellCheck (SC2034).

## [0.5.1] - 2026-04-24

### Added
- `CHANGELOG.md` documenting releases from v0.1.0 forward.
- `make update VERSION=<tag>` pins the repo to a specific release tag before re-running `make setup`. Default (`make update` with no `VERSION`) still fast-forwards `main`.
- `VERSION` variable documented in `make help`.

### Changed
- `make update` now refuses to run when the working tree has uncommitted changes (prevents silent loss when switching tags).

## [0.5.0] - 2026-04-24

### Added
- `bin/dev-ai-tools` wrapper CLI, symlinked to `~/.local/bin/dev-ai-tools` (override with `DEV_AI_TOOLS_BIN`) so per-project tool wiring works from any directory without `cd`-ing back to the dev-ai-tools repo.
- `make install-cli` / `make uninstall-cli` targets for managing the symlink.
- `dev-ai-tools` subcommands: `install-graphify`, `install-serena` (alias: `setup-serena`), `check`, `update`, `help`.
- Automatic wrapper install as part of `make setup` (via new section in `install.sh`).
- `DEV_AI_TOOLS_SKIP_CLI_UPGRADE` env var — set by the wrapper — suppresses the redundant Graphify-CLI upgrade prompt during per-project invocations.

### Fixed
- `scripts/install-graphify.sh` no longer aborts when the Graphify CLI is already installed and the user declines an upgrade; per-client wiring now continues as intended.
- Docs that referenced `/graphify` as a slash command corrected: Graphify is a shell CLI invoked via Bash, steered by `CLAUDE.md` / `AGENTS.md` rules and a `PreToolUse` hook. `USING.md` and `.github/copilot-instructions.md` updated accordingly.

## [0.4.0] - 2026-04-22

### Added
- `USING.md` — practical guide for verifying and leveraging Serena, Graphify, and RTK in an AI-coding session, with a TL;DR, per-tool verification steps, when-to-reach-for-it tables, and a troubleshooting section. Linked from `README.md`.

## [0.3.1] - 2026-04-22

### Fixed
- `scripts/install-rtk.sh` no longer aborts when Homebrew's incidental 30-day auto-cleanup runs after `brew install rtk` and hits permission-denied errors on unrelated root-owned files in the prefix. RTK itself is poured successfully; the cleanup failure is isolated.

## [0.3.0] - 2026-04-22

### Added
- Renamed repository and command surface to **dev-ai-tools** (previously a Serena-only installer).
- **Graphify** installer (`scripts/install-graphify.sh`, `make install-graphify`) — installs the CLI via `uv tool install graphifyy` and offers to wire it into each detected client (Claude Code, Cursor, VS Code).
- **RTK** (Rust Token Killer) installer (`scripts/install-rtk.sh`, `make install-rtk`) — brew on macOS when available, else the upstream curl installer.
- Project-level `.claude/settings.json`, `.cursor/rules/graphify.mdc`, `.github/copilot-instructions.md`, and `CLAUDE.md` graphify section so the repo self-hosts the same wiring it installs elsewhere.

### Changed
- `make setup` now installs Serena + Graphify + RTK as a bundle.

## [0.2.0] - 2026-03-29

### Added
- Cross-platform support for **macOS, WSL, and Linux**.
  - Platform detection (`macos` / `wsl` / `linux`) displayed at setup start.
  - Prerequisite validation (Xcode CLT on macOS, `python3` everywhere).
  - Windows-username resolution on WSL (often differs from `$USER`).
  - `uvx` wrapped via `wsl.exe` for Windows-side VS Code and Claude Desktop configs.
  - Claude Desktop support on Windows via WSL.
  - Homebrew LLVM added to `PATH` on macOS so `clangd` is found after install.
  - ZLS falls back from snap to apt-get on Linux/WSL.
- Supported-platforms table in `README.md` documenting per-client behaviour.

### Changed
- `sudo` is used for `apt-get` when not running as root.
- Cursor noted as Linux-side only on WSL.

## [0.1.0] - 2026-03-28

### Added
- Claude Desktop as a supported MCP client throughout the installer.
- VS Code migration from `settings.json` to a dedicated `mcp.json`; cleanup of stale `settings.json` entries.
- Per-language prompt workflow for language servers (replaces earlier `fzf`-based selection).
- Skip file (`~/.serena/lsp-skip`) for declined language servers so users aren't re-prompted every run.
- `claude-desktop-mcp.json` template added to the file table in `README.md`.

### Changed
- Troubleshooting section updated for the VS Code MCP deprecation warning.

[Unreleased]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.5.4...HEAD
[0.5.4]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/wwvuillemot/dev-ai-tools/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/wwvuillemot/dev-ai-tools/releases/tag/v0.1.0
