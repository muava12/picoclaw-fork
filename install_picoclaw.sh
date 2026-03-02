#!/bin/bash
# ═══════════════════════════════════════════════════
#  PicoClaw Gateway — Interactive Installer
#  Optimized for STB / Armbian / Linux
# ═══════════════════════════════════════════════════

# Default configurations
DEFAULT_INSTALL_DIR="$HOME/.local/bin"
DEFAULT_BINARY_NAME="picoclaw"
DEFAULT_REPO="muava12/picoclaw-fork"

# ── Warna & UI ────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' B='\033[0;34m'
Y='\033[1;33m' C='\033[0;36m' W='\033[1;37m' X='\033[0m'
BOLD='\033[1m'

banner() {
  # Clear only if it's a real terminal to avoid exit on error or mess in logs
  [ -t 1 ] && clear || true
  echo -e "  ${C}┌──────────────────────────────────────┐${X}"
  echo -e "  ${C}│${W}${BOLD}   🦀 PicoClaw Gateway Installer     ${X}${C}│${X}"
  echo -e "  ${C}│${X}      Core Binary Controller          ${C}│${X}"
  echo -e "  ${C}└──────────────────────────────────────┘${X}"
  echo ""
}

info()    { echo -e "  ${B}▸${X} $1"; }
success() { echo -e "  ${G}✓${X} $1"; }
warn()    { echo -e "  ${Y}⚠${X} $1"; }
err()     { echo -e "  ${R}✗${X} $1"; }

# Robust interactive read that works even when script is piped via curl
read_tty() {
    if [ -t 0 ]; then
        read "$@"
    elif [ -c /dev/tty ]; then
        read "$@" < /dev/tty
    else
        # If no TTY, we might be in a non-interactive environment
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
        # Fallback to default if read fails (non-interactive)
        eval "$var_name=\"$default\""
        echo -e "${Y}(automatic)${X}"
    fi
}

# ── Utils ─────────────────────────────────────────

get_latest_version() {
    local repo="$1"
    # Fetch all tags, exclude piman/pilaunch
    local tags
    tags=$(curl -s "https://api.github.com/repos/${repo}/releases" \
        | grep '"tag_name":' \
        | grep -v 'piman\|pilaunch' \
        | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')

    if [[ "$repo" == *"fork"* ]]; then
        # Sort by numeric suffix after last '-' (handles fork-0.24 > fork-0.9 correctly)
        echo "$tags" | grep 'fork-' \
            | awk -F'[.-]' '{n=$NF+0; print n, $0}' \
            | sort -k1,1n \
            | tail -n 1 \
            | cut -d' ' -f2-
    else
        # Standard SemVer sort for original repo
        echo "$tags" | sort -V | tail -n 1
    fi
}

fetch_versions() {
    # Installed version
    local inst_path
    inst_path=$(command -v picoclaw 2>/dev/null || echo "$DEFAULT_INSTALL_DIR/picoclaw")
    CUR_VER="(tidak terpasang)"
    if [ -x "$inst_path" ]; then
        CUR_VER=$("$inst_path" --version 2>/dev/null | head -n 1 || echo "unknown")
    fi

    # Latest versions (fetch once)
    info "Menyisir info rilis..."
    LATEST_FORK=$(get_latest_version "muava12/picoclaw-fork")
    LATEST_ORIG=$(get_latest_version "sipeed/picoclaw")
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*|armhf)  echo "armv7" ;;
        *)             echo "unknown" ;;
    esac
}

# ── Commands ──────────────────────────────────────

cmd_status() {
    banner
    echo -e "  ${BOLD}${W}System Status:${X}"
    echo ""
    
    # 1. Check Binary
    local inst_path=$(command -v picoclaw || echo "$DEFAULT_INSTALL_DIR/picoclaw")
    if [ -f "$inst_path" ]; then
        local ver=$("$inst_path" --version 2>/dev/null | head -n 1 || echo "Unknown")
        success "Binary: ${W}$inst_path${X}"
        info "Version: ${G}$ver${X}"
    else
        warn "Binary: ${R}Not found${X}"
    fi

    # 2. Check PATH
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        success "PATH: ${G}Configured${X} ($HOME/.local/bin)"
    else
        warn "PATH: ${R}Not in PATH${X} (Manual export needed)"
    fi

    # 3. Check Service (via Manager)
    if systemctl is-active --quiet picoclaw-manager 2>/dev/null; then
        success "Manager Service: ${G}Active${X}"
    else
        info "Manager Service: ${Y}Inactive/Not Installed${X}"
    fi

    echo ""
    echo -ne "  Tekan [Enter] untuk kembali..."
    read_tty -r
}

cmd_install() {
    banner
    info "${BOLD}Starting Installation Wizard...${X}"
    echo ""

    # Select Repo
    echo -e "  ${BOLD}Pilih Edisi:${X}"
    echo "  1) Original (sipeed/picoclaw)"
    echo "  2) Fork (muava12/picoclaw-fork)"
    ask "Pilihan" "2" "EDO_CHOICE"
    if [ "$EDO_CHOICE" == "1" ]; then REPO="sipeed/picoclaw"; else REPO="$DEFAULT_REPO"; fi

    # Configs
    ask "Direktori Instalasi" "$DEFAULT_INSTALL_DIR" "INSTALL_DIR"
    ask "Nama Binary" "$DEFAULT_BINARY_NAME" "BINARY_NAME"
    
    # Arch
    local det_arch=$(detect_arch)
    ask "Arsitektur" "$det_arch" "ARCH"
    if [ "$ARCH" == "unknown" ]; then
        err "Arsitektur tidak dikenali secara otomatis. Harap masukkan manual (x86_64, arm64, armv7)."
        return 1
    fi

    echo ""
    info "Menyisir versi terbaru..."
    local latest=$(get_latest_version "$REPO")
    info "Versi Teks: ${G}$latest${X}"

    local url="https://github.com/${REPO}/releases/download/${latest}/picoclaw_Linux_${ARCH}.tar.gz"
    if [ "$latest" == "" ]; then
        url="https://github.com/${REPO}/releases/latest/download/picoclaw_Linux_${ARCH}.tar.gz"
    fi

    # Execution - from here on, we want to stop on any failure
    set -e
    mkdir -p "$INSTALL_DIR"
    info "Mengunduh tarball..."
    
    cd /tmp
    curl -fsSL -L "$url" -o picoclaw.tar.gz || { err "Gagal mengunduh file."; set +e; return 1; }
    
    info "Mengekstrak..."
    tar -xzf picoclaw.tar.gz "$DEFAULT_BINARY_NAME"
    mv -f "$DEFAULT_BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    rm -f picoclaw.tar.gz

    success "Instalasi binary selesai: $INSTALL_DIR/$BINARY_NAME"

    # PATH Fix
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        info "Menambahkan $INSTALL_DIR ke PATH..."
        [ -f "$HOME/.bashrc" ] && ! grep -q "$INSTALL_DIR" "$HOME/.bashrc" && echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$HOME/.bashrc"
        [ -f "$HOME/.zshrc" ] && ! grep -q "$INSTALL_DIR" "$HOME/.zshrc" && echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$HOME/.zshrc"
        success "PATH ditambahkan ke .bashrc/.zshrc. Selesaikan dengan 'source ~/.bashrc'."
    fi

    # Optional Manager
    if [ "$REPO" == "$DEFAULT_REPO" ]; then
        echo ""
        echo -ne "  Pasang PicoClaw Manager (piman) juga? [y/N] "
        local reply=""
        if read_tty -n 1 -r reply; then
            echo ""
            if [[ $reply =~ ^[Yy]$ ]]; then
                curl -fsSL https://raw.githubusercontent.com/${REPO}/main/setup_picoclaw_manager.sh | bash -s install
            fi
        fi
    fi
    set +e

    echo ""
    success "${BOLD}PicoClaw siap digunakan!${X}"
    echo -ne "  Tekan [Enter] untuk kembali..."
    read_tty -r
}

cmd_uninstall() {
    banner
    warn "${BOLD}Hapus PicoClaw?${X}"
    ask "Nama Binary yang dihapus" "$DEFAULT_BINARY_NAME" "BIN_TO_DEL"
    
    local target=$(command -v "$BIN_TO_DEL" || echo "$DEFAULT_INSTALL_DIR/$BIN_TO_DEL")
    if [ -f "$target" ]; then
        sudo rm -f "$target"
        success "Binary $target dihapus."
    else
        err "Binary tidak ditemukan."
    fi
    sleep 2
}

cmd_check_update() {
    banner
    echo -e "  ${BOLD}${W}Update Check:${X}"
    echo ""

    # Versi terpasang
    local inst_path
    inst_path=$(command -v picoclaw 2>/dev/null || echo "$DEFAULT_INSTALL_DIR/picoclaw")
    local installed="(tidak terpasang)"
    if [ -x "$inst_path" ]; then
        installed=$("$inst_path" --version 2>/dev/null | head -n 1 || echo "unknown")
    fi
    info "Terpasang : ${W}${installed}${X}"

    info "Memeriksa versi terbaru..."
    local latest
    latest=$(get_latest_version "$DEFAULT_REPO")
    if [ -z "$latest" ]; then
        warn "Tidak dapat membaca versi terbaru dari GitHub."
    else
        info "Tersedia  : ${G}${latest}${X}"
        echo ""
        echo -e "  Untuk update, jalankan: ${W}curl -fsSL .../install_picoclaw.sh | bash -s install${X}"
    fi
    echo ""
    echo -ne "  Tekan [Enter] untuk kembali..."
    read_tty -r
}

cmd_onboard() {
    if command -v picoclaw &>/dev/null; then
        picoclaw onboard
    else
        err "Jalankan instalasi terlebih dahulu."
        sleep 2
    fi
}

cmd_menu() {
  fetch_versions
  
  while true; do
    banner
    echo -e "  ${BOLD}Status Sistem:${X}"
    echo -e "  Terpasang : ${W}${CUR_VER% (fork*)}${X}"
    echo -e "  Rilis Fork: ${G}${LATEST_FORK}${X}"
    echo -e "  Rilis Orig: ${C}${LATEST_ORIG}${X}"
    echo ""

    echo -e "  ${BOLD}Aksi Utama:${X}"
    echo -e "  ${G}1)${X} Update / Reinstall ${BOLD}Fork${X} (${LATEST_FORK})"
    echo -e "  ${C}2)${X} Install / Switch ke ${BOLD}Original${X} (${LATEST_ORIG})"
    echo -e "  ${B}3)${X} Setup / Manage ${BOLD}Manager (piman)${X}"
    echo -e "  ${Y}4)${X} Run Onboard Wizard"
    echo -e "  ${W}5)${X} Check Status / Full Info"
    echo -e "  ${R}6)${X} Uninstall Binary"
    echo -e "  ${W}0)${X} Exit"
    echo ""
    echo -ne "  ${BOLD}Pilihan: ${X}"
    local opt=""
    if ! read_tty -r opt; then
        exit 0
    fi
    
    case $opt in
      1) REPO="muava12/picoclaw-fork"; cmd_install ;;
      2) REPO="sipeed/picoclaw"; cmd_install ;;
      3) # Direct curl to setup_picoclaw_manager.sh
         curl -fsSL https://raw.githubusercontent.com/muava12/picoclaw-fork/main/setup_picoclaw_manager.sh | bash ;;
      4) cmd_onboard ;;
      5) cmd_status ;;
      6) cmd_uninstall ;;
      0) banner; exit 0 ;;
      *) warn "Pilihan tidak valid."; sleep 1 ;;
    esac
    # Refresh versions after potential install/update
    [ "$opt" == "1" ] || [ "$opt" == "2" ] || [ "$opt" == "6" ] && fetch_versions
  done
}

# ── Dispatch ──────────────────────────────────────
if [ -z "$1" ]; then
    cmd_menu
else
    case "$1" in
        install)      cmd_install ;;
        status)       cmd_status ;;
        check-update) cmd_check_update ;;
        onboard)      cmd_onboard ;;
        uninstall)    cmd_uninstall ;;
        *)            cmd_menu ;;
    esac
fi
