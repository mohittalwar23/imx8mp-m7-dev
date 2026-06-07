# Workflow A: U-Boot TFTP Boot

Use this workflow for **standalone M7 examples** that cannot run while Linux is
booted (they own SAI clocks/pins directly). The M7 is loaded and started from
U-Boot before Linux ever runs.

## When to Use

- `sai_interrupt_transfer` — plays a 1 kHz sine tone
- `sai_interrupt_record_playback` — mic loopback (record + playback)
- Any bare-metal example that directly configures audio or other A53-owned peripherals

## Prerequisites

```bash
sudo apt install dnsmasq-base picocom
```

## Step 1 — Build the firmware

In MCUXpresso VS Code, run **"Copy to TFTP dir"** task (builds and copies the `.bin`
to `~/tftp/`). Or copy manually:
```bash
cp debug/<project>_cm7.bin ~/tftp/<name>.bin
```

## Step 2 — Start the TFTP server

```bash
sudo sh scripts/start-tftp.sh
```

This script:
1. Removes `eno1` from NetworkManager (prevents DHCP clobbering the static IP)
2. Assigns `192.168.7.1/24` to `eno1`
3. Starts a throwaway `dnsmasq` serving `~/tftp/` on port 69

Undo with `sudo sh scripts/stop-tftp.sh`.

## Step 3 — Catch U-Boot

Open the A53 console, then power-cycle the board:
```bash
picocom -b 115200 /dev/ttyUSB2
```

At the `Hit any key to stop autoboot` countdown, **press any key** to get `u-boot=>`.

## Step 4 — Load and boot the M7 (one paste)

```
setenv ipaddr 192.168.7.2; setenv serverip 192.168.7.1; setenv netmask 255.255.255.0; tftp 0x48000000 <name>.bin; cp.b 0x48000000 0x7e0000 ${filesize}; bootaux 0x7e0000
```

Replace `<name>` with the filename you copied to `~/tftp/`. Examples:
- `sai_tone.bin` — sine tone
- `sai_loopback.bin` — mic loopback

What each command does:
- `setenv ipaddr/serverip/netmask` — board-side network config (RAM only, not saved)
- `tftp 0x48000000 <name>.bin` — pull binary from laptop into DDR scratch area
- `cp.b 0x48000000 0x7e0000 ${filesize}` — copy from DDR into M7's ITCM
- `bootaux 0x7e0000` — release M7 from reset; it starts executing from ITCM

## Step 5 — Watch M7 output

```bash
picocom -b 115200 /dev/ttyUSB3
```

## Step 6 — Boot Linux too (optional)

The M7 keeps running after `bootaux`. To boot Linux on the A53:
```
boot
```

## Gotchas

- **`bootaux` is one-shot.** If M7 is already running, `bootaux` does nothing.
  To reload: `reset`, catch U-Boot, run the paste again.
- **First `tftp` may ARP-time out.** PHY link takes a moment. Retry once.
- **Two RJ45 jacks.** U-Boot only drives one at a time. If `ping 192.168.7.1`
  fails, swap to the other jack.
- **`hello_world` prints only once.** Use the synchronization sample (prints
  forever) when locating the M7 serial port.
