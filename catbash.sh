#!/usr/bin/env bash
#
# 猫脚本 / Catbash — interactive launcher for SICK + NETS
#
# Usage:
#   curl -sL https://catbash.net/menu | bash
#   curl -sL https://catbash.net/catbash | bash
#   ./catbash.sh              # menu
#   ./catbash.sh sick [args]  # run SICK directly
#   ./catbash.sh nets [args]  # run NETS directly
#   ./catbash.sh 1            # same as sick
#   ./catbash.sh 2 -r -t 5    # NETS with args
#
set -uo pipefail

VERSION="1.0.0"

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

if [[ -t 1 ]]; then
  C_HDR=$'\033[1;38;5;222m'
  C_DIM=$'\033[2m'
  C_OK=$'\033[38;5;114m'
  C_ACC=$'\033[38;5;81m'
  C_BAR=$'\033[38;5;73m'
  C_ERR=$'\033[38;5;203m'
  NC=$'\033[0m'
  BOLD=$'\033[1m'
else
  C_HDR=""; C_DIM=""; C_OK=""; C_ACC=""; C_BAR=""; C_ERR=""; NC=""; BOLD=""
fi

err()  { printf '%b\n' "${C_ERR}$*${NC}" >&2; }
info() { printf '%b\n' "${C_DIM}$*${NC}"; }

usage() {
  cat <<EOF
猫脚本 / Catbash v${VERSION} — launcher for SICK & NETS

Usage:
  $(basename "$0")                 Interactive menu
  $(basename "$0") sick [opts]     Run SICK (hardware inventory)
  $(basename "$0") nets [opts]     Run NETS (iperf3 throughput)
  $(basename "$0") 1 [opts]        Same as sick
  $(basename "$0") 2 [opts]        Same as nets
  $(basename "$0") -h | --help

One-liner:
  curl -sL https://catbash.net/menu | bash
  curl -sL https://catbash.net/menu | bash -s -- nets -r

Docs:
  https://catbash.net/          hub
  https://catbash.net/sick.html SICK
  https://catbash.net/nets.html NETS
EOF
}

# Download first working URL and run with bash, forwarding args.
# Uses a temp file so child scripts get a real path when needed.
run_remote() {
  local name="$1"; shift
  local -a urls=()
  local url body tmp rc=1

  case "$name" in
    sick) urls=("${SICK_URLS[@]}") ;;
    nets) urls=("${NETS_URLS[@]}") ;;
    *) err "Unknown tool: $name"; return 1 ;;
  esac

  tmp="$(mktemp "${TMPDIR:-/tmp}/catbash-${name}.XXXXXX.sh")"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  for url in "${urls[@]}"; do
    [[ -z "$url" ]] && continue
    body=""
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp" 2>/dev/null \
        && [[ -s "$tmp" ]]; then
        body=1
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -T 120 -O "$tmp" "$url" 2>/dev/null && [[ -s "$tmp" ]]; then
        body=1
      fi
    else
      err "Need curl or wget to download scripts."
      return 1
    fi
    if [[ -n "$body" ]]; then
      # basic sanity: looks like a shell script
      if head -1 "$tmp" | grep -qE '^#!.*(bash|sh)'; then
        info "→ ${name}: ${url}"
        chmod +x "$tmp" 2>/dev/null || true
        bash "$tmp" "$@"
        rc=$?
        return "$rc"
      fi
    fi
  done

  err "Failed to download ${name} script from any mirror."
  return 1
}

print_menu() {
  printf '%b\n' "${C_BAR}+----------------------------------------------------------+${NC}"
  printf '%b|%b  %b猫脚本 / Catbash%b  v%s%-28s%b|%b\n' \
    "${C_BAR}" "${NC}" "${C_HDR}" "${NC}" "$VERSION" "" "${C_BAR}" "${NC}"
  printf '%b\n' "${C_BAR}+----------------------------------------------------------+${NC}"
  echo
  printf '  %b1)%b  %bSICK%b   Server Info & Check Kit\n' "${C_ACC}" "${NC}" "${BOLD}" "${NC}"
  printf '       %bOne-shot hardware inventory (CPU/RAM/disk/NIC…)%b\n' "${C_DIM}" "${NC}"
  echo
  printf '  %b2)%b  %bNETS%b   Network Endpoint Throughput Sampler\n' "${C_ACC}" "${NC}" "${BOLD}" "${NC}"
  printf '       %bPublic iperf3 send/recv tests worldwide%b\n' "${C_DIM}" "${NC}"
  echo
  printf '  %b0)%b  Exit\n' "${C_ACC}" "${NC}"
  echo
  printf '  %bDocs:%b https://catbash.net/\n' "${C_DIM}" "${NC}"
  echo
}

# Read a line from the real terminal (works under curl | bash)
read_choice() {
  local prompt="$1"
  local reply=""
  if [[ -r /dev/tty ]]; then
    printf '%s' "$prompt" > /dev/tty
    # shellcheck disable=SC2162
    IFS= read -r reply < /dev/tty || true
  elif [[ -t 0 ]]; then
    printf '%s' "$prompt"
    IFS= read -r reply || true
  else
    err "No interactive TTY. Use: bash -s -- sick|nets [options]"
    err "Example: curl -sL https://catbash.net/menu | bash -s -- nets -r"
    return 1
  fi
  printf '%s' "$reply"
}

interactive_menu() {
  local choice
  while true; do
    print_menu
    choice="$(read_choice "  Select [1/2/0]: ")" || return 1
    choice="$(printf '%s' "$choice" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    case "$choice" in
      1|sick|s)
        echo
        run_remote sick
        return $?
        ;;
      2|nets|n)
        echo
        run_remote nets
        return $?
        ;;
      0|q|quit|exit)
        info "Bye."
        return 0
        ;;
      "")
        err "Empty choice."
        ;;
      *)
        err "Invalid option: ${choice}"
        ;;
    esac
    echo
  done
}

main() {
  # help
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi
  if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
    echo "Catbash v${VERSION}"
    exit 0
  fi

  # direct dispatch
  if [[ $# -gt 0 ]]; then
    local cmd="$1"; shift
    case "$cmd" in
      1|sick|s|SICK)
        run_remote sick "$@"
        exit $?
        ;;
      2|nets|n|NETS)
        run_remote nets "$@"
        exit $?
        ;;
      *)
        err "Unknown command: $cmd"
        usage
        exit 1
        ;;
    esac
  fi

  # no args → interactive menu
  interactive_menu
  exit $?
}

main "$@"
