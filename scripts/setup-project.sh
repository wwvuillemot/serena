#!/usr/bin/env bash
# setup-project.sh — Add a .serena/project.yml to a project directory.
# Usage: setup-project.sh [<project-path>]  (defaults to current directory)
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"   # resolve to absolute path
SERENA_DIR="$PROJECT_DIR/.serena"
PROJECT_YML="$SERENA_DIR/project.yml"

echo "Setting up Serena for: $PROJECT_DIR"

if [[ -f "$PROJECT_YML" ]]; then
  echo "  → .serena/project.yml already exists, skipping."
  exit 0
fi

mkdir -p "$SERENA_DIR/memories"

cat > "$PROJECT_YML" <<EOF
# Serena project configuration for: $(basename "$PROJECT_DIR")
# See: https://oraios.github.io/serena/02-usage/050_configuration.html

# Project-level overrides (all fields are optional — global config applies otherwise)

# Uncomment to override language backend for this project:
# language_backend: language_servers

# Project-specific ignore rules (merged with global_ignore_rules)
# ignore_rules:
#   - "tests/fixtures/**"

# Uncomment to disable onboarding for this project:
# auto_onboarding: false
EOF

echo "  → Created $PROJECT_YML"

# Optionally add .serena to .gitignore (keeps caches/memories local)
GITIGNORE="$PROJECT_DIR/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  if ! grep -q "^\.serena/cache" "$GITIGNORE" 2>/dev/null; then
    printf '\n# Serena caches and logs (memories are intentionally kept)\n.serena/cache/\n.serena/*.log\n' >> "$GITIGNORE"
    echo "  → Appended .serena/cache/ to .gitignore"
  fi
else
  printf '# Serena caches and logs\n.serena/cache/\n.serena/*.log\n' > "$GITIGNORE"
  echo "  → Created .gitignore with .serena/cache/ entry"
fi

echo "Done: $PROJECT_DIR"
