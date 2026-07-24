#!/usr/bin/env bash
#
# CPUX — CPU eXaminer (Geekbench 5 / 6 / 7)
# Sequential Geekbench CPU benchmarks with reliable single/multi-core scores.
#
# Usage:
#   curl -sL https://ba.sh/cpux | bash
#   curl -sL https://catbash.net/cpux | bash
#   ./cpux.sh                 # interactive menu
#   ./cpux.sh 5               # Geekbench 5 only
#   ./cpux.sh 6
#   ./cpux.sh 7
#   ./cpux.sh all             # 5 → 6 → 7 sequentially
#   ./cpux.sh -5 -6           # selected versions
#   ./cpux.sh all -y          # auto yes (non-interactive defaults)
#
# Design notes:
#   - Geekbench tryout CLI uploads results but does NOT print scores to stdout.
#   - browser.geekbench.com is Cloudflare-protected; plain curl/wget often blank.
#   - We fetch scores via multiple strategies (jina reader → direct HTML → retries).
#   - Inspired by i-abc/GB5 and masonr/yabs, with robust multi-core extraction.
#
set -uo pipefail

VERSION="1.1.1"

# Pin known-good Geekbench releases (update when new stable drops).
GB5_VER="5.5.1"
GB6_VER="6.7.1"
GB7_VER="7.0.0"

CDN_PRIMARY="https://cdn.geekbench.com"
CDN_MIRROR="https://asset.bash.icu/https://cdn.geekbench.com"

# Score fetch proxies / readers (first success wins)
JINA_PREFIXES=(
  "https://r.jina.ai/"
)

KEEP_FILES=0
AUTO_YES=0
LANG_MODE="en"   # en | zh
DO_GB5=0
DO_GB6=0
DO_GB7=0
INTERACTIVE_PICK=0
WORKDIR=""
RESULTS_TSV=""
STATUS_FILE=""
SPINNER_PID=""
PLAN_INDEX=0
PLAN_TOTAL=0
RUN_START_TS=0

# ---------- colors ----------
if [[ -t 1 ]]; then
  C_HDR=$'\033[1;38;5;222m'
  C_DIM=$'\033[2m'
  C_OK=$'\033[38;5;114m'
  C_ACC=$'\033[38;5;81m'
  C_BAR=$'\033[38;5;73m'
  C_ERR=$'\033[38;5;203m'
  C_WARN=$'\033[38;5;214m'
  NC=$'\033[0m'
  BOLD=$'\033[1m'
else
  C_HDR=""; C_DIM=""; C_OK=""; C_ACC=""; C_BAR=""; C_ERR=""; C_WARN=""; NC=""; BOLD=""
fi

err()  { printf '%b\n' "${C_ERR}$*${NC}" >&2; }
ok()   { printf '%b\n' "${C_OK}$*${NC}"; }
info() { printf '%b\n' "${C_DIM}$*${NC}" >&2; }
warn() { printf '%b\n' "${C_WARN}$*${NC}" >&2; }
hdr()  { printf '%b\n' "${C_HDR}$*${NC}" >&2; }

# Human duration: 129 → 2m09s
format_duration() {
  local s="${1:-0}"
  if [[ "$s" -ge 60 ]]; then
    printf '%dm%02ds' "$((s / 60))" "$((s % 60))"
  else
    printf '%ds' "$s"
  fi
}

# Clear terminal when interactive (works under curl|bash via /dev/tty).
clear_screen() {
  if [[ -w /dev/tty ]]; then
    printf '\033[2J\033[H' > /dev/tty 2>/dev/null || true
  elif [[ -t 1 ]]; then
    printf '\033[2J\033[H'
  fi
}

# Update spinner status line (overwritten, not scrolled).
status_set() {
  [[ -n "${STATUS_FILE:-}" ]] || return 0
  printf '%s\n' "$*" >"$STATUS_FILE"
}

# ---------- i18n helpers ----------
T() {
  # T en_text zh_text
  if [[ "$LANG_MODE" == "zh" ]]; then
    printf '%s' "${2:-$1}"
  else
    printf '%s' "$1"
  fi
}

usage() {
  cat <<EOF
CPUX v${VERSION} — CPU eXaminer (Geekbench 5 / 6 / 7)

$(T "Usage:" "用法:")
  $(basename "$0")                 $(T "Interactive menu" "交互菜单")
  $(basename "$0") 5|6|7           $(T "Run one Geekbench version" "运行单个版本")
  $(basename "$0") all             $(T "Run 5 → 6 → 7 sequentially" "依次运行 5 → 6 → 7")
  $(basename "$0") -5 -6 -7        $(T "Select versions (any combo)" "任选版本组合")
  $(basename "$0") -h | --help
  $(basename "$0") -v | --version

$(T "Options:" "参数:")
  -5, --gb5          Geekbench 5
  -6, --gb6          Geekbench 6
  -7, --gb7          Geekbench 7
  -a, --all          Geekbench 5 + 6 + 7 (sequential)
  -y, --yes          $(T "Non-interactive defaults" "非交互默认")
  -k, --keep         $(T "Keep downloaded binaries" "保留下载的二进制")
  -cn, --chinese     $(T "Chinese UI" "中文界面")
  -us, --english     $(T "English UI (default)" "英文界面（默认）")

$(T "One-liner:" "一键运行:")
  curl -sL https://ba.sh/cpux | bash
  curl -sL https://catbash.net/cpux | bash
  curl -sL https://ba.sh/cpux | bash -s -- all
  curl -sL https://ba.sh/cpux | bash -s -- 6
  curl -sL https://ba.sh/menu | bash -s -- cpux all

$(T "Docs:" "文档:")
  https://catbash.net/cpux.html
EOF
}

cleanup() {
  local rc=$?
  if [[ -n "${WORKDIR:-}" && -d "${WORKDIR:-}" && "$KEEP_FILES" -eq 0 ]]; then
    rm -rf "$WORKDIR" 2>/dev/null || true
  fi
  # stop spinner if any
  if [[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  return "$rc"
}
trap cleanup EXIT INT TERM

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Download URL to file; returns 0 on success.
dl() {
  local url="$1" out="$2"
  if need_cmd curl; then
    curl -fsSL --connect-timeout 15 --max-time 600 -o "$out" "$url"
  elif need_cmd wget; then
    wget -q -T 600 -O "$out" "$url"
  else
    err "$(T "Need curl or wget." "需要 curl 或 wget。")"
    return 1
  fi
}

# Fetch URL body to stdout (for score pages).
fetch_body() {
  local url="$1"
  if need_cmd curl; then
    curl -fsSL --connect-timeout 12 --max-time 45 \
      -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36" \
      -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
      -H "Accept-Language: en-US,en;q=0.9" \
      "$url" 2>/dev/null
  else
    wget -q -T 45 -O - "$url" 2>/dev/null
  fi
}

detect_arch() {
  local m bits
  m="$(uname -m)"
  bits="$(getconf LONG_BIT 2>/dev/null || echo 64)"
  if [[ "$bits" != "64" ]]; then
    err "$(T "Only 64-bit systems are supported." "仅支持 64 位系统。")"
    return 1
  fi
  case "$m" in
    x86_64|amd64) ARCH_KIND="x64" ;;
    aarch64|arm64) ARCH_KIND="arm64" ;;
    riscv64) ARCH_KIND="riscv64" ;;
    *)
      err "$(T "Unsupported architecture: $m" "不支持的架构: $m")"
      return 1
      ;;
  esac
  return 0
}

# Set package metadata for a Geekbench major version (5/6/7).
# Exports: GB_TAR GB_DIR GB_BIN GB_URLS[] GB_LABEL
setup_gb_meta() {
  local ver="$1"
  GB_URLS=()
  case "$ver" in
    5)
      GB_LABEL="Geekbench 5"
      GB_BIN="geekbench5"
      case "$ARCH_KIND" in
        x64)
          GB_TAR="Geekbench-${GB5_VER}-Linux.tar.gz"
          GB_DIR="Geekbench-${GB5_VER}-Linux"
          ;;
        arm64)
          GB_TAR="Geekbench-${GB5_VER}-LinuxARMPreview.tar.gz"
          GB_DIR="Geekbench-${GB5_VER}-LinuxARMPreview"
          ;;
        riscv64)
          GB_TAR="Geekbench-${GB5_VER}-LinuxRISCVPreview.tar.gz"
          GB_DIR="Geekbench-${GB5_VER}-LinuxRISCVPreview"
          ;;
      esac
      ;;
    6)
      GB_LABEL="Geekbench 6"
      GB_BIN="geekbench6"
      case "$ARCH_KIND" in
        x64)
          GB_TAR="Geekbench-${GB6_VER}-Linux.tar.gz"
          GB_DIR="Geekbench-${GB6_VER}-Linux"
          ;;
        arm64)
          GB_TAR="Geekbench-${GB6_VER}-LinuxARMPreview.tar.gz"
          GB_DIR="Geekbench-${GB6_VER}-LinuxARMPreview"
          ;;
        riscv64)
          GB_TAR="Geekbench-${GB6_VER}-LinuxRISCVPreview.tar.gz"
          GB_DIR="Geekbench-${GB6_VER}-LinuxRISCVPreview"
          ;;
      esac
      ;;
    7)
      GB_LABEL="Geekbench 7"
      GB_BIN="geekbench7"
      case "$ARCH_KIND" in
        x64)
          GB_TAR="Geekbench-${GB7_VER}-Linux.tar.gz"
          GB_DIR="Geekbench-${GB7_VER}-Linux"
          ;;
        arm64)
          GB_TAR="Geekbench-${GB7_VER}-LinuxARMPreview.tar.gz"
          GB_DIR="Geekbench-${GB7_VER}-LinuxARMPreview"
          ;;
        riscv64)
          GB_TAR="Geekbench-${GB7_VER}-LinuxRISCVPreview.tar.gz"
          GB_DIR="Geekbench-${GB7_VER}-LinuxRISCVPreview"
          ;;
      esac
      ;;
    *) return 1 ;;
  esac
  GB_URLS=(
    "${CDN_PRIMARY}/${GB_TAR}"
    "${CDN_MIRROR}/${GB_TAR}"
  )
}

check_ipv4_browser() {
  # browser.geekbench.com is IPv4-only; upload needs connectivity.
  # Note: CF may return 403 to bare curls — treat any TCP/TLS response as OK.
  local code=""
  if need_cmd curl; then
    code="$(curl -4 -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 15 \
      "https://cdn.geekbench.com/" 2>/dev/null || true)"
    if [[ -n "$code" && "$code" != "000" ]]; then
      return 0
    fi
    code="$(curl -4 -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 15 \
      "https://browser.geekbench.com/" 2>/dev/null || true)"
    if [[ -n "$code" && "$code" != "000" ]]; then
      return 0
    fi
  fi
  # soft-fail: still allow attempt
  warn "$(T "Could not preflight IPv4 to Geekbench CDN/Browser. Continuing anyway…" "无法预检 Geekbench CDN/Browser 的 IPv4 连通性，仍继续…")"
  return 0
}

check_memory() {
  local mem_mb
  mem_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "${mem_mb:-0}" -gt 0 && "${mem_mb}" -lt 900 ]]; then
    warn "$(T "Low RAM (${mem_mb} MiB). Geekbench 5/6/7 may fail without ≥1 GiB RAM+Swap." "内存较低（${mem_mb} MiB）。Geekbench 5/6/7 在内存+Swap < 1 GiB 时可能失败。")"
  fi
}

ensure_tools() {
  local missing=()
  need_cmd tar || missing+=("tar")
  need_cmd curl || need_cmd wget || missing+=("curl|wget")
  if ((${#missing[@]})); then
    err "$(T "Missing required tools: ${missing[*]}" "缺少必要工具: ${missing[*]}")"
    return 1
  fi
  return 0
}

# Sets GB_DEST to extracted directory path. Progress via status_set only.
download_and_extract() {
  local ver="$1"
  local dest="$WORKDIR/gb${ver}"
  local tarpath="$WORKDIR/${GB_TAR}"
  local url ok=0
  GB_DEST=""

  mkdir -p "$dest"
  if [[ -x "$dest/${GB_BIN}" ]]; then
    status_set "$(T "reuse binary" "复用二进制")"
    GB_DEST="$dest"
    return 0
  fi

  status_set "$(T "download" "下载") ${GB_TAR}"
  for url in "${GB_URLS[@]}"; do
    if dl "$url" "$tarpath"; then
      if [[ -s "$tarpath" ]]; then
        ok=1
        break
      fi
    fi
    rm -f "$tarpath" 2>/dev/null || true
  done
  if [[ "$ok" -ne 1 ]]; then
    err "$(T "Failed to download ${GB_LABEL}." "下载 ${GB_LABEL} 失败。")"
    return 1
  fi

  status_set "$(T "extract" "解压")"
  if ! tar -xzf "$tarpath" -C "$dest" --strip-components=1 2>/dev/null; then
    # some tarballs have a single top-level folder; extract then move
    rm -rf "${dest:?}/"* 2>/dev/null || true
    local tmpx="$WORKDIR/extract_${ver}"
    rm -rf "$tmpx"
    mkdir -p "$tmpx"
    tar -xzf "$tarpath" -C "$tmpx" || { err "$(T "Extract failed." "解压失败。")"; return 1; }
    if [[ -x "$tmpx/${GB_DIR}/${GB_BIN}" ]]; then
      mv "$tmpx/${GB_DIR}"/* "$dest/" 2>/dev/null || true
    elif [[ -x "$tmpx/${GB_BIN}" ]]; then
      mv "$tmpx"/* "$dest/" 2>/dev/null || true
    else
      # find binary
      local found
      found="$(find "$tmpx" -type f -name "$GB_BIN" 2>/dev/null | head -1)"
      if [[ -n "$found" ]]; then
        mv "$(dirname "$found")"/* "$dest/" 2>/dev/null || true
      else
        err "$(T "Could not locate ${GB_BIN} in archive." "归档中找不到 ${GB_BIN}。")"
        return 1
      fi
    fi
    rm -rf "$tmpx"
  fi

  if [[ ! -x "$dest/${GB_BIN}" ]]; then
    # binary might not have +x after extract
    chmod +x "$dest/${GB_BIN}" 2>/dev/null || true
  fi
  # companion workload binaries may also need +x
  find "$dest" -maxdepth 1 -type f -name 'geekbench*' -exec chmod +x {} \; 2>/dev/null || true

  if [[ ! -x "$dest/${GB_BIN}" ]]; then
    err "$(T "Binary not executable: $dest/${GB_BIN}" "二进制不可执行: $dest/${GB_BIN}")"
    return 1
  fi

  # unlock if license file present in CWD
  if [[ -f "geekbench.license" ]]; then
    local email key
    email="$(awk 'NR==1{print;exit}' geekbench.license)"
    key="$(awk 'NR==2{print;exit}' geekbench.license)"
    if [[ -n "$email" && -n "$key" ]]; then
      "$dest/${GB_BIN}" --unlock "$email" "$key" >/dev/null 2>&1 || true
    fi
  fi

  GB_DEST="$dest"
  return 0
}

# Parse single/multi scores from free-form text (jina markdown or HTML).
# Sets: PARSE_SINGLE PARSE_MULTI
parse_scores_text() {
  local text="$1"
  PARSE_SINGLE=""
  PARSE_MULTI=""

  # 1) Markdown table: | Single-Core Score | 1379 |
  PARSE_SINGLE="$(printf '%s' "$text" | grep -oiE '\|[[:space:]]*Single[- ]Core[[:space:]]+Score[[:space:]]*\|[[:space:]]*[0-9]{2,7}' \
    | head -1 | grep -oE '[0-9]{2,7}' | head -1 || true)"
  PARSE_MULTI="$(printf '%s' "$text" | grep -oiE '\|[[:space:]]*Multi[- ]Core[[:space:]]+Score[[:space:]]*\|[[:space:]]*[0-9]{2,7}' \
    | head -1 | grep -oE '[0-9]{2,7}' | head -1 || true)"

  # 2) Label then number on same/next lines
  if [[ -z "$PARSE_SINGLE" ]]; then
    PARSE_SINGLE="$(printf '%s' "$text" | tr '\n' ' ' | grep -oiE 'Single[- ]Core[[:space:]]+Score[^0-9]{0,40}[0-9]{2,7}' \
      | head -1 | grep -oE '[0-9]{2,7}' | tail -1 || true)"
  fi
  if [[ -z "$PARSE_MULTI" ]]; then
    PARSE_MULTI="$(printf '%s' "$text" | tr '\n' ' ' | grep -oiE 'Multi[- ]Core[[:space:]]+Score[^0-9]{0,40}[0-9]{2,7}' \
      | head -1 | grep -oE '[0-9]{2,7}' | tail -1 || true)"
  fi

  # 3) Number then label (jina block layout)
  if [[ -z "$PARSE_SINGLE" ]]; then
    PARSE_SINGLE="$(printf '%s\n' "$text" | awk '
      /^[0-9]{2,7}$/ { n=$0; getline; if ($0 ~ /Single[- ]Core/) { print n; exit } }
    ')"
  fi
  if [[ -z "$PARSE_MULTI" ]]; then
    PARSE_MULTI="$(printf '%s\n' "$text" | awk '
      /^[0-9]{2,7}$/ { n=$0; getline; if ($0 ~ /Multi[- ]Core/) { print n; exit } }
    ')"
  fi

  # 4) HTML: <div class='score'>1234</div>  (first=single, second=multi)
  if [[ -z "$PARSE_SINGLE" || -z "$PARSE_MULTI" ]]; then
    local scores
    scores="$(printf '%s' "$text" | grep -oE "class=['\"]score['\"][^>]*>[[:space:]]*[0-9]{2,7}" \
      | grep -oE '[0-9]{2,7}' || true)"
    if [[ -n "$scores" ]]; then
      local s1 s2
      s1="$(printf '%s\n' "$scores" | sed -n '1p')"
      s2="$(printf '%s\n' "$scores" | sed -n '2p')"
      [[ -z "$PARSE_SINGLE" && -n "$s1" ]] && PARSE_SINGLE="$s1"
      [[ -z "$PARSE_MULTI" && -n "$s2" ]] && PARSE_MULTI="$s2"
    fi
  fi

  # 5) span class='score' (GB4-style leftovers)
  if [[ -z "$PARSE_SINGLE" || -z "$PARSE_MULTI" ]]; then
    local scores
    scores="$(printf '%s' "$text" | grep -oE "class=['\"]score['\"][^>]*>[^<]*" \
      | grep -oE '[0-9]{2,7}' || true)"
    if [[ -n "$scores" ]]; then
      local s1 s2
      s1="$(printf '%s\n' "$scores" | sed -n '1p')"
      s2="$(printf '%s\n' "$scores" | sed -n '2p')"
      [[ -z "$PARSE_SINGLE" && -n "$s1" ]] && PARSE_SINGLE="$s1"
      [[ -z "$PARSE_MULTI" && -n "$s2" ]] && PARSE_MULTI="$s2"
    fi
  fi

  # sanitize
  [[ "$PARSE_SINGLE" =~ ^[0-9]+$ ]] || PARSE_SINGLE=""
  [[ "$PARSE_MULTI" =~ ^[0-9]+$ ]] || PARSE_MULTI=""
}

# Fetch scores for a public result URL. Retries until both scores or attempts exhausted.
# Sets: SCORE_SINGLE SCORE_MULTI
fetch_scores() {
  local result_url="$1"
  local attempts="${2:-8}"
  local i body prefix
  SCORE_SINGLE=""
  SCORE_MULTI=""

  for ((i=1; i<=attempts; i++)); do
    # A) jina reader (bypasses most CF challenges)
    for prefix in "${JINA_PREFIXES[@]}"; do
      body="$(fetch_body "${prefix}${result_url}" || true)"
      if [[ -n "$body" && "$body" != *"Just a moment"* && "$body" != *"Attention Required"* ]]; then
        parse_scores_text "$body"
        if [[ -n "$PARSE_SINGLE" && -n "$PARSE_MULTI" ]]; then
          SCORE_SINGLE="$PARSE_SINGLE"
          SCORE_MULTI="$PARSE_MULTI"
          return 0
        fi
        # partial is still useful — keep trying other methods for the missing half
        [[ -n "$PARSE_SINGLE" ]] && SCORE_SINGLE="$PARSE_SINGLE"
        [[ -n "$PARSE_MULTI" ]] && SCORE_MULTI="$PARSE_MULTI"
      fi
    done

    # B) direct page
    body="$(fetch_body "$result_url" || true)"
    if [[ -n "$body" && "$body" != *"Just a moment"* && "$body" != *"Enable JavaScript"* ]]; then
      parse_scores_text "$body"
      [[ -n "$PARSE_SINGLE" ]] && SCORE_SINGLE="$PARSE_SINGLE"
      [[ -n "$PARSE_MULTI" ]] && SCORE_MULTI="$PARSE_MULTI"
      if [[ -n "$SCORE_SINGLE" && -n "$SCORE_MULTI" ]]; then
        return 0
      fi
    fi

    if [[ -n "$SCORE_SINGLE" && -n "$SCORE_MULTI" ]]; then
      return 0
    fi

    # wait for browser index / CF / jina cache
    sleep $((2 + i))
  done

  [[ -n "$SCORE_SINGLE" || -n "$SCORE_MULTI" ]] && return 0
  return 1
}

# Spinner: one live line — label + status_file detail (overwrites). Quiet if not a TTY.
start_spinner() {
  local label="$1"
  if [[ ! -t 1 ]]; then
    printf '%b·%b %s\n' "${C_DIM}" "${NC}" "$label" >&2
    SPINNER_PID=""
    return 0
  fi
  (
    local frames=('|' '/' '-' '\') i=0 detail=""
    while true; do
      detail=""
      if [[ -n "${STATUS_FILE:-}" && -f "$STATUS_FILE" ]]; then
        detail="$(tail -n 1 "$STATUS_FILE" 2>/dev/null | tr -d '\r' | cut -c1-52)"
      fi
      printf '\r%b[%s]%b %s  %b%s%b\033[K' \
        "${C_ACC}" "${frames[i % 4]}" "${NC}" "$label" "${C_DIM}" "$detail" "${NC}"
      i=$((i + 1))
      sleep 0.12
    done
  ) &
  SPINNER_PID=$!
}

stop_spinner() {
  if [[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  SPINNER_PID=""
  printf '\r\033[0K'
}

# Compact list row (multi-suite mode).
print_suite_list() {
  local suite="$1" status="$2" single="$3" multi="$4" url="$5" elapsed="$6"
  local dur s_disp m_disp
  dur="$(format_duration "$elapsed")"
  s_disp="${single:--}"
  m_disp="${multi:--}"

  if [[ "$status" == "OK" ]]; then
    printf '  %b%-4s%b  Single %b%-7s%b Multi %b%-7s%b %b%s%b\n' \
      "${BOLD}" "$suite" "${NC}" \
      "${C_OK}${BOLD}" "$s_disp" "${NC}" \
      "${C_OK}${BOLD}" "$m_disp" "${NC}" \
      "${C_DIM}" "$dur" "${NC}"
    if [[ -n "$url" && "$url" != "-" ]]; then
      printf '         %s\n' "$url"
    fi
  else
    printf '  %b%-4s%b  %b%s%b  %b%s%b\n' \
      "${BOLD}" "$suite" "${NC}" \
      "${C_ERR}" "$status" "${NC}" \
      "${C_DIM}" "$dur" "${NC}"
    [[ -n "$url" && "$url" != "-" ]] && printf '         %s\n' "$url"
  fi
}

# Vertical detail table (single-suite mode) — classic scannable report.
print_suite_detail() {
  local label="$1" status="$2" single="$3" multi="$4" url="$5" claim="$6" elapsed="$7"
  local s_disp m_disp
  s_disp="${single:--}"
  m_disp="${multi:--}"

  echo
  printf '%b%s Benchmark Test:%b\n' "${C_BAR}" "$label" "${NC}"
  printf '%b---------------------------------%b\n' "${C_BAR}" "${NC}"
  printf "%-16s | %-40s\n" "Test" "Value"
  printf "%-16s | %-40s\n" "----------------" "----------------------------------------"
  if [[ "$status" != "OK" ]]; then
    printf "%-16s | %b%s%b\n" "Status" "${C_ERR}" "$status" "${NC}"
  fi
  if [[ -n "$single" && "$single" != "-" ]]; then
    printf "%-16s | %b%s%b\n" "Single Core" "${C_OK}${BOLD}" "$s_disp" "${NC}"
  else
    printf "%-16s | %b%s%b\n" "Single Core" "${C_WARN}" "${s_disp}" "${NC}"
  fi
  if [[ -n "$multi" && "$multi" != "-" ]]; then
    printf "%-16s | %b%s%b\n" "Multi Core" "${C_OK}${BOLD}" "$m_disp" "${NC}"
  else
    printf "%-16s | %b%s%b\n" "Multi Core" "${C_WARN}" "${m_disp}" "${NC}"
  fi
  [[ -n "$url" && "$url" != "-" ]] && printf "%-16s | %s\n" "Full Test" "$url"
  [[ -n "$claim" && "$claim" != "-" ]] && printf "%-16s | %s\n" "Claim" "$claim"
  printf "%-16s | %s\n" "Duration" "$(format_duration "$elapsed")"
  echo
}

# Dispatch: detail table if one suite, list row if many.
emit_suite_result() {
  local suite="$1" status="$2" single="$3" multi="$4" url="$5" claim="$6" elapsed="$7" label="${8:-$suite}"
  if [[ "${PLAN_TOTAL:-1}" -le 1 ]]; then
    print_suite_detail "$label" "$status" "$single" "$multi" "$url" "$claim" "$elapsed"
  else
    print_suite_list "$suite" "$status" "$single" "$multi" "$url" "$elapsed"
  fi
}

# Run one Geekbench version. Quiet progress + compact result line.
run_gb() {
  local ver="$1"
  local dest bin out log start_ts end_ts elapsed
  local result_url claim_url single multi label
  local gb_pid watch_pid gb_rc=0

  PLAN_INDEX=$((PLAN_INDEX + 1))
  setup_gb_meta "$ver" || return 1

  STATUS_FILE="$WORKDIR/gb${ver}.status"
  out="$WORKDIR/gb${ver}.out"
  log="$WORKDIR/gb${ver}.log"
  : >"$out"
  : >"$STATUS_FILE"

  if [[ "$PLAN_TOTAL" -gt 1 ]]; then
    label="[$((PLAN_INDEX))/${PLAN_TOTAL}] GB${ver}"
  else
    label="GB${ver}"
  fi

  start_ts="$(date +%s)"
  start_spinner "$label"

  if ! download_and_extract "$ver"; then
    stop_spinner
    elapsed=$(( $(date +%s) - start_ts ))
    emit_suite_result "GB${ver}" "FAIL" "-" "-" "-" "-" "$elapsed" "$GB_LABEL"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "GB${ver}" "FAIL" "-" "-" "-" "$elapsed" >>"$RESULTS_TSV"
    return 1
  fi
  dest="$GB_DEST"
  bin="$dest/${GB_BIN}"

  status_set "$(T "benchmark" "跑分")"
  # shellcheck disable=SC2094
  "$bin" --cpu >"$out" 2>"$log" &
  gb_pid=$!

  # Progress watcher: latest workload / section for spinner
  (
    while kill -0 "$gb_pid" 2>/dev/null; do
      if [[ -s "$out" ]]; then
        local last
        last="$(grep -E '^(Single-Core|Multi-Core|  Running |Upload)' "$out" 2>/dev/null | tail -1 | sed 's/^  //')"
        [[ -n "$last" ]] && printf '%s\n' "$last" >"$STATUS_FILE"
      fi
      sleep 0.35
    done
  ) &
  watch_pid=$!

  wait "$gb_pid"
  gb_rc=$?
  kill "$watch_pid" 2>/dev/null || true
  wait "$watch_pid" 2>/dev/null || true

  end_ts="$(date +%s)"
  elapsed=$((end_ts - start_ts))

  if [[ "$gb_rc" -ne 0 ]]; then
    stop_spinner
    err "$(T "${GB_LABEL} exited ${gb_rc}" "${GB_LABEL} 退出码 ${gb_rc}")"
    emit_suite_result "GB${ver}" "FAIL" "-" "-" "-" "-" "$elapsed" "$GB_LABEL"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "GB${ver}" "FAIL" "-" "-" "-" "$elapsed" >>"$RESULTS_TSV"
    return 1
  fi

  result_url="$(grep -oE 'https://browser\.geekbench\.com/v[0-9]+/cpu/[0-9]+' "$out" | head -1 || true)"
  claim_url="$(grep -oE 'https://browser\.geekbench\.com/v[0-9]+/cpu/[0-9]+/claim\?key=[0-9]+' "$out" | head -1 || true)"

  if [[ -z "$result_url" ]]; then
    stop_spinner
    err "$(T "GB${ver}: no result URL (network / tryout?)" "GB${ver}: 无结果链接（网络/试用？）")"
    emit_suite_result "GB${ver}" "NO_URL" "-" "-" "-" "-" "$elapsed" "$GB_LABEL"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "GB${ver}" "NO_URL" "-" "-" "-" "$elapsed" >>"$RESULTS_TSV"
    return 1
  fi

  status_set "$(T "fetch scores" "取分")…"
  if fetch_scores "$result_url" 10; then
    single="${SCORE_SINGLE:-}"
    multi="${SCORE_MULTI:-}"
  else
    single="${SCORE_SINGLE:-}"
    multi="${SCORE_MULTI:-}"
  fi
  stop_spinner

  if [[ -z "$single" || -z "$multi" ]]; then
    warn "$(T "GB${ver}: partial scores — open report URL" "GB${ver}: 分数不完整 — 请打开报告链接")"
  fi

  emit_suite_result "GB${ver}" "OK" "${single:--}" "${multi:--}" "$result_url" "${claim_url:--}" "$elapsed" "$GB_LABEL"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "GB${ver}" "OK" "${single:--}" "${multi:--}" "$result_url" "$elapsed" >>"$RESULTS_TSV"

  if [[ -n "$claim_url" ]]; then
    printf '%s\n' "$claim_url" >>"$WORKDIR/geekbench_claim.url" 2>/dev/null || true
    printf '%s\n' "$claim_url" >>"./geekbench_claim.url" 2>/dev/null || true
  fi

  return 0
}

print_summary() {
  # Only for multi-suite runs (list mode). Single suite already printed detail.
  [[ -s "$RESULTS_TSV" ]] || return 0
  [[ "${PLAN_TOTAL:-1}" -gt 1 ]] || return 0
  local lines total_elapsed=0
  lines="$(wc -l <"$RESULTS_TSV" | tr -d ' ')"
  echo
  printf '%b%s%b\n' "${C_BAR}" "── $(T "Summary" "汇总") ──────────────────────────────────────" "${NC}"
  printf "  %-6s %8s %8s %8s  %s\n" "Suite" "Single" "Multi" "Time" "Report"
  printf "  %-6s %8s %8s %8s  %s\n" "------" "--------" "--------" "--------" "------"
  while IFS=$'\t' read -r suite status single multi url secs; do
    total_elapsed=$((total_elapsed + ${secs:-0}))
    if [[ "$status" == "OK" ]]; then
      printf "  %-6s %b%8s%b %b%8s%b %8s  %s\n" \
        "$suite" "${C_OK}" "${single}" "${NC}" "${C_OK}" "${multi}" "${NC}" \
        "$(format_duration "$secs")" "$url"
    else
      printf "  %-6s %b%8s%b %8s %8s  %s\n" \
        "$suite" "${C_ERR}" "$status" "${NC}" "-" \
        "$(format_duration "$secs")" "${url:--}"
    fi
  done <"$RESULTS_TSV"
  if [[ -n "${RUN_START_TS:-}" && "$RUN_START_TS" -gt 0 ]]; then
    total_elapsed=$(( $(date +%s) - RUN_START_TS ))
  fi
  printf "  %b%s%b %s" "${C_DIM}" "$(T "Total" "合计")" "${NC}" "$(format_duration "$total_elapsed")"
  if [[ "$lines" -gt 1 ]]; then
    printf " · %s %s" "$lines" "$(T "suites" "项")"
  fi
  if [[ -f ./geekbench_claim.url ]]; then
    printf " · claim → ./geekbench_claim.url"
  fi
  printf '\n\n'
}

print_sysinfo() {
  local cpu cores mem virt plan=""
  cpu="$(awk -F: '/model name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || uname -m)"
  cores="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")"
  mem="$(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?")"
  virt="$(systemd-detect-virt 2>/dev/null || true)"
  virt="${virt:-none}"

  echo
  printf '%bCPUX%b v%s · CPU eXaminer\n' "${C_HDR}${BOLD}" "${NC}" "$VERSION"
  printf '%b%s%b\n' "${C_DIM}" \
    "${cpu} · ${cores}c · ${mem} · $(uname -m)/${virt}" "${NC}"
}

print_menu() {
  print_sysinfo
  echo
  printf '  %b1%b  Geekbench 5   %b%s%b\n' "${C_ACC}" "${NC}" "${C_DIM}" "$GB5_VER" "${NC}"
  printf '  %b2%b  Geekbench 6   %b%s%b\n' "${C_ACC}" "${NC}" "${C_DIM}" "$GB6_VER" "${NC}"
  printf '  %b3%b  Geekbench 7   %b%s%b\n' "${C_ACC}" "${NC}" "${C_DIM}" "$GB7_VER" "${NC}"
  printf '  %b4%b  %s  %b5→6→7%b\n' "${C_ACC}" "${NC}" "$(T "All" "全部")" "${C_DIM}" "${NC}"
  printf '  %b0%b  %s\n' "${C_ACC}" "${NC}" "$(T "Exit" "退出")"
  echo
}

read_choice() {
  local prompt="$1" reply=""
  if [[ -r /dev/tty ]]; then
    printf '%s' "$prompt" > /dev/tty
    # shellcheck disable=SC2162
    IFS= read -r reply < /dev/tty || true
  elif [[ -t 0 ]]; then
    printf '%s' "$prompt"
    IFS= read -r reply || true
  else
    err "$(T "No interactive TTY. Use: bash -s -- 5|6|7|all" "无交互终端。请用: bash -s -- 5|6|7|all")"
    err "Example: curl -sL https://ba.sh/cpux | bash -s -- all"
    return 1
  fi
  printf '%s' "$reply"
}

interactive_menu() {
  local choice
  clear_screen
  print_menu
  choice="$(read_choice "  $(T "Select [1/2/3/4/0]:" "请选择 [1/2/3/4/0]:") ")" || return 1
  choice="$(printf '%s' "$choice" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  case "$choice" in
    1|5|gb5) DO_GB5=1 ;;
    2|6|gb6) DO_GB6=1 ;;
    3|7|gb7) DO_GB7=1 ;;
    4|a|all|567)
      DO_GB5=1; DO_GB6=1; DO_GB7=1
      ;;
    0|q|quit|exit)
      info "$(T "Bye." "再见。")"
      return 0
      ;;
    *)
      err "$(T "Invalid option: ${choice}" "无效选项: ${choice}")"
      return 1
      ;;
  esac
  return 0
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    INTERACTIVE_PICK=1
    return 0
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -v|--version) echo "CPUX v${VERSION}"; exit 0 ;;
      -y|--yes) AUTO_YES=1; shift ;;
      -k|--keep) KEEP_FILES=1; shift ;;
      -cn|--chinese) LANG_MODE="zh"; shift ;;
      -us|--english) LANG_MODE="en"; shift ;;
      -5|--gb5|5|gb5) DO_GB5=1; shift ;;
      -6|--gb6|6|gb6) DO_GB6=1; shift ;;
      -7|--gb7|7|gb7) DO_GB7=1; shift ;;
      -a|--all|all|567)
        DO_GB5=1; DO_GB6=1; DO_GB7=1
        shift
        ;;
      *)
        err "$(T "Unknown argument: $1" "未知参数: $1")"
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  # locale for stable parsing
  if locale -a 2>/dev/null | grep -q '^C$'; then
    export LC_ALL=C
  fi

  ensure_tools || exit 1
  detect_arch || exit 1
  check_memory
  check_ipv4_browser

  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/cpux.XXXXXX")"
  RESULTS_TSV="$WORKDIR/results.tsv"
  : >"$RESULTS_TSV"

  if [[ "$INTERACTIVE_PICK" -eq 1 ]]; then
    interactive_menu || exit 1
  fi

  if [[ "$DO_GB5" -eq 0 && "$DO_GB6" -eq 0 && "$DO_GB7" -eq 0 ]]; then
    # nothing selected (e.g. exit from menu)
    exit 0
  fi

  # Count planned suites for [n/N] progress
  PLAN_TOTAL=0
  PLAN_INDEX=0
  [[ "$DO_GB5" -eq 1 ]] && PLAN_TOTAL=$((PLAN_TOTAL + 1))
  [[ "$DO_GB6" -eq 1 ]] && PLAN_TOTAL=$((PLAN_TOTAL + 1))
  [[ "$DO_GB7" -eq 1 ]] && PLAN_TOTAL=$((PLAN_TOTAL + 1))

  # Fresh screen for the run (menu already cleared once)
  clear_screen
  print_sysinfo
  local plan_str=""
  [[ "$DO_GB5" -eq 1 ]] && plan_str+="GB5 "
  [[ "$DO_GB6" -eq 1 ]] && plan_str+="GB6 "
  [[ "$DO_GB7" -eq 1 ]] && plan_str+="GB7 "
  plan_str="${plan_str% }"
  plan_str="${plan_str// / → }"
  printf '%b%s%b %s\n' "${C_DIM}" "$(T "Plan" "计划")" "${NC}" "$plan_str"
  if [[ "$KEEP_FILES" -eq 1 ]]; then
    info "$(T "Keep:" "保留:") $WORKDIR"
  fi
  echo

  RUN_START_TS="$(date +%s)"
  local failed=0
  # Sequential only — parallel GB would corrupt multi-core scores
  if [[ "$DO_GB5" -eq 1 ]]; then
    run_gb 5 || failed=1
  fi
  if [[ "$DO_GB6" -eq 1 ]]; then
    run_gb 6 || failed=1
  fi
  if [[ "$DO_GB7" -eq 1 ]]; then
    run_gb 7 || failed=1
  fi

  print_summary

  if [[ "$KEEP_FILES" -eq 1 ]]; then
    info "$(T "Files kept:" "文件保留:") $WORKDIR"
  fi

  if [[ "$failed" -ne 0 ]]; then
    warn "$(T "Finished with errors." "完成（有失败项）。")"
    exit 1
  fi
  exit 0
}

main "$@"
