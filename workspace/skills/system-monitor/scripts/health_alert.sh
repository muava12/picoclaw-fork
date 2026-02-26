#!/bin/bash
# health_alert.sh — Send ntfy alert ONLY if system has warning/critical issues
# Does nothing if everything is OK (silent success).
# Designed to be called from cron every hour.

set -euo pipefail

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

if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE"
fi

# Detect issues
alerts=""
priority="default"
tags="computer"

# Check CPU temp
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    raw=$(cat /sys/class/thermal/thermal_zone0/temp)
    temp=$((raw / 1000))
    if [ "$temp" -ge "$TEMP_CRIT" ]; then
        alerts="$alerts 🔥 CPU: ${temp}°C CRITICAL!"
        priority="urgent"
        tags="fire,$tags"
    elif [ "$temp" -ge "$TEMP_WARN" ]; then
        alerts="$alerts 🔥 CPU: ${temp}°C warning"
        priority="high"
        tags="warning,$tags"
    fi
fi

# Check RAM
mem_info=$(free -m 2>/dev/null | grep Mem)
if [ -n "$mem_info" ]; then
    total=$(echo "$mem_info" | awk '{print $2}')
    used=$(echo "$mem_info" | awk '{print $3}')
    if [ "$total" -gt 0 ]; then
        pct=$((used * 100 / total))
        if [ "$pct" -ge "$RAM_CRIT" ]; then
            alerts="$alerts 🧠 RAM: ${pct}% CRITICAL!"
            priority="urgent"
        elif [ "$pct" -ge "$RAM_WARN" ]; then
            alerts="$alerts 🧠 RAM: ${pct}% warning"
            [ "$priority" = "default" ] && priority="high"
        fi
    fi
fi

# Check disk
disk_pct=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
if [ -n "$disk_pct" ]; then
    if [ "$disk_pct" -ge "$DISK_CRIT" ]; then
        alerts="$alerts 💾 Disk: ${disk_pct}% CRITICAL!"
        priority="urgent"
    elif [ "$disk_pct" -ge "$DISK_WARN" ]; then
        alerts="$alerts 💾 Disk: ${disk_pct}% warning"
        [ "$priority" = "default" ] && priority="high"
    fi
fi

# Check network
if ! ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1; then
    alerts="$alerts 🌐 Network: disconnected!"
    [ "$priority" = "default" ] && priority="high"
fi

# Exit silently if no issues
if [ -z "$alerts" ]; then
    exit 0
fi

# Find ntfy config (check reminder skill's config)
NTFY_TOPIC=""
REMINDER_CONF="$SKILL_DIR/../reminder/data/ntfy.conf"
if [ -f "$REMINDER_CONF" ]; then
    . "$REMINDER_CONF"
fi

# Also check own config
OWN_NTFY="$SKILL_DIR/data/ntfy.conf"
if [ -f "$OWN_NTFY" ]; then
    . "$OWN_NTFY"
fi

if [ -z "$NTFY_TOPIC" ]; then
    # No ntfy configured — just print to stdout (goes to Telegram via cron)
    echo "⚠️ SYSTEM ALERT:$alerts"
    exit 0
fi

# Send via ntfy
HOSTNAME_STR=$(hostname 2>/dev/null || echo "STB")
eval curl -sf \
    -H "\"Title: System Alert - $HOSTNAME_STR\"" \
    -H "\"Priority: $priority\"" \
    -H "\"Tags: $tags\"" \
    -d "\"$alerts\"" \
    "\"$NTFY_TOPIC\"" || true

echo "⚠️ SYSTEM ALERT (sent to ntfy):$alerts"
