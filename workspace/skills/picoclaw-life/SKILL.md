---
name: picoclaw-life
description: Setup, manage, dan monitor PicoClaw gateway lifecycle — install service, start/stop/restart, update binary, lihat status dan log.
metadata: {"nanobot":{"emoji":"🦀"}}
---

# PicoClaw Lifecycle Manager

Manage PicoClaw gateway lifecycle: install sebagai systemd service, start/stop/restart, check & apply updates, monitor status dan log.

## When to use (trigger phrases)

- "start/stop/restart picoclaw"
- "status picoclaw" / "picoclaw jalan gak?"
- "install picoclaw service" / "setup picoclaw"
- "update picoclaw" / "cek update picoclaw"
- "log picoclaw" / "lihat log picoclaw"
- "uninstall picoclaw service"

## Arsitektur

```
systemd → picoclaw-manager (port 8321) → picoclaw gateway
                  ↓ (saat update)
           update_picoclaw.sh → download binary dari GitHub releases
```

- `picoclaw-manager` (Go binary) jalan sebagai systemd service (`picoclaw-manager`)
- REST API untuk kontrol gateway (start/stop/restart/status)
- REST API untuk check update dan update binary via `update_picoclaw.sh`
- Auto-start gateway saat service dimulai

## Init — Download Semua File dari GitHub

Saat pertama kali setup, download semua file yang dibutuhkan ke direktori skill lokal:

```bash
# Direktori lokal skill
SKILL_DIR="/DATA/.picoclaw/workspace/skills/picoclaw-life"
SCRIPTS_DIR="${SKILL_DIR}/scripts"

# 1. Pastikan direktori scripts ada
mkdir -p "${SCRIPTS_DIR}"

# 2. Unduh setup script dan install manager service
curl -fsSL https://raw.githubusercontent.com/muava12/picoclaw-fork/main/setup_picoclaw_manager.sh | bash -s install -- --install-dir "${SCRIPTS_DIR}"

# 3. Unduh dan instal update script ke direktori scripts lokal
curl -fsSL https://raw.githubusercontent.com/muava12/picoclaw-fork/main/workspace/skills/picoclaw-life/scripts/update_picoclaw.sh -o "${SCRIPTS_DIR}/update_picoclaw.sh"
chmod +x "${SCRIPTS_DIR}/update_picoclaw.sh"
```

### File yang dibutuhkan

| File | Lokasi | Fungsi |
|------|---------|--------|
| `picoclaw` (binary) | `~/.local/bin/picoclaw` | Gateway utama |
| `picoclaw-manager` (Go) | `/opt/picoclaw/picoclaw-manager` | API server manager |
| `update_picoclaw.sh` | `/DATA/.picoclaw/workspace/skills/picoclaw-life/scripts/` | Script update binary (dipanggil oleh manager) |
| `setup_picoclaw_manager.sh` | Via curl (tidak perlu simpan) | Installer service |

## API Endpoints

| Method | Endpoint | Fungsi |
|--------|----------|--------|
| `GET` | `/api/health` | Health check manager |
| `GET` | `/api/picoclaw/status` | Status gateway (running, pid, uptime, recent logs) |
| `GET` | `/api/picoclaw/check-update` | Cek versi baru di GitHub releases |
| `POST` | `/api/picoclaw/start` | Start gateway |
| `POST` | `/api/picoclaw/stop` | Stop gateway |
| `POST` | `/api/picoclaw/restart` | Restart gateway |
| `POST` | `/api/picoclaw/update` | Update binary via update_picoclaw.sh (auto stop/start) |

## Update Binary

Sangat disarankan untuk menggunakan **CLI `piman`** agar lebih mudah dan tidak terpengaruh asalkan service berjalan (terhindar dari masalah port binding manual):

```bash
# Update fusi gateway terbaru dari Github (auto stop/start gateway)
piman update
```

Flow: manager stop gateway → jalankan `update_picoclaw.sh` → restart gateway otomatis.

> 📝 **Auto-update versi di IDENTITY.md**: Setelah update berhasil, versi di file `IDENTITY.md` di direktori workspace `/DATA/.picoclaw/workspace/` akan otomatis diperbarui ke versi terbaru.

> ⚠️ **JANGAN gunakan `install_picoclaw.sh` untuk update** — script itu akan mematikan manager dan membutuhkan manual restart. Selalu gunakan `piman update` di atas.

## Perintah Harian

### Cek status & Update
Perintah status juga akan sekaligus mengecek versi rilisan terbaru di GitHub:
```bash
piman status
```

### Restart / Start / Stop gateway
```bash
piman restart
piman start
piman stop
```

### Lihat log terakhir
Menampilkan 20 log terakhir yang ditangkap oleh manager:
```bash
piman logs
```

### Follow live log
Jika Anda ingin melihat streaming log secara live (di luar executor nanobot):
```bash
journalctl -u picoclaw-manager -f
```

## Rules

1. **Gunakan CLI piman** — untuk start/stop/restart/status/update, panggil CLI `piman <command>`.
2. **Lihat logs** — memanggil `piman logs` adalah cara teraman untuk mengecek apa yang sedang diproses.
3. **Install cukup sekali** — setup script download semua dari GitHub.
4. **Re-install aman** — menjalankan `install` ulang akan restart service dengan script terbaru.
5. **Update binary via CLI** — gunakan `piman update` untuk update dengan aman secara otomatis.
6. **update_picoclaw.sh harus ada** — pastikan file ini di `/DATA/.picoclaw/workspace/skills/picoclaw-life/scripts/` untuk update.

## Config

- **Binary PicoClaw**: `~/.local/bin/picoclaw`
- **Config**: `~/.picoclaw/config.json`
- **Port Manager API**: `8321`
- **Install dir**: `/DATA/.picoclaw/workspace/skills/picoclaw-life/scripts/`
- **Service**: `picoclaw-manager.service`
- **Repo**: `muava12/picoclaw-fork`
