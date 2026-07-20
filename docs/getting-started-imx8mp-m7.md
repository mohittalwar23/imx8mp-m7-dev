# Getting Started with the i.MX8M Plus EVK: Your First Firmware on the Cortex-M7

You've just unboxed an i.MX8M Plus EVK. You want to run your own code on its Cortex-M7. You've done this on an STM32 or an nRF board before, so you go looking for the flash command — and there isn't one.

This guide is the path from that moment to a working, repeatable firmware workflow. I wrote it while doing it for the first time myself, as groundwork for porting an audio pipeline to this board, so it's ordered the way you'll actually hit things rather than the way a reference manual would organize them.

**Everything here is reproducible.** Every command is one I run, every log line is pasted from a real terminal. The reference setup — scripts, VS Code configs, per-example overlays — lives in **[mohittalwar23/imx8mp-m7-dev](https://github.com/mohittalwar23/imx8mp-m7-dev)**.

**What you'll have at the end:** Zephyr running on the M7, loaded over Ethernet in about five seconds, plus a second workflow that loads it from Linux without a reboot.

---

## Contents

**Part 0** — [What you're holding](#part-0--what-youre-holding) · **Part 1** — [First power-on](#part-1--first-power-on) · **Part 2** — [The memory map](#part-2--the-memory-map-and-why-bootaux-looks-like-magic) · **Part 3** — [Host setup](#part-3--host-setup-a-tftp-server-on-a-direct-cable) · **Part 4** — [Your first load](#part-4--your-first-firmware-load) · **Part 5** — [No-network fallback](#part-5--the-no-network-fallback-ymodem) · **Part 6** — [remoteproc](#part-6--the-other-way-loading-from-linux-with-remoteproc) · **Part 7** — [SDK examples](#part-7--working-through-the-mcuxpresso-examples) · **Part 8** — [Zephyr](#part-8--zephyr-on-the-m7) · **Part 9** — [Troubleshooting](#part-9--troubleshooting-reference)

---

## Part 0 — What you're holding

### 0.1 The chip

The i.MX8M Plus is **heterogeneous**: it has two completely different CPU complexes on one die.

![i.MX 8M Plus: Cortex-A53 cluster running Linux alongside a Cortex-M7, HiFi4 DSP and NPU](https://raw.githubusercontent.com/mohittalwar23/imx8mp-m7-dev/main/docs/diagrams/01-soc-overview.png)

Zephyr and the MCUXpresso examples target the **M7**. The A53 cluster runs Linux and handles the heavy lifting. The M7 is the real-time co-processor — in my case it will eventually own an audio pipeline.

### 0.2 The thing that makes this board different

Here's the catch that shapes everything else:

> ### The M7 has no flash of its own.

There is no "flash the M7" command because there is nothing to flash. The **A53 side must load M7 firmware into RAM and then release the M7 from reset.** Something else always does the loading.

![Boot chain: power on to U-Boot SPL to ATF to U-Boot, then forking to bootaux or Linux remoteproc](https://raw.githubusercontent.com/mohittalwar23/imx8mp-m7-dev/main/docs/diagrams/02-boot-chain.png)

So your first real problem isn't writing M7 code. It's **handing the M7 a binary.** There are two ways, and this guide sets up both:

![Decision tree: exclusive peripheral access picks Path A (U-Boot TFTP), otherwise Path B (remoteproc)](https://raw.githubusercontent.com/mohittalwar23/imx8mp-m7-dev/main/docs/diagrams/03-workflow-decision.png)

I use **Path A** day to day, because audio bring-up wants the M7 to have the SAI to itself. Path B has a much faster edit-run loop, so it wins for everything else.

### 0.3 What you need

| Item | Notes |
|---|---|
| **i.MX8M Plus EVK** | Mine reports `Model: NXP i.MX8MPlus LPDDR4 EVK board`, **6 GiB** DRAM, BSP **L5.4.70_2.3.2** on eMMC — **no reflash needed** |
| **USB-C power supply** | The board negotiates USB-C PD and requests **20 V @ 2.25 A**. A supply that can't offer a 20 V PDO will give you trouble |
| **USB micro-B cable** | Debug console, port **J15** |
| **Ethernet cable** | Straight to your laptop, no router. **Which of the two jacks matters** — see §4.4 |
| **4-pole CTIA headset** | Phone earbuds with inline mic, port **J6**. Needed only for the audio examples |
| J-Link EDU Mini *(optional)* | Only for JTAG debug on **J17**. I don't have one; nothing in this guide needs it |

Host side — my versions, for reference on skew:

| Component | Version |
|---|---|
| Host OS | Ubuntu, kernel 6.17 |
| picocom | v3.1 |
| MCUXpresso SDK | **26.06.00** (reports `2026.06.00-pvw2`) |
| Zephyr / Zephyr SDK | **4.4.99** / 1.0.1 |

```bash
sudo apt install picocom dnsmasq-base
```

> **Note the version gap.** The board's BSP is **kernel 5.4.70** (2020). The SDK is **26.06.00** (2026). That six-year gap is invisible until it isn't — it breaks exactly one example, in §7.5.

---

## Part 1 — First power-on

Do this before you write or build anything. The goal is only to prove you can talk to the board.

### Step 1.1 — Set the DIP switches

**SW4** selects boot mode. Leave it at normal eMMC boot:

| Mode | SW4[1] | SW4[2–4] |
|---|---|---|
| **Normal eMMC boot** ← you want this | ON | OFF |
| USB Serial Download (UUU reflash) | OFF | OFF |

### Step 1.2 — Plug in, and find your serial ports

Connect USB micro-B to **J15**, then power on. The debug chip is an FT4232H that enumerates **four** ports — and only two of them are useful.

```bash
$ lsusb | grep -i future
Bus 003 Device 121: ID 0403:6011 Future Technology Devices International, Ltd FT4232H Quad HS USB-UART/FIFO IC

$ ls /dev/ttyUSB*
/dev/ttyUSB0  /dev/ttyUSB1  /dev/ttyUSB2  /dev/ttyUSB3
```

![FT4232H on J15 enumerates four ttyUSB ports; ttyUSB2 is the A53 console and ttyUSB3 the M7 console](https://raw.githubusercontent.com/mohittalwar23/imx8mp-m7-dev/main/docs/diagrams/04-serial-ports.png)

All four are **115200 8N1**. Despite the FT4232H being a JTAG-capable part, **J15 gives you UARTs only** — real JTAG needs an external probe on J17.

> **If you see no `/dev/ttyUSB*` at all:** check the cable first, then your group membership — `sudo usermod -aG dialout $USER`, then log out and back in.

### Step 1.3 — Catch U-Boot

Open the A53 console *before* powering on, so you don't miss the window:

```bash
picocom -b 115200 /dev/ttyUSB2
```

Power-cycle, and **mash a key** as it boots. You're aiming for a two-second window. You should land here:

```
U-Boot SPL 2020.04-5.4.70-2.3.2+g185bdaaaf5 (Apr 02 2021 - 17:52:17 +0000)
DDRINFO: DRAM rate 4000MTS
NOTICE:  BL31: v2.2(release):imx_5.4.70_er5-4-g2a2678646

U-Boot 2020.04-5.4.70-2.3.2+g185bdaaaf5 (Apr 02 2021 - 17:52:17 +0000)

CPU:   i.MX8MP[8] rev1.1 1800 MHz (running at 1200 MHz)
CPU:   Commercial temperature grade (0C to 95C) at 33C
Reset cause: POR
Model: NXP i.MX8MPlus LPDDR4 EVK board
DRAM:  6 GiB
...
Net:   eth0: ethernet@30be0000, eth1: ethernet@30bf0000 [PRIME]
Hit any key to stop autoboot:  2  0
u-boot=>
```

**Three lines to notice now, because they matter later:**

1. **`Hit any key to stop autoboot: 2`** — a *two second* window. Have the terminal focused and hold a key down while powering on.
2. **`Net: ... eth1: ethernet@30bf0000 [PRIME]`** — write down which device is PRIME. This costs you 40 seconds in §4.4 if you ignore it.
3. **`Model: ... LPDDR4 EVK board`** — confirms which EVK variant you have.

**Errors you should ignore.** Before the prompt you'll see a wall of video complaints:

```
Can't find cec device id=0x3c
fail to probe panel device adv7535@3d
probe video device failed, ret -19
```

That's U-Boot looking for the ADV7535 HDMI bridge with no display attached. Nothing to do with the M7, nothing to do with you. I spent real time worrying about this the first time.

> ✅ **Checkpoint 1:** you have a `u-boot=>` prompt. That's the whole goal of Part 1.

### Step 1.4 — A habit worth forming now

`picocom -g` logs the session to a file:

```bash
picocom -b 115200 -g ~/uboot.log /dev/ttyUSB2
```

Every log line in this guide came out of `-g`. When you're bringing up something unfamiliar, having the exact text — rather than your memory of it — is the difference between fixing a problem and re-encountering it.

---

## Part 2 — The memory map (and why `bootaux` looks like magic)

Skip this and the commands in Part 4 will feel arbitrary. It's five minutes.

Several memories on this chip are visible to **both cores, at different addresses**:

![ITCM seen at 0x007E0000 from the A53 and at 0x00000000 from the M7 - the same physical bytes](https://raw.githubusercontent.com/mohittalwar23/imx8mp-m7-dev/main/docs/diagrams/05-memory-map.png)

| Region | A53 address | M7 address | Size |
|---|---|---|---|
| **ITCM** (M7 code) | `0x007E0000` | `0x00000000` | 128 KB |
| DTCM (M7 data) | `0x00800000` | `0x20000000` | 128 KB |
| DDR scratch (TFTP landing pad) | `0x48000000` | — | any |
| DDR M7 (`m7_ddr` variant) | `0x80000000` | `0x80000000` | up to 16 MB |

The M7's reset vector sits at **its** `0x00000000`. The A53 sees those same physical bytes at `0x007E0000`. So:

```
bootaux 0x7e0000
```

means *"release the M7 from reset, pointing at the A53-side address of the M7's vector table."*

**U-Boot shows you this happening.** It prints the entry point it read out of that vector table:

```
## Starting auxiliary core stack = 0x20001948, pc = 0x00000E55...
```

You handed it `0x7e0000`, and it reports a **`pc` of `0x00000E55`** — a low address in the M7's own map, not the A53's. Same bytes, two names. The stack at `0x20001948` is DTCM as the M7 sees it. That one line is the dual-address idea made concrete.

Those two values aren't magic constants — they're read out of whatever vector table you just loaded, so they change per firmware. The MCUXpresso SAI example reports `stack = 0x20020000, pc = 0x0000048D` instead. Different entry point, same two regions.

### Why the load takes two stages

You do **not** TFTP straight into ITCM. It's a small region, and a mid-transfer network hiccup can drop you into a bus error. Instead:

![Three-stage load: tftp into DDR at 0x48000000, cp.b into ITCM at 0x7E0000, then bootaux](https://raw.githubusercontent.com/mohittalwar23/imx8mp-m7-dev/main/docs/diagrams/06-tftp-stages.png)

Land it in spare DDR first, then copy into ITCM. `0x48000000` isn't special — it's just a free spot well clear of everything else. This is the pattern NXP documents and it's meaningfully more robust.

### 128 KB is your real budget

Zephyr reports ITCM as its `FLASH` region, and it fills faster than you'd expect:

```
Memory region         Used Size  Region Size  %age Used
           FLASH:       20932 B       128 KB     15.97%     # synchronization
           FLASH:       69524 B       128 KB     53.04%     # shell_module
```

The shell sample is already at half. When you outgrow it, that's what the `m7_ddr` board variant and the DDR region are for.

---

## Part 3 — Host setup: a TFTP server on a direct cable

I didn't want the board near my router or WiFi, and I didn't want to touch the Yocto image on eMMC. So: direct cable, RAM-only, nothing persistent.

![Direct Ethernet between laptop at 192.168.7.1 and board at 192.168.7.2, with WiFi keeping the default route](https://raw.githubusercontent.com/mohittalwar23/imx8mp-m7-dev/main/docs/diagrams/07-network.png)

### Step 3.1 — Pin the laptop to 192.168.7.1 (once, permanently)

Most guides tell you to `ip addr add` the address and then wrestle NetworkManager into leaving it alone. I did that for a while. It's better to just tell NetworkManager what you want, so it cooperates instead of fighting:

```bash
sudo nmcli connection modify "Wired connection 1" \
     ipv4.method manual \
     ipv4.addresses 192.168.7.1/24 \
     ipv4.gateway "" \
     ipv4.never-default yes
sudo nmcli connection up "Wired connection 1"
```

**`ipv4.gateway ""` and `never-default yes` are not optional.** Without them your laptop installs the board link as its default route and tries to reach the internet through a dev board that isn't routing anything. Verify WiFi still owns the default route:

```bash
$ ip route | head -2
default via 192.168.1.1 dev wlo1 proto dhcp src 192.168.1.46 metric 600
192.168.7.0/24 dev eno1 proto kernel scope link src 192.168.7.1 metric 100
```

Permanent, survives reboots, no per-session `ip addr` dance.

### Step 3.2 — Start the TFTP server

```bash
mkdir -p ~/tftp

sudo dnsmasq --conf-file=/dev/null --port=0 --enable-tftp \
             --tftp-root=/home/mt/tftp --interface=eno1 --bind-interfaces \
             --user=mt --log-facility=/home/mt/tftp/dnsmasq.log --log-debug
```

Scripted as [`scripts/start-tftp.sh`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/scripts/start-tftp.sh); undo with [`scripts/stop-tftp.sh`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/scripts/stop-tftp.sh).

Each flag is load-bearing, and three of them exist because of a bug I hit:

| Flag | Why |
|---|---|
| `--port=0` | dnsmasq is a **DNS server** that happens to do TFTP. Leave DNS on and it collides with `systemd-resolved` on port 53. This disables the DNS half entirely |
| `--user=mt` | See gotcha 2 below. Non-negotiable if your TFTP root is under `$HOME` |
| `--conf-file=/dev/null` | Ignore system config — this is a throwaway server, not a service |
| `--bind-interfaces` | Bind only `eno1`, don't listen everywhere |
| `--log-debug` | You want to see each file served |

> ✅ **Checkpoint 2 — is it listening?**
> ```bash
> $ ss -ulnp | grep :69
> UNCONN 0 0    192.168.7.1:69    0.0.0.0:*
> UNCONN 0 0      127.0.0.1:69    0.0.0.0:*
> ```
> and the log should confirm the DNS half is off:
> ```
> dnsmasq[341906]: started, version 2.90 DNS disabled
> dnsmasq-tftp[341906]: TFTP root is /home/mt/tftp
> ```

### Step 3.3 — Test TFTP *before* touching the board

This is the step I wish I'd done on day one. dnsmasq binds `127.0.0.1` too, so you can prove the entire server works from the laptop alone — no board, no cable, no U-Boot prompt:

```bash
$ curl -s -o /tmp/dl.bin tftp://127.0.0.1/sync.bin && cmp /tmp/dl.bin ~/tftp/sync.bin && echo OK
OK
```

If that fails, your problem is on the laptop and you'll fix it in seconds. If it passes and the board still can't fetch, the problem is the cable, the board's IP, or `serverip` — and you've halved the search space. Debugging a silent TFTP transfer through a U-Boot prompt is miserable; debugging it with `curl` is trivial.

### The four things that cost me time

Each of these produced an error pointing somewhere other than the actual problem.

#### Gotcha 1 — NetworkManager silently owning the address

The one that fooled me longest. I assumed NM was DHCP-ing over my static config. It wasn't:

```bash
$ nmcli -f ipv4.method,ipv4.addresses connection show "Wired connection 1"
ipv4.method:       manual
ipv4.addresses:    192.168.7.207/24
```

A **saved profile** was pinning `eno1` to a *manual static* `192.168.7.207/24`. No DHCP, no router. My `ip addr add 192.168.7.1/24` ran, NM reasserted the profile, and `.1` quietly disappeared.

Why it's so nasty: `.207` is still inside the board's `/24`. The link is up, the board at `.2` answers pings, everything **looks healthy**. But U-Boot was told `serverip 192.168.7.1` and nothing is listening there — so `tftp` emits `T T T` timeouts on a network that appears fine. You will blame your cable, your board, and your bootloader long before you blame a saved network profile.

**Check the profile, not just `ip addr`.** Step 3.1 avoids this permanently.

#### Gotcha 2 — the `--user` trap

This error blames TFTP for a filesystem problem. dnsmasq binds port 69 as root, then **drops privileges to `nobody`** — and `nobody` cannot traverse my home directory:

```bash
$ stat -c '%a %U %n' /home/mt
750 mt /home/mt
```

Mode `750`: group and others get nothing. So `nobody` can't even reach `/home/mt/tftp`, and the transfer fails with a permission error that has nothing to do with TFTP. `--user=mt` keeps dnsmasq running as me. (Putting the TFTP root somewhere world-traversable like `/srv/tftp` works too.)

#### Gotcha 3 — `--port=0` or fight systemd-resolved

Covered in the flag table above. Symptom is dnsmasq refusing to start at all because port 53 is taken.

#### Gotcha 4 — bare `tftp` invents a filename

Omit the filename argument and U-Boot derives one from the IP: `192.168.7.2` → **`C0A80702.img`**. You get a file-not-found for a file you never asked for. **Always pass both address and name.**

---

## Part 4 — Your first firmware load

Now the payoff. We'll load the Zephyr `synchronization` sample, because it prints forever — which makes it far better than `hello_world` for a first attempt, where you're still figuring out which console is which.

### Step 4.1 — Build it

```bash
cd ~/zephyrproject
source .venv/bin/activate

west build -b imx8mp_evk/mimx8ml8/m7 zephyr/samples/synchronization -d build/m7_sync
```

Watch the memory report — `20932 B` into the 128 KB ITCM. Then stage it:

```bash
cp build/m7_sync/zephyr/zephyr.bin ~/tftp/sync.bin
```

### Step 4.2 — Load it from U-Boot

Back at your `u-boot=>` prompt:

```
setenv ipaddr 192.168.7.2
setenv serverip 192.168.7.1
setenv netmask 255.255.255.0
setenv ethact eth0
tftp 0x48000000 sync.bin
cp.b 0x48000000 0x7e0000 ${filesize}
bootaux 0x7e0000
```

> **None of these are ever saved.** No `saveenv` — a power cycle wipes them and the Yocto environment on eMMC stays exactly as it was. That was deliberate: I wanted a workflow I couldn't accidentally brick the board with.

Real output from my board:

```
u-boot=> tftp 0x48000000 sync.bin
TFTP from server 192.168.7.1; our IP address is 192.168.7.2
Filename 'sync.bin'.
Load address: 0x48000000
Loading: *##
         10 MiB/s
done
Bytes transferred = 20932 (51c4 hex)

u-boot=> cp.b 0x48000000 0x7e0000 ${filesize}
u-boot=> bootaux 0x7e0000
## Starting auxiliary core stack = 0x20001948, pc = 0x00000E55...
```

> ✅ **Checkpoint 3:** `Bytes transferred` matches your `.bin` exactly — `20932`. At 10 MiB/s the transfer itself is instant.

### Step 4.3 — Watch the M7

Open the *other* console:

```bash
picocom -b 115200 /dev/ttyUSB3
```

```
*** Booting Zephyr OS build v4.4.0-5641-gb6cc7688ef7f ***
thread_a: Hello World from cpu 0 on imx8mp_evk!
thread_b: Hello World from cpu 0 on imx8mp_evk!
thread_a: Hello World from cpu 0 on imx8mp_evk!
thread_b: Hello World from cpu 0 on imx8mp_evk!
```

**That's it.** Two threads ping-ponging forever on a core that, twenty minutes ago, had no way to be given a program.

The M7 keeps running independently after `bootaux`. If you want Linux as well, just type `boot` at the U-Boot prompt — the A53 boots normally while the M7 carries on. That independence is the entire appeal of this path.

### Step 4.4 — If you saw 40 seconds of dots

Your first `tftp` may have looked like this:

```
ethernet@30bf0000 Waiting for PHY auto negotiation to complete...................... TIMEOUT !
phy_startup() failed: -110FAILED: -110Using ethernet@30be0000 device
TFTP from server 192.168.7.1; our IP address is 192.168.7.2
```

Remember the `Net:` line from §1.3:

```
Net:   eth0: ethernet@30be0000, eth1: ethernet@30bf0000 [PRIME]
```

The EVK has **two RJ45 jacks**. `eth1` is `[PRIME]` — U-Boot's default. My cable is in the *other* jack (`eth0`). So every `tftp` began by waiting ~40 seconds for auto-negotiation on an empty port, timing out with `-110` (`ETIMEDOUT`), then falling back to `eth0` and working perfectly.

It's not fatal — it self-recovers — which is exactly why you can donate 40 seconds to every load for weeks without noticing.

The fix is the `setenv ethact eth0` already in §4.2. Same board, same cable, with it set:

```
u-boot=> tftp 0x48000000 sai_tone.bin
ethernet@30be0000 Waiting for PHY auto negotiation to complete.... done
Using ethernet@30be0000 device
TFTP from server 192.168.7.1; our IP address is 192.168.7.2
Filename 'sai_tone.bin'.
Load address: 0x48000000
Loading: *######
         16.4 MiB/s
done
Bytes transferred = 85748 (14ef4 hex)
```

Four dots and `done`, instead of forty-odd and `TIMEOUT !`. Moving the cable to the `[PRIME]` jack does the same job in hardware.

Check your own `Net:` line — which device is PRIME is a property of your board and which jack you used, so don't assume mine matches yours.

Full details: [`docs/03-uboot-tftp.md`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/docs/03-uboot-tftp.md)

---

## Part 5 — The no-network fallback: YMODEM

No Ethernet? You can push firmware straight down the U-Boot console. It's slow — roughly 10 seconds for 64 KB versus well under a second on TFTP — but it needs zero networking.

Launch picocom with the send command overridden:

```bash
picocom -b 115200 --send-cmd "sb -v" /dev/ttyUSB2
```

At the U-Boot prompt:

```
loady 0x48000000
```

Send the file with `Ctrl-A Ctrl-S`, then finish exactly as before:

```
cp.b 0x48000000 0x7e0000 ${filesize}
bootaux 0x7e0000
```

> **The gotcha:** picocom defaults its file-send to **ZMODEM**, but U-Boot's `loady` only speaks **YMODEM**. Without `--send-cmd "sb -v"` the transfer just sits there failing at you. You'll also see it NAK a few times mid-flight and recover — that's normal for YMODEM over a console link, not a fault.

---

## Part 6 — The other way: loading from Linux with remoteproc

Path A is great when the M7 should own the hardware. But if you want the cores *talking* — RPMsg, shared buffers, the co-processor model — you want Linux doing the loading, via the kernel's `imx-rproc` driver.

First, a naming correction I had to make in my own head: **nothing here flashes anything.** Neither path writes to persistent storage. Both drop code into RAM and release a core from reset. remoteproc just moves the loading job from U-Boot to Linux.

![remoteproc load sequence: scp the ELF, stop, set firmware, start; imx-rproc checks ELF headers against DTB carveouts](https://raw.githubusercontent.com/mohittalwar23/imx8mp-m7-dev/main/docs/diagrams/08-remoteproc.png)

### Step 6.1 — Enabling remoteproc (you don't edit a devicetree)

I expected to write devicetree overlays. **You don't.** NXP already ships a second DTB on the FAT `/boot` partition, and the kernel already has the driver built in:

```
CONFIG_REMOTEPROC=y
CONFIG_IMX_REMOTEPROC=y
```

So "enabling remoteproc" just means *booting a different devicetree*. At U-Boot:

```
setenv fdt_file imx8mp-evk-rpmsg.dtb
saveenv
boot
```

Versus the stock `imx8mp-evk.dtb`, the rpmsg DTB does two things that matter:

- **Adds the `imx-rproc` node** — this is what makes `/sys/class/remoteproc/remoteproc0` appear, along with **reserved-memory carveouts** describing where M7 firmware is allowed to land.
- **Reassigns UART4 to the M7**, so the M7 owns its console instead of Linux claiming it.

That second point has a consequence: under this DTB, UART4 belongs to the M7. Don't expect Linux to enumerate it.

> **Gotcha — `saveenv` may not stick.** On this BSP the environment partition doesn't reliably persist. If `remoteproc0` is missing after a power cycle, this is almost always why: you booted the stock DTB again. I stopped trusting `saveenv` and just re-set `fdt_file` every boot.

### Step 6.2 — Verify before deploying

Log in as root on `ttyUSB2` and confirm the plumbing exists:

```bash
ls /sys/class/remoteproc/
# expect: remoteproc0

cat /sys/class/remoteproc/remoteproc0/state
# expect: offline
```

If `remoteproc0` isn't there, **stop** — you're on the wrong DTB and nothing downstream will work.

> **You can't tell which DTB you booted from the model string.** Both report the same thing:
> ```bash
> $ cat /sys/firmware/devicetree/base/model
> NXP i.MX8MPlus EVK board
> ```
> The presence of `remoteproc0` *is* the check. Or look for the rpmsg-specific reserved regions — `ls /proc/device-tree/reserved-memory/` should list `rpmsg@0x55800000` and `vdev0vring0@55000000`.

Two more `dmesg` lines you'll see at boot and can safely ignore:

```
imx-rproc imx8mp-cm7: failed to find syscon
imx-rproc imx8mp-cm7: mbox_request_channel_byname() could not locate channel named "txdb"
```

Neither stops the driver from coming up (`remoteproc0: imx-rproc is available` follows immediately). They cost you the doorbell mailbox, which the loading path doesn't use.

Restore the board's IP, which is RAM-only and dies on every reboot:

```bash
ip addr add 192.168.7.2/24 dev eth0
```

### Step 6.3 — Load firmware: ELF, not .bin

A difference that trips people coming from Path A: **U-Boot wants a raw `.bin`; remoteproc wants an `.elf`.** remoteproc parses program headers to decide where each segment goes, so a stripped binary is useless to it.

Firmware must live in `/lib/firmware/`:

**First, the SSH quirk.** The board's Yocto image runs an old Dropbear that only offers `ssh-rsa` and has no `sftp-server`. Modern OpenSSH refuses both, so plain `scp` fails with errors that look like auth problems. You need three flags — and `-O` to force the legacy protocol:

```bash
scp -O \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    build/m7_sync/zephyr/zephyr.elf root@192.168.7.2:/lib/firmware/m7-app.elf
```

Then on the board:

```bash
echo stop            > /sys/class/remoteproc/remoteproc0/state   # if already running
echo -n "m7-app.elf" > /sys/class/remoteproc/remoteproc0/firmware
echo start           > /sys/class/remoteproc/remoteproc0/state
cat /sys/class/remoteproc/remoteproc0/state
# running
```

> **Note the `-n`.** A trailing newline becomes part of the filename, and you get a confusing not-found for a file that's clearly sitting right there.

`dmesg` is where you find out whether it actually worked:

```
remoteproc remoteproc0: powering up imx-rproc
remoteproc remoteproc0: Booting fw image m7-app.elf, size 582644
remoteproc remoteproc0: no dtb rsrc-table
imx-rproc imx8mp-cm7: No resource table in elf
remoteproc remoteproc0: remote processor imx-rproc is now up
```

> **`No resource table in elf` is not an error.** A resource table is how firmware *declares* shared resources — vrings, trace buffers — to the host. The RPMsg examples have one. Plain Zephyr samples like `synchronization` don't, and don't need one. You'll see those two lines on every load and they're fine.

### Step 6.3a — if you already ran `bootaux`, remoteproc adopts the core

Worth knowing, because it confused me. If you loaded firmware via Path A and *then* booted Linux, remoteproc finds the M7 already running:

```
remoteproc remoteproc0: Synchronizing with preloaded co-processor
remoteproc remoteproc0: no dtb rsrc-table
remoteproc remoteproc0: remote processor imx-rproc is now up
```

The kernel **attaches to the running core instead of loading anything.** So you'll see:

```bash
$ cat /sys/class/remoteproc/remoteproc0/state
running
$ cat /sys/class/remoteproc/remoteproc0/firmware
(null)
```

`running` with a `(null)` firmware is the tell: that's a core Linux adopted, not one it started. You must `echo stop` before your own firmware will load — otherwise `start` has nothing to do. This is a nice property, not a bug: your Path A firmware survives a Linux boot untouched.

[`scripts/m7-remoteproc.sh`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/scripts/m7-remoteproc.sh) wraps all of it, including refusing to start over an already-running core:

```bash
scp scripts/m7-remoteproc.sh root@192.168.7.2:/usr/local/bin/

# board
m7-remoteproc.sh start m7-app.elf
m7-remoteproc.sh status
m7-remoteproc.sh stop
```

> **Tip:** open `picocom -b 115200 /dev/ttyUSB3` *before* starting the M7. The boot banner scrolls past in milliseconds and there's no way to ask for it again.

### Step 6.4 — Why this becomes the nicer loop

**remoteproc has no reboot in the cycle.** Stop, copy, start — Linux stays up the whole time. I timed the full loop (scp a fresh ELF, stop, start):

```
$ time ( scp -O ... zephyr.elf root@192.168.7.2:/lib/firmware/m7-app.elf
         ssh ... 'echo stop > .../state; echo start > .../state' )
running

real    0m0.574s
```

**Well under a second.** Compare that to Path A, where every iteration means a power cycle and catching a two-second autoboot window — call it 30 seconds of human attention, and you can't script it.

| | Path A — U-Boot TFTP | Path B — Linux remoteproc |
|---|---|---|
| Firmware format | raw `.bin` | `.elf` |
| Reload cycle | power cycle + catch autoboot | **~3 s, no reboot** |
| Linux running? | optional | required |
| M7 owns audio hardware | **yes** | shared/contended |
| Load address | you choose (`cp.b` → ITCM) | ELF headers + DTB carveouts |

Path A stays my daily driver for audio bring-up specifically because the M7 gets the SAI to itself. For everything else, Path B's edit-run loop is simply faster.

### Step 6.5 — The carveout trap

This is where "reserved-memory carveouts" stops being trivia. If your ELF asks to load somewhere the DTB hasn't reserved, remoteproc rejects it outright:

```
remoteproc remoteproc0: bad phdr da 0x80000000 mem 0xa80
```

That's not a corrupt binary — it's the driver refusing to write to an address it can't translate. The specific fix is in §7.4.

**Worth seeing what the DTB actually reserves**, since this is the constraint you're working against:

```bash
$ ls /proc/device-tree/reserved-memory/
audio@0x81000000    m4@0x80000000       rpmsg@0x55800000
dsp@92400000        ocram@900000        rsc-table
isp0@94400000       optee_core@0x56000000   vdev0vring0@55000000
linux,cma           optee_shm@0x57c00000    vdev0vring1@55008000
                                        vdevbuffer@55400000
```

Note `m4@0x80000000` **is** declared — so the tidy explanation "there's no carveout at that address" isn't quite right, and I'd repeated it before checking. The region is reserved; what fails is `imx-rproc`'s address translation for that particular program-header destination. I haven't root-caused it further than that, and I'd rather say so than hand you a confident wrong mechanism. The fix in §7.4 is verified regardless.

The general lesson stands: under remoteproc **your link map has to agree with what the devicetree and driver will accept** — a constraint Path A simply doesn't have, since `cp.b` puts bytes wherever you point it.

Full details: [`docs/04-remoteproc.md`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/docs/04-remoteproc.md)

---

## Part 7 — Working through the MCUXpresso examples

With loading solved both ways, the SDK examples are how you learn the board's audio path and multicore plumbing. Config overlays for all five are in [`mcuxsdk-projects/`](https://github.com/mohittalwar23/imx8mp-m7-dev/tree/main/mcuxsdk-projects).

### 7.1 `hello_world` — the sanity check
**SDK path:** `demo_apps/hello_world` · **Load via:** remoteproc

Prints `Hello World` once to `ttyUSB3`, then halts. Boring on purpose — it proves toolchain and loader before anything else is in play. (This is the one that's painful to catch if you're still hunting for the right console, which is why Part 4 used `synchronization` instead.)

### 7.2 SAI interrupt transfer — a 1 kHz tone
**SDK path:** `driver_examples/sai/interrupt_transfer` · **Load via:** TFTP (Linux must *not* be booted)

Plug headphones into **J6** and load `sai_tone.bin` with the Part 4 sequence. You get a 1 kHz sine out the jack, and this on `ttyUSB3`:

```
  MCUX SDK version: 2026.06.00-pvw2
SAI example started!

 SAI example finished!
```

**It plays once and stops** — note `finished`, not a loop. I'd assumed it was a continuous tone until I actually listened: you get a single beep, and then silence with the M7 still halted at the end of `main`. If you blink you'll miss it, and you'll conclude the example is broken when it isn't. Power-cycle and reload to hear it again.

First time the board made a sound I controlled — a good feeling, and a real milestone for audio work.

> That `-pvw2` suffix on the SDK version string means **preview**. Worth knowing when you're deciding whether an odd behaviour is your bug or the SDK's.

### 7.3 SAI record/playback — real-time mic loopback
**SDK path:** `driver_examples/sai/interrupt_record_playback` · **Load via:** TFTP
**Hardware:** 4-pole CTIA headset in **J6**

The one that mattered most. Speak into the mic, hear yourself live through the earphones.

This gives you a **known-good reference** for SAI + codec configuration and the DMA buffer flow on the 8MP. That reference is the actual point of this whole exercise: when my own Zephyr audio path is silent later, I can trust the hardware and go straight to debugging my code. A baseline you know works is worth more than any amount of documentation.

### 7.4 RPMsg string echo — the multicore channel
**SDK path:** `multicore_examples/rpmsg_lite_str_echo_rtos/remote` · **Load via:** remoteproc

Send strings from Linux, the M7 echoes them back. On the board:

```bash
modprobe imx_rpmsg_tty
cat /dev/ttyRPMSG30 &          # read echoes in background
echo "hello M7" > /dev/ttyRPMSG30
```

On `ttyUSB3`:

```
Get Message From Master Side : "hello M7" [len : 8]
```

This is the channel the eventual multicore audio work leans on, so it's worth proving early.

**The SDMA snag** — this is the `bad phdr` error from §6.5:

```
remoteproc remoteproc0: bad phdr da 0x80000000 mem 0xa80
```

The stock `prj.conf` enables the SDMA driver, which places a 2688-byte non-cacheable DMA buffer at `0x80000000` in the ELF, and remoteproc rejects the segment (see §6.5 — the reserved region exists, but the driver won't translate that destination). Drop the buffer and the problem goes away:

```
CONFIG_MCUX_COMPONENT_driver.sdma=n
```

**The subtle part is *where* that goes.** It must be in `evkmimx8mp/prj.conf`, **not** the root `prj.conf`, because the board-level file is merged last by Kconfig and therefore wins. Put it in the root and it silently does nothing — which is a genuinely confusing hour. The patch is committed in the repo.

### 7.5 SAI low power audio — the one that doesn't work
**Load via:** remoteproc · **Status:** broken, deliberately

An SRTM co-processor demo where Linux streams audio and the M7 drives the SAI. The M7 starts fine, but no sound card ever appears in `aplay -l`.

**You don't even need to run the demo to see this fail.** The rpmsg DTB declares a `sound-rpmsg` node, so the driver probes on every Linux boot and defers forever — the failure is sitting in `dmesg` within the first three seconds, regardless of what the M7 is doing:

```
[    2.300289] imx-audio-rpmsg sound-rpmsg: assigned reserved memory node audio@0x81000000
[    2.308329] imx-audio-rpmsg sound-rpmsg: ASoC: failed to init link rpmsg hifi: -517
[    2.315994] imx-audio-rpmsg sound-rpmsg: snd_soc_register_card failed (-517)
```

It retries and fails again at 3.3 s, 3.4 s, and onward. `-517` is `-EPROBE_DEFER` — the driver waiting for a resource that never arrives. **This is that six-year version gap from §0.3 finally biting:** SDK 26.06.00's SRTM protocol doesn't match kernel 5.4.70's `imx-audio-rpmsg` driver, so the A53 never receives the M7's audio service announcement in a form it understands. It defers forever.

The fix is rebuilding against an SDK from the kernel 5.4.x era (2.9.x / 2.10.x). Not worth the detour for me right now — so I'm leaving it broken **with the reason written down**, which is worth more than a silent gap in a repo. See [`docs/05-known-issues.md`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/docs/05-known-issues.md).

---

## Part 8 — Zephyr on the M7

The same TFTP flow loads any Zephyr `.bin`. Board target: `imx8mp_evk/mimx8ml8/m7`.

```bash
cd ~/zephyrproject
source .venv/bin/activate

# prints thread_a / thread_b forever - ideal for finding the M7 console
west build -b imx8mp_evk/mimx8ml8/m7 zephyr/samples/synchronization -d build/m7_sync

# interactive uart:~$ prompt over UART4
west build -b imx8mp_evk/mimx8ml8/m7 zephyr/samples/subsys/shell/shell_module -d build/m7_shell

cp build/m7_shell/zephyr/zephyr.bin ~/tftp/shell.bin
```

The shell sample is the more fun one — a real interactive prompt on `ttyUSB3`, with `[C-a] [C-h]` in picocom to list picocom's own commands.

Board variants, if you go looking:

| Target | Core |
|---|---|
| `imx8mp_evk/mimx8ml8/m7` | Cortex-M7, runs from ITCM |
| `imx8mp_evk/mimx8ml8/m7_ddr` | Cortex-M7, runs from DDR (bigger images) |
| `imx8mp_evk/mimx8ml8/a53` | Cortex-A53, single core |
| `imx8mp_evk/mimx8ml8/a53/smp` | Cortex-A53, SMP |
| `imx8mp_evk/mimx8ml8/adsp` | HiFi4 DSP |

### Blinky won't build — and that's correct

Worth calling out, because your instinct will be that the port is broken:

```
error: '__device_dts_ord_DT_N_ALIAS_led0_P_gpios_IDX_0_PH_ORD' undeclared here (not in a function)
error: 'DT_N_ALIAS_led0_P_gpios_IDX_0_VAL_pin' undeclared here (not in a function)
```

The EVK has only a power LED and a UART-activity LED, both hardware-wired to no GPIO. Check the board files and the M7 devicetree has **no `aliases` block at all** — only `imx8mp_evk_mimx8ml8_a53.dts` defines one. `blinky` is built around `DT_ALIAS(led0)`, so it cannot resolve, and the failure surfaces as an undefined symbol rather than anything readable.

Not a bug. Just the board. Use `synchronization` as your smoke test.

---

## Part 9 — Troubleshooting reference

| Symptom | Cause | Fix |
|---|---|---|
| No `/dev/ttyUSB*` | Cable, or you're not in `dialout` | `sudo usermod -aG dialout $USER`, re-login |
| Missed the U-Boot prompt | Autoboot window is only **2 seconds** | Focus the terminal, hold a key while powering on |
| `fail to probe panel device adv7535@3d` | U-Boot hunting for an HDMI bridge, no display attached | **Ignore** — unrelated to the M7 |
| ~40 s of dots, then `phy_startup() failed: -110` | Cable is in the jack that *isn't* U-Boot's `[PRIME]` device | `setenv ethact eth0`, or move the cable |
| `tftp` hangs on `T T T`, but the board pings fine | Laptop isn't actually on `.1` — an NM profile may pin a *different* address in the same `/24` | `nmcli -f ipv4.addresses connection show "Wired connection 1"`, then §3.1 |
| TFTP permission denied | dnsmasq dropped to `nobody`, can't traverse `$HOME` (mode 750) | `--user=<you>`, or TFTP root in `/srv/tftp` |
| U-Boot asks for `C0A80702.img` | Filename omitted; U-Boot derived it from the IP | Always pass address **and** name |
| `curl tftp://127.0.0.1/...` fails | Server-side problem — stop debugging the board | Fix on the laptop first |
| Laptop loses internet after board setup | Board link installed as default route | `ipv4.gateway ""` + `ipv4.never-default yes` |
| dnsmasq won't start | DNS half colliding with `systemd-resolved` | `--port=0` |
| YMODEM send does nothing | picocom defaults to ZMODEM | `picocom --send-cmd "sb -v"` |
| `remoteproc0` missing after reboot | `saveenv` didn't persist — you booted the stock DTB | Re-set `fdt_file imx8mp-evk-rpmsg.dtb` every boot |
| remoteproc won't load your firmware | Fed it a `.bin`; it needs program headers | Use the `.elf` |
| remoteproc "not found" but the file is there | Trailing newline captured in the filename | `echo -n` when writing `.../firmware` |
| `scp` to the board fails oddly | Old Dropbear: `ssh-rsa` only, no `sftp-server` | `scp -O -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa` |
| State `running`, firmware `(null)`, `start` does nothing | Linux adopted a core you already `bootaux`'d | `echo stop` first — see §6.3a |
| `No resource table in elf` | Plain Zephyr samples don't have one | Not an error — ignore |
| No M7 console under remoteproc | rpmsg DTB hands UART4 to the M7 | Expected — watch `ttyUSB3` |
| `bad phdr da 0x80000000` | SDMA buffer with no matching carveout | `driver.sdma=n` in **`evkmimx8mp/prj.conf`** |
| `snd_soc_register_card failed (-517)` | SDK 26.06 SRTM ≠ kernel 5.4.70 | Rebuild with SDK 2.9.x |
| blinky won't compile | No `led0` alias in the M7 devicetree | Expected — use `synchronization` |
| Debug attach unavailable | J15 is UART-only | External J-Link on J17 |

---

## Where this leaves you

If you've followed along, you now have:

- **a fast, repeatable way to load M7 firmware** that never touches the Yocto image on eMMC,
- **a YMODEM fallback** for when there's no cable,
- **a second workflow** via remoteproc with a ~3 second edit-run loop and a proven RPMsg channel,
- **a working hardware audio loopback** as a reference for SAI and codec configuration,
- and **a written record of the one example that doesn't work**, and why.

None of this is a deliverable in itself. It's the foundation everything else stands on. When I bring my own audio pipeline to this board and it doesn't make a sound — and it didn't, the first several times — I can be confident the silence is in my Zephyr drivers and not in the hardware path.

That confidence is worth most of the time this took.

**Next up:** porting the libMP audio sample onto the 8MP and debugging it block by block — the part where that bet gets tested.

---

## Reference

**Repo:** [mohittalwar23/imx8mp-m7-dev](https://github.com/mohittalwar23/imx8mp-m7-dev)

| Doc | Contents |
|---|---|
| [`docs/01-hardware.md`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/docs/01-hardware.md) | Connector map, memory addresses |
| [`docs/02-network-setup.md`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/docs/02-network-setup.md) | Point-to-point link, SSH/SCP flags |
| [`docs/03-uboot-tftp.md`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/docs/03-uboot-tftp.md) | Path A in full |
| [`docs/04-remoteproc.md`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/docs/04-remoteproc.md) | Path B in full |
| [`docs/05-known-issues.md`](https://github.com/mohittalwar23/imx8mp-m7-dev/blob/main/docs/05-known-issues.md) | Every failure above, with root causes |
| [`scripts/`](https://github.com/mohittalwar23/imx8mp-m7-dev/tree/main/scripts) | `start-tftp.sh`, `stop-tftp.sh`, `m7-remoteproc.sh` |
| [`mcuxsdk-projects/`](https://github.com/mohittalwar23/imx8mp-m7-dev/tree/main/mcuxsdk-projects) | `prj.conf` overlays + VS Code tasks per example |

**External:**
- [Zephyr — i.MX8M Plus EVK board docs](https://docs.zephyrproject.org/latest/boards/nxp/imx8mp_evk/doc/index.html)
- [NXP — i.MX 8M Plus EVK product page](https://www.nxp.com/design/design-center/development-boards-and-designs/8MPLUSLPD4-EVK)
- [Zephyr — getting started guide](https://docs.zephyrproject.org/latest/develop/getting_started/index.html)
- [Linux remoteproc framework docs](https://docs.kernel.org/staging/remoteproc.html)
