# NETS — Network Endpoint Throughput Sampler

Public **iperf3** throughput sampler for Linux servers. Curated endpoints (Leaseweb, Clouvider, Eranium, OnlyServers, RedSwitches 25G, Advin, InterServer, …) with **IPv4 and IPv6** send/recv tests.

> Shared public nodes are often **busy**. Numbers are comparative, not lab-grade capacity.

## Layout

```
nets/
  nets.sh           # main script
  endpoints.json    # machine-readable endpoint catalog
  endpoints.md      # human-readable list + probe notes
  probe-results.txt # last TCP probe snapshot (optional)
  README.md
```

## Requirements

- `bash`, `iperf3`, `python3` (to load `endpoints.json`)
- Optional: `ping`, `timeout` (coreutils)

```bash
# Debian/Ubuntu
sudo apt install iperf3 python3
```

## Quick start

```bash
cd nets
chmod +x nets.sh
./nets.sh -l                 # list endpoints
./nets.sh -r -t 5            # reduced set, 5s per direction
./nets.sh --region apac -4   # APAC, IPv4 only
./nets.sh                    # full global catalog
```

## Options

| Flag | Meaning |
|------|---------|
| `-r` / `--reduced` | 8-endpoint short list |
| `--region na\|eu\|apac\|global\|reduced` | Filter by region |
| `-4` / `-6` | IPv4 or IPv6 only |
| `-t <sec>` | iperf duration per direction (default 10) |
| `-P <n>` | parallel streams (default 4) |
| `--send-only` / `--recv-only` | One direction only |
| `-l` | List endpoints |

## Endpoint policy (v0.1)

- **RedSwitches**: Amsterdam **25G** only (`43.250.53.56`)
- **Advin**: all published LG regions
- **OnlyServers**: UK `speedtest.onlyservers.com`
- **Eranium**: Amsterdam 100G (required)
- **Canada**: Leaseweb Montreal
- **No FiberState**
- **Hong Kong**: Leaseweb HKG; **no dedicated Taiwan** public 10G (use Tokyo as nearby)
- DATAPACKET full mesh: not in default (see planning notes)

See [endpoints.md](endpoints.md).

## Disclaimer

Endpoints are third-party public services. Be polite (`-P 4`, limited duration). Do not flood. Operators may block or rate-limit abuse.
