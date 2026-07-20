#  SICK - Server Info & Check Kit

> **S**erver **I**nfo & **C**heck **K**it - Because knowing your server's health shouldn't make you sick! 😷➡️😎

**🌐 Language / 语言:** [English](README.md) | [中文文档](README_CN.md)

##  About

SICK is a powerful Linux server hardware information collection tool. The project name comes from the acronym **Server Info & Check Kit**, and also cleverly implies turning "sick" (problematic) server information into something "sick" (awesome)!

### 🤔 Why Called SICK?

-  **S**erver - Hardware servers
- **I**nfo - Information collection  
- **C**heck - Health checking
- **K**it - Complete toolkit

But more importantly, we want to make the "sick" (frustrating) task of server hardware information collection become "sick" (super cool)!

##  Key Features

### Multilingual Support
- 🇺🇸 **English** - Complete English interface
- 🇨🇳 **Chinese** - Complete Chinese interface

### Comprehensive Hardware Detection
- **System Info**: Hostname, OS, kernel version, uptime
- **CPU Info**: Model, cores, threads, frequency, cache, usage
- **Memory Info**: Total capacity, usage + detailed memory module table
- **Disk Info**: Disk usage + SMART health status + read/write statistics
- **Network Info**: Network interfaces + model detection + traffic stats (physical only)
- **GPU Info**: NVIDIA/AMD/Intel GPU detection
- **RAID Info**: Software/hardware RAID controllers
- **Motherboard Info**: Vendor, model, BIOS information

###  Smart Data Presentation
- **Colorful Output**: Beautiful terminal display
- **Table Format**: Neat memory module information tables
- **Perfect Alignment**: Support for mixed Chinese/English display alignment
- **JSON Output**: `--json` prints machine-readable data to stdout

### 🔧 Advanced Features
- **SMART Detection**: Hard drive health, power-on hours, read/write stats, bad blocks and defect counters
- **Real-time Data**: CPU usage, IO statistics, network traffic
- **Auto Installation**: Smart detection and installation of required packages
- **High Compatibility**: Support for mainstream Linux distributions
- **Virtual Interface Filtering**: Only shows physical network cards (including InfiniBand)

## Supported Systems

| Distribution | Package Manager | Test Status |
|--------------|-----------------|-------------|
| **Debian/Ubuntu** | apt | ✅ Fully Supported |
| **CentOS/RHEL** | yum/dnf | ✅ Fully Supported |
| **AlmaLinux/Rocky** | dnf | ✅ Fully Supported |
| **Fedora** | dnf | ✅ Fully Supported |
| **Arch Linux** | pacman | ✅ Fully Supported |
| **openSUSE** | zypper | ✅ Fully Supported |

## Quick Start

### One-Click Execution

```
# English
curl -sL https://ba.sh/sick | bash

# Chinese
curl -sL https://ba.sh/sick | bash -s -- -cn

# JSON output
curl -sL https://ba.sh/sick | bash -s -- --json
```

When passing options through `curl | bash`, use `bash -s -- <options>`.


### 🧪 Beta (v3.0.0-beta.1)

A refactored beta (`hardware_info_beta.sh`) is available for testing. It renders
**GPU, RAID/HBA, Network and NVMe as aligned colorized tables** (like the memory/disk
tables), asks **Y/N before installing any dependency**, fixes CJK width/locale handling,
and drops the noisy PCIe / ECC / storage-stack / CPU-vulnerability sections to stay a
clean one-shot inventory.

```
# English
curl -sL https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/hardware_info_beta.sh | bash

# Chinese
curl -sL https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/hardware_info_beta.sh | bash -s -- -cn

# Auto-install missing tools (no prompt) — handy for curl | bash
curl -sL https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/hardware_info_beta.sh | bash -s -- -y

# JSON output
curl -sL https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/hardware_info_beta.sh | bash -s -- --json
```

Beta flags: `-y/--yes` (auto-install), `--no-install` (report with what's present, never install).


###  Sample Output

```shell
════════════════════════════════════════════════════════════════════════════════
                       System Hardware Information Report                       
════════════════════════════════════════════════════════════════════════════════

┌─ Report Overview ───────────────────────────────
├──────────────────────────────────────────────────
│ Version             : 2.9.0
│ Mode                : Text
│ Privacy             : IP/MAC masked
└──────────────────────────────────────────────────
┌─ System Information ────────────────────────────
├──────────────────────────────────────────────────
│ Hostname            : pve
│ Operating System    : Debian GNU/Linux 13 (trixie)
│ Kernel Version      : 7.0.2-6-pve
│ System Uptime       : up 1 week, 1 day, 16 hours, 26 minutes
└──────────────────────────────────────────────────
┌─ CPU Information ───────────────────────────────
├──────────────────────────────────────────────────
│ Model               : Intel(R) Xeon(R) Gold 6148 CPU @ 2.40GHz
│ Cores               : 40
│ Threads             : 80
│ Frequency           : 2600.037 MHz
│ Cache               : 28160 KB
│ Usage               : 34.7%
│ CPU Temperature     : +83.0°C ⚠
└──────────────────────────────────────────────────
┌─ CPU / Platform Status ─────────────────────────
├──────────────────────────────────────────────────
│ Platform            : 2 socket(s), 2 NUMA node(s)
│ Virtualization      : Yes
│ Microcode           : 0x2007006
│ CPU Vulnerability   : 1 vulnerable, 10 mitigated
│
│ Vulnerable CPU Items:
│   gather_data_sampling: Vulnerable
└──────────────────────────────────────────────────
┌─ Memory (RAM) Information ──────────────────────
├──────────────────────────────────────────────────
│ Total               : 188.43 GB
│ Used                : 168Gi
│ Available           : 20.09 GB
│
│ Memory Modules:
├────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Size     │ Type   │ Frequency    │ Manufacturer │ Serial Number   │ Model                │
├────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 32 GB    │ DDR4   │ 2666 MT/s    │ 00CE063200CE │ 402C51CC        │ M393A4K40CB2-CTD     │
│ 32 GB    │ DDR4   │ 2666 MT/s    │ 00CE063200CE │ 402C5401        │ M393A4K40CB2-CTD     │
│ 32 GB    │ DDR4   │ 2666 MT/s    │ 00CE063200CE │ 402B9BB8        │ M393A4K40CB2-CTD     │
│ 32 GB    │ DDR4   │ 2666 MT/s    │ 00CE063200CE │ 402C52B3        │ M393A4K40CB2-CTD     │
│ 32 GB    │ DDR4   │ 2666 MT/s    │ 00CE063200CE │ 402C578C        │ M393A4K40CB2-CTD     │
│ 32 GB    │ DDR4   │ 2666 MT/s    │ 00CE063200CE │ 402C5641        │ M393A4K40CB2-CTD     │
└────────────────────────────────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────
┌─ ECC / Memory RAS Information ──────────────────
├──────────────────────────────────────────────────
│ ECC Type            : Multi-bit ECC
│ EDAC Available      : Yes
│ Corrected Errors    : 0
│ Uncorrected Errors  : 0
└──────────────────────────────────────────────────
┌─ Disk Drive Information ────────────────────────
├──────────────────────────────────────────────────
│ /dev/mapper/pve-root   94G   11G   79G  12% /
│ /dev/sda2            1022M  9.1M 1013M   1% /boot/efi
│ /dev/fuse             128M   24K  128M   1% /etc/pve
│
│ ═══════════════════════════════════════════════════
│ Other Disks (NVMe / SATA / SAS)
│ ═══════════════════════════════════════════════════
│ Disk Summary (defects=reallocated/pending/offline)
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Device       │ Basic Info                         │ SMART  │ Hours    │ Temp   │ I/O              │ Defects   │ Notes                │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ /dev/sda     │ 447.1G DELLBOSS VD        ATA      │ -      │ -        │ -      │ -                │ -         │ no SMART info        │
│ /dev/nvme0n1 │ 3.5T SAMSUNG MZWLJ3T8HBLS-00007    │ PASS   │ 31214h   │ 36°C   │ R3.74P W3.58P    │ -         │ used 7%, spare 100%  │
│ /dev/nvme1n1 │ 3.5T SAMSUNG MZWLJ3T8HBLS-00007    │ PASS   │ 25878h   │ 36°C   │ R3.04P W2.97P    │ -         │ used 5%, spare 100%  │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────
┌─ NVMe Deep Health ──────────────────────────────
├──────────────────────────────────────────────────
│ Devices Checked     : 2
│ Status              : No critical/media/error-log issues
│   Unsafe Shutdowns: nvme0n1=144 nvme1n1=138 (history)
└──────────────────────────────────────────────────
┌─ PCIe Link Status ──────────────────────────────
├──────────────────────────────────────────────────
│ Summary             : 3 degraded active PCIe link(s); verify slot wiring,
│                       card generation, riser/backplane, or BIOS lane
│                       settings
│ Attention:
│   WARN 0000:3a:00.0  current 5.0 GT/s PCIe/x2  cap 8.0 GT/s PCIe/x16
│        Intel Sky Lake-E PCIe Root Port A (rev 04)
│   WARN 0000:b1:00.0  current 8.0 GT/s PCIe/x4  cap 16.0 GT/s PCIe/x4
│        Samsung NVMe SSD Controller PM173X
│   WARN 0000:b3:00.0  current 8.0 GT/s PCIe/x4  cap 16.0 GT/s PCIe/x4
│        Samsung NVMe SSD Controller PM173X
│ PCIe Links          : 122
│ Degraded Links      : 3
│ Inactive Links      : 109
└──────────────────────────────────────────────────
┌─ Filesystem / Storage Stack ────────────────────
├──────────────────────────────────────────────────
│ Summary             : 3 disk(s), 1 RAID device(s), 21 LVM volume(s)
│ Warning             : 1 RAID0 device(s) detected; RAID0 has no redundancy
│                       and any member failure can break the array
│ Physical Disks      : sda 447.1G nvme0n1 3.5T linux_raid_member nvme1n1
│                       3.5T linux_raid_member
│ RAID Devices:
│   WARN md0  raid0  7T  fs=LVM2_member
│ Key Mounts:
│   / <- /dev/mapper/pve-root (ext4)
│   /boot/efi <- /dev/sda2 (vfat)
│   /etc/pve <- /dev/fuse (fuse)
│ LVM:
│   PV /dev/md0   nvme-vg   <6.99t <71.54g
│   PV /dev/sda3  pve     <446.07g  16.00g
│   VG nvme-vg   <6.99t <71.54g  13
│   VG pve     <446.07g  16.00g   3
│   LV count: 16
└──────────────────────────────────────────────────
┌─ RAID Controller Information ───────────────────
├──────────────────────────────────────────────────
│ Software RAID:
│   WARN md0  raid0  active  members=2
│        no redundancy; any member failure can break this array
│ Array IDs           : 1 stored in JSON
│ Controllers         : 6 total, 2 RAID/HBA/SAS
│ RAID/HBA Controllers:
│   HBA 18:00.0  Broadcom / LSI SAS3008 PCIe Fusion-MPT SAS-3 (rev 02)
│   HBA 3b:00.0  Marvell 88SE9230 PCIe 2.0 x2 4-port SATA 6 Gb/s RAID
│     Controller (rev 11)
└──────────────────────────────────────────────────
┌─ Network Interface Information ─────────────────
├──────────────────────────────────────────────────
│ Interface: nic0
│   Link        : UP 25000Mbps full link=Yes master=vmbr0
│   Driver      : bnxt_en fw=237.1.141.0/pkg 37.11.48.00
│   Model       : Broadcom Inc. and subsidiaries BCM57414 NetXtreme-E
│                 10Gb/25Gb RDMA Ethernet Controller (rev 01)
│   Traffic     : RX=281.20 TB TX=280.43 TB
│   NIC Counters: rx_total_l4_csum_errors=167951 rx_total_buf_errors=2929080
│ Interface: nic1
│   Link        : DOWN link=No
│   Driver      : bnxt_en fw=237.1.141.0/pkg 37.11.48.00
│   Model       : Broadcom Inc. and subsidiaries BCM57414 NetXtreme-E
│                 10Gb/25Gb RDMA Ethernet Controller (rev 01)
│   Traffic     : RX=0.00 GB TX=0.00 GB
└──────────────────────────────────────────────────
┌─ Graphics Card Information ─────────────────────
├──────────────────────────────────────────────────
│ Graphics Cards (PCI):
│   03:00.0 VGA compatible controller: Matrox Electronics Systems Ltd.
│     Integrated Matrox G200eW3 Graphics Controller (rev 04)
│ Display Hardware Summary:
│   /0/100/1c.4/0/0  /dev/fb0    display        Integrated Matrox G200eW3
│     Graphics Controller
└──────────────────────────────────────────────────
┌─ Motherboard Information ───────────────────────
├──────────────────────────────────────────────────
│ Vendor              : Dell Inc.
│ Model               : 06DKY5
│ Version             : A02
│ BIOS Vendor         : Dell Inc.
│ BIOS Version        : 2.27.0
└──────────────────────────────────────────────────

Report generation completed!
Generated on: Wed Jun  3 09:25:20 AM CET 2026
```


##  License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

##  Author
Blog - [猫猫博客](https://catcat.blog)
Made with ❤️ by Yuri NagaSaki

---

**Make server checking no longer sick (frustrating), but sick (awesome)!** 
