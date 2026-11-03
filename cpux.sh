#!/usr/bin/env bash
#
# CPUX — CPU eXaminer (Geekbench 5 / 6 / 7)
# Sequential Geekbench CPU benchmarks with reliable single/multi-core scores.
#
# Usage:
#   curl -sL https://ba.sh/cpux | bash
#   curl -sL https://ba.sh/cpux | bash -s -- 6
#   curl -sL https://ba.sh/cpux | bash -s -- all -cn
#   ./cpux.sh -5 -6 --json        # selected versions, JSON on stdout
#   ./cpux.sh --fetch URL         # (re)fetch scores of an existing result
#
# How scores are obtained:
#   The Geekbench *tryout* CLI uploads results but never prints scores.
#   CPUX therefore reads them back from the public result page, trying in
#   order (first complete answer wins, bounded by --fetch-timeout):
#     1. local CLI output       (licensed/Pro builds print a summary)
#     2. browser.geekbench.com  direct, plain curl UA, then browser UA
#     3. <url>.gbN              raw result JSON (if public; needs python3/jq)
#     4. catbash.net/api/gb     server-side fetch on Cloudflare (worker.js)
#     5. r.jina.ai              reader proxy, cache bypassed
#   Every source is parsed by the same tokenizer, which pairs each
#   "Single-Core Score" / "Multi-Core Score" label with its own number.
#
# Environment overrides:
#   CPUX_GB5_VER / CPUX_GB6_VER / CPUX_GB7_VER   pin other Geekbench builds
#   CPUX_MIRROR         extra download mirror, tried first (…/Geekbench-X-Linux.tar.gz)
#   CPUX_WORKDIR        where binaries are unpacked (default: auto-pick)
#   CPUX_FETCH_TIMEOUT  seconds to keep trying for scores (default 120)
#   CPUX_SCORE_API      score API URL ("" disables; default catbash.net)
#   CPUX_JINA           reader prefix ("" disables; default https://r.jina.ai/)
#   JINA_API_KEY        optional key for higher r.jina.ai rate limits
#   GEEKBENCH_EMAIL + GEEKBENCH_KEY   unlock a licensed build
#   NO_COLOR            disable colors
#
set -uo pipefail

VERSION="2.0.0"

GB5_VER="${CPUX_GB5_VER:-5.5.1}"
GB6_VER="${CPUX_GB6_VER:-6.7.1}"
GB7_VER="${CPUX_GB7_VER:-7.0.0}"

CDN_PRIMARY="https://cdn.geekbench.com"
CDN_MIRROR="https://asset.bash.icu/https://cdn.geekbench.com"

SCORE_API="${CPUX_SCORE_API-https://catbash.net/api/gb}"
JINA_PREFIX="${CPUX_JINA-https://r.jina.ai/}"
FETCH_BUDGET="${CPUX_FETCH_TIMEOUT:-120}"
[[ "$FETCH_BUDGET" =~ ^[0-9]+$ ]] || FETCH_BUDGET=120

UA_BROWSER="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
UA_CPUX="cpux/${VERSION} (+https://catbash.net/cpux.html)"

# Free space wanted for one unpacked Geekbench build (KiB).
NEED_DISK_KB=$((600 * 1024))

KEEP_FILES=0
AUTO_YES=0
JSON_MODE=0
NO_CLEAR=0
NO_COLOR_FLAG=0
LANG_MODE="en"   # en | zh
DO_GB5=0
DO_GB6=0
DO_GB7=0
FETCH_URLS=()
WORKDIR=""
STATUS_FILE=""
SPINNER_PID=""
GB_PID=""
BG_PID=""
PLAN_INDEX=0
PLAN_TOTAL=0
RUN_START=0
CURL_IPV=""
HTTP_CODE="000"
ARCH_KIND=""
CLAIM_SAVED=0

# Per-suite results (parallel arrays)
R_SUITE=(); R_BUILD=(); R_STATUS=(); R_SINGLE=(); R_MULTI=()
R_URL=(); R_CLAIM=(); R_SECS=(); R_NOTE=()

# Colors are set in setup_colors() once we know where output goes.
C_HDR=""; C_DIM=""; C_OK=""; C_ACC=""; C_BAR=""; C_ERR=""; C_WARN=""; NC=""; BOLD=""

setup_colors() {
  if [[ -t 1 && -z "${NO_COLOR:-}" && "$NO_COLOR_FLAG" -eq 0 && "${TERM:-}" != "dumb" ]]; then
    C_HDR=$'\033[1;38;5;222m'
    C_DIM=$'\033[2m'
    C_OK=$'\033[38;5;114m'
    C_ACC=$'\033[38;5;81m'
    C_BAR=$'\033[38;5;73m'
    C_ERR=$'\033[38;5;203m'
    C_WARN=$'\033[38;5;214m'
    NC=$'\033[0m'
    BOLD=$'\033[1m'
  fi
}

# ---------- output helpers ----------
# The spinner owns the current line; wipe it before printing a message.
clear_line() {
  if [[ -n "${SPINNER_PID:-}" && -t 1 ]]; then printf '\r\033[K'; fi
  return 0
}
say()  { clear_line; printf '%s\n' "$*"; }
info() { clear_line; printf '%s\n' "${C_DIM}$*${NC}"; }
warn() { clear_line; printf '%s\n' "${C_WARN}! $*${NC}"; }
err()  { clear_line; printf '%s\n' "${C_ERR}x $*${NC}" >&2; }

T() { # T "english" "中文"
  if [[ "$LANG_MODE" == "zh" ]]; then printf '%s' "${2:-$1}"; else printf '%s' "$1"; fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# Fork-free duration formatting: sets DUR (129 → 2m09s).
fmt_dur() {
  local s="${1:-0}"
  if ((s >= 60)); then printf -v DUR '%dm%02ds' "$((s / 60))" "$((s % 60))"
  else printf -v DUR '%ds' "$s"; fi
}

# A usable controlling terminal? (/dev/tty can exist yet fail to open
# under ssh without -t, cron, CI and containers.)
TTY_STATE=""
have_tty() {
  if [[ -z "$TTY_STATE" ]]; then
    if (exec </dev/tty) 2>/dev/null; then TTY_STATE=yes; else TTY_STATE=no; fi
  fi
  [[ "$TTY_STATE" == yes ]]
}

# Read one line from the terminal (works under curl | bash). Sets REPLY_TEXT.
read_tty() {
  REPLY_TEXT=""
  have_tty || return 1
  printf '%s' "$1" >/dev/tty
  IFS= read -r REPLY_TEXT </dev/tty || true
  return 0
}

# ask_yn "prompt" default(y|n) — honours -y; without a TTY returns the default.
ask_yn() {
  local prompt="$1" def="${2:-n}"
  if [[ "$AUTO_YES" -eq 1 ]]; then return 0; fi
  if ! read_tty "$prompt"; then [[ "$def" == y ]]; return; fi
  case "$REPLY_TEXT" in
    [Yy]|[Yy][Ee][Ss]|是) return 0 ;;
    [Nn]|[Nn][Oo]|否) return 1 ;;
    *) [[ "$def" == y ]] ;;
  esac
}

clear_screen() {
  if [[ -t 1 && "$NO_CLEAR" -eq 0 && "$JSON_MODE" -eq 0 && -z "${CATBASH_NO_CLEAR:-}" ]]; then printf '\033[2J\033[H'; fi
  return 0
}

status_set() {
  [[ -n "${STATUS_FILE:-}" ]] || return 0
  printf '%s\n' "$*" >"$STATUS_FILE" 2>/dev/null || true
}

usage() {
  cat <<EOF
CPUX v${VERSION} — CPU eXaminer (Geekbench 5 / 6 / 7)

$(T "Usage:" "用法:")
  cpux.sh                    $(T "Interactive menu" "交互菜单")
  cpux.sh 5|6|7              $(T "Run one Geekbench version" "运行单个版本")
  cpux.sh all                $(T "Run 5 → 6 → 7 sequentially" "依次运行 5 → 6 → 7")
  cpux.sh -5 -7              $(T "Any combination" "任选版本组合")
  cpux.sh --fetch URL...     $(T "Only fetch scores of existing result URL(s)" "仅获取已有结果链接的分数")

$(T "Options:" "参数:")
  -5, --gb5                  Geekbench ${GB5_VER}
  -6, --gb6                  Geekbench ${GB6_VER}
  -7, --gb7                  Geekbench ${GB7_VER}
  -a, --all                  $(T "Geekbench 5 + 6 + 7 (sequential)" "Geekbench 5 + 6 + 7（依次）")
  -j, --json                 $(T "JSON result on stdout (progress on stderr)" "stdout 输出 JSON（进度在 stderr）")
  -y, --yes                  $(T "Do not ask; continue on warnings" "不询问；遇到警告继续")
  -k, --keep                 $(T "Keep downloaded binaries" "保留下载的二进制")
      --fetch-timeout SEC    $(T "Give up fetching scores after SEC (default ${FETCH_BUDGET})" "取分超时秒数（默认 ${FETCH_BUDGET}）")
      --no-clear             $(T "Do not clear the screen" "不清屏")
      --no-color             $(T "Disable colors" "禁用颜色")
  -cn, --chinese             $(T "Chinese UI" "中文界面")
  -us, --english             $(T "English UI (default)" "英文界面（默认）")
  -h, --help                 $(T "Show help" "显示帮助")
  -v, --version              $(T "Show version" "显示版本")

$(T "Examples:" "示例:")
  curl -sL https://ba.sh/cpux | bash -s -- 6
  curl -sL https://ba.sh/cpux | bash -s -- all -cn
  curl -sL https://ba.sh/cpux | bash -s -- 6 --json > gb6.json
  curl -sL https://ba.sh/cpux | bash -s -- --fetch https://browser.geekbench.com/v6/cpu/123456

$(T "Docs:" "文档:") https://catbash.net/cpux.html
EOF
}

# ---------- lifecycle ----------
stop_spinner() {
  if [[ -n "${SPINNER_PID:-}" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    if [[ -t 1 ]]; then printf '\r\033[K\033[?25h'; fi
  fi
  return 0
}

# Background jobs of a non-interactive shell ignore SIGINT, and Geekbench
# runs its workloads in a child process — so terminate whole trees.
kill_tree() {
  local pid="$1" kids="" c
  [[ -n "$pid" ]] || return 0
  if [[ -r "/proc/$pid/task/$pid/children" ]]; then
    kids="$(<"/proc/$pid/task/$pid/children")"
  elif need_cmd pgrep; then
    kids="$(pgrep -P "$pid" 2>/dev/null)"
  fi
  kill -TERM "$pid" 2>/dev/null
  for c in $kids; do kill_tree "$c"; done
  return 0
}

kill_children() {
  kill_tree "${GB_PID:-}"
  kill_tree "${BG_PID:-}"
  GB_PID=""; BG_PID=""
  return 0
}

cleanup() {
  stop_spinner
  kill_children
  if [[ -n "${WORKDIR:-}" && -d "$WORKDIR" && "$KEEP_FILES" -eq 0 ]]; then
    rm -rf "$WORKDIR" 2>/dev/null || true
  fi
}

on_interrupt() {
  local code="${1:-130}"
  trap - INT TERM
  stop_spinner
  kill_children
  printf '\n'
  warn "$(T "Interrupted." "已中断。")"
  if ((${#R_SUITE[@]} > 0)); then
    if [[ "$JSON_MODE" -eq 1 ]]; then emit_json; else print_summary; fi
  fi
  exit "$code"
}

# ---------- system checks ----------
detect_arch() {
  local m bits
  m="$(uname -m)"
  bits="$(getconf LONG_BIT 2>/dev/null || echo 64)"
  if [[ "$bits" != "64" ]]; then
    err "$(T "Only 64-bit systems are supported." "仅支持 64 位系统。")"
    return 1
  fi
  case "$m" in
    x86_64|amd64)  ARCH_KIND="x64" ;;
    aarch64|arm64) ARCH_KIND="arm64" ;;
    riscv64)       ARCH_KIND="riscv64" ;;
    *) err "$(T "Unsupported architecture: $m" "不支持的架构: $m")"; return 1 ;;
  esac
}

SYS_CPU=""; SYS_CORES=""; SYS_MEM_MIB=0; SYS_SWAP_MIB=0; SYS_VIRT=""; SYS_OS=""; SYS_LOAD=""
collect_sysinfo() {
  SYS_CPU="$(awk -F: '/^model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)"
  if [[ -z "$SYS_CPU" ]] && need_cmd lscpu; then
    SYS_CPU="$(LC_ALL=C lscpu 2>/dev/null | awk -F: '/^Model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}')"
  fi
  [[ -n "$SYS_CPU" ]] || SYS_CPU="$(uname -m) CPU"
  SYS_CPU="${SYS_CPU//  / }"
  SYS_CORES="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"
  read -r SYS_MEM_MIB SYS_SWAP_MIB < <(awk '/^MemTotal:/ {m=int($2/1024)} /^SwapTotal:/ {s=int($2/1024)} END {print m+0, s+0}' /proc/meminfo 2>/dev/null)
  SYS_MEM_MIB="${SYS_MEM_MIB:-0}"; SYS_SWAP_MIB="${SYS_SWAP_MIB:-0}"
  SYS_VIRT="$(systemd-detect-virt 2>/dev/null || true)"
  if [[ -z "$SYS_VIRT" || "$SYS_VIRT" == "none" ]]; then
    if [[ -f /.dockerenv ]]; then SYS_VIRT="docker"
    elif [[ -f /run/.containerenv ]]; then SYS_VIRT="podman"
    elif grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then SYS_VIRT="vm"
    else SYS_VIRT="none"; fi
  fi
  if [[ -r /etc/os-release ]]; then
    SYS_OS="$(awk -F= '/^PRETTY_NAME=/ {gsub(/"/, "", $2); print $2; exit}' /etc/os-release)"
  fi
  [[ -n "$SYS_OS" ]] || SYS_OS="$(uname -s)"
  SYS_LOAD="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
}

print_sysinfo() {
  local mem
  mem="$(awk -v m="$SYS_MEM_MIB" 'BEGIN { printf "%.1f GiB", m / 1024 }')"
  say ""
  say "${C_HDR}${BOLD}CPUX${NC} v${VERSION} · CPU eXaminer"
  say "${C_DIM}${SYS_CPU} · ${SYS_CORES}c · ${mem} · $(uname -m)/${SYS_VIRT}${NC}"
}

preflight_warnings() {
  local total=$((SYS_MEM_MIB + SYS_SWAP_MIB))
  if ((total > 0 && total < 1000)); then
    warn "$(T "Low memory (${SYS_MEM_MIB} MiB RAM + ${SYS_SWAP_MIB} MiB swap). Geekbench may be killed below ~1 GiB." \
              "内存较低（${SYS_MEM_MIB} MiB 内存 + ${SYS_SWAP_MIB} MiB Swap）。低于约 1 GiB 时 Geekbench 可能被杀。")"
  fi
  # Something else hogging the CPU skews scores downward.
  if [[ -n "$SYS_LOAD" ]] && awk -v l="$SYS_LOAD" -v c="$SYS_CORES" 'BEGIN { exit !(l > c * 0.5 + 0.5) }'; then
    warn "$(T "System is busy (load ${SYS_LOAD} on ${SYS_CORES} cores) — scores will be lower than idle." \
              "系统繁忙（负载 ${SYS_LOAD} / ${SYS_CORES} 核）— 分数会低于空闲状态。")"
  fi
  # Geekbench ships glibc binaries.
  if ldd --version 2>&1 | grep -qi musl && [[ ! -e /lib64/ld-linux-x86-64.so.2 && ! -e /lib/ld-linux-aarch64.so.1 ]]; then
    warn "$(T "musl libc detected: Geekbench needs glibc (Alpine: apk add gcompat)." \
              "检测到 musl libc：Geekbench 需要 glibc（Alpine: apk add gcompat）。")"
  fi
}

# Uploads go to browser.geekbench.com over IPv4. Prefer -4 for every
# Geekbench request when that works (broken IPv6 otherwise adds timeouts).
probe_ipv4() {
  local code=""
  need_cmd curl || return 0
  code="$(curl -4 -sS -o /dev/null -w '%{http_code}' --connect-timeout 6 --max-time 12 \
            https://browser.geekbench.com/ </dev/null 2>/dev/null)" || true
  if [[ "$code" =~ ^[1-9][0-9][0-9]$ ]]; then CURL_IPV="-4"; return 0; fi
  return 1
}

check_network() {
  need_cmd curl || return 0
  probe_ipv4 && return 0
  warn "$(T "Cannot reach browser.geekbench.com over IPv4. Geekbench uploads results there; without it there is no result URL and no scores." \
            "无法通过 IPv4 访问 browser.geekbench.com。Geekbench 需要上传结果到此处，否则没有结果链接和分数。")"
  if have_tty && [[ "$AUTO_YES" -eq 0 ]]; then
    ask_yn "  $(T "Run anyway? [y/N]: " "仍然运行？[y/N]: ")" n || return 1
  fi
  return 0
}

# Choose a work dir with room for an unpacked build; prefer disk over tmpfs
# so small-RAM VPSes don't spend benchmark memory on extracted files.
pick_workdir_base() {
  local d free fs best="" best_free=-1 pass
  local -a cands=("${CPUX_WORKDIR:-}" "${TMPDIR:-/tmp}" /var/tmp "${HOME:-}" "$PWD")
  for pass in 1 2; do
    for d in "${cands[@]}"; do
      [[ -n "$d" && -d "$d" && -w "$d" ]] || continue
      free="$(df -Pk "$d" 2>/dev/null | awk 'NR == 2 {print $4}')"
      [[ "$free" =~ ^[0-9]+$ ]] || free=0
      fs="$(stat -f -c %T "$d" 2>/dev/null || true)"
      if ((free >= NEED_DISK_KB)); then
        if [[ $pass -eq 2 || ( "$fs" != tmpfs && "$fs" != ramfs ) ]]; then
          printf '%s' "$d"; return 0
        fi
      fi
      if ((free > best_free)); then best="$d"; best_free=$free; fi
    done
  done
  if [[ -n "$best" ]]; then
    warn "$(T "Low disk space: $((best_free / 1024)) MiB free in ${best} (want ~$((NEED_DISK_KB / 1024)) MiB)." \
              "磁盘空间不足：${best} 仅剩 $((best_free / 1024)) MiB（建议约 $((NEED_DISK_KB / 1024)) MiB）。")"
    printf '%s' "$best"; return 0
  fi
  return 1
}

# ---------- Geekbench packages ----------
# Sets GB_LABEL GB_BUILD GB_BIN GB_TAR GB_URLS
setup_gb_meta() {
  local ver="$1" build suffix
  case "$ver" in
    5) build="$GB5_VER" ;;
    6) build="$GB6_VER" ;;
    7) build="$GB7_VER" ;;
    *) return 1 ;;
  esac
  case "$ARCH_KIND" in
    x64)     suffix="Linux" ;;
    arm64)   suffix="LinuxARMPreview" ;;
    riscv64) suffix="LinuxRISCVPreview" ;;
  esac
  GB_LABEL="Geekbench ${ver}"
  GB_BUILD="$build"
  GB_BIN="geekbench${ver}"
  GB_TAR="Geekbench-${build}-${suffix}.tar.gz"
  GB_URLS=()
  [[ -n "${CPUX_MIRROR:-}" ]] && GB_URLS+=("${CPUX_MIRROR%/}/${GB_TAR}")
  GB_URLS+=("${CDN_PRIMARY}/${GB_TAR}" "${CDN_MIRROR}/${GB_TAR}")
}

# Stream download straight into tar: no tarball on disk, no second pass.
stream_extract() {
  local url="$1" dest="$2"
  if need_cmd curl; then
    curl -fsSL --connect-timeout 15 --max-time 1800 "$url" </dev/null | tar -xzf - -C "$dest" --strip-components=1
  else
    wget -q -T 60 -O - "$url" </dev/null | tar -xzf - -C "$dest" --strip-components=1
  fi
}

# Sets GB_DEST to the directory holding the binary.
download_and_extract() {
  local ver="$1" dest="$WORKDIR/gb$1" url rc kb found
  GB_DEST=""
  if [[ -x "$dest/${GB_BIN}" ]]; then GB_DEST="$dest"; return 0; fi

  for url in "${GB_URLS[@]}"; do
    rm -rf "$dest" && mkdir -p "$dest" || return 1
    status_set "$(T "download" "下载") ${GB_TAR}"
    stream_extract "$url" "$dest" 2>"$WORKDIR/dl.err" &
    BG_PID=$!
    while kill -0 "$BG_PID" 2>/dev/null; do
      kb="$(du -sk "$dest" 2>/dev/null)"; kb="${kb%%[[:space:]]*}"
      status_set "$(T "download + unpack" "下载并解压") $(( ${kb:-0} / 1024 )) MiB"
      sleep 0.5
    done
    wait "$BG_PID"; rc=$?
    BG_PID=""
    found=""
    if [[ $rc -eq 0 ]]; then
      if [[ -f "$dest/${GB_BIN}" ]]; then found="$dest"
      else
        found="$(find "$dest" -maxdepth 3 -type f -name "$GB_BIN" 2>/dev/null | head -n 1)"
        found="${found%/*}"
      fi
    fi
    if [[ -n "$found" ]]; then
      find "$found" -maxdepth 1 -type f -name 'geekbench*' -exec chmod +x {} + 2>/dev/null || true
      GB_DEST="$found"
      break
    fi
    warn "$(T "Download failed from ${url%%/Geekbench-*}, trying next mirror…" "从 ${url%%/Geekbench-*} 下载失败，尝试下一个镜像…")"
  done

  if [[ -z "$GB_DEST" ]]; then
    err "$(T "Could not download ${GB_LABEL} (${GB_TAR})." "无法下载 ${GB_LABEL}（${GB_TAR}）。")"
    if [[ -s "$WORKDIR/dl.err" ]]; then
      info "  $(grep -m 1 '^curl:' "$WORKDIR/dl.err" || tail -n 1 "$WORKDIR/dl.err")"
    fi
    return 1
  fi

  # Optional unlock: ./geekbench.license (email on line 1, key on line 2) or env.
  local email="${GEEKBENCH_EMAIL:-}" key="${GEEKBENCH_KEY:-}"
  if [[ -z "$email" && -f geekbench.license ]]; then
    email="$(sed -n 1p geekbench.license)"; key="$(sed -n 2p geekbench.license)"
  fi
  if [[ -n "$email" && -n "$key" ]]; then
    "$GB_DEST/${GB_BIN}" --unlock "$email" "$key" </dev/null >/dev/null 2>&1 || true
  fi
  return 0
}

# ---------- score parsing ----------
# Tokenize HTML / markdown / CLI text and pair each score label with its
# number. Prints "single multi" ("-" when unknown).
#
# Layouts handled:
#   score card   <div class='score'>1047</div><div class='note'>Single-Core Score</div>
#   table row    <th>Single-Core Score</th><th class='score'>1047</th>   | Single-Core Score | 1047 |
#   CLI summary  "  Single-Core Score             1047"
# A number *before* the label (score card) outranks one after it, and the
# card + table agree, so the neighbouring score can never be picked.
# POSIX awk only (mawk 1.3.3 has no {m,n} intervals).
parse_scores_file() {
  awk '
    function isnum(t) { gsub(/,/, "", t); return t ~ /^[0-9]+$/ && length(t) <= 7 && t + 0 > 0 }
    function vote(kind, t, w) { gsub(/,/, "", t); if (isnum(t)) V[kind, t + 0] += w }
    function best(kind,   key, parts, v, bv, bw) {
      bw = 0; bv = "-"
      for (key in V) {
        split(key, parts, SUBSEP)
        if (parts[1] != kind) continue
        v = parts[2]
        if (V[key] > bw) { bw = V[key]; bv = v }
      }
      return bv
    }
    { buf = buf "\n" $0 }
    END {
      s = buf
      gsub(/\r/, "", s)
      gsub(/<[^>]*>/, "\n", s)
      gsub(/\|/, "\n", s)
      gsub(/&nbsp;/, " ", s)
      n = split(s, raw, "\n")
      k = 0
      for (i = 1; i <= n; i++) {
        t = raw[i]
        gsub(/[*_`#]/, "", t)
        gsub(/[ \t]+/, " ", t)
        sub(/^ /, "", t); sub(/ $/, "", t)
        if (t == "" || t ~ /^:?-+:?$/) continue
        tok[++k] = t
      }
      for (i = 1; i <= k; i++) {
        t = tolower(tok[i])
        for (j = 1; j <= 2; j++) {
          kind = (j == 1) ? "single" : "multi"
          lab = kind "[- ]?core score"
          if (t ~ ("^" lab "$")) {
            if (i > 1) vote(kind, tok[i - 1], 1.5)
            if (i < k) vote(kind, tok[i + 1], 1)
          } else if (t ~ ("^[0-9,]+ " lab "$")) {
            v = t; sub(/ .*/, "", v); vote(kind, v, 3)
          } else if (t ~ ("^" lab " ?:? ?[0-9,]+$")) {
            v = t; sub(/.*[^0-9,]/, "", v); vote(kind, v, 3)
          }
        }
      }
      print best("single"), best("multi")
    }
  ' "$1" 2>/dev/null
}

# Raw result JSON (.gb5/.gb6): top-level "score" and "multicore_score".
parse_scores_json() {
  local f="$1"
  if need_cmd python3; then
    python3 -I - "$f" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    s, m = int(d.get("score") or 0), int(d.get("multicore_score") or 0)
    print(s or "-", m or "-")
except Exception:
    print("- -")
PY
  elif need_cmd jq; then
    jq -r '[(.score // "-"), (.multicore_score // "-")] | map(tostring) | join(" ")' "$f" 2>/dev/null || echo "- -"
  else
    echo "- -"
  fi
}

# catbash.net/api/gb answer: {"ok":true,"single":1234,"multi":5678,...}
parse_scores_api() {
  local s m
  s="$(grep -oE '"single"[[:space:]]*:[[:space:]]*[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | head -n 1)"
  m="$(grep -oE '"multi"[[:space:]]*:[[:space:]]*[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | head -n 1)"
  echo "${s:--} ${m:--}"
}

# HTTP GET into $2; sets HTTP_CODE ("000" = no connection).
# mode: gb (plain curl, like yabs) | browser | api | jina
http_get() {
  local url="$1" out="$2" mode="$3" tmo="$4"
  local -a a=(-sS -L -o "$out" -w '%{http_code}' --connect-timeout 8 --max-time "$tmo")
  case "$mode" in
    gb)      [[ -n "$CURL_IPV" ]] && a+=("$CURL_IPV") ;;
    browser) [[ -n "$CURL_IPV" ]] && a+=("$CURL_IPV")
             a+=(-A "$UA_BROWSER"
                 -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
                 -H 'Accept-Language: en-US,en;q=0.9') ;;
    api)     a+=(-A "$UA_CPUX" -H 'Accept: application/json') ;;
    jina)    a+=(-A "$UA_CPUX" -H 'X-No-Cache: true' -H 'X-Timeout: 25')
             [[ -n "${JINA_API_KEY:-}" ]] && a+=(-H "Authorization: Bearer ${JINA_API_KEY}") ;;
  esac
  : >"$out"
  if need_cmd curl; then
    HTTP_CODE="$(curl "${a[@]}" "$url" </dev/null 2>/dev/null)" || true
  else
    local -a w=(-q -T "$tmo" -O "$out")
    [[ "$mode" == browser ]] && w+=(-U "$UA_BROWSER")
    if wget "${w[@]}" "$url" </dev/null 2>/dev/null; then HTTP_CODE=200; else HTTP_CODE=000; fi
  fi
  [[ "$HTTP_CODE" =~ ^[0-9]{3}$ ]] || HTTP_CODE="000"
}

# Short reason for a failed fetch (for the final diagnostic line).
classify_fetch() {
  local code="$1" f="$2" cf=0
  grep -qiE 'just a moment|cf-chl|challenge-platform|attention required|cf-browser-verification' "$f" 2>/dev/null && cf=1
  case "$code" in
    000) printf 'unreachable' ;;
    404) printf '404 not ready' ;;
    429) printf '429 rate-limited' ;;
    200) if ((cf)); then printf 'cloudflare challenge'; else printf 'no scores on page'; fi ;;
    *)   if ((cf)); then printf '%s cloudflare' "$code"; else printf 'HTTP %s' "$code"; fi ;;
  esac
}

merge_scores() { # merge "s m" pair into SCORE_SINGLE/SCORE_MULTI; 0 when complete
  local s="$1" m="$2"
  [[ "$s" =~ ^[0-9]+$ && -z "$SCORE_SINGLE" ]] && SCORE_SINGLE="$s"
  [[ "$m" =~ ^[0-9]+$ && -z "$SCORE_MULTI" ]] && SCORE_MULTI="$m"
  [[ -n "$SCORE_SINGLE" && -n "$SCORE_MULTI" ]]
}

# fetch_scores URL [local_output_file]
# Sets SCORE_SINGLE SCORE_MULTI SCORE_SRC FETCH_NOTE. Returns 0 when both found.
fetch_scores() {
  local url="${1%/}" local_out="${2:-}"
  local deadline=$((SECONDS + FETCH_BUDGET)) attempt=0 nap left tmo
  local page="${WORKDIR:-${TMPDIR:-/tmp}}/cpux-page.$$" s m why gbv
  local -A dead=() last=()
  SCORE_SINGLE=""; SCORE_MULTI=""; SCORE_SRC=""; FETCH_NOTE=""
  gbv="$(printf '%s' "$url" | grep -oE '/v[0-9]+/' | tr -dc '0-9')"

  # 1) licensed builds print a summary locally
  if [[ -n "$local_out" && -s "$local_out" ]]; then
    read -r s m < <(parse_scores_file "$local_out")
    if merge_scores "$s" "$m"; then SCORE_SRC="local"; return 0; fi
  fi
  [[ -z "$SCORE_API" ]] && dead[api]=1
  [[ -z "$JINA_PREFIX" ]] && dead[jina]=1

  # try_src NAME URL MODE TIMEOUT PARSER
  try_src() {
    local name="$1" u="$2" mode="$3" t="$4" parser="$5"
    [[ -n "${dead[$name]:-}" ]] && return 1
    left=$((deadline - SECONDS)); ((left < 3)) && return 1
    ((t > left)) && t=$left
    status_set "$(T "fetch scores" "获取分数") #${attempt} · ${name}"
    http_get "$u" "$page" "$mode" "$t"
    if [[ "$HTTP_CODE" == 200 ]]; then
      read -r s m < <("$parser" "$page")
      if merge_scores "$s" "$m"; then SCORE_SRC="$name"; return 0; fi
    fi
    why="$(classify_fetch "$HTTP_CODE" "$page")"
    last[$name]="$why"
    # Stop hammering sources that will not change their mind soon.
    case "$name:$why" in
      gb:*cloudflare*|browser:*cloudflare*|gb:HTTP\ 403|browser:HTTP\ 403) dead[$name]=1 ;;
      api:404*|api:unreachable|api:HTTP*) dead[$name]=1 ;;
      jina:unreachable|json:*) dead[$name]=1 ;;
    esac
    return 1
  }

  while ((SECONDS < deadline)); do
    attempt=$((attempt + 1))
    try_src gb      "$url" gb      15 parse_scores_file && break
    try_src browser "$url" browser 15 parse_scores_file && break
    if ((attempt == 1)) && [[ -n "$gbv" && -z "${dead[gb]:-}" ]] && { need_cmd python3 || need_cmd jq; }; then
      try_src json "${url}.gb${gbv}" gb 15 parse_scores_json && break
    fi
    try_src api  "${SCORE_API}?url=${url}" api 30 parse_scores_api && break
    try_src jina "${JINA_PREFIX}${url}"    jina 35 parse_scores_file && break
    # back off: 3, 6, 9 … capped at 15 s, never past the deadline
    nap=$((attempt * 3)); ((nap > 15)) && nap=15
    left=$((deadline - SECONDS)); ((left <= 3)) && break
    ((nap > left - 3)) && nap=$((left - 3))
    status_set "$(T "waiting for result page" "等待结果页") ${nap}s"
    sleep "$nap"
  done
  unset -f try_src
  rm -f "$page"

  if [[ -n "$SCORE_SINGLE" && -n "$SCORE_MULTI" ]]; then return 0; fi
  local k note=""
  for k in gb browser json api jina; do
    [[ -n "${last[$k]:-}" ]] && note+="${note:+ · }${k}: ${last[$k]}"
  done
  FETCH_NOTE="$note"
  return 1
}

# ---------- spinner ----------
# One live line: [|] GB6  1m23s  Multi-Core 7/15 · Navigation
# Forks only `sleep`; reads the status file with the read builtin.
start_spinner() {
  local label="$1"
  if [[ ! -t 1 ]]; then
    say "· ${label}"
    return 0
  fi
  local cols
  cols="$(tput cols 2>/dev/null || echo 80)"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  (
    trap 'exit 0' TERM
    local frames='|/-\' i=0 t0=$SECONDS detail="" line="" room
    room=$((cols - ${#label} - 16)); ((room < 10)) && room=10
    printf '\033[?25l'
    while :; do
      if [[ -r "$STATUS_FILE" ]] && IFS= read -r line <"$STATUS_FILE" && [[ -n "$line" ]]; then
        detail="$line"
      fi
      fmt_dur $((SECONDS - t0))
      printf '\r%s[%s]%s %s  %s%6s%s  %s\033[K' \
        "$C_ACC" "${frames:i % 4:1}" "$NC" "$label" "$C_DIM" "$DUR" "$NC" "${detail:0:room}"
      i=$((i + 1))
      sleep 0.25
    done
  ) &
  SPINNER_PID=$!
}

# ---------- results ----------
record_result() { # suite build status single multi url claim secs note
  R_SUITE+=("$1"); R_BUILD+=("$2"); R_STATUS+=("$3"); R_SINGLE+=("${4:--}")
  R_MULTI+=("${5:--}"); R_URL+=("${6:--}"); R_CLAIM+=("${7:--}"); R_SECS+=("${8:-0}"); R_NOTE+=("${9:-}")
}

score_cell() { # colored score or warning dash
  if [[ "$1" =~ ^[0-9]+$ ]]; then printf '%s%s%s' "${C_OK}${BOLD}" "$1" "$NC"
  else printf '%s%s%s' "$C_WARN" "-" "$NC"; fi
}

# Vertical report (single suite) — yabs-style.
print_suite_detail() {
  local i="$1"
  local name="Geekbench ${R_SUITE[$i]#GB}"
  [[ "${R_BUILD[$i]}" != "-" ]] && name="Geekbench ${R_BUILD[$i]}"
  fmt_dur "${R_SECS[$i]}"
  say ""
  say "${C_BAR}${name} Benchmark Test:${NC}"
  say "${C_BAR}---------------------------------${NC}"
  # ASCII labels on purpose: printf pads by bytes, so CJK would misalign.
  printf '%-16s | %s\n' "Test" "Value"
  printf '%-16s | %s\n' "----------------" "----------------------------------------"
  [[ "${R_STATUS[$i]}" != "OK" ]] && printf '%-16s | %s%s%s\n' "Status" "$C_ERR" "${R_STATUS[$i]}" "$NC"
  printf '%-16s | %s\n' "Single Core" "$(score_cell "${R_SINGLE[$i]}")"
  printf '%-16s | %s\n' "Multi Core" "$(score_cell "${R_MULTI[$i]}")"
  [[ "${R_URL[$i]}" != "-" ]] && printf '%-16s | %s\n' "Full Test" "${R_URL[$i]}"
  [[ "${R_CLAIM[$i]}" != "-" ]] && printf '%-16s | %s\n' "Claim" "${R_CLAIM[$i]}"
  [[ "${R_SECS[$i]}" -gt 0 ]] && printf '%-16s | %s\n' "Duration" "$DUR"
  [[ "${R_STATUS[$i]}" != "OK" && -n "${R_NOTE[$i]}" ]] && printf '%-16s | %s%s%s\n' "Note" "$C_DIM" "${R_NOTE[$i]}" "$NC"
  say ""
}

# Compact row (multi-suite run).
print_suite_row() {
  local i="$1"
  fmt_dur "${R_SECS[$i]}"
  if [[ "${R_STATUS[$i]}" == "OK" || "${R_STATUS[$i]}" == "PARTIAL" ]]; then
    printf '  %s%-4s%s  Single %s%-7s%s Multi %s%-7s%s %s%s%s\n' \
      "$BOLD" "${R_SUITE[$i]}" "$NC" \
      "${C_OK}${BOLD}" "${R_SINGLE[$i]}" "$NC" "${C_OK}${BOLD}" "${R_MULTI[$i]}" "$NC" "$C_DIM" "$DUR" "$NC"
  else
    printf '  %s%-4s%s  %s%s%s  %s%s%s\n' "$BOLD" "${R_SUITE[$i]}" "$NC" "$C_ERR" "${R_STATUS[$i]}" "$NC" "$C_DIM" "$DUR" "$NC"
  fi
  [[ "${R_URL[$i]}" != "-" ]] && printf '        %s\n' "${R_URL[$i]}"
  return 0
}

print_summary() {
  local n=${#R_SUITE[@]} i
  ((n > 1)) || { [[ "$PLAN_TOTAL" -le 1 ]] && return 0; }
  ((n > 0)) || return 0
  say ""
  say "${C_BAR}── $(T "Summary" "汇总") ──────────────────────────────────────${NC}"
  printf '  %-6s %8s %8s %8s  %s\n' "Suite" "Single" "Multi" "Time" "Report"
  printf '  %-6s %8s %8s %8s  %s\n' "------" "--------" "--------" "--------" "------"
  for ((i = 0; i < n; i++)); do
    fmt_dur "${R_SECS[$i]}"
    if [[ "${R_STATUS[$i]}" == "OK" || "${R_STATUS[$i]}" == "PARTIAL" ]]; then
      printf '  %-6s %s%8s%s %s%8s%s %8s  %s\n' "${R_SUITE[$i]}" \
        "$C_OK" "${R_SINGLE[$i]}" "$NC" "$C_OK" "${R_MULTI[$i]}" "$NC" "$DUR" "${R_URL[$i]}"
    else
      printf '  %-6s %s%8s%s %8s %8s  %s\n' "${R_SUITE[$i]}" "$C_ERR" "${R_STATUS[$i]}" "$NC" "-" "$DUR" "${R_URL[$i]}"
    fi
  done
  fmt_dur $((SECONDS - RUN_START))
  printf '  %s%s%s %s · %d %s' "$C_DIM" "$(T "Total" "合计")" "$NC" "$DUR" "$n" "$(T "suites" "项")"
  [[ "$CLAIM_SAVED" -eq 1 ]] && printf ' · claim → ./geekbench_claim.url'
  printf '\n\n'
}

json_str() {
  local s="$1"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/}
  printf '"%s"' "$s"
}
json_num() { if [[ "$1" =~ ^[0-9]+$ ]]; then printf '%s' "$1"; else printf 'null'; fi; }
json_url() { if [[ "$1" == "-" || -z "$1" ]]; then printf 'null'; else json_str "$1"; fi; }

emit_json() {
  local i n=${#R_SUITE[@]} sep=""
  {
    printf '{"tool":"cpux","version":%s,"time":%s,' "$(json_str "$VERSION")" "$(json_str "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    printf '"system":{"cpu":%s,"cores":%s,"ram_mib":%s,"swap_mib":%s,"arch":%s,"virt":%s,"os":%s},' \
      "$(json_str "$SYS_CPU")" "$(json_num "$SYS_CORES")" "$(json_num "$SYS_MEM_MIB")" "$(json_num "$SYS_SWAP_MIB")" \
      "$(json_str "$(uname -m)")" "$(json_str "$SYS_VIRT")" "$(json_str "$SYS_OS")"
    printf '"geekbench":['
    for ((i = 0; i < n; i++)); do
      printf '%s{"suite":%s,"build":%s,"status":%s,"single":%s,"multi":%s,"url":%s,"claim":%s,"seconds":%s,"note":%s}' \
        "$sep" "$(json_str "${R_SUITE[$i]}")" "$(json_str "${R_BUILD[$i]}")" "$(json_str "${R_STATUS[$i]}")" \
        "$(json_num "${R_SINGLE[$i]}")" "$(json_num "${R_MULTI[$i]}")" "$(json_url "${R_URL[$i]}")" \
        "$(json_url "${R_CLAIM[$i]}")" "$(json_num "${R_SECS[$i]}")" "$(json_str "${R_NOTE[$i]}")"
      sep=","
    done
    printf ']}\n'
  } >&3
}

emit_suite_result() {
  local i=$((${#R_SUITE[@]} - 1))
  if [[ "$PLAN_TOTAL" -le 1 ]]; then print_suite_detail "$i"; else print_suite_row "$i"; fi
}

retry_hint() {
  info "  $(T "Scores may appear later. Retry with:" "分数可能稍后才可用，可重试:")"
  info "  curl -sL https://ba.sh/cpux | bash -s -- --fetch $1"
}

# ---------- one suite ----------
# Watch Geekbench output: "Single-Core 4 · Navigation", "Multi-Core 7/15 · …"
gb_progress() {
  awk '
    /^Single-Core *$/ { ph = "Single-Core"; n = 0; next }
    /^Multi-Core *$/  { ph = "Multi-Core"; total = n; n = 0; next }
    /^ *Running /     { n++; w = $0; sub(/^ *Running /, "", w); next }
    /^Uploading/      { ph = "upload"; next }
    END {
      if (ph == "upload") print "uploading results"
      else if (ph == "") print (w != "" ? w : "starting")
      else if (total > 0) printf "%s %d/%d · %s\n", ph, n, total, w
      else printf "%s %d · %s\n", ph, n, w
    }
  ' "$1" 2>/dev/null
}

run_gb() {
  local ver="$1" out log start label rc url claim status note prog
  PLAN_INDEX=$((PLAN_INDEX + 1))
  setup_gb_meta "$ver" || return 1

  STATUS_FILE="$WORKDIR/gb${ver}.status"
  out="$WORKDIR/gb${ver}.out"
  log="$WORKDIR/gb${ver}.log"
  : >"$out"; : >"$STATUS_FILE"

  label="GB${ver}"
  [[ "$PLAN_TOTAL" -gt 1 ]] && label="[${PLAN_INDEX}/${PLAN_TOTAL}] GB${ver}"
  start=$SECONDS
  start_spinner "$label"

  if ! download_and_extract "$ver"; then
    stop_spinner
    record_result "GB${ver}" "$GB_BUILD" "FAIL" - - - - $((SECONDS - start)) "download failed"
    emit_suite_result
    return 1
  fi

  status_set "$(T "starting benchmark" "开始跑分")"
  ( cd "$GB_DEST" && exec "./${GB_BIN}" --cpu ) </dev/null >"$out" 2>"$log" &
  GB_PID=$!
  local phase="" last_phase=""
  while kill -0 "$GB_PID" 2>/dev/null; do
    prog="$(gb_progress "$out")"
    if [[ -n "$prog" ]]; then
      status_set "$prog"
      # Without a spinner, log each phase once so CI/cron logs show progress.
      if [[ ! -t 1 ]]; then
        phase="${prog%% *}"
        if [[ "$phase" == Single-Core || "$phase" == Multi-Core || "$phase" == uploading ]] \
           && [[ "$phase" != "$last_phase" ]]; then
          info "  ${label}: ${phase}"
          last_phase="$phase"
        fi
      fi
    fi
    sleep 1
  done
  wait "$GB_PID"; rc=$?
  GB_PID=""

  url="$(grep -oE 'https://browser\.geekbench\.com/v[0-9]+/cpu/[0-9]+' "$out" | head -n 1)"
  claim="$(grep -oE 'https://browser\.geekbench\.com/v[0-9]+/cpu/[0-9]+/claim\?key=[0-9]+' "$out" | head -n 1)"

  if [[ -z "$url" ]]; then
    # Licensed builds don't upload by default but print scores.
    read -r SCORE_SINGLE SCORE_MULTI < <(parse_scores_file "$out")
    if [[ "$SCORE_SINGLE" =~ ^[0-9]+$ && "$SCORE_MULTI" =~ ^[0-9]+$ ]]; then
      stop_spinner
      record_result "GB${ver}" "$GB_BUILD" "OK" "$SCORE_SINGLE" "$SCORE_MULTI" - - $((SECONDS - start)) "local"
      emit_suite_result
      cleanup_suite "$ver"
      return 0
    fi
    stop_spinner
    if [[ $rc -ne 0 ]]; then
      status="FAIL"; note="exit code ${rc}"
      ((rc == 137)) && note="killed (out of memory?)"
    else
      status="NO_URL"; note="upload failed"
    fi
    err "$(T "${GB_LABEL}: ${note} — no result URL." "${GB_LABEL}: ${note} — 没有结果链接。")"
    # Surface Geekbench's own last words (upload errors, missing libs …).
    local reason
    reason="$(cat "$out" "$log" 2>/dev/null | grep -iE 'error|fail|unable|denied|not found|cannot' | tail -n 3)"
    [[ -n "$reason" ]] && while IFS= read -r l; do info "  ${l}"; done <<<"$reason"
    record_result "GB${ver}" "$GB_BUILD" "$status" - - - - $((SECONDS - start)) "$note"
    emit_suite_result
    cleanup_suite "$ver"
    return 1
  fi

  if [[ -n "$claim" ]] && printf '%s\n' "$claim" >>./geekbench_claim.url 2>/dev/null; then CLAIM_SAVED=1; fi

  status_set "$(T "fetch scores" "获取分数")"
  fetch_scores "$url" "$out"
  stop_spinner
  status="OK"; note="${SCORE_SRC}"
  if [[ -z "$SCORE_SINGLE" || -z "$SCORE_MULTI" ]]; then
    status="PARTIAL"; note="$FETCH_NOTE"
    warn "$(T "GB${ver}: could not read scores (${FETCH_NOTE:-timeout})." "GB${ver}: 未能读取分数（${FETCH_NOTE:-超时}）。")"
  fi
  record_result "GB${ver}" "$GB_BUILD" "$status" "$SCORE_SINGLE" "$SCORE_MULTI" "$url" "${claim:--}" $((SECONDS - start)) "$note"
  emit_suite_result
  [[ "$status" == PARTIAL ]] && retry_hint "$url"
  cleanup_suite "$ver"
  return 0
}

# Free disk between suites unless --keep.
cleanup_suite() {
  [[ "$KEEP_FILES" -eq 1 ]] && return 0
  rm -rf "${WORKDIR:?}/gb$1" 2>/dev/null || true
}

# ---------- --fetch mode ----------
run_fetch_only() {
  local u i=0 rc=0 suite
  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/cpux.XXXXXX")" || return 1
  STATUS_FILE="$WORKDIR/fetch.status"
  RUN_START=$SECONDS
  for u in "${FETCH_URLS[@]}"; do
    i=$((i + 1))
    if [[ ! "$u" =~ ^https://browser\.geekbench\.com/v[0-9]+/cpu/[0-9]+/?$ ]]; then
      err "$(T "Not a Geekbench CPU result URL: $u" "不是 Geekbench CPU 结果链接: $u")"
      rc=1; continue
    fi
    u="${u%/}"
    suite="GB$(printf '%s' "$u" | grep -oE '/v[0-9]+/' | tr -dc '0-9')"
    PLAN_INDEX=$i
    start_spinner "$suite"
    if fetch_scores "$u"; then
      stop_spinner
      record_result "$suite" "-" "OK" "$SCORE_SINGLE" "$SCORE_MULTI" "$u" - 0 "$SCORE_SRC"
    else
      stop_spinner
      record_result "$suite" "-" "PARTIAL" "$SCORE_SINGLE" "$SCORE_MULTI" "$u" - 0 "$FETCH_NOTE"
      warn "$(T "Could not read scores (${FETCH_NOTE:-timeout})." "未能读取分数（${FETCH_NOTE:-超时}）。")"
      rc=1
    fi
    emit_suite_result
  done
  print_summary
  [[ "$JSON_MODE" -eq 1 ]] && emit_json
  return "$rc"
}

# ---------- menu / args ----------
print_menu() {
  print_sysinfo
  say ""
  say "  ${C_ACC}1${NC}  Geekbench 5   ${C_DIM}${GB5_VER}${NC}"
  say "  ${C_ACC}2${NC}  Geekbench 6   ${C_DIM}${GB6_VER}${NC}"
  say "  ${C_ACC}3${NC}  Geekbench 7   ${C_DIM}${GB7_VER}${NC}"
  say "  ${C_ACC}4${NC}  $(T "All" "全部")          ${C_DIM}5 → 6 → 7${NC}"
  say "  ${C_ACC}0${NC}  $(T "Exit" "退出")"
  say ""
  say "  ${C_DIM}$(T "Tip: combine, e.g. \"1 2\" for GB5 + GB6" "提示：可组合，如 \"1 2\" 运行 GB5 + GB6")${NC}"
  say ""
}

# Returns 0 if something was selected, 2 for exit.
apply_menu_choice() {
  local c="$1" w picked=0
  c="${c//,/ }"
  for w in $c; do
    case "${w,,}" in
      1|5|gb5) DO_GB5=1; picked=1 ;;
      2|6|gb6) DO_GB6=1; picked=1 ;;
      3|7|gb7) DO_GB7=1; picked=1 ;;
      4|a|all) DO_GB5=1; DO_GB6=1; DO_GB7=1; picked=1 ;;
      0|q|quit|exit) return 2 ;;
      *) DO_GB5=0; DO_GB6=0; DO_GB7=0; return 1 ;;
    esac
  done
  ((picked)) && return 0
  return 1
}

interactive_menu() {
  local tries=0 rc
  if ! have_tty; then
    info "$(T "No interactive terminal — running the default suite (Geekbench 6). Pass 5|6|7|all to choose." \
              "无交互终端 — 运行默认项目（Geekbench 6）。可传 5|6|7|all 指定。")"
    DO_GB6=1
    return 0
  fi
  clear_screen
  print_menu
  while ((tries < 3)); do
    read_tty "  $(T "Select [1/2/3/4/0]: " "请选择 [1/2/3/4/0]: ")"
    apply_menu_choice "$REPLY_TEXT"; rc=$?
    case $rc in
      0) return 0 ;;
      2) info "$(T "Bye." "再见。")"; exit 0 ;;
    esac
    tries=$((tries + 1))
    warn "$(T "Invalid choice: '${REPLY_TEXT}'" "无效选项: '${REPLY_TEXT}'")"
  done
  return 1
}

parse_args() {
  local a
  for a in "$@"; do [[ "$a" == "-cn" || "$a" == "--chinese" ]] && LANG_MODE="zh"; done
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -v|--version) echo "CPUX v${VERSION}"; exit 0 ;;
      -y|--yes) AUTO_YES=1 ;;
      -k|--keep) KEEP_FILES=1 ;;
      -j|--json) JSON_MODE=1 ;;
      --no-clear) NO_CLEAR=1 ;;
      --no-color) NO_COLOR_FLAG=1 ;;
      -cn|--chinese) LANG_MODE="zh" ;;
      -us|--english) LANG_MODE="en" ;;
      -5|--gb5|5|gb5) DO_GB5=1 ;;
      -6|--gb6|6|gb6) DO_GB6=1 ;;
      -7|--gb7|7|gb7) DO_GB7=1 ;;
      -a|--all|all|567) DO_GB5=1; DO_GB6=1; DO_GB7=1 ;;
      --fetch-timeout) FETCH_BUDGET="${2:-}"; shift
        [[ "$FETCH_BUDGET" =~ ^[0-9]+$ ]] || { usage >&2; exit 1; } ;;
      --fetch-timeout=*) FETCH_BUDGET="${1#*=}"
        [[ "$FETCH_BUDGET" =~ ^[0-9]+$ ]] || { usage >&2; exit 1; } ;;
      --fetch) shift
        while [[ $# -gt 0 && "$1" != -* ]]; do FETCH_URLS+=("$1"); shift; done
        ((${#FETCH_URLS[@]})) || { echo "--fetch needs a result URL" >&2; exit 1; }
        continue ;;
      *) echo "$(T "Unknown argument: $1" "未知参数: $1")" >&2; usage >&2; exit 1 ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  # --json: human output goes to stderr, JSON to the original stdout (fd 3).
  if [[ "$JSON_MODE" -eq 1 ]]; then exec 3>&1 1>&2; else exec 3>&1; fi
  setup_colors
  export LC_ALL=C
  trap cleanup EXIT
  trap 'on_interrupt 130' INT
  trap 'on_interrupt 143' TERM

  if ! need_cmd curl && ! need_cmd wget; then
    err "$(T "Need curl or wget." "需要 curl 或 wget。")"; exit 1
  fi
  collect_sysinfo

  if ((${#FETCH_URLS[@]})); then
    probe_ipv4 || true
    run_fetch_only
    exit $?
  fi

  need_cmd tar || { err "$(T "Missing required tool: tar" "缺少必要工具: tar")"; exit 1; }
  detect_arch || exit 1

  if [[ $((DO_GB5 + DO_GB6 + DO_GB7)) -eq 0 ]]; then
    interactive_menu || exit 1
  fi
  PLAN_TOTAL=$((DO_GB5 + DO_GB6 + DO_GB7))

  clear_screen
  print_sysinfo
  local plan=""
  [[ "$DO_GB5" -eq 1 ]] && plan+="GB5 → "
  [[ "$DO_GB6" -eq 1 ]] && plan+="GB6 → "
  [[ "$DO_GB7" -eq 1 ]] && plan+="GB7 → "
  say "${C_DIM}$(T "Plan" "计划")${NC} ${plan% → }"
  preflight_warnings
  check_network || exit 1

  local base
  base="$(pick_workdir_base)" || { err "$(T "No writable work directory." "没有可写的工作目录。")"; exit 1; }
  WORKDIR="$(mktemp -d "${base%/}/cpux.XXXXXX")" || { err "mktemp failed in ${base}"; exit 1; }
  [[ "$KEEP_FILES" -eq 1 ]] && info "$(T "Keep:" "保留:") $WORKDIR"
  say ""

  RUN_START=$SECONDS
  local failed=0
  # Strictly sequential — concurrent runs would wreck multi-core scores.
  [[ "$DO_GB5" -eq 1 ]] && { run_gb 5 || failed=1; }
  [[ "$DO_GB6" -eq 1 ]] && { run_gb 6 || failed=1; }
  [[ "$DO_GB7" -eq 1 ]] && { run_gb 7 || failed=1; }

  print_summary
  [[ "$JSON_MODE" -eq 1 ]] && emit_json
  [[ "$KEEP_FILES" -eq 1 ]] && info "$(T "Files kept:" "文件保留:") $WORKDIR"

  local i
  for ((i = 0; i < ${#R_STATUS[@]}; i++)); do
    [[ "${R_STATUS[$i]}" == OK ]] || failed=1
  done
  if [[ "$failed" -ne 0 ]]; then
    warn "$(T "Finished with errors." "完成（有失败项）。")"
    exit 1
  fi
  exit 0
}

main "$@"
