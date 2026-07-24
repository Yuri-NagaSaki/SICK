# 猫脚本 · Catbash

Open-source **Linux server scripts** you run with one `curl | bash` — no installers, no daemons, zero leftover footprint.

**Website:** [https://catbash.net/](https://catbash.net/)  
**Language:** [English](README.md) · [中文](README_CN.md)

---

## What’s inside

| Tool | Role | One-liner | Docs |
|------|------|-----------|------|
| **Menu** | Pick SICK / NETS / CPUX interactively | `curl -sL https://ba.sh/menu \| bash` | [catbash.sh](catbash.sh) |
| **SICK** | One-shot hardware inventory | `curl -sL https://ba.sh/sick \| bash` | [sick.html](https://catbash.net/sick.html) |
| **NETS** | Public iperf3 throughput sampler | `curl -sL https://ba.sh/nets \| bash` | [nets.html](https://catbash.net/nets.html) |
| **CPUX** | Geekbench 5 / 6 / 7 CPU tests | `curl -sL https://ba.sh/cpux \| bash` | [cpux.html](https://catbash.net/cpux.html) |

### Previews

| SICK | NETS | CPUX |
|:----:|:----:|:----:|
| ![SICK preview](https://cdn.nodeimage.com/i/nBu2RRSLC5ebMCcWDzdPMUaYQq5wg8hA.webp) | ![NETS preview](https://cdn.nodeimage.com/i/f5eoaoJfF5hAGGbCafRStVZQrFZeS3xD.webp) | ![CPUX preview](https://cdn.nodeimage.com/i/cXXg1mmSfDkxBvseInICpQmrUy5w8M3I.webp) |

Same scripts on **catbash.net**:

| Short URL | Target |
|-----------|--------|
| https://ba.sh/menu · https://catbash.net/menu | [catbash.sh](catbash.sh) launcher |
| https://ba.sh/sick · https://catbash.net/sick | [hardware_info.sh](hardware_info.sh) |
| https://ba.sh/nets · https://catbash.net/nets | [nets/nets.sh](nets/nets.sh) |
| https://ba.sh/cpux · https://catbash.net/cpux | [cpux.sh](cpux.sh) |

---

## Quick start — launcher

Interactive menu (`1` = SICK, `2` = NETS, `3` = CPUX, `0` = exit):

```bash
curl -sL https://ba.sh/menu | bash
# curl -sL https://catbash.net/menu | bash
```

Skip the menu and pass options:

```bash
curl -sL https://ba.sh/menu | bash -s -- sick -cn
curl -sL https://ba.sh/menu | bash -s -- nets -r -t 5
curl -sL https://ba.sh/menu | bash -s -- nets -y --region eu
curl -sL https://ba.sh/menu | bash -s -- cpux all
```

Through `curl | bash`, always use `bash -s -- <args>`.

---

## SICK — Server Info & Check Kit

One command → full hardware report: CPU, RAM (per-DIMM), disks/SMART, NVMe, RAID, NICs, GPU, motherboard. Colorized tables or JSON. English / Chinese.

```bash
# English
curl -sL https://ba.sh/sick | bash

# Chinese
curl -sL https://ba.sh/sick | bash -s -- -cn

# Auto-install missing tools
curl -sL https://ba.sh/sick | bash -s -- -y

# JSON only
curl -sL https://ba.sh/sick | bash -s -- --json
```

Use `sudo` for complete data (dmidecode, SMART, some sensors need root).

### Options

| Flag | Description |
|------|-------------|
| `-cn` / `--chinese` | Chinese output |
| `-us` / `--english` | English output (default) |
| `-j` / `--json` | JSON to stdout only |
| `-y` / `--yes` | Install missing tools without prompting |
| `--no-install` | Never install; use tools already present |
| `-h` / `-v` | Help / version |

### Report coverage

System · CPU / platform · Memory · Disks / SMART · NVMe · RAID · Network · GPU · Motherboard

More: [https://catbash.net/sick.html](https://catbash.net/sick.html)

---

## NETS — Network Endpoint Throughput Sampler

Public **iperf3** send/recv against curated endpoints. IPv4 & IPv6. Summary includes **Mbps/Gbps** and **traffic used this run**.

### Supported regions

| Flag | Region | Coverage |
|------|--------|----------|
| `--region na` | North America | New York, Los Angeles, Kansas City, Montreal (5) |
| `--region eu` | Europe | UK, NL, DE, FR, AT, SE, DK, NO, LU, UA (13) |
| `--region apac` | Asia-Pacific | Tokyo, Singapore, Hong Kong, Sydney, Mumbai, Tashkent (6) |
| `global` (default) | All | 23 nodes · NA + EU + APAC |
| `-r` / `reduced` | Quick set | 8 nodes across the three regions |

```bash
# Full run
curl -sL https://ba.sh/nets | bash

# Reduced set, 5s per direction
curl -sL https://ba.sh/nets | bash -s -- -r -t 5

# Auto-install iperf3 + python3 if missing
curl -sL https://ba.sh/nets | bash -s -- -y -r

# Asia only, IPv4
curl -sL https://ba.sh/nets | bash -s -- --region apac -4

# List catalog
curl -sL https://ba.sh/nets | bash -s -- -l
```

**Deps:** `iperf3`, `python3`. Missing tools trigger a **Y/N install prompt** (or `-y` / `--no-install`).

### Options

| Flag | Description |
|------|-------------|
| `-r` / `--reduced` | Short endpoint list |
| `--region na\|eu\|apac\|global\|reduced` | Filter by region |
| `-4` / `-6` | IPv4 only / IPv6 only |
| `-t <sec>` | Duration per direction (default 10) |
| `-P <n>` | Parallel streams (default 4) |
| `--send-only` / `--recv-only` | One direction |
| `-y` / `--yes` | Auto-install missing deps |
| `--no-install` | Never install; exit if deps missing |
| `-l` | List endpoints and exit |

Endpoint catalog: [nets/endpoints.md](nets/endpoints.md) · [nets/endpoints.json](nets/endpoints.json)  
More: [https://catbash.net/nets.html](https://catbash.net/nets.html)

> Public shared nodes are often busy. Numbers are comparative, not lab-grade capacity. Prefer `-r` or `--region` first — a full dual-stack run moves a lot of data.

---

## CPUX — CPU eXaminer

Sequential **Geekbench 5 / 6 / 7** CPU benchmarks. Terminal prints real **single-core** and **multi-core** scores (not blank columns). Progress spinner while each suite runs.

```bash
# Interactive (1=GB5, 2=GB6, 3=GB7, 4=all)
curl -sL https://ba.sh/cpux | bash

# Geekbench 6 only
curl -sL https://ba.sh/cpux | bash -s -- 6

# All three suites, one after another
curl -sL https://ba.sh/cpux | bash -s -- all

# Chinese UI
curl -sL https://ba.sh/cpux | bash -s -- all -cn
```

Needs outbound HTTPS (IPv4) to `cdn.geekbench.com` and `browser.geekbench.com`. Binaries are large; run on a host that can take full CPU load.

More: [https://catbash.net/cpux.html](https://catbash.net/cpux.html)

---

## Repository layout

```
.
├── catbash.sh           # Launcher menu
├── hardware_info.sh     # SICK
├── cpux.sh              # CPUX (Geekbench 5/6/7)
├── index.html           # Hub site
├── sick.html            # SICK docs
├── nets.html            # NETS docs
├── cpux.html            # CPUX docs
├── nets/
│   ├── nets.sh
│   ├── endpoints.json
│   └── endpoints.md
├── worker.js            # Cloudflare short links
└── wrangler.jsonc
```

---

## Support

- **USDT (TRC20):** `TT6Ly1NpWSeYubufPVRUp4dz8SMUCZzcE5`
- **Afdian:** [afdian.com/a/ellye](https://afdian.com/a/ellye)
- **Blog:** [catcat.blog](https://catcat.blog)

---

## License

[MIT](LICENSE) · © Yuri NagaSaki
