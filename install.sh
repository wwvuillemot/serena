#!/usr/bin/env bash
# =============================================================================
# Serena Setup — install.sh
# Managed via: https://github.com/wwvuillemot/serena
#
# Idempotent bootstrap for Serena MCP on macOS and Linux (including WSL).
# Run from the repo root: bash install.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERENA_HOME="${SERENA_HOME:-$HOME/.serena}"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
info()    { echo "  [·] $*"; }
ok()      { echo "  [✓] $*"; }
warn()    { echo "  [!] $*"; }
section() { echo; echo "── $* ──────────────────────────────────────────────"; }

detect_os() {
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "macos"
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    echo "wsl"
  else
    echo "linux"
  fi
}

OS="$(detect_os)"

# -----------------------------------------------------------------------------
# 1. Check / install uv
# -----------------------------------------------------------------------------
section "uv (Python package manager)"

if command -v uv &>/dev/null; then
  ok "uv is already installed: $(uv --version)"
else
  warn "uv not found. Installing..."
  if [[ "$OS" == "macos" ]]; then
    if command -v brew &>/dev/null; then
      brew install uv
    else
      curl -LsSf https://astral.sh/uv/install.sh | sh
      # Reload PATH for current session
      export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    fi
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi

  if command -v uv &>/dev/null; then
    ok "uv installed: $(uv --version)"
  else
    warn "uv installed but not in current PATH. You may need to restart your shell."
    warn "Add one of these to your shell profile:"
    warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    warn "  export PATH=\"\$HOME/.cargo/bin:\$PATH\""
  fi
fi

# Resolve uvx path once — used by all client config sections below
UVX_PATH="$(which uvx 2>/dev/null || echo "")"

# Pre-cache Serena so first use is fast
info "Pre-fetching Serena via uvx (this may take a moment on first run)..."
uvx --from git+https://github.com/oraios/serena serena --help &>/dev/null && ok "Serena cached" || warn "Pre-fetch failed — will download on first use"

# -----------------------------------------------------------------------------
# 2. Global Serena config (~/.serena/serena_config.yml)
# -----------------------------------------------------------------------------
section "Serena global config"

mkdir -p "$SERENA_HOME"

TARGET="$SERENA_HOME/serena_config.yml"
SOURCE="$REPO_DIR/serena_config.yml"

# Copy (not symlink) so Serena's runtime writes (e.g. projects list) stay in
# ~/.serena/ and never bleed back into the repo.
if [[ -L "$TARGET" ]]; then
  # Migrate anyone who had the old symlink approach
  warn "Converting symlink to copy (prevents runtime state leaking into repo)"
  rm "$TARGET"
fi
if [[ -f "$TARGET" ]]; then
  # Preserve any machine-local projects list across re-runs
  PROJECTS_LINE="$(grep -A999 '^projects:' "$TARGET" 2>/dev/null | head -20 || true)"
  cp "$SOURCE" "$TARGET"
  ok "Updated $TARGET from $SOURCE"
  if echo "$PROJECTS_LINE" | grep -q '/'; then
    info "Note: your local projects list in $TARGET was preserved — re-run 'make setup' if Serena loses project registrations"
  fi
else
  cp "$SOURCE" "$TARGET"
  ok "Copied $SOURCE → $TARGET"
fi

# -----------------------------------------------------------------------------
# 3. Claude Code — global MCP entry
# -----------------------------------------------------------------------------
section "Claude Code (global MCP)"

if ! command -v claude &>/dev/null; then
  warn "claude CLI not found — skipping Claude Code MCP setup."
  warn "Install Claude Code, then run:"
  warn "  claude mcp add -s user serena -- \$(which uvx) --from git+https://github.com/oraios/serena serena start-mcp-server --context claude-code --project-from-cwd"
else
  if [[ -z "$UVX_PATH" ]]; then
    warn "uvx not found in PATH — cannot register Claude Code MCP. Re-run after fixing PATH."
  else
    # Remove stale entry (may have been registered with wrong path) then re-add
    claude mcp remove serena 2>/dev/null || true
    claude mcp add -s user serena -- \
      "$UVX_PATH" --from git+https://github.com/oraios/serena \
      serena start-mcp-server \
      --context claude-code \
      --project-from-cwd
    ok "Serena added to Claude Code global MCP (uvx: $UVX_PATH)."
  fi
fi

# -----------------------------------------------------------------------------
# 4. VS Code — merge MCP server into user settings.json
# -----------------------------------------------------------------------------
section "VS Code (user settings)"

vscode_settings_path() {
  case "$OS" in
    macos) echo "$HOME/Library/Application Support/Code/User/settings.json" ;;
    wsl)   echo "$HOME/.config/Code/User/settings.json" ;;
    linux) echo "$HOME/.config/Code/User/settings.json" ;;
  esac
}

VSCODE_SETTINGS="$(vscode_settings_path)"

if [[ ! -d "$(dirname "$VSCODE_SETTINGS")" ]]; then
  warn "VS Code user directory not found — skipping VS Code setup."
  warn "If VS Code is installed, manually merge: $REPO_DIR/templates/vscode-mcp-snippet.json"
  warn "into: $VSCODE_SETTINGS"
else
  # Use Python to safely merge the mcp.servers key into existing settings,
  # substituting the resolved uvx path so Claude/IDEs don't need it in PATH.
  python3 - "$VSCODE_SETTINGS" "$REPO_DIR/templates/vscode-mcp-snippet.json" "${UVX_PATH:-uvx}" <<'PYEOF'
import json, sys, os

settings_path = sys.argv[1]
snippet_path  = sys.argv[2]
uvx_path      = sys.argv[3]

if os.path.exists(settings_path):
    with open(settings_path) as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            print(f"  [!] Could not parse {settings_path} — skipping VS Code setup.")
            sys.exit(0)
else:
    settings = {}

with open(snippet_path) as f:
    snippet = json.load(f)

# Substitute resolved uvx path into the command field
for server in snippet.get("mcp", {}).get("servers", {}).values():
    if server.get("command") == "uvx":
        server["command"] = uvx_path

settings.setdefault("mcp", {}).setdefault("servers", {})
settings["mcp"]["servers"].update(snippet["mcp"]["servers"])

if os.path.exists(settings_path):
    import shutil
    shutil.copy2(settings_path, settings_path + ".bak")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"  [✓] Merged serena MCP entry into {settings_path} (uvx: {uvx_path})")
PYEOF
fi

# WSL note: if using VS Code Remote-WSL the settings live on the Windows side
if [[ "$OS" == "wsl" ]]; then
  WIN_APPDATA="${APPDATA:-/mnt/c/Users/$USER/AppData/Roaming}"
  WIN_VSCODE="$WIN_APPDATA/Code/User/settings.json"
  if [[ -f "$WIN_VSCODE" ]]; then
    info "WSL detected: also updating Windows-side VS Code settings..."
    python3 - "$WIN_VSCODE" "$REPO_DIR/templates/vscode-mcp-snippet.json" <<'PYEOF'
import json, sys, os, shutil
settings_path, snippet_path = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    settings = json.load(f)
with open(snippet_path) as f:
    snippet = json.load(f)
settings.setdefault("mcp", {}).setdefault("servers", {})
settings["mcp"]["servers"].update(snippet["mcp"]["servers"])
shutil.copy2(settings_path, settings_path + ".bak")
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(f"  [✓] Merged into Windows VS Code: {settings_path}")
PYEOF
  fi
fi

# -----------------------------------------------------------------------------
# 5. Cursor — ~/.cursor/mcp.json
# -----------------------------------------------------------------------------
section "Cursor IDE (~/.cursor/mcp.json)"

CURSOR_MCP="$HOME/.cursor/mcp.json"
CURSOR_TEMPLATE="$REPO_DIR/templates/cursor-mcp.json"

mkdir -p "$HOME/.cursor"

if [[ -f "$CURSOR_MCP" ]]; then
  # Merge serena entry without clobbering other servers,
  # substituting the resolved uvx path.
  python3 - "$CURSOR_MCP" "$CURSOR_TEMPLATE" "${UVX_PATH:-uvx}" <<'PYEOF'
import json, sys, os, shutil
existing_path, template_path, uvx_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(existing_path) as f:
    try:
        existing = json.load(f)
    except json.JSONDecodeError:
        print(f"  [!] Could not parse {existing_path} — overwriting.")
        existing = {}
with open(template_path) as f:
    template = json.load(f)

for server in template.get("mcpServers", {}).values():
    if server.get("command") == "uvx":
        server["command"] = uvx_path

existing.setdefault("mcpServers", {})
existing["mcpServers"].update(template["mcpServers"])

shutil.copy2(existing_path, existing_path + ".bak")
with open(existing_path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
print(f"  [✓] Merged serena into {existing_path} (uvx: {uvx_path})")
PYEOF
else
  # Write template with resolved uvx path directly
  python3 - "$CURSOR_TEMPLATE" "$CURSOR_MCP" "${UVX_PATH:-uvx}" <<'PYEOF'
import json, sys
template_path, out_path, uvx_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(template_path) as f:
    template = json.load(f)
for server in template.get("mcpServers", {}).values():
    if server.get("command") == "uvx":
        server["command"] = uvx_path
with open(out_path, "w") as f:
    json.dump(template, f, indent=2)
    f.write("\n")
print(f"  [✓] Created {out_path} (uvx: {uvx_path})")
PYEOF
fi

# -----------------------------------------------------------------------------
# 6. Make scripts executable
# -----------------------------------------------------------------------------
section "Script permissions"
chmod +x "$REPO_DIR/scripts/setup-project.sh"
chmod +x "$REPO_DIR/scripts/setup-all-projects.sh"
ok "Scripts are executable"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
section "Complete"
echo
echo "Serena is configured for:"
echo "  • Claude Code CLI  (global MCP, auto-detects project from cwd)"
echo "  • VS Code          (user settings, uses \${workspaceFolder})"
echo "  • Cursor IDE       (~/.cursor/mcp.json, auto-detects project from cwd)"
echo
echo "Optional next steps:"
echo "  • Set up individual projects:    make setup-project PATH=~/Projects/my-repo"
echo "  • Set up all ~/Projects at once: make setup-projects"
echo
echo "Serena docs: https://oraios.github.io/serena/01-about/000_intro.html"
