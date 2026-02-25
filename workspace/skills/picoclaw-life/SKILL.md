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
```

- `picoclaw_manager.py` jalan sebagai systemd service (`picoclaw-manager`)
- REST API untuk kontrol gateway (start/stop/restart/status)
- REST API untuk check update dan update binary otomatis
- Auto-start gateway saat service dimulai

## API Endpoints

| Method | Endpoint | Fungsi |
|--------|----------|--------|
| `GET` | `/api/health` | Health check manager |
| `GET` | `/api/picoclaw/status` | Status gateway (running, pid, uptime, recent logs) |
| `GET` | `/api/picoclaw/check-update` | Cek apakah ada versi baru di GitHub releases |
| `POST` | `/api/picoclaw/start` | Start gateway |
| `POST` | `/api/picoclaw/stop` | Stop gateway |
| `POST` | `/api/picoclaw/restart` | Restart gateway |
| `POST` | `/api/picoclaw/update` | Download & install versi terbaru (auto-stop gateway) |

## Setup (Pertama Kali)

Script otomatis download `picoclaw_manager.py` dari GitHub — cukup satu perintah:

```bash
curl -fsSL https://raw.githubusercontent.com/muava12/picoclaw-fork/main/setup_picoclaw_manager.sh | bash -s install
```

Ini akan:
- Download `picoclaw_manager.py` dari GitHub ke `/opt/picoclaw/`
- Buat systemd service `picoclaw-manager`
- Enable auto-start on boot
- Start (atau restart jika sudah ada) service

### Verifikasi

```bash
curl -s http://localhost:8321/api/health
```

## Install / Update Binary PicoClaw

Binary picoclaw sendiri di-install terpisah:

```bash
curl -fsSL https://raw.githubusercontent.com/muava12/picoclaw-fork/main/install_picoclaw.sh | bash
```

Script ini otomatis **stop gateway yang sedang berjalan** sebelum replace binary. User harus start manual setelah update.

Atau update via manager API (otomatis download dari GitHub releases):

```bash
# Cek apakah ada versi baru
curl -s http://localhost:8321/api/picoclaw/check-update

# Update langsung (auto-stop gateway, download, replace binary)
curl -s -X POST http://localhost:8321/api/picoclaw/update
```

## Update Manager Script

Untuk update picoclaw_manager.py ke versi terbaru:

```bash
curl -fsSL https://raw.githubusercontent.com/muava12/picoclaw-fork/main/setup_picoclaw_manager.sh | bash -s update
```

Atau jalankan ulang install (aman, akan restart service):

```bash
curl -fsSL https://raw.githubusercontent.com/muava12/picoclaw-fork/main/setup_picoclaw_manager.sh | bash -s install
```

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

### Restart gateway

```bash
curl -s -X POST http://localhost:8321/api/picoclaw/restart
```

### Start/stop gateway

```bash
curl -s -X POST http://localhost:8321/api/picoclaw/start
curl -s -X POST http://localhost:8321/api/picoclaw/stop
```

### Lihat log terakhir (via systemd)

```bash
journalctl -u picoclaw-manager --no-pager -n 30
```

### Follow live log (via systemd)

> ⚠️ **JANGAN jalankan dari exec tool** — streaming tidak akan selesai.

```bash
journalctl -u picoclaw-manager -f
```

## CI/CD

Build otomatis via GitHub Actions (`build-fork.yml`):
- Trigger: push ke `main` atau manual dispatch
- Matrix build: **ARM64** + **AMD64** secara paralel
- Release: kedua binary diupload ke satu tag release (`v0.1.2-fork-0.N`)
- Notifikasi: ntfy push saat build start/success/fail

Untuk push tanpa trigger CI, tambahkan `[skip ci]` di commit message.

## Rules

1. **Prefer curl API** — untuk start/stop/restart/status/update, gunakan curl ke `localhost:8321` karena lebih cepat dan tidak butuh sudo.
2. **Gunakan `journalctl -n N`** untuk log — jangan pakai `-f` (streaming) dari exec tool.
3. **Install cukup sekali** — setup script download semua dari GitHub, tidak perlu file lokal.
4. **Re-install aman** — menjalankan `install` ulang akan restart service dengan script terbaru.
5. **Update binary via API** — gunakan `/api/picoclaw/update` untuk update binary tanpa SSH manual.

## Config

- **Binary PicoClaw**: `~/.local/bin/picoclaw`
- **Config**: `~/.picoclaw/config.json`
- **Port Manager API**: `8321`
- **Install dir**: `/opt/picoclaw/`
- **Service**: `picoclaw-manager.service`
- **Repo**: `muava12/picoclaw-fork`
