#!/bin/bash
setterm -cursor off
export TERM=linux

clear
echo " _    __          _   __     __ _____"
echo "| |  / /__  _  __/ | / /__  / /|__  /"
echo "| | / / _ \| |/_/  |/ / _ \/ __//_ < "
echo "| |/ /  __/>  </ /|  /  __/ /____/ / "
echo "|___/\___/_/|_/_/ |_/\___/\__/____/  "

sleep 2
echo
echo "Loading startup script..."
sleep 2

echo
echo "LOG | Enabling IP forwarding"
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf >/dev/null
fi
sleep 1

AP_IP="192.168.69.1/24"
echo "LOG | Configuring wlan1 IP $AP_IP"
sudo ip addr flush dev wlan1 >/dev/null 2>&1
sudo ip addr add $AP_IP dev wlan1 >/dev/null 2>&1
sudo ip link set wlan1 up >/dev/null 2>&1
sleep 1

echo "LOG | Setting NAT rules"
sudo iptables -t nat -A POSTROUTING -s 192.168.69.0/24 -o eth0 -j MASQUERADE >/dev/null 2>&1
sudo iptables -A FORWARD -i wlan1 -o eth0 -j ACCEPT >/dev/null 2>&1
sudo iptables -A FORWARD -i eth0 -o wlan1 -m state --state RELATED,ESTABLISHED -j ACCEPT >/dev/null 2>&1

sudo apt install -y iptables-persistent >/dev/null 2>&1
sudo netfilter-persistent save >/dev/null 2>&1
sleep 1

echo "LOG | Starting hostapd & dnsmasq"
sudo systemctl restart hostapd >/dev/null 2>&1
sudo systemctl enable hostapd >/dev/null 2>&1
sudo systemctl restart dnsmasq >/dev/null 2>&1
sudo systemctl enable dnsmasq >/dev/null 2>&1

get_time() { date +"%H:%M:%S"; }
get_date() { date +"%d-%m-%y"; }
get_cpu_temp() { vcgencmd measure_temp | awk -F"=" '{print int($2)}'; }
get_gpu_temp() { vcgencmd measure_temp | awk -F"=" '{print int($2)}'; }
get_cpu_usage() { top -bn1 | awk '/Cpu/ {print int($2 + $4)}'; }
get_gpu_clock() { vcgencmd measure_clock core | awk -F= '{print int($2/1000000)}'; }
get_ram_used()  { free -h | awk '/Mem:/ {print $3"/"$2}'; }
get_disk_usage() { df -h / | awk 'NR==2 {print $3 "/" $2}'; }
get_clients() { iw dev wlan1 station dump | grep Station | wc -l; }
get_ssid() { iw dev wlan1 info | awk -F'ssid ' '/ssid/ {print $2}'; }
get_signal() { iw dev wlan1 info | awk '/txpower/ {print $2 " dBm"}'; }
get_status() { ip link show wlan1 | awk '/state/ {print $9}'; }
get_ip() { ip addr show wlan1 | awk '/inet / {print $2}'; }

echo
echo "Script started successfully!"
sleep 2

START_TIME=$(date +%s)

clear

echo "───────────── VexNet3 RPi5 Monitor ─────────────"
echo
tput cup 2 0; printf "Time:"
tput cup 3 0; printf "Date:"
tput cup 2 25; printf "SSID:"
tput cup 4 0; printf "Uptime:"
tput cup 4 25; printf "IP:"
tput cup 3 25; printf "Signal:"
tput cup 6 0; printf "CPU Temp:"
tput cup 6 25; printf "Status:"
tput cup 7 25; printf "Clients:"
tput cup 7 0; printf "GPU Temp:"
tput cup 9 0; printf "CPU Usage:"
tput cup 10 0; printf "GPU Clock:"
tput cup 11 0; printf "RAM Usage:"
tput cup 13 0; printf "Disk Space:"
tput cup 13 25; printf "Version: 1.1.0"

for i in {2..13}; do
    tput cup $i 23; printf "│"
done

while true; do
    DATE=$(get_date)
    TIME=$(get_time)
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
    DISK_USE=$(get_disk_usage)
    CLIENTS=$(get_clients)
    SSID=$(get_ssid)
    SIGNAL=$(get_signal)
    STATUS=$(get_status)
    IP=$(get_ip)

    tput cup 2 6;  printf "%s" "$TIME"
    tput cup 2 31; printf "%s" "$SSID"
    tput cup 3 6; printf "%s" "$DATE"

    tput cup 4 8;  printf "%s" "$UPTIME"
    tput cup 4 29; printf "%s" "$IP"
    tput cup 3 33; printf "%s" "$SIGNAL"

    tput cup 6 10; printf "%s°C" "$CPU_TEMP"
    tput cup 6 33; printf "%s" "$STATUS"

    tput cup 7 10; printf "%s°C" "$GPU_TEMP"

    tput cup 9 11; printf "%s%%" "$CPU_USAGE"
    tput cup 10 11; printf "%s MHz" "$GPU_CLOCK"
    tput cup 11 11; printf "%s" "$RAM_USE"

    tput cup 13 12; printf "%s" "$DISK_USE"

    tput cup 7 34; printf "%s" "$CLIENTS"

    read RX TX < <(RX1=$(cat /sys/class/net/wlan1/statistics/rx_bytes); TX1=$(cat /sys/class/net/wlan1/statistics/tx_bytes); sleep 1; RX2=$(cat /sys/class/net/wlan1/statistics/rx_bytes); TX2=$(cat /sys/class/net/wlan1/statistics/tx_bytes); echo $((RX2-RX1)) $((TX2-TX1)) | awk '{printf "%.2f %.2f\n",$1/1024/1024,$2/1024/1024}')
    tput cup 9 25; printf "Traffic Monitor:"
    tput cup 11 25; printf "Inbound: %.2f Mb/s" "$RX"
    tput cup 10 25; printf "Outbound: %.2f Mb/s" "$TX"

    sleep 3
done

setterm -cursor on