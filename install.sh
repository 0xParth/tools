#!/usr/bin/env bash
# macOS Recon Tool Installer
# Installs recon/offsec tools into ~/tools (no BurpSuite, no Postman)
# Requires: Homebrew (installs automatically if missing)

set -euo pipefail

TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
BIN_DIR="$TOOLS_DIR/bin"

msg() { printf "\n[%s] %s\n" "$(date +'%H:%M:%S')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

ensure_dirs() {
  mkdir -p "$BIN_DIR" "$TOOLS_DIR/src"
}

ensure_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    msg "Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  else
    msg "Updating Homebrew..."
    brew update
  fi
}

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    msg "Go found: $(go version)"
    return
  fi

  msg "Installing Go via Homebrew..."
  brew install go
  if ! grep -q '/usr/local/go/bin' "$HOME/.bashrc" 2>/dev/null && ! grep -q '/opt/homebrew/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$PATH:/usr/local/go/bin:/opt/homebrew/bin"' >> "$HOME/.bashrc"
  fi
  export PATH="$PATH:/usr/local/go/bin:/opt/homebrew/bin"
}

ensure_node() {
  if ! command -v npm >/dev/null 2>&1; then
    msg "Installing Node.js + npm..."
    brew install node
  fi
}

ensure_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    msg "Installing Python3..."
    brew install python
  fi
  python3 -m pip install --upgrade pip
}

go_get() {
  local pkg="$1"
  GOBIN="$BIN_DIR" GO111MODULE=on go install -v "$pkg"
}

install_go_tools() {
  msg "Installing Go-based tools into $BIN_DIR ..."
  go_get github.com/ffuf/ffuf/v2@latest
  go_get github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
  go_get github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
  go_get github.com/projectdiscovery/httpx/cmd/httpx@latest
  go_get github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
  go_get github.com/tomnomnom/assetfinder@latest
  go_get github.com/tomnomnom/anew@latest
  go_get github.com/tomnomnom/waybackurls@latest
  go_get github.com/owasp-amass/amass/v4/...@latest
}

install_python_tools() {
  msg "Installing Python-based tools (Shodan CLI)…"
  python3 -m pip install --user shodan
  SHODAN_PATH="$(python3 -m site --user-base)/bin/shodan"
  [ -x "$SHODAN_PATH" ] && ln -sf "$SHODAN_PATH" "$BIN_DIR/shodan" || true
}

install_node_tools() {
  msg "Installing Node-based tools (Wappalyzer CLI)…"
  npm install -g wappalyzer || npm install -g wappalyzer-cli || true
  for b in wappalyzer wappalyzer-cli; do
    if command -v "$b" >/dev/null 2>&1; then
      ln -sf "$(command -v "$b")" "$BIN_DIR/$b"
    fi
  done
}

install_wordlists_and_aux() {
  msg "Fetching OneListForAll wordlists…"
  if [ ! -d "$TOOLS_DIR/src/OneListForAll" ]; then
    git clone --depth=1 https://github.com/six2dez/OneListForAll "$TOOLS_DIR/src/OneListForAll" || \
    git clone --depth=1 https://github.com/danielmiessler/OneListForAll "$TOOLS_DIR/src/OneListForAll" || true
  else
    (cd "$TOOLS_DIR/src/OneListForAll" && git pull --ff-only || true)
  fi
}

wire_path() {
  if ! grep -q "$BIN_DIR" "$HOME/.bashrc" 2>/dev/null && ! grep -q "$BIN_DIR" "$HOME/.zshrc" 2>/dev/null; then
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.zshrc"
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
  fi
  export PATH="$BIN_DIR:$PATH"
}

summarize() {
  msg "Done. Binaries in: $BIN_DIR"
  msg "You may need to 'source ~/.zshrc' or open a new terminal."
  msg "Quick sanity check (versions):"
  for t in ffuf subfinder nuclei httpx naabu waybackurls assetfinder anew amass shodan; do
    command -v "$t" >/dev/null 2>&1 && printf "  - %-12s -> %s\n" "$t" "$(command -v "$t")" || printf "  - %-12s -> MISSING\n" "$t"
  done
  printf "\nWordlists: %s/src/OneListForAll\n" "$TOOLS_DIR"
}

main() {
  msg "Starting macOS recon tool bootstrap (no Burp, no Postman)"
  ensure_dirs
  ensure_homebrew
  ensure_go
  ensure_node
  ensure_python
  wire_path
  install_go_tools
  install_python_tools
  install_node_tools
  install_wordlists_and_aux
  summarize
}

main "$@"

