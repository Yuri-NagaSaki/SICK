# 猫脚本 · Catbash

Open-source **Linux server scripts** you run with one `curl | bash` — no installers, no daemons, zero leftover footprint.

**Website:** [https://catbash.net/](https://catbash.net/)  
**Language:** [English](README.md) · [中文](README_CN.md)

---

## What’s inside

| Tool | Role | One-liner | Docs |
|------|------|-----------|------|
| **Menu** | Pick SICK / NETS / CPUX, or run all | `curl -sL https://ba.sh/menu \| bash` | [catbash.sh](catbash.sh) |
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

Interactive menu (`1` = SICK, `2` = NETS, `3` = CPUX, `4` = all, `0` = exit):

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

Full check, yabs-style — SICK → NETS (reduced) → CPUX (Geekbench 6) in one scrollback:

```bash
curl -sL https://ba.sh/menu | bash -s -- all
curl -sL https://ba.sh/menu | bash -s -- all -cn
```

Through `curl | bash`, always use `bash -s -- <args>`. Without an interactive terminal (`ssh host '…'`, cron) the menu prints usage and exits instead of hanging.

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
| `--no-color` / `--color` | Plain output / force colors (`NO_COLOR` honoured) |
| `--no-clear` | Do not clear the screen |
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

# Auto-install iperf3 if missing
curl -sL https://ba.sh/nets | bash -s -- -y -r

# Asia only, IPv4
curl -sL https://ba.sh/nets | bash -s -- --region apac -4

# List catalog
curl -sL https://ba.sh/nets | bash -s -- -l

# JSON results (progress goes to stderr)
curl -sL https://ba.sh/nets | bash -s -- -r --json > nets.json
```

**Deps:** only `iperf3` (catalog and results are parsed with awk — python3 is no longer needed). A missing iperf3 triggers a **Y/N install prompt** (or `-y` / `--no-install`). A live status line shows the test in progress; Ctrl-C prints a summary of what finished. Unreachable endpoints (timeouts / refusals / DNS failures) are skipped quickly instead of retried port by port.

### Options

| Flag | Description |
|------|-------------|
| `-r` / `--reduced` | Short endpoint list |
| `--region na\|eu\|apac\|global\|reduced` | Filter by region |
| `-4` / `-6` | IPv4 only / IPv6 only |
| `-t <sec>` | Duration per direction (default 10) |
| `-P <n>` | Parallel streams (default 4) |
| `--send-only` / `--recv-only` | One direction |
| `-j` / `--json` | JSON results on stdout |
| `-y` / `--yes` | Auto-install missing deps |
| `--no-install` | Never install; exit if deps missing |
| `--no-clear` / `--no-color` | Keep screen / plain output (`NO_COLOR` honoured) |
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

# JSON result
curl -sL https://ba.sh/cpux | bash -s -- 6 --json > gb6.json

# Scores missing? Re-fetch them for an existing result URL (no re-run)
curl -sL https://ba.sh/cpux | bash -s -- --fetch https://browser.geekbench.com/v6/cpu/123456
```

Needs outbound HTTPS (IPv4) to `cdn.geekbench.com` and `browser.geekbench.com`. Binaries are large; run on a host that can take full CPU load.

**How scores are obtained:** the Geekbench tryout CLI uploads but never prints scores. CPUX tries, in order: local CLI output (licensed builds) → the result page directly (plain and browser UA, IPv4) → the raw result JSON → `catbash.net/api/gb` (server-side fetch on Cloudflare, see `worker.js`) → `r.jina.ai` with cache bypass. Each number is paired with its own "Single-Core / Multi-Core Score" label, so the two can never be swapped. The whole chain is capped at 120 s (`--fetch-timeout`); on failure CPUX prints a one-line `--fetch` retry command.

| Flag | Description |
|------|-------------|
| `5` / `6` / `7` / `all` | Pick versions (combine: `-5 -7`) |
| `-j` / `--json` | JSON on stdout |
| `--fetch URL…` | Only fetch scores of existing result URLs |
| `--fetch-timeout SEC` | Score fetch budget (default 120) |
| `-y` / `--yes` | Don't ask; continue past warnings |
| `-k` / `--keep` | Keep downloaded binaries |
| `--no-clear` / `--no-color` | Keep screen / plain output |
| `-cn` / `-us` | Chinese / English UI |

Environment: `CPUX_GB5_VER` / `CPUX_GB6_VER` / `CPUX_GB7_VER` (pin builds), `CPUX_MIRROR` (custom download mirror), `CPUX_WORKDIR` (unpack dir), `CPUX_SCORE_API` / `CPUX_JINA` (set empty to disable a score source), `JINA_API_KEY`.

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
├── worker.js            # Cloudflare short links + /api/gb (CPUX score fallback)
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
