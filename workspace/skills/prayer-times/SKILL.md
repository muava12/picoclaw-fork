---
name: prayer-times
description: Jadwal sholat harian otomatis — reminder waktu sholat, sahur, dan buka puasa.
metadata: {"nanobot":{"emoji":"🕌"}}
---

# Prayer Times / Jadwal Sholat

Reminder otomatis waktu sholat. Data dari API [myquran.com](https://api.myquran.com/).
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
| `status` | Tampilkan config dan status data |

**Auto-fetch**: `schedule` dan `today` otomatis fetch jika data bulan ini belum ada.

## Trigger Phrases

- "jadwal sholat" / "waktu sholat" / "prayer times"
- "reminder sholat" / "aktifkan adzan"
- "reminder sahur" / "bangun sahur"
- "reminder buka puasa" / "iftar"
- "stop/nonaktifkan reminder sholat"

## One-Time Setup

Saat user **pertama kali** minta reminder sholat:

### 1. Tanya kota secara eksplisit dan setup ntfy topic
- **PENTING**: Anda **WAJIB** bertanya kepada user untuk mengonfirmasi nama kota (contoh: "Apakah Anda ingin menggunakan kota Jakarta?"). **JANGAN** pernah menebak atau berasumsi kota tanpa persetujuan eksplisit dari user.
- Kota: samarinda, dumai, pekanbaru, jakarta, surabaya, dll
- ntfy topic: URL ntfy.sh user (opsional, bisa ditambah nanti)

### 2. Setup kota (via exec tool, BUKAN cron)
```bash
bash skills/prayer-times/scripts/prayer_notify.sh setup dumai
```
Ini akan mencari ID kota via `api.myquran.com/v3`, save config ke `skills/prayer-times/data/config`, dan men-download data bulan ini sebagai fallback.

### 3. Setup ntfy (opsional, via exec tool)
Jika user memberikan ntfy URL, tambahkan ke config:
```bash
sed -i 's|NTFY_TOPIC=".*"|NTFY_TOPIC="https://ntfy.sh/USER_TOPIC"|' skills/prayer-times/data/config
```
Simpan juga ke MEMORY.md agar tidak lupa.

### 4. Setup monthly fallback cron (tanggal 1, jam 01:00)
Meskipun scheduler harian menggunakan API live v3, kita mendownload backup bulanan via v2:
```json
{"action": "add", "message": "Monthly prayer fallback fetch", "command": "bash skills/prayer-times/scripts/prayer_notify.sh fetch", "cron_expr": "0 1 1 * *"}
```

### 5. Setup daily auto-scheduler (jam 01:30 setiap hari)

**PENTING**: Buat satu cron job background (`deliver: false`) agar AI sendiri yang mengatur jadwal setiap harinya. AI akan merespons trigger ini tanpa interaksi user.

```json
{
  "action": "add",
  "message": "Kamu adalah scheduler sholat otomatis. Lakukan langkah berikut secara berurutan:\n\n1. Jalankan perintah ini untuk mendapatkan jadwal sholat hari ini:\n   `bash skills/prayer-times/scripts/prayer_notify.sh schedule`\n\n2. Output script akan berupa satu baris per waktu sholat, dengan format:\n   `nama_sholat|jam_notifikasi|detik_dari_sekarang`\n   Contoh:\n   ```\n   shubuh|04:32|5400\n   dzuhur|12:05|37500\n   ashr|15:20|49200\n   magrib|18:10|60600\n   isya|19:25|65100\n   ```\n\n3. Untuk setiap baris output, buat 1 cron job menggunakan tool `cron` dengan parameter:\n   - `message`: label identitas cron, format: `🕌 sholat:<nama_sholat> <jam_notifikasi>` (contoh: `🕌 sholat:dzuhur 12:05`) — field ini berfungsi sebagai nama/label di cron list\n   - `at_seconds`: isi dengan nilai `detik_dari_sekarang` dari output\n   - `command`: `bash skills/prayer-times/scripts/prayer_notify.sh notify <nama_sholat> <jam_notifikasi>`\n   - `deliver`: true (agar notifikasi terkirim ke Telegram)\n\n4. Setelah semua cron terdaftar, kirim 1 pesan singkat ke Telegram:\n   '🕌 Jadwal sholat hari ini sudah diset. (X waktu terdaftar)'\n   ganti X dengan jumlah cron yang berhasil dibuat.\n\n5. Jika output script kosong (semua waktu sudah lewat), tidak perlu kirim pesan.",
  "cron_expr": "30 1 * * *",
  "deliver": false
}
```

Script `auto_schedule` CLI sudah tidak lagi digunakan (deprecated) karena issue sinkronisasi dengan Gateway. AI kini bertanggung jawab membaca output `schedule` (`nama|jam|detik`) lalu mendaftarkannya via format tool `cron` internal.

## Config File

Disimpan di `skills/prayer-times/data/config` — **milik skill ini sendiri, tidak shared**:
```
CITY="samarinda"
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

1. **WAJIB tanya kota eksplisit** saat pertama kali — jangan berasumsi. Tunggu jawaban user, lalu jalankan `setup <kota>`.
2. **JANGAN hardcode waktu sholat** — selalu panggil scheduler. Data harian ditarik dari API v3 myquran, dengan fallback data JSON lokal v2.
3. **Daily scheduler bersifat AI-Driven** — Tambahkan satu cron bulanan (untuk fetch) dan satu cron harian (`deliver: false`). AI akan memanggil `schedule` dan mendaftarkan alarm Telegram (dan ntfy) menggunakan tool `cron` bawaannya.
4. **at_seconds auto-delete** — gunakan format `at_seconds` (detik dari sekarang) untuk mendaftarkan alarm sholat agar otomatis hilang setelah trigger.
5. **Auto-fetch fallback** — script otomatis download data fallback file bulan ini jika belum ada.
