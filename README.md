# 猫脚本 · Catbash

Open-source Linux server scripts on **[catbash.net](https://catbash.net/)**:

| Project | What it does | Run | Docs |
|---------|--------------|-----|------|
| **[SICK](https://catbash.net/sick.html)** | One-shot hardware inventory | `curl -sL https://catbash.net/sick \| bash` | [sick.html](https://catbash.net/sick.html) · this README |
| **[NETS](https://catbash.net/nets/)** | Public iperf3 throughput sampler | `curl -sL https://catbash.net/nets \| bash` | [nets/](https://catbash.net/nets/) · [nets/README.md](nets/README.md) |

Short links (also on ba.sh): `https://ba.sh/sick` · `https://ba.sh/nets`

---

# SICK — Server Info & Check Kit

> A one-shot Linux server hardware inventory tool. It collects everything about a box in a single run and prints a clean, colorized report (or JSON). It never installs a daemon, never persists data, and never runs as a monitor.

**Language / 语言:** [English](README.md) | [中文](README_CN.md)

**Website:** [https://catbash.net/](https://catbash.net/) · [SICK docs](https://catbash.net/sick.html)

## About

**SICK** (Server Info & Check Kit) answers one question fast: *what hardware is in this server and is it healthy right now?* Run it once, read the report, move on. Every section is rendered as an aligned, color-coded table so the output stays readable whether the machine has one disk or forty.

## Features

- **One-shot, no footprint** — pure collection and rendering; nothing is written to disk, no service is installed.
- **Aligned colorized tables** — memory modules, filesystems, disks/SMART, NVMe health, RAID arrays, network interfaces and GPUs all render as boxed tables with status colors, correct even with CJK text.
- **Bilingual** — full English and Chinese output (`-cn`).
- **JSON output** — `--json` emits a single machine-readable object to stdout.
- **Privacy-aware** — IPv4/IPv6 and MAC addresses are masked by default; serial numbers are shown in full.
- **Friendly dependencies** — missing tools are detected and listed; the script asks **Y/N before installing anything** (`-y` to auto-install, `--no-install` to just report with what's present).
- **Broad compatibility** — Debian/Ubuntu, RHEL/CentOS/Alma/Rocky/CloudLinux, Fedora, Arch/Manjaro, openSUSE/SLES.

## What it reports

| Section | Details |
|---------|---------|
| **System** | Hostname, OS, kernel, uptime |
| **CPU / Platform** | Model, cores/threads, frequency, cache, live usage, temperature, sockets/NUMA, virtualization, microcode |
| **Memory** | Total / used / available, plus a per-module table (size, type, speed, vendor, serial, part number) |
| **Disks** | Mounted-filesystem usage table + a SMART summary table (health, power-on hours, temperature, lifetime I/O, reallocated/pending/offline defects) |
| **NVMe deep health** | Per-drive temperature, endurance used, spare, and health status |
| **RAID** | Software RAID (mdraid) arrays, hardware RAID/HBA controllers, and detected vendor CLI tools — RAID member disks are folded into the disk table and de-duplicated by serial |
| **Network** | Physical interfaces only: link/speed/duplex, masked MAC & IPv4, NIC model, and cumulative error/drop counters |
| **GPU** | Vendor and class (Discrete / Integrated / BMC), model, and — for NVIDIA — memory, driver and temperature |
| **Motherboard** | Vendor, model, BIOS vendor/version |

## Quick Start

### One-line run

Short install URLs (same script):

- `https://ba.sh/sick`
- `https://catbash.net/sick`

```bash
# English (default)
curl -sL https://ba.sh/sick | bash
# curl -sL https://catbash.net/sick | bash

# Chinese
curl -sL https://ba.sh/sick | bash -s -- -cn
# curl -sL https://catbash.net/sick | bash -s -- -cn

# Auto-install any missing tools without prompting
curl -sL https://ba.sh/sick | bash -s -- -y

# JSON to stdout
curl -sL https://ba.sh/sick | bash -s -- --json
```

When passing options through `curl | bash`, use `bash -s -- <options>`.

Alternatively, download and run locally:

```bash
curl -sLO https://catbash.net/hardware_info.sh
# or: curl -sLO https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/hardware_info.sh
chmod +x hardware_info.sh
sudo ./hardware_info.sh
```

Run with `sudo` for complete data (dmidecode, SMART, and some sensors require root).

## Options

| Option | Description |
|--------|-------------|
| `-cn`, `--chinese` | Output in Chinese |
| `-us`, `--english` | Output in English (default) |
| `-j`, `--json` | Print a JSON object to stdout only |
| `-y`, `--yes` | Install missing tools without prompting |
| `--no-install` | Never install; report with whatever tools are present |
| `-h`, `--help` | Show help |
| `-v`, `--version` | Show version |

## Dependencies

SICK uses standard Linux tools and detects which are missing on startup:
`dmidecode`, `lshw`, `smartmontools` (smartctl), `ethtool`, `nvme-cli`, `jq`, `pciutils` (lspci), `lm-sensors`.
It maps them to the right package for your distribution and installs on confirmation. Anything still missing is simply skipped — the report continues with whatever data is available.

## Sample Output

```text
                       System Hardware Information Report
════════════════════════════════════════════════════════════════════════════════

┌─ Report Overview ───────────────────────────────
├──────────────────────────────────────────────────
│ Version             : 3.0.0
│ Mode                : Text
│ Privacy             : IP/MAC masked
│ Serials             : shown in full
└──────────────────────────────────────────────────
┌─ CPU Information ───────────────────────────────
├──────────────────────────────────────────────────
│ Model               : Intel(R) Xeon(R) W-1250 CPU @ 3.30GHz
│ Cores               : 6
│ Threads             : 12
│ Frequency           : 3606.867 MHz
│ Cache               : 12288 KB
│ Usage               : 14.1%
│ CPU Temperature     : +55.0°C
└──────────────────────────────────────────────────
┌─ Memory (RAM) Information ──────────────────────
├──────────────────────────────────────────────────
│ Total               : 62.67 GB
│ Used                : 29Gi
│ Available           : 33.54 GB
│
│ Memory Modules:
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│ Size     │ Type   │ Frequency    │ Manufacturer │ Serial           │ Model                  │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│ 32 GB    │ DDR4   │ 2667 MT/s    │ Samsung      │ 03ED821A         │ M391A4G43MB1-CTD       │
│ 32 GB    │ DDR4   │ 2667 MT/s    │ Samsung      │ 042F10F4         │ M391A4G43MB1-CTD       │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────
┌─ Disk Drive Information ────────────────────────
├──────────────────────────────────────────────────
│ Mounted Filesystems:
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Filesystem                         │ Size    │ Used    │ Avail   │ Use%   │ Mounted              │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│ /dev/mapper/example--vg-root       │ 878G    │ 422G    │ 412G    │ 51%    │ /                    │
│ /dev/md0                           │ 102T    │ 35T     │ 68T     │ 34%    │ /hdd                 │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
│
│ Disk Summary (defects=reallocated/pending/offline)
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Device       │ Basic Info                         │ SMART  │ Hours    │ Temp   │ I/O                  │ Defects   │ Notes                │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ /dev/sda     │ 25.5T ST28000NM000C-3WM103 ATA     │ PASS   │ 9225h    │ 38°C   │ R132.2T W8.99T       │ 0/0/0     │ -                    │
│ /dev/nvme0n1 │ 894.3G MZXLR960HBHQ-000H3          │ PASS   │ 20194h   │ 29°C   │ R717.4T W755.5T      │ -         │ used 8%, spare 100%  │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────
┌─ NVMe Deep Health ──────────────────────────────
├──────────────────────────────────────────────────
├─────────────────────────────────────────────────────────────────────────────────────┤
│ Device         │ Model                      │ Temp    │ Used    │ Spare   │ Status  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ /dev/nvme0n1   │ MZXLR960HBHQ-000H3         │ 29°C    │ 8%      │ 100%    │ OK      │
└─────────────────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────
┌─ RAID Controller Information ───────────────────
├──────────────────────────────────────────────────
│ Software RAID (mdraid):
├───────────────────────────────────────────────────────────┤
│ Array    │ Level      │ State        │ Members   │ Health │
├───────────────────────────────────────────────────────────┤
│ md0      │ raid0      │ active       │ 4         │ OK     │
└───────────────────────────────────────────────────────────┘
│   ⚠ md0             raid0 has no redundancy; any member failure breaks the array
│ RAID/HBA Controllers:
├───────────────────────────────────────────────────────────────────────────┤
│ Slot       │ Type      │ Controller                                       │
├───────────────────────────────────────────────────────────────────────────┤
│ 05:00.0    │ RAID      │ Broadcom / LSI MegaRAID SAS-3 3108 [Invader] (r~ │
└───────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────
┌─ Network Interface Information ─────────────────
├──────────────────────────────────────────────────
├───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Iface        │ Status   │ Link         │ MAC                │ IPv4                 │ Model                    │
├───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ enp8s0       │ UP       │ 1000M/full   │ d0:50:99:XX:XX:XX  │ 104.250.XX.XX/30     │ Intel Corporation I210 ~ │
│ enp9s0       │ DOWN     │ -            │ d0:50:99:XX:XX:XX  │ -                    │ Intel Corporation I210 ~ │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
│
│ RX/TX error & drop counters (cumulative):
│   ⚠ enp8s0          rx_errors=4
└──────────────────────────────────────────────────
┌─ Graphics Card Information ─────────────────────
├──────────────────────────────────────────────────
├────────────────────────────────────────────────────────────────────────────────┤
│ Vendor   │ Class      │ Model                                                  │
├────────────────────────────────────────────────────────────────────────────────┤
│ ASPEED   │ BMC        │ ASPEED Technology, Inc. ASPEED Graphics Family (rev 4~ │
└────────────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────
┌─ Motherboard Information ───────────────────────
├──────────────────────────────────────────────────
│ Vendor              : ASRockRack
│ Model               : W480D4U/JAX
│ BIOS Vendor         : American Megatrends Inc.
│ BIOS Version        : L0.04
└──────────────────────────────────────────────────
```

## Supported Systems

| Distribution | Package Manager | Status |
|--------------|-----------------|--------|
| Debian / Ubuntu / Mint | apt | Supported |
| RHEL / CentOS / AlmaLinux / Rocky / CloudLinux | yum / dnf | Supported |
| Fedora | dnf | Supported |
| Arch / Manjaro | pacman | Supported |
| openSUSE / SLES | zypper | Supported |

## Privacy

The report masks IPv4/IPv6 (keeps the network prefix, hides host bits) and MAC addresses (keeps the vendor OUI, hides the device portion). Serial numbers (disk, memory, motherboard) are shown in full so you can inventory hardware; keep that in mind before sharing a report publicly.

## License

MIT — see [LICENSE](LICENSE).

## Author

Made by Yuri NagaSaki — blog: [猫猫博客](https://catcat.blog)
