# Network Setup — Point-to-Point Ethernet

The board uses a **direct cable** between the laptop's wired NIC and one of the
board's RJ45 jacks. No router involved — WiFi internet is untouched.

## Addresses

| Side | Interface | IP |
|---|---|---|
| Laptop | `eno1` | `192.168.7.1/24` |
| Board | `eth0` | `192.168.7.2/24` |

## Per-Session Setup

Static IPs reset on power cycle. Re-run these each session.

**Laptop:**
```bash
sudo ip addr add 192.168.7.1/24 dev eno1
```

**Board** (via ttyUSB2 serial console after Linux boots):
```bash
ip addr add 192.168.7.2/24 dev eth0
```

Verify: `ping 192.168.7.2` from laptop.

> **Note:** The laptop NIC name may differ. Find yours with `ip link show`.
> This guide uses `eno1` (tested hardware). Adjust if needed.

## SSH / SCP Quirks (Old Dropbear)

The board's Yocto L5.4.70 runs Dropbear SSH which:
- Only offers `ssh-rsa` host key algorithm (modern OpenSSH rejects it by default)
- Has no `sftp-server` (modern `scp` defaults to SFTP and fails)

Always add these flags to every `ssh` and `scp` command:
```bash
# SCP — the -O flag forces legacy protocol (no sftp-server needed)
scp -O \
    -o StrictHostKeyChecking=no \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    <file> root@192.168.7.2:<path>

# SSH
ssh \
    -o StrictHostKeyChecking=no \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    root@192.168.7.2 '<command>'
```

All VS Code tasks in this repo already include these flags.
