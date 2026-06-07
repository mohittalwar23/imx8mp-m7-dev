#!/bin/bash
# Run on the i.MX8MP EVK (Linux side) to load/start/stop the M7 via remoteproc.
# Usage:
#   m7-remoteproc.sh start <firmware-name-in-/lib/firmware>
#   m7-remoteproc.sh stop
#   m7-remoteproc.sh status

set -e
RPROC=/sys/class/remoteproc/remoteproc0

if [ ! -d "$RPROC" ]; then
    echo "ERROR: $RPROC not found."
    echo "  - Boot with imx8mp-evk-rpmsg.dtb (setenv fdt_file imx8mp-evk-rpmsg.dtb in U-Boot)"
    echo "  - Check: lsmod | grep imx_rproc"
    exit 1
fi

case "$1" in
    start)
        FIRM="${2:-imx8mp-m7-zephyr.elf}"
        STATE=$(cat "$RPROC/state")
        if [ "$STATE" = "running" ]; then
            echo "M7 already running. Stop it first."
            exit 1
        fi
        echo -n "$FIRM" > "$RPROC/firmware"
        echo start > "$RPROC/state"
        echo "M7 started with firmware: $FIRM"
        echo "State: $(cat $RPROC/state)"
        ;;
    stop)
        echo stop > "$RPROC/state"
        echo "M7 stopped."
        ;;
    status)
        echo "State:    $(cat $RPROC/state)"
        echo "Firmware: $(cat $RPROC/firmware)"
        ;;
    *)
        echo "Usage: $0 {start [firmware.elf]|stop|status}"
        exit 1
        ;;
esac
