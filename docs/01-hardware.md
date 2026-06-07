# Hardware Reference — i.MX8MP EVK Plus DDR4

## Board Identity

| Item | Value |
|---|---|
| Board | i.MX8MP EVK Plus DDR4 (`IMX8MPLUSEVK`) |
| SoC | i.MX 8M Plus — quad Cortex-A53 + single Cortex-M7 |
| RAM | DDR4 |
| Storage | eMMC (no SD card in this setup) |
| BSP on eMMC | NXP L5.4.70_2.3.2 (kernel `5.4.70-2.3.2`) |

## DIP Switches (SW4)

Located near the USB OTG port.

| Mode | SW4[1] | SW4[2] | SW4[3] | SW4[4] |
|---|---|---|---|---|
| **eMMC boot (normal)** | ON | OFF | OFF | OFF |
| **USB Serial Download (UUU)** | OFF | OFF | OFF | OFF |

## USB Debug Port (J15, micro-B)

The on-board FT4232H provides **4 UARTs only** — no JTAG.

| Port | Role | Baud |
|---|---|---|
| `/dev/ttyUSB0` | Unused / JTAG stub | — |
| `/dev/ttyUSB1` | Unused / JTAG stub | — |
| `/dev/ttyUSB2` | **A53 console** — U-Boot + Linux | 115200 |
| `/dev/ttyUSB3` | **M7 console** — firmware UART output | 115200 |

Open both at once:
```bash
picocom -b 115200 /dev/ttyUSB2   # A53
picocom -b 115200 /dev/ttyUSB3   # M7
```
Exit picocom: `Ctrl-A Ctrl-X`

## JTAG Debug (J17, 20-pin)

M7 hardware debug requires an external J-Link connected to **J17**. The on-board
FT4232H does NOT provide JTAG. A J-Link EDU Mini (~$20) is needed for
MCUXpresso debug-attach to the running M7 core.

## M7 Memory Map

| Region | A53 address | M7 address | Size | Notes |
|---|---|---|---|---|
| **ITCM** | `0x007E0000` | `0x00000000` | 128 KB | M7 code execution; `bootaux 0x7e0000` |
| **DTCM** | `0x00800000` | (M7 data bus) | 128 KB | M7 data/stack |
| **DDR scratch** | `0x48000000` | — | — | TFTP landing pad (not executed here) |
| **DDR M7** | `0x80000000` | `0x80000000` | up to 16 MB | Used by `m7/ddr` board variant |

## Connectors Used

| Connector | Purpose |
|---|---|
| J6 | 3.5mm HP jack — headphone output + headset mic input |
| J13 | USB-C OTG — used for UUU flashing |
| J15 | Micro-B debug — FT4232H serial ports |
| J17 | 20-pin JTAG — external J-Link debug (not populated) |
| RJ45 (either) | Ethernet — point-to-point link to laptop |
