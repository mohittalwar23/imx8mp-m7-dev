# i.MX8MP EVK — Cortex-M7 Development

Scripts, VS Code configs, and a complete guide for running bare-metal and FreeRTOS
firmware on the Cortex-M7 of the **NXP i.MX8M Plus EVK Plus DDR4**, verified on
BSP **L5.4.70_2.3.2** (kernel `5.4.70`).

Two workflows are covered:

| Workflow | When to use | M7 loaded by |
|---|---|---|
| **A — U-Boot TFTP** | Standalone M7 (owns audio hardware directly) | U-Boot `bootaux` |
| **B — Linux remoteproc** | M7 alongside Linux (RPMsg, co-processor model) | Linux `imx-rproc` driver |

---

## Table of Contents

1. [Hardware Overview](#1-hardware-overview)
2. [Prerequisites](#2-prerequisites)
3. [Network Setup](#3-network-setup)
4. [Workflow A: U-Boot TFTP](#4-workflow-a-u-boot-tftp)
5. [Workflow B: Linux remoteproc](#5-workflow-b-linux-remoteproc)
6. [Examples](#6-examples)
   - [hello\_world](#61-hello_world)
   - [SAI Interrupt Transfer — 1 kHz tone](#62-sai-interrupt-transfer)
   - [SAI Interrupt Record/Playback — mic loopback](#63-sai-interrupt-recordplayback)
   - [RPMsg String Echo — A53↔M7 communication](#64-rpmsg-string-echo)
   - [SAI Low Power Audio — ⚠️ broken](#65-sai-low-power-audio)
7. [Zephyr on M7](#7-zephyr-on-m7)
8. [Known Issues](#8-known-issues)
9. [Memory Map Reference](#9-memory-map-reference)

---

## 1. Hardware Overview

- **SoC:** i.MX 8M Plus — quad Cortex-A53 + single Cortex-M7
- **Debug port (J15, micro-B):** FT4232H — four UARTs only, **no JTAG**
  - `ttyUSB2` = A53 console (U-Boot + Linux)
  - `ttyUSB3` = M7 console (UART4, 115200 baud)
- **JTAG (J17, 20-pin):** requires external J-Link — not used in this guide
- **Audio jack (J6):** 3.5mm HP + headset mic (CTIA 4-pole)

### DIP Switches (SW4)

| Mode | SW4[1] | SW4[2–4] |
|---|---|---|
| Normal eMMC boot | ON | OFF |
| USB Serial Download (UUU flash) | OFF | OFF |

See [docs/01-hardware.md](docs/01-hardware.md) for full connector map and memory addresses.

---

## 2. Prerequisites

### Laptop

```bash
sudo apt install picocom dnsmasq-base
```

- **MCUXpresso VS Code extension** v26.5.49+ with SDK 26.06.00 installed
- SDK root: `/home/mt/mcuxsdk/mcuxsdk/` (adjust if yours differs)

### Board

Board ships with NXP BSP L5.4.70_2.3.2 on eMMC. No reflash needed — the kernel
already has remoteproc built in, and `imx8mp-evk-rpmsg.dtb` is on the FAT partition.

---

## 3. Network Setup

Direct Ethernet cable: laptop `eno1` → board RJ45 (either port). No router.

**Per session — laptop:**
```bash
sudo ip addr add 192.168.7.1/24 dev eno1
```

**Per session — board** (after Linux boots, via ttyUSB2):
```bash
ip addr add 192.168.7.2/24 dev eth0
```

> SSH/SCP requires extra flags because the board runs old Dropbear. All VS Code
> tasks in this repo already include them. See [docs/02-network-setup.md](docs/02-network-setup.md).

---

## 4. Workflow A: U-Boot TFTP

For standalone M7 examples that need exclusive access to audio hardware.

### 4.1 Start TFTP server

```bash
sudo sh scripts/start-tftp.sh
```

Serves `~/tftp/` at `192.168.7.1`. Undo with `sudo sh scripts/stop-tftp.sh`.

### 4.2 Catch U-Boot

Power-cycle the board with `picocom -b 115200 /dev/ttyUSB2` open. Press any key
at the autoboot countdown to get `u-boot=>`.

### 4.3 Load and boot the M7

```
setenv ipaddr 192.168.7.2; setenv serverip 192.168.7.1; setenv netmask 255.255.255.0; tftp 0x48000000 <name>.bin; cp.b 0x48000000 0x7e0000 ${filesize}; bootaux 0x7e0000
```

Replace `<name>` with your file in `~/tftp/`. M7 output appears on `ttyUSB3`.

### 4.4 Boot Linux too (optional)

The M7 keeps running after `bootaux`. Type `boot` at the U-Boot prompt.

Full details: [docs/03-uboot-tftp.md](docs/03-uboot-tftp.md)

---

## 5. Workflow B: Linux remoteproc

For RPMsg examples and general co-processor use.

### 5.1 Select the remoteproc device tree (once per power cycle)

At U-Boot:
```
setenv fdt_file imx8mp-evk-rpmsg.dtb; saveenv; boot
```

> `saveenv` may not persist — re-run if `remoteproc0` is missing after boot.

### 5.2 Verify remoteproc is ready

```bash
ls /sys/class/remoteproc/    # must show: remoteproc0
```

### 5.3 Deploy from VS Code

Open the project in MCUXpresso VS Code:

**Terminal → Run Task → "Deploy to M7 (remoteproc)"**

This builds, SCPs the ELF to `/lib/firmware/m7-app.elf`, and starts the M7.

Full details: [docs/04-remoteproc.md](docs/04-remoteproc.md)

---

## 6. Examples

### 6.1 `hello_world`

**What:** Prints `Hello World` once to ttyUSB3 then halts.
**Deploy:** remoteproc (VS Code task)
**SDK path:** `demo_apps/hello_world`
**Config overlay:** `mcuxsdk-projects/hello_world/`

```bash
# After deploy, watch M7 console:
picocom -b 115200 /dev/ttyUSB3
# Output: Hello World
```

---

### 6.2 SAI Interrupt Transfer

**What:** Plays a continuous 1 kHz sine tone through the headphone jack.
**Deploy:** TFTP (U-Boot) — Linux must NOT be booted
**SDK path:** `driver_examples/sai/interrupt_transfer`
**Config overlay:** `mcuxsdk-projects/sai_interrupt_transfer/`

**Steps:**
1. Plug headphones into **J6**
2. In VS Code: **Run Task → "Copy to TFTP dir"** (builds + copies `sai_tone.bin`)
3. Catch U-Boot, paste:
   ```
   setenv ipaddr 192.168.7.2; setenv serverip 192.168.7.1; setenv netmask 255.255.255.0; tftp 0x48000000 sai_tone.bin; cp.b 0x48000000 0x7e0000 ${filesize}; bootaux 0x7e0000
   ```
4. Hear the tone; ttyUSB3 shows `SAI example started!`

---

### 6.3 SAI Interrupt Record/Playback

**What:** Real-time microphone loopback — speak into the headset mic and hear
your voice immediately through the earphones.
**Deploy:** TFTP (U-Boot) — Linux must NOT be booted
**SDK path:** `driver_examples/sai/interrupt_record_playback`
**Config overlay:** `mcuxsdk-projects/sai_interrupt_record_playback/`
**Hardware:** 4-pole CTIA headset (phone earbuds with inline mic) in **J6**

**Steps:**
1. Plug CTIA headset into **J6**
2. In VS Code: **Run Task → "Copy to TFTP dir"** (builds + copies `sai_loopback.bin`)
3. Catch U-Boot, paste:
   ```
   setenv ipaddr 192.168.7.2; setenv serverip 192.168.7.1; setenv netmask 255.255.255.0; tftp 0x48000000 sai_loopback.bin; cp.b 0x48000000 0x7e0000 ${filesize}; bootaux 0x7e0000
   ```
4. Speak into the mic — hear yourself live

---

### 6.4 RPMsg String Echo

**What:** Bidirectional A53↔M7 messaging. Send strings from Linux; the M7 echoes
them back via RPMsg. Demonstrates the inter-processor communication channel.
**Deploy:** remoteproc (VS Code task)
**SDK path:** `multicore_examples/rpmsg_lite_str_echo_rtos/remote`
**Config overlay:** `mcuxsdk-projects/rpmsg_lite_str_echo_rtos/`

> **prj.conf patch required** — see `mcuxsdk-projects/rpmsg_lite_str_echo_rtos/`.
> The SDMA driver must be disabled or remoteproc rejects the ELF.
> See [docs/05-known-issues.md](docs/05-known-issues.md) for details.

**Steps:**
1. Open `picocom -b 115200 /dev/ttyUSB3` **before** deploying
2. In VS Code: **Run Task → "Deploy to M7 (remoteproc)"**
3. ttyUSB3 shows:
   ```
   RPMSG String Echo FreeRTOS RTOS API Demo...
   Nameservice sent, ready for incoming messages...
   ```
4. On the board:
   ```bash
   modprobe imx_rpmsg_tty
   # Read M7 echo responses in background:
   cat /dev/ttyRPMSG30 &
   # Send a message:
   echo "hello M7" > /dev/ttyRPMSG30
   # Output: hello M7    (echoed back by M7)
   ```
5. ttyUSB3 shows:
   ```
   Get Message From Master Side : "hello M7" [len : 8]
   ```

---

### 6.5 SAI Low Power Audio

**What:** SRTM audio co-processor demo — Linux streams audio files via RPMsg,
M7 drives the SAI hardware.
**Deploy:** remoteproc (VS Code task)
**Status:** ⚠️ M7 starts but no audio card appears on Linux

**Root cause:** SDK 26.06.00 SRTM protocol ≠ kernel 5.4.70 `imx-audio-rpmsg` driver.
The sound card registration always fails with `-EPROBE_DEFER`.

**Fix:** Rebuild with MCUXpresso SDK 2.9.x (matching kernel 5.4.x era). See
[docs/05-known-issues.md](docs/05-known-issues.md).

---

## 7. Zephyr on M7

The Zephyr RTOS also targets the M7 core. Use the TFTP workflow to load Zephyr
`.bin` files via U-Boot.

### Build

```bash
cd ~/zephyrproject/zephyr

# Synchronization sample (prints thread_a/thread_b forever — good for port testing)
west build -b imx8mp_evk/mimx8ml8/m7 samples/synchronization -d build/m7_sync

# Interactive shell
west build -b imx8mp_evk/mimx8ml8/m7 samples/subsys/shell/shell_module -d build/m7_shell
```

### Deploy via TFTP

```bash
cp build/m7_sync/zephyr/zephyr.bin ~/tftp/sync.bin
```

U-Boot:
```
setenv ipaddr 192.168.7.2; setenv serverip 192.168.7.1; setenv netmask 255.255.255.0; tftp 0x48000000 sync.bin; cp.b 0x48000000 0x7e0000 ${filesize}; bootaux 0x7e0000
```

VS Code configs for Zephyr builds are in `zephyr/.vscode/`.

---

## 8. Known Issues

| Issue | Symptom | Fix |
|---|---|---|
| SRTM mismatch | `sai_low_power_audio` no audio | Use SDK 2.9.x |
| `saveenv` not persisting | remoteproc0 missing after reboot | Re-set `fdt_file` at U-Boot each boot |
| SDMA phdr rejected | `bad phdr da 0x80000000` | `prj.conf` patch: `sdma=n` (included) |
| No J-Link | Debug attach unavailable | Buy J-Link EDU Mini, connect to J17 |
| Network resets | `No route to host` after reboot | Re-run `ip addr add` on both sides |

Full details: [docs/05-known-issues.md](docs/05-known-issues.md)

---

## 9. Memory Map Reference

| Region | A53 address | M7 address | Size |
|---|---|---|---|
| ITCM | `0x007E0000` | `0x00000000` | 128 KB |
| DTCM | `0x00800000` | (M7 data bus) | 128 KB |
| DDR scratch (TFTP pad) | `0x48000000` | — | any |
| DDR M7 (`m7/ddr` variant) | `0x80000000` | `0x80000000` | up to 16 MB |

The M7's reset vector is at M7-`0x00000000` = A53-`0x007E0000`. `bootaux 0x7e0000`
releases the M7 from reset pointing there.

---

## Repository Structure

```
.
├── scripts/            start-tftp.sh, stop-tftp.sh, m7-remoteproc.sh
├── docs/               hardware, network, TFTP, remoteproc, known-issues
├── mcuxsdk-projects/   .vscode/tasks.json and prj.conf overlays per example
└── zephyr/             .vscode/settings.json and launch.json for Zephyr workspace
```
