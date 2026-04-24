SHELL := /usr/bin/env bash
REPO_DIR := $(shell pwd)
PROJECTS_ROOT ?= $(HOME)/Projects
DEV_AI_TOOLS_BIN ?= $(HOME)/.local/bin

.DEFAULT_GOAL := help

# ─── Primary targets ──────────────────────────────────────────────────────────

.PHONY: setup
setup: ## Bootstrap dev-ai-tools (Serena, Graphify, RTK) — wires MCP clients, prompts for language servers
	@bash $(REPO_DIR)/install.sh

.PHONY: setup-projects
setup-projects: ## Add .serena/project.yml to every project under ~/Projects
	@bash $(REPO_DIR)/scripts/setup-all-projects.sh $(PROJECTS_ROOT)

.PHONY: setup-project
setup-project: ## Add .serena/project.yml to a single project (usage: make setup-project PATH=~/Projects/my-repo)
ifndef PATH
	$(error PATH is required — usage: make setup-project PATH=~/Projects/my-repo)
endif
	@bash $(REPO_DIR)/scripts/setup-project.sh $(PATH)

.PHONY: install-lsp
install-lsp: ## Scan repos and interactively install Serena language servers
	@chmod +x $(REPO_DIR)/scripts/install-language-servers.sh
	@bash $(REPO_DIR)/scripts/install-language-servers.sh $(PROJECTS_ROOT)

.PHONY: install-graphify
install-graphify: ## Install Graphify (uv tool install graphifyy) and wire it into detected clients
	@chmod +x $(REPO_DIR)/scripts/install-graphify.sh
	@bash $(REPO_DIR)/scripts/install-graphify.sh

.PHONY: install-rtk
install-rtk: ## Install RTK (brew on macOS when available, else curl installer)
	@chmod +x $(REPO_DIR)/scripts/install-rtk.sh
	@bash $(REPO_DIR)/scripts/install-rtk.sh

.PHONY: install-cli
install-cli: ## Symlink dev-ai-tools wrapper to $(DEV_AI_TOOLS_BIN) so it's callable from any repo
	@chmod +x $(REPO_DIR)/bin/dev-ai-tools
	@mkdir -p "$(DEV_AI_TOOLS_BIN)"
	@target="$(DEV_AI_TOOLS_BIN)/dev-ai-tools"; \
	src="$(REPO_DIR)/bin/dev-ai-tools"; \
	if [[ -L "$$target" && "$$(readlink "$$target")" == "$$src" ]]; then \
		echo "  [✓] dev-ai-tools already linked: $$target → $$src"; \
	elif [[ -e "$$target" && ! -L "$$target" ]]; then \
		echo "  [✗] $$target exists and is not a symlink — refusing to overwrite."; \
		echo "      Remove it manually or set DEV_AI_TOOLS_BIN=<dir> to install elsewhere."; \
		exit 1; \
	else \
		ln -sfn "$$src" "$$target"; \
		echo "  [✓] Linked: $$target → $$src"; \
	fi; \
	case ":$$PATH:" in \
		*":$(DEV_AI_TOOLS_BIN):"*) \
			echo "  [✓] $(DEV_AI_TOOLS_BIN) is on PATH" ;; \
		*) \
			echo "  [!] $(DEV_AI_TOOLS_BIN) is NOT on PATH."; \
			echo "      Add this line to your shell rc (~/.zshrc or ~/.bashrc):"; \
			echo "        export PATH=\"$(DEV_AI_TOOLS_BIN):\$$PATH\""; \
			echo "      Then reload your shell: source ~/.zshrc  (or ~/.bashrc)" ;; \
	esac

.PHONY: uninstall-cli
uninstall-cli: ## Remove the dev-ai-tools symlink from $(DEV_AI_TOOLS_BIN)
	@target="$(DEV_AI_TOOLS_BIN)/dev-ai-tools"; \
	if [[ -L "$$target" ]]; then \
		rm "$$target"; \
		echo "  [✓] Removed: $$target"; \
	else \
		echo "  [!] No symlink at $$target — nothing to remove."; \
	fi

# ─── Maintenance ──────────────────────────────────────────────────────────────

.PHONY: update
update: ## Update to latest on main (default) or a specific tag, then re-run setup (usage: make update [VERSION=v0.5.0])
	@if [[ -n "$$(git -C $(REPO_DIR) status --porcelain)" ]]; then \
		echo "  [✗] $(REPO_DIR) has uncommitted changes — commit or stash first."; \
		exit 1; \
	fi
ifneq ($(VERSION),)
	@echo "  [·] Updating dev-ai-tools to $(VERSION)..."
	@git -C $(REPO_DIR) fetch --tags --quiet
	@git -C $(REPO_DIR) checkout "$(VERSION)"
else
	@echo "  [·] Updating dev-ai-tools to latest on main..."
	@git -C $(REPO_DIR) checkout main --quiet
	@git -C $(REPO_DIR) pull --ff-only
endif
	@$(MAKE) setup

.PHONY: check
check: ## Verify Serena, Graphify, and RTK are wired up correctly across all clients
	@echo
	@echo "── uv ──────────────────────────────────────────────"
	@if command -v uv &>/dev/null; then \
		echo "  [✓] uv: $$(uv --version)"; \
	else \
		echo "  [✗] uv not found — run: make setup"; \
	fi
	@echo
	@echo "── ~/.serena/serena_config.yml ─────────────────────"
	@if [[ -f "$(HOME)/.serena/serena_config.yml" ]]; then \
		echo "  [✓] $(HOME)/.serena/serena_config.yml exists"; \
	else \
		echo "  [✗] Missing — run: make setup"; \
	fi
	@echo
	@echo "── Claude Code MCP ─────────────────────────────────"
	@if command -v claude &>/dev/null; then \
		if claude mcp list 2>/dev/null | grep -q serena; then \
			echo "  [✓] serena registered in Claude Code global MCP"; \
		else \
			echo "  [✗] serena not found — run: make setup"; \
		fi; \
	else \
		echo "  [!] claude CLI not installed"; \
	fi
	@echo
	@echo "── Cursor (~/.cursor/mcp.json) ─────────────────────"
	@if [[ -f "$(HOME)/.cursor/mcp.json" ]] && python3 -c \
		"import json; d=json.load(open('$(HOME)/.cursor/mcp.json')); exit(0 if 'serena' in d.get('mcpServers',{}) else 1)" 2>/dev/null; then \
		echo "  [✓] serena present in ~/.cursor/mcp.json"; \
	elif [[ -f "$(HOME)/.cursor/mcp.json" ]]; then \
		echo "  [✗] serena missing from ~/.cursor/mcp.json — run: make setup"; \
	else \
		echo "  [!] ~/.cursor/mcp.json not found (Cursor not installed?)"; \
	fi
	@echo
	@echo "── Claude Desktop ──────────────────────────────────"
	@CLAUDE_DESKTOP_CONFIG=""; \
	if [[ "$$(uname)" == "Darwin" ]]; then \
		CLAUDE_DESKTOP_CONFIG="$(HOME)/Library/Application Support/Claude/claude_desktop_config.json"; \
		CLAUDE_DESKTOP_APP="/Applications/Claude.app"; \
	elif grep -qi microsoft /proc/version 2>/dev/null; then \
		WIN_USER="$$(cmd.exe /C 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n' || echo $$USER)"; \
		CLAUDE_DESKTOP_CONFIG="/mnt/c/Users/$$WIN_USER/AppData/Roaming/Claude/claude_desktop_config.json"; \
		CLAUDE_DESKTOP_APP="/mnt/c/Users/$$WIN_USER/AppData/Local/AnthropicClaude"; \
	fi; \
	if [[ -n "$$CLAUDE_DESKTOP_CONFIG" ]] && { [[ -d "$$CLAUDE_DESKTOP_APP" ]] || [[ -d "/Applications/Claude.app" ]]; }; then \
		if [[ -f "$$CLAUDE_DESKTOP_CONFIG" ]] && python3 -c \
			"import json; d=json.load(open('$$CLAUDE_DESKTOP_CONFIG')); exit(0 if 'serena' in d.get('mcpServers',{}) else 1)" 2>/dev/null; then \
			echo "  [✓] serena present in Claude Desktop config"; \
		else \
			echo "  [✗] serena missing from Claude Desktop — run: make setup"; \
		fi; \
	else \
		echo "  [!] Claude Desktop not installed"; \
	fi
	@echo
	@echo "── VS Code (user mcp.json) ─────────────────────────"
	@VSCODE_MCP=""; \
	if [[ "$$(uname)" == "Darwin" ]]; then \
		VSCODE_MCP="$(HOME)/Library/Application Support/Code/User/mcp.json"; \
	else \
		VSCODE_MCP="$(HOME)/.config/Code/User/mcp.json"; \
	fi; \
	if [[ -f "$$VSCODE_MCP" ]] && python3 -c \
		"import json; d=json.load(open('$$VSCODE_MCP')); exit(0 if 'serena' in d.get('servers',{}) else 1)" 2>/dev/null; then \
		echo "  [✓] serena present in VS Code mcp.json"; \
	elif [[ -f "$$VSCODE_MCP" ]]; then \
		echo "  [✗] serena missing from VS Code mcp.json — run: make setup"; \
	else \
		echo "  [!] VS Code mcp.json not found — run: make setup"; \
	fi
	@if grep -qi microsoft /proc/version 2>/dev/null; then \
		WIN_USER="$$(cmd.exe /C 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n' || echo $$USER)"; \
		WIN_MCP="/mnt/c/Users/$$WIN_USER/AppData/Roaming/Code/User/mcp.json"; \
		echo "── VS Code Windows-side (WSL) ─────────────────────"; \
		if [[ -f "$$WIN_MCP" ]] && python3 -c \
			"import json; d=json.load(open('$$WIN_MCP')); exit(0 if 'serena' in d.get('servers',{}) else 1)" 2>/dev/null; then \
			echo "  [✓] serena present in Windows-side VS Code mcp.json"; \
		elif [[ -f "$$WIN_MCP" ]]; then \
			echo "  [✗] serena missing from Windows-side VS Code — run: make setup"; \
		else \
			echo "  [!] Windows-side VS Code mcp.json not found"; \
		fi; \
	fi
	@echo
	@echo "── Graphify ───────────────────────────────────────"
	@if command -v graphify &>/dev/null; then \
		echo "  [✓] graphify: $$(graphify --version 2>/dev/null | head -1)"; \
	else \
		echo "  [✗] graphify not found — run: make install-graphify"; \
	fi
	@echo
	@echo "── RTK ────────────────────────────────────────────"
	@if command -v rtk &>/dev/null; then \
		echo "  [✓] rtk: $$(rtk --version 2>/dev/null | head -1)"; \
	else \
		echo "  [✗] rtk not found — run: make install-rtk"; \
	fi
	@echo

.PHONY: cache-clean
cache-clean: ## Force uvx to re-download Serena on next use
	@uvx cache clean
	@echo "  [✓] uvx cache cleared — Serena will re-download on next use"

.PHONY: lint
lint: ## Run ShellCheck on all shell scripts (same as CI)
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "  [✗] shellcheck not found. Install with:  brew install shellcheck  (or your package manager)"; \
		exit 1; \
	fi
	@echo "  [·] ShellCheck (severity=warning)..."
	@shellcheck --severity=warning install.sh bin/dev-ai-tools scripts/*.sh
	@echo "  [✓] ShellCheck clean."

.PHONY: preflight
preflight: ## Pre-push checks: working tree + lint + remote sync + unpushed tags
	@echo
	@echo "── Preflight: working tree ─────────────────────────"
	@if [[ -n "$$(git -C $(REPO_DIR) status --porcelain)" ]]; then \
		echo "  [✗] Uncommitted changes — commit or stash before pushing:"; \
		git -C $(REPO_DIR) status --short | sed 's/^/      /'; \
		exit 1; \
	else \
		echo "  [✓] Clean"; \
	fi
	@echo
	@echo "── Preflight: ShellCheck ───────────────────────────"
	@$(MAKE) --no-print-directory lint
	@echo
	@echo "── Preflight: remote sync ──────────────────────────"
	@git -C $(REPO_DIR) fetch --quiet origin
	@LOCAL=$$(git -C $(REPO_DIR) rev-parse @); \
	REMOTE=$$(git -C $(REPO_DIR) rev-parse @{u} 2>/dev/null || echo ""); \
	BASE=$$(git -C $(REPO_DIR) merge-base @ @{u} 2>/dev/null || echo ""); \
	if [[ -z "$$REMOTE" ]]; then \
		echo "  [!] No upstream tracking branch — set with: git branch -u origin/<branch>"; \
	elif [[ "$$LOCAL" == "$$REMOTE" ]]; then \
		echo "  [✓] In sync with origin"; \
	elif [[ "$$LOCAL" == "$$BASE" ]]; then \
		echo "  [✗] Local is behind origin — 'git pull' first."; \
		exit 1; \
	elif [[ "$$REMOTE" == "$$BASE" ]]; then \
		N=$$(git -C $(REPO_DIR) rev-list --count @{u}..@); \
		echo "  [✓] Local is ahead of origin by $$N commit(s) — ready to push"; \
	else \
		echo "  [✗] Local and origin have diverged — resolve before pushing."; \
		exit 1; \
	fi
	@echo
	@echo "── Preflight: unpushed tags ────────────────────────"
	@LOCAL_TAGS=$$(git -C $(REPO_DIR) tag -l 'v*' | sort); \
	REMOTE_TAGS=$$(git -C $(REPO_DIR) ls-remote --tags origin 'v*' 2>/dev/null | awk '{print $$2}' | sed 's|refs/tags/||; s|\^{}||' | sort -u); \
	UNPUSHED=$$(comm -23 <(echo "$$LOCAL_TAGS") <(echo "$$REMOTE_TAGS")); \
	if [[ -z "$$UNPUSHED" ]]; then \
		echo "  [✓] All local tags are on origin"; \
	else \
		echo "  [!] Unpushed local tags (push with 'git push --tags origin'):"; \
		echo "$$UNPUSHED" | sed 's/^/        /'; \
	fi
	@echo
	@echo "  [✓] Preflight complete."
	@echo

.PHONY: help
help: ## Show this help
	@echo
	@echo "Usage: make <target>"
	@echo
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "Variables:"
	@echo "  PROJECTS_ROOT      Root directory scanned by setup-projects (default: ~/Projects)"
	@echo "  PATH               Project path for setup-project target"
	@echo "  DEV_AI_TOOLS_BIN   Where install-cli symlinks the wrapper (default: ~/.local/bin)"
	@echo "  VERSION            Git tag to check out for 'make update' (default: latest on main)"
	@echo
