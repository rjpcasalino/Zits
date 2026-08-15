#!/usr/bin/env bash

# Cache public IP to avoid blocking the main bar loop
fetch_pub_ip() {
    curl -s --max-time 2 https://ifconfig.me 2>/dev/null || echo "offline"
}

PUB="fetching..."
(PUB=$(fetch_pub_ip); echo "$PUB" > /tmp/sway_pub_ip) &

# Initialize network bandwidth tracking
PREV_RX=0
PREV_TX=0

while true; do
    # -------------------------------------------------------------------------
    # 1. NETWORK & VPN
    # -------------------------------------------------------------------------
    IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')
    IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
    
    # Active Interfaces & IPs (State UP, excluding loopback)
    IFACES_ACTIVE=$(ip -o -4 addr show | grep -v ' state DOWN' | awk '$2 != "lo" {print $2 ":" $4}' | cut -d'/' -f1 | tr '\n' ' ' | sed 's/ $//')

    # Total Active TCP/UDP Connections
    CONN_COUNT=$(ss -tua state established 2>/dev/null | tail -n +2 | wc -l)

    # Refresh public IP periodically in background
    if [ -f /tmp/sway_pub_ip ]; then
        PUB=$(cat /tmp/sway_pub_ip)
    fi 
    
    # Active VPN/Tunnel Check (wireguard, tun, tap)
    VPN=$(ip link show | grep -E 'wg|tun|mullvad|proton' | awk -F': ' '{print $2}' | head -n1)
    VPN_STR="${VPN:+" | 🛡️ ${VPN}"}"

    # Bandwidth Rx/Tx (KB/s)
    if [ -n "$IFACE" ] && [ -e "/sys/class/net/$IFACE/statistics/rx_bytes" ]; then
        NOW_RX=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes")
        NOW_TX=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes")
        if [ "$PREV_RX" -gt 0 ]; then
            RX_SPEED=$(( (NOW_RX - PREV_RX) / 2048 )) # divide by 2s * 1024
            TX_SPEED=$(( (NOW_TX - PREV_TX) / 2048 ))
            NET_SPEED=" | ⬇️ ${RX_SPEED}K ⬆️ ${TX_SPEED}K"
        else
            NET_SPEED=""
        fi
        PREV_RX=$NOW_RX
        PREV_TX=$NOW_TX
    fi

    # -------------------------------------------------------------------------
    # 2. DISK SPACE (All real physical mounts)
    # -------------------------------------------------------------------------
    DISKS=$(df -h --output=target,pcent -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | \
            tail -n +2 | awk '{printf "%s:%s ", $1, $2}' | sed 's/ $//')

    # -------------------------------------------------------------------------
    # 3. CPU & LOAD & TEMP
    # -------------------------------------------------------------------------
    LOAD=$(awk '{print $1" "$2" "$3}' /proc/loadavg)
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print int(100 - $8)"%"}')

    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        TEMP=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
        TEMP_STR=" (${TEMP}°C)"
    else
        TEMP_STR=""
    fi

    # -------------------------------------------------------------------------
    # 4. MEMORY & SWAP
    # -------------------------------------------------------------------------
    MEM=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')

    # -------------------------------------------------------------------------
    # 5. BATTERY & POWER
    # -------------------------------------------------------------------------
    BAT_STR=""
    if [ -d /sys/class/power_supply/BAT0 ]; then
        BAT_CAP=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
        BAT_STAT=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)
        [ "$BAT_STAT" = "Charging" ] && BAT_ICON="⚡" || BAT_ICON="🔋"
        BAT_STR=" | ${BAT_ICON} ${BAT_CAP}%"
    fi

    # -------------------------------------------------------------------------
    # 6. AUDIO VOLUME (WirePlumber)
    # -------------------------------------------------------------------------
    VOL_RAW=$(wpctl get-volume @DEFAULT_SINK@ 2>/dev/null)
    if [ -n "$VOL_RAW" ]; then
        VOL=$(echo "$VOL_RAW" | awk '{print int($2 * 100)"%"}')
        [[ "$VOL_RAW" == *"[MUTED]"* ]] && VOL="${VOL} (MUTED)"
    else
        VOL="N/A"
    fi

    # -------------------------------------------------------------------------
    # 7. UPTIME & DATE
    # -------------------------------------------------------------------------
    UPTIME=$(awk '{m=int($1/60); h=int(m/60); d=int(h/24); printf "%sd %sh %sm\n", d, h%24, m%60}' /proc/uptime | sed 's/^0d //;s/^0h //')
    DATE=$(date +'%Y-%m-%d %H:%M:%S')

    # -------------------------------------------------------------------------
    # OUTPUT FORMAT
    # -------------------------------------------------------------------------
    echo -e "\U1F1FA\U1F1F8 IF: [ ${IFACES_ACTIVE} ] | CONN: ${CONN_COUNT}${NET_SPEED} | PUB: ${PUB}${VPN_STR} | DISK: [ ${DISKS} ] | CPU: ${CPU}${TEMP_STR} (load ${LOAD}) | RAM: ${MEM}${BAT_STR} | VOL: ${VOL} | UP: ${UPTIME} | ${DATE}"

    # Asynchronously refresh Public IP every 30 iterations (~60 seconds)
    ((COUNTER++))
    if [ $((COUNTER % 30)) -eq 0 ]; then
        (fetch_pub_ip > /tmp/sway_pub_ip) &
    fi

    sleep 2
done
