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
#   ./nets.sh -r --json > nets.json
#
# Only dependency: iperf3 (bash + awk + coreutils otherwise).
# Endpoint list: endpoints.json (same directory) or embedded fallback.
#
set -uo pipefail

VERSION="0.4.0"
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
  "version": 7,
  "updated": "2026-07-24",
  "notes": [
    "Public shared iperf3 endpoints — results may show busy and do not equal raw DC capacity.",
    "port_range is inclusive. Script tries ports on busy/fail (ports not shown; max tries capped).",
    "stack is planning metadata; runtime still probes IPv4/IPv6.",
    "v6: drop failing DataPacket TYO/SIN/FRA; +Leaseweb TYO/SIN/FRA, Wobcom FRA, Cosmonova Kyiv; Gigahost IPv4-only (no AAAA).",
    "v7: drop InterServer LAX (lax.speedtest.is.cc) — consistently fail in practice."
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
      "id": "cosmonova-iev",
      "provider": "Cosmonova",
      "city": "Kyiv, UA",
      "region": "eu",
      "host": "speed.cosmonova.net",
      "port_range": [
        5201,
        5209
      ],
      "speed": "40G",
      "stack": "IPv4",
      "source": "cosmonova.net"
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
      "stack": "IPv4",
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
      "id": "leaseweb-fra",
      "provider": "Leaseweb",
      "city": "Frankfurt, DE",
      "region": "eu",
      "host": "speedtest.fra1.de.leaseweb.net",
      "port_range": [
        5201,
        5210
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "leaseweb"
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
      "id": "wobcom-fra",
      "provider": "Wobcom",
      "city": "Frankfurt, DE",
      "region": "eu",
      "host": "a205.speedtest.wobcom.de",
      "port_range": [
        5201,
        5201
      ],
      "speed": "25G",
      "stack": "IPv4|IPv6",
      "source": "wobcom.de"
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
      "id": "leaseweb-sin",
      "provider": "Leaseweb",
      "city": "Singapore, SG",
      "region": "apac",
      "host": "speedtest.sin1.sg.leaseweb.net",
      "port_range": [
        5201,
        5210
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "leaseweb"
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
      "id": "leaseweb-tyo",
      "provider": "Leaseweb",
      "city": "Tokyo, JP",
      "region": "apac",
      "host": "speedtest.tyo11.jp.leaseweb.net",
      "port_range": [
        5201,
        5210
      ],
      "speed": "10G",
      "stack": "IPv4|IPv6",
      "source": "leaseweb"
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
    "wobcom-fra",
    "leaseweb-tyo",
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
AUTO_YES=false           # -y : install missing deps without prompting
NO_INSTALL=false         # --no-install : never install
JSON_MODE=false          # -j : JSON on stdout, human output on stderr
NO_CLEAR=false
NO_COLOR_FLAG=false
CONNECT_TIMEOUT=5
MAX_PORT_TRIES=12        # cap so wide ranges (Fiberby 9201-9240) stay usable
IPERF_BIN=""
IPERF_HAS_CT=false       # iperf3 >= 3.6 knows --connect-timeout
TIMEOUT_BIN=""
STATUS_FILE=""
TICKER_PID=""
RUN_START=0
RUN_STARTED=false
INTERRUPTED=false

HAVE_IPV4=false
HAVE_IPV6=false

# Traffic totals for this run (bytes on the wire, approx. from iperf3)
TOTAL_SEND_BYTES=0   # upload: client -> server
TOTAL_RECV_BYTES=0   # download: server -> client
TOTAL_OK=0
TOTAL_BUSY=0
TOTAL_FAIL=0
TOTAL_TESTS=0

# Result rows for --json (parallel arrays)
J_IPV=(); J_ID=(); J_SEND_ST=(); J_SEND_MB=(); J_RECV_ST=(); J_RECV_MB=()

RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; DIM=""; NC=""
C_UP=""; C_DOWN=""; C_OK=""; C_BUSY=""; C_FAIL=""; C_META=""
C_LOC=""; C_PROV=""; C_HDR=""; C_BAR=""

# Colors only when the (human) output is a terminal.
setup_colors() {
  [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]] || return 0
  $NO_COLOR_FLAG && return 0
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
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
}

usage() {
  cat <<EOF
NETS v${VERSION} — Network Endpoint Throughput Sampler

Usage: nets.sh [options]

Options:
  -r, --reduced         Short list (8 endpoints)
  --region <name>       global | na | eu | apac | reduced  (default: global)
  -4                    IPv4 only
  -6                    IPv6 only
  -t, --time <sec>      iperf3 test duration per direction (default: ${TEST_TIME})
  -P, --parallel <n>    parallel streams (default: ${PARALLEL})
  --send-only           Upload only (client -> server)
  --recv-only           Download only (server -> client, iperf -R)
  -j, --json            JSON results on stdout (progress goes to stderr)
  -y, --yes             Auto-install iperf3 without prompting
  --no-install          Never install; exit if iperf3 is missing
  --no-clear            Do not clear the screen
  --no-color            Disable colors (NO_COLOR is honoured too)
  -l, --list            List endpoints and exit
  -h, --help            Show help
  -v, --version         Show version

Examples:
  nets.sh
  nets.sh -r -t 8
  nets.sh --region apac -4
  curl -sL https://ba.sh/nets | bash -s -- -y -r
  curl -sL https://ba.sh/nets | bash -s -- -r --json > nets.json
EOF
}

# The live status line owns the current row; wipe it before printing.
clear_line() {
  if [[ -n "${TICKER_PID:-}" && -t 1 ]]; then printf '\r\033[K'; fi
  return 0
}
log()  { clear_line; printf '%s\n' "$*"; }
info() { clear_line; printf '%s\n' "${CYAN}$*${NC}"; }
ok()   { clear_line; printf '%s\n' "${GREEN}$*${NC}"; }
warn() { clear_line; printf '%s\n' "${YELLOW}$*${NC}"; }
err()  { clear_line; printf '%s\n' "${RED}$*${NC}" >&2; }

fmt_dur() { # sets DUR: 129 -> 2m09s
  local s="${1:-0}"
  if ((s >= 60)); then printf -v DUR '%dm%02ds' "$((s / 60))" "$((s % 60))"
  else printf -v DUR '%ds' "$s"; fi
}

# /dev/tty may exist but fail to open (ssh without -t, cron, CI, containers).
have_tty() { (exec </dev/tty) 2>/dev/null; }

# Y/N from the real terminal (works under curl | bash). No TTY → "no".
ask_yn() {
  local prompt="$1" reply=""
  have_tty || return 1
  printf '%s' "$prompt" >/dev/tty
  IFS= read -r reply </dev/tty || true
  case "$reply" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

detect_pkg_manager() {
  local pm
  for pm in apt-get dnf yum pacman zypper apk; do
    if command -v "$pm" >/dev/null 2>&1; then
      [[ "$pm" == apt-get ]] && pm=apt
      echo "$pm"; return
    fi
  done
  echo "unknown"
}

# Ensure iperf3 exists; offer a Y/N install if missing.
ensure_deps() {
  local pm
  if command -v iperf3 >/dev/null 2>&1; then
    IPERF_BIN="$(command -v iperf3)"
    return 0
  fi

  warn "Missing required tool: iperf3"
  if $NO_INSTALL; then
    err "--no-install set: cannot continue without iperf3."
    return 1
  fi

  pm="$(detect_pkg_manager)"
  local -a sudo_prefix=()
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_prefix=(sudo)
    else
      err "No root/sudo. Install iperf3 manually, then re-run:"
      case "$pm" in
        apt)    err "  apt-get update && apt-get install -y iperf3" ;;
        dnf)    err "  dnf install -y iperf3" ;;
        yum)    err "  yum install -y iperf3" ;;
        pacman) err "  pacman -S --needed iperf3" ;;
        zypper) err "  zypper install -y iperf3" ;;
        apk)    err "  apk add iperf3" ;;
        *)      err "  install the iperf3 package" ;;
      esac
      return 1
    fi
  fi

  if [[ "$pm" == "unknown" ]]; then
    err "Unknown package manager. Install iperf3 manually."
    return 1
  fi

  if ! $AUTO_YES; then
    if ! have_tty; then
      err "iperf3 is missing and there is no terminal to ask. Re-run with -y to install it."
      return 1
    fi
    if ! ask_yn "Install iperf3 now via ${pm}? [y/N]: "; then
      err "Skipped install. Install iperf3 and re-run (or pass -y)."
      return 1
    fi
  fi

  # Non-interactive installs: Debian's iperf3 asks (debconf) whether to
  # start a daemon; `env` survives sudo's env_reset.
  local -a install_cmd=()
  case "$pm" in
    apt)
      info "Running apt-get update..."
      "${sudo_prefix[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update -qq </dev/null >/dev/null 2>&1 || true
      install_cmd=("${sudo_prefix[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends)
      ;;
    dnf)    install_cmd=("${sudo_prefix[@]}" dnf install -y -q) ;;
    yum)    install_cmd=("${sudo_prefix[@]}" yum install -y -q) ;;
    pacman) install_cmd=("${sudo_prefix[@]}" pacman -S --noconfirm --needed) ;;
    zypper) install_cmd=("${sudo_prefix[@]}" zypper --non-interactive install) ;;
    apk)    install_cmd=("${sudo_prefix[@]}" apk add --no-cache) ;;
  esac

  info "Installing iperf3..."
  if ! "${install_cmd[@]}" iperf3 </dev/null; then
    err "Package install failed. Install iperf3 manually."
    return 1
  fi
  if ! command -v iperf3 >/dev/null 2>&1; then
    err "iperf3 still not found after install."
    return 1
  fi
  IPERF_BIN="$(command -v iperf3)"
  ok "Installed $("$IPERF_BIN" --version 2>/dev/null | head -n 1)"
  return 0
}

# Feature probes, once per run.
probe_tools() {
  if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN="$(command -v timeout)"; fi
  if "$IPERF_BIN" --help 2>&1 | grep -q -- '--connect-timeout'; then IPERF_HAS_CT=true; fi
}

# TCP connect test with bash's /dev/tcp (no curl/nc needed). host port secs
tcp_probe() {
  [[ -n "$TIMEOUT_BIN" ]] || return 1
  "$TIMEOUT_BIN" "$3" bash -c 'exec 3<>"/dev/tcp/$0/$1"' "$1" "$2" 2>/dev/null
}

# A global IPv6 route/address must exist; DNS answering AAAA proves nothing.
has_v6_route() {
  if command -v ip >/dev/null 2>&1; then
    ip -6 route get 2606:4700:4700::1111 >/dev/null 2>&1
    return
  fi
  # /proc/net/if_inet6: addr idx plen scope flags dev — scope 00 = global
  [[ -r /proc/net/if_inet6 ]] && awk '$4 == "00" { f = 1 } END { exit !f }' /proc/net/if_inet6
}

detect_connectivity() {
  HAVE_IPV4=false
  HAVE_IPV6=false
  local p4="" p6=""
  # Probe both families in parallel (≤ 3 s each). 223.5.5.5 / 2400:3200::1
  # cover networks where Cloudflare/Google resolvers are filtered.
  if [[ "$FORCE_IP" != "6" ]]; then
    ( tcp_probe 1.1.1.1 443 3 || tcp_probe 8.8.8.8 53 3 || tcp_probe 223.5.5.5 53 3 \
      || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 ) &
    p4=$!
  fi
  if [[ "$FORCE_IP" != "4" ]]; then
    ( has_v6_route && { tcp_probe 2606:4700:4700::1111 443 3 || tcp_probe 2001:4860:4860::8888 53 3 \
        || tcp_probe 2400:3200::1 53 3 || ping -6 -c1 -W2 2606:4700:4700::1111 >/dev/null 2>&1; } ) &
    p6=$!
  fi
  if [[ -n "$p4" ]] && wait "$p4"; then HAVE_IPV4=true; fi
  if [[ -n "$p6" ]] && wait "$p6"; then HAVE_IPV6=true; fi

  # Probes can be filtered while iperf3 still works — fall back to IPv4.
  if ! $HAVE_IPV4 && ! $HAVE_IPV6 && [[ "$FORCE_IP" != "6" ]]; then
    HAVE_IPV4=true
    warn "Could not confirm IPv4/IPv6 connectivity; trying IPv4 anyway."
  fi
  if [[ "$FORCE_IP" == "6" ]] && ! $HAVE_IPV6; then
    warn "No IPv6 route detected; trying IPv6 anyway (-6)."
    HAVE_IPV6=true
  fi
}

# Does host have an address of this family? (skips hosts without AAAA fast)
host_has_family() {
  local host="$1" ipver="$2"
  command -v getent >/dev/null 2>&1 || return 0
  if [[ "$ipver" == 6 ]]; then
    [[ "$host" == *:* ]] && return 0
    getent ahostsv6 "$host" 2>/dev/null | grep -q ':'
  else
    getent ahostsv4 "$host" >/dev/null 2>&1
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
  ENDPOINTS_TMP="$(mktemp "${TMPDIR:-/tmp}/nets-endpoints.XXXXXX")" || return 1
  # 3) embedded catalog — always matches this script version (curl|bash)
  if declare -F write_embedded_endpoints >/dev/null 2>&1; then
    write_embedded_endpoints "$ENDPOINTS_TMP"
    if [[ -s "$ENDPOINTS_TMP" ]]; then
      ENDPOINTS_JSON="$ENDPOINTS_TMP"
      return 0
    fi
  fi
  # 4) download from public hosts (override / fallback)
  local url
  for url in "${ENDPOINTS_URLS[@]}"; do
    [[ -z "$url" ]] && continue
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL --connect-timeout 8 --max-time 30 "$url" -o "$ENDPOINTS_TMP" </dev/null 2>/dev/null \
        && [[ -s "$ENDPOINTS_TMP" ]]; then
        ENDPOINTS_JSON="$ENDPOINTS_TMP"
        info "Loaded endpoints from ${url}"
        return 0
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -T 30 -O "$ENDPOINTS_TMP" "$url" </dev/null 2>/dev/null \
        && [[ -s "$ENDPOINTS_TMP" ]]; then
        ENDPOINTS_JSON="$ENDPOINTS_TMP"
        info "Loaded endpoints from ${url}"
        return 0
      fi
    fi
  done
  err "Could not load endpoints.json (local, embedded, or remote)."
  return 1
}

cleanup() {
  ticker_stop
  [[ -n "${ENDPOINTS_TMP:-}" && -f "$ENDPOINTS_TMP" ]] && rm -f "$ENDPOINTS_TMP"
  [[ -n "${STATUS_FILE:-}" && -f "$STATUS_FILE" ]] && rm -f "$STATUS_FILE"
  return 0
}

# Ctrl-C / TERM: stop, show what was measured so far.
on_interrupt() {
  local code="${1:-130}"
  trap - INT TERM
  INTERRUPTED=true
  ticker_stop
  printf '\n'
  warn "Interrupted — partial results:"
  if $RUN_STARTED; then
    print_summary $((SECONDS - RUN_START))
    $JSON_MODE && emit_json
  fi
  exit "$code"
}

# endpoints.json → TSV rows (id provider city region host p0 p1 speed stack),
# filtered by region. Pure awk JSON tokenizer: any formatting, no python/jq.
endpoints_tsv() {
  awk -v want="$2" '
    function unq(t) {
      if (substr(t, 1, 1) != "\"") return t
      t = substr(t, 2, length(t) - 2)
      gsub(/\\"/, "\"", t); gsub(/\\\//, "/", t); gsub(/\\[tnr]/, " ", t)
      return t
    }
    function clean(v) { gsub(/[\t\n]/, " ", v); return v }
    BEGIN { RS = "\001" }
    {
      s = $0; d = 0; n = 0
      while (match(s, /"([^"\\]|\\.)*"|-?[0-9][0-9.eE+-]*|true|false|null|[][{}:,]/)) {
        t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        if (t == "{" || t == "[") {
          d++; ty[d] = t; expk[d] = (t == "{"); arr[d] = ""
          if (t == "{" && d == 3 && key[1] == "endpoints") { delete rec }
          continue
        }
        if (t == "}") {
          if (d == 3 && key[1] == "endpoints") {
            n++
            split(rec["port_range"], pr, ",")
            p0 = (pr[1] != "") ? pr[1] : 5201; p1 = (pr[2] != "") ? pr[2] : p0
            E_ID[n] = rec["id"]; E_REG[n] = rec["region"]; E_EN[n] = rec["enabled"]
            E_ROW[n] = clean(rec["id"]) "\t" clean(rec["provider"]) "\t" clean(rec["city"]) "\t" \
                       clean(rec["region"]) "\t" clean(rec["host"]) "\t" p0 "\t" p1 "\t" \
                       clean(rec["speed"]) "\t" ((rec["stack"] != "") ? clean(rec["stack"]) : "IPv4")
          }
          d--; continue
        }
        if (t == "]") {
          if (d == 4 && key[1] == "endpoints") rec[key[3]] = arr[4]
          d--; continue
        }
        if (t == ":") { expk[d] = 0; continue }
        if (t == ",") { if (ty[d] == "{") expk[d] = 1; continue }
        if (ty[d] == "{" && expk[d]) { key[d] = unq(t); continue }
        v = unq(t)
        if (d == 3 && key[1] == "endpoints") rec[key[3]] = v
        else if (d == 4 && key[1] == "endpoints") arr[4] = (arr[4] == "") ? v : arr[4] "," v
        else if (d == 2 && key[1] == "reduced_ids") RED[v] = 1
      }
    }
    END {
      for (i = 1; i <= n; i++) {
        if (E_EN[i] == "false" || E_ID[i] == "") continue
        if (want == "reduced" && !(E_ID[i] in RED)) continue
        if ((want == "na" || want == "eu" || want == "apac") && E_REG[i] != want) continue
        print E_ROW[i]
      }
    }
  ' "$1"
}

# Arrays: EP_ID EP_PROVIDER EP_CITY EP_REGION EP_HOST EP_P0 EP_P1 EP_SPEED EP_STACK
load_endpoints() {
  EP_ID=(); EP_PROVIDER=(); EP_CITY=(); EP_REGION=()
  EP_HOST=(); EP_P0=(); EP_P1=(); EP_SPEED=(); EP_STACK=()
  local id prov city reg host p0 p1 speed stack

  resolve_endpoints_json || return 1
  while IFS=$'\t' read -r id prov city reg host p0 p1 speed stack; do
    [[ -z "${id:-}" || -z "${host:-}" ]] && continue
    [[ "$p0" =~ ^[0-9]+$ && "$p1" =~ ^[0-9]+$ ]] || { p0=5201; p1=5201; }
    ((p1 < p0)) && p1=$p0
    EP_ID+=("$id"); EP_PROVIDER+=("$prov"); EP_CITY+=("$city"); EP_REGION+=("$reg")
    EP_HOST+=("$host"); EP_P0+=("$p0"); EP_P1+=("$p1"); EP_SPEED+=("$speed"); EP_STACK+=("$stack")
  done < <(endpoints_tsv "$ENDPOINTS_JSON" "$REGION")

  if ((${#EP_ID[@]} == 0)); then
    err "No endpoints matched region=${REGION} (catalog: ${ENDPOINTS_JSON})"
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
    *) printf '%s' "${1^^}" ;;
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
  printf '%s\n' "${C_HDR}NETS endpoints${NC} ${C_META}(filter=${REGION})${NC}"
  printf '%s\n' "${C_META}--------------------------------------------------------------------------------${NC}"
  local i last=""
  for ((i = 0; i < ${#EP_ID[@]}; i++)); do
    local reg="${EP_REGION[$i]}"
    if [[ "$reg" != "$last" ]]; then
      last="$reg"
      printf '\n%s[%s] %s%s\n' "${C_HDR}" "$(region_label "$reg")" "$(region_title "$reg")" "${NC}"
      printf '%s%-5s %-20s %-14s %-20s %-32s %s%s\n' \
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
  printf '\n%s%d endpoint(s)%s\n' "${C_META}" "${#EP_ID[@]}" "${NC}"
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
  s="$(printf '%s' "$s" | LC_ALL=C tr -cd '\11\12\15\40-\176')"
  if ((${#s} > w)); then
    printf '%s' "${s:0:$((w - 3))}..."
  else
    printf '%s' "$s"
  fi
}

# Left-pad plain text then wrap color (ANSI-safe column width)
lcell() {
  local width="$1" text="$2" color="${3:-}"
  if [[ -n "$color" ]]; then printf '%s%-*s%s' "$color" "$width" "$text" "$NC"
  else printf '%-*s' "$width" "$text"; fi
}

# Right-pad (for numbers) then wrap color
rcell() {
  local width="$1" text="$2" color="${3:-}"
  if [[ -n "$color" ]]; then printf '%s%*s%s' "$color" "$width" "$text" "$NC"
  else printf '%*s' "$width" "$text"; fi
}

# ---------- live status line ----------
status_set() {
  [[ -n "${STATUS_FILE:-}" ]] || return 0
  printf '%s\n' "$*" >"$STATUS_FILE" 2>/dev/null || true
}

# "  [/] Los Angeles · Clouvider   send :5203 · 7s" — redrawn in place.
ticker_start() {
  [[ -t 1 && -n "$STATUS_FILE" ]] || return 0
  local label="$1"
  : >"$STATUS_FILE"
  (
    trap 'exit 0' TERM
    local f='|/-\' i=0 t0=$SECONDS d="" line=""
    while :; do
      if [[ -r "$STATUS_FILE" ]] && IFS= read -r line <"$STATUS_FILE" && [[ -n "$line" ]]; then d="$line"; fi
      printf '\r  %s[%s]%s %s  %s%s · %ds%s\033[K' \
        "$C_META" "${f:i % 4:1}" "$NC" "$label" "$DIM" "$d" $((SECONDS - t0)) "$NC"
      i=$((i + 1))
      sleep 0.2
    done
  ) &
  TICKER_PID=$!
}

ticker_stop() {
  if [[ -n "${TICKER_PID:-}" ]]; then
    kill "$TICKER_PID" 2>/dev/null
    wait "$TICKER_PID" 2>/dev/null
    TICKER_PID=""
    [[ -t 1 ]] && printf '\r\033[K'
  fi
  return 0
}

# ---------- iperf3 ----------
# iperf3 -J output (cJSON, one key per line) → "status|mbps|bytes".
# status: ok | busy | refused | timeout | dns | noaf | fail
# Throughput is the receiver-side total in both directions (what arrived),
# with the sender total as fallback.
parse_iperf() {
  awk -v rc="$1" '
    /"error":/ { e = $0; sub(/^[^:]*:[ \t]*"/, "", e); sub(/"[ \t]*,?[ \t]*$/, "", e); err = e }
    /^iperf3: / { err = $0 }
    /"sum_sent":[ \t]*\{/     { blk = "s"; next }
    /"sum_received":[ \t]*\{/ { blk = "r"; next }
    blk != "" && /"bytes":/ { v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]*,?[ \t]*$/, "", v); by[blk] = v + 0 }
    blk != "" && /"bits_per_second":/ { v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]*,?[ \t]*$/, "", v); bps[blk] = v + 0 }
    blk != "" && /^[ \t]*\},?[ \t]*$/ { blk = "" }
    END {
      if (bps["r"] > 0) { printf "ok|%.2f|%.0f\n", bps["r"] / 1e6, by["r"]; exit }
      if (bps["s"] > 0) { printf "ok|%.2f|%.0f\n", bps["s"] / 1e6, by["s"]; exit }
      e = tolower(err)
      if (e ~ /busy/)                                          print "busy||0"
      else if (e ~ /refused/)                                  print "refused||0"
      else if (e ~ /name or service|not known|resolve|nodename|name resolution/) print "dns||0"
      else if (e ~ /address family|network is unreachable/)    print "noaf||0"
      else if (e ~ /unrecognized|invalid option|usage:/)     print "fail||0"
      else if (e ~ /timed out|timeout|no route|unreachable/ || rc == 124) print "timeout||0"
      else                                                     print "fail||0"
    }
  '
}

# One attempt. Sets IP_ST IP_MB IP_BY.
run_iperf_once() {
  local host="$1" port="$2" ipver="$3" reverse="$4" out rc
  local -a cmd=("$IPERF_BIN" -J -c "$host" -p "$port" -P "$PARALLEL" -t "$TEST_TIME")
  [[ "$ipver" == "4" ]] && cmd+=(-4)
  [[ "$ipver" == "6" ]] && cmd+=(-6)
  [[ "$reverse" == "1" ]] && cmd+=(-R)
  $IPERF_HAS_CT && cmd+=(--connect-timeout $((CONNECT_TIMEOUT * 1000)))
  # Hard wall-clock cap: a stalled server must not hang the whole run.
  [[ -n "$TIMEOUT_BIN" ]] && cmd=("$TIMEOUT_BIN" $((TEST_TIME + CONNECT_TIMEOUT + 8)) "${cmd[@]}")
  out="$("${cmd[@]}" </dev/null 2>&1)"
  rc=$?
  IFS='|' read -r IP_ST IP_MB IP_BY < <(printf '%s\n' "$out" | parse_iperf "$rc")
  IP_ST="${IP_ST:-fail}"
}

# Try ports in the range until one works. Sets RG_ST RG_MB RG_BY RG_PORT RG_WHY.
# - starts at a random port (spreads load across users) or a known-good one
# - busy → next port; refused ×4 / timeout ×2 / DNS / no-route → give up early
run_iperf_range() {
  local host="$1" p0="$2" p1="$3" ipver="$4" reverse="$5" prefer="${6:-}"
  local span=$((p1 - p0 + 1)) start k p tries=0 refused=0 timeouts=0 busy=0 dir="send" note
  [[ "$reverse" == "1" ]] && dir="recv"
  ((span < 1)) && span=1
  if [[ -n "$prefer" ]] && ((prefer >= p0 && prefer <= p1)); then start=$((prefer - p0))
  else start=$((RANDOM % span)); fi
  RG_ST="fail"; RG_MB=""; RG_BY=0; RG_PORT=""; RG_WHY=""

  for ((k = 0; k < span && tries < MAX_PORT_TRIES; k++)); do
    p=$((p0 + (start + k) % span))
    tries=$((tries + 1))
    note="${dir} :${p}"
    ((tries > 1)) && note+=" · try ${tries}"
    ((busy)) && note+=" (busy)"
    status_set "$note"
    run_iperf_once "$host" "$p" "$ipver" "$reverse"
    RG_WHY="$IP_ST"
    case "$IP_ST" in
      ok) RG_ST="ok"; RG_MB="$IP_MB"; RG_BY="${IP_BY:-0}"; RG_PORT="$p"; return 0 ;;
      busy) busy=1 ;;
      refused) refused=$((refused + 1)); ((refused >= 4)) && break ;;
      timeout) timeouts=$((timeouts + 1)); ((timeouts >= 2)) && break ;;
      dns|noaf) break ;;
    esac
  done
  ((busy)) && RG_ST="busy"
  return 0
}

# Speed text with full units (Mbps / Gbps). Max length fits W_SPD=12.
format_speed_text() {
  local status="$1" mbps="$2"
  case "$status" in
    ok)
      awk -v m="${mbps:-0}" 'BEGIN{
        if (m >= 1000) printf "%.2f Gbps", m/1000
        else           printf "%.0f Mbps", m
      }'
      ;;
    busy) printf '%s' "busy" ;;
    skip) printf '%s' "-" ;;
    nov6) printf '%s' "no IPv6" ;;
    *)    printf '%s' "fail" ;;
  esac
}

speed_color() {
  case "$1" in
    ok)   if [[ "$2" == "up" ]]; then printf '%s' "$C_UP"; else printf '%s' "$C_DOWN"; fi ;;
    busy) printf '%s' "$C_BUSY" ;;
    fail) printf '%s' "$C_FAIL" ;;
    *)    printf '%s' "$C_META" ;;
  esac
}

track_result() {
  local st="$1" bytes="${2:-0}" direction="$3"  # direction: up|down
  [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
  case "$st" in
    ok)
      TOTAL_TESTS=$((TOTAL_TESTS + 1)); TOTAL_OK=$((TOTAL_OK + 1))
      if [[ "$direction" == "up" ]]; then TOTAL_SEND_BYTES=$((TOTAL_SEND_BYTES + bytes))
      else TOTAL_RECV_BYTES=$((TOTAL_RECV_BYTES + bytes)); fi
      ;;
    busy) TOTAL_TESTS=$((TOTAL_TESTS + 1)); TOTAL_BUSY=$((TOTAL_BUSY + 1)) ;;
    fail) TOTAL_TESTS=$((TOTAL_TESTS + 1)); TOTAL_FAIL=$((TOTAL_FAIL + 1)) ;;
  esac
}

print_header() {
  local v4c v4s v6c v6s mode=""
  if $HAVE_IPV4; then v4c="$C_OK"; v4s=on; else v4c="$C_FAIL"; v4s=off; fi
  if $HAVE_IPV6; then v6c="$C_OK"; v6s=on; else v6c="$C_META"; v6s=off; fi
  $SKIP_RECV && mode=" · send only"
  $SKIP_SEND && mode=" · recv only"
  # ASCII-only frame — wide Unicode box-drawing misaligns on many CJK terminals
  printf '%s\n' "${C_BAR}+--------------------------------------------------------------------------+${NC}"
  printf '%s|%s  %sNETS v%s%s — Network Endpoint Throughput Sampler\n' \
    "${C_BAR}" "${NC}" "${C_HDR}" "$VERSION" "${NC}"
  printf '%s\n' "${C_BAR}+--------------------------------------------------------------------------+${NC}"
  printf '  %sRegion%s      %s\n' "${BOLD}" "${NC}" "$REGION"
  printf '  %sDuration%s    %ss / direction · parallel %s%s\n' "${BOLD}" "${NC}" "$TEST_TIME" "$PARALLEL" "$mode"
  printf '  %sStack%s       IPv4 %s%s%s · IPv6 %s%s%s\n' \
    "${BOLD}" "${NC}" "$v4c" "$v4s" "${NC}" "$v6c" "$v6s" "${NC}"
  printf '  %sEndpoints%s   %d · %s\n' "${BOLD}" "${NC}" "${#EP_ID[@]}" "$("$IPERF_BIN" --version 2>/dev/null | head -n 1 | awk '{print $1, $2}')"
  printf '  %sLegend%s      %sSend=upload%s  %sRecv=download%s  %sbusy%s  %sfail%s\n' \
    "${BOLD}" "${NC}" "${C_UP}" "${NC}" "${C_DOWN}" "${NC}" "${C_BUSY}" "${NC}" "${C_FAIL}" "${NC}"
  printf '%s  Note: public shared servers — busy is normal; not bare-metal capacity.%s\n' "${DIM}" "${NC}"
  echo
}

# Column layout (ASCII widths, fixed):
#  Area(4) + 2 + Location(18) + 2 + Provider(14) + 2 + Send(12) + 2 + Recv(12) + 2 + Link(6)
W_REG=4; W_LOC=18; W_PROV=14; W_SPD=12; W_LINK=6

print_cols() {
  printf '  %s' "${DIM}"
  lcell "$W_REG" "Area"; printf '  '
  lcell "$W_LOC" "Location"; printf '  '
  lcell "$W_PROV" "Provider"; printf '  '
  rcell "$W_SPD" "Send"; printf '  '
  rcell "$W_SPD" "Recv"; printf '  '
  lcell "$W_LINK" "Link"
  printf '%s\n' "${NC}"
  local dash
  printf -v dash '%*s' 80 ''; dash="${dash// /-}"
  printf '  %s%s  %s  %s  %s  %s  %s%s\n' "${C_META}" \
    "${dash:0:W_REG}" "${dash:0:W_LOC}" "${dash:0:W_PROV}" "${dash:0:W_SPD}" "${dash:0:W_SPD}" "${dash:0:W_LINK}" "${NC}"
}

run_mode_table() {
  local ipver="$1"   # 4 or 6
  local mode_label="IPv${ipver}"

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

  printf '%s\n' "${C_BAR}-- iperf3 ${mode_label} -----------------------------------------------------------${NC}"

  local i host p0 p1 stack city prov speed_meta reg
  local send_st send_mb send_by recv_st recv_mb recv_by send_s recv_s good_port
  local last_reg="" fam_ok

  for ((i = 0; i < ${#EP_ID[@]}; i++)); do
    host="${EP_HOST[$i]}"
    p0="${EP_P0[$i]}"; p1="${EP_P1[$i]}"
    stack="${EP_STACK[$i]}"
    city="${EP_CITY[$i]}"
    prov="${EP_PROVIDER[$i]}"
    speed_meta="${EP_SPEED[$i]}"
    reg="${EP_REGION[$i]}"

    # Catalog metadata first (cheap), then DNS for the family.
    [[ "$ipver" == "6" && "$stack" == "IPv4" ]] && continue
    [[ "$ipver" == "4" && "$stack" == "IPv6" ]] && continue

    if [[ "$reg" != "$last_reg" ]]; then
      last_reg="$reg"
      printf '\n  %s[%s] %s%s\n' "${C_HDR}" "$(region_label "$reg")" "$(region_title "$reg")" "${NC}"
      print_cols
    fi

    send_st="skip"; send_mb=""; send_by=0
    recv_st="skip"; recv_mb=""; recv_by=0
    good_port=""
    fam_ok=true
    host_has_family "$host" "$ipver" || fam_ok=false

    if $fam_ok; then
      ticker_start "$(fit "$city" "$W_LOC") · $(fit "$prov" "$W_PROV")"
      if ! $SKIP_SEND; then
        run_iperf_range "$host" "$p0" "$p1" "$ipver" 0
        send_st="$RG_ST"; send_mb="$RG_MB"; send_by="$RG_BY"; good_port="$RG_PORT"
        track_result "$send_st" "$send_by" "up"
      fi
      if ! $SKIP_RECV; then
        # Unreachable host for upload → don't burn another round of timeouts.
        if [[ "$send_st" == "fail" && "$RG_WHY" =~ ^(dns|noaf|timeout)$ ]]; then
          recv_st="fail"
        else
          run_iperf_range "$host" "$p0" "$p1" "$ipver" 1 "$good_port"
          recv_st="$RG_ST"; recv_mb="$RG_MB"; recv_by="$RG_BY"
        fi
        track_result "$recv_st" "$recv_by" "down"
      fi
      ticker_stop
    elif [[ "$ipver" == "6" ]]; then
      # No AAAA record: not a failure, the endpoint just has no IPv6.
      $SKIP_SEND || send_st="nov6"
      $SKIP_RECV || recv_st="nov6"
    else
      # No A record (DNS failure): count as failed without trying ports.
      if ! $SKIP_SEND; then send_st="fail"; track_result fail 0 up; fi
      if ! $SKIP_RECV; then recv_st="fail"; track_result fail 0 down; fi
    fi

    J_IPV+=("$ipver"); J_ID+=("${EP_ID[$i]}")
    J_SEND_ST+=("$send_st"); J_SEND_MB+=("$send_mb"); J_RECV_ST+=("$recv_st"); J_RECV_MB+=("$recv_mb")

    send_s="$(format_speed_text "$send_st" "$send_mb")"
    recv_s="$(format_speed_text "$recv_st" "$recv_mb")"

    printf '  '
    lcell "$W_REG" "$(region_label "$reg")" "$C_HDR"; printf '  '
    lcell "$W_LOC" "$(fit "$city" "$W_LOC")" "$C_LOC"; printf '  '
    lcell "$W_PROV" "$(fit "$prov" "$W_PROV")" "$C_PROV"; printf '  '
    rcell "$W_SPD" "$send_s" "$(speed_color "$send_st" up)"; printf '  '
    rcell "$W_SPD" "$recv_s" "$(speed_color "$recv_st" down)"; printf '  '
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
  fmt_dur "$elapsed"

  printf '%s\n' "${C_BAR}-- Summary ----------------------------------------------------------------${NC}"
  printf '  %sElapsed%s     %s\n' "${BOLD}" "${NC}" "$DUR"
  printf '  %sTests%s       %s%d ok%s  %s%d busy%s  %s%d fail%s  %d total\n' \
    "${BOLD}" "${NC}" \
    "${C_OK}" "$TOTAL_OK" "${NC}" \
    "${C_BUSY}" "$TOTAL_BUSY" "${NC}" \
    "${C_FAIL}" "$TOTAL_FAIL" "${NC}" \
    "$TOTAL_TESTS"
  printf '  %sTraffic%s     %sSend(up)   %s%s\n' "${BOLD}" "${NC}" "${C_UP}" "$up_h" "${NC}"
  printf '               %sRecv(down) %s%s\n' "${C_DOWN}" "$down_h" "${NC}"
  printf '               total      %s\n' "$tot_h"
  printf '  %s             (this run only — iperf3 payload)%s\n' "${DIM}" "${NC}"
  printf '%s\n' "${C_BAR}--------------------------------------------------------------------------${NC}"
  $INTERRUPTED || ok "Done · NETS v${VERSION}"
}

json_str() {
  local s="$1"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/ }; s=${s//$'\n'/ }
  printf '"%s"' "$s"
}

# Row index → endpoint metadata index (rows only reference EP_ID values).
ep_index() {
  local id="$1" j
  for ((j = 0; j < ${#EP_ID[@]}; j++)); do [[ "${EP_ID[$j]}" == "$id" ]] && { printf '%s' "$j"; return; }; done
  printf '0'
}

emit_json() {
  local i j sep="" sm rm
  {
    printf '{"tool":"nets","version":%s,"time":%s,"region":%s,"duration_s":%s,"parallel":%s,' \
      "$(json_str "$VERSION")" "$(json_str "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" "$(json_str "$REGION")" "$TEST_TIME" "$PARALLEL"
    printf '"ipv4":%s,"ipv6":%s,"interrupted":%s,"results":[' "$HAVE_IPV4" "$HAVE_IPV6" "$INTERRUPTED"
    for ((i = 0; i < ${#J_ID[@]}; i++)); do
      j="$(ep_index "${J_ID[$i]}")"
      sm="${J_SEND_MB[$i]:-null}"; rm="${J_RECV_MB[$i]:-null}"
      printf '%s{"ip":%s,"id":%s,"provider":%s,"city":%s,"region":%s,"host":%s,"send":{"status":%s,"mbps":%s},"recv":{"status":%s,"mbps":%s}}' \
        "$sep" "${J_IPV[$i]}" "$(json_str "${J_ID[$i]}")" "$(json_str "${EP_PROVIDER[$j]}")" "$(json_str "${EP_CITY[$j]}")" \
        "$(json_str "${EP_REGION[$j]}")" "$(json_str "${EP_HOST[$j]}")" \
        "$(json_str "${J_SEND_ST[$i]}")" "$sm" "$(json_str "${J_RECV_ST[$i]}")" "$rm"
      sep=","
    done
    printf '],"totals":{"ok":%d,"busy":%d,"fail":%d,"tests":%d,"send_bytes":%d,"recv_bytes":%d}}\n' \
      "$TOTAL_OK" "$TOTAL_BUSY" "$TOTAL_FAIL" "$TOTAL_TESTS" "$TOTAL_SEND_BYTES" "$TOTAL_RECV_BYTES"
  } >&3
}

need_arg() { # option value
  if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then err "Option $1 needs a value."; usage >&2; exit 1; fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--reduced) REGION="reduced"; shift ;;
      --region) need_arg "$@"; REGION="$2"; shift 2 ;;
      --region=*) REGION="${1#*=}"; shift ;;
      -4) FORCE_IP="4"; shift ;;
      -6) FORCE_IP="6"; shift ;;
      -t|--time) need_arg "$@"; TEST_TIME="$2"; shift 2 ;;
      --time=*) TEST_TIME="${1#*=}"; shift ;;
      -P|--parallel) need_arg "$@"; PARALLEL="$2"; shift 2 ;;
      --parallel=*) PARALLEL="${1#*=}"; shift ;;
      --send-only) SKIP_RECV=true; shift ;;
      --recv-only) SKIP_SEND=true; shift ;;
      -j|--json) JSON_MODE=true; shift ;;
      -y|--yes) AUTO_YES=true; shift ;;
      --no-install) NO_INSTALL=true; shift ;;
      --no-clear) NO_CLEAR=true; shift ;;
      --no-color) NO_COLOR_FLAG=true; shift ;;
      -l|--list) LIST_ONLY=true; shift ;;
      -h|--help) usage; exit 0 ;;
      -v|--version) echo "NETS v${VERSION}"; exit 0 ;;
      *) err "Unknown option: $1"; usage >&2; exit 1 ;;
    esac
  done
  REGION="${REGION,,}"
  case "$REGION" in
    global|na|eu|apac|reduced) ;;
    *) err "Invalid region: $REGION (global | na | eu | apac | reduced)"; exit 1 ;;
  esac
  if ! [[ "$TEST_TIME" =~ ^[0-9]+$ ]] || ((TEST_TIME < 1 || TEST_TIME > 600)); then
    err "Invalid -t value: $TEST_TIME (1-600 seconds)"; exit 1
  fi
  if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || ((PARALLEL < 1 || PARALLEL > 128)); then
    err "Invalid -P value: $PARALLEL (1-128)"; exit 1
  fi
  if $SKIP_SEND && $SKIP_RECV; then
    err "--send-only and --recv-only are mutually exclusive."; exit 1
  fi
}

# Clear only a real terminal (under curl|bash stdout is still the TTY).
clear_screen() {
  if [[ -t 1 && -z "${CATBASH_NO_CLEAR:-}" ]] && ! $NO_CLEAR && ! $JSON_MODE; then printf '\033[2J\033[H'; fi
  return 0
}

main() {
  parse_args "$@"

  # --json: human output → stderr, JSON → original stdout (fd 3).
  if $JSON_MODE; then exec 3>&1 1>&2; else exec 3>&1; fi
  setup_colors
  trap cleanup EXIT
  trap 'on_interrupt 130' INT
  trap 'on_interrupt 143' TERM

  load_endpoints || exit 1

  if $LIST_ONLY; then
    list_endpoints
    exit 0
  fi

  ensure_deps || exit 1
  probe_tools
  STATUS_FILE="$(mktemp "${TMPDIR:-/tmp}/nets-status.XXXXXX")" || STATUS_FILE=""

  clear_screen
  detect_connectivity
  print_header

  RUN_START=$SECONDS
  RUN_STARTED=true
  if [[ -z "$FORCE_IP" || "$FORCE_IP" == "4" ]]; then
    run_mode_table 4
  fi
  if [[ -z "$FORCE_IP" || "$FORCE_IP" == "6" ]]; then
    run_mode_table 6
  fi

  print_summary $((SECONDS - RUN_START))
  $JSON_MODE && emit_json
  # Exit 1 only when nothing at all succeeded.
  if ((TOTAL_TESTS > 0 && TOTAL_OK == 0)); then exit 1; fi
  exit 0
}

main "$@"
