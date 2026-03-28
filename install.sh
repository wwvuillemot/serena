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
# 4. VS Code — write to dedicated mcp.json (settings.json is deprecated)
# -----------------------------------------------------------------------------
section "VS Code (user mcp.json)"

vscode_user_dir() {
  case "$OS" in
    macos) echo "$HOME/Library/Application Support/Code/User" ;;
    *)     echo "$HOME/.config/Code/User" ;;
  esac
}

VSCODE_USER_DIR="$(vscode_user_dir)"
VSCODE_MCP="$VSCODE_USER_DIR/mcp.json"
VSCODE_SETTINGS="$VSCODE_USER_DIR/settings.json"

if [[ ! -d "$VSCODE_USER_DIR" ]]; then
  warn "VS Code user directory not found — skipping VS Code setup."
  warn "If VS Code is installed, copy: $REPO_DIR/templates/vscode-mcp-snippet.json"
  warn "to: $VSCODE_MCP"
else
  python3 - "$VSCODE_MCP" "$REPO_DIR/templates/vscode-mcp-snippet.json" "${UVX_PATH:-uvx}" <<'PYEOF'
import json, sys, os, shutil

mcp_path    = sys.argv[1]
snippet_path = sys.argv[2]
uvx_path    = sys.argv[3]

existing = {}
if os.path.exists(mcp_path):
    with open(mcp_path) as f:
        try:
            existing = json.load(f)
        except json.JSONDecodeError:
            pass
    shutil.copy2(mcp_path, mcp_path + ".bak")

with open(snippet_path) as f:
    snippet = json.load(f)

# Substitute resolved uvx path
for server in snippet.get("servers", {}).values():
    if server.get("command") == "uvx":
        server["command"] = uvx_path

existing.setdefault("servers", {}).update(snippet["servers"])

with open(mcp_path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")

print(f"  [✓] Wrote serena to {mcp_path} (uvx: {uvx_path})")
PYEOF

  # Clean up stale mcp.servers entry from settings.json if present
  if [[ -f "$VSCODE_SETTINGS" ]]; then
    python3 - "$VSCODE_SETTINGS" <<'PYEOF'
import json, sys, os, shutil
path = sys.argv[1]
with open(path) as f:
    try:
        s = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)
mcp = s.get("mcp", {})
servers = mcp.get("servers", {})
if "serena" in servers:
    del servers["serena"]
    if not servers:
        mcp.pop("servers", None)
    if not mcp:
        s.pop("mcp", None)
    shutil.copy2(path, path + ".bak")
    with open(path, "w") as f:
        json.dump(s, f, indent=2)
        f.write("\n")
    print(f"  [✓] Removed stale serena entry from settings.json")
PYEOF
  fi
fi

# WSL note: if using VS Code Remote-WSL the mcp.json lives on the Windows side
if [[ "$OS" == "wsl" ]]; then
  WIN_APPDATA="${APPDATA:-/mnt/c/Users/$USER/AppData/Roaming}"
  WIN_MCP="$WIN_APPDATA/Code/User/mcp.json"
  WIN_SETTINGS="$WIN_APPDATA/Code/User/settings.json"
  if [[ -d "$(dirname "$WIN_MCP")" ]]; then
    info "WSL detected: also updating Windows-side VS Code mcp.json..."
    python3 - "$WIN_MCP" "$REPO_DIR/templates/vscode-mcp-snippet.json" "${UVX_PATH:-uvx}" <<'PYEOF'
import json, sys, os, shutil
mcp_path, snippet_path, uvx_path = sys.argv[1], sys.argv[2], sys.argv[3]
existing = {}
if os.path.exists(mcp_path):
    with open(mcp_path) as f:
        try: existing = json.load(f)
        except: pass
    shutil.copy2(mcp_path, mcp_path + ".bak")
with open(snippet_path) as f:
    snippet = json.load(f)
for server in snippet.get("servers", {}).values():
    if server.get("command") == "uvx":
        server["command"] = uvx_path
existing.setdefault("servers", {}).update(snippet["servers"])
with open(mcp_path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
print(f"  [✓] Wrote serena to {mcp_path}")
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
echo "Serena docs: https://oraios.github.io/serena/01-about/000_intro.html"
echo

# -----------------------------------------------------------------------------
# 7. Language servers
# -----------------------------------------------------------------------------
section "Language servers"
echo
read -r -p "  Scan projects and install language servers now? [Y/n] " _lsp_answer
_lsp_answer="${_lsp_answer:-Y}"
echo
echo "  (You can run 'make install-lsp' at any time to install or update language servers.)"
echo
if [[ "$_lsp_answer" =~ ^[Yy] ]]; then
  bash "$REPO_DIR/scripts/install-language-servers.sh"
fi
