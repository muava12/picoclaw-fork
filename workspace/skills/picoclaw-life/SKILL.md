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
systemd → picoclaw_manager.py (port 8321) → picoclaw gateway
                  ↓ (saat update)
           update_picoclaw.sh → download binary dari GitHub releases
```

- `picoclaw_manager.py` jalan sebagai systemd service (`picoclaw-manager`)
- REST API untuk kontrol gateway (start/stop/restart/status)
- REST API untuk check update dan update binary via `update_picoclaw.sh`
- Auto-start gateway saat service dimulai

## Init — Download Semua File dari GitHub

Saat pertama kali setup, download semua file yang dibutuhkan:

```bash
REPO_RAW="https://raw.githubusercontent.com/muava12/picoclaw-fork/main"
SKILL_RAW="${REPO_RAW}/workspace/skills/picoclaw-life/scripts"

# 1. Install manager service (otomatis download picoclaw_manager.py)
curl -fsSL ${REPO_RAW}/setup_picoclaw_manager.sh | bash -s install

# 2. Download update script ke /opt/picoclaw/
sudo curl -fsSL ${SKILL_RAW}/update_picoclaw.sh -o /opt/picoclaw/update_picoclaw.sh
sudo chmod +x /opt/picoclaw/update_picoclaw.sh
```

### File yang dibutuhkan

| File | Lokasi | Fungsi |
|------|---------|--------|
| `picoclaw` (binary) | `~/.local/bin/picoclaw` | Gateway utama |
| `picoclaw_manager.py` | `/opt/picoclaw/` | API server manager |
| `update_picoclaw.sh` | `/opt/picoclaw/` | Script update binary (dipanggil oleh manager) |
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

Selalu gunakan Manager API:

```bash
# Cek apakah ada versi baru
curl -s http://localhost:8321/api/picoclaw/check-update

# Update langsung (auto stop/start gateway)
curl -s -X POST http://localhost:8321/api/picoclaw/update
```

Flow: manager stop gateway → jalankan `update_picoclaw.sh` → restart gateway otomatis.

> ⚠️ **JANGAN gunakan `install_picoclaw.sh` untuk update** — script itu akan mematikan manager dan membutuhkan manual restart. Selalu gunakan API di atas.

## Perintah Harian

### Cek status

```bash
curl -s http://localhost:8321/api/picoclaw/status
```

### Cek update

```bash
curl -s http://localhost:8321/api/picoclaw/check-update
```

### Update binary

```bash
curl -s -X POST http://localhost:8321/api/picoclaw/update
```

### Restart / Start / Stop gateway

```bash
curl -s -X POST http://localhost:8321/api/picoclaw/restart
curl -s -X POST http://localhost:8321/api/picoclaw/start
curl -s -X POST http://localhost:8321/api/picoclaw/stop
```

### Lihat log terakhir

```bash
journalctl -u picoclaw-manager --no-pager -n 30
```

### Follow live log

> ⚠️ **JANGAN jalankan dari exec tool** — streaming tidak akan selesai.

```bash
journalctl -u picoclaw-manager -f
```

## Rules

1. **Prefer curl API** — untuk start/stop/restart/status/update, gunakan curl ke `localhost:8321`.
2. **Gunakan `journalctl -n N`** untuk log — jangan pakai `-f` dari exec tool.
3. **Install cukup sekali** — setup script download semua dari GitHub.
4. **Re-install aman** — menjalankan `install` ulang akan restart service dengan script terbaru.
5. **Update binary via API** — gunakan `/api/picoclaw/update` untuk update tanpa SSH manual.
6. **update_picoclaw.sh harus ada** — pastikan file ini ada di `/opt/picoclaw/` untuk update via manager.

## Config

- **Binary PicoClaw**: `~/.local/bin/picoclaw`
- **Config**: `~/.picoclaw/config.json`
- **Port Manager API**: `8321`
- **Install dir**: `/opt/picoclaw/`
- **Service**: `picoclaw-manager.service`
- **Repo**: `muava12/picoclaw-fork`
