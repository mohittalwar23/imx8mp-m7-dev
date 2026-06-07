# Workflow B: Linux remoteproc

Use this workflow for examples that **communicate with Linux** (RPMsg) or simply
need to run alongside a booted Linux system. The M7 is loaded by the kernel's
`imx-rproc` driver after Linux is up.

## When to Use

- `hello_world` — basic sanity check
- `rpmsg_lite_str_echo_rtos` — A53↔M7 message passing via `/dev/ttyRPMSG30`
- `sai_low_power_audio` — SRTM audio (broken on kernel 5.4.70 — see known issues)

## Prerequisites

The board's kernel already has `CONFIG_REMOTEPROC=y` and `CONFIG_IMX_REMOTEPROC=y`
built in, and the FAT `/boot` partition includes `imx8mp-evk-rpmsg.dtb`. No
kernel rebuild or BSP upgrade needed.

## Step 1 — Boot with the remoteproc device tree

Catch U-Boot autoboot (press any key on ttyUSB2), then:
```
setenv fdt_file imx8mp-evk-rpmsg.dtb; saveenv; boot
```

> **`saveenv` note:** On this BSP the env partition may be read-only; `saveenv` sometimes
> does not persist across power cycles. Always verify at U-Boot and re-set if needed.

This DTB enables the `imx-rproc` device tree node and reassigns UART4 to the M7.

## Step 2 — Restore network

After Linux boots, log in as root and set the static IP:
```bash
ip addr add 192.168.7.2/24 dev eth0
```

On the laptop:
```bash
sudo ip addr add 192.168.7.1/24 dev eno1
```

Verify `remoteproc0` exists:
```bash
ls /sys/class/remoteproc/    # expect: remoteproc0
cat /sys/class/remoteproc/remoteproc0/state   # expect: offline
```

## Step 3 — Deploy from VS Code

Open the MCUXpresso project in VS Code, then:

**Terminal → Run Task → "Deploy to M7 (remoteproc)"**

This task:
1. Builds the ELF
2. SCPs it to `/lib/firmware/m7-app.elf` on the board
3. Stops any running M7 firmware
4. Sets the firmware name and starts the M7
5. Prints `M7 state: running`

## Step 4 — Watch M7 output

> **Tip:** Open picocom on ttyUSB3 **before** deploying to catch the M7 boot messages.

```bash
picocom -b 115200 /dev/ttyUSB3
```

## Stop / Reload Cycle

No reboot needed. Just re-run the deploy task:
- The task sends `echo stop` before loading the new firmware
- Total cycle time: ~3 seconds (SCP + remoteproc restart)

## Manual remoteproc commands (on the board)

```bash
# Stop M7
echo stop > /sys/class/remoteproc/remoteproc0/state

# Set firmware (must be in /lib/firmware/)
echo -n "m7-app.elf" > /sys/class/remoteproc/remoteproc0/firmware

# Start M7
echo start > /sys/class/remoteproc/remoteproc0/state

# Check state
cat /sys/class/remoteproc/remoteproc0/state
```

Or use the helper script (copy to board first):
```bash
scp scripts/m7-remoteproc.sh root@192.168.7.2:/usr/local/bin/
# On board:
m7-remoteproc.sh start m7-app.elf
m7-remoteproc.sh status
m7-remoteproc.sh stop
```
