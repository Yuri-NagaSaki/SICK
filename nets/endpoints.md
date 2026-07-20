# NETS endpoint list (v6)

Public **iperf3** targets. Machine-readable: [`endpoints.json`](endpoints.json).

> Shared nodes are often **busy**. Numbers are comparative only.  
> Ports are tried internally (capped) and **not shown** in the default table.  
> Output is grouped by **Area**: `NA` · `EU` · `APAC`.

## Default (`global`) — 24 endpoints

### North America — NA (5)

| ID | Provider | City | Host | Speed | Stack |
|----|----------|------|------|-------|-------|
| purevoltage-nyc | PureVoltage | New York, US | `speedtest.nyc.purevoltage.com` | 40G | IPv4 |
| clouvider-la | Clouvider | Los Angeles, US | `la.speedtest.clouvider.net` | 10G | IPv4\|IPv6 |
| interserver-lax | InterServer | Los Angeles, US | `lax.speedtest.is.cc` | 10G | IPv4 |
| nocix-kc | Nocix | Kansas City, US | `speedtest.nocix.net` | 200G | IPv4\|IPv6 |
| leaseweb-mtl | Leaseweb | Montreal, CA | `speedtest.mtl2.ca.leaseweb.net` | 10G | IPv4\|IPv6 |

### Europe — EU (13)

| ID | Provider | City | Host | Speed | Stack |
|----|----------|------|------|-------|-------|
| onlyservers-uk | OnlyServers | United Kingdom | `speedtest.onlyservers.com` | 10G | IPv4 |
| clouvider-lon | Clouvider | London, UK | `lon.speedtest.clouvider.net` | 10G | IPv4\|IPv6 |
| eranium-ams | Eranium | Amsterdam, NL | `iperf-ams-nl.eranium.net` | 100G | IPv4\|IPv6 |
| redswitches-ams25g | RedSwitches | Amsterdam, NL | `43.250.53.56` | **25G** | IPv4 |
| scaleway-paris | Scaleway | Paris, FR | `iperf.online.net` | 100G | IPv4 |
| alwyzon-vie | Alwyzon | Vienna, AT | `iperf3-vie-at.alwyzon.net` | 200G | IPv4\|IPv6 |
| kamel-kista | Kamel Networks | Kista, SE | `speedtest.kamel.network` | 10G | IPv4\|IPv6 |
| fiberby-cph | Fiberby | Copenhagen, DK | `speed2.fiberby.dk` | **25G** | IPv4\|IPv6 |
| buyvm-lux | BuyVM | Bissen, LU | `speedtest.lu.buyvm.net` | 10G | IPv4\|IPv6 |
| gigahost-svg | Gigahost | Sandefjord, NO | `lg.gigahost.no` | **100G** | **IPv4 only** |
| wobcom-fra | Wobcom | Frankfurt, DE | `a205.speedtest.wobcom.de` | **25G** | IPv4\|IPv6 |
| leaseweb-fra | Leaseweb | Frankfurt, DE | `speedtest.fra1.de.leaseweb.net` | 10G | IPv4\|IPv6 |
| cosmonova-iev | Cosmonova | Kyiv, UA | `speed.cosmonova.net` | **40G** | IPv4 |

### Asia-Pacific — APAC (6)

| ID | Provider | City | Host | Speed | Stack |
|----|----------|------|------|-------|-------|
| leaseweb-tyo | Leaseweb | Tokyo, JP | `speedtest.tyo11.jp.leaseweb.net` | 10G | IPv4\|IPv6 |
| leaseweb-sin | Leaseweb | Singapore, SG | `speedtest.sin1.sg.leaseweb.net` | 10G | IPv4\|IPv6 |
| leaseweb-hkg | Leaseweb | Hong Kong, HK | `speedtest.hkg12.hk.leaseweb.net` | 10G | IPv4\|IPv6 |
| leaseweb-syd | Leaseweb | Sydney, AU | `speedtest.syd12.au.leaseweb.net` | 10G | IPv4\|IPv6 |
| ovh-bom | OVH | Mumbai, IN | `bom.proof.ovh.net` | 10G | IPv4\|IPv6 |
| uztelecom-tas | UZ Telecom | Tashkent, UZ | `speedtest.uztelecom.uz` | 10G | IPv4\|IPv6 |

## Notes

### Gigahost IPv6 always failed
`lg.gigahost.no` has **A only** (no **AAAA**). `iperf3 -6` returns *No address associated with hostname*. Stack is therefore **IPv4 only** so the script skips v6 for this host.

### DataPacket TYO / SIN / FRA removed
Public iperf on DataPacket IPs frequently failed send/recv. Replaced with:
- **Tokyo / Singapore** → Leaseweb
- **Frankfurt** → Wobcom (+ Leaseweb FRA)

## Reduced (`-r`)

`purevoltage-nyc` · `clouvider-la` · `leaseweb-mtl` · `onlyservers-uk` · `eranium-ams` · `wobcom-fra` · `leaseweb-tyo` · `leaseweb-hkg`

## Changelog

- **v6:** Drop DataPacket TYO/SIN/FRA; +Leaseweb TYO/SIN/FRA, Wobcom FRA, Cosmonova Kyiv; Gigahost IPv4-only
- **v5:** Gigahost NO, DataPacket FRA; Scaleway rename; region grouping
- **v4:** DataPacket TYO/SIN, Kamel, Fiberby, BuyVM, UZ Telecom
