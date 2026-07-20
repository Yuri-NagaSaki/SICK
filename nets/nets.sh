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

VERSION="0.1.0"
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

# Colors
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; WHITE=$'\033[1;37m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; CYAN=""; WHITE=""; DIM=""; NC=""
fi

HAVE_IPV4=false
HAVE_IPV6=false

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
  # 2) beside script
  if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/endpoints.json" ]]; then
    ENDPOINTS_JSON="${SCRIPT_DIR}/endpoints.json"
    return 0
  fi
  # 3) cwd
  if [[ -f "./endpoints.json" ]]; then
    ENDPOINTS_JSON="$(pwd)/endpoints.json"
    return 0
  fi
  # 4) download from public short hosts
  local url
  ENDPOINTS_TMP="$(mktemp "${TMPDIR:-/tmp}/nets-endpoints.XXXXXX.json")"
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
  err "Could not load endpoints.json (local or https://catbash.net/nets/endpoints.json)."
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

list_endpoints() {
  printf '%b\n' "${WHITE}NETS endpoints (region=${REGION})${NC}"
  printf '%-20s %-16s %-28s %-36s %s\n' "ID" "PROVIDER" "CITY" "HOST" "PORTS/STACK"
  local i
  for ((i = 0; i < ${#EP_ID[@]}; i++)); do
    printf '%-20s %-16s %-28s %-36s %s-%s %s\n' \
      "${EP_ID[$i]}" "${EP_PROVIDER[$i]}" "${EP_CITY[$i]}" "${EP_HOST[$i]}" \
      "${EP_P0[$i]}" "${EP_P1[$i]}" "${EP_STACK[$i]}"
  done
  printf '\n%d endpoint(s)\n' "${#EP_ID[@]}"
}

# Try iperf3 once; print result line to stdout: status|speed_mbps
# status: ok | busy | fail
run_iperf_once() {
  local host="$1" port="$2" ipver="$3" reverse="$4"
  local flags=()
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

  if echo "$out" | grep -qiE 'busy|server is busy|the server is busy'; then
    echo "busy|"
    return 0
  fi
  if echo "$out" | grep -qiE 'unable to connect|connection refused|no route|failed to connect|timeout|timed out'; then
    echo "fail|"
    return 0
  fi
  # Prefer SUM receiver line (aggregate with -P)
  local speed unit
  speed="$(echo "$out" | grep -E 'SUM.*receiver|\[SUM\].*receiver' | tail -1 | awk '{print $(NF-2)}')"
  unit="$(echo "$out" | grep -E 'SUM.*receiver|\[SUM\].*receiver' | tail -1 | awk '{print $(NF-1)}')"
  if [[ -z "$speed" ]]; then
    # single-stream fallback
    speed="$(echo "$out" | grep -E 'receiver$' | tail -1 | awk '{print $(NF-2)}')"
    unit="$(echo "$out" | grep -E 'receiver$' | tail -1 | awk '{print $(NF-1)}')"
  fi
  if [[ -z "$speed" || "$speed" == "0.00" ]]; then
    if [[ $rc -ne 0 ]]; then
      echo "fail|"
    else
      echo "busy|"
    fi
    return 0
  fi
  # Normalize to Mbps
  local mbps
  case "$unit" in
    Gbits/sec|Gbit/s) mbps="$(awk -v s="$speed" 'BEGIN{printf "%.2f", s*1000}')" ;;
    Mbits/sec|Mbit/s) mbps="$(awk -v s="$speed" 'BEGIN{printf "%.2f", s}')" ;;
    Kbits/sec|Kbit/s) mbps="$(awk -v s="$speed" 'BEGIN{printf "%.2f", s/1000}')" ;;
    *) mbps="$speed" ;;
  esac
  echo "ok|${mbps}"
}

# Run direction trying ports in range until ok or exhausted.
# Prints: status|mbps|port
run_iperf_range() {
  local host="$1" p0="$2" p1="$3" ipver="$4" reverse="$5"
  local p st mb
  for ((p = p0; p <= p1; p++)); do
    IFS='|' read -r st mb <<<"$(run_iperf_once "$host" "$p" "$ipver" "$reverse")"
    if [[ "$st" == "ok" ]]; then
      echo "ok|${mb}|${p}"
      return 0
    fi
    if [[ "$st" == "fail" && "$p0" == "$p1" ]]; then
      echo "fail||${p}"
      return 0
    fi
    # busy -> try next port; fail on multi-port also try next
  done
  # last status
  if [[ "${st:-}" == "busy" ]]; then
    echo "busy||${p1}"
  else
    echo "fail||${p1}"
  fi
}

format_speed() {
  local status="$1" mbps="$2"
  case "$status" in
    ok)   printf '%s' "${mbps} Mbps" ;;
    busy) printf '%s' "busy" ;;
    skip) printf '%s' "-" ;;
    *)    printf '%s' "fail" ;;
  esac
}

print_header() {
  printf '%b\n' "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
  printf '%b\n' "${WHITE}  NETS v${VERSION} — Network Endpoint Throughput Sampler${NC}"
  printf '%b\n' "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
  printf ' Region     : %s\n' "$REGION"
  printf ' Duration   : %ss / direction · Parallel: %s\n' "$TEST_TIME" "$PARALLEL"
  printf ' IPv4       : %s\n' "$( $HAVE_IPV4 && echo yes || echo no )"
  printf ' IPv6       : %s\n' "$( $HAVE_IPV6 && echo yes || echo no )"
  printf ' Endpoints  : %d\n' "${#EP_ID[@]}"
  printf ' iperf3     : %s\n' "$IPERF_BIN"
  printf '%b\n' "${DIM} Public shared servers — busy is normal; not equal to bare-metal capacity.${NC}"
  echo
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

  printf '%b\n' "${WHITE}── iperf3 (${mode_label}) ──────────────────────────────────────────────────${NC}"
  printf '%-16s %-18s %-6s %-14s %-14s %s\n' \
    "Location" "Provider" "Port" "Send (up)" "Recv (down)" "Link"
  printf '%-16s %-18s %-6s %-14s %-14s %s\n' \
    "----------------" "------------------" "------" "--------------" "--------------" "------"

  local i host p0 p1 stack city prov speed_meta
  local do_test port send_st send_mb recv_st recv_mb send_s recv_s sport rport
  for ((i = 0; i < ${#EP_ID[@]}; i++)); do
    host="${EP_HOST[$i]}"
    p0="${EP_P0[$i]}"; p1="${EP_P1[$i]}"
    stack="${EP_STACK[$i]}"
    city="${EP_CITY[$i]}"
    prov="${EP_PROVIDER[$i]}"
    speed_meta="${EP_SPEED[$i]}"

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

    local city_short="$city"
    ((${#city_short} > 16)) && city_short="${city_short:0:15}…"
    local prov_short="$prov"
    ((${#prov_short} > 18)) && prov_short="${prov_short:0:17}…"

    send_st="skip"; send_mb=""; recv_st="skip"; recv_mb=""
    port="$p0"

    if ! $SKIP_SEND; then
      IFS='|' read -r send_st send_mb sport <<<"$(run_iperf_range "$host" "$p0" "$p1" "$ipver" 0)"
      [[ -n "${sport:-}" ]] && port="$sport"
    fi
    if ! $SKIP_RECV; then
      IFS='|' read -r recv_st recv_mb rport <<<"$(run_iperf_range "$host" "$p0" "$p1" "$ipver" 1)"
      [[ -n "${rport:-}" ]] && port="$rport"
    fi

    send_s="$(format_speed "$send_st" "$send_mb")"
    recv_s="$(format_speed "$recv_st" "$recv_mb")"

    # Plain table (no ANSI inside columns — keeps alignment)
    printf '%-16s %-18s %-6s %-14s %-14s %s\n' \
      "$city_short" "$prov_short" "$port" "$send_s" "$recv_s" "$speed_meta"
  done
  echo
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
  printf '%b\n' "${CYAN}────────────────────────────────────────────────────────────────────────────${NC}"
  ok "Done in $((end - start))s · NETS v${VERSION}"
  printf '%b\n' "${DIM}Endpoint catalog: ${ENDPOINTS_JSON}${NC}"
}

main "$@"
