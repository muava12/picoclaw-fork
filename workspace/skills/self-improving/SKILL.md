---
name: self-improving
description: Catat kesalahan, koreksi, dan pelajaran agar agent terus belajar dari pengalaman. Otomatis aktif saat terjadi error atau user mengoreksi.
metadata: {"nanobot":{"emoji":"🧠"}}
---

# Self-Improving Agent

Skill ini membuat agent belajar dari kesalahan dan koreksi. Setiap error, koreksi user, atau knowledge gap dicatat ke file log, dan pelajaran penting dipromosikan ke MEMORY.md agar persisten lintas sesi.

> Diadaptasi dari [self-improving-agent di ClawHub](https://clawhub.ai/pskoett/self-improving-agent) untuk PicoClaw.

## When to use (trigger phrases)

Skill ini aktif **otomatis** saat agent mendeteksi situasi berikut:

**Kesalahan:**
- Command gagal (non-zero exit code)
- Error, exception, atau stack trace
- Timeout atau connection failure

**Koreksi user:**
- "Bukan, yang bener..."
- "Salah, seharusnya..."
- "Actually, it should be..."

**Knowledge gap:**
- User kasih info yang agent belum tahu
- Dokumentasi ternyata outdated
- Perilaku API berbeda dari yang agent kira

**Feature request:**
- "Bisa gak kamu..."
- "Bagaimana kalau..."
- "I wish you could..."

## Storage

Semua log disimpan di `skills/self-improving/data/`:

```
skills/self-improving/data/
├── LEARNINGS.md         # Koreksi, knowledge gaps, best practices
├── ERRORS.md            # Command failures, exceptions
└── FEATURE_REQUESTS.md  # User-requested capabilities
```

## Quick Reference

| Situasi | Aksi |
|---------|------|
| Command/operasi gagal | Catat ke `ERRORS.md` |
| User mengoreksi agent | Catat ke `LEARNINGS.md` (kategori: `correction`) |
| User minta fitur baru | Catat ke `FEATURE_REQUESTS.md` |
| API/tool eksternal gagal | Catat ke `ERRORS.md` dengan detail integrasi |
| Pengetahuan agent outdated | Catat ke `LEARNINGS.md` (kategori: `knowledge_gap`) |
| Ditemukan cara yang lebih baik | Catat ke `LEARNINGS.md` (kategori: `best_practice`) |
| Pelajaran bisa diterapkan luas | Promote ke `MEMORY.md` |

## Format Log

### Learning Entry

Append ke `skills/self-improving/data/LEARNINGS.md`:

```markdown
## [LRN-YYYYMMDD-XXX] category

**Logged**: ISO-8601 timestamp
**Priority**: low | medium | high | critical
**Status**: pending

### Summary
Satu baris ringkasan pelajaran

### Details
Konteks lengkap: apa yang terjadi, apa yang salah, apa yang benar

### Suggested Action
Fix atau improvement spesifik

### Metadata
- Source: conversation | error | user_feedback
- Related Files: path/to/file
- Tags: tag1, tag2
---
```

### Error Entry

Append ke `skills/self-improving/data/ERRORS.md`:

```markdown
## [ERR-YYYYMMDD-XXX] skill_or_command_name

**Logged**: ISO-8601 timestamp
**Priority**: high
**Status**: pending

### Summary
Ringkasan singkat apa yang gagal

### Error
```
Pesan error atau output aktual
```

### Context
- Command yang dijalankan
- Parameter yang dipakai
- Detail environment jika relevan

### Suggested Fix
Jika teridentifikasi, apa yang bisa memperbaiki ini

### Metadata
- Reproducible: yes | no | unknown
- Related Files: path/to/file
---
```

### Feature Request Entry

Append ke `skills/self-improving/data/FEATURE_REQUESTS.md`:

```markdown
## [FEAT-YYYYMMDD-XXX] capability_name

**Logged**: ISO-8601 timestamp
**Priority**: medium
**Status**: pending

### Requested Capability
Apa yang user ingin lakukan

### User Context
Kenapa mereka butuh ini, masalah apa yang ingin dipecahkan

### Suggested Implementation
Bagaimana ini bisa dibangun

### Metadata
- Frequency: first_time | recurring
---
```

## ID Format

Format: `TYPE-YYYYMMDD-XXX`

- TYPE: `LRN` (learning), `ERR` (error), `FEAT` (feature)
- YYYYMMDD: Tanggal saat ini
- XXX: Nomor urut (001, 002, dst)

## Resolve Entry

Saat issue sudah diperbaiki, update entry:

1. Ubah `**Status**: pending` → `**Status**: resolved`
2. Tambah blok resolusi:

```markdown
### Resolution
- **Resolved**: 2026-02-24T12:00:00Z
- **Notes**: Penjelasan singkat apa yang dilakukan
```

## Promote ke MEMORY.md

Saat pelajaran applicable secara luas (bukan one-off fix), promosikan ke `MEMORY.md`:

### Kapan Promote

- Pelajaran berlaku untuk banyak skill/fitur
- Pengetahuan penting yang harus diingat lintas sesi
- Mencegah kesalahan berulang
- Mendokumentasikan konvensi khusus user

### Cara Promote

1. **Ringkas** pelajaran jadi rule singkat
2. **Tambahkan** ke section yang tepat di `MEMORY.md`
3. **Update** entry original: ubah `**Status**` → `promoted`

### Contoh

**Learning entry (verbose):**
> PicoClaw exec tool memblokir pattern `${}` dan `> /dev/null`. Command cron harus ditulis sederhana tanpa shell metacharacters.

**Di MEMORY.md (ringkas):**
```markdown
## PicoClaw Safety Guard
- Exec tool memblokir: `${}`, `$()`, `> /dev/null`, `source *.sh`, `sudo`, `eval`
- Command cron harus ditulis sederhana: `bash scripts/file.sh "arg"`
```

## Recurring Pattern

Jika mencatat pelajaran yang mirip dengan entry yang sudah ada:

1. **Cari dulu**: apakah sudah ada entry serupa
2. **Link**: tambah `See Also: ERR-YYYYMMDD-XXX` di Metadata
3. **Naikkan priority** jika issue terus berulang
4. **Promote** jika sudah 3x berulang → masukkan ke `MEMORY.md`

## Periodic Review

Review `skills/self-improving/data/` di saat-saat natural:

- Sebelum mulai task besar baru
- Setelah menyelesaikan fitur
- Saat bekerja di area yang pernah ada masalah
- Mingguan selama development aktif

## Rules

1. **Log segera** — konteks paling segar tepat setelah masalah terjadi
2. **Spesifik** — agent di sesi berikutnya harus bisa memahami dengan cepat
3. **Sertakan langkah reproduksi** — terutama untuk error
4. **Sarankan fix konkret** — bukan sekadar "perlu investigasi"
5. **Promote agresif** — jika ragu, masukkan ke MEMORY.md
6. **Jangan log hal sepele** — hanya yang non-obvious dan bermanfaat
7. **Hindari menyimpan data sensitif** — jangan log API key, password, atau data pribadi
