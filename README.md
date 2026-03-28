# serena-setup

Portable, idempotent setup for [Serena](https://github.com/oraios/serena) — a semantic code-intelligence MCP server that gives AI tools (Claude Code, Claude Desktop, Cursor, VS Code) IDE-like symbol navigation, refactoring, and code understanding across 40+ languages.

## Quick start

```bash
git clone https://github.com/wwvuillemot/serena ~/Projects/serena
cd ~/Projects/serena
make setup
```

## Commands

| Command | Description |
|---|---|
| `make setup` | Full bootstrap: `uv`, config, all detected clients, then language servers |
| `make install-lsp` | Scan repos, detect languages, prompt per language to install servers |
| `make setup-projects` | Add `.serena/project.yml` to every project under `~/Projects` |
| `make setup-project PATH=…` | Add `.serena/project.yml` to one project |
| `make update` | Pull latest changes and re-run `make setup` |
| `make check` | Verify Serena is correctly wired in all detected clients |
| `make cache-clean` | Force `uvx` to re-download Serena on next use |
| `make help` | Show all targets |

`PROJECTS_ROOT` defaults to `~/Projects`. Override any target with:

```bash
make install-lsp PROJECTS_ROOT=/some/other/path
```

---

## What `make setup` does

1. Installs `uv` (Python package manager) if missing
2. Pre-fetches Serena via `uvx` so first use is fast
3. Copies `serena_config.yml` → `~/.serena/serena_config.yml`
4. For each detected client, prompts to install or update:
   - **Claude Code** — global MCP (`-s user`, `--project-from-cwd`)
   - **VS Code** — dedicated `mcp.json` (also cleans up stale `settings.json` entries)
   - **Cursor** — `~/.cursor/mcp.json`
   - **Claude Desktop** — `claude_desktop_config.json` (macOS only)
5. Runs `make install-lsp` — scans `~/Projects`, detects languages, and prompts per language to install servers

Verify everything after setup:

```bash
make check
```

---

## Language server installer

`make install-lsp` (also called automatically by `make setup`):

- Scans all repos under `~/Projects` for language indicators (`go.mod`, `Cargo.toml`, `tsconfig.json`, `*.py`, etc.) with a progress spinner
- Shows install status — already-installed and bundled servers are labelled
- Prompts individually per language (`Install Go (gopls)? [Y/n]`)
- Declining a language records it in `~/.serena/lsp-skip` so it won't be asked again (delete the file to re-prompt)
- Checks prerequisites before installing (e.g. won't attempt `gopls` if `go` isn't found)

Supported languages: Go, Rust, Python (pyright), TypeScript/JS, Ruby, C/C++, C#/F#, Java, Scala, Kotlin, Haskell, Elixir, Erlang, OCaml, R, Fortran, Nix, Zig, PHP, Ansible, Vue, Solidity, Elm, Lua, Bash/Shell.

---

## What this repo manages

| File | Purpose |
|---|---|
| `Makefile` | Primary interface — all commands |
| `install.sh` | Called by `make setup`; idempotent bootstrap |
| `serena_config.yml` | Global Serena config template, copied to `~/.serena/` at setup |
| `templates/cursor-mcp.json` | Cursor global MCP config (`~/.cursor/mcp.json`) |
| `templates/claude-desktop-mcp.json` | Claude Desktop MCP config (`claude_desktop_config.json`) |
| `templates/vscode-mcp-snippet.json` | VS Code MCP entry merged into user `mcp.json` |
| `scripts/install-language-servers.sh` | Interactive language server installer |
| `scripts/setup-project.sh` | Creates `.serena/project.yml` in a single project |
| `scripts/setup-all-projects.sh` | Runs `setup-project.sh` across every project under `~/Projects` |

Serena itself is **not** installed locally — it runs on demand via `uvx`.

---

## Prerequisites

- macOS, Linux, or WSL on Windows 11
- `make` — ships with macOS (Xcode CLT) and all Linux distros
- `python3` — for JSON merging; ships with macOS and most Linux distros
- For **Claude Code**: `claude` CLI installed and authenticated
- For **Claude Desktop**: `/Applications/Claude.app` installed (macOS only)
- `uv` is installed automatically by `make setup`

---

## New machine setup

```bash
git clone https://github.com/wwvuillemot/serena ~/Projects/serena
cd ~/Projects/serena
make setup
```

---

## Per-project setup

Each project can have a `.serena/project.yml` for overrides and a `.serena/memories/` folder for Serena's persistent notes about that codebase.

```bash
# All projects under ~/Projects at once
make setup-projects

# One project
make setup-project PATH=~/Projects/my-repo
```

Both are idempotent — safe to re-run as new projects are added.

---

## How each client uses Serena

### Claude Code CLI

Configured globally with `--project-from-cwd` — Serena auto-detects the project from wherever `claude` is launched.

```bash
cd ~/Projects/my-repo
claude
/mcp   # confirm serena shows as connected
```

### VS Code

Written to the dedicated **user** `mcp.json` with `${workspaceFolder}` — activates automatically for any folder you open. No per-project config needed.

For a per-workspace override, create `.vscode/mcp.json` in the project:

```json
{
  "servers": {
    "serena": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--from", "git+https://github.com/oraios/serena",
               "serena", "start-mcp-server",
               "--context", "ide",
               "--project", "${workspaceFolder}"]
    }
  }
}
```

> **Note:** VS Code previously used `mcp.servers` inside `settings.json`. That location is deprecated. `make setup` automatically migrates to the dedicated `mcp.json` and removes the stale entry from `settings.json`.

### Cursor

Configured globally via `~/.cursor/mcp.json`. Verify: **Cursor Settings → MCP** → `serena` should show as connected.

### Claude Desktop (macOS)

Configured via `~/Library/Application Support/Claude/claude_desktop_config.json`. `make setup` detects the app and prompts to install. Restart Claude Desktop after setup to activate.

---

## Configuration

### Global config: `serena_config.yml`

Copied to `~/.serena/serena_config.yml` at setup time. Serena may write runtime state (project list, etc.) back to `~/.serena/` — this stays local and never touches the repo.

To push a config change to all machines: edit `serena_config.yml`, commit, push, then run `make update` on each machine.

Key options:

```yaml
language_backend: LSP          # or "JetBrains"
log_level: 20                  # 10=DEBUG 20=INFO 30=WARNING 40=ERROR
web_dashboard: true            # browser-based log viewer at http://localhost:24282
web_dashboard_open_on_launch: false  # don't auto-open browser on every start
ignored_paths:                 # gitignore-style, merged with per-project rules
  - "**/node_modules/**"
  - "**/.venv/**"
```

### Per-project config: `.serena/project.yml`

Created by `make setup-project`. Overrides global settings for that repo:

```yaml
ignored_paths:
  - "tests/fixtures/**"
```

Commit `project.yml` and `memories/` so teammates share context. Exclude caches:

```gitignore
.serena/cache/
.serena/*.log
```

---

## Keeping Serena up to date

```bash
# Pull config changes from this repo and re-run setup
make update

# Force uvx to re-download the latest Serena release
make cache-clean
```

To pin to a specific Serena version, replace the `--from` URL in `templates/cursor-mcp.json`, `templates/claude-desktop-mcp.json`, `templates/vscode-mcp-snippet.json`, and the `claude mcp add` line in `install.sh`:

```
--from git+https://github.com/oraios/serena@<commit-sha>
```

---

## Troubleshooting

**`make` not found**

```bash
xcode-select --install   # macOS
sudo apt install make    # Linux
```

**`uv` not in PATH after install**

```bash
export PATH="$HOME/.local/bin:$PATH"   # add to ~/.zshrc or ~/.bashrc
```

**Serena shows `✘ failed` in `/mcp`**

```bash
make check           # diagnose
make setup           # re-registers with correct absolute uvx path
```

The most common cause is `uvx` not being in the PATH that Claude Code uses when spawning subprocesses. `make setup` resolves and bakes in the full path automatically.

**VS Code MCP not working**

Manually copy `templates/vscode-mcp-snippet.json` to:
- macOS: `~/Library/Application Support/Code/User/mcp.json`
- Linux/WSL: `~/.config/Code/User/mcp.json`

If you see "MCP servers should no longer be configured in user settings", run `make setup` — it will migrate to the dedicated `mcp.json` and clean up `settings.json` automatically.

**Onboarding runs every time**

Serena writes memories to `.serena/memories/`. If they're missing or gitignored, onboarding re-triggers. Either commit the memories or set in `.serena/project.yml`:

```yaml
# not a real key — disable via mode flag instead:
# pass --mode no-onboarding in the MCP args
```

**Slow first start**

Expected on first run — `uvx` downloads and caches Serena. `make setup` pre-caches it.

---

## References

- [Serena GitHub](https://github.com/oraios/serena)
- [Serena Docs](https://oraios.github.io/serena/01-about/000_intro.html)
- [Configuration Reference](https://oraios.github.io/serena/02-usage/050_configuration.html)
- [Client Setup Guide](https://oraios.github.io/serena/02-usage/030_clients.html)
- [Language Support](https://oraios.github.io/serena/01-about/020_programming-languages.html)
