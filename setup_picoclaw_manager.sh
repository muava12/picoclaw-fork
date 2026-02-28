#!/bin/bash
# ═══════════════════════════════════════════════════
#  PicoClaw Manager — Interactive Installer
#  Optimized for Armbian / Debian / Ubuntu
# ═══════════════════════════════════════════════════
set -e

# Resolve current user even if run with sudo
REAL_USER=${SUDO_USER:-$(whoami)}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

SERVICE_NAME="picoclaw-manager"
DEFAULT_INSTALL_DIR="/opt/picoclaw"
DEFAULT_BINARY_NAME="picoclaw-manager"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
REPO="muava12/picoclaw-fork"

# ── Warna & UI ────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' B='\033[0;34m'
Y='\033[1;33m' C='\033[0;36m' W='\033[1;37m' X='\033[0m'
BOLD='\033[1m'

banner() {
  clear
  echo -e "  ${C}┌──────────────────────────────────────┐${X}"
  echo -e "  ${C}│${W}${BOLD}   🦀 PicoClaw Service Manager       ${X}${C}│${X}"
  echo -e "  ${C}│${X}      Interactive Controller          ${C}│${X}"
  echo -e "  ${C}└──────────────────────────────────────┘${X}"
  echo ""
}

info()    { echo -e "  ${B}▸${X} $1"; }
success() { echo -e "  ${G}✓${X} $1"; }
warn()    { echo -e "  ${Y}⚠${X} $1"; }
err()     { echo -e "  ${R}✗${X} $1"; }
ask()     {
    local prompt=$1
    local default=$2
    local var_name=$3
    echo -ne "  ${W}?${X} ${prompt} [${Y}${default}${X}]: "
    read -r value
    if [ -z "$value" ]; then
        eval "$var_name=\"$default\""
    else
        eval "$var_name=\"$value\""
    fi
}

get_latest_manager_version() {
    curl -s "https://api.github.com/repos/${REPO}/releases" | \
        grep -oP '"tag_name":\s*"piman-\K[^"]+' | head -n 1
}

# ── Install ───────────────────────────────────────
cmd_install() {
  banner
  info "${BOLD}Starting Installation Wizard...${X}"
  echo ""

  # 1. Configuration
  ask "Direktori Instalasi" "$DEFAULT_INSTALL_DIR" "INSTALL_DIR"
  ask "Nama Binary Manager" "$DEFAULT_BINARY_NAME" "BINARY_NAME"
  
  # Auto-detect picoclaw
  if command -v picoclaw &> /dev/null; then
    DETECTED_BIN=$(command -v picoclaw)
  else
    DETECTED_BIN="${REAL_HOME}/.local/bin/picoclaw"
  fi
  ask "Path Binary PicoClaw" "$DETECTED_BIN" "PICOCLAW_BIN"
  
  ask "Jalankan sebagai User" "$REAL_USER" "RUN_USER"

  echo ""
  info "Konfigurasi diproses. Menyiapkan sistem..."

  # Detect architecture
  ARCH=$(uname -m)
  case "$ARCH" in
      x86_64|amd64)  ARCH="amd64" ;;
      aarch64|arm64) ARCH="arm64" ;;
      *)
          err "Arsitektur tidak didukung: $ARCH"
          exit 1
          ;;
  esac

  VERSION=$(get_latest_manager_version)
  if [ -z "$VERSION" ]; then
      err "Gagal mendapatkan versi terbaru dari GitHub."
      exit 1
  fi

  DL_URL="https://github.com/${REPO}/releases/download/piman-${VERSION}/picoclaw-manager-linux-${ARCH}"

  info "Mendownload ${BINARY_NAME} ${VERSION}..."
  sudo mkdir -p "$INSTALL_DIR"
  sudo curl -fsSL -L -o "${INSTALL_DIR}/${BINARY_NAME}" "$DL_URL" || {
      err "Gagal mendownload binary."
      exit 1
  }
  sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
  
  # Symlink
  sudo ln -sf "${INSTALL_DIR}/${BINARY_NAME}" /usr/local/bin/piman
  success "Binary terpasang & CLI 'piman' aktif."

  # Systemd Service
  info "Membuat file service systemd..."
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

  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"
  sudo systemctl restart "$SERVICE_NAME"
  success "Service ${SERVICE_NAME} berhasil dijalankan!"

  echo ""
  echo -e "  ${G}${BOLD}Instalasi Selesai!${X}"
  echo -e "  Jalankan '${W}piman status${X}' untuk mengecek kesehatan sistem."
  echo ""
  read -p "Tekan [Enter] untuk kembali ke menu..."
}

# ── Update ────────────────────────────────────────
cmd_update() {
  banner
  info "Memeriksa pembaruan..."
  
  # Set default paths if not set (case for direct command call)
  INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
  BINARY_NAME="${BINARY_NAME:-$DEFAULT_BINARY_NAME}"

  VERSION=$(get_latest_manager_version)
  ARCH=$(uname -m)
  case "$ARCH" in
      x86_64|amd64)  ARCH="amd64" ;;
      aarch64|arm64) ARCH="arm64" ;;
  esac

  DL_URL="https://github.com/${REPO}/releases/download/piman-${VERSION}/picoclaw-manager-linux-${ARCH}"
  
  info "Mengunduh versi ${VERSION}..."
  sudo curl -fsSL -L -o "${INSTALL_DIR}/${BINARY_NAME}" "$DL_URL"
  sudo systemctl restart "$SERVICE_NAME"
  
  success "Update ke versi ${VERSION} berhasil!"
  sleep 2
}

# ── Service Management ────────────────────────────
cmd_restart() {
    info "Restarting service..."
    sudo systemctl restart "$SERVICE_NAME" && success "Done."
    sleep 1
}

cmd_status() {
  banner
  echo -e "  ${W}${BOLD}Service Status:${X}"
  echo ""
  sudo systemctl status "$SERVICE_NAME" --no-pager -l || warn "Service belum terpasang."
  echo ""
  if command -v piman &> /dev/null; then
    echo -e "  ${W}${BOLD}API Status:${X}"
    piman status 2>/dev/null || warn "API tidak merespon."
  fi
  echo ""
  read -p "Tekan [Enter] untuk kembali..."
}

cmd_uninstall() {
  banner
  warn "${BOLD}PERINGATAN: Ini akan menghapus service dan binary!${X}"
  read -p "  Lanjutkan? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then return; fi

  sudo systemctl stop "$SERVICE_NAME" || true
  sudo systemctl disable "$SERVICE_NAME" || true
  sudo rm -f "$SERVICE_FILE"
  sudo rm -f /usr/local/bin/piman
  sudo systemctl daemon-reload
  
  success "Service dibersihkan."
  read -p "Hapus folder ${DEFAULT_INSTALL_DIR}? [y/N] " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo rm -rf "$DEFAULT_INSTALL_DIR"
    success "File fisik dihapus."
  fi
  sleep 1
}

# ── Main Menu ─────────────────────────────────────
cmd_menu() {
  while true; do
    banner
    echo -e "  ${BOLD}Pilih Aksi:${X}"
    echo ""
    echo -e "  ${G}1)${X} Install / Reinstall"
    echo -e "  ${G}2)${X} Update Manager"
    echo -e "  ${G}3)${X} Check Status"
    echo -e "  ${B}4)${X} Restart Service"
    echo -e "  ${B}5)${X} View Logs (Live)"
    echo -e "  ${R}6)${X} Uninstall"
    echo -e "  ${W}0)${X} Exit"
    echo ""
    echo -ne "  ${BOLD}Pilihan: ${X}"
    read -r opt
    
    case $opt in
      1) cmd_install ;;
      2) cmd_update ;;
      3) cmd_status ;;
      4) cmd_restart ;;
      5) banner; journalctl -u "$SERVICE_NAME" -f ;;
      6) cmd_uninstall ;;
      0) clear; exit 0 ;;
      *) warn "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

# ── Dispatch ──────────────────────────────────────
if [ -z "$1" ]; then
    cmd_menu
else
    case "$1" in
        install)      cmd_install ;;
        uninstall)    cmd_uninstall ;;
        update)       cmd_update ;;
        restart)      cmd_restart ;;
        status)       cmd_status ;;
        logs)         journalctl -u "$SERVICE_NAME" -f ;;
        *)            cmd_menu ;;
    esac
fi
