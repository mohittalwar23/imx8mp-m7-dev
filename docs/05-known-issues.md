# Known Issues and Limitations

## SAI Low Power Audio — No Sound (SRTM Protocol Mismatch)

**Symptom:** M7 starts (`M7 state: running`) but no audio card appears in `aplay -l`.
Kernel log shows:
```
imx-audio-rpmsg sound-rpmsg: snd_soc_register_card failed (-517)
```

**Root cause:** The MCUXpresso SDK 26.06.00 uses a newer SRTM protocol version than
the 5.4.70 kernel's `imx-audio-rpmsg` driver. The A53 driver never receives the
M7's audio service announcement in a format it understands.

**Fix:** Rebuild `sai_low_power_audio` using MCUXpresso SDK 2.9.x/2.10.x
(the release matching kernel 5.4.x). Download from mcuxpresso.nxp.com — select
imx8mpevk, pick a 2020-era SDK version.

---

## `saveenv` Does Not Always Persist

**Symptom:** After a power cycle, U-Boot still uses the default `fdt_file`
(`imx8mp-evk.dtb`) instead of `imx8mp-evk-rpmsg.dtb`. The `remoteproc0` node
is absent when Linux boots.

**Root cause:** The env partition on the eMMC may be read-only or the env storage
area is not properly configured in this BSP build.

**Workaround:** Always catch U-Boot autoboot after power cycle and re-run:
```
setenv fdt_file imx8mp-evk-rpmsg.dtb; saveenv; boot
```

---

## rpmsg_lite_str_echo_rtos — SDMA Causes remoteproc Boot Failure

**Symptom:** `remoteproc remoteproc0: bad phdr da 0x80000000 mem 0xa80`

**Root cause:** The default SDK `prj.conf` enables the SDMA driver
(`CONFIG_MCUX_COMPONENT_driver.sdma=y`), which places a 2688-byte non-cacheable
DMA buffer at `0x80000000` in the ELF. The 5.4.70 kernel's remoteproc driver has
no carveout registered at that address and rejects the firmware.

**Fix applied in this repo:** `mcuxsdk-projects/rpmsg_lite_str_echo_rtos/evkmimx8mp/prj.conf`
sets `CONFIG_MCUX_COMPONENT_driver.sdma=n`. This file is the last one merged by
the Kconfig system, so it wins over the SDK's default.

> The override must be in `evkmimx8mp/prj.conf` (not the root `prj.conf`) because
> the SDK's example-level `prj.conf` is merged after the root project `prj.conf`.

---

## No J-Link — Cannot Use MCUXpresso Debug Attach

**Symptom:** The "Debug" launch config in `.vscode/launch.json` requires a J-Link
connected to J17 (20-pin JTAG header). The on-board FT4232H (J15 micro-B) provides
UARTs only, not JTAG.

**Status:** J-Link hardware not yet available. The `launch.json` files are committed
as a ready-to-use template for when a J-Link EDU Mini (~$20) is connected.

---

## Network Resets on Power Cycle

Static IPs (`192.168.7.1` on laptop, `192.168.7.2` on board) are set in RAM only
and disappear after reboot.

**Workaround:** Re-run after every power cycle:
- Laptop: `sudo ip addr add 192.168.7.1/24 dev eno1`
- Board: `ip addr add 192.168.7.2/24 dev eth0`
