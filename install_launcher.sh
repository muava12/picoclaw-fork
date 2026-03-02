#!/bin/bash
# ═══════════════════════════════════════════════════
#  PicoClaw Launcher — Install / Update / Uninstall
#  Supports: Linux (x86_64, arm64) & macOS (arm64)
# ═══════════════════════════════════════════════════

REPO="muava12/picoclaw-fork"
BINARY_NAME="picoclaw-launcher"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="pilaunch"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ── Warna & UI ────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' B='\033[0;34m'
Y='\033[1;33m' C='\033[0;36m' W='\033[1;37m' X='\033[0m'
BOLD='\033[1m'

banner() {
  [ -t 1 ] && clear || true
  echo -e "  ${C}┌──────────────────────────────────────┐${X}"
  echo -e "  ${C}│${W}${BOLD}   🚀 PicoClaw Launcher Installer    ${X}${C}│${X}"
  echo -e "  ${C}│${X}      Visual Config & Auth GUI        ${C}│${X}"
  echo -e "  ${C}└──────────────────────────────────────┘${X}"
  echo ""
}

info()    { echo -e "  ${B}▸${X} $1"; }
success() { echo -e "  ${G}✓${X} $1"; }
warn()    { echo -e "  ${Y}⚠${X} $1"; }
err()     { echo -e "  ${R}✗${X} $1"; }

# ── Helpers ───────────────────────────────────────

need_sudo() {
    if [ ! -w "$INSTALL_DIR" ]; then
        echo "sudo"
    else
        echo ""
    fi
}

detect_os_arch() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) err "Arsitektur tidak didukung: $arch"; return 1 ;;
    esac

    case "$os" in
        linux)  ;;
        darwin) os="macos" ;;
        *) err "OS tidak didukung: $os"; return 1 ;;
    esac

    echo "${os}-${arch}"
}

get_latest_launcher_version() {
    # Latest tag yang dimulai dengan "pilaunch-"
    curl -sf "https://api.github.com/repos/${REPO}/releases" | \
        grep '"tag_name":' | grep -Eo '"pilaunch-[^"]+' | tr -d '"' | sort -V | tail -n 1
}

download_launcher() {
    local version="$1"
    local os_arch="$2"
    local dest="$3"

    local asset_name="${BINARY_NAME}-${os_arch}"
    local dl_url="https://github.com/${REPO}/releases/download/${version}/${asset_name}"

    info "Mengunduh ${asset_name} (${version})..."
    local sudo_cmd
    sudo_cmd=$(need_sudo)

    ${sudo_cmd} curl -fsSL -L -o "${dest}.tmp" "$dl_url" || {
        err "Gagal mengunduh dari: $dl_url"
        ${sudo_cmd} rm -f "${dest}.tmp"
        return 1
    }
    # Atomic replace
    ${sudo_cmd} mv -f "${dest}.tmp" "$dest"
    ${sudo_cmd} chmod +x "$dest"
}

# ── Service Management ──────────────────────────

is_systemd_available() {
    if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

setup_systemd_service() {
    if ! is_systemd_available; then
        return
    fi

    info "Menyiapkan systemd service..."
    local sudo_cmd
    sudo_cmd=$(need_sudo)
    local user_name
    user_name=$(whoami)
    local home_dir
    home_dir=$HOME

    local service_content="[Unit]
Description=PicoClaw Launcher Service
After=network.target

[Service]
Type=simple
User=${user_name}
ExecStart=${INSTALL_DIR}/${BINARY_NAME} -public
Restart=always
RestartSec=5
Environment=HOME=${home_dir}

[Install]
WantedBy=multi-user.target"

    echo "$service_content" | ${sudo_cmd} tee "$SERVICE_FILE" > /dev/null
    ${sudo_cmd} systemctl daemon-reload
    ${sudo_cmd} systemctl enable "$SERVICE_NAME"
    success "Service ${SERVICE_NAME} berhasil dikonfigurasi dan diaktifkan."
}

manage_service() {
    local action="$1"
    if ! is_systemd_available; then
        return
    fi
    
    local sudo_cmd
    sudo_cmd=$(need_sudo)
    
    # Cek jika service file ada sebelum menjalankan command
    if [ ! -f "$SERVICE_FILE" ]; then
        return
    fi

    case "$action" in
        stop)
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                info "Menghentikan service ${SERVICE_NAME}..."
                ${sudo_cmd} systemctl stop "$SERVICE_NAME"
            fi
            ;;
        start)
            info "Menjalankan service ${SERVICE_NAME}..."
            ${sudo_cmd} systemctl start "$SERVICE_NAME"
            ;;
        restart)
            info "Me-restart service ${SERVICE_NAME}..."
            ${sudo_cmd} systemctl restart "$SERVICE_NAME"
            ;;
        disable)
            info "Menonaktifkan service ${SERVICE_NAME}..."
            ${sudo_cmd} systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
            ${sudo_cmd} rm -f "$SERVICE_FILE"
            ${sudo_cmd} systemctl daemon-reload
            ;;
    esac
}

# ── Commands ──────────────────────────────────────

cmd_install() {
    banner
    info "${BOLD}Instalasi PicoClaw Launcher...${X}"
    echo ""

    local os_arch
    os_arch=$(detect_os_arch) || return 1
    info "Terdeteksi: ${G}${os_arch}${X}"

    local version
    version=$(get_latest_launcher_version)
    if [ -z "$version" ]; then
        err "Tidak dapat menemukan rilis launcher di GitHub."
        return 1
    fi
    info "Versi terbaru: ${G}${version}${X}"

    local dest="${INSTALL_DIR}/${BINARY_NAME}"

    # Stop proses launcher jika sedang berjalan (baik via binary langsung atau service)
    manage_service stop
    if pgrep -x "$BINARY_NAME" &>/dev/null; then
        info "Menghentikan launcher yang sedang berjalan..."
        pkill -x "$BINARY_NAME" || true
        sleep 1
    fi

    download_launcher "$version" "$os_arch" "$dest" || return 1

    setup_systemd_service
    manage_service start

    echo ""
    success "PicoClaw Launcher berhasil dipasang di ${W}${dest}${X}"
    info "Jalankan dengan: ${W}${BINARY_NAME}${X}"
    info "Buka browser ke: ${W}http://localhost:18800${X}"
    echo ""
}

cmd_update() {
    banner
    info "Memeriksa pembaruan launcher..."
    echo ""

    local os_arch
    os_arch=$(detect_os_arch) || return 1

    # Versi terpasang
    local installed_ver="(tidak terpasang)"
    if command -v "$BINARY_NAME" &>/dev/null; then
        installed_ver=$("$BINARY_NAME" --version 2>/dev/null | head -n 1 || echo "unknown")
    fi
    info "Terpasang: ${Y}${installed_ver}${X}"

    local version
    version=$(get_latest_launcher_version)
    if [ -z "$version" ]; then
        err "Tidak dapat menemukan rilis terbaru."
        return 1
    fi
    info "Tersedia : ${G}${version}${X}"
    echo ""

    local dest="${INSTALL_DIR}/${BINARY_NAME}"

    # Stop launcher jika berjalan
    manage_service stop
    if pgrep -x "$BINARY_NAME" &>/dev/null; then
        info "Menghentikan launcher yang sedang berjalan..."
        pkill -x "$BINARY_NAME" || true
        sleep 1
    fi

    download_launcher "$version" "$os_arch" "$dest" || return 1

    # Update service jika belum ada (misal dari instalasi lama)
    if is_systemd_available && [ ! -f "$SERVICE_FILE" ]; then
        setup_systemd_service
    fi
    manage_service start

    success "Update selesai → ${W}${version}${X}"
    echo ""
}

cmd_uninstall() {
    banner
    warn "${BOLD}Ini akan menghapus ${BINARY_NAME} dari sistem.${X}"
    echo -ne "  Lanjutkan? [y/N] "
    local reply=""
    if [ -t 0 ] || [ -c /dev/tty ]; then
        read -r reply </dev/tty 2>/dev/null || read -r reply
    fi
    echo ""
    if [[ ! $reply =~ ^[Yy]$ ]]; then
        info "Dibatalkan."
        return
    fi

    # Stop proses jika berjalan
    manage_service stop
    manage_service disable
    if pgrep -x "$BINARY_NAME" &>/dev/null; then
        info "Menghentikan launcher..."
        pkill -x "$BINARY_NAME" || true
        sleep 1
    fi

    local dest="${INSTALL_DIR}/${BINARY_NAME}"
    local sudo_cmd
    sudo_cmd=$(need_sudo)

    if [ -f "$dest" ]; then
        ${sudo_cmd} rm -f "$dest"
        success "Binary ${dest} dihapus."
    else
        warn "Binary tidak ditemukan di ${dest}."
    fi
    echo ""
}

cmd_status() {
    banner
    echo -e "  ${W}${BOLD}Launcher Status:${X}"
    echo ""

    local dest="${INSTALL_DIR}/${BINARY_NAME}"
    if [ -f "$dest" ]; then
        local ver
        ver=$("$dest" --version 2>/dev/null | head -n 1 || echo "unknown")
        success "Binary: ${W}${dest}${X}"
        info "Versi  : ${G}${ver}${X}"
    else
        warn "Binary tidak terpasang."
    fi

    if is_systemd_available; then
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            success "Service : ${G}Active${X} (${SERVICE_NAME}.service)"
        else
            info "Service : ${Y}Inactive${X} (${SERVICE_NAME}.service)"
        fi
    fi

    if pgrep -x "$BINARY_NAME" &>/dev/null; then
        success "Proses  : ${G}Berjalan${X} (PID: $(pgrep -x "$BINARY_NAME" | head -1))"
        info "UI      : ${W}http://localhost:18800${X}"
    else
        info "Proses  : ${Y}Tidak berjalan${X}"
    fi
    echo ""
}

# ── Dispatch ──────────────────────────────────────
case "${1:-install}" in
    install)   cmd_install ;;
    update)    cmd_update ;;
    uninstall) cmd_uninstall ;;
    status)    cmd_status ;;
    *)
        banner
        echo -e "  Usage: curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install_launcher.sh | bash"
        echo ""
        echo -e "  Commands:"
        echo -e "    ${G}install${X}   — Install / reinstall (default)"
        echo -e "    ${G}update${X}    — Update ke versi terbaru"
        echo -e "    ${R}uninstall${X} — Hapus binary"
        echo -e "    ${W}status${X}    — Cek status"
        echo ""
        echo -e "  Jalankan command tertentu:"
        echo -e "    curl ... | bash -s update"
        echo ""
        ;;
esac
