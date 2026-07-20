# NETS — Network Endpoint Throughput Sampler

Part of **[猫脚本 / Catbash](https://catbash.net/)** · [Docs page](https://catbash.net/nets.html)

Public **iperf3** throughput sampler for Linux servers. Curated endpoints (Leaseweb, Clouvider, Eranium, OnlyServers, RedSwitches 25G, InterServer, …) with **IPv4 and IPv6** send/recv tests.

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

- `bash`, `iperf3`, `python3` (to load `endpoints.json`)
- Optional: `ping`, `timeout` (coreutils)

```bash
# Debian/Ubuntu
sudo apt install iperf3 python3
```

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
| `-l` | List endpoints |

## Endpoint policy (v6)

- **NA** PureVoltage NYC · Clouvider/InterServer LA · Nocix KC · Leaseweb MTL  
- **EU** Wobcom/Leaseweb FRA · Cosmonova Kyiv · Gigahost NO · Scaleway · Eranium/RS AMS · Kamel · Fiberby · BuyVM · …  
- **APAC** Leaseweb TYO/SIN/HKG/SYD · OVH Mumbai · UZ Telecom  
- Output grouped by area (`NA` / `EU` / `APAC`). Ports capped/hidden. Summary shows Send/Recv traffic.

See [endpoints.md](endpoints.md). Full reverse-proxy URL list: [PROXY.md](PROXY.md).

## Disclaimer

Endpoints are third-party public services. Be polite (`-P 4`, limited duration). Do not flood. Operators may block or rate-limit abuse.
