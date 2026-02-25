#!/bin/bash
# ═══════════════════════════════════════════════════
#  PicoClaw Binary Updater (for picoclaw-manager)
#  Called by picoclaw_manager.py /api/picoclaw/update
# ═══════════════════════════════════════════════════
set -e

REPO="muava12/picoclaw-fork"
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="picoclaw"

# ── Helpers ───────────────────────────────────────
info()  { echo "[INFO] $1"; }
error() { echo "[ERROR] $1" >&2; }

# ── Detect arch ───────────────────────────────────
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) error "Unsupported architecture: $arch"; exit 1 ;;
    esac
}

# ── Get installed version ─────────────────────────
get_installed_version() {
    if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        "$INSTALL_DIR/$BINARY_NAME" --version 2>/dev/null | \
            sed -n 's/.*\(v\?[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*[^ )]*\).*/\1/p' | \
            head -1 | sed 's/^v//'
    else
        echo "not-installed"
    fi
}

# ── Get latest version from GitHub ────────────────
get_latest_version() {
    curl -sI "https://github.com/${REPO}/releases/latest" 2>/dev/null | \
        grep -i "location:" | sed 's|.*/tag/||' | tr -d '\r\n' | sed 's/^v//'
}

# ── Main ──────────────────────────────────────────
ARCH=$(detect_arch)
INSTALLED=$(get_installed_version)
LATEST_TAG=$(curl -sI "https://github.com/${REPO}/releases/latest" 2>/dev/null | \
    grep -i "location:" | sed 's|.*/tag/||' | tr -d '\r\n')
LATEST=$(echo "$LATEST_TAG" | sed 's/^v//')

if [ -z "$LATEST" ]; then
    error "Failed to fetch latest version from GitHub"
    echo '{"success":false,"message":"Failed to fetch latest version from GitHub","updated":false}'
    exit 1
fi

if [ "$INSTALLED" = "$LATEST" ]; then
    info "Already on latest version $INSTALLED"
    echo "{\"success\":true,\"message\":\"Already on latest version ${INSTALLED}. No action needed.\",\"updated\":false,\"installed_version\":\"${INSTALLED}\"}"
    exit 0
fi

info "Update available: $INSTALLED → $LATEST ($ARCH)"

# Download
URL="https://github.com/${REPO}/releases/latest/download/picoclaw_Linux_${ARCH}.tar.gz"
info "Downloading from $URL..."
curl -fsSL "$URL" -o /tmp/picoclaw_update.tar.gz

# Extract
info "Extracting..."
tar -xzf /tmp/picoclaw_update.tar.gz -C /tmp "$BINARY_NAME"
chmod +x "/tmp/$BINARY_NAME"

# Replace binary
info "Installing to $INSTALL_DIR/$BINARY_NAME..."
mkdir -p "$INSTALL_DIR"
mv -f "/tmp/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
rm -f /tmp/picoclaw_update.tar.gz

# Verify
NEW_VERSION=$(get_installed_version)
info "Update complete: $INSTALLED → $NEW_VERSION"

# Output JSON for manager to parse
echo "{\"success\":true,\"message\":\"Update complete: ${INSTALLED} → ${NEW_VERSION}.\",\"updated\":true,\"previous_version\":\"${INSTALLED}\",\"new_version\":\"${NEW_VERSION}\"}"
