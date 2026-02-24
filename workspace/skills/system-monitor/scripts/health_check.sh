#!/bin/bash
# health_check.sh — System health check for PicoClaw STB/server
# Usage:
#   bash skills/system-monitor/scripts/health_check.sh           # Full report
#   bash skills/system-monitor/scripts/health_check.sh --cpu     # CPU only
#   bash skills/system-monitor/scripts/health_check.sh --memory  # RAM only
#   bash skills/system-monitor/scripts/health_check.sh --disk    # Disk only
#   bash skills/system-monitor/scripts/health_check.sh --temp    # Temperature only
#   bash skills/system-monitor/scripts/health_check.sh --network # Network only

set -euo pipefail

# Load config if exists
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF_FILE="$SKILL_DIR/data/config"

# Defaults
TEMP_WARN=70
TEMP_CRIT=80
RAM_WARN=80
RAM_CRIT=90
DISK_WARN=80
DISK_CRIT=90
LOAD_WARN=2.0
LOAD_CRIT=4.0

if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE"
fi

# Helper: status icon
status_icon() {
    local val=$1 warn=$2 crit=$3
    if [ "$(echo "$val >= $crit" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        echo "🔴"
    elif [ "$(echo "$val >= $warn" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        echo "🟡"
    else
        echo "✅"
    fi
}

# Components
get_uptime() {
    uptime_str=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*load.*//')
    echo "$uptime_str"
}

get_cpu_temp() {
    temp=""
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        raw=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp=$(echo "$raw / 1000" | bc 2>/dev/null || echo "$((raw / 1000))")
    fi
    if [ -z "$temp" ]; then
        echo "N/A"
        return
    fi
    icon=$(status_icon "$temp" "$TEMP_WARN" "$TEMP_CRIT")
    echo "${temp}°C $icon"
}

get_cpu_load() {
    load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
    if [ -z "$load" ]; then
        load=$(uptime | grep -oP 'load average: \K[^,]+' 2>/dev/null || echo "N/A")
    fi
    cores=$(nproc 2>/dev/null || echo 1)
    if [ "$load" != "N/A" ]; then
        icon=$(status_icon "$load" "$LOAD_WARN" "$LOAD_CRIT")
        echo "$load ($cores core) $icon"
    else
        echo "N/A"
    fi
}

get_memory() {
    mem_info=$(free -m 2>/dev/null | grep Mem)
    if [ -z "$mem_info" ]; then
        echo "N/A"
        return
    fi
    total=$(echo "$mem_info" | awk '{print $2}')
    used=$(echo "$mem_info" | awk '{print $3}')
    if [ "$total" -gt 0 ]; then
        pct=$((used * 100 / total))
    else
        pct=0
    fi
    icon=$(status_icon "$pct" "$RAM_WARN" "$RAM_CRIT")
    echo "${used}MB / ${total}MB (${pct}%) $icon"
}

get_disk() {
    disk_info=$(df -h / 2>/dev/null | tail -1)
    if [ -z "$disk_info" ]; then
        echo "N/A"
        return
    fi
    used=$(echo "$disk_info" | awk '{print $3}')
    total=$(echo "$disk_info" | awk '{print $2}')
    pct_raw=$(echo "$disk_info" | awk '{print $5}' | tr -d '%')
    icon=$(status_icon "$pct_raw" "$DISK_WARN" "$DISK_CRIT")
    echo "${used} / ${total} (${pct_raw}%) $icon"
}

get_network() {
    if ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1; then
        echo "✅ connected"
    else
        echo "🔴 disconnected"
    fi
}

# Get overall status
get_overall_status() {
    local has_warning=false has_critical=false

    # Check temp
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        raw=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp=$((raw / 1000))
        [ "$temp" -ge "$TEMP_CRIT" ] && has_critical=true
        [ "$temp" -ge "$TEMP_WARN" ] && has_warning=true
    fi

    # Check RAM
    mem_info=$(free -m 2>/dev/null | grep Mem)
    if [ -n "$mem_info" ]; then
        total=$(echo "$mem_info" | awk '{print $2}')
        used=$(echo "$mem_info" | awk '{print $3}')
        if [ "$total" -gt 0 ]; then
            pct=$((used * 100 / total))
            [ "$pct" -ge "$RAM_CRIT" ] && has_critical=true
            [ "$pct" -ge "$RAM_WARN" ] && has_warning=true
        fi
    fi

    # Check disk
    disk_pct=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [ -n "$disk_pct" ]; then
        [ "$disk_pct" -ge "$DISK_CRIT" ] && has_critical=true
        [ "$disk_pct" -ge "$DISK_WARN" ] && has_warning=true
    fi

    if [ "$has_critical" = true ]; then
        echo "CRITICAL 🔴"
    elif [ "$has_warning" = true ]; then
        echo "WARNING 🟡"
    else
        echo "ALL OK ✅"
    fi
}

# Main
MODE="${1:-full}"
DATE_STR=$(date '+%Y-%m-%d %H:%M %Z' 2>/dev/null || date)

case "$MODE" in
    --cpu)
        echo "💻 CPU Load: $(get_cpu_load)"
        ;;
    --temp)
        echo "🔥 CPU Temp: $(get_cpu_temp)"
        ;;
    --memory)
        echo "🧠 RAM: $(get_memory)"
        ;;
    --disk)
        echo "💾 Disk: $(get_disk)"
        ;;
    --network)
        echo "🌐 Network: $(get_network)"
        ;;
    *)
        echo "🖥️ SYSTEM HEALTH REPORT"
        echo "========================"
        echo "📅 $DATE_STR"
        echo "⏱️ Uptime: $(get_uptime)"
        echo "🔥 CPU Temp: $(get_cpu_temp)"
        echo "💻 CPU Load: $(get_cpu_load)"
        echo "🧠 RAM: $(get_memory)"
        echo "💾 Disk: $(get_disk)"
        echo "🌐 Network: $(get_network)"
        echo "========================"
        echo "Status: $(get_overall_status)"
        ;;
esac
