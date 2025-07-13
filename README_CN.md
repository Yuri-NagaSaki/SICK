# 🏥 SICK - 服务器信息检测工具包

> **S**erver **I**nfo & **C**heck **K**it - 让服务器健康检查不再令人头疼！😷➡️😎

**🌐 语言选择 / Language:** [English](README.md) | [中文文档](README_CN.md)

## 🎯 项目介绍

SICK 是一个功能强大的 Linux 服务器硬件信息收集工具。项目名称来源于 **Server Info & Check Kit** 的首字母缩写，同时也暗示着让服务器"病态"的信息变得"酷炫"（sick 在俚语中也有"很棒"的意思）！

### 🤔 为什么叫 SICK？

- 📊 **S**erver - 服务器
- ℹ️ **I**nfo - 信息
- ✅ **C**heck - 检查  
- 🛠️ **K**it - 工具包

但更重要的是，我们希望让那些"令人头疼"（sick）的服务器硬件信息收集工作变得"超级酷"（sick）！

## ✨ 核心特性

### 🌐 多语言支持
- 🇺🇸 **English** - 完整的英文界面
- 🇨🇳 **中文** - 完整的中文界面

### 🖥️ 全面硬件检测
- **💻 系统信息**: 主机名、操作系统、内核版本、运行时间
- **🧠 CPU 信息**: 型号、核心数、线程数、频率、缓存、使用率
- **🎯 内存信息**: 总容量、使用情况 + 详细内存条信息表格
- **💾 硬盘信息**: 磁盘使用率 + SMART 健康状态 + 读写统计
- **🌐 网卡信息**: 网络接口 + 型号检测 + 流量统计（仅物理网卡）
- **🎮 显卡信息**: NVIDIA/AMD/Intel GPU 检测
- **🔧 RAID 信息**: 软件/硬件 RAID 控制器
- **📋 主板信息**: 厂商、型号、BIOS 信息

### 📊 智能数据展示
- **🎨 彩色输出**: 美观的终端显示效果
- **📋 表格格式**: 整齐的内存模块信息表格
- **📏 精确对齐**: 支持中英文混合显示的完美对齐
- **💾 自动保存**: 同时保存为纯文本报告文件

### 🔧 高级功能
- **🔍 SMART 检测**: 硬盘健康状态、通电时间、读写统计
- **📈 实时数据**: CPU 使用率、IO 统计、网络流量
- **🔌 自动安装**: 智能检测并安装所需依赖包
- **📱 兼容性强**: 支持主流 Linux 发行版
- **🚫 虚拟网卡过滤**: 只显示物理网卡（包括 InfiniBand）

## 🐧 支持的系统

| 发行版 | 包管理器 | 测试状态 |
|--------|----------|----------|
| **Debian/Ubuntu** | apt | ✅ 完全支持 |
| **CentOS/RHEL** | yum/dnf | ✅ 完全支持 |
| **AlmaLinux/Rocky** | dnf | ✅ 完全支持 |
| **Fedora** | dnf | ✅ 完全支持 |
| **Arch Linux** | pacman | ✅ 完全支持 |
| **openSUSE** | zypper | ✅ 完全支持 |
| **Alpine Linux** | apk | ✅ 完全支持 |

## 🚀 快速开始

### ⚡ 一键执行

```
# 英文输出
curl -sL https://sick.onl | bash

# 中文输出
curl -sL https://sick.onl | bash -s -- -cn
```

### 📋 示例输出

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

✓ 报告已保存到文件: hardware_report_server01_20250701_123456.txt
```

## 📊 输出特性

### 🎨 双重输出
- **🖥️ 屏幕显示**: 彩色、美观的实时显示
- **📄 文件保存**: 纯文本格式，便于分享和存档

### 📁 文件命名规则
```
hardware_report_[主机名]_[时间戳].txt
例如: hardware_report_web-server01_20250701_143022.txt
```

## 🔧 命令选项

| 选项 | 说明 |
|------|------|
| `-cn, --chinese` | 中文界面显示 |
| `-us, --english` | 英文界面显示（默认） |
| `-h, --help` | 显示帮助信息 |
| `-v, --version` | 显示版本信息 |

## 🛠️ 依赖工具

脚本会自动检测并安装以下工具：

| 工具 | 用途 | 自动安装 |
|------|------|----------|
| `dmidecode` | 读取硬件信息 | ✅ |
| `lshw` | 硬件列表工具 | ✅ |
| `smartctl` | 磁盘SMART信息 | ✅ |
| `iostat` | IO统计信息 | ✅ |
| `bc` | 数学计算 | ✅ |
| `ethtool` | 网卡信息 | ✅ |

## 💡 使用建议

### 🔐 权限要求
```bash
# 推荐使用 sudo 运行以获取完整信息
sudo ./hardware_info.sh -cn
```


### 🔧 故障排查
如果遇到问题，请检查：
1. 是否有 sudo 权限
2. 系统是否支持所需的硬件检测命令
3. 网络是否正常（用于安装依赖包）


## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 👨‍💻 作者

Made with ❤️ by Yuri NagaSaki

---

**让服务器检查不再令人 sick，而是变得 sick（超酷）！** 🚀 
