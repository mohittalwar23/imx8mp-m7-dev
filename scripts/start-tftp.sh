#!/bin/sh
# M7 firmware TFTP loader setup -- direct laptop <-> i.MX8MP board link.
# Run with:  sudo sh /home/mt/Downloads/start-tftp.sh
# Reverse with:  sudo sh /home/mt/Downloads/stop-tftp.sh
IF=eno1

# Stop NetworkManager managing this port, so it won't DHCP over our static IP.
nmcli device set "$IF" managed no 2>/dev/null

# Static point-to-point address (board will be 192.168.7.2).
ip addr flush dev "$IF"
ip addr add 192.168.7.1/24 dev "$IF"
ip link set "$IF" up

# Throwaway TFTP-only dnsmasq: DNS disabled, no system config, bound to eno1.
pkill -x dnsmasq 2>/dev/null
sleep 1
dnsmasq --conf-file=/dev/null --port=0 --enable-tftp \
        --tftp-root=/home/mt/tftp --interface="$IF" --bind-interfaces \
        --user=mt --log-facility=/home/mt/tftp/dnsmasq.log --log-debug

echo
echo "=== result ==="
ip -br addr show "$IF"
if pgrep -x dnsmasq >/dev/null; then
    echo "dnsmasq: running -- serving /home/mt/tftp as 192.168.7.1"
else
    echo "dnsmasq: NOT running -- check the error above"
fi
