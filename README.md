# 🏥 SICK - Server Info & Check Kit

> **S**erver **I**nfo & **C**heck **K**it - Because knowing your server's health shouldn't make you sick! 😷➡️😎

**🌐 Language / 语言:** [English](README.md) | [中文文档](README_CN.md)

## 🎯 About

SICK is a powerful Linux server hardware information collection tool. The project name comes from the acronym **Server Info & Check Kit**, and also cleverly implies turning "sick" (problematic) server information into something "sick" (awesome)!

### 🤔 Why Called SICK?

- 📊 **S**erver - Hardware servers
- ℹ️ **I**nfo - Information collection  
- ✅ **C**heck - Health checking
- 🛠️ **K**it - Complete toolkit

But more importantly, we want to make the "sick" (frustrating) task of server hardware information collection become "sick" (super cool)!

## ✨ Key Features

### 🌐 Multilingual Support
- 🇺🇸 **English** - Complete English interface
- 🇨🇳 **Chinese** - Complete Chinese interface

### 🖥️ Comprehensive Hardware Detection
- **💻 System Info**: Hostname, OS, kernel version, uptime
- **🧠 CPU Info**: Model, cores, threads, frequency, cache, usage
- **🎯 Memory Info**: Total capacity, usage + detailed memory module table
- **💾 Disk Info**: Disk usage + SMART health status + read/write statistics
- **🌐 Network Info**: Network interfaces + model detection + traffic stats (physical only)
- **🎮 GPU Info**: NVIDIA/AMD/Intel GPU detection
- **🔧 RAID Info**: Software/hardware RAID controllers
- **📋 Motherboard Info**: Vendor, model, BIOS information

### 📊 Smart Data Presentation
- **🎨 Colorful Output**: Beautiful terminal display
- **📋 Table Format**: Neat memory module information tables
- **📏 Perfect Alignment**: Support for mixed Chinese/English display alignment
- **💾 Auto Save**: Simultaneously save as plain text report files

### 🔧 Advanced Features
- **🔍 SMART Detection**: Hard drive health, power-on hours, read/write stats
- **📈 Real-time Data**: CPU usage, IO statistics, network traffic
- **🔌 Auto Installation**: Smart detection and installation of required packages
- **📱 High Compatibility**: Support for mainstream Linux distributions
- **🚫 Virtual Interface Filtering**: Only shows physical network cards (including InfiniBand)

## 🐧 Supported Systems

| Distribution | Package Manager | Test Status |
|--------------|-----------------|-------------|
| **Debian/Ubuntu** | apt | ✅ Fully Supported |
| **CentOS/RHEL** | yum/dnf | ✅ Fully Supported |
| **AlmaLinux/Rocky** | dnf | ✅ Fully Supported |
| **Fedora** | dnf | ✅ Fully Supported |
| **Arch Linux** | pacman | ✅ Fully Supported |
| **openSUSE** | zypper | ✅ Fully Supported |
| **Alpine Linux** | apk | ✅ Fully Supported |

## 🚀 Quick Start

### ⚡ One-Click Execution

```
# English
curl -sL https://sick.onl | bash

# Chinese
curl -sL https://sick.onl | bash -s -- -cn
```


### 📋 Sample Output

```

════════════════════════════════════════════════════════════════════════════════
                       System Hardware Information Report                       
════════════════════════════════════════════════════════════════════════════════

┌─ System Information
├────────────────────
│ Hostname            : catcat
│ Operating System    : Debian GNU/Linux 12 (bookworm)
│ Kernel Version      : 6.1.0-37-amd64
│ System Uptime       : up 3 days, 10 hours, 58 minutes
└──────────────────────────────────────────────────
┌─ CPU Information
├─────────────────
│ Model               : AMD EPYC 4244P 6-Core Processor
│ Cores               : 6
│ Threads             : 12
│ Frequency           : 3706.683 MHz
│ Cache               : 1024 KB
│ Usage               : 0.0%
└──────────────────────────────────────────────────
┌─ Memory (RAM) Information
├──────────────────────────
│ Total               : 30.96 GB
│ Used                : 1.1Gi
│ Available           : 29.87 GB
│
│ Memory Modules:
├────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Size     │ Type   │ Frequency    │ Manufacturer │ Serial Number   │ Model                │
├────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 16 GB    │ DDR5   │ 5600 MT/s    │ Samsung      │ 4077E4A3        │ M323R2GA3PB0-CWMOD   │
│ 16 GB    │ DDR5   │ 5600 MT/s    │ Samsung      │ 4077E5FC        │ M323R2GA3PB0-CWMOD   │
└────────────────────────────────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────
┌─ Disk Drive Information
├────────────────────────
│ /dev/md3        878G  2.3G  831G   1% /
│ /dev/md2        988M   71M  851M   8% /boot
│ /dev/nvme1n1p1  511M  5.9M  505M   2% /boot/efi
│
│ Physical Disks Details:
│
│ ═══ /dev/nvme1n1 ═══
│   Basic Info: 894.3G SAMSUNG MZQL2960HCJR-00A07 
│   SMART Status: PASSED
│   Power On Hours: 88 hours
│   Data Transfer Statistics:
│     Total Reads: 1.92 GB
│     Total Writes: 1.89 GB
│   Temperature: 39°C
│   Health Status: 100%
│
│ ═══ /dev/nvme0n1 ═══
│   Basic Info: 894.3G SAMSUNG MZQL2960HCJR-00A07 
│   SMART Status: PASSED
│   Power On Hours: 88 hours
│   Data Transfer Statistics:
│     Total Reads: 1.90 GB
│     Total Writes: 1.87 GB
│   Temperature: 38°C
│   Health Status: 100%
└──────────────────────────────────────────────────
┌─ RAID Controller Information
├─────────────────────────────
│ Software RAID:
│   md2 : active raid1 nvme1n1p2[1] nvme0n1p2[0]
│   md3 : active raid0 nvme1n1p3[1] nvme0n1p3[0]
└──────────────────────────────────────────────────
┌─ Network Interface Information
├───────────────────────────────
│
│ ═══ enp1s0f0np0 ═══
│   Model: Broadcom Inc. and subsidiaries BCM57502 NetXtreme-E 10Gb/25Gb/40Gb/50Gb Ethernet (rev 12)
│   Status: UP
│   IPv4: ipc
│   IPv6: ip
│   MAC: 9c:6b:00:96:f3:9d
│   Speed: 25000 Mbps
│   Duplex: full
│   Link Detected: Yes
│   RX: 77.96 GB
│   TX: 33.76 GB
│
│ ═══ enp1s0f1np1 ═══
│   Model: Broadcom Inc. and subsidiaries BCM57502 NetXtreme-E 10Gb/25Gb/40Gb/50Gb Ethernet (rev 12)
│   Status: UP
│   IPv4: 192.168.1.100/16
│   IPv6: fe80::9e6b:ff:fe96:fcc0/64
│   MAC: 9c:6b:00:96:fc:c0
│   Speed: 25000 Mbps
│   Duplex: full
│   Link Detected: Yes
│   RX: 0 GB
│   TX: 0 GB
└──────────────────────────────────────────────────
┌─ Graphics Card Information
├───────────────────────────
│
│ Graphics Cards (PCI):
│   08:00.0 VGA compatible controller: ASPEED Technology, Inc. ASPEED Graphics Family (rev 52)
│
│ Display Hardware Summary:
│   ==============================================================
│   /0/100/2.1/0/3/0/0                  display        ASPEED Graphics Family
│   /1                  /dev/fb0        display        EFI VGA
└──────────────────────────────────────────────────
┌─ Motherboard Information
├─────────────────────────
│ Vendor              : ASRockRack
│ Model               : B650D4U3-2Q/BCM
│ Version             : 3.01A
│ BIOS Vendor         : American Megatrends International, LLC.
│ BIOS Version        : 20.01.OV04
└──────────────────────────────────────────────────

Report generation completed!
Generated on: Tue Jul  1 04:15:37 UTC 2025
```

## 📊 Output Features

### 🎨 Dual Output
- **🖥️ Screen Display**: Colorful, beautiful real-time display
- **📄 File Save**: Plain text format for easy sharing and archiving

### 📁 File Naming Convention
```
hardware_report_[hostname]_[timestamp].txt
Example: hardware_report_web-server01_20250701_143022.txt
```

## 🔧 Command Options

| Option | Description |
|--------|-------------|
| `-cn, --chinese` | Display in Chinese |
| `-us, --english` | Display in English (default) |
| `-h, --help` | Show help information |
| `-v, --version` | Show version information |

## 🛠️ Dependencies

The script will automatically detect and install the following tools:

| Tool | Purpose | Auto Install |
|------|---------|--------------|
| `dmidecode` | Read hardware information | ✅ |
| `lshw` | Hardware listing tool | ✅ |
| `smartctl` | Disk SMART information | ✅ |
| `iostat` | IO statistics | ✅ |
| `bc` | Mathematical calculations | ✅ |
| `ethtool` | Network card information | ✅ |

## 💡 Usage Tips

### 🔐 Permission Requirements
```bash
# Recommended to run with sudo for complete information
sudo ./hardware_info.sh -cn
```

### 🔧 Troubleshooting
If you encounter issues, please check:
1. Whether you have sudo privileges
2. Whether the system supports required hardware detection commands
3. Whether the network is working (for dependency package installation)


## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author
Blog - [猫猫博客](https://catcat.blog)
Made with ❤️ by Yuri NagaSaki

---

**Make server checking no longer sick (frustrating), but sick (awesome)!** 🚀 
