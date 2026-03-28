SHELL := /usr/bin/env bash
REPO_DIR := $(shell pwd)
PROJECTS_ROOT ?= $(HOME)/Projects

.DEFAULT_GOAL := help

# ─── Primary targets ──────────────────────────────────────────────────────────

.PHONY: setup
setup: ## Bootstrap Serena on this machine (installs uv, wires all clients, prompts for language servers)
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

# ─── Maintenance ──────────────────────────────────────────────────────────────

.PHONY: update
update: ## Pull latest config changes and re-run setup
	@git -C $(REPO_DIR) pull --ff-only
	@$(MAKE) setup

.PHONY: check
check: ## Verify Serena is wired up correctly across all clients
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
	fi; \
	if [[ -n "$$CLAUDE_DESKTOP_CONFIG" ]] && [[ -d "/Applications/Claude.app" ]]; then \
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
	@echo "── VS Code (user settings.json) ────────────────────"
	@VSCODE_SETTINGS=""; \
	if [[ "$$(uname)" == "Darwin" ]]; then \
		VSCODE_SETTINGS="$(HOME)/Library/Application Support/Code/User/settings.json"; \
	else \
		VSCODE_SETTINGS="$(HOME)/.config/Code/User/settings.json"; \
	fi; \
	if [[ -f "$$VSCODE_SETTINGS" ]] && python3 -c \
		"import json; d=json.load(open('$$VSCODE_SETTINGS')); exit(0 if 'serena' in d.get('mcp',{}).get('servers',{}) else 1)" 2>/dev/null; then \
		echo "  [✓] serena present in VS Code settings.json"; \
	elif [[ -f "$$VSCODE_SETTINGS" ]]; then \
		echo "  [✗] serena missing from VS Code settings — run: make setup"; \
	else \
		echo "  [!] VS Code settings.json not found"; \
	fi
	@echo

.PHONY: cache-clean
cache-clean: ## Force uvx to re-download Serena on next use
	@uvx cache clean
	@echo "  [✓] uvx cache cleared — Serena will re-download on next use"

.PHONY: help
help: ## Show this help
	@echo
	@echo "Usage: make <target>"
	@echo
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "Variables:"
	@echo "  PROJECTS_ROOT   Root directory scanned by setup-projects (default: ~/Projects)"
	@echo "  PATH            Project path for setup-project target"
	@echo
