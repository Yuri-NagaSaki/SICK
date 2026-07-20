# NETS endpoint list

Public shared **iperf3** targets for NETS. Machine-readable copy: [`endpoints.json`](endpoints.json).

> Results often show `busy` and do **not** equal raw datacenter capacity.

Probe notes from build host (2026-07-20) are informational only.

## Default (`global`)

### North America

| ID | Provider | City | Host | Ports | Speed | Stack | Probe v4/v6 |
|----|----------|------|------|-------|-------|-------|-------------|
| leaseweb-nyc | Leaseweb | New York, US | `speedtest.nyc1.us.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 | open/open |
| leaseweb-lax | Leaseweb | Los Angeles, US | `speedtest.lax12.us.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 | open/open |
| leaseweb-mtl | Leaseweb | Montreal, CA | `speedtest.mtl2.ca.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 | open/open |
| clouvider-la | Clouvider | Los Angeles, US | `la.speedtest.clouvider.net` | 5200–5209 | 10G | IPv4\|IPv6 | open/refused@5200 |
| purevoltage-nyc | PureVoltage | New York, US | `speedtest.nyc.purevoltage.com` | 5201–5210 | 40G | IPv4 | open/— |
| nocix-kc | Nocix | Kansas City, US | `speedtest.nocix.net` | 5201–5205 | 200G | IPv4\|IPv6 | open/open |
| interserver-nyc | InterServer | Secaucus/NYC, US | `nyc.speedtest.is.cc` | 5201–5209 | 10G | IPv4\|IPv6 | open/open |
| interserver-lax | InterServer | Los Angeles, US | `lax.speedtest.is.cc` | 5201–5209 | 10G | IPv4 | open/— |
| advin-lax | Advin Servers | Los Angeles, US | `lg-lax.advinservers.com` | 5201 | 10G | IPv4\|IPv6 | open/open |
| advin-ewr | Advin Servers | Secaucus, US | `lg-ewr.advinservers.com` | 5201 | 10G | IPv4\|IPv6 | timeout/open |
| advin-mia | Advin Servers | Miami, US | `lg-mia.advinservers.com` | 5201 | 10G | IPv4\|IPv6 | open/open |
| advin-mci | Advin Servers | Kansas City, US | `lg-mci.advinservers.com` | 5201 | 10G | IPv4\|IPv6 | open/open |

### Europe

| ID | Provider | City | Host | Ports | Speed | Stack | Probe v4/v6 |
|----|----------|------|------|-------|-------|-------|-------------|
| onlyservers-uk | OnlyServers | United Kingdom | `speedtest.onlyservers.com` | 5201 | 10G | IPv4 | open/— |
| eranium-ams | Eranium | Amsterdam, NL | `iperf-ams-nl.eranium.net` | 5201–5210 | 100G | IPv4\|IPv6 | open/open |
| clouvider-lon | Clouvider | London, UK | `lon.speedtest.clouvider.net` | 5200–5209 | 10G | IPv4\|IPv6 | open/open |
| online-paris | Online.net/Scaleway | Paris, FR | `iperf.online.net` | 5200–5209 | 100G | IPv4 | open/— |
| alwyzon-vie | Alwyzon | Vienna, AT | `iperf3-vie-at.alwyzon.net` | 5201–5210 | 200G | IPv4\|IPv6 | open/open |
| redswitches-ams25g | RedSwitches | Amsterdam Iron Mountain, NL | `43.250.53.56` | 5201 | **25G** | IPv4 | open/— |
| advin-nbg | Advin Servers | Nuremberg, DE | `lg-nbg.advinservers.com` | 5201 | 10G | IPv4 | timeout |

### Asia-Pacific

| ID | Provider | City | Host | Ports | Speed | Stack | Probe v4/v6 |
|----|----------|------|------|-------|-------|-------|-------------|
| leaseweb-sin | Leaseweb | Singapore, SG | `speedtest.sin1.sg.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 | open/open |
| leaseweb-hkg | Leaseweb | Hong Kong, HK | `speedtest.hkg12.hk.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 | open/open |
| leaseweb-tyo | Leaseweb | Tokyo, JP | `speedtest.tyo11.jp.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 | open/open |
| leaseweb-syd | Leaseweb | Sydney, AU | `speedtest.syd12.au.leaseweb.net` | 5201–5210 | 10G | IPv4\|IPv6 | open/open |
| ovh-bom | OVH | Mumbai, IN | `bom.proof.ovh.net` | 5201–5210 | 10G | IPv4\|IPv6 | timeout/open |
| advin-kix | Advin Servers | Osaka, JP | `lg-kix.advinservers.com` | 5201 | 10G | IPv4 | timeout |
| advin-jhb | Advin Servers | Johor, MY | `lg-jhb.advinservers.com` | 5201 | 10G | IPv4 | fail |

## Reduced (`-r`)

`leaseweb-nyc`, `leaseweb-lax`, `leaseweb-mtl`, `onlyservers-uk`, `eranium-ams`, `redswitches-ams25g`, `leaseweb-hkg`, `leaseweb-sin`

## Not in default

- **FiberState** — removed by request  
- **Taiwan** — no solid public 10G pool; use Tokyo Leaseweb as nearby reference  
- **Russia HOSTKEY** — optional future `region=ru`  
- **DATAPACKET full set** — optional future `provider=datapacket` (mostly single port 5201)

## Sources

- nws.sh / yabs open endpoint arrays  
- [interserver.net/speedtest](https://www.interserver.net/speedtest/)  
- [speedtest.onlyservers.com](https://speedtest.onlyservers.com/)  
- [lg.redswitches.com](https://lg.redswitches.com/) (25G only)  
- [lg.advinservers.com](https://lg.advinservers.com/)  
- [iperf3serverlist.net](https://iperf3serverlist.net/)  
