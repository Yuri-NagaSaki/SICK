# 猫脚本 · Catbash

一组用一条 `curl | bash` 就能跑的 **Linux 服务器脚本** —— 无需安装器、无守护进程、零残留。

**官网：** [https://catbash.net/](https://catbash.net/)  
**语言：** [中文](README_CN.md) · [English](README.md)

---

## 包含什么

| 工具 | 作用 | 一键运行 | 文档 |
|------|------|----------|------|
| **主菜单** | 交互选择 SICK / NETS / CPUX | `curl -sL https://ba.sh/menu \| bash` | [catbash.sh](catbash.sh) |
| **SICK** | 一次性硬件盘点 | `curl -sL https://ba.sh/sick \| bash` | [sick.html](https://catbash.net/sick.html) |
| **NETS** | 公网 iperf3 吞吐采样 | `curl -sL https://ba.sh/nets \| bash` | [nets.html](https://catbash.net/nets.html) |
| **CPUX** | Geekbench 5 / 6 / 7 CPU 跑分 | `curl -sL https://ba.sh/cpux \| bash` | [cpux.html](https://catbash.net/cpux.html) |

### 预览

| SICK | NETS | CPUX |
|:----:|:----:|:----:|
| ![SICK 预览](https://cdn.nodeimage.com/i/nBu2RRSLC5ebMCcWDzdPMUaYQq5wg8hA.webp) | ![NETS 预览](https://cdn.nodeimage.com/i/f5eoaoJfF5hAGGbCafRStVZQrFZeS3xD.webp) | ![CPUX 预览](https://cdn.nodeimage.com/i/cXXg1mmSfDkxBvseInICpQmrUy5w8M3I.webp) |

**catbash.net** 上的对应短链：

| 短链 | 指向 |
|------|------|
| https://ba.sh/menu · https://catbash.net/menu | [catbash.sh](catbash.sh) 主菜单 |
| https://ba.sh/sick · https://catbash.net/sick | [hardware_info.sh](hardware_info.sh) |
| https://ba.sh/nets · https://catbash.net/nets | [nets/nets.sh](nets/nets.sh) |
| https://ba.sh/cpux · https://catbash.net/cpux | [cpux.sh](cpux.sh) |

---

## 快速开始 — 主菜单

交互菜单（`1` = SICK，`2` = NETS，`3` = CPUX，`0` = 退出）：

```bash
curl -sL https://ba.sh/menu | bash
# curl -sL https://catbash.net/menu | bash
```

跳过菜单并传参：

```bash
curl -sL https://ba.sh/menu | bash -s -- sick -cn
curl -sL https://ba.sh/menu | bash -s -- nets -r -t 5
curl -sL https://ba.sh/menu | bash -s -- nets -y --region eu
curl -sL https://ba.sh/menu | bash -s -- cpux all
```

通过 `curl | bash` 传参时，请使用 `bash -s -- <参数>`。

---

## SICK — 服务器信息检查工具包

一条命令 → 完整硬件报告：CPU、内存（逐模组）、磁盘/SMART、NVMe、RAID、网卡、GPU、主板。彩色表格或 JSON。中英双语。

```bash
# 英文（默认）
curl -sL https://ba.sh/sick | bash

# 中文
curl -sL https://ba.sh/sick | bash -s -- -cn

# 自动安装缺失工具
curl -sL https://ba.sh/sick | bash -s -- -y

# 仅输出 JSON
curl -sL https://ba.sh/sick | bash -s -- --json
```

建议 `sudo` 运行以获取完整信息（dmidecode、SMART、部分传感器需要 root）。

### 参数

| 参数 | 说明 |
|------|------|
| `-cn` / `--chinese` | 中文输出 |
| `-us` / `--english` | 英文输出（默认） |
| `-j` / `--json` | 仅向 stdout 打印 JSON |
| `-y` / `--yes` | 不询问，直接安装缺失工具 |
| `--no-install` | 从不安装；只用现有工具 |
| `-h` / `-v` | 帮助 / 版本 |

### 报告覆盖

系统 · CPU / 平台 · 内存 · 磁盘 / SMART · NVMe · RAID · 网卡 · 显卡 · 主板

更多：[https://catbash.net/sick.html](https://catbash.net/sick.html)

---

## NETS — 公网节点吞吐采样

对精选公网节点跑 **iperf3** 上下行。支持 IPv4 与 IPv6。汇总含 **Mbps/Gbps** 与 **本轮流量**。

### 支持的地区

| 参数 | 地区 | 覆盖 |
|------|------|------|
| `--region na` | 北美 | 纽约、洛杉矶、堪萨斯城、蒙特利尔（5） |
| `--region eu` | 欧洲 | 英、荷、德、法、奥、瑞典、丹麦、挪威、卢森堡、乌克兰（13） |
| `--region apac` | 亚太 | 东京、新加坡、香港、悉尼、孟买、塔什干（6） |
| `global`（默认） | 全部 | 24 节点 · 北美 + 欧洲 + 亚太 |
| `-r` / `reduced` | 精简 | 跨三区共 8 节点 |

```bash
# 全量
curl -sL https://ba.sh/nets | bash

# 精简节点，每方向 5 秒
curl -sL https://ba.sh/nets | bash -s -- -r -t 5

# 缺依赖时自动安装 iperf3 + python3
curl -sL https://ba.sh/nets | bash -s -- -y -r

# 仅亚太 + IPv4
curl -sL https://ba.sh/nets | bash -s -- --region apac -4

# 只列节点
curl -sL https://ba.sh/nets | bash -s -- -l
```

**依赖：** `iperf3`、`python3`。缺失时会 **Y/N 询问安装**（也可用 `-y` / `--no-install`）。

### 参数

| 参数 | 说明 |
|------|------|
| `-r` / `--reduced` | 精简节点列表 |
| `--region na\|eu\|apac\|global\|reduced` | 按区域筛选 |
| `-4` / `-6` | 仅 IPv4 / 仅 IPv6 |
| `-t <秒>` | 每方向测试时长（默认 10） |
| `-P <n>` | 并行流数（默认 4） |
| `--send-only` / `--recv-only` | 只测上传 / 只测下载 |
| `-y` / `--yes` | 自动安装缺失依赖 |
| `--no-install` | 不安装；缺依赖则退出 |
| `-l` | 列出节点后退出 |

节点目录：[nets/endpoints.md](nets/endpoints.md) · [nets/endpoints.json](nets/endpoints.json)  
更多：[https://catbash.net/nets.html](https://catbash.net/nets.html)

> 公网共享节点常 busy，结果用于对比，不等于实验室带宽。建议先用 `-r` 或 `--region`——全量双栈流量很大。

---

## CPUX — CPU 跑分

串行 **Geekbench 5 / 6 / 7** CPU 测试。终端真实输出**单核**与**多核**分数（不会空白列）。测试中有进度指示。

```bash
# 交互（1=GB5，2=GB6，3=GB7，4=全部）
curl -sL https://ba.sh/cpux | bash

# 仅 Geekbench 6
curl -sL https://ba.sh/cpux | bash -s -- 6

# 三套依次跑
curl -sL https://ba.sh/cpux | bash -s -- all

# 中文界面
curl -sL https://ba.sh/cpux | bash -s -- all -cn
```

需要能访问 `cdn.geekbench.com` 与 `browser.geekbench.com` 的 IPv4 HTTPS。安装包较大，请在可承受满载的机器上测。

更多：[https://catbash.net/cpux.html](https://catbash.net/cpux.html)

---

## 仓库结构

```
.
├── catbash.sh           # 主菜单
├── hardware_info.sh     # SICK
├── cpux.sh              # CPUX（Geekbench 5/6/7）
├── index.html           # 官网首页
├── sick.html            # SICK 介绍
├── nets.html            # NETS 介绍
├── cpux.html            # CPUX 介绍
├── nets/
│   ├── nets.sh
│   ├── endpoints.json
│   └── endpoints.md
├── worker.js            # Cloudflare 短链
└── wrangler.jsonc
```

---

## 赞助

- **USDT (TRC20):** `TT6Ly1NpWSeYubufPVRUp4dz8SMUCZzcE5`
- **爱发电：** [afdian.com/a/ellye](https://afdian.com/a/ellye)
- **博客：** [catcat.blog](https://catcat.blog)

---

## 许可证

[MIT](LICENSE) · © Yuri NagaSaki
