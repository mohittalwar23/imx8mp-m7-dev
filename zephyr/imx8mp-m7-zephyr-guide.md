# Running Zephyr on the i.MX8M Plus EVK Cortex-M7

End-to-end guide for booting a Zephyr sample on the **Cortex-M7** core of the
NXP i.MX8M Plus EVK, **without an SD card and without touching Yocto**.
The M7 firmware is pulled over Ethernet from a temporary TFTP server on the
laptop, copied into the M7's ITCM, and started from U-Boot.

*Verified working: 2026-05-25 (TFTP path). YMODEM fallback verified 2026-05-21.*

---

## 1. Overview

The i.MX8MP has a quad Cortex-A53 cluster plus a single Cortex-M7. The M7 has
**no flash of its own** — the A53 side (U-Boot or Linux) must load the M7
firmware into RAM and release the M7 from reset.

The path used here:

- Build a Zephyr `.bin` for the M7.
- From U-Boot, pull the `.bin` over Ethernet via **TFTP** into a DDR scratch
  area, then `cp.b` it into the M7's tightly-coupled memory (ITCM) and start
  the M7 with `bootaux`.
- The laptop runs a throwaway TFTP server (`dnsmasq` with DNS disabled) on a
  **point-to-point Ethernet link** to the board. No SD card, your WiFi
  internet is untouched, and your home network is not involved.
- **Yocto on the eMMC is never touched.** Everything is RAM-only and
  `saveenv` is never run. A power-cycle returns the board to its exact prior
  state.

Why not Linux `remoteproc` (original assumption — now corrected): the board
runs NXP BSP **L5.4.70_2.3.0** (kernel `5.4.70-2.3.2`). Originally assumed
remoteproc was non-functional, but the kernel has `CONFIG_REMOTEPROC=y` and
`CONFIG_IMX_REMOTEPROC=y` built in, and `imx8mp-evk-rpmsg.dtb` is already on
the FAT partition. **Remoteproc works — see §11** for the full Linux-side deploy
workflow (recommended for MCUXpresso SDK examples).

Why TFTP instead of YMODEM-over-serial: TFTP transfers a 64 KB image in well
under a second versus ~10 s on YMODEM, and avoids YMODEM's picocom-protocol /
wrong-port pitfalls. YMODEM remains here as the **no-Ethernet fallback** (§7).

---

## 2. Host environment

| Item | Value |
|---|---|
| Zephyr tree | `/home/mohit/zephyrproject/zephyr` (v4.2.99) |
| `west` | v1.5.0 (`/home/mohit/bin/west`) |
| Zephyr SDK | 0.17.4 (`/home/mohit/Downloads/zephyr-sdk-0.17.4_linux-x86_64/zephyr-sdk-0.17.4`) — provides `arm-zephyr-eabi` for the M7 |
| TFTP server | `dnsmasq-base` 2.90, one-shot mode (no service, no system config touched) |
| Terminal tool | `picocom` v3.1 |
| Wired NIC | `enp43s0` — used for the point-to-point link to the board |
| WiFi NIC | `wlp0s20f3` — your internet; **untouched** by anything here |

---

## 3. Serial ports

The EVK's debug micro-USB enumerates **four** `/dev/ttyUSB*` ports:

| Port | Role |
|---|---|
| `/dev/ttyUSB0` | JTAG / unused |
| `/dev/ttyUSB1` | JTAG / unused |
| `/dev/ttyUSB2` | **A53 console** — U-Boot prompt + Linux console (UART2) |
| `/dev/ttyUSB3` | **M7 console** — Zephyr output (UART4) |

All at **115200 8N1**, no flow control. picocom exit: `Ctrl-A Ctrl-X`.

---

## 4. Memory map — what each address actually means

Several memories are visible to both cores, but at **different addresses on
each side**. Source: the board doc (`boards/nxp/imx8mp_evk/doc/index.rst`).

| Region | A53 view | M7 (Code Bus) | Size | Role in this guide |
|---|---|---|---|---|
| **ITCM** | `0x007E0000` | `0x00000000` | 128 KB | Where the M7 executes from. The M7's reset vector is at *its* `0x00000000`, which the A53 sees as `0x007E0000`. |
| **DTCM** | `0x00800000` | (M7-side data) | 128 KB | M7 data/stack — managed by the linker, not addressed by us here. |
| **DDR scratch** | `0x48000000` | — | n/a | A free spot in main DDR we use as a **TFTP landing pad**. Not special — any free DDR address would do. We don't execute from here for the ITCM build. |
| **DDR (M7 code)** | `0x80000000` | `0x80000000` | 2 MB | Used only by the `imx8mp_evk/mimx8ml8/m7/ddr` build variant, for apps too big for the 128 KB ITCM. |

Two consequences worth understanding before reading the commands below:

1. **Why `bootaux 0x7e0000`.** Zephyr's M7 ELF is linked for `0x00000000` (the
   M7's view). To run it, we must place the binary so the M7 sees its vector
   table at `0x00000000` — i.e. at the A53-side ITCM address `0x007E0000`.
   `bootaux 0x7e0000` releases the M7 from reset with its boot pointer set
   there; the M7 fetches its first instruction from M7-`0x00000000`, which is
   the same memory.

2. **Why two-stage load (DDR scratch → ITCM).** U-Boot's `tftp` can load to
   any address, but downloading directly into ITCM is brittle (small region,
   network errors can land mid-write, easier to bus-error). Pulling into
   plenty of DDR first and *then* atomically `cp.b`'ing into ITCM is what NXP
   documents, and it lets you reuse the DDR landing pad across runs.

---

## 5. Building samples

```bash
cd /home/mohit/zephyrproject/zephyr

# one-shot greeting (banner only at boot)
west build -b imx8mp_evk/mimx8ml8/m7 samples/hello_world -d build/m7_hello

# continuously printing — useful for confirming which ttyUSB is the M7 console
west build -b imx8mp_evk/mimx8ml8/m7 samples/synchronization -d build/m7_sync

# dining philosophers — colorful ANSI demo
west build -b imx8mp_evk/mimx8ml8/m7 samples/philosophers -d build/m7_philosophers

# interactive shell over UART4
west build -b imx8mp_evk/mimx8ml8/m7 samples/subsys/shell/shell_module -d build/m7_shell

# shell + GPIO sub-command + per-thread CPU usage
west build -p always -b imx8mp_evk/mimx8ml8/m7 samples/subsys/shell/shell_module -d build/m7_shell_v2 \
  -- -DCONFIG_GPIO_SHELL=y -DCONFIG_THREAD_RUNTIME_STATS=y
```

Output binary: `build/<dir>/zephyr/zephyr.bin`. ITCM cap is 128 KB; if a build
overflows it, switch to the DDR board target (`imx8mp_evk/mimx8ml8/m7/ddr`).

> **No `blinky` on this board.** The EVK has only a power LED and a
> UART-activity LED, both hardware-wired. There's no `led0` alias in the
> board files, so `samples/basic/blinky` fails to build. To blink something
> visible, attach an LED to a free GPIO pin on the 40-pin expansion header
> and supply a small devicetree overlay defining `led0`.

---

## 6. TFTP boot procedure (the recommended path)

### 6.1 Stage the binaries — `/home/mohit/tftp/`

The TFTP server hands files out of one directory:

```bash
mkdir -p /home/mohit/tftp
cp build/m7_sync/zephyr/zephyr.bin           /home/mohit/tftp/sync.bin
cp build/m7_hello/zephyr/zephyr.bin          /home/mohit/tftp/hello.bin
cp build/m7_philosophers/zephyr/zephyr.bin   /home/mohit/tftp/philosophers.bin
cp build/m7_shell_v2/zephyr/zephyr.bin       /home/mohit/tftp/shell.bin
```

Re-copy after each rebuild. Naming files `<sample>.bin` lets us boot any of
them from U-Boot with one short command.

### 6.2 Cabling

Run the Ethernet cable **straight from the laptop's `enp43s0` port to one of
the board's two RJ45 jacks**. The EVK has two — U-Boot only drives one at a
time (`ethact`); if the link doesn't come up later, swap to the other jack.
**Do not go via your home router** — that would pull the board onto your home
subnet and require completely different IPs.

### 6.3 Bring up the link + TFTP server (one command)

The whole host-side setup is captured in `/home/mohit/start-tftp.sh` (to
avoid paste/line-break problems with long sudo lines). Run:

```bash
sudo sh /home/mohit/start-tftp.sh
```

What it does, and *why* each line:

```sh
nmcli device set enp43s0 managed no
```
NetworkManager auto-runs DHCP the moment a freshly-linked port comes up. If
we don't take it out of NM's hands, it'll happily lease `192.168.1.x` from
your home router and fight our static config. `managed no` is the clean,
runtime-only way to tell NM "don't touch this NIC". A reboot restores NM
management — just re-run the script after boot.

```sh
ip addr flush dev enp43s0
ip addr add 192.168.7.1/24 dev enp43s0
ip link set enp43s0 up
```
Flush any stale addresses (e.g. a DHCP-acquired `192.168.1.102` left over
from when the cable was last on a router), then assign the static
point-to-point IP `192.168.7.1/24`. `192.168.7.0/24` is just a private range
**chosen not to collide with the home network** at `192.168.1.x` or the
common `192.168.0.x`.

```sh
dnsmasq --conf-file=/dev/null --port=0 --enable-tftp \
        --tftp-root=/home/mohit/tftp --interface=enp43s0 --bind-interfaces \
        --user=mohit --log-facility=/home/mohit/tftp/dnsmasq.log --log-debug
```
A throwaway TFTP-only `dnsmasq`. Each flag:

- `--conf-file=/dev/null` — skip `/etc/dnsmasq.conf` and `/etc/dnsmasq.d/`.
  Guarantees no system config sneaks in.
- `--port=0` — disable the DNS resolver. We only want TFTP. Avoids any
  collision with systemd-resolved or another resolver on port 53.
- `--enable-tftp --tftp-root=/home/mohit/tftp` — turn the TFTP server on,
  rooted at our staging directory.
- `--interface=enp43s0 --bind-interfaces` — bind exactly one socket to that
  one NIC. Without `--bind-interfaces`, dnsmasq listens on `0.0.0.0` and
  filters by interface, which can leak across interfaces. With it, you get a
  strict per-NIC bind that won't touch WiFi.
- `--user=mohit` — dnsmasq binds privileged port 69 as root then drops
  privileges. Its default user is `nobody`, which **can't traverse
  `/home/mohit` (mode 0750)** → "TFTP directory inaccessible: Permission
  denied". Dropping to `mohit` is the fix.
- `--log-facility=…/dnsmasq.log --log-debug` — log every TFTP request to a
  file, so we can see hits and misses (`sent /home/mohit/tftp/sync.bin to
  192.168.7.2`).

`dnsmasq` daemonizes itself; the script then prints a status block (`enp43s0
= …`, `dnsmasq: running`) and returns to the prompt.

To undo (kill dnsmasq, flush the static IP, hand `enp43s0` back to NM):

```bash
sudo sh /home/mohit/stop-tftp.sh
```

### 6.4 U-Boot — load, copy, boot

Open the U-Boot console (plain picocom — no YMODEM tweaks needed):

```bash
picocom -b 115200 /dev/ttyUSB2
```

Power-cycle the board (or `reset` from a live U-Boot prompt). At
`Hit any key to stop autoboot`, press any key → `u-boot=>`.

Then, as **one paste**:

```
setenv ipaddr 192.168.7.2; setenv serverip 192.168.7.1; setenv netmask 255.255.255.0; tftp 0x48000000 sync.bin; cp.b 0x48000000 0x7e0000 ${filesize}; bootaux 0x7e0000
```

Reading it left-to-right:

- `setenv ipaddr 192.168.7.2` — the **board's** static IP on the
  point-to-point link. Same /24 as the laptop's `192.168.7.1`.
- `setenv serverip 192.168.7.1` — where to fetch from. This is the
  laptop's `enp43s0` address, where dnsmasq is listening.
- `setenv netmask 255.255.255.0` — explicit /24. U-Boot can infer
  classful netmasks, but being explicit avoids any guess.
- These three `setenv`s are **RAM-only** — we never `saveenv`. They
  vanish on reset; Yocto's saved env stays untouched.
- `tftp 0x48000000 sync.bin` — pull `/home/mohit/tftp/sync.bin` from the
  server into DDR at `0x48000000`. On success, U-Boot also sets the
  `filesize` env to the number of bytes received. **Always pass both the
  address and the filename** — bare `tftp` makes U-Boot invent a filename
  from the IP (e.g. `C0A80702.img`), which obviously isn't on the server.
- `cp.b 0x48000000 0x7e0000 ${filesize}` — byte-copy `filesize` bytes from
  the DDR landing pad into the A53-side ITCM aperture. ITCM is the memory
  the M7 will execute from (M7-`0x00000000` ↔ A53-`0x007E0000`).
- `bootaux 0x7e0000` — i.MX-specific U-Boot command: release the M7 from
  reset with its initial PC set to `0x7e0000`. The M7 immediately starts
  executing Zephyr's reset handler out of ITCM.

A good run prints:
```
Bytes transferred = 19004 (0x4a3c)
…
## Starting auxiliary core stack = 0x20000F78, pc = 0x00000C85...
```

### 6.5 Watch the M7

```bash
picocom -b 115200 /dev/ttyUSB3
```

`sync.bin` prints `thread_a` / `thread_b` lines every second. For
`shell.bin`, **press Enter** to get the `uart:~$` prompt.

### 6.6 Boot Linux too (optional)

In the U-Boot terminal (the M7 keeps running independently after `bootaux`):

```
boot
```

Yocto boots normally; Zephyr keeps running on the M7.

---

## 7. Fallback: YMODEM over the serial console (no network)

Without an Ethernet cable, you can send the binary in-band over the U-Boot
console using YMODEM. It's slow (~10 s for 64 KB) but needs zero networking.

picocom defaults its file-send to ZMODEM (`sz`); `loady` only understands
YMODEM (`sb`). Launch picocom with the YMODEM sender:

```bash
picocom -b 115200 --send-cmd "sb -v" /dev/ttyUSB2
```

Confirm the picocom banner shows `send_cmd is : sb -v` (not `sz`).

At `u-boot=>`:
```
loady 0x48000000
```
Then `Ctrl-A Ctrl-S` in picocom, enter the local path to `zephyr.bin`, wait
for `## Total Size = …`, then:
```
cp.b 0x48000000 0x7e0000 ${filesize}
bootaux 0x7e0000
```

YMODEM-specific gotchas:
- **Wrong protocol.** Default ZMODEM won't talk to `loady`. Use `--send-cmd "sb -v"`.
- **Wrong port.** The transfer is *in-band on the U-Boot console* (ttyUSB2). Send the file from that same picocom window — not from ttyUSB3.

---

## 8. Gotchas

1. **`bootaux` is one-shot per reset.** If the M7 is already running, a
   second `bootaux` just prints `## Auxiliary core is already up` and does
   nothing — your new image never starts. Rule: to load a different image,
   `reset` first, then a single `tftp` → `cp.b` → `bootaux`.

2. **Bare `tftp` invents a filename.** With no args, U-Boot uses the
   `bootfile` env, or failing that a default name derived from the IP
   (`192.168.7.2` → `C0A80702.img`). Always pass `tftp <addr> <name>`.

3. **First `ping`/`tftp` may ARP-time out.** The PHY takes a moment to
   establish link on the first network command. Retry once.

4. **Two RJ45 jacks on the EVK.** U-Boot's `ethact` only drives one of them.
   If `ping 192.168.7.1` fails with `ARP Retry count exceeded`, move the
   cable to the other jack.

5. **dnsmasq "Permission denied".** Caused by the default `nobody` user
   being unable to traverse `/home/mohit` (mode 0750). `--user=mohit` fixes
   it; `start-tftp.sh` already does this.

6. **Cable into a router, not the board.** If `enp43s0` quietly picks up a
   `192.168.1.x` lease, the cable is on your home network, not the board.
   Move it. `start-tftp.sh` flushes the address and reasserts static.

7. **`hello_world` prints only once.** Easy to miss while hunting for the
   M7 serial port. Use `sync.bin` (prints forever) when locating the port.

8. **No user LED on this board.** Stock `blinky` won't build — there's no
   `led0` alias. The EVK only has a power LED and a UART-activity LED.

---

## 9. Quick reference

```bash
# HOST: bring up enp43s0 + TFTP server (once per boot)
sudo sh /home/mohit/start-tftp.sh

# HOST: U-Boot console
picocom -b 115200 /dev/ttyUSB2

# HOST: M7 console (another terminal)
picocom -b 115200 /dev/ttyUSB3
```

```
# BOARD (u-boot=>): power-cycle, catch autoboot, then one paste:
setenv ipaddr 192.168.7.2; setenv serverip 192.168.7.1; setenv netmask 255.255.255.0; tftp 0x48000000 <name>.bin; cp.b 0x48000000 0x7e0000 ${filesize}; bootaux 0x7e0000
```

Replace `<name>` with `sync`, `hello`, `philosophers`, `shell`, etc.
To swap images: `reset`, catch U-Boot, re-paste with a different `<name>`.

```bash
# HOST: tear down (optional)
sudo sh /home/mohit/stop-tftp.sh
```

---

## 10. Notes

- Nothing is written to eMMC; `saveenv` is never used. A power-cycle clears
  the M7 (RAM-only) and leaves Yocto exactly as it was.
- DDR build variant: `-b imx8mp_evk/mimx8ml8/m7/ddr` loads at `0x80000000`
  on both A53 and M7 sides, so the `cp.b` step is skipped. Flow becomes
  `tftp 0x80000000 <name>.bin; dcache flush; bootaux 0x80000000`. The
  `dcache flush` is needed because the A53's data cache has dirty lines
  for the bytes the M7 is about to fetch via its code bus.

---

## 11. Linux remoteproc workflow (MCUXpresso SDK ELF deploy)

*Verified working: 2026-06-07. Contrary to original assumption, remoteproc
works fine on the 5.4.70 kernel — no new BSP needed.*

### 11.1 One-time boot setup (each power cycle)

**On laptop** — this laptop's wired NIC is `eno1` (not `enp43s0`):
```bash
sudo ip addr add 192.168.7.1/24 dev eno1
```

**On board** (ttyUSB2 serial console). First, catch U-Boot autoboot:
```
setenv fdt_file imx8mp-evk-rpmsg.dtb; saveenv; boot
```
> `saveenv` may not persist across all power cycles on this image — always
> check U-Boot and re-set if needed.

After Linux boots, log in as root and set static IP:
```bash
ip addr add 192.168.7.2/24 dev eth0
```

Verify: `ls /sys/class/remoteproc/` should show `remoteproc0`.

### 11.2 SSH/SCP quirks (old Dropbear)

The board runs Dropbear SSH which only offers `ssh-rsa` and has no sftp-server.
Always add these flags:
```bash
scp -O -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa
ssh    -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa
```

### 11.3 Deploy an ELF

```bash
# Copy ELF to board
scp -O -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    <path-to>.elf root@192.168.7.2:/lib/firmware/m7-app.elf

# Start M7 via remoteproc
ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    root@192.168.7.2 \
    'echo stop > /sys/class/remoteproc/remoteproc0/state 2>/dev/null; \
     sleep 0.5; \
     echo -n m7-app.elf > /sys/class/remoteproc/remoteproc0/firmware; \
     echo start > /sys/class/remoteproc/remoteproc0/state; \
     echo M7 state: $(cat /sys/class/remoteproc/remoteproc0/state)'
```

