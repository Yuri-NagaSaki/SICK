#!/usr/bin/env bash
#
# Regenerate the terminal replays on catbash.net (assets/demos/*.ansi) by
# running the real scripts inside `script` (a pty, so colours, spinners and
# \r redraws are kept), then refresh the static no-JS fallbacks in the pages.
#
#   bash tools/demos/capture.sh               # everything (~3 min)
#   bash tools/demos/capture.sh sick nets     # only some: menu sick nets cpux all
#   DEMO_COLS=110 bash tools/demos/capture.sh # terminal width (default 100)
#
# Needs: bash, script (util-linux), python3, tar, curl, iperf3; node for the
# static fallbacks (skipped with a warning when missing). Run as root so SICK
# takes its full-data paths. Nothing touches the network: hardware tools,
# Geekbench and the iperf3 endpoints are mocked (tools/demos/mock/), every
# temp file lives in one mktemp dir that is removed on exit.
#
# What is mocked:
#   SICK  smartctl nvme lspci dmidecode sensors ethtool lshw lsblk df ip
#         systemd-detect-virt stubs on PATH (mock/bin, canned JSON in mock/data)
#   NETS  local `iperf3 -s` daemons on 127.0.0.1; NETS_ENDPOINTS_JSON points
#         at a catalog with real city/provider names; mock/bin/iperf3 caps
#         per-port bitrates so numbers vary; one endpoint is kept busy
#   CPUX  fake Geekbench 5/6/7 tarballs (mock/geekbench) served by
#         mock/server.py via CPUX_MIRROR; scores from a local CPUX_SCORE_API;
#         mock/bin/curl rewrites *.geekbench.com to that server; CPUX_JINA=""
#
# Every replay is labelled "Sample output · demo data" on the site.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/tools/demos"
OUT="$ROOT/assets/demos"
COLS="${DEMO_COLS:-100}"
HOST="${DEMO_HOST:-catlab-01}"
PORT0="${DEMO_PORT:-18300}"          # mock HTTP server; iperf3 uses PORT0+1…
SCORES="${DEMO_SCORES:-5:1046:3794 6:1373:4219 7:1528:5107}"

for c in script python3 tar curl iperf3; do
  command -v "$c" >/dev/null 2>&1 || { echo "capture.sh: missing $c" >&2; exit 1; }
done

WANT=("$@")
((${#WANT[@]})) || WANT=(menu sick nets cpux all)
want() { local w; for w in "${WANT[@]}"; do [[ "$w" == "$1" ]] && return 0; done; return 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/catbash-demo.XXXXXX")"
PIDS=()
cleanup() {
  local p f
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  for f in "$TMP"/iperf-*.pid; do [[ -f "$f" ]] && kill "$(cat "$f")" 2>/dev/null || true; done
  wait 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
mkdir -p "$OUT" "$TMP/run" "$TMP/cdn"

# ---------- common environment ----------
export PATH="$HERE/mock/bin:$PATH"
export HOSTNAME="$HOST" TERM=xterm-256color LANG=C.UTF-8 TZ=UTC SHELL=/bin/bash
unset LC_ALL NO_COLOR CATBASH_NO_CLEAR CATBASH_LOCAL \
      http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy 2>/dev/null || true

# ---------- mock HTTP server (Geekbench CDN + browser + score API) ----------
start_http() {
  local v build sfx d
  for v in 5 6 7; do
    case $v in 5) build=5.5.1 ;; 6) build=6.7.1 ;; 7) build=7.0.0 ;; esac
    for sfx in Linux LinuxARMPreview LinuxRISCVPreview; do
      d="$TMP/pkg/Geekbench-${build}-${sfx}"
      mkdir -p "$d"
      sed -e "s/@MAJOR@/$v/" -e "s/@BUILD@/$build/" "$HERE/mock/geekbench" >"$d/geekbench$v"
      chmod +x "$d/geekbench$v"
      tar -czf "$TMP/cdn/Geekbench-${build}-${sfx}.tar.gz" -C "$TMP/pkg" "Geekbench-${build}-${sfx}"
    done
  done
  python3 -I "$HERE/mock/server.py" "$PORT0" "$TMP/cdn" "$SCORES" &
  PIDS+=($!)
  local i
  for i in $(seq 1 50); do
    curl -fsS -o /dev/null "http://127.0.0.1:$PORT0/gbb/" 2>/dev/null && return 0
    sleep 0.1
  done
  echo "capture.sh: mock server did not start on :$PORT0" >&2; exit 1
}

# ---------- iperf3 endpoints (NETS) ----------
# id|provider|city|region|link|per-stream rate ("busy" = kept busy)
NETS_EPS=(
  "purevoltage-nyc|PureVoltage|New York, US|na|40G|420M"
  "clouvider-la|Clouvider|Los Angeles, US|na|10G|240M"
  "leaseweb-mtl|Leaseweb|Montreal, CA|na|10G|360M"
  "onlyservers-uk|OnlyServers|United Kingdom|eu|10G|1050M"
  "eranium-ams|Eranium|Amsterdam, NL|eu|100G|1580M"
  "wobcom-fra|Wobcom|Frankfurt, DE|eu|25G|2240M"
  "leaseweb-tyo|Leaseweb|Tokyo, JP|apac|10G|150M"
  "leaseweb-hkg|Leaseweb|Hong Kong, HK|apac|10G|busy"
)
start_iperf() {
  local i=0 e id prov city reg link rate port rows="" ids="" sep=""
  export DEMO_IPERF_RATES=""
  for e in "${NETS_EPS[@]}"; do
    IFS='|' read -r id prov city reg link rate <<<"$e"
    i=$((i + 1)); port=$((PORT0 + i))
    command iperf3 -s -p "$port" -D --pidfile "$TMP/iperf-$port.pid" >/dev/null 2>&1
    if [[ "$rate" == busy ]]; then
      # Occupy the server: NETS then reports "busy", like a shared public node.
      sleep 0.3
      command iperf3 -c 127.0.0.1 -p "$port" -t 900 -b 64K >/dev/null 2>&1 &
      PIDS+=($!)
    else
      DEMO_IPERF_RATES+="${DEMO_IPERF_RATES:+ }$port:$rate"
    fi
    rows+="$sep{\"id\":\"$id\",\"provider\":\"$prov\",\"city\":\"$city\",\"region\":\"$reg\",\"host\":\"127.0.0.1\",\"port_range\":[$port,$port],\"speed\":\"$link\",\"stack\":\"IPv4|IPv6\"}"
    ids+="$sep\"$id\""
    sep=","
  done
  printf '{"version":1,"endpoints":[%s],"reduced_ids":[%s]}\n' "$rows" "$ids" >"$TMP/endpoints.json"
  export NETS_ENDPOINTS_JSON="$TMP/endpoints.json"
  sleep 0.5
}

# ---------- recording ----------
# feed RAW [pattern text]… : wait for each pattern in the live log, then type.
feed() {
  local raw="$1" pat txt n
  shift
  while (($# >= 2)); do
    pat="$1" txt="$2"; shift 2
    for n in $(seq 1 1200); do
      grep -aqF -- "$pat" "$raw" 2>/dev/null && break
      sleep 0.1
    done
    sleep 0.8
    printf '%s' "$txt"
  done
  sleep 0.5
}

# record NAME "shown command" "real command" [pattern text]…
record() {
  local name="$1" shown="$2" cmd="$3"
  shift 3
  local raw="$TMP/$name.raw" tim="$TMP/$name.tim"
  printf '  %-8s %s\n' "$name" "$shown" >&2
  : >"$raw"
  (
    cd "$TMP/run"
    feed "$raw" "$@" | script -q -f -T "$tim" -ec "stty cols $COLS rows 40; $cmd" "$raw" >/dev/null 2>&1
  ) || true
  python3 -I "$HERE/pack.py" "$raw" "$tim" "$OUT/$name.ansi" --cmd "$shown" --host "$HOST" \
    --max-frames "${MAXF:-14}" \
    --sub "$ROOT/hardware_info.sh=https://catbash.net/sick" \
    --sub "$ROOT/nets/nets.sh=https://catbash.net/nets" \
    --sub "$ROOT/cpux.sh=https://catbash.net/cpux" \
    --sub "$TMP=/tmp" >&2
}

echo "capture.sh → $OUT" >&2
if want cpux || want all; then start_http; fi
if want nets || want all; then start_iperf; fi

CPUX_ENV="DEMO_MOCK_URL=http://127.0.0.1:$PORT0 CPUX_MIRROR=http://127.0.0.1:$PORT0/cdn CPUX_SCORE_API=http://127.0.0.1:$PORT0/api/gb CPUX_JINA= CPUX_WORKDIR=$TMP/run"

# CPUX first: its preflight warns when the load average is high (NETS raises it).
if want cpux; then
  record cpux    "curl -sL https://ba.sh/cpux | bash -s -- all"     "$CPUX_ENV bash $ROOT/cpux.sh all"
  record cpux.zh "curl -sL https://ba.sh/cpux | bash -s -- all -cn" "$CPUX_ENV bash $ROOT/cpux.sh all -cn"
fi
if want sick; then
  record sick    "curl -sL https://ba.sh/sick | bash"            "bash $ROOT/hardware_info.sh"
  record sick.zh "curl -sL https://ba.sh/sick | bash -s -- -cn"  "bash $ROOT/hardware_info.sh -cn"
fi
if want menu; then
  # Launcher: pick 1 (SICK), then q at "[Enter] back to menu · [q] quit".
  record menu "curl -sL https://ba.sh/menu | bash" "CATBASH_LOCAL=1 bash $ROOT/catbash.sh" \
    "Select [" $'1\n' "back to menu" $'q\n'
fi
if want nets; then
  MAXF=10 record nets "curl -sL https://ba.sh/nets | bash -s -- -r -t 2" "bash $ROOT/nets/nets.sh -r -t 2"
fi
if want all; then
  # `all` runs NETS with its default 10 s per direction; DEMO_IPERF_TIME=2
  # shortens the actual iperf3 runs so the capture stays quick.
  MAXF=10 record all    "curl -sL https://ba.sh/menu | bash -s -- all" \
    "CATBASH_LOCAL=1 DEMO_IPERF_TIME=2 $CPUX_ENV bash $ROOT/catbash.sh all"
  MAXF=10 record all.zh "curl -sL https://ba.sh/menu | bash -s -- all -cn" \
    "CATBASH_LOCAL=1 DEMO_IPERF_TIME=2 $CPUX_ENV bash $ROOT/catbash.sh all -cn"
fi

# ---------- static fallbacks (no-JS / reduced motion) ----------
if command -v node >/dev/null 2>&1; then
  node "$HERE/render.mjs"
else
  echo "capture.sh: node not found — static fallbacks in the HTML pages were not refreshed" >&2
fi
echo "done." >&2
