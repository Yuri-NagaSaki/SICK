#!/usr/bin/env bash
#
# 猫脚本 / Catbash — interactive launcher for SICK + NETS + CPUX
#
# Usage:
#   curl -sL https://catbash.net/menu | bash
#   curl -sL https://catbash.net/catbash | bash
#   ./catbash.sh              # menu
#   ./catbash.sh sick [args]  # run SICK directly
#   ./catbash.sh nets [args]  # run NETS directly
#   ./catbash.sh cpux [args]  # run CPUX directly
#   ./catbash.sh all [-cn]    # SICK → NETS (reduced) → CPUX (Geekbench 6)
#   ./catbash.sh 1            # same as sick
#   ./catbash.sh 2 -r -t 5    # NETS with args
#   ./catbash.sh 3 all        # CPUX all versions
#
set -uo pipefail

VERSION="1.2.0"

# Prefer catbash short links; ba.sh as fallbacks
SICK_URLS=(
  "https://catbash.net/sick"
  "https://ba.sh/sick"
  "https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/hardware_info.sh"
)
NETS_URLS=(
  "https://catbash.net/nets"
  "https://ba.sh/nets"
  "https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/nets/nets.sh"
)
CPUX_URLS=(
  "https://catbash.net/cpux"
  "https://ba.sh/cpux"
  "https://raw.githubusercontent.com/Yuri-NagaSaki/SICK/main/cpux.sh"
)

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  C_HDR=$'\033[1;38;5;222m'
  C_DIM=$'\033[2m'
  C_ACC=$'\033[38;5;81m'
  C_BAR=$'\033[38;5;73m'
  C_ERR=$'\033[38;5;203m'
  NC=$'\033[0m'
  BOLD=$'\033[1m'
else
  C_HDR=""; C_DIM=""; C_ACC=""; C_BAR=""; C_ERR=""; NC=""; BOLD=""
fi

err()  { printf '%s\n' "${C_ERR}$*${NC}" >&2; }
info() { printf '%s\n' "${C_DIM}$*${NC}"; }

TMP_SCRIPT=""
cleanup() { [[ -n "$TMP_SCRIPT" ]] && rm -f "$TMP_SCRIPT"; return 0; }
trap cleanup EXIT

# /dev/tty can exist yet fail to open (ssh without -t, cron, CI, containers).
have_tty() { (exec </dev/tty) 2>/dev/null; }

# Only clear a real terminal: under `curl | bash` stdout is still the TTY,
# and redirected output (> report.txt) must stay clean.
clear_screen() {
  if [[ -t 1 && -z "${CATBASH_NO_CLEAR:-}" ]]; then printf '\033[2J\033[H'; fi
  return 0
}

usage() {
  cat <<EOF
猫脚本 / Catbash v${VERSION} — launcher for SICK, NETS & CPUX

Usage:
  catbash.sh                 Interactive menu
  catbash.sh sick [opts]     Run SICK (hardware inventory)
  catbash.sh nets [opts]     Run NETS (iperf3 throughput)
  catbash.sh cpux [opts]     Run CPUX (Geekbench 5/6/7)
  catbash.sh all [-cn]       SICK → NETS (reduced) → CPUX (Geekbench 6)
  catbash.sh 1|2|3|4 [opts]  Same as sick | nets | cpux | all
  catbash.sh -h | --help
  catbash.sh -v | --version

One-liner:
  curl -sL https://ba.sh/menu | bash
  curl -sL https://catbash.net/menu | bash
  curl -sL https://ba.sh/menu | bash -s -- nets -r
  curl -sL https://ba.sh/menu | bash -s -- cpux all
  curl -sL https://ba.sh/menu | bash -s -- all -cn

Docs:
  https://catbash.net/          hub
  https://catbash.net/sick.html SICK
  https://catbash.net/nets.html NETS
  https://catbash.net/cpux.html CPUX
EOF
}

# CATBASH_LOCAL=1 in a checkout: run sibling scripts instead of downloading.
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

local_script() {
  [[ -n "${CATBASH_LOCAL:-}" && -n "$SCRIPT_DIR" ]] || return 1
  case "$1" in
    sick) LOCAL_PATH="$SCRIPT_DIR/hardware_info.sh" ;;
    nets) LOCAL_PATH="$SCRIPT_DIR/nets/nets.sh" ;;
    cpux) LOCAL_PATH="$SCRIPT_DIR/cpux.sh" ;;
    *) return 1 ;;
  esac
  [[ -f "$LOCAL_PATH" ]]
}

# Download first working mirror and run it with bash, forwarding args.
# A real file (not a pipe) keeps the child's stdin free for its own prompts.
run_remote() {
  local name="$1"; shift
  local -a urls=()
  local url rc

  if local_script "$name"; then
    info "→ ${name}: ${LOCAL_PATH}"
    bash "$LOCAL_PATH" "$@"
    return $?
  fi

  case "$name" in
    sick) urls=("${SICK_URLS[@]}") ;;
    nets) urls=("${NETS_URLS[@]}") ;;
    cpux) urls=("${CPUX_URLS[@]}") ;;
    *) err "Unknown tool: $name"; return 1 ;;
  esac

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    err "Need curl or wget to download scripts."
    return 1
  fi

  TMP_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/catbash-${name}.XXXXXX")" || { err "mktemp failed"; return 1; }
  for url in "${urls[@]}"; do
    [[ -z "$url" ]] && continue
    : >"$TMP_SCRIPT"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$TMP_SCRIPT" </dev/null 2>/dev/null || continue
    else
      wget -q -T 120 -O "$TMP_SCRIPT" "$url" </dev/null 2>/dev/null || continue
    fi
    # Sanity: a shell script, not an HTML error page from a captive portal.
    if [[ -s "$TMP_SCRIPT" ]] && head -n 1 "$TMP_SCRIPT" | grep -qE '^#!.*(bash|sh)'; then
      info "→ ${name}: ${url}"
      bash "$TMP_SCRIPT" "$@"
      rc=$?
      rm -f "$TMP_SCRIPT"; TMP_SCRIPT=""
      return "$rc"
    fi
  done

  rm -f "$TMP_SCRIPT"; TMP_SCRIPT=""
  err "Failed to download ${name} script from any mirror."
  return 1
}

# Full check, yabs-style: one command, everything in one scrollback.
run_all() {
  local lang="" rc=0 a
  for a in "$@"; do
    case "$a" in
      -cn|--chinese) lang="-cn" ;;
      -us|--english) lang="" ;;
      *) err "all: unsupported option '$a' (only -cn / -us)"; return 1 ;;
    esac
  done
  # Env, not flags: older deployed tool versions ignore unknown env vars.
  export CATBASH_NO_CLEAR=1
  clear_screen
  printf '%s\n' "${C_HDR}== 1/3 SICK ==${NC}"
  run_remote sick ${lang:+"$lang"} || rc=1
  printf '\n%s\n' "${C_HDR}== 2/3 NETS (reduced) ==${NC}"
  run_remote nets -r || rc=1
  printf '\n%s\n' "${C_HDR}== 3/3 CPUX (Geekbench 6) ==${NC}"
  run_remote cpux 6 -y ${lang:+"$lang"} || rc=1
  return "$rc"
}

print_menu() {
  # Box is 60 columns; "猫脚本" is 3 double-width glyphs (6 columns).
  local title_w=$((20 + 1 + ${#VERSION})) pad
  pad=$((58 - title_w)); ((pad < 1)) && pad=1
  printf '%s\n' "${C_BAR}+----------------------------------------------------------+${NC}"
  printf '%s|%s  %s猫脚本 / Catbash%s  v%s%*s%s|%s\n' \
    "${C_BAR}" "${NC}" "${C_HDR}" "${NC}" "$VERSION" "$pad" "" "${C_BAR}" "${NC}"
  printf '%s\n' "${C_BAR}+----------------------------------------------------------+${NC}"
  echo
  printf '  %s1)%s  %sSICK%s   Server Info & Check Kit\n' "${C_ACC}" "${NC}" "${BOLD}" "${NC}"
  printf '       %sOne-shot hardware inventory (CPU/RAM/disk/NIC…)%s\n' "${C_DIM}" "${NC}"
  echo
  printf '  %s2)%s  %sNETS%s   Network Endpoint Throughput Sampler\n' "${C_ACC}" "${NC}" "${BOLD}" "${NC}"
  printf '       %sPublic iperf3 send/recv tests worldwide%s\n' "${C_DIM}" "${NC}"
  echo
  printf '  %s3)%s  %sCPUX%s   CPU eXaminer (Geekbench 5 / 6 / 7)\n' "${C_ACC}" "${NC}" "${BOLD}" "${NC}"
  printf '       %sSequential CPU benchmarks with single/multi scores%s\n' "${C_DIM}" "${NC}"
  echo
  printf '  %s4)%s  %sALL%s    SICK → NETS (reduced) → CPUX (GB6)\n' "${C_ACC}" "${NC}" "${BOLD}" "${NC}"
  printf '       %sFull server check in one scrollback%s\n' "${C_DIM}" "${NC}"
  echo
  printf '  %s0)%s  Exit\n' "${C_ACC}" "${NC}"
  echo
  printf '  %sDocs:%s https://catbash.net/\n' "${C_DIM}" "${NC}"
  echo
}

# Read a line from the real terminal (works under curl | bash). Sets REPLY_TEXT.
# Returns 1 on EOF (Ctrl-D) so callers can quit instead of spinning.
read_tty() {
  REPLY_TEXT=""
  printf '%s' "$1" >/dev/tty
  IFS= read -r REPLY_TEXT </dev/tty
}

interactive_menu() {
  local choice rc
  if ! have_tty; then
    err "No interactive terminal. Pass a tool name instead:"
    err "  curl -sL https://ba.sh/menu | bash -s -- sick|nets|cpux|all [options]"
    return 1
  fi
  while true; do
    clear_screen
    print_menu
    read_tty "  Select [1/2/3/4/0]: " || { echo; return 0; }
    choice="${REPLY_TEXT//[[:space:]]/}"
    choice="${choice,,}"
    rc=0
    case "$choice" in
      1|sick|s)     clear_screen; run_remote sick; rc=$? ;;
      2|nets|n)     clear_screen; run_remote nets; rc=$? ;;
      3|cpux|c|cpu) clear_screen; run_remote cpux; rc=$? ;;
      4|all|a)      run_all; rc=$? ;;
      0|q|quit|exit) info "Bye."; return 0 ;;
      *)
        err "Invalid option: ${choice:-<empty>}"
        sleep 1
        continue
        ;;
    esac
    # Interrupted tool (Ctrl-C) → leave; otherwise offer the menu again.
    ((rc == 130 || rc == 143)) && return "$rc"
    echo
    read_tty "  ${C_DIM}[Enter] back to menu · [q] quit:${NC} " || { echo; return "$rc"; }
    case "${REPLY_TEXT,,}" in q|quit|exit|0) return "$rc" ;; esac
  done
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -v|--version) echo "Catbash v${VERSION}"; exit 0 ;;
  esac

  if [[ $# -gt 0 ]]; then
    local cmd="${1,,}"; shift
    case "$cmd" in
      1|sick|s)     clear_screen; run_remote sick "$@"; exit $? ;;
      2|nets|n)     clear_screen; run_remote nets "$@"; exit $? ;;
      3|cpux|c|cpu) clear_screen; run_remote cpux "$@"; exit $? ;;
      4|all|a)      run_all "$@"; exit $? ;;
      *)
        err "Unknown command: $cmd"
        usage >&2
        exit 1
        ;;
    esac
  fi

  interactive_menu
  exit $?
}

main "$@"
