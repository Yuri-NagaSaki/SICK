# NETS endpoint list (v2)

Public **iperf3** targets. Machine-readable: [`endpoints.json`](endpoints.json).

> Shared nodes are often **busy**. Numbers are comparative only.

## Default (`global`) — 16 endpoints

### North America (5)

| ID | Provider | City | Host | Ports | Speed | Stack |
|----|----------|------|------|-------|-------|-------|
| purevoltage-nyc | PureVoltage | New York, US | `speedtest.nyc.purevoltage.com` | 5201–5210 | 40G | IPv4 |
| clouvider-la | Clouvider | Los Angeles, US | `la.speedtest.clouvider.net` | 5200–5209 | 10G | IPv4\|IPv6 |
| interserver-lax | InterServer | Los Angeles, US | `lax.speedtest.is.cc` | 5201–5209 | 10G | IPv4 |
| nocix-kc | Nocix | Kansas City, US | `speedtest.nocix.net` | 5201–5205 | 200G | IPv4\|IPv6 |
| leaseweb-mtl | Leaseweb | Montreal, CA | `speedtest.mtl2.ca.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 |

### Europe (6)

| ID | Provider | City | Host | Ports | Speed | Stack |
|----|----------|------|------|-------|-------|-------|
| onlyservers-uk | OnlyServers | United Kingdom | `speedtest.onlyservers.com` | 5201 | 10G | IPv4 |
| clouvider-lon | Clouvider | London, UK | `lon.speedtest.clouvider.net` | 5200–5209 | 10G | IPv4\|IPv6 |
| eranium-ams | Eranium | Amsterdam, NL | `iperf-ams-nl.eranium.net` | 5201–5210 | 100G | IPv4\|IPv6 |
| redswitches-ams25g | RedSwitches | Amsterdam Iron Mountain, NL | `43.250.53.56` | 5201 | **25G** | IPv4 |
| online-paris | Online.net/Scaleway | Paris, FR | `iperf.online.net` | 5200–5209 | 100G | IPv4 |
| alwyzon-vie | Alwyzon | Vienna, AT | `iperf3-vie-at.alwyzon.net` | 5201–5210 | 200G | IPv4\|IPv6 |

### Asia-Pacific (5)

| ID | Provider | City | Host | Ports | Speed | Stack |
|----|----------|------|------|-------|-------|-------|
| advin-kix | Advin Servers | Osaka, JP | `lg-kix.advinservers.com` | 5201 | 10G | IPv4 |
| advin-jhb | Advin Servers | Johor, MY | `lg-jhb.advinservers.com` | 5201 | 10G | IPv4 |
| leaseweb-hkg | Leaseweb | Hong Kong, HK | `speedtest.hkg12.hk.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 |
| leaseweb-syd | Leaseweb | Sydney, AU | `speedtest.syd12.au.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 |
| ovh-bom | OVH | Mumbai, IN | `bom.proof.ovh.net` | 5201–5210 | 10G | IPv4\|IPv6 |

## Reduced (`-r`)

`purevoltage-nyc` · `clouvider-la` · `leaseweb-mtl` · `onlyservers-uk` · `eranium-ams` · `redswitches-ams25g` · `advin-kix` · `leaseweb-hkg`

## Removed in v2

- FiberState (all)
- Leaseweb NYC / LAX / SIN / TYO
- InterServer NYC
- Advin LAX / EWR / MIA / MCI / NBG
- PureVoltage kept for NYC only; LA = Clouvider + InterServer; KC = Nocix only
- Japan / SE Asia = Advin only (KIX + JHB)

## Selection notes

| Metro | Kept |
|-------|------|
| NYC | PureVoltage |
| LA | Clouvider + InterServer |
| Kansas City | Nocix |
| Canada | Leaseweb Montreal |
| UK | OnlyServers + Clouvider London |
| Amsterdam | Eranium + RedSwitches 25G |
| Japan / SE Asia | Advin Osaka + Johor |
