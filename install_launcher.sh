#!/bin/bash
# PicoClaw Launcher Install Script

set -e

REPO="muava12/picoclaw-fork"
BINARY_NAME="picoclaw-launcher"
INSTALL_DIR="/usr/local/bin"

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo"
  exit 1
fi

echo "Detecting OS and Architecture..."
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

if [ "$OS" = "darwin" ]; then
    OS="macos"
fi

ASSET_NAME="${BINARY_NAME}-${OS}-${ARCH}"
if [ "$OS" = "windows" ]; then
    ASSET_NAME="${ASSET_NAME}.exe"
fi

echo "Fetching latest release data for picoclaw-launcher..."
API_URL="https://api.github.com/repos/$REPO/releases/tags/pilaunch-v0.0.1"

DOWNLOAD_URL=$(curl -s "$API_URL" | grep -o 'https://github.com/[^"]*' | grep "download/pilaunch-v0.0.1/$ASSET_NAME")

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Error: Could not find download URL for $ASSET_NAME"
  exit 1
fi

echo "Downloading $ASSET_NAME..."
curl -L -o "$BINARY_NAME" "$DOWNLOAD_URL"

echo "Installing $BINARY_NAME to $INSTALL_DIR..."
chmod +x "$BINARY_NAME"
mv "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"

echo "Installation complete!"
echo "Run it by typing: $BINARY_NAME"
