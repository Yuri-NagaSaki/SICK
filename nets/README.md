# NETS — Network Endpoint Throughput Sampler

Part of **[猫脚本 / Catbash](https://catbash.net/)** · [Docs page](https://catbash.net/nets.html)

Public **iperf3** throughput sampler for Linux servers. Curated endpoints (Leaseweb, Clouvider, Eranium, OnlyServers, RedSwitches 25G, …) with **IPv4 and IPv6** send/recv tests.

> Shared public nodes are often **busy**. Numbers are comparative, not lab-grade capacity.

## One-line run

Short install URLs (same script):

- `https://ba.sh/nets`
- `https://catbash.net/nets`

```bash
curl -sL https://ba.sh/nets | bash
# curl -sL https://catbash.net/nets | bash

# Reduced set
curl -sL https://catbash.net/nets | bash -s -- -r
```

## Layout

```
nets/
  index.html        # intro page (served at /nets/)
  nets.sh           # main script (served at /nets)
  endpoints.json    # machine-readable endpoint catalog
  endpoints.md      # human-readable list + probe notes
  probe-results.txt # last TCP probe snapshot (optional)
  README.md
```

## Requirements

- `bash` 4+, `iperf3` (endpoints and results are parsed with awk — no python/jq)
- Optional: `timeout` (coreutils, caps stalled tests), `getent` (skips hosts without A/AAAA fast), `ip` (IPv6 route check)

```bash
# Debian/Ubuntu
sudo apt install iperf3
```

Custom catalog: `NETS_ENDPOINTS_JSON=/path/endpoints.json ./nets.sh`

## Quick start (local)

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
| `-j` / `--json` | JSON results on stdout (progress on stderr) |
| `-y` / `--no-install` | Auto-install iperf3 / never install |
| `--no-clear` / `--no-color` | Keep screen / plain output (`NO_COLOR` honoured) |
| `-l` | List endpoints |

Port handling: each test starts at a random port in the endpoint's range (spreads load across users), moves on when a port is busy, and gives up early on hosts that are unreachable (2 timeouts / 4 refusals / DNS failure) instead of walking the whole range.

## Endpoint policy (v6)

- **NA** PureVoltage NYC · Clouvider LA · Nocix KC · Leaseweb MTL 
- **EU** Wobcom/Leaseweb FRA · Cosmonova Kyiv · Gigahost NO · Scaleway · Eranium/RS AMS · Kamel · Fiberby · BuyVM · …  
- **APAC** Leaseweb TYO/SIN/HKG/SYD · OVH Mumbai · UZ Telecom  
- Output grouped by area (`NA` / `EU` / `APAC`). Ports capped/hidden. Summary shows Send/Recv traffic.

See [endpoints.md](endpoints.md). Full reverse-proxy URL list: [PROXY.md](PROXY.md).

## Disclaimer

Endpoints are third-party public services. Be polite (`-P 4`, limited duration). Do not flood. Operators may block or rate-limit abuse.
