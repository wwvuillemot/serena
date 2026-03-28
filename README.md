# serena-setup

Portable, idempotent setup for [Serena](https://github.com/oraios/serena) — a semantic code-intelligence MCP server that gives AI tools (Claude Code, Cursor, VS Code Copilot, etc.) IDE-like symbol navigation, refactoring, and code understanding across 40+ languages.

## What this repo manages

| File/Script | Purpose |
|---|---|
| `serena_config.yml` | Global Serena config, symlinked to `~/.serena/serena_config.yml` |
| `install.sh` | One-shot bootstrap: installs `uv`, links config, wires MCP into all three clients |
| `templates/cursor-mcp.json` | Cursor global MCP config (`~/.cursor/mcp.json`) |
| `templates/vscode-mcp-snippet.json` | VS Code MCP entry merged into user `settings.json` |
| `scripts/setup-project.sh` | Creates `.serena/project.yml` in a single project |
| `scripts/setup-all-projects.sh` | Runs `setup-project.sh` across every project under `~/Projects` |

Serena itself is **not** installed locally — it runs via `uvx` (no version pinning, always pulls latest).

---

## Prerequisites

- macOS, Linux, or WSL on Windows 11
- `uv` — the install script will install it if missing
- `python3` — for JSON merging in the install script (ships with macOS and most Linux distros)
- For **Claude Code**: `claude` CLI installed and authenticated
- Language servers for the languages you work in (see [Language Support](https://oraios.github.io/serena/01-about/020_programming-languages.html))

---

## Setting up a new machine

```bash
# 1. Clone this repo
git clone https://github.com/wwvuillemot/serena ~/Projects/serena
cd ~/Projects/serena

# 2. Run the installer (safe to run multiple times)
bash install.sh
```

The installer will:
1. Install `uv` if not present
2. Pre-fetch Serena so first use is fast
3. Symlink `serena_config.yml` → `~/.serena/serena_config.yml`
4. Register Serena in **Claude Code** global MCP
5. Merge Serena into **VS Code** user `settings.json`
6. Merge Serena into **Cursor** `~/.cursor/mcp.json`

---

## Per-project setup (optional but recommended)

Each project under `~/Projects` can have a `.serena/project.yml` for project-specific overrides (custom ignore rules, language server config, etc.) and a `.serena/memories/` folder for Serena's persistent notes.

### One project

```bash
bash scripts/setup-project.sh ~/Projects/my-repo
# or, from inside the project:
bash ~/Projects/serena/scripts/setup-project.sh
```

### All projects at once

```bash
bash scripts/setup-all-projects.sh
# optionally with a custom root:
bash scripts/setup-all-projects.sh /path/to/projects
```

This scans `~/Projects` (up to 2 levels deep), skips directories without project markers (`.git`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.), and creates `.serena/project.yml` in each.

---

## How each client uses Serena

### Claude Code CLI

Configured globally — no per-project action needed.

```bash
cd ~/Projects/my-repo
claude  # Serena is available; it detects the project from cwd
```

Serena is registered with `--project-from-cwd`, so it automatically targets whichever directory you launch Claude Code from.

To verify registration:

```bash
claude mcp list
```

### VS Code

Serena is added to your **user** `settings.json` with `${workspaceFolder}` — it activates automatically when you open any folder. No per-project `.vscode/` config needed.

If you prefer per-workspace config instead, create `.vscode/mcp.json` in the project:

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

### Cursor IDE

Configured globally via `~/.cursor/mcp.json`. Opens automatically for any workspace. To verify, open **Cursor Settings → MCP** and confirm `serena` is listed.

---

## Configuration

### Global config: `serena_config.yml`

This file is symlinked to `~/.serena/serena_config.yml` and applies to all projects. Edit it here; the symlink means changes take effect immediately everywhere.

Key options:

```yaml
language_backend: language_servers   # or "JetBrains"
log_level: INFO                      # DEBUG | INFO | WARNING | ERROR
global_ignore_rules:                 # gitignore-style patterns
  - "**/node_modules/**"
  - "**/.venv/**"
```

### Per-project config: `.serena/project.yml`

Lives in each project repo. Created by `setup-project.sh`. Use it to override global settings for that project:

```yaml
ignore_rules:
  - "tests/fixtures/**"
auto_onboarding: false
```

Commit `project.yml` and `memories/` to the project repo so teammates benefit from accumulated context. Exclude caches:

```gitignore
.serena/cache/
.serena/*.log
```

---

## Updating Serena

Serena runs via `uvx`, which caches the latest version. To force-pull a newer version:

```bash
uvx cache clean
```

Or pin to a specific commit by replacing the `--from` URL in the templates:

```
--from git+https://github.com/oraios/serena@<commit-sha>
```

Update the URL in:
- `serena_config.yml` (if referencing)
- `templates/cursor-mcp.json`
- `templates/vscode-mcp-snippet.json`
- `install.sh` (the `claude mcp add` line)

---

## Re-running the installer

The installer is idempotent — safe to run again after pulling changes:

```bash
cd ~/Projects/serena
git pull
bash install.sh
```

---

## Troubleshooting

**Serena doesn't start / uvx not found**

Ensure `~/.local/bin` or `~/.cargo/bin` is in your `PATH`. Add to `~/.zshrc` or `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Claude Code doesn't see Serena**

```bash
claude mcp list        # check it's registered
claude mcp remove serena && bash ~/Projects/serena/install.sh  # re-register
```

**VS Code settings not updated**

Manually merge `templates/vscode-mcp-snippet.json` into your VS Code `settings.json`:
- macOS: `~/Library/Application Support/Code/User/settings.json`
- Linux/WSL: `~/.config/Code/User/settings.json`

**Slow first start**

Expected — `uvx` downloads and caches Serena on the first run. Subsequent starts are fast. Run `bash install.sh` to pre-cache.

**Onboarding runs every time**

Serena's onboarding creates memory files in `.serena/memories/`. If they're missing or gitignored, onboarding re-triggers. Either commit the memories or add `auto_onboarding: false` to the project's `.serena/project.yml`.

---

## References

- [Serena GitHub](https://github.com/oraios/serena)
- [Serena Docs](https://oraios.github.io/serena/01-about/000_intro.html)
- [Configuration Reference](https://oraios.github.io/serena/02-usage/050_configuration.html)
- [Client Setup Guide](https://oraios.github.io/serena/02-usage/030_clients.html)
- [Language Support](https://oraios.github.io/serena/01-about/020_programming-languages.html)
