# NETS endpoint list (v5)

Public **iperf3** targets. Machine-readable: [`endpoints.json`](endpoints.json).

> Shared nodes are often **busy**. Numbers are comparative only.  
> Ports are tried internally (capped) and **not shown** in the default table.  
> Output is grouped by **Area**: `NA` · `EU` · `APAC`.

## Default (`global`) — 22 endpoints

### North America — NA (5)

| ID | Provider | City | Host | Speed | Stack |
|----|----------|------|------|-------|-------|
| purevoltage-nyc | PureVoltage | New York, US | `speedtest.nyc.purevoltage.com` | 40G | IPv4 |
| clouvider-la | Clouvider | Los Angeles, US | `la.speedtest.clouvider.net` | 10G | IPv4\|IPv6 |
| interserver-lax | InterServer | Los Angeles, US | `lax.speedtest.is.cc` | 10G | IPv4 |
| nocix-kc | Nocix | Kansas City, US | `speedtest.nocix.net` | 200G | IPv4\|IPv6 |
| leaseweb-mtl | Leaseweb | Montreal, CA | `speedtest.mtl2.ca.leaseweb.net` | 10G | IPv4\|IPv6 |

### Europe — EU (11)

| ID | Provider | City | Host | Speed | Stack |
|----|----------|------|------|-------|-------|
| onlyservers-uk | OnlyServers | United Kingdom | `speedtest.onlyservers.com` | 10G | IPv4 |
| clouvider-lon | Clouvider | London, UK | `lon.speedtest.clouvider.net` | 10G | IPv4\|IPv6 |
| eranium-ams | Eranium | Amsterdam, NL | `iperf-ams-nl.eranium.net` | 100G | IPv4\|IPv6 |
| redswitches-ams25g | RedSwitches | Amsterdam, NL | `43.250.53.56` | **25G** | IPv4 |
| scaleway-paris | Scaleway | Paris, FR | `iperf.online.net` | 100G | IPv4 |
| alwyzon-vie | Alwyzon | Vienna, AT | `iperf3-vie-at.alwyzon.net` | 200G | IPv4\|IPv6 |
| kamel-kista | Kamel Networks | Kista, SE | `speedtest.kamel.network` | 10G | IPv4\|IPv6 |
| fiberby-cph | Fiberby | Copenhagen, DK | `speed2.fiberby.dk` (9201–9240) | **25G** | IPv4\|IPv6 |
| buyvm-lux | BuyVM | Bissen, LU | `speedtest.lu.buyvm.net` | 10G | IPv4\|IPv6 |
| gigahost-svg | Gigahost | Sandefjord, NO | `lg.gigahost.no` (9201–9240) | **100G** | IPv4\|IPv6 |
| datapacket-fra | DataPacket | Frankfurt, DE | `185.102.219.93` | 10G | IPv4 |

### Asia-Pacific — APAC (6)

| ID | Provider | City | Host | Speed | Stack |
|----|----------|------|------|-------|-------|
| datapacket-tyo | DataPacket | Tokyo, JP | `89.187.160.1` | 10G | IPv4 |
| datapacket-sin | DataPacket | Singapore, SG | `89.187.162.1` | 10G | IPv4 |
| leaseweb-hkg | Leaseweb | Hong Kong, HK | `speedtest.hkg12.hk.leaseweb.net` | 10G | IPv4\|IPv6 |
| leaseweb-syd | Leaseweb | Sydney, AU | `speedtest.syd12.au.leaseweb.net` | 10G | IPv4\|IPv6 |
| ovh-bom | OVH | Mumbai, IN | `bom.proof.ovh.net` | 10G | IPv4\|IPv6 |
| uztelecom-tas | UZ Telecom | Tashkent, UZ | `speedtest.uztelecom.uz` | 10G | IPv4\|IPv6 |

## Reduced (`-r`)

`purevoltage-nyc` · `clouvider-la` · `leaseweb-mtl` · `onlyservers-uk` · `eranium-ams` · `fiberby-cph` · `datapacket-tyo` · `leaseweb-hkg`

## Filter by area

```bash
./nets.sh --region na     # North America
./nets.sh --region eu     # Europe
./nets.sh --region apac   # Asia-Pacific
```

## Changelog

- **v5:** Gigahost NO, DataPacket FRA; Scaleway rename; region grouping in UI
- **v4:** DataPacket TYO/SIN, Kamel SE, Fiberby DK, BuyVM LU, UZ Telecom
- **v3:** Removed Advin Osaka/Johor
