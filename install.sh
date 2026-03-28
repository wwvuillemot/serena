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

if [[ -L "$TARGET" && "$(readlink "$TARGET")" == "$SOURCE" ]]; then
  ok "Symlink already correct: $TARGET → $SOURCE"
elif [[ -f "$TARGET" && ! -L "$TARGET" ]]; then
  warn "Backing up existing config to ${TARGET}.bak"
  mv "$TARGET" "${TARGET}.bak"
  ln -s "$SOURCE" "$TARGET"
  ok "Symlinked $TARGET → $SOURCE"
else
  ln -sf "$SOURCE" "$TARGET"
  ok "Symlinked $TARGET → $SOURCE"
fi

# -----------------------------------------------------------------------------
# 3. Claude Code — global MCP entry
# -----------------------------------------------------------------------------
section "Claude Code (global MCP)"

if ! command -v claude &>/dev/null; then
  warn "claude CLI not found — skipping Claude Code MCP setup."
  warn "Install Claude Code, then run:"
  warn "  claude mcp add --global serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context claude-code --project-from-cwd"
else
  # Check if serena is already registered
  if claude mcp list 2>/dev/null | grep -q "serena"; then
    ok "Serena already registered in Claude Code global MCP."
  else
    claude mcp add --global serena -- \
      uvx --from git+https://github.com/oraios/serena \
      serena start-mcp-server \
      --context claude-code \
      --project-from-cwd
    ok "Serena added to Claude Code global MCP."
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
  # Use Python to safely merge the mcp.servers key into existing settings
  python3 - "$VSCODE_SETTINGS" "$REPO_DIR/templates/vscode-mcp-snippet.json" <<'PYEOF'
import json, sys, os

settings_path = sys.argv[1]
snippet_path  = sys.argv[2]

# Load or initialize settings
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

# Deep-merge mcp.servers so we don't clobber other MCP servers
settings.setdefault("mcp", {}).setdefault("servers", {})
settings["mcp"]["servers"].update(snippet["mcp"]["servers"])

# Backup original
if os.path.exists(settings_path):
    import shutil
    shutil.copy2(settings_path, settings_path + ".bak")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"  [✓] Merged serena MCP entry into {settings_path}")
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
  # Merge serena entry without clobbering other servers
  python3 - "$CURSOR_MCP" "$CURSOR_TEMPLATE" <<'PYEOF'
import json, sys, os, shutil
existing_path, template_path = sys.argv[1], sys.argv[2]
with open(existing_path) as f:
    try:
        existing = json.load(f)
    except json.JSONDecodeError:
        print(f"  [!] Could not parse {existing_path} — overwriting.")
        existing = {}
with open(template_path) as f:
    template = json.load(f)

existing.setdefault("mcpServers", {})
existing["mcpServers"].update(template["mcpServers"])

shutil.copy2(existing_path, existing_path + ".bak")
with open(existing_path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
print(f"  [✓] Merged serena into {existing_path}")
PYEOF
else
  cp "$CURSOR_TEMPLATE" "$CURSOR_MCP"
  ok "Created $CURSOR_MCP"
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
echo "  • Set up individual projects:    bash $REPO_DIR/scripts/setup-project.sh <path>"
echo "  • Set up all ~/Projects at once: bash $REPO_DIR/scripts/setup-all-projects.sh"
echo
echo "Serena docs: https://oraios.github.io/serena/01-about/000_intro.html"
