#!/bin/bash
set -e

INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="picoclaw"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

print_step() {
    echo -e "${BLUE}==>${RESET} ${BOLD}$1${RESET}"
}

print_success() {
    echo -e "${GREEN}✓${RESET} $1"
}

print_error() {
    echo -e "${RED}✗${RESET} $1"
}

print_warn() {
    echo -e "${YELLOW}!${RESET} $1"
}

get_latest_version() {
    local repo="$1"
    # Mengambil daftar rilis dari API, mencari tag_name yang TIDAK mengandung "piman", 
    # mengambil yang pertama, lalu mengekstrak versinya.
    curl -s "https://api.github.com/repos/${repo}/releases" | \
        grep '"tag_name":' | grep -v 'piman' | head -n 1 | sed -E 's/.*"tag_name": "([^"]+)".*/\1/'
}

# Detect system architecture
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*|armhf)  echo "armv7" ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

echo ""
echo -e "${BOLD}  PicoClaw Installer${RESET}"
echo "  ─────────────────────"
echo ""

# Detect architecture
ARCH=$(detect_arch)
print_success "Detected architecture: $ARCH"

# Ask user which version to install
echo ""
echo -e "${BOLD}Select version to install:${RESET}"
echo "  1) Original (sipeed/picoclaw)"
echo "  2) Fork (muava12/picoclaw-fork)"
echo ""
read -p "Choose [1-2] (default: 2): " version_choice < /dev/tty

if [[ "$version_choice" == "1" ]]; then
    REPO="sipeed/picoclaw"
    echo ""
    print_step "Selected: ${BOLD}Original version${RESET}"
else
    REPO="muava12/picoclaw-fork"
    echo ""
    print_step "Selected: ${BOLD}Fork version${RESET}"
fi

URL="https://github.com/${REPO}/releases/latest/download/picoclaw_Linux_${ARCH}.tar.gz"

print_step "Checking for latest version..."
VERSION=$(get_latest_version "$REPO")
if [ -n "$VERSION" ]; then
    echo "    Latest: $VERSION"
else
    echo "    (unable to fetch version)"
fi

# Check if already installed
if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
    INSTALLED_VERSION=$("$INSTALL_DIR/$BINARY_NAME" --version 2>/dev/null | sed -n 's/.*\(v\?[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*[^ ]*\).*/\1/p' | head -1)
    # Strip 'v' prefix if present
    INSTALLED_VERSION=${INSTALLED_VERSION#v}
    if [ -n "$INSTALLED_VERSION" ]; then
        print_success "Already installed: $BINARY_NAME v$INSTALLED_VERSION"
        
        if [ -n "$VERSION" ]; then
            # Strip 'v' prefix for comparison
            VERSION_NUM=${VERSION#v}
            if [ "$INSTALLED_VERSION" = "$VERSION_NUM" ]; then
                echo ""
                print_success "You already have the latest version!"
                echo ""
                echo -e "Run: ${BOLD}picoclaw onboard${RESET} to get started"
                echo ""
                exit 0
            else
                echo ""
                echo -e "${BLUE}!${RESET} Update available: v$INSTALLED_VERSION → $VERSION"
                echo ""
                if [ -t 0 ]; then
                    read -p "Do you want to update? [y/N] " -n 1 -r
                else
                    read -p "Do you want to update? [y/N] " -n 1 -r < /dev/tty
                fi
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    print_step "Update cancelled"
                    echo ""
                    exit 0
                fi
            fi
        fi
    fi
fi

mkdir -p "$INSTALL_DIR"
print_success "Install directory: $INSTALL_DIR"

print_step "Downloading $BINARY_NAME ($ARCH)..."
cd /tmp
if command -v pv &> /dev/null; then
    curl -L "$URL" | pv -b -p -e -r > picoclaw.tar.gz
else
    curl -L --progress-bar "$URL" -o picoclaw.tar.gz
fi

print_step "Extracting..."
tar -xzf picoclaw.tar.gz "$BINARY_NAME"
chmod +x "$BINARY_NAME"

print_step "Stopping running PicoClaw instances..."
# Stop systemd service if active
if systemctl is-active --quiet picoclaw 2>/dev/null; then
    sudo systemctl stop picoclaw 2>/dev/null && print_success "Stopped systemd service" || print_warn "Failed to stop systemd service"
elif systemctl is-active --quiet picoclaw-manager 2>/dev/null; then
    # Stop via manager API first (graceful)
    MANAGER_PORT=$(ss -tlnp 2>/dev/null | grep picoclaw_manager | grep -oP ':\K[0-9]+' | head -1)
    if [ -n "$MANAGER_PORT" ]; then
        curl -s -X POST "http://localhost:${MANAGER_PORT}/api/picoclaw/stop" >/dev/null 2>&1 && print_success "Stopped via manager API" || true
    fi
fi
# Kill any remaining picoclaw gateway processes
if pgrep -f "picoclaw gateway" >/dev/null 2>&1; then
    pkill -f "picoclaw gateway" 2>/dev/null && print_success "Stopped picoclaw gateway process" || true
    sleep 1
fi

print_step "Installing..."
mv -f "$BINARY_NAME" "$INSTALL_DIR/"
rm -f picoclaw.tar.gz

print_success "Installed to $INSTALL_DIR/$BINARY_NAME"
print_success "Version: $VERSION"

echo ""
print_step "Optional Components"
echo "  PicoClaw Manager (piman) is a background service and CLI tool"
echo "  that manages the PicoClaw process lifecycle (start, stop, logs)"
echo "  and provides a memory-efficient HTTP API for integrations."
echo ""
if [ -t 0 ]; then
    read -p "Do you want to install PicoClaw Manager (piman)? [y/N] " -n 1 -r
else
    read -p "Do you want to install PicoClaw Manager (piman)? [y/N] " -n 1 -r < /dev/tty
fi
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "Installing PicoClaw Manager..."
    if command -v curl &> /dev/null; then
        curl -fsSL https://raw.githubusercontent.com/${REPO}/main/setup_picoclaw_manager.sh | bash -s install
    else
        wget -qO- https://raw.githubusercontent.com/${REPO}/main/setup_picoclaw_manager.sh | bash -s install
    fi
else
    print_step "Skipping Manager installation"
fi

echo ""
PATH_CHANGED=false
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    print_step "Fixing PATH..."
    if ! grep -q "$INSTALL_DIR" ~/.bashrc 2>/dev/null; then
        echo '' >> ~/.bashrc
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        print_success "Added to ~/.bashrc"
        PATH_CHANGED=true
    else
        print_success "Already configured in ~/.bashrc"
    fi
    # Also add to ~/.zshrc if zsh is available
    if [ -f "$HOME/.zshrc" ] && ! grep -q "$INSTALL_DIR" ~/.zshrc 2>/dev/null; then
        echo '' >> ~/.zshrc
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
        print_success "Added to ~/.zshrc"
        PATH_CHANGED=true
    fi
    export PATH="$INSTALL_DIR:$PATH"
    print_success "PATH updated for current session"
else
    print_success "Already in PATH"
fi

echo ""
if [ "$PATH_CHANGED" = true ]; then
    print_warn "Run this first to activate PATH:"
    echo ""
    echo -e "  ${BOLD}source ~/.bashrc${RESET}"
    echo ""
fi
echo -e "Then run: ${BOLD}picoclaw onboard${RESET} to get started"
echo ""
