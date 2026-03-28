#!/usr/bin/env bash
# install-language-servers.sh
# Scans project repos, detects languages in use, and installs the
# corresponding Serena language servers.
#
# Usage: install-language-servers.sh [projects-root]
#   projects-root  defaults to ~/Projects

set -euo pipefail

PROJECTS_ROOT="${1:-$HOME/Projects}"

ok()      { echo "  [✓] $*"; }
skip()    { echo "  [–] $*"; }
warn()    { echo "  [!] $*"; }
info()    { echo "  [·] $*"; }
section() { echo; echo "── $* ──────────────────────────────────────────────"; }

detect_os() {
  if [[ "$(uname)" == "Darwin" ]]; then echo "macos"
  elif grep -qi microsoft /proc/version 2>/dev/null; then echo "wsl"
  else echo "linux"; fi
}
OS="$(detect_os)"
cmd_exists() { command -v "$1" &>/dev/null; }

# ── Language definitions ───────────────────────────────────────────────────────
# KEY | LABEL | DETECT GLOBS | CHECK CMD | PREREQ | INSTALL MAC | INSTALL LINUX | NOTES
LANG_DEFS=(
  "go        | Go (gopls)                  | go.mod *.go                         | gopls                                     | go      | go install golang.org/x/tools/gopls@latest                                                          | go install golang.org/x/tools/gopls@latest                                                            | Requires Go SDK"
  "rust       | Rust (rust-analyzer)        | Cargo.toml *.rs                     | rust-analyzer                             | rustup  | rustup component add rust-analyzer                                                                  | rustup component add rust-analyzer                                                                    | Requires rustup"
  "python     | Python (pyright)            | *.py pyproject.toml requirements.txt | pyright                                  | uv      | uv tool install pyright                                                                             | uv tool install pyright                                                                               | Optional upgrade; pylsp is bundled"
  "typescript | TypeScript / JavaScript     | tsconfig.json *.ts                  | bundled                                   |         |                                                                                                     |                                                                                                       | Bundled with Serena"
  "ruby       | Ruby (ruby-lsp)             | Gemfile *.rb                        | ruby-lsp                                  | ruby    | gem install ruby-lsp                                                                                | gem install ruby-lsp                                                                                  | Requires Ruby"
  "cpp        | C / C++ (clangd)            | CMakeLists.txt *.cpp *.cc *.c *.h   | clangd                                    |         | brew install llvm                                                                                   | apt-get install -y clangd                                                                             | Add compile_commands.json to project root"
  "csharp     | C# / F# (Roslyn / .NET)     | *.csproj *.sln *.cs *.fsproj *.fs   | dotnet                                    |         | brew install dotnet                                                                                 | wget https://dot.net/v1/dotnet-install.sh -O - | bash                                                  | Requires .NET v10+"
  "java       | Java                        | pom.xml build.gradle *.java         | bundled                                   |         |                                                                                                     |                                                                                                       | Bundled with Serena"
  "scala      | Scala (Metals)              | build.sbt *.scala                   | metals                                    |         | brew install coursier && cs install metals                                                          | curl -fLo cs https://git.io/coursier-cli-linux && chmod +x cs && ./cs install metals                 | Requires coursier"
  "kotlin     | Kotlin (kotlin-lsp)         | *.kt *.kts                          | kotlin                                    | kotlin  | brew install kotlin                                                                                 | apt-get install -y kotlin                                                                             | kotlin-lsp is pre-alpha"
  "haskell    | Haskell (HLS)               | stack.yaml *.cabal *.hs             | haskell-language-server-wrapper           | ghcup   | ghcup install hls                                                                                   | ghcup install hls                                                                                     | Requires ghcup"
  "elixir     | Elixir (auto-downloads)     | mix.exs *.ex *.exs                  | elixir                                    | elixir  | auto                                                                                                | auto                                                                                                  | LS auto-downloads on first project activation"
  "erlang     | Erlang (erlang_ls)          | rebar.config *.erl                  | erlang_ls                                 |         | brew install erlang-ls                                                                              | apt-get install -y erlang-ls                                                                          | Requires Erlang/OTP"
  "ocaml      | OCaml (ocaml-lsp-server)    | dune-project *.ml *.mli             | ocamllsp                                  | opam    | opam install ocaml-lsp-server                                                                       | opam install ocaml-lsp-server                                                                         | Requires opam"
  "r          | R (languageserver)          | DESCRIPTION *.R *.r                 | Rscript                                   | Rscript | Rscript -e 'install.packages(\"languageserver\",repos=\"https://cloud.r-project.org\")'             | Rscript -e 'install.packages(\"languageserver\",repos=\"https://cloud.r-project.org\")'               | Requires R"
  "fortran    | Fortran (fortls)            | *.f90 *.f95 *.f03 *.f08             | fortls                                    | uv      | uv tool install fortls                                                                              | uv tool install fortls                                                                                |"
  "nix        | Nix (nixd)                  | flake.nix *.nix                     | nixd                                      |         | nix-env -iA nixpkgs.nixd                                                                            | nix-env -iA nixpkgs.nixd                                                                              | Requires Nix"
  "zig        | Zig (ZLS)                   | *.zig build.zig                     | zls                                       |         | brew install zls                                                                                    | snap install zls --classic                                                                            | ZLS version must match Zig version"
  "php        | PHP (Intelephense)          | composer.json *.php                 | php                                       |         | bundled                                                                                             | bundled                                                                                               | Bundled; set INTELEPHENSE_LICENSE_KEY for premium"
  "ansible    | Ansible                     | playbooks tasks roles site.yml      | ansible                                   | npm     | npm install -g @ansible/ansible-language-server                                                     | npm install -g @ansible/ansible-language-server                                                       | Requires Node.js"
  "vue        | Vue (volar)                 | *.vue vite.config.ts vite.config.js | bundled                                   | npm     | npm install -g @vue/language-server                                                                 | npm install -g @vue/language-server                                                                   | Requires Node.js v18+"
  "solidity   | Solidity                    | *.sol foundry.toml hardhat.config.js | bundled                                  | npm     | npm install -g @nomicfoundation/solidity-language-server                                            | npm install -g @nomicfoundation/solidity-language-server                                              | Requires Node.js"
  "elm        | Elm                         | elm.json *.elm                      | elm                                       | npm     | npm install -g elm                                                                                  | npm install -g elm                                                                                    | Requires Node.js"
  "lua        | Lua                         | *.lua                               | bundled                                   |         |                                                                                                     |                                                                                                       | Bundled with Serena"
  "bash       | Bash / Shell                | *.sh                                | bundled                                   |         |                                                                                                     |                                                                                                       | Bundled with Serena"
)

# ── Detect languages ──────────────────────────────────────────────────────────
section "Scanning $PROJECTS_ROOT"

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; echo "$s"; }

detect_language() {
  local globs="$1"
  for glob in $globs; do
    find "$PROJECTS_ROOT" -maxdepth 5 \
      \( -path "*/node_modules/*" -o -path "*/.git/*" -o -path "*/.venv/*" \) -prune \
      -o -name "$glob" -print -quit 2>/dev/null | grep -q . && return 0
  done
  return 1
}

# Build list of detected entries needing action
declare -a TO_INSTALL_LABELS TO_INSTALL_INDICES
declare -a BUNDLED_LABELS MISSING_PREREQ_LABELS ALREADY_LABELS

for i in "${!LANG_DEFS[@]}"; do
  def="${LANG_DEFS[$i]}"
  IFS='|' read -r key label globs check prereq mac linux notes <<< "$def"
  key="$(trim "$key")"; key="${key// /}"
  label="$(trim "$label")"
  globs="$(trim "$globs")"
  check="$(trim "$check")"
  prereq="$(trim "$prereq")"
  notes="$(trim "$notes")"
  [[ "$OS" == "macos" ]] && install_cmd="$(trim "$mac")" || install_cmd="$(trim "$linux")"

  detect_language "$globs" || continue

  # Bundled / auto
  if [[ "$check" == "bundled" || "$install_cmd" == "bundled" || "$install_cmd" == "auto" || -z "$install_cmd" ]]; then
    BUNDLED_LABELS+=("$label")
    continue
  fi

  # Already installed
  if cmd_exists "$check"; then
    ALREADY_LABELS+=("$label")
    continue
  fi

  # Missing prerequisite
  if [[ -n "$prereq" ]] && ! cmd_exists "$prereq"; then
    MISSING_PREREQ_LABELS+=("$label (needs: $prereq)")
    continue
  fi

  TO_INSTALL_LABELS+=("$label")
  TO_INSTALL_INDICES+=("$i")
done

# ── Report findings ───────────────────────────────────────────────────────────
if [[ ${#ALREADY_LABELS[@]} -gt 0 ]]; then
  for l in "${ALREADY_LABELS[@]}"; do ok "$l — already installed"; done
fi
if [[ ${#BUNDLED_LABELS[@]} -gt 0 ]]; then
  for l in "${BUNDLED_LABELS[@]}"; do skip "$l — bundled with Serena"; done
fi
if [[ ${#MISSING_PREREQ_LABELS[@]} -gt 0 ]]; then
  for l in "${MISSING_PREREQ_LABELS[@]}"; do warn "$l — skipped"; done
fi

if [[ ${#TO_INSTALL_LABELS[@]} -eq 0 ]]; then
  echo
  info "Nothing new to install."
  echo
  exit 0
fi

# ── Confirm ───────────────────────────────────────────────────────────────────
echo
echo "  Detected languages to install language servers for:"
for l in "${TO_INSTALL_LABELS[@]}"; do echo "    • $l"; done
echo
read -r -p "  Install these? [Y/n] " answer
answer="${answer:-Y}"
if [[ ! "$answer" =~ ^[Yy] ]]; then
  info "Skipped."
  echo
  exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────
section "Installing"

installed=0; failed=0

for i in "${!TO_INSTALL_INDICES[@]}"; do
  def="${LANG_DEFS[${TO_INSTALL_INDICES[$i]}]}"
  IFS='|' read -r key label globs check prereq mac linux notes <<< "$def"
  label="$(trim "$label")"
  notes="$(trim "$notes")"
  [[ "$OS" == "macos" ]] && install_cmd="$(trim "$mac")" || install_cmd="$(trim "$linux")"

  info "$label…"
  if eval "$install_cmd" 2>&1 | sed 's/^/    /'; then
    ok "$label — done"
    ((installed++)) || true
  else
    warn "$label — failed"
    [[ -n "$notes" ]] && info "$notes"
    ((failed++)) || true
  fi
done

echo
echo "  Installed: $installed  |  Failed: $failed"
[[ $failed -gt 0 ]] && echo "  Re-run 'make install-lsp' after fixing prerequisites."
[[ $installed -gt 0 ]] && echo "  Restart Claude Code / VS Code / Cursor to activate new language servers."
echo
