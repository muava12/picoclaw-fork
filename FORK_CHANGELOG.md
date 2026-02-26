# Repositori PicoClaw-Fork Changelog

Dokumen ini mencatat seluruh penambahan atau modifikasi fitur independen yang ada pada repositori fork ini (branch `main`). Pada proses re-basis atau "clean start", perhatikan komponen-komponen berikut untuk diaplikasikan kembali di atas source code *upstream* murni.

## 1. Modifikasi Independen (Tidak Menyentuh Kode Utama)

### PicoClaw Manager (Go)
- **`cmd/manager/main.go`**: Implementasi server dan CLI (`piman`) pengganti manager berbasis Python dengan efisiensi RAM tinggi.
- **`setup_picoclaw_manager.sh`**: Skrip pengaturan API / daemon service systemd untuk manager, disesuaikan dengan eksekusi binary `piman` (menggantikan versi Python lama). 
- **`install_picoclaw.sh`**: Dimodifikasi dengan flag instalasi manager interaktif, jika string versi berformat 'Fork', pengguna akan diprompt untuk opsi menginstal PicoClaw Manager. Logic deteksi versi upstream juga diubah untuk mem-filter out release khusus (seperti `piman-v0.0.1`).

### Sistem Build, Makefile, dan Rilis CI
- **`Makefile`**: Tambahan blok ruleset untuk mem-build target binary `manager` (GOOS/GOARCH multi-platform).
- **`.goreleaser.yaml`**: Modifikasi blok `builds` dimana proses build khusus manager diabaikan/di-exclude dari eksekusi binary picoclaw utama.
- **`.github/workflows/build-fork.yml`**: Membatasi pencarian dan ekstraksi tag *Latest Release* dengan parameter `--match="v[0-9]*"` agar GitHub Actions tetap pada siklus semver picoclaw standard, mengabaikan tag khusus `piman-*`.
- **`.github/workflows/release-manager.yml`**: Pipeline Actions yang didedikasikan secara independen untuk merilis aset PicoClaw Manager saja.

### Voice Bridge
- **`picoclaw_voice_bridge.py`** & **`setup_voice_bridge.sh`**: Layanan integrasi microphone dan Deepgram Transcription model voice input-to-text.

### Skills Customisations
Semua file `.md` atau skrip modifikasi di dalam folder `workspace/skills/`:
- `picoclaw-life`
- `prayer-times` (dengan skrip notifikasi stateless sendiri `ntfy_send.sh`)
- `reminder` (dengan skrip notifikasi stateless sendiri `ntfy_send.sh`)
- `self-improving` (dengan dokumen pembelajaran)
- `system-monitor` (dengan skrip cek suhu & RAM)

## 2. Modifikasi Bersifat Isolatif pada Sistem PicoClaw Core

- **Pembacaan Waktu & Timezone (`pkg/config/config.go`)**: Penambahan field struktur `Timezone` di *AgentDefaults* yang menavigasi `time.Local` secara global.
- **Prioritas Pencarian Web (`pkg/tools/web.go`)**: Diubah blok fallback `NewWebSearchTool` agar menjadikan `TavilySearchProvider` selalu diperiksa sebagai urutan no.1 apabila tersedia (mendahului Perplexity/Brave/DDG).
- **Manajemen Fallback & Skema Validasi Provider (`pkg/providers/...`)**:
  - `pkg/providers/fallback.go`: Modifikasi handling `err` dengan pemeriksaan tipe error untuk melakukan skip atau mencoba kandidat substitusi.
  - `pkg/providers/error_classifier.go`: Validasi logik *IsModelInvalid()* diperbaiki agar mendeteksi keyword unik yang me-reject nama model asing dari OpenRouter atau API kompetitif lainnya.
  - `pkg/providers/cooldown.go`: Rate-limit dan penundaan dieksekusi berdasarkan referensi ID `model`/`alias` (unik setiap provider), bukan *scope* provider tunggalnya (mencegah API key 1 pool lumpuh total semua variannya).
  - `pkg/providers/openai_compat/provider.go`: Fix parsing input config *OpenRouter* sehingga endpoint URI & prefix nama model di *upstream* terkelola dengan baik.
- **Dinamika Provider Matching (`pkg/agent/loop.go`)**: Penambahan *mapping logic* dalam fallback list; mendeteksi nama ID model baru untuk memastikan struktur `CreateProviderFromConfig` diinisialisasi berdasarkan workspace *default agent* config lokal secara tepat.

---
> **Catatan Rekonstruksi**: Aplikasikan kembali fitur bagian (1) secara mentah tanpa modifikasi (Copy-Paste langsung), sedangkan fitur bagian (2) disisipkan secara *surgical* (perlahan per baris) pada core code untuk meminimalisasi crash dengan format teranyar *upstream/main*.
