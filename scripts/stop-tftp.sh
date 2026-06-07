#!/bin/sh
# Undo start-tftp.sh -- stop the TFTP server and hand eno1 back to NetworkManager.
# Run with:  sudo sh /home/mt/Downloads/stop-tftp.sh
IF=eno1

pkill -x dnsmasq 2>/dev/null
ip addr flush dev "$IF"
nmcli device set "$IF" managed yes 2>/dev/null

echo "TFTP server stopped; $IF returned to NetworkManager."
