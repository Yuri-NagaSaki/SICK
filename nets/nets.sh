#!/usr/bin/env bash
#
# NETS — Network Endpoint Throughput Sampler
# Public iperf3 throughput tests (IPv4/IPv6) against curated endpoints.
#
# Usage:
#   ./nets.sh
#   ./nets.sh -r
#   ./nets.sh --region na
#   ./nets.sh -4 -t 10 -P 4
#
# Endpoint list: endpoints.json (same directory) or embedded fallback.
#
set -uo pipefail

VERSION="0.3.1"
# When piped via curl|bash, BASH_SOURCE may be /dev/fd/* — resolve carefully.
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR=""
fi
ENDPOINTS_JSON="${NETS_ENDPOINTS_JSON:-}"
ENDPOINTS_TMP=""
# Preferred public URLs when running via curl|bash (no local file tree)
ENDPOINTS_URLS=(
  "${NETS_ENDPOINTS_URL:-}"
  "https://catbash.net/nets/endpoints.json"
  "https://ba.sh/nets/endpoints.json"
)

# BEGIN_EMBEDDED_ENDPOINTS
write_embedded_endpoints() {
  # Writes embedded catalog to $1
  cat >"$1" <<'NETS_ENDPOINTS_JSON'
{
  "version": 5,
  "updated": "2026-07-20",
  "notes": [
    "Public shared iperf3 endpoints — results may show busy and do not equal raw DC capacity.",
    "port_range is inclusive. Script tries ports on busy/fail (ports not shown; max tries capped).",
    "stack is planning metadata; runtime still probes IPv4/IPv6.",
    "v5: +Gigahost NO, DataPacket FRA; Scaleway rename; region column in table."
  ],
  "endpoints": [
    {
      "id": "clouvider-la",
      "provider": "Clouvider",
      "city": "Los Angeles, US",
      "region": "na",
      "host": "la.speedtest.clouvider.net",
      "port_range": [
        5200,
        5209
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "yabs"
    },
    {
      "id": "interserver-lax",
      "provider": "InterServer",
      "city": "Los Angeles, US",
      "region": "na",
      "host": "lax.speedtest.is.cc",
      "port_range": [
        5201,
        5209
      ],
      "speed": "10G",
      "stack": "IPv4",
      "source": "interserver.net/speedtest"
    },
    {
      "id": "leaseweb-mtl",
      "provider": "Leaseweb",
      "city": "Montreal, CA",
      "region": "na",
      "host": "speedtest.mtl2.ca.leaseweb.net",
      "port_range": [
        5201,
        5210
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "iperf3serverlist"
    },
    {
      "id": "nocix-kc",
      "provider": "Nocix",
      "city": "Kansas City, US",
      "region": "na",
      "host": "speedtest.nocix.net",
      "port_range": [
        5201,
        5205
      ],
      "speed": "200G",
      "stack": "IPv4|IPv6",
      "source": "nws"
    },
    {
      "id": "purevoltage-nyc",
      "provider": "PureVoltage",
      "city": "New York, US",
      "region": "na",
      "host": "speedtest.nyc.purevoltage.com",
      "port_range": [
        5201,
        5210
      ],
      "speed": "40G",
      "stack": "IPv4",
      "source": "nws"
    },
    {
      "id": "alwyzon-vie",
      "provider": "Alwyzon",
      "city": "Vienna, AT",
      "region": "eu",
      "host": "iperf3-vie-at.alwyzon.net",
      "port_range": [
        5201,
        5210
      ],
      "speed": "200G",
      "stack": "IPv4|IPv6",
      "source": "nws"
    },
    {
      "id": "buyvm-lux",
      "provider": "BuyVM",
      "city": "Bissen, LU",
      "region": "eu",
      "host": "speedtest.lu.buyvm.net",
      "port_range": [
        5201,
        5201
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "buyvm.net"
    },
    {
      "id": "clouvider-lon",
      "provider": "Clouvider",
      "city": "London, UK",
      "region": "eu",
      "host": "lon.speedtest.clouvider.net",
      "port_range": [
        5200,
        5209
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "yabs"
    },
    {
      "id": "datapacket-fra",
      "provider": "DataPacket",
      "city": "Frankfurt, DE",
      "region": "eu",
      "host": "185.102.219.93",
      "port_range": [
        5201,
        5201
      ],
      "speed": "10G",
      "stack": "IPv4",
      "source": "datapacket.com"
    },
    {
      "id": "eranium-ams",
      "provider": "Eranium",
      "city": "Amsterdam, NL",
      "region": "eu",
      "host": "iperf-ams-nl.eranium.net",
      "port_range": [
        5201,
        5210
      ],
      "speed": "100G",
      "stack": "IPv4|IPv6",
      "source": "yabs"
    },
    {
      "id": "fiberby-cph",
      "provider": "Fiberby",
      "city": "Copenhagen, DK",
      "region": "eu",
      "host": "speed2.fiberby.dk",
      "port_range": [
        9201,
        9240
      ],
      "speed": "25G",
      "stack": "IPv4|IPv6",
      "source": "fiberby.dk"
    },
    {
      "id": "gigahost-svg",
      "provider": "Gigahost",
      "city": "Sandefjord, NO",
      "region": "eu",
      "host": "lg.gigahost.no",
      "port_range": [
        9201,
        9240
      ],
      "speed": "100G",
      "stack": "IPv4|IPv6",
      "source": "gigahost.no"
    },
    {
      "id": "kamel-kista",
      "provider": "Kamel Networks",
      "city": "Kista, SE",
      "region": "eu",
      "host": "speedtest.kamel.network",
      "port_range": [
        5201,
        5205
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "kamel.network"
    },
    {
      "id": "onlyservers-uk",
      "provider": "OnlyServers",
      "city": "United Kingdom",
      "region": "eu",
      "host": "speedtest.onlyservers.com",
      "port_range": [
        5201,
        5201
      ],
      "speed": "10G",
      "stack": "IPv4",
      "source": "speedtest.onlyservers.com"
    },
    {
      "id": "redswitches-ams25g",
      "provider": "RedSwitches",
      "city": "Amsterdam, NL",
      "region": "eu",
      "host": "43.250.53.56",
      "port_range": [
        5201,
        5201
      ],
      "speed": "25G",
      "stack": "IPv4",
      "source": "lg.redswitches.com"
    },
    {
      "id": "scaleway-paris",
      "provider": "Scaleway",
      "city": "Paris, FR",
      "region": "eu",
      "host": "iperf.online.net",
      "port_range": [
        5200,
        5209
      ],
      "speed": "100G",
      "stack": "IPv4",
      "source": "nws"
    },
    {
      "id": "datapacket-sin",
      "provider": "DataPacket",
      "city": "Singapore, SG",
      "region": "apac",
      "host": "89.187.162.1",
      "port_range": [
        5201,
        5201
      ],
      "speed": "10G",
      "stack": "IPv4",
      "source": "datapacket.com"
    },
    {
      "id": "datapacket-tyo",
      "provider": "DataPacket",
      "city": "Tokyo, JP",
      "region": "apac",
      "host": "89.187.160.1",
      "port_range": [
        5201,
        5201
      ],
      "speed": "10G",
      "stack": "IPv4",
      "source": "datapacket.com"
    },
    {
      "id": "leaseweb-hkg",
      "provider": "Leaseweb",
      "city": "Hong Kong, HK",
      "region": "apac",
      "host": "speedtest.hkg12.hk.leaseweb.net",
      "port_range": [
        5201,
        5210
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "iperf3serverlist"
    },
    {
      "id": "leaseweb-syd",
      "provider": "Leaseweb",
      "city": "Sydney, AU",
      "region": "apac",
      "host": "speedtest.syd12.au.leaseweb.net",
      "port_range": [
        5201,
        5210
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "nws"
    },
    {
      "id": "ovh-bom",
      "provider": "OVH",
      "city": "Mumbai, IN",
      "region": "apac",
      "host": "bom.proof.ovh.net",
      "port_range": [
        5201,
        5210
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "nws"
    },
    {
      "id": "uztelecom-tas",
      "provider": "UZ Telecom",
      "city": "Tashkent, UZ",
      "region": "apac",
      "host": "speedtest.uztelecom.uz",
      "port_range": [
        5200,
        5209
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "uztelecom.uz"
    }
  ],
  "reduced_ids": [
    "purevoltage-nyc",
    "clouvider-la",
    "leaseweb-mtl",
    "onlyservers-uk",
    "eranium-ams",
    "fiberby-cph",
    "datapacket-tyo",
    "leaseweb-hkg"
  ]
}
NETS_ENDPOINTS_JSON
}
# END_EMBEDDED_ENDPOINTS


# Defaults
TEST_TIME=10
PARALLEL=4
REGION="global"          # global | na | eu | apac | reduced
FORCE_IP=""              # "" | 4 | 6
SKIP_RECV=false
SKIP_SEND=false
LIST_ONLY=false
CONNECT_TIMEOUT=5
IPERF_BIN=""

# Colors (TTY only; keep plain when piped)
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'; MAGENTA=$'\033[0;35m'
  WHITE=$'\033[1;37m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
  # Semantic
  C_UP=$'\033[38;5;81m'     # upload / send
  C_DOWN=$'\033[38;5;114m'  # download / recv
  C_OK=$'\033[38;5;114m'
  C_BUSY=$'\033[38;5;221m'
  C_FAIL=$'\033[38;5;203m'
  C_META=$'\033[38;5;245m'
  C_LOC=$'\033[38;5;252m'
  C_PROV=$'\033[38;5;180m'
  C_HDR=$'\033[1;38;5;222m'
  C_BAR=$'\033[38;5;73m'
else
  RED=""; GREEN=""; YELLOW=""; CYAN=""; BLUE=""; MAGENTA=""
  WHITE=""; BOLD=""; DIM=""; NC=""
  C_UP=""; C_DOWN=""; C_OK=""; C_BUSY=""; C_FAIL=""; C_META=""
  C_LOC=""; C_PROV=""; C_HDR=""; C_BAR=""
fi

HAVE_IPV4=false
HAVE_IPV6=false

# Traffic totals for this run (bytes on the wire, approx. from iperf3)
TOTAL_SEND_BYTES=0   # upload: client -> server
TOTAL_RECV_BYTES=0   # download: server -> client
TOTAL_OK=0
TOTAL_BUSY=0
TOTAL_FAIL=0
TOTAL_TESTS=0

usage() {
  cat <<EOF
NETS v${VERSION} — Network Endpoint Throughput Sampler

Usage: $(basename "$0") [options]

Options:
  -r, --reduced         Short list (8 endpoints)
  --region <name>       global | na | eu | apac | reduced  (default: global)
  -4                    IPv4 only
  -6                    IPv6 only
  -t, --time <sec>      iperf3 test duration per direction (default: ${TEST_TIME})
  -P, --parallel <n>    parallel streams (default: ${PARALLEL})
  --send-only           Upload only (client -> server)
  --recv-only           Download only (server -> client, iperf -R)
  -l, --list            List endpoints and exit
  -h, --help            Show help
  -v, --version         Show version

Examples:
  $(basename "$0")
  $(basename "$0") -r -t 8
  $(basename "$0") --region apac -4
EOF
}

log()  { printf '%s\n' "$*"; }
info() { printf '%b\n' "${CYAN}$*${NC}"; }
ok()   { printf '%b\n' "${GREEN}$*${NC}"; }
warn() { printf '%b\n' "${YELLOW}$*${NC}"; }
err()  { printf '%b\n' "${RED}$*${NC}" >&2; }

detect_iperf() {
  if command -v iperf3 >/dev/null 2>&1; then
    IPERF_BIN="$(command -v iperf3)"
    return 0
  fi
  err "iperf3 not found. Install it first, e.g.:"
  err "  apt install iperf3   # Debian/Ubuntu"
  err "  dnf install iperf3   # RHEL/Fedora"
  err "  pacman -S iperf3     # Arch"
  return 1
}

detect_connectivity() {
  HAVE_IPV4=false
  HAVE_IPV6=false
  # Lightweight connectivity hints (DNS + TCP to well-known)
  if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 \
     || ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 \
     || getent ahostsv4 one.one.one.one >/dev/null 2>&1; then
    HAVE_IPV4=true
  fi
  if ping -6 -c1 -W2 2606:4700:4700::1111 >/dev/null 2>&1 \
     || getent ahostsv6 one.one.one.one >/dev/null 2>&1; then
    HAVE_IPV6=true
  fi
  # Fallback: assume v4 if neither detected (common in restricted ICMP envs)
  if ! $HAVE_IPV4 && ! $HAVE_IPV6; then
    HAVE_IPV4=true
    warn "Could not confirm IPv4/IPv6; assuming IPv4."
  fi
}

resolve_endpoints_json() {
  # 1) explicit path
  if [[ -n "$ENDPOINTS_JSON" && -f "$ENDPOINTS_JSON" ]]; then
    return 0
  fi
  # 2) beside script (local checkout)
  if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/endpoints.json" ]]; then
    ENDPOINTS_JSON="${SCRIPT_DIR}/endpoints.json"
    return 0
  fi
  # 3) cwd
  if [[ -f "./endpoints.json" ]]; then
    ENDPOINTS_JSON="$(pwd)/endpoints.json"
    return 0
  fi
  ENDPOINTS_TMP="$(mktemp "${TMPDIR:-/tmp}/nets-endpoints.XXXXXX.json")"
  # 4) embedded catalog first — always matches this script version (curl|bash)
  if declare -F write_embedded_endpoints >/dev/null 2>&1; then
    write_embedded_endpoints "$ENDPOINTS_TMP"
    if [[ -s "$ENDPOINTS_TMP" ]]; then
      ENDPOINTS_JSON="$ENDPOINTS_TMP"
      return 0
    fi
  fi
  # 5) download from public hosts (override / fallback)
  local url
  for url in "${ENDPOINTS_URLS[@]}"; do
    [[ -z "$url" ]] && continue
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL --connect-timeout 8 --max-time 30 "$url" -o "$ENDPOINTS_TMP" 2>/dev/null \
        && [[ -s "$ENDPOINTS_TMP" ]]; then
        ENDPOINTS_JSON="$ENDPOINTS_TMP"
        info "Loaded endpoints from ${url}"
        return 0
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -T 30 -O "$ENDPOINTS_TMP" "$url" 2>/dev/null \
        && [[ -s "$ENDPOINTS_TMP" ]]; then
        ENDPOINTS_JSON="$ENDPOINTS_TMP"
        info "Loaded endpoints from ${url}"
        return 0
      fi
    fi
  done
  rm -f "$ENDPOINTS_TMP"
  ENDPOINTS_TMP=""
  err "Could not load endpoints.json (local, embedded, or remote)."
  return 1
}

cleanup() {
  [[ -n "${ENDPOINTS_TMP:-}" && -f "$ENDPOINTS_TMP" ]] && rm -f "$ENDPOINTS_TMP"
}
trap cleanup EXIT

# Load endpoints into parallel bash arrays via python3 (preferred) or jq.
# Arrays: EP_ID EP_PROVIDER EP_CITY EP_REGION EP_HOST EP_P0 EP_P1 EP_SPEED EP_STACK
load_endpoints() {
  EP_ID=(); EP_PROVIDER=(); EP_CITY=(); EP_REGION=()
  EP_HOST=(); EP_P0=(); EP_P1=(); EP_SPEED=(); EP_STACK=()

  resolve_endpoints_json || return 1

  if command -v python3 >/dev/null 2>&1; then
    local dumped
    dumped="$(python3 - "$ENDPOINTS_JSON" "$REGION" <<'PY'
import json, sys
path, region = sys.argv[1], sys.argv[2]
data = json.load(open(path))
eps = data["endpoints"]
if region == "reduced":
    ids = set(data.get("reduced_ids") or [])
    eps = [e for e in eps if e.get("id") in ids]
elif region in ("na", "eu", "apac"):
    eps = [e for e in eps if e.get("region") == region]
# global: all
for e in eps:
    if e.get("enabled") is False:
        continue
    pr = e.get("port_range") or [5201, 5201]
    p0, p1 = int(pr[0]), int(pr[1] if len(pr) > 1 else pr[0])
    fields = [
        e.get("id", ""),
        e.get("provider", ""),
        e.get("city", ""),
        e.get("region", ""),
        e.get("host", ""),
        str(p0),
        str(p1),
        e.get("speed", ""),
        e.get("stack", "IPv4"),
    ]
    # TSV, escape tabs/newlines out of values
    print("\t".join(x.replace("\t", " ").replace("\n", " ") for x in fields))
PY
)" || return 1
    while IFS=$'\t' read -r id prov city reg host p0 p1 speed stack; do
      [[ -z "${id:-}" ]] && continue
      EP_ID+=("$id")
      EP_PROVIDER+=("$prov")
      EP_CITY+=("$city")
      EP_REGION+=("$reg")
      EP_HOST+=("$host")
      EP_P0+=("$p0")
      EP_P1+=("$p1")
      EP_SPEED+=("$speed")
      EP_STACK+=("$stack")
    done <<< "$dumped"
  elif command -v jq >/dev/null 2>&1; then
    err "python3 required to parse endpoints.json (jq-only path not implemented)."
    return 1
  else
    err "python3 is required to load endpoints.json"
    return 1
  fi

  if ((${#EP_ID[@]} == 0)); then
    err "No endpoints matched region=${REGION}"
    return 1
  fi
  return 0
}

# Region code for display: na -> NA, eu -> EU, apac -> APAC
region_label() {
  case "$1" in
    na) printf 'NA' ;;
    eu) printf 'EU' ;;
    apac) printf 'APAC' ;;
    *) printf '%s' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" ;;
  esac
}

region_title() {
  case "$1" in
    na) printf 'North America' ;;
    eu) printf 'Europe' ;;
    apac) printf 'Asia-Pacific' ;;
    *) printf '%s' "$1" ;;
  esac
}

list_endpoints() {
  printf '%b\n' "${C_HDR}NETS endpoints${NC} ${C_META}(filter=${REGION})${NC}"
  printf '%b\n' "${C_META}--------------------------------------------------------------------------------${NC}"
  local i last=""
  for ((i = 0; i < ${#EP_ID[@]}; i++)); do
    local reg="${EP_REGION[$i]}"
    if [[ "$reg" != "$last" ]]; then
      last="$reg"
      printf '\n%b[%s] %s%b\n' "${C_HDR}" "$(region_label "$reg")" "$(region_title "$reg")" "${NC}"
      printf '%b%-5s %-20s %-14s %-20s %-32s %s%b\n' \
        "${DIM}" "AREA" "ID" "PROVIDER" "CITY" "HOST" "STACK" "${NC}"
    fi
    printf '%-5s %-20s %-14s %-20s %-32s %s\n' \
      "$(region_label "$reg")" \
      "$(fit "${EP_ID[$i]}" 20)" \
      "$(fit "${EP_PROVIDER[$i]}" 14)" \
      "$(fit "${EP_CITY[$i]}" 20)" \
      "$(fit "${EP_HOST[$i]}" 32)" \
      "${EP_STACK[$i]}"
  done
  printf '\n%b%d endpoint(s)%b\n' "${C_META}" "${#EP_ID[@]}" "${NC}"
}

# Human-readable byte size
human_bytes() {
  awk -v b="${1:-0}" 'BEGIN{
    if (b < 0) b = 0
    if (b < 1024)          printf "%.0f B", b
    else if (b < 1048576)  printf "%.2f KiB", b/1024
    else if (b < 1073741824) printf "%.2f MiB", b/1048576
    else                   printf "%.2f GiB", b/1073741824
  }'
}

# ASCII-safe truncate to display width (no wide Unicode)
fit() {
  local s="$1" w="$2"
  # strip non-ASCII that can break terminal columns
  s="$(printf '%s' "$s" | tr -cd '\11\12\15\40-\176')"
  if ((${#s} > w)); then
    printf '%s' "${s:0:$((w - 3))}..."
  else
    printf '%s' "$s"
  fi
}

# Left-pad plain text then wrap color (ANSI-safe column width)
lcell() {
  local width="$1" text="$2" color="${3:-}"
  local plain
  plain="$(printf '%-*s' "$width" "$text")"
  if [[ -n "$color" ]]; then
    printf '%b%s%b' "$color" "$plain" "$NC"
  else
    printf '%s' "$plain"
  fi
}

# Right-pad (for numbers) then wrap color
rcell() {
  local width="$1" text="$2" color="${3:-}"
  local plain
  plain="$(printf '%*s' "$width" "$text")"
  if [[ -n "$color" ]]; then
    printf '%b%s%b' "$color" "$plain" "$NC"
  else
    printf '%s' "$plain"
  fi
}

# Try iperf3 once (JSON). Prints: status|speed_mbps|bytes
# status: ok | busy | fail
run_iperf_once() {
  local host="$1" port="$2" ipver="$3" reverse="$4"
  local flags=(-J)
  [[ "$ipver" == "4" ]] && flags+=(-4)
  [[ "$ipver" == "6" ]] && flags+=(-6)
  [[ "$reverse" == "1" ]] && flags+=(-R)

  local out rc
  out="$(
    timeout $((TEST_TIME + CONNECT_TIMEOUT + 8)) \
      "$IPERF_BIN" "${flags[@]}" \
      -c "$host" -p "$port" \
      -P "$PARALLEL" -t "$TEST_TIME" \
      --connect-timeout $((CONNECT_TIMEOUT * 1000)) \
      2>&1
  )" && rc=0 || rc=$?

  # Prefer structured JSON parse via python3
  local parsed
  parsed="$(
    REVERSE="$reverse" RC="$rc" python3 -c '
import json, os, re, sys
raw = sys.stdin.read()
reverse = os.environ.get("REVERSE") == "1"
rc = int(os.environ.get("RC") or "1")
low = raw.lower()
if "busy" in low and "server" in low:
    print("busy||0"); sys.exit(0)
# try JSON object (iperf3 -J)
start = raw.find("{")
if start >= 0:
    try:
        d = json.loads(raw[start:])
    except Exception:
        d = None
    if isinstance(d, dict):
        err = (d.get("error") or "")
        if err:
            el = err.lower()
            if "busy" in el:
                print("busy||0"); sys.exit(0)
            print("fail||0"); sys.exit(0)
        end = d.get("end") or {}
        # Upload (client send): sum_sent; Download (-R): sum_received
        if reverse:
            s = end.get("sum_received") or end.get("sum_sent") or {}
        else:
            s = end.get("sum_sent") or end.get("sum_received") or {}
        # streams aggregate fallback
        if not s and end.get("streams"):
            bps = bytes_ = 0
            key = "receiver" if reverse else "sender"
            for st in end["streams"]:
                part = st.get(key) or st.get("receiver") or st.get("sender") or {}
                bps += float(part.get("bits_per_second") or 0)
                bytes_ += int(part.get("bytes") or 0)
            if bps > 0:
                print("ok|%.2f|%d" % (bps / 1e6, bytes_)); sys.exit(0)
        bps = float(s.get("bits_per_second") or 0)
        bytes_ = int(s.get("bytes") or 0)
        if bps > 0:
            print("ok|%.2f|%d" % (bps / 1e6, bytes_)); sys.exit(0)
        print("busy||0" if rc == 0 else "fail||0"); sys.exit(0)
# plaintext fallback
if re.search(r"busy|server is busy", raw, re.I):
    print("busy||0"); sys.exit(0)
if re.search(r"unable to connect|connection refused|no route|failed to connect|timed out|timeout", raw, re.I):
    print("fail||0"); sys.exit(0)
line = ""
for ln in raw.splitlines():
    if re.search(r"SUM.*receiver|\[SUM\].*receiver", ln) or ln.rstrip().endswith("receiver"):
        line = ln
if not line:
    print("fail||0" if rc != 0 else "busy||0"); sys.exit(0)
parts = line.split()
# … sec <amt> <unit> <speed> <speed_unit> receiver
try:
    # find "sec" then amount unit speed speed_unit
    i = parts.index("sec")
    amt = float(parts[i+1]); unit = parts[i+2]
    spd = float(parts[i+3]); su = parts[i+4]
except Exception:
    print("fail||0"); sys.exit(0)
mult = {"bits/sec":1e-6,"bit/s":1e-6,"Kbits/sec":1e-3,"Kbit/s":1e-3,
        "Mbits/sec":1,"Mbit/s":1,"Gbits/sec":1e3,"Gbit/s":1e3}.get(su, 1)
mbps = spd * mult
bmult = {"Bytes":1,"KBytes":1024,"MBytes":1048576,"GBytes":1073741824,
         "Kbytes":1024,"Mbytes":1048576,"Gbytes":1073741824}.get(unit, 1)
bytes_ = int(amt * bmult)
if mbps <= 0:
    print("busy||0"); sys.exit(0)
print("ok|%.2f|%d" % (mbps, bytes_))
' <<<"$out"
  )" || parsed="fail||0"

  echo "${parsed}"
}

# Run direction trying ports in range until ok or exhausted.
# Prints: status|mbps|bytes  (port not exposed)
run_iperf_range() {
  local host="$1" p0="$2" p1="$3" ipver="$4" reverse="$5"
  local p st mb by st_last="fail" tries=0
  # Cap attempts so wide ranges (e.g. Fiberby 9201-9240) stay usable
  local max_tries=12
  for ((p = p0; p <= p1; p++)); do
    tries=$((tries + 1))
    IFS='|' read -r st mb by <<<"$(run_iperf_once "$host" "$p" "$ipver" "$reverse")"
    st_last="$st"
    if [[ "$st" == "ok" ]]; then
      echo "ok|${mb}|${by:-0}"
      return 0
    fi
    if [[ "$st" == "fail" && "$p0" == "$p1" ]]; then
      echo "fail||0"
      return 0
    fi
    if (( tries >= max_tries )); then
      break
    fi
  done
  if [[ "$st_last" == "busy" ]]; then
    echo "busy||0"
  else
    echo "fail||0"
  fi
}

# Speed text for table — fixed patterns so columns stay aligned
# ok values always fit in 10 ASCII chars: "9999 Mbps" / "99.99 Gbps"
format_speed_text() {
  local status="$1" mbps="$2"
  case "$status" in
    ok)
      awk -v m="${mbps:-0}" 'BEGIN{
        if (m >= 1000) printf "%.2fG", m/1000
        else if (m >= 100) printf "%.0fM", m
        else if (m >= 10)  printf "%.1fM", m
        else               printf "%.2fM", m
      }'
      ;;
    busy) printf '%s' "busy" ;;
    skip) printf '%s' "-" ;;
    *)    printf '%s' "fail" ;;
  esac
}

# Color for status cell
speed_color() {
  case "$1" in
    ok)   [[ "$2" == "up" ]] && printf '%s' "$C_UP" || printf '%s' "$C_DOWN" ;;
    busy) printf '%s' "$C_BUSY" ;;
    fail) printf '%s' "$C_FAIL" ;;
    *)    printf '%s' "$C_META" ;;
  esac
}

track_result() {
  local st="$1" bytes="$2" direction="$3"  # direction: up|down
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  case "$st" in
    ok)
      TOTAL_OK=$((TOTAL_OK + 1))
      bytes="${bytes:-0}"
      [[ -z "$bytes" || "$bytes" == "0" ]] && return 0
      if [[ "$direction" == "up" ]]; then
        TOTAL_SEND_BYTES=$((TOTAL_SEND_BYTES + bytes))
      else
        TOTAL_RECV_BYTES=$((TOTAL_RECV_BYTES + bytes))
      fi
      ;;
    busy) TOTAL_BUSY=$((TOTAL_BUSY + 1)) ;;
    fail) TOTAL_FAIL=$((TOTAL_FAIL + 1)) ;;
  esac
}

print_header() {
  # ASCII-only frame — wide Unicode box-drawing misaligns on many CJK terminals
  printf '%b\n' "${C_BAR}+--------------------------------------------------------------------------+${NC}"
  printf '%b|%b  %bNETS v%s%b — Network Endpoint Throughput Sampler%b\n' \
    "${C_BAR}" "${NC}" "${C_HDR}" "$VERSION" "${NC}" "${NC}"
  printf '%b\n' "${C_BAR}+--------------------------------------------------------------------------+${NC}"
  printf '  %bRegion%b      %s\n' "${BOLD}" "${NC}" "$REGION"
  printf '  %bDuration%b    %ss / direction · parallel %s\n' "${BOLD}" "${NC}" "$TEST_TIME" "$PARALLEL"
  printf '  %bStack%b       IPv4 %b%s%b · IPv6 %b%s%b\n' \
    "${BOLD}" "${NC}" \
    "$( $HAVE_IPV4 && printf '%s' "$C_OK" || printf '%s' "$C_FAIL" )" \
    "$( $HAVE_IPV4 && echo on || echo off )" "${NC}" \
    "$( $HAVE_IPV6 && printf '%s' "$C_OK" || printf '%s' "$C_META" )" \
    "$( $HAVE_IPV6 && echo on || echo off )" "${NC}"
  printf '  %bEndpoints%b   %d · iperf3 %s\n' "${BOLD}" "${NC}" "${#EP_ID[@]}" "$IPERF_BIN"
  printf '  %bLegend%b      %bSend=upload%b  %bRecv=download%b  %bbusy%b  %bfail%b\n' \
    "${BOLD}" "${NC}" "${C_UP}" "${NC}" "${C_DOWN}" "${NC}" "${C_BUSY}" "${NC}" "${C_FAIL}" "${NC}"
  printf '%b  Note: public shared servers — busy is normal; not bare-metal capacity.%b\n' "${DIM}" "${NC}"
  echo
}

# Column layout (ASCII widths, fixed):
#  Area(4) + 2 + Location(18) + 2 + Provider(12) + 2 + Send(10) + 2 + Recv(10) + 2 + Link(6)
run_mode_table() {
  local ipver="$1"   # 4 or 6
  local mode_label="IPv${ipver}"
  local W_REG=4 W_LOC=18 W_PROV=12 W_SPD=10 W_LINK=6

  if [[ "$ipver" == "4" ]] && ! $HAVE_IPV4; then
    warn "Skipping ${mode_label} (no IPv4 connectivity)."
    return 0
  fi
  if [[ "$ipver" == "6" ]] && ! $HAVE_IPV6; then
    warn "Skipping ${mode_label} (no IPv6 connectivity)."
    return 0
  fi
  if [[ -n "$FORCE_IP" && "$FORCE_IP" != "$ipver" ]]; then
    return 0
  fi

  printf '%b\n' "${C_BAR}-- iperf3 ${mode_label} -----------------------------------------------------------${NC}"

  local i host p0 p1 stack city prov speed_meta reg
  local do_test send_st send_mb send_by recv_st recv_mb recv_by send_s recv_s
  local last_reg=""

  print_cols() {
    printf '  %b' "${DIM}"
    lcell "$W_REG" "Area"
    printf '  '
    lcell "$W_LOC" "Location"
    printf '  '
    lcell "$W_PROV" "Provider"
    printf '  '
    rcell "$W_SPD" "Send"
    printf '  '
    rcell "$W_SPD" "Recv"
    printf '  '
    lcell "$W_LINK" "Link"
    printf '%b\n' "${NC}"
    printf '  %b' "${C_META}"
    printf '%s  %s  %s  %s  %s  %s' \
      "$(printf '%*s' "$W_REG" '' | tr ' ' '-')" \
      "$(printf '%*s' "$W_LOC" '' | tr ' ' '-')" \
      "$(printf '%*s' "$W_PROV" '' | tr ' ' '-')" \
      "$(printf '%*s' "$W_SPD" '' | tr ' ' '-')" \
      "$(printf '%*s' "$W_SPD" '' | tr ' ' '-')" \
      "$(printf '%*s' "$W_LINK" '' | tr ' ' '-')"
    printf '%b\n' "${NC}"
  }

  for ((i = 0; i < ${#EP_ID[@]}; i++)); do
    host="${EP_HOST[$i]}"
    p0="${EP_P0[$i]}"; p1="${EP_P1[$i]}"
    stack="${EP_STACK[$i]}"
    city="${EP_CITY[$i]}"
    prov="${EP_PROVIDER[$i]}"
    speed_meta="${EP_SPEED[$i]}"
    reg="${EP_REGION[$i]}"

    do_test=true
    if [[ "$ipver" == "6" && "$stack" == "IPv4" ]]; then
      do_test=false
    fi
    if [[ "$ipver" == "4" && "$stack" == "IPv6" ]]; then
      do_test=false
    fi

    if ! $do_test; then
      continue
    fi

    if [[ "$reg" != "$last_reg" ]]; then
      last_reg="$reg"
      printf '\n  %b[%s] %s%b\n' "${C_HDR}" "$(region_label "$reg")" "$(region_title "$reg")" "${NC}"
      print_cols
    fi

    send_st="skip"; send_mb=""; send_by=0
    recv_st="skip"; recv_mb=""; recv_by=0

    if ! $SKIP_SEND; then
      IFS='|' read -r send_st send_mb send_by <<<"$(run_iperf_range "$host" "$p0" "$p1" "$ipver" 0)"
      track_result "$send_st" "${send_by:-0}" "up"
    fi
    if ! $SKIP_RECV; then
      IFS='|' read -r recv_st recv_mb recv_by <<<"$(run_iperf_range "$host" "$p0" "$p1" "$ipver" 1)"
      track_result "$recv_st" "${recv_by:-0}" "down"
    fi

    send_s="$(format_speed_text "$send_st" "$send_mb")"
    recv_s="$(format_speed_text "$recv_st" "$recv_mb")"

    printf '  '
    lcell "$W_REG" "$(region_label "$reg")" "$C_HDR"
    printf '  '
    lcell "$W_LOC" "$(fit "$city" "$W_LOC")" "$C_LOC"
    printf '  '
    lcell "$W_PROV" "$(fit "$prov" "$W_PROV")" "$C_PROV"
    printf '  '
    rcell "$W_SPD" "$send_s" "$(speed_color "$send_st" up)"
    printf '  '
    rcell "$W_SPD" "$recv_s" "$(speed_color "$recv_st" down)"
    printf '  '
    lcell "$W_LINK" "$(fit "$speed_meta" "$W_LINK")" "$C_META"
    printf '\n'
  done
  echo
}

print_summary() {
  local elapsed="$1"
  local total_bytes=$((TOTAL_SEND_BYTES + TOTAL_RECV_BYTES))
  local up_h down_h tot_h
  up_h="$(human_bytes "$TOTAL_SEND_BYTES")"
  down_h="$(human_bytes "$TOTAL_RECV_BYTES")"
  tot_h="$(human_bytes "$total_bytes")"

  printf '%b\n' "${C_BAR}-- Summary ----------------------------------------------------------------${NC}"
  printf '  %bElapsed%b     %ss\n' "${BOLD}" "${NC}" "$elapsed"
  printf '  %bTests%b       %b%d ok%b  %b%d busy%b  %b%d fail%b  %d total\n' \
    "${BOLD}" "${NC}" \
    "${C_OK}" "$TOTAL_OK" "${NC}" \
    "${C_BUSY}" "$TOTAL_BUSY" "${NC}" \
    "${C_FAIL}" "$TOTAL_FAIL" "${NC}" \
    "$TOTAL_TESTS"
  printf '  %bTraffic%b     %bSend(up)  %s%b\n' "${BOLD}" "${NC}" "${C_UP}" "$up_h" "${NC}"
  printf '               %bRecv(down) %s%b\n' "${C_DOWN}" "$down_h" "${NC}"
  printf '               total      %s\n' "$tot_h"
  printf '  %b             (this run only — iperf3 payload)%b\n' "${DIM}" "${NC}"
  printf '%b\n' "${C_BAR}--------------------------------------------------------------------------${NC}"
  ok "Done · NETS v${VERSION}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--reduced) REGION="reduced"; shift ;;
      --region) REGION="${2:-}"; shift 2 ;;
      --region=*) REGION="${1#*=}"; shift ;;
      -4) FORCE_IP="4"; shift ;;
      -6) FORCE_IP="6"; shift ;;
      -t|--time) TEST_TIME="${2:-10}"; shift 2 ;;
      --time=*) TEST_TIME="${1#*=}"; shift ;;
      -P|--parallel) PARALLEL="${2:-4}"; shift 2 ;;
      --parallel=*) PARALLEL="${1#*=}"; shift ;;
      --send-only) SKIP_RECV=true; shift ;;
      --recv-only) SKIP_SEND=true; shift ;;
      -l|--list) LIST_ONLY=true; shift ;;
      -h|--help) usage; exit 0 ;;
      -v|--version) echo "NETS v${VERSION}"; exit 0 ;;
      *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
  case "$REGION" in
    global|na|eu|apac|reduced) ;;
    *) err "Invalid region: $REGION"; exit 1 ;;
  esac
}

main() {
  parse_args "$@"
  detect_iperf || exit 1
  load_endpoints || exit 1

  if $LIST_ONLY; then
    list_endpoints
    exit 0
  fi

  detect_connectivity
  print_header

  local start end
  start="$(date +%s)"

  if [[ -z "$FORCE_IP" || "$FORCE_IP" == "4" ]]; then
    run_mode_table 4
  fi
  if [[ -z "$FORCE_IP" || "$FORCE_IP" == "6" ]]; then
    run_mode_table 6
  fi

  end="$(date +%s)"
  print_summary "$((end - start))"
}

main "$@"
