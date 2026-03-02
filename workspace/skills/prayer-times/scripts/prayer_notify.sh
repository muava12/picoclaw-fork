#!/bin/bash
# prayer_notify.sh — Fetch, schedule, and send prayer time notifications
# Usage:
#   prayer_notify.sh fetch                  — Download current month's JSON
#   prayer_notify.sh today                  — Show today's prayer times
#   prayer_notify.sh schedule [prayers...]  — Output seconds-from-now for each prayer
#   prayer_notify.sh notify <prayer> <time> — Send notification via ntfy + stdout
#   prayer_notify.sh setup <city>           — Set city and fetch initial data
#   prayer_notify.sh status                 — Show current config and data status
#
# Config file: skills/prayer-times/data/config (co-located with skill)
# Auto-fetch: schedule command auto-fetches if data is missing or stale

set -euo pipefail


# Resolve paths relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="${PRAYER_DATA_DIR:-$SKILL_DIR/data}"
CONFIG_FILE="$DATA_DIR/config"

# ntfy_send.sh lives alongside this script
NTFY_SEND="${SCRIPT_DIR}/ntfy_send.sh"

mkdir -p "$DATA_DIR"

# ---- Load config ----

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # Source config file (contains CITY=, CITY_ID=, CITY_ID_V2=, SAHUR_MINS=, IFTAR_MINS=, PRAYERS=)
        . "$CONFIG_FILE"
    fi
    CITY="${CITY:-samarinda}"
    CITY_ID="${CITY_ID:-}"
    CITY_ID_V2="${CITY_ID_V2:-}"
    SAHUR_MINS="${SAHUR_MINS:-30}"
    IFTAR_MINS="${IFTAR_MINS:-10}"
    PRAYERS="${PRAYERS:-shubuh dzuhur ashr magrib isya}"
    NTFY_TOPIC="${NTFY_TOPIC:-}"
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
CITY="$CITY"
CITY_ID="$CITY_ID"
CITY_ID_V2="$CITY_ID_V2"
SAHUR_MINS="$SAHUR_MINS"
IFTAR_MINS="$IFTAR_MINS"
PRAYERS="$PRAYERS"
NTFY_TOPIC="$NTFY_TOPIC"
EOF
    echo "Config saved to $CONFIG_FILE"
}

# ---- Timezone mapping ----

# Map Indonesian city to IANA timezone.
# jadwalsholatorg data is in the city's local time,
# so we need the correct TZ for epoch calculation.
city_to_tz() {
    local city="$1"
    case "$city" in
        # WIB (UTC+7) — Sumatra, Jawa, Kalimantan Barat/Tengah
        dumai|pekanbaru|medan|padang|palembang|jambi|bengkulu|lampung|\
        banda-aceh|batam|tanjung-pinang|pangkal-pinang|bandar-lampung|\
        jakarta-pusat|jakarta-selatan|jakarta-barat|jakarta-timur|jakarta-utara|\
        bogor|depok|tangerang|bekasi|bandung|semarang|yogyakarta|surabaya|\
        malang|solo|cirebon|serang|pontianak|palangka-raya)
            echo "Asia/Jakarta" ;;
        # WITA (UTC+8) — Kalimantan Selatan/Timur/Utara, Sulawesi, Bali, NTB, NTT
        samarinda|makassar|denpasar|balikpapan|banjarmasin|manado|gorontalo|\
        palu|kendari|mamuju|mataram|kupang|tarakan|bontang)
            echo "Asia/Makassar" ;;
        # WIT (UTC+9) — Papua, Maluku
        jayapura|ambon|manokwari|sorong|ternate|tual|merauke|fakfak)
            echo "Asia/Jayapura" ;;
        *)
            # Default: try to infer from system TZ, fallback to WIB
            echo "${TZ:-Asia/Jakarta}" ;;
    esac
}

# ---- Helper functions ----

get_json_path() {
    local year month
    year=$(date +%Y)
    month=$(date +%m)
    echo "$DATA_DIR/${CITY}_${year}_${month}.json"
}

is_data_current() {
    local json_path
    json_path=$(get_json_path)
    [ -f "$json_path" ]
}

ensure_data() {
    # Auto-fetch if data for current month is missing
    if ! is_data_current; then
        echo "Data bulan ini belum ada, auto-fetching..." >&2
        cmd_fetch
    fi
}

now_epoch() {
    date +%s
}

today_date() {
    date +%Y-%m-%d
}

# ---- Commands ----

cmd_setup() {
    local city="${1:-}"
    if [ -z "$city" ]; then
        echo "Usage: prayer_notify.sh setup <city>"
        echo ""
        echo "PENTING: Jangan asumsikan kota, selalu pastikan user menyebutkan kota eksplisit."
        echo "Contoh kota: samarinda, dumai, pekanbaru, jakarta, surabaya"
        exit 1
    fi

    # URL encode city name for API request
    local enc_city
    enc_city=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$city'))")

    # Fetch API v3 City ID
    local res_v3
    res_v3=$(curl -sL "https://api.myquran.com/v3/sholat/kota/cari/$enc_city" || echo "")
    local cid_v3
    cid_v3=$(echo "$res_v3" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['data'][0]['id'] if data.get('status') and data.get('data') else '')" 2>/dev/null || echo "")

    # Fetch API v2 City ID
    local res_v2
    res_v2=$(curl -sL "https://api.myquran.com/v2/sholat/kota/cari/$enc_city" || echo "")
    local cid_v2
    cid_v2=$(echo "$res_v2" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['data'][0]['id'] if data.get('status') and data.get('data') else '')" 2>/dev/null || echo "")

    if [ -z "$cid_v3" ] && [ -z "$cid_v2" ]; then
        echo "ERROR: Kota '$city' tidak ditemukan di database API myquran.com."
        exit 1
    fi

    CITY="$city"
    CITY_ID="$cid_v3"
    CITY_ID_V2="$cid_v2"
    save_config

    echo "Kota diset ke: $CITY (API V3 ID: ${CITY_ID:--}, API V2 ID: ${CITY_ID_V2:--})"
    echo "Mengambil jadwal sholat fallback bulanan..."
    cmd_fetch

    echo ""
    echo "Setup selesai! Gunakan:"
    echo "  prayer_notify.sh today      — lihat jadwal hari ini"
    echo "  prayer_notify.sh schedule   — hitung waktu reminder"
}

cmd_fetch() {
    if [ -z "$CITY_ID_V2" ]; then
        echo "ERROR: CITY_ID_V2 tidak ada di config. Jalankan setup terlebih dahulu."
        exit 1
    fi

    local year month json_path url
    year=$(date +%Y)
    month=$(date +%m)
    json_path=$(get_json_path)
    url="https://api.myquran.com/v2/sholat/jadwal/$CITY_ID_V2/${year}/${month}"

    echo "Fetching fallback (v2): ${CITY} ${year}-${month}..."
    if curl -sf "$url" -o "$json_path"; then
        local count
        count=$(python3 -c "import json; data=json.load(open('$json_path')); print(len(data.get('data',{}).get('jadwal',[])))" 2>/dev/null || echo "?")
        echo "OK: $json_path ($count hari)"
    else
        echo "ERROR: Gagal fetch dari $url"
        exit 1
    fi
}

cmd_today() {
    ensure_data
    local json_path today url_v3
    json_path=$(get_json_path)
    today=$(today_date)
    
    python3 -c "
import urllib.request, json, sys

today = '$today'
city_id_v3 = '$CITY_ID'
city_id_v2 = '$CITY_ID_V2'
city_name = '$CITY'
json_path = '$json_path'

entry = None

# Try V3 Live API first
if city_id_v3:
    url_v3 = f'https://api.myquran.com/v3/sholat/jadwal/{city_id_v3}/' + today.replace('-', '/')
    try:
        req = urllib.request.Request(url_v3, headers={'User-Agent': 'Mozilla/5.0'})
        res = json.loads(urllib.request.urlopen(req, timeout=5).read())
        if res.get('status') and res.get('data') and res['data'].get('jadwal'):
            entry = res['data']['jadwal']
            entry['tanggal'] = entry.get('date', today)
            
            # Map v3 fields to internal format
            entry['imsyak'] = entry.get('imsak', '')
            entry['shubuh'] = entry.get('subuh', '')
            entry['magrib'] = entry.get('maghrib', '')
            
    except Exception as e:
        print(f'Warning: Live API v3 failed ({e}), using fallback data...', file=sys.stderr)

# Fallback to local V2 JSON
if not entry:
    try:
        data = json.load(open(json_path))
        jadwal = data.get('data', {}).get('jadwal', [])
        for e in jadwal:
            if e['date'] == today:
                entry = e
                # Fix field names for consistency (V2 to V1/V3 mapping)
                if 'imsak' in entry: entry['imsyak'] = entry['imsak']
                if 'subuh' in entry: entry['shubuh'] = entry['subuh']
                if 'maghrib' in entry: entry['magrib'] = entry['maghrib']
                if 'ashar' in entry: entry['ashr'] = entry['ashar']
                break
    except Exception as e:
        pass

if entry:
    print(f'📅 Jadwal Sholat {city_name.upper()} ({entry[\"tanggal\"]})')
    print(f'  Imsyak  : {entry.get(\"imsyak\", \"-\")}')
    print(f'  Shubuh  : {entry.get(\"shubuh\", \"-\")}')
    print(f'  Terbit  : {entry.get(\"terbit\", \"-\")}')
    print(f'  Dhuha   : {entry.get(\"dhuha\", \"-\")}')
    print(f'  Dzuhur  : {entry.get(\"dzuhur\", \"-\")}')
    print(f'  Ashar   : {entry.get(\"ashr\", \"-\")}')
    print(f'  Maghrib : {entry.get(\"magrib\", \"-\")}')
    print(f'  Isya    : {entry.get(\"isya\", \"-\")}')
    sys.exit(0)

print(f'Tidak ada data jadwal sholat untuk {today}')
sys.exit(1)
"
}

cmd_schedule() {
    ensure_data
    local json_path today now_ts
    json_path=$(get_json_path)
    today=$(today_date)
    now_ts=$(now_epoch)

    # Filter: use args if provided, otherwise use config
    local filter="${*:-$PRAYERS}"

    # Determine the correct timezone for this city
    local city_tz
    city_tz=$(city_to_tz "$CITY")

    TZ="$city_tz" python3 -c "
import urllib.request, json, sys, time, os
from datetime import datetime

today = '$today'
now_ts = int('$now_ts')
sahur_mins = int('$SAHUR_MINS')
iftar_mins = int('$IFTAR_MINS')
filter_arg = '$filter'.strip()
city_id_v3 = '$CITY_ID'
json_path = '$json_path'

entry = None

# Try V3 Live API first
if city_id_v3:
    url_v3 = f'https://api.myquran.com/v3/sholat/jadwal/{city_id_v3}/' + today.replace('-', '/')
    try:
        req = urllib.request.Request(url_v3, headers={'User-Agent': 'Mozilla/5.0'})
        res = json.loads(urllib.request.urlopen(req, timeout=5).read())
        if res.get('status') and res.get('data') and res['data'].get('jadwal'):
            entry = res['data']['jadwal']
            entry['imsyak'] = entry.get('imsak', '')
            entry['shubuh'] = entry.get('subuh', '')
            entry['magrib'] = entry.get('maghrib', '')
    except Exception as e:
        pass

# Fallback to local V2 JSON
if not entry:
    try:
        data = json.load(open(json_path))
        jadwal = data.get('data', {}).get('jadwal', [])
        for e in jadwal:
            if e['date'] == today:
                entry = e
                # Fix field names for consistency
                if 'imsak' in entry: entry['imsyak'] = entry['imsak']
                if 'subuh' in entry: entry['shubuh'] = entry['subuh']
                if 'maghrib' in entry: entry['magrib'] = entry['maghrib']
                if 'ashar' in entry: entry['ashr'] = entry['ashar']
                break
    except Exception as e:
        pass

if not entry:
    print('ERROR: Tidak ada data jadwal sholat untuk ' + today, file=sys.stderr)
    sys.exit(1)

def hhmm_to_epoch(hhmm):
    h, m = map(int, hhmm.split(':'))
    dt = datetime.strptime(today + f' {h:02d}:{m:02d}:00', '%Y-%m-%d %H:%M:%S')
    return int(dt.timestamp())

schedule = []

# Sahur: N min before Shubuh
shubuh_epoch = hhmm_to_epoch(entry['shubuh'])
sahur_epoch = shubuh_epoch - (sahur_mins * 60)
sahur_time = time.strftime('%H:%M', time.localtime(sahur_epoch))
schedule.append(('sahur', sahur_time, sahur_epoch))

# 5 waktu wajib
for name in ['shubuh', 'dzuhur', 'ashr', 'magrib', 'isya']:
    schedule.append((name, entry[name], hhmm_to_epoch(entry[name])))

# Iftar: N min before Maghrib
magrib_epoch = hhmm_to_epoch(entry['magrib'])
iftar_epoch = magrib_epoch - (iftar_mins * 60)
iftar_time = time.strftime('%H:%M', time.localtime(iftar_epoch))
schedule.append(('iftar', iftar_time, iftar_epoch))

# Filter
wanted = set(f.strip().lower() for f in filter_arg.split())
schedule = [s for s in schedule if s[0] in wanted]

# Output future prayers only
found = False
for name, display_time, epoch in sorted(schedule, key=lambda x: x[2]):
    diff = epoch - now_ts
    if diff > 0:
        print(f'{name}|{display_time}|{diff}')
        found = True

if not found:
    print('INFO: Semua waktu sholat hari ini sudah lewat.', file=sys.stderr)
"
}

cmd_notify() {
    local prayer="$1"
    local prayer_time="${2:-}"

    local emoji tag title
    case "$prayer" in
        sahur)  emoji="🌙"; tag="crescent_moon"; title="Waktu Sahur";;
        shubuh) emoji="🌅"; tag="sunrise"; title="Waktu Shubuh";;
        dzuhur) emoji="☀️"; tag="sun"; title="Waktu Dzuhur";;
        ashr)   emoji="🌤️"; tag="sun_behind_cloud"; title="Waktu Ashar";;
        magrib) emoji="🌇"; tag="city_sunset"; title="Waktu Maghrib";;
        isya)   emoji="🌃"; tag="night_with_stars"; title="Waktu Isya";;
        iftar)  emoji="🍽️"; tag="fork_and_knife"; title="Persiapan Buka Puasa";;
        *)      emoji="🕌"; tag="mosque"; title="Waktu Sholat";;
    esac

    local message
    if [ "$prayer" = "sahur" ]; then
        message="${emoji} ${title} (${prayer_time}) — Ayo bangun sahur! ${SAHUR_MINS} menit lagi waktu Imsyak."
    elif [ "$prayer" = "iftar" ]; then
        message="${emoji} ${title} (${prayer_time}) — ${IFTAR_MINS} menit lagi waktu berbuka puasa!"
    else
        message="${emoji} ${title} (${prayer_time}) — Saatnya menunaikan sholat ${prayer}."
    fi

    # Send to ntfy via shared helper (export NTFY_TOPIC from our own config)
    if [ -f "$NTFY_SEND" ]; then
        NTFY_TOPIC="$NTFY_TOPIC" bash "$NTFY_SEND" "$message" --title "$title" --tags "$tag" --priority high >/dev/null 2>&1 || true
    fi

    # Output for PicoClaw to send to Telegram
    echo "$message"
}

cmd_status() {
    echo "=== Prayer Times Config ==="
    echo "Kota     : $CITY (API V3 ID: ${CITY_ID:--}, API V2 ID: ${CITY_ID_V2:--})"
    echo "Timezone : $(city_to_tz "$CITY")"
    echo "Sahur    : $SAHUR_MINS menit sebelum Shubuh"
    echo "Iftar    : $IFTAR_MINS menit sebelum Maghrib"
    echo "Prayers  : $PRAYERS"
    echo "Data dir : $DATA_DIR"
    echo ""
    # Show ntfy status from shared config
    if [ -x "$NTFY_SEND" ]; then
        bash "$NTFY_SEND" status
    else
        echo "ntfy: ⚠️  ntfy_send.sh not found"
    fi
    echo ""

    local json_path
    json_path=$(get_json_path)
    if [ -f "$json_path" ]; then
        local count
        count=$(python3 -c "import json; data=json.load(open('$json_path')); print(len(data.get('data',{}).get('jadwal',[])))" 2>/dev/null || echo "?")
        echo "Data fallback bulan ini: ✅ Ada ($count hari)"
        echo "File: $json_path"
    else
        echo "Data fallback bulan ini: ❌ Belum ada"
        echo "Jalankan: prayer_notify.sh fetch"
    fi
}


# ---- Main ----

load_config

case "${1:-help}" in
    setup)         shift; cmd_setup "$@" ;;
    fetch)         cmd_fetch ;;
    today)         cmd_today ;;
    schedule)      shift; cmd_schedule "$@" ;;
    notify)        shift; cmd_notify "$@" ;;
    status)        cmd_status ;;
    help|*)
        echo "Usage: prayer_notify.sh {setup|fetch|today|schedule|notify|status}"
        echo ""
        echo "Commands:"
        echo "  setup <city>           Set kota dan fetch data awal"
        echo "  fetch                  Download jadwal bulan ini"
        echo "  today                  Tampilkan jadwal hari ini"
        echo "  schedule [prayers...]  Hitung detik-dari-sekarang untuk reminder AI"
        echo "  notify <prayer> <time> Kirim notifikasi (ntfy + stdout)"
        echo "  status                 Tampilkan config dan status data"
        echo ""
        echo "Config: $CONFIG_FILE"
        echo "Kota saat ini: $CITY"
        ;;
esac
