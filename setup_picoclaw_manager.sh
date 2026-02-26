#!/bin/bash
# ═══════════════════════════════════════════════════
#  PicoClaw Manager — Installer & Service Manager
#  Untuk Armbian / Debian / Ubuntu
# ═══════════════════════════════════════════════════
set -e

SERVICE_NAME="picoclaw-manager"
INSTALL_DIR="/opt/picoclaw"
BINARY_NAME="picoclaw-manager"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
PICOCLAW_BIN="$HOME/.local/bin/picoclaw"
RUN_USER="$(whoami)"
REPO="muava12/picoclaw-fork"

# ── Warna ─────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' B='\033[0;34m'
Y='\033[1;33m' C='\033[0;36m' W='\033[1;37m' X='\033[0m'

banner() {
  echo ""
  echo -e "  ${C}┌──────────────────────────────────────┐${X}"
  echo -e "  ${C}│${W}   🦀 PicoClaw Service Manager       ${C}│${X}"
  echo -e "  ${C}└──────────────────────────────────────┘${X}"
  echo ""
}

info()    { echo -e "  ${B}▸${X} $1"; }
success() { echo -e "  ${G}✓${X} $1"; }
warn()    { echo -e "  ${Y}!${X} $1"; }
err()     { echo -e "  ${R}✗${X} $1"; }

get_latest_manager_version() {
    # Mengambil daftar rilis terbaru, mencari tag yang diawali "piman-", lalu memisahkan versinya.
    curl -s "https://api.github.com/repos/${REPO}/releases" | \
        grep '"tag_name": "piman-' | head -n 1 | sed -E 's/.*"tag_name": "piman-([^"]+)".*/\1/'
}

# ── Install ───────────────────────────────────────
cmd_install() {
  banner
  info "Installing ${SERVICE_NAME}..."
  echo ""

  # Detect architecture
  ARCH=$(uname -m)
  case "$ARCH" in
      x86_64|amd64)  ARCH="amd64" ;;
      aarch64|arm64) ARCH="arm64" ;;
      *)
          err "Unsupported architecture: $ARCH for pre-compiled manager"
          exit 1
          ;;
  esac

  VERSION=$(get_latest_manager_version)
  if [ -z "$VERSION" ]; then
      err "Gagal mendapatkan versi rilis terbaru manager dari $REPO"
      info "Pastikan ada rilis dengan tag berawalan 'piman-'"
      exit 1
  fi

  DL_URL="https://github.com/${REPO}/releases/download/piman-${VERSION}/picoclaw-manager-linux-${ARCH}"

  info "Downloading $BINARY_NAME (${VERSION}) dari GitHub Releases..."
  sudo mkdir -p "$INSTALL_DIR"
  sudo curl -fsSL -o "${INSTALL_DIR}/${BINARY_NAME}" "$DL_URL" || {
      err "Gagal mendownload binary dari $DL_URL"
      exit 1
  }
  sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
  success "Binary downloaded"

  # Buat symlink piman
  sudo ln -sf "${INSTALL_DIR}/${BINARY_NAME}" /usr/local/bin/piman
  success "CLI terhubung: jalankan 'piman' dari mana saja"

  # Buat systemd service
  info "Creating systemd service..."
  sudo tee "$SERVICE_FILE" > /dev/null << UNIT
[Unit]
Description=PicoClaw Manager — Process Lifecycle Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${BINARY_NAME} server --auto-start --picoclaw-bin ${PICOCLAW_BIN}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT
  success "Service file created: ${SERVICE_FILE}"

  # Reload & enable
  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"
  success "Service enabled (auto-start on boot)"

  # Start (or restart if already running)
  sudo systemctl restart "$SERVICE_NAME"
  success "Service started"

  echo ""
  info "Gunakan CLI piman: ${W}piman status${X}"
  info "Lihat log CLI:     ${W}piman logs${X}"
  echo ""
}

# ── Uninstall ─────────────────────────────────────
cmd_uninstall() {
  banner
  warn "Uninstalling ${SERVICE_NAME}..."
  echo ""

  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    sudo systemctl stop "$SERVICE_NAME"
    success "Service stopped"
  fi

  if [ -f "$SERVICE_FILE" ]; then
    sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
    success "Service file removed"
  fi

  if [ -d "$INSTALL_DIR" ]; then
    read -p "  Hapus ${INSTALL_DIR}? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      sudo rm -rf "$INSTALL_DIR"
      success "Install directory removed"
    fi
  fi

  sudo rm -f /usr/local/bin/piman

  success "Uninstall selesai"
  echo ""
}

# ── Update ────────────────────────────────────────
cmd_update() {
  banner
  info "Updating ${BINARY_NAME}..."

  ARCH=$(uname -m)
  case "$ARCH" in
      x86_64|amd64)  ARCH="amd64" ;;
      aarch64|arm64) ARCH="arm64" ;;
  esac
  VERSION=$(get_latest_manager_version)
  if [ -z "$VERSION" ]; then
      err "Gagal menemukan rilis baru."
      exit 1
  fi
  DL_URL="https://github.com/${REPO}/releases/download/piman-${VERSION}/picoclaw-manager-linux-${ARCH}"

  sudo curl -fsSL -o "${INSTALL_DIR}/${BINARY_NAME}" "$DL_URL"
  success "Binary manager updated"

  sudo systemctl restart "$SERVICE_NAME"
  success "Service restarted"
  echo ""
}

# ── Service Commands ──────────────────────────────
cmd_start()   { sudo systemctl start "$SERVICE_NAME"   && success "Started";   }
cmd_stop()    { sudo systemctl stop "$SERVICE_NAME"     && success "Stopped";   }
cmd_restart() { sudo systemctl restart "$SERVICE_NAME"  && success "Restarted"; }

cmd_status() {
  banner
  echo -e "  ${W}Systemd Status:${X}"
  echo ""
  sudo systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null || warn "Service not found"
  echo ""
  
  if command -v piman &> /dev/null; then
    echo -e "  ${W}API Status via piman:${X}"
    echo ""
    piman status
  fi
}

cmd_logs() {
  journalctl -u "$SERVICE_NAME" -f --no-pager
}

cmd_logs_history() {
  journalctl -u "$SERVICE_NAME" --no-pager -n "${1:-50}"
}

# ── Usage ─────────────────────────────────────────
cmd_help() {
  banner
  echo -e "  ${W}Usage:${X} $0 <command>"
  echo ""
  echo -e "  ${C}Setup${X}"
  echo "    install       Install & enable service"
  echo "    uninstall     Remove service & files"
  echo "    update        Update script & restart"
  echo ""
  echo -e "  ${C}Service${X}"
  echo "    start         Start the API server"
  echo "    stop          Stop the API server"
  echo "    restart       Restart the API server"
  echo "    status        Show status & health check"
  echo ""
  echo -e "  ${C}Logs${X}"
  echo "    logs          Follow live logs"
  echo "    logs-history  Show last 50 log lines"
  echo ""
}

# ── Dispatch ──────────────────────────────────────
case "${1:-help}" in
  install)      cmd_install      ;;
  uninstall)    cmd_uninstall    ;;
  update)       cmd_update       ;;
  start)        cmd_start        ;;
  stop)         cmd_stop         ;;
  restart)      cmd_restart      ;;
  status)       cmd_status       ;;
  logs)         cmd_logs         ;;
  logs-history) cmd_logs_history "$2" ;;
  help|--help|-h) cmd_help       ;;
  *)
    err "Unknown command: $1"
    cmd_help
    exit 1
    ;;
esac
