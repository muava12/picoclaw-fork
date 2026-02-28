#!/bin/bash
# ═══════════════════════════════════════════════════
#  PicoClaw Gateway — Interactive Installer
#  Optimized for STB / Armbian / Linux
# ═══════════════════════════════════════════════════
set -e

# Default configurations
DEFAULT_INSTALL_DIR="$HOME/.local/bin"
DEFAULT_BINARY_NAME="picoclaw"
DEFAULT_REPO="muava12/picoclaw-fork"

# ── Warna & UI ────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' B='\033[0;34m'
Y='\033[1;33m' C='\033[0;36m' W='\033[1;37m' X='\033[0m'
BOLD='\033[1m'

banner() {
  clear
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

# ── Utils ─────────────────────────────────────────

get_latest_version() {
    local repo="$1"
    local tags
    tags=$(curl -s "https://api.github.com/repos/${repo}/releases" | grep '"tag_name":' | grep -v 'piman' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    
    local latest=""
    if echo "$tags" | grep -q '\-fork-0\.'; then
        latest=$(echo "$tags" | grep '\-fork-0\.' | sort -V | tail -n 1)
    else
        latest=$(echo "$tags" | sort -V | tail -n 1)
    fi
    echo "$latest"
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
    read -p "Tekan [Enter] untuk kembali..."
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
        exit 1
    fi

    echo ""
    info "Menyisir versi terbaru..."
    local latest=$(get_latest_version "$REPO")
    info "Versi Teks: ${G}$latest${X}"

    local url="https://github.com/${REPO}/releases/download/${latest}/picoclaw_Linux_${ARCH}.tar.gz"
    if [ "$latest" == "" ]; then
        url="https://github.com/${REPO}/releases/latest/download/picoclaw_Linux_${ARCH}.tar.gz"
    fi

    # Execution
    mkdir -p "$INSTALL_DIR"
    info "Mengunduh tarball..."
    
    cd /tmp
    curl -fsSL -L "$url" -o picoclaw.tar.gz || { err "Gagal mengunduh file."; exit 1; }
    
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
        read -p "  Pasang PicoClaw Manager (piman) juga? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            curl -fsSL https://raw.githubusercontent.com/${REPO}/main/setup_picoclaw_manager.sh | bash -s install
        fi
    fi

    echo ""
    success "${BOLD}PicoClaw siap digunakan!${X}"
    read -p "Tekan [Enter] untuk kembali..."
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

cmd_onboard() {
    if command -v picoclaw &> /dev/null; then
        picoclaw onboard
    else
        err "Jalankan instalasi terlebih dahulu."
        sleep 2
    fi
}

cmd_menu() {
  while true; do
    banner
    echo -e "  ${BOLD}Aksi Utama:${X}"
    echo ""
    echo -e "  ${G}1)${X} Install / Reinstall"
    echo -e "  ${G}2)${X} Check Status / Version"
    echo -e "  ${B}3)${X} Check For Updates"
    echo -e "  ${B}4)${X} Run Onboard Wizard"
    echo -e "  ${R}5)${X} Uninstall Binary"
    echo -e "  ${W}0)${X} Exit"
    echo ""
    echo -ne "  ${BOLD}Pilihan: ${X}"
    read -r opt
    
    case $opt in
      1) cmd_install ;;
      2) cmd_status ;;
      3) # Simplified update = reinstall latest
         cmd_install ;;
      4) cmd_onboard ;;
      5) cmd_uninstall ;;
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
        install)   cmd_install ;;
        status)    cmd_status ;;
        onboard)   cmd_onboard ;;
        uninstall) cmd_uninstall ;;
        *)         cmd_menu ;;
    esac
fi
