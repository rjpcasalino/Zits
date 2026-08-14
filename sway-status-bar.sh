#!/usr/bin/env bash

while true; do
    IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
    PUB=$(curl -s --max-time 2 https://ifconfig.me 2>/dev/null || echo "offline")
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print int(100 - $8)"%"}')
    MEM=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    
    VOL_RAW=$(wpctl get-volume @DEFAULT_SINK@ 2>/dev/null)
    if [ -n "$VOL_RAW" ]; then
        VOL=$(echo "$VOL_RAW" | awk '{print int($2 * 100)"%"}')
        if [[ "$VOL_RAW" == *"[MUTED]"* ]]; then
            VOL="${VOL} (MUTED)"
        fi
    else
        VOL="N/A"
    fi

    DATE=$(date +'%Y-%m-%d %H:%M:%S')

    echo "LAN: ${IP:-down} | PUB: ${PUB} | CPU: ${CPU} | RAM: ${MEM} | VOL: ${VOL} | ${DATE}"
    sleep 2
done
