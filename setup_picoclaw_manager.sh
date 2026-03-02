#!/bin/bash
# ═══════════════════════════════════════════════════
#  PicoClaw Manager — Interactive Installer
#  Optimized for Armbian / Debian / Ubuntu
# ═══════════════════════════════════════════════════

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
  [ -t 1 ] && clear || true
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

read_tty() {
    if [ -t 0 ]; then
        read "$@"
    elif [ -c /dev/tty ]; then
        read "$@" < /dev/tty
    else
        return 1
    fi
}

ask() {
    local prompt=$1
    local default=$2
    local var_name=$3
    echo -ne "  ${W}?${X} ${prompt} [${Y}${default}${X}]: "
    local value=""
    if read_tty -r value; then
        if [ -z "$value" ]; then
            eval "$var_name=\"$default\""
        else
            eval "$var_name=\"$value\""
        fi
    else
        eval "$var_name=\"$default\""
        echo -e "${Y}(automatic)${X}"
    fi
}

# Returns the latest piman-vX.Y.Z tag
get_latest_manager_version() {
    curl -s "https://api.github.com/repos/${REPO}/releases" | \
        grep '"tag_name":' | grep -Eo '"piman-[^"]+' | tr -d '"' | sort -V | tail -n 1
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)
            err "Arsitektur tidak didukung: $(uname -m)"
            return 1
            ;;
    esac
}

# Stop service jika sedang berjalan; returns 0 selalu
stop_service_if_running() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        info "Menghentikan service ${SERVICE_NAME} yang sedang berjalan..."
        sudo systemctl stop "$SERVICE_NAME" || true
        # Tunggu hingga benar-benar berhenti
        local i=0
        while systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && [ $i -lt 10 ]; do
            sleep 1; i=$((i+1))
        done
        success "Service dihentikan."
    fi
}

# ── Install ───────────────────────────────────────
cmd_install() {
  banner
  info "${BOLD}Starting Installation Wizard...${X}"
  echo ""

  # 1. Configuration
  ask "Direktori Instalasi" "$DEFAULT_INSTALL_DIR" "INSTALL_DIR"
  ask "Nama Binary Manager" "$DEFAULT_BINARY_NAME" "BINARY_NAME"

  # Auto-detect picoclaw binary
  if command -v picoclaw &>/dev/null; then
    DETECTED_BIN=$(command -v picoclaw)
  else
    DETECTED_BIN="${REAL_HOME}/.local/bin/picoclaw"
  fi
  ask "Path Binary PicoClaw" "$DETECTED_BIN" "PICOCLAW_BIN"
  ask "Jalankan sebagai User" "$REAL_USER" "RUN_USER"

  echo ""
  info "Mendeteksi arsitektur..."
  local arch_final
  arch_final=$(detect_arch) || return 1

  info "Menyisir versi terbaru..."
  local version
  version=$(get_latest_manager_version)
  if [ -z "$version" ]; then
      err "Gagal mendapatkan versi terbaru dari GitHub."
      return 1
  fi
  info "Versi: ${G}${version}${X}"

  local dl_url="https://github.com/${REPO}/releases/download/${version}/picoclaw-manager-linux-${arch_final}"

  # ── Stop service dulu sebelum overwrite binary ──
  stop_service_if_running

  info "Mengunduh ${BINARY_NAME} (${version})..."
  sudo mkdir -p "$INSTALL_DIR"
  sudo curl -fsSL -L -o "${INSTALL_DIR}/${BINARY_NAME}.tmp" "$dl_url" || {
      err "Gagal mengunduh binary dari: $dl_url"
      return 1
  }
  # Atomic replace — hindari binary korup jika curl terputus di tengah
  sudo mv -f "${INSTALL_DIR}/${BINARY_NAME}.tmp" "${INSTALL_DIR}/${BINARY_NAME}"
  sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

  # Symlink CLI
  sudo ln -sf "${INSTALL_DIR}/${BINARY_NAME}" /usr/local/bin/piman
  success "Binary terpasang & CLI 'piman' aktif."

  # Systemd Service
  info "Membuat file service systemd..."
  sudo tee "$SERVICE_FILE" > /dev/null <<UNIT
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

  # Verifikasi service benar-benar up
  sleep 2
  if systemctl is-active --quiet "$SERVICE_NAME"; then
      success "Service ${SERVICE_NAME} aktif!"
  else
      warn "Service mungkin belum aktif. Cek dengan: sudo journalctl -u ${SERVICE_NAME} -n 30"
  fi

  echo ""
  echo -e "  ${G}${BOLD}Instalasi Selesai!${X}"
  echo -e "  Jalankan '${W}piman status${X}' untuk mengecek kesehatan sistem."
  echo ""
  echo -ne "  Tekan [Enter] untuk kembali ke menu..."
  read_tty -r
}

# ── Update ────────────────────────────────────────
cmd_update() {
  banner
  info "Memeriksa pembaruan..."

  INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
  BINARY_NAME="${BINARY_NAME:-$DEFAULT_BINARY_NAME}"

  local arch_final
  arch_final=$(detect_arch) || return 1

  local version
  version=$(get_latest_manager_version)
  if [ -z "$version" ]; then
      err "Gagal mendapatkan versi terbaru."
      return 1
  fi
  info "Update ke: ${G}${version}${X}"

  # Tag format: piman-vX.Y.Z → binary URL: .../piman-vX.Y.Z/picoclaw-manager-linux-arch
  local dl_url="https://github.com/${REPO}/releases/download/${version}/picoclaw-manager-linux-${arch_final}"

  # Stop service sebelum update
  stop_service_if_running

  info "Mengunduh binary baru..."
  sudo curl -fsSL -L -o "${INSTALL_DIR}/${BINARY_NAME}.tmp" "$dl_url" || {
      err "Gagal mengunduh binary."
      # Restart service dengan binary lama
      sudo systemctl start "$SERVICE_NAME" || true
      return 1
  }
  sudo mv -f "${INSTALL_DIR}/${BINARY_NAME}.tmp" "${INSTALL_DIR}/${BINARY_NAME}"
  sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

  sudo systemctl start "$SERVICE_NAME"
  sleep 2
  if systemctl is-active --quiet "$SERVICE_NAME"; then
      success "Update ke ${version} berhasil & service aktif!"
  else
      warn "Update selesai tapi service gagal start. Cek: sudo journalctl -u ${SERVICE_NAME} -n 30"
  fi
  sleep 2
}

# ── Service Management ────────────────────────────
cmd_restart() {
    info "Restarting service..."
    sudo systemctl restart "$SERVICE_NAME" && success "Done." || err "Gagal restart."
    sleep 1
}

cmd_status() {
  banner
  echo -e "  ${W}${BOLD}Service Status:${X}"
  echo ""
  sudo systemctl status "$SERVICE_NAME" --no-pager -l || warn "Service belum terpasang."
  echo ""
  if command -v piman &>/dev/null; then
    echo -e "  ${W}${BOLD}API Status:${X}"
    piman status 2>/dev/null || warn "API tidak merespon."
  fi
  echo ""
  echo -ne "  Tekan [Enter] untuk kembali..."
  read_tty -r
}

cmd_uninstall() {
  banner
  warn "${BOLD}PERINGATAN: Ini akan menghapus service dan binary!${X}"
  echo -ne "  Lanjutkan? [y/N] "
  local reply=""
  if read_tty -n 1 -r reply; then
    echo ""
    if [[ ! $reply =~ ^[Yy]$ ]]; then return; fi
  else
    return 1
  fi

  stop_service_if_running
  sudo systemctl disable "$SERVICE_NAME" || true
  sudo rm -f "$SERVICE_FILE"
  sudo rm -f /usr/local/bin/piman
  sudo systemctl daemon-reload
  success "Service dan symlink dibersihkan."

  echo -ne "  Hapus folder ${DEFAULT_INSTALL_DIR}? [y/N] "
  if read_tty -n 1 -r reply; then
    echo ""
    if [[ $reply =~ ^[Yy]$ ]]; then
      sudo rm -rf "$DEFAULT_INSTALL_DIR"
      success "File fisik dihapus."
    fi
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
    local opt=""
    if ! read_tty -r opt; then
        exit 0
    fi

    case $opt in
      1) cmd_install ;;
      2) cmd_update ;;
      3) cmd_status ;;
      4) cmd_restart ;;
      5) banner; journalctl -u "$SERVICE_NAME" -f ;;
      6) cmd_uninstall ;;
      0) banner; exit 0 ;;
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
