---
name: system-monitor
description: Monitor kesehatan sistem — CPU, RAM, disk, suhu, dan uptime. Kirim alert via ntfy jika ada masalah.
metadata: {"nanobot":{"emoji":"📊"}}
---

# System Monitor

Monitor kesehatan STB/server: CPU, RAM, disk, suhu, dan uptime. Bisa dijalankan manual atau dijadwalkan via cron tool.

## When to use (trigger phrases)

- "cek sistem" / "system status"
- "health check" / "kesehatan server"
- "berapa suhu CPU?" / "CPU temperature"
- "disk penuh?" / "free disk space"
- "RAM usage" / "memory usage"
- "uptime" / "sudah jalan berapa lama?"
- "monitor sistem setiap jam"

## Perintah Manual

### Health check lengkap (via exec tool)

```bash
bash skills/system-monitor/scripts/health_check.sh
```

Output berupa ringkasan singkat yang mudah dibaca:

```
🖥️ SYSTEM HEALTH REPORT
========================
📅 2026-02-24 12:00 WIB
⏱️ Uptime: 3 days, 2:15
🔥 CPU Temp: 52°C ✅
💻 CPU Load: 0.85 (1 core)
🧠 RAM: 412MB / 1024MB (40%) ✅
💾 Disk: 4.2GB / 14.5GB (29%) ✅
🌐 Network: ✅ connected
========================
Status: ALL OK ✅
```

### Cek komponen spesifik (via exec tool)

```bash
bash skills/system-monitor/scripts/health_check.sh --cpu
bash skills/system-monitor/scripts/health_check.sh --memory
bash skills/system-monitor/scripts/health_check.sh --disk
bash skills/system-monitor/scripts/health_check.sh --temp
bash skills/system-monitor/scripts/health_check.sh --network
```

## Jadwal Otomatis (via cron tool)

### Health report harian pagi

```json
{"action": "add", "message": "📊 System Health Report", "command": "bash skills/system-monitor/scripts/health_check.sh", "cron_expr": "0 7 * * *"}
```

### Monitor suhu tiap 6 jam

```json
{"action": "add", "message": "🌡️ Temp check", "command": "bash skills/system-monitor/scripts/health_check.sh --temp", "every_seconds": 21600}
```

### Health check + ntfy alert (pakai reminder skill)

Jika ingin health report dikirim ke HP juga via ntfy, buat 2 job:

**Job 1 — Report ke Telegram:**
```json
{"action": "add", "message": "📊 Daily health", "command": "bash skills/system-monitor/scripts/health_check.sh", "cron_expr": "0 7 * * *"}
```

**Job 2 — Alert ke ntfy (hanya jika ada masalah):**
```json
{"action": "add", "message": "ntfy: health alert", "command": "bash skills/system-monitor/scripts/health_alert.sh", "every_seconds": 3600}
```

Script `health_alert.sh` hanya mengirim notifikasi jika ada warning/critical.

## Threshold (Default)

| Metrik | Warning | Critical |
|--------|---------|----------|
| CPU Temp | > 70°C | > 80°C |
| RAM Usage | > 80% | > 90% |
| Disk Usage | > 80% | > 90% |
| CPU Load (1-min) | > 2.0 | > 4.0 |

Threshold bisa dikustomisasi di `skills/system-monitor/data/config`.

## Custom Config

Buat `skills/system-monitor/data/config` jika ingin override default:

```bash
mkdir -p skills/system-monitor/data
cat > skills/system-monitor/data/config << 'ENDCONF'
TEMP_WARN=65
TEMP_CRIT=75
RAM_WARN=85
RAM_CRIT=95
DISK_WARN=85
DISK_CRIT=95
LOAD_WARN=3.0
LOAD_CRIT=5.0
ENDCONF
```

## Rules

1. **Prefer script** — selalu gunakan `health_check.sh`, jangan `top` atau `htop` (bisa hang).
2. **Jangan pakai `-f` flag** — streaming command tidak cocok untuk exec tool.
3. **Alert cukup summary** — jangan dump output panjang, cukup status singkat.
4. **Kombinasikan dengan ntfy** — gunakan `health_alert.sh` untuk push notification saat ada masalah.
