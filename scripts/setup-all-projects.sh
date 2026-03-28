#!/usr/bin/env bash
# setup-all-projects.sh — Run setup-project.sh for every subdirectory of ~/Projects.
# Usage: setup-all-projects.sh [<root-dir>]  (defaults to ~/Projects)
set -euo pipefail

PROJECTS_ROOT="${1:-$HOME/Projects}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-project.sh"

if [[ ! -d "$PROJECTS_ROOT" ]]; then
  echo "Error: $PROJECTS_ROOT does not exist."
  exit 1
fi

echo "Scanning $PROJECTS_ROOT for project directories..."
echo

count=0
skipped=0

while IFS= read -r -d '' dir; do
  # Skip the serena-setup repo itself and hidden dirs
  basename_dir="$(basename "$dir")"
  if [[ "$basename_dir" == serena || "$basename_dir" == .* ]]; then
    continue
  fi

  # Only treat it as a project if it has a git repo or common project markers
  if [[ -d "$dir/.git" || -f "$dir/package.json" || -f "$dir/pyproject.toml" || \
        -f "$dir/Cargo.toml" || -f "$dir/go.mod" || -f "$dir/pom.xml" || \
        -f "$dir/build.gradle" || -f "$dir/Makefile" ]]; then
    bash "$SETUP_SCRIPT" "$dir"
    ((count++)) || true
  else
    echo "  Skipping (no project markers): $dir"
    ((skipped++)) || true
  fi
done < <(find "$PROJECTS_ROOT" -mindepth 1 -maxdepth 2 -type d -print0 | sort -z)

echo
echo "Done. Configured $count project(s), skipped $skipped."
