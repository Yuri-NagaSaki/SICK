# SICK - 服务器信息检测工具包

> **S**erver **I**nfo & **C**heck **K**it - 因为了解服务器的健康状况不应该让你感到头疼！😷➡️😎

**🌐 语言选择 / Language:** [English](README.md) | [中文文档](README_CN.md)

## 关于

SICK 是一个功能强大的 Linux 服务器硬件信息收集工具。项目名称来源于 **Server Info & Check Kit** 的首字母缩写，同时也巧妙地暗示着将"sick"（有问题的）服务器信息转变为"sick"（超棒的）！

### 🤔 为什么叫 SICK？

- **S**erver - 硬件服务器
- **I**nfo - 信息收集
- **C**heck - 健康检查
- **K**it - 完整工具包

但更重要的是，我们希望让"sick"（令人沮丧的）服务器硬件信息收集任务变得"sick"（超级酷）！

## 核心特性

### 多语言支持
- 🇺🇸 **English** - 完整的英文界面
- 🇨🇳 **中文** - 完整的中文界面

### 全面硬件检测
- **系统信息**: 主机名、操作系统、内核版本、运行时间
- **CPU 信息**: 型号、核心数、线程数、频率、缓存、使用率
- **内存信息**: 总容量、使用情况 + 详细内存条信息表格
- **磁盘信息**: 磁盘使用率 + SMART 健康状态 + 读写统计
- **网络信息**: 网络接口 + 型号检测 + 流量统计（仅物理网卡）
- **显卡信息**: NVIDIA/AMD/Intel GPU 检测
- **RAID 信息**: 软件/硬件 RAID 控制器
- **主板信息**: 厂商、型号、BIOS 信息

### 智能数据展示
- **彩色输出**: 美观的终端显示
- **表格格式**: 整齐的内存条信息表格
- **完美对齐**: 支持中英文混合显示对齐
- **JSON 输出**: `--json` 将机器可读数据输出到 stdout

### 🔧 高级功能
- **SMART 检测**: 硬盘健康状态、通电时间、读写统计
- **实时数据**: CPU 使用率、IO 统计、网络流量
- **自动安装**: 智能检测并安装所需依赖包
- **高兼容性**: 支持主流 Linux 发行版
- **虚拟接口过滤**: 只显示物理网卡（包括 InfiniBand）

## 支持的系统

| 发行版 | 包管理器 | 测试状态 |
|--------------|-----------------|-------------|
| **Debian/Ubuntu** | apt | ✅ 完全支持 |
| **CentOS/RHEL** | yum/dnf | ✅ 完全支持 |
| **AlmaLinux/Rocky** | dnf | ✅ 完全支持 |
| **Fedora** | dnf | ✅ 完全支持 |
| **Arch Linux** | pacman | ✅ 完全支持 |
| **openSUSE** | zypper | ✅ 完全支持 |
| **Alpine Linux** | apk | ✅ 完全支持 |

## 快速开始

### 一键执行

```
# 英文
curl -sL https://ba.sh/sick | bash

# 中文
curl -sL https://ba.sh/sick | bash -s -- -cn
```


### 示例输出

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


## 许可证

本项目基于 MIT 许可证发布 - 详情请查看 [LICENSE](LICENSE) 文件。

## 作者
博客 - [猫猫博客](https://catcat.blog)
Made with ❤️ by Yuri NagaSaki

---

**让服务器检查不再 sick（令人沮丧），而是变得 sick（超棒）！**

## 由 SharonNetworks 赞助

本项目的构建和发布环境由 SharonNetworks 提供支持 — 专注于亚太地区顶级优化回国线路，提供高带宽、低延迟的中国大陆直连，并内置强大的 DDoS 清洗功能。

SharonNetworks 确保您的业务平稳运行！

### 服务优势

* 亚太三网回程优化，直连中国大陆，实现超高速下载
* 超高带宽 + 防攻击清洗服务，确保业务安全稳定
* 多节点覆盖（香港、新加坡、日本、台湾、韩国）
* 高防御能力和高速网络；香港/日本/新加坡 CDN 即将推出

想要体验同样的部署环境？访问 Sharon 官方[网站](https://sharon.io)或加入 [Telegram 群组](https://t.me/SharonNetwork) 了解更多并申请赞助。
