---
name: prayer-times
description: Jadwal sholat otomatis — reminder waktu sholat, sahur, dan buka puasa. Data dari jadwalsholatorg.
metadata: {"nanobot":{"emoji":"🕌"}}
---

# Prayer Times / Jadwal Sholat

Reminder otomatis waktu sholat. Data dari [jadwalsholatorg](https://github.com/lakuapik/jadwalsholatorg).
Notifikasi dikirim ke **Telegram + ntfy**.

## Script

Lokasi: `skills/prayer-times/scripts/prayer_notify.sh`

```bash
chmod +x skills/prayer-times/scripts/prayer_notify.sh
```

| Command | Fungsi |
|---------|--------|
| `setup <city>` | Set kota + fetch data awal **(wajib pertama kali)** |
| `fetch` | Download JSON bulan ini |
| `today` | Tampilkan jadwal hari ini |
| `schedule [prayers...]` | Output `nama\|HH:MM\|detik` untuk sholat yang belum lewat |
| `notify <prayer> <time>` | Kirim ke ntfy + cetak pesan untuk Telegram |
| `auto_schedule <channel> <chat_id>` | **Tulis cron job via picoclaw CLI (tanpa AI)** |
| `status` | Tampilkan config dan status data |

**Auto-fetch**: `schedule`, `today`, dan `auto_schedule` otomatis fetch jika data bulan ini belum ada.

## Trigger Phrases

- "jadwal sholat" / "waktu sholat" / "prayer times"
- "reminder sholat" / "aktifkan adzan"
- "reminder sahur" / "bangun sahur"
- "reminder buka puasa" / "iftar"
- "stop/nonaktifkan reminder sholat"

## One-Time Setup

Saat user **pertama kali** minta reminder sholat:

### 1. Tanya kota dan ntfy topic
- Kota: samarinda, dumai, pekanbaru, jakarta-pusat, surabaya, dll
- ntfy topic: URL ntfy.sh user (opsional, bisa ditambah nanti)

### 2. Setup kota (via exec tool, BUKAN cron)
```bash
bash skills/prayer-times/scripts/prayer_notify.sh setup dumai
```
Ini akan save config ke `skills/prayer-times/data/config` dan fetch data bulan ini.

### 3. Setup ntfy (opsional, via exec tool)
Jika user memberikan ntfy URL, tambahkan ke config:
```bash
sed -i 's|NTFY_TOPIC=".*"|NTFY_TOPIC="https://ntfy.sh/USER_TOPIC"|' skills/prayer-times/data/config
```
Simpan juga ke MEMORY.md agar tidak lupa.

### 4. Setup monthly fetch cron (tanggal 1, jam 01:00)
```json
{"action": "add", "message": "Monthly prayer fetch", "command": "bash skills/prayer-times/scripts/prayer_notify.sh fetch", "cron_expr": "0 1 1 * *"}
```

### 5. Setup daily auto-scheduler (jam 01:30 setiap hari)

**PENTING**: Gunakan `command` mode agar script langsung menulis cron job. AI **tidak** perlu terlibat.

```json
{
  "action": "add",
  "message": "Daily prayer auto-schedule",
  "command": "bash skills/prayer-times/scripts/prayer_notify.sh auto_schedule telegram CHAT_ID",
  "cron_expr": "30 1 * * *"
}
```

Ganti `CHAT_ID` dengan chat ID user yang meminta (tersedia di session context).
Script akan menambah reminder sholat ke cron via `picoclaw cron add`, tanpa perlu AI.

## Config File

Disimpan di `skills/prayer-times/data/config` — **milik skill ini sendiri, tidak shared**:
```
CITY="dumai"
SAHUR_MINS="30"
IFTAR_MINS="10"
PRAYERS="shubuh dzuhur ashr magrib isya"
NTFY_TOPIC="https://ntfy.sh/user-topic-here"
```

User bisa minta ubah via exec tool:
- Tambah sahur+iftar: edit PRAYERS di config lalu restart daily scheduler
- Ganti kota: `prayer_notify.sh setup <kota_baru>`
- Ganti ntfy: edit NTFY_TOPIC di config

## Timezone

Script otomatis mapping kota Indonesia ke timezone yang benar:

| Zona | Contoh Kota | TZ |
|------|-------------|-----|
| WIB (UTC+7) | dumai, pekanbaru, jakarta, surabaya | Asia/Jakarta |
| WITA (UTC+8) | samarinda, makassar, denpasar | Asia/Makassar |
| WIT (UTC+9) | jayapura, ambon, manokwari | Asia/Jayapura |

Ini penting agar epoch calculation sesuai waktu lokal kota, bukan system timezone.

## Waktu yang Tersedia

| Nama | Keterangan | Perlu diminta user? |
|------|------------|---------------------|
| `shubuh` | Waktu Shubuh | Default aktif |
| `dzuhur` | Waktu Dzuhur | Default aktif |
| `ashr` | Waktu Ashar | Default aktif |
| `magrib` | Waktu Maghrib | Default aktif |
| `isya` | Waktu Isya | Default aktif |
| `sahur` | 30 menit sebelum Shubuh | Ya — untuk Ramadan |
| `iftar` | 10 menit sebelum Maghrib | Ya — untuk Ramadan |

## Rules

1. **Tanya kota** saat pertama kali — jangan asumsi. Jalankan `setup <kota>` sebelum apapun.
2. **JANGAN hardcode waktu sholat** — selalu baca dari script output. Waktu berubah setiap hari.
3. **Gunakan auto_schedule** untuk daily scheduler — ini menulis cron job langsung tanpa AI.
4. **at_seconds auto-delete** — one-time job otomatis hilang setelah trigger.
5. **Auto-fetch** — script otomatis download data jika file bulan ini belum ada.
