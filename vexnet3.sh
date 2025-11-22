#!/bin/bash
setterm -cursor off
export TERM=linux
clear

echo " _    __          _   __     __ _____"
echo "| |  / /__  _  __/ | / /__  / /|__  /"
echo "| | / / _ \| |/_/  |/ / _ \/ __//_ < "
echo "| |/ /  __/>  </ /|  /  __/ /____/ / "
echo "|___/\___/_/|_/_/ |_/\___/\__/____/  "
sleep 1
echo
echo "[LOG] Initialising VexNet3"
echo
sleep 1

start_spinner() {
    SPINNER_SPIN='|/-\'
    SPINNER_INDEX=0
    SPINNER_MESSAGE="$1"

    tput civis 2>/dev/null
    tput sc

    (
        while true; do
            tput rc
            printf "[%c] %s" "${SPINNER_SPIN:SPINNER_INDEX%4:1}" "$SPINNER_MESSAGE"
            ((SPINNER_INDEX++))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null
    tput rc
    printf "[OK] %s\n" "$SPINNER_MESSAGE"
    tput cnorm 2>/dev/null
    sleep 0.5
}

start_spinner "Starting hostapd & raspapd..."
sudo systemctl restart hostapd >/dev/null 2>&1
sudo systemctl enable hostapd >/dev/null 2>&1
sudo systemctl restart raspapd >/dev/null 2>&1
sudo systemctl enable raspapd >/dev/null 2>&1
stop_spinner "Starting hostapd & raspapd..."

start_spinner "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf >/dev/null
stop_spinner "Enabling IP forwarding..."

start_spinner "Setting NAT rules..."
sudo iptables -t nat -C POSTROUTING -s 192.168.69.0/24 -o eth0 -j MASQUERADE 2>/dev/null \
    || sudo iptables -t nat -A POSTROUTING -s 192.168.69.0/24 -o eth0 -j MASQUERADE >/dev/null 2>&1
sudo iptables -C FORWARD -i wlan1 -o eth0 -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i wlan1 -o eth0 -j ACCEPT >/dev/null 2>&1
sudo iptables -C FORWARD -i eth0 -o wlan1 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i eth0 -o wlan1 -m state --state RELATED,ESTABLISHED -j ACCEPT >/dev/null 2>&1

sudo apt install -y iptables-persistent >/dev/null 2>&1
sudo netfilter-persistent save >/dev/null 2>&1
stop_spinner "Setting NAT rules..."

start_spinner "Retrieving system info..."
get_time() { date +"%H:%M:%S"; }
get_date() { date +"%d-%m-%y"; }

vcgencmd measure_temp 2>/dev/null | grep -q temp
HAS_VCGENCMD=$?

get_cpu_temp() {
    if [ $HAS_VCGENCMD -eq 0 ]; then
        vcgencmd measure_temp | awk -F'[=.]' '{print $2}'
    else
        awk '{print int($1/1000)}' /sys/class/thermal/thermal_zone0/temp
    fi
}

get_gpu_temp() { get_cpu_temp; }

get_cpu_usage() {
    read _ user nice system idle _ < /proc/stat
    local idle1=$idle total1=$((user+nice+system+idle))
    sleep 0.1
    read _ user nice system idle _ < /proc/stat
    local idle2=$idle total2=$((user+nice+system+idle))
    local delta_idle=$((idle2-idle1))
    local delta_total=$((total2-total1))
    echo $((100 * (delta_total - delta_idle) / delta_total))
}

get_gpu_clock() { vcgencmd measure_clock core | awk -F= '{print int($2/1000000)}'; }

get_ram_used() {
    local total avail used
    total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    avail=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    used=$((total - avail))
    total_mb=$((total / 1024))
    used_mb=$((used / 1024))
    echo "${used_mb}MB"
}

get_clients() { iw dev wlan1 station dump | grep -c Station; }
get_ssid() { iw dev wlan1 info | awk -F'ssid ' '/ssid/ {print $2}'; }
get_signal() { iw dev wlan1 info | awk '/txpower/ {print $2 " dBm"}'; }
get_status() { ip link show wlan1 | awk '/state/ {print $9}'; }
get_ip() { ip addr show wlan1 | awk '/inet / {print $2}'; }
stop_spinner "Retrieving system info..."

echo
echo "[LOG] VexNet3 successfully loaded"
sleep 2

START_TIME=$(date +%s)
clear

tput cup 0 0; printf "┌───────────────┐ VexNet3-v.1.2 ┌──────────────┐"
tput cup 1 0; printf "│               └──────┬────────┘              │"
tput cup 2 2; printf "Time:"
tput cup 3 2; printf "Date:"
tput cup 4 2; printf "Uptime:"
tput cup 6 2; printf "CPU Temp:"
tput cup 7 2; printf "GPU Temp:"
tput cup 9 2; printf "CPU Usage:"
tput cup 10 2; printf "GPU Clock:"
tput cup 11 2; printf "RAM Usage:"
tput cup 2 25; printf "SSID:"
tput cup 3 25; printf "Signal:"
tput cup 4 25; printf "IP:"
tput cup 6 25; printf "Status:"
tput cup 7 25; printf "Clients:"
tput cup 13 0; printf "├──────────────────────┼───────────────────────┤"
tput cup 14 0; printf "│    Ctrl+C to exit    │  Ctrl+X to toggle AP  │"
tput cup 15 0; printf "└──────────────────────┴───────────────────────┘"

for i in {2..13}; do
    tput cup $i 0;  printf "│"
    tput cup $i 23; printf "│"
    tput cup $i 47; printf "│"
done

stty -echo -icanon time 0 min 0

toggle_ap() {
    if systemctl is-active --quiet hostapd; then
        sudo systemctl stop hostapd >/dev/null 2>&1
    else
        sudo systemctl start hostapd >/dev/null 2>&1
    fi
    tput cup 6 33; printf "%-6s" "$AP_STATUS"
}

while true; do
    setterm -cursor off

    read -rsn1 -t 0.1 KEY

    [[ $KEY == $'\x03' ]] && { setterm -cursor on; clear; break; }
    [[ $KEY == $'\x18' ]] && toggle_ap

    TIME=$(get_time)
    DATE=$(get_date)

    CURRENT_TIME=$(date +%s)
    UPTIME_SEC=$((CURRENT_TIME - START_TIME))
    UPTIME=$(printf '%d:%02d:%02d' \
        $((UPTIME_SEC/3600)) \
        $(((UPTIME_SEC%3600)/60)) \
        $((UPTIME_SEC%60)))

    CPU_TEMP=$(get_cpu_temp)
    GPU_TEMP=$(get_gpu_temp)
    CPU_USAGE=$(get_cpu_usage)
    GPU_CLOCK=$(get_gpu_clock)
    RAM_USE=$(get_ram_used)
    CLIENTS=$(get_clients)
    SSID=$(get_ssid)
    SIGNAL=$(get_signal)
    STATUS=$(get_status)
    IP=$(get_ip)

    tput cup 2 8;  printf "%s" "$TIME"
    tput cup 2 31; printf "%s" "$SSID"
    tput cup 3 8; printf "%s" "$DATE"
    tput cup 4 10;  printf "%s" "$UPTIME"
    tput cup 4 29; printf "%s" "$IP"
    tput cup 3 33; printf "%s" "$SIGNAL"
    tput cup 6 12; printf "%s°C" "$CPU_TEMP"
    tput cup 6 33; printf "%-6s" "$STATUS"
    tput cup 7 12; printf "%s°C" "$GPU_TEMP"
    tput cup 9 13; printf "%-6s" "$CPU_USAGE%"
    tput cup 10 13; printf "%-10s" "$GPU_CLOCK MHz"
    tput cup 11 13; printf "%-6s" "$RAM_USE"
    tput cup 7 34; printf "%s" "$CLIENTS"

    RX1=$(< /sys/class/net/wlan1/statistics/rx_bytes)
    TX1=$(< /sys/class/net/wlan1/statistics/tx_bytes)
    sleep 1
    RX2=$(< /sys/class/net/wlan1/statistics/rx_bytes)
    TX2=$(< /sys/class/net/wlan1/statistics/tx_bytes)

    RX=$(awk "BEGIN {print ($RX2-$RX1)/1024/1024}")
    TX=$(awk "BEGIN {print ($TX2-$TX1)/1024/1024}")

    tput cup 9 25; printf "Traffic Monitor:"
    tput cup 11 25; printf "%-20s" "Inbound: $(printf "%.2f" "$RX") MB/s"
    tput cup 10 25; printf "%-20s" "Outbound: $(printf "%.2f" "$TX") MB/s"
done

trap 'clear; setterm -cursor on' EXIT
