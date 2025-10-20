#!/usr/bin/env bash
# Install recon/offsec tools into ~/tools (no Burp Suite, no Postman).
# Target: Debian/Ubuntu/Kali/Parrot. Requires sudo for system deps.
# Idempotent-ish: safe to re-run. Exits on first error.
set -euo pipefail

TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
BIN_DIR="$TOOLS_DIR/bin"

msg() { printf "\n[%s] %s\n" "$(date +'%H:%M:%S')" "$*"; }
need_sudo() { [ "${EUID:-$(id -u)}" -eq 0 ] || command -v sudo >/dev/null 2>&1; }
die() { echo "ERROR: $*" >&2; exit 1; }

ensure_dirs() {
  mkdir -p "$BIN_DIR" "$TOOLS_DIR/src"
}

ensure_basic_deps() {
  msg "Installing system dependencies via apt…"
  need_sudo || die "sudo not available; run as root or install sudo."
  sudo apt-get update -y
  sudo apt-get install -y \
    git curl wget unzip ca-certificates build-essential pkg-config \
    python3 python3-pip jq xz-utils software-properties-common
}

ensure_snap() {
  if ! command -v snap >/dev/null 2>&1; then
    msg "snapd not found; installing (optional: for amass snap) …"
    sudo apt-get install -y snapd
    sudo systemctl enable --now snapd.socket || true
    sudo ln -sf /var/lib/snapd/snap /snap || true
  fi
}

ensure_node() {
  if ! command -v npm >/dev/null 2>&1; then
    msg "npm not found; installing Node.js + npm from apt (for Wappalyzer CLI)…"
    sudo apt-get install -y nodejs npm
  fi
}

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    msg "Go found: $(go version)"
    return
  fi

  msg "Go not found; installing latest stable to /usr/local…"
  LATEST="$(curl -fsSL https://go.dev/VERSION?m=text | head -n1)"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) GOARCH=amd64 ;;
    aarch64|arm64) GOARCH=arm64 ;;
    *) die "Unsupported architecture for this script: $ARCH" ;;
  esac
  TARBALL="${LATEST}.linux-${GOARCH}.tar.gz"
  curl -fsSL "https://go.dev/dl/${TARBALL}" -o "/tmp/${TARBALL}"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "/tmp/${TARBALL}"
  rm -f "/tmp/${TARBALL}"
  if ! grep -q '/usr/local/go/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="/usr/local/go/bin:$PATH"' >> "$HOME/.bashrc"
  fi
  export PATH="/usr/local/go/bin:$PATH"
  msg "Installed $(go version)"
}

go_get() {
  local pkg="$1"
  GOBIN="$BIN_DIR" GO111MODULE=on go install -v "$pkg"
}

install_go_tools() {
  msg "Installing Go-based tools into $BIN_DIR …"
  go_get github.com/ffuf/ffuf/v2@latest
  go_get github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
  go_get github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
  go_get github.com/projectdiscovery/httpx/cmd/httpx@latest
  go_get github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
  go_get github.com/tomnomnom/assetfinder@latest
  go_get github.com/tomnomnom/anew@latest
  go_get github.com/tomnomnom/waybackurls@latest
  # Amass fallback via go if snap not used
  if ! command -v amass >/dev/null 2>&1; then
    go_get github.com/owasp-amass/amass/v4/...@latest || true
  fi
}

install_python_tools() {
  msg "Installing Python-based tools (Shodan CLI)…"
  python3 -m pip install --upgrade pip
  python3 -m pip install --user shodan
  if command -v shodan >/dev/null 2>&1; then
    ln -sf "$(command -v shodan)" "$BIN_DIR/shodan"
  else
    USR_BIN="$(python3 -m site --user-base)/bin/shodan"
    [ -x "$USR_BIN" ] && ln -sf "$USR_BIN" "$BIN_DIR/shodan" || true
  fi
}

install_node_tools() {
  msg "Installing Node-based tools (Wappalyzer CLI)…"
  sudo npm -g install wappalyzer || sudo npm -g install wappalyzer-cli || true
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

install_amass_snap_optional() {
  # Only install amass via snap if snap is available and amass not already present
  if command -v snap >/dev/null 2>&1 && ! command -v amass >/dev/null 2>&1; then
    msg "Installing amass via snap (optional) …"
    sudo snap install amass || true
  fi
}

wire_path() {
  if ! grep -q "$BIN_DIR" "$HOME/.bashrc" 2>/dev/null; then
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
  fi
  export PATH="$BIN_DIR:$PATH"
}

summarize() {
  msg "Done. Binaries in: $BIN_DIR"
  msg "You may need to 'source ~/.bashrc' or open a new shell for PATH changes."
  msg "Quick sanity check (versions):"
  for t in ffuf subfinder nuclei httpx naabu waybackurls assetfinder anew amass shodan; do
    command -v "$t" >/dev/null 2>&1 && printf "  - %-12s -> %s\n" "$t" "$(command -v "$t")" || printf "  - %-12s -> MISSING\n" "$t"
  done
  printf "\nWordlists: %s/src/OneListForAll\n" "$TOOLS_DIR"
}

main() {
  msg "Starting tool bootstrap into $TOOLS_DIR (no Burp, no Postman)"
  ensure_dirs
  ensure_basic_deps
  ensure_go
  wire_path
  install_go_tools
  install_python_tools
  ensure_node
  install_node_tools
  install_wordlists_and_aux
  ensure_snap
  install_amass_snap_optional
  summarize
}

main "$@"

