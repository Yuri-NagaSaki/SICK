#!/bin/bash

# Hardware Information Collection Script
# 硬件信息收集脚本
# Compatible with Debian/Ubuntu/CentOS/AlmaLinux/Rocky Linux/CloudLinux/Arch Linux/openSUSE/Fedora
# 兼容 Debian/Ubuntu/CentOS/AlmaLinux/Rocky Linux/CloudLinux/Arch Linux/openSUSE/Fedora
#
# NOTE: This is a one-shot hardware inventory tool. It does NOT persist anything
# or run as a monitor. Strict mode (set -e/-u) is intentionally NOT enabled:
# collection is best-effort and many probes legitimately fail (missing tool,
# grep no-match); aborting on the first failure would truncate the report.

# Use a UTF-8 locale with English/C tool output. UTF-8 keeps CJK display-width
# math and box-drawing aligned under cron / CI / `curl | bash` (often plain C);
# English output and a "." decimal point keep the parsers working when the user
# runs a localized locale (lscpu, df and lsblk translate labels / use ",").
# Each candidate is probed in-process (a CJK glyph must count as 1 character),
# which also works where `locale -a` does not exist (Alpine/musl).
_sick_orig_lc_all="${LC_ALL-__unset__}"
_sick_utf8=""
for _cand in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    { export LC_ALL="$_cand"; } 2>/dev/null
    _probe="中"
    if [[ ${#_probe} -eq 1 ]]; then
        _sick_utf8="$_cand"
        break
    fi
done
if [[ -z "$_sick_utf8" ]]; then
    # No English UTF-8 locale installed: keep the user's character set but
    # force C messages / numbers for the tools we parse.
    if [[ "$_sick_orig_lc_all" == "__unset__" ]]; then
        { unset LC_ALL; } 2>/dev/null
    else
        { export LC_CTYPE="$_sick_orig_lc_all"; unset LC_ALL; } 2>/dev/null
    fi
    export LC_MESSAGES=C LC_NUMERIC=C
fi
# UTF8_OK: the active locale is UTF-8 (symbols / spinner frames below use it)
UTF8_OK=false
_probe="中"
[[ ${#_probe} -eq 1 ]] && UTF8_OK=true
unset _sick_orig_lc_all _sick_utf8 _cand _probe

VERSION="3.2.0"
SCRIPT_NAME="Hardware Info Collector"

# Temporary files tracking for cleanup
TEMP_FILES=()

# Caches to reduce repeated external calls
SMARTCTL_SCAN_CACHE=""
SMARTCTL_SCAN_DONE=false
RAID_MEMBER_CACHE=""
RAID_MEMBER_CACHE_READY=false
declare -A SMART_JSON_CACHE
declare -A SMART_JSON_CACHE_READY
declare -A SMART_JSON_RAID_CACHE
declare -A SMART_JSON_RAID_CACHE_READY
declare -A DISPLAY_WIDTH_CACHE
SMARTCTL_SCAN_RESULT=""
RAID_MEMBER_RESULT=""
SMART_JSON_RESULT=""
SMART_JSON_RAID_RESULT=""
DISPLAY_WIDTH_RESULT=0
SMARTCTL_TIMEOUT_SECONDS=8
SMARTCTL_PARALLEL=4
SMARTCTL_VERSION_MAJOR=""
SMARTCTL_VERSION_CHECKED=false
NVME_TIMEOUT_SECONDS=6
LSPCI_CACHE=""
LSPCI_CACHE_DONE=false
LSPCI_RESULT=""
LSCPU_CACHE=""
LSCPU_CACHE_DONE=false
LSHW_DISPLAY_CACHE=""
LSHW_DISPLAY_CACHE_DONE=false
LSHW_DISPLAY_RESULT=""
LSHW_DISPLAY_PREFETCH_PID=""
LSHW_DISPLAY_PREFETCH_FILE=""
LSHW_TIMEOUT_SECONDS=15
COLLECT_JSON=false
declare -A DISK_BASIC_INFO_CACHE
declare -A DISK_SMART_FIELDS
declare -A PCIE_NAME_CACHE
# Fields of the SMART JSON currently being parsed (filled by smart_json_load).
declare -A SJ

# Block devices worth a SMART query (sd/vd/xvd/hd, NVMe namespaces, eMMC/SD).
DISK_NAME_REGEX='^([sv]|xv|h)d[a-z]+$|^nvme[0-9]+n[0-9]+$|^mmcblk[0-9]+$'
DISK_NAMES=()
DISK_ENUM_DONE=false

# Background prefetch (smartctl / nvme-cli run in parallel while the first
# sections render). Results land in PREFETCH_DIR; PREFETCH_PID is the dispatcher.
PREFETCH_DIR=""
PREFETCH_PID=""
PREFETCH_DONE=false
CPU_USAGE_RESULT=""
CPU_USAGE_SAMPLED=false
CPU_TEMP_RESULT=""

# Collected memory data. Rendering and JSON assembly consume these instead of
# mixing dmidecode parsing with terminal output.
RAM_TOTAL=""
RAM_USED=""
RAM_AVAILABLE=""
RAM_MODULE_ROWS=()
RAM_FALLBACK_LINES=()
RAM_HAS_DETAILED_MODULES=false
RAM_FIELD_SEP=$'\034'
RAM_ECC_CE=""
RAM_ECC_UE=""

# JSON report data containers
JSON_SYSTEM_KV=()
JSON_CPU_KV=()
JSON_RAM_KV=()
JSON_RAM_MODULES=()
JSON_DISKS=()
JSON_RAID_SW=()
JSON_RAID_HW=()
JSON_NETWORK=()
JSON_GPU=()
JSON_MOTHERBOARD_KV=()
JSON_NVME_DEEP=()
JSON_PLATFORM_KV=()
JSON_RAID_TOOLS=()
JSON_DISK_SMART_KV=()
DISK_JSON_EXTRA=()

# Cleanup: stop the spinner (restoring the cursor), stop any prefetch jobs
# still running (e.g. on Ctrl-C) and remove temporary files.
cleanup_temp_files() {
    spin_stop
    if [[ "$CURSOR_HIDDEN" == true ]]; then
        printf '\033[?25h'
        CURSOR_HIDDEN=false
    fi
    if [[ -n "$PREFETCH_PID" ]]; then
        kill "$PREFETCH_PID" 2>/dev/null
        PREFETCH_PID=""
    fi
    if [[ -n "$LSHW_DISPLAY_PREFETCH_PID" ]]; then
        kill "$LSHW_DISPLAY_PREFETCH_PID" 2>/dev/null
        LSHW_DISPLAY_PREFETCH_PID=""
    fi
    local tmp_file=""
    for tmp_file in "${TEMP_FILES[@]}"; do
        [[ -e "$tmp_file" ]] && rm -rf "$tmp_file"
    done
}

# Set trap to cleanup on exit; INT/TERM exit through it as well, so the
# cursor is always restored and background jobs are stopped.
trap cleanup_temp_files EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Colors are real escape bytes (not '\033' text) so every print path agrees.
# setup_colors() blanks them unless stdout is a terminal (see --color/--no-color
# and the NO_COLOR convention, https://no-color.org).
# Shared catbash 256-color palette:
#   accent 81 (cyan) · brand bold 222 (gold) · ok 114 · warn 214 · err 203 ·
#   rule 73 · dim. RED/GREEN/YELLOW/CYAN keep their names (err/ok/warn/accent).
RED=$'\033[38;5;203m'
GREEN=$'\033[38;5;114m'
YELLOW=$'\033[38;5;214m'
CYAN=$'\033[38;5;81m'
WHITE=$'\033[1m'
BRAND=$'\033[1;38;5;222m'
RULE=$'\033[38;5;73m'
DIM=$'\033[2m'
CHIP=$'\033[1;48;5;81;38;5;16m'
BAR_FILL=$'\033[48;5;81m'
BAR_EMPTY=$'\033[48;5;238m'
NC=$'\033[0m'
COLOR_MODE="auto"     # auto | always | never
COLOR_ON=true

setup_colors() {
    local enable=false
    case "$COLOR_MODE" in
        always) enable=true ;;
        never)  enable=false ;;
        *)
            if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
                enable=true
            fi
            ;;
    esac
    if [[ "$enable" != true ]]; then
        RED="" GREEN="" YELLOW="" CYAN="" WHITE="" NC=""
        BRAND="" RULE="" DIM="" CHIP="" BAR_FILL="" BAR_EMPTY=""
        COLOR_ON=false
    fi
}

# Symbols: Unicode in a UTF-8 locale, ASCII otherwise.
if [[ "$UTF8_OK" == true ]]; then
    SYM_OK="✓" SYM_FAIL="✗" SYM_WARN="!" SYM_DOT="·" SYM_ARROW="→"
    SPIN_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
else
    SYM_OK="+" SYM_FAIL="x" SYM_WARN="!" SYM_DOT="-" SYM_ARROW="->"
    SPIN_FRAMES=('|' '/' '-' '\')
fi

# ---------------------------------------------------------------------------
# Spinner for waits longer than ~0.3 s. Only on a terminal (never for --json,
# files or pipes); main() sets SPIN_ENABLED. It runs as a background loop that
# reads its state with builtins and forks nothing but `sleep`, so it does not
# disturb what is being measured. The cursor is hidden while it spins and is
# always restored (spin_stop, and the EXIT/INT/TERM traps).
#   spin_start LABEL [DETAIL] [PREFETCH_DIR]   (dir => progress bar done/total)
#   spin_stop                                   (wipes the line)
# ---------------------------------------------------------------------------
SPIN_ENABLED=false
SPIN_PID=""
CURSOR_HIDDEN=false

# progress_bar_to VAR DONE TOTAL [CELLS] - background-colored cells (width-safe
# in CJK terminals where block glyphs are ambiguous-width); [###---] uncolored.
progress_bar_to() {
    local __out="$1" __done="$2" __total="$3" __cells="${4:-12}" __fill=0 __a="" __b=""
    (( __total > 0 )) && __fill=$(( __done * __cells / __total ))
    (( __fill > __cells )) && __fill=$__cells
    if [[ "$COLOR_ON" == true ]]; then
        printf -v __a '%*s' "$__fill" ''
        printf -v __b '%*s' "$(( __cells - __fill ))" ''
        printf -v "$__out" '%s%s%s%s%s' "$BAR_FILL" "$__a" "$BAR_EMPTY" "$__b" "$NC"
    else
        repeat_char_to __a '#' "$__fill"
        repeat_char_to __b '-' "$(( __cells - __fill ))"
        printf -v "$__out" '[%s%s]' "$__a" "$__b"
    fi
}

spinner_loop() {
    local label="$1" detail="$2" pdir="$3"
    local i=0 start="$SECONDS" frame="" extra="" bar="" total="" n=${#SPIN_FRAMES[@]}
    local -a done_jobs=()
    shopt -s nullglob
    trap - INT TERM EXIT
    sleep 0.3
    while :; do
        frame="${SPIN_FRAMES[i % n]}"
        extra=""
        if [[ -n "$pdir" ]]; then
            total=""
            read -r total 2>/dev/null < "$pdir/total"
            done_jobs=("$pdir"/done.dev.*)
            if [[ "$total" =~ ^[0-9]+$ && "$total" -gt 0 ]]; then
                progress_bar_to bar "${#done_jobs[@]}" "$total" 12
                extra="  $bar ${#done_jobs[@]}/$total"
            fi
        fi
        printf '\r  %s%s%s %s%s%s%s%s %s %ss%s\033[K' "$CYAN" "$frame" "$NC" "$label" \
            "$DIM" "${detail:+ $SYM_DOT $detail}" "$NC" "$extra" "$DIM$SYM_DOT" "$(( SECONDS - start ))" "$NC"
        i=$((i + 1))
        sleep 0.125
    done
}

spin_start() {
    [[ "$SPIN_ENABLED" == true ]] || return 0
    spin_stop
    printf '\033[?25l'
    CURSOR_HIDDEN=true
    spinner_loop "$1" "${2:-}" "${3:-}" </dev/null 2>/dev/null &
    SPIN_PID=$!
}

spin_stop() {
    [[ -n "$SPIN_PID" ]] || return 0
    kill "$SPIN_PID" 2>/dev/null
    wait "$SPIN_PID" 2>/dev/null
    SPIN_PID=""
    printf '\r\033[K\033[?25h'
    CURSOR_HIDDEN=false
}

# True when /dev/tty can actually be opened. `[[ -r /dev/tty ]]` is not enough:
# without a controlling terminal (ssh without -t, cron, CI, containers) the node
# has rw permissions but open() fails with ENXIO.
have_tty() {
    { : </dev/tty; } 2>/dev/null
}

# Default language
LANG_MODE="en"
OUTPUT_MODE="text"
QUIET_MODE=false
AUTO_YES=false        # -y/--yes : install missing deps without prompting
NO_INSTALL=false      # --no-install : never install, just report with what's present
NO_CLEAR=false        # --no-clear : keep the terminal contents

# Language definitions
declare -A LABELS_EN=(
    ["title"]="System Hardware Information Report"
    ["system_info"]="System Information"
    ["cpu_info"]="CPU Information"
    ["ram_info"]="Memory (RAM) Information"
    ["disk_info"]="Disk Drive Information"
    ["raid_info"]="RAID Controller Information"
    ["network_info"]="Network Interface Information"
    ["gpu_info"]="Graphics Card Information"
    ["motherboard_info"]="Motherboard Information"
    ["ecc_info"]="ECC / Memory RAS Information"
    ["nvme_deep_info"]="NVMe Deep Health"
    ["pcie_info"]="PCIe Link Status"
    ["platform_info"]="CPU / Platform Status"
    ["storage_info"]="Filesystem / Storage Stack"
    ["hostname"]="Hostname"
    ["os"]="Operating System"
    ["kernel"]="Kernel Version"
    ["uptime"]="System Uptime"
    ["model"]="Model"
    ["cores"]="Cores"
    ["threads"]="Threads"
    ["frequency"]="Frequency"
    ["cache"]="Cache"
    ["usage"]="Usage"
    ["total"]="Total"
    ["used"]="Used"
    ["free"]="Free"
    ["available"]="Available"
    ["speed"]="Speed"
    ["type"]="Type"
    ["size"]="Size"
    ["vendor"]="Vendor"
    ["status"]="Status"
    ["temperature"]="Temperature"
    ["manufacturer"]="Manufacturer"
    ["configured_speed"]="Configured Speed"
    ["power_on_hours"]="Power On Hours"
    ["total_reads"]="Total Reads"
    ["total_writes"]="Total Writes"
    ["health_status"]="Health Status"
    ["smart_status"]="SMART Status"
    ["wear_level"]="Remaining Lifetime"
    ["driver"]="Driver"
    ["resolution"]="Resolution"
    ["memory"]="Memory"
    ["duplex"]="Duplex"
    ["link_detected"]="Link Detected"
    ["serial_number"]="Serial Number"
    ["no_info"]="No information available"
    ["not_detected"]="Not detected"
    ["generating"]="Generating hardware report..."
    ["completed"]="Report generation completed!"
    ["percentage_used"]="Percentage Used"
    ["available_spare"]="Available Spare"
    ["critical_warning"]="Critical Warning"
    ["mac_address"]="MAC Address"
    ["cpu_temperature"]="CPU Temperature"
    ["core_temps"]="Core Temperatures"
    ["cpu_temp_high"]="High Temperature Warning"
    ["requires_root_sensors"]="Requires root/sensors"
    ["reallocated_sectors"]="Reallocated Sectors"
    ["pending_sectors"]="Pending Sectors"
    ["offline_uncorrectable"]="Offline Uncorrectable"
    ["reported_uncorrect"]="Reported Uncorrectable"
    ["uncorrected_errors"]="Uncorrected Errors"
    ["grown_defects"]="Grown Defect List"
    ["non_medium_errors"]="Non-medium Errors"
    ["bad_blocks"]="Bad Blocks"
    ["filesystem"]="Filesystem"
    ["warning"]="Warning"
    ["root_note"]="Note: Some hardware information requires root privileges."
    ["root_hint"]="Run with sudo for complete information."
    ["generated_on"]="Generated on"
    ["platform"]="Platform"
    ["hw_virt"]="Virtualization"
    ["hypervisor"]="Hypervisor"
    ["microcode"]="Microcode"
    ["governor"]="CPU Governor"
    ["turbo"]="Turbo Boost"
    ["yes"]="Yes"
    ["no"]="No"
    ["enabled"]="Enabled"
    ["disabled"]="Disabled"
    ["version"]="Version"
    ["bios_vendor"]="BIOS Vendor"
    ["bios_version"]="BIOS Version"
    ["nvme_cli_missing"]="nvme-cli not installed"
    ["dmidecode_required"]="(dmidecode required)"
    ["ram_need_root"]="Root privileges required for detailed memory information"
    ["ram_need_dmidecode"]="dmidecode not installed; per-module details unavailable"
    ["ram_lshw"]="Alternative detection using lshw:"
    ["ram_dmidecode_try"]="Attempting dmidecode (may fail without root):"
    ["mdadm_arrays"]="mdadm arrays"
    ["details_in_json"]="(details in JSON)"
    ["needs_root"]="needs root"
    ["ecc_errors"]="ECC Errors"
)

declare -A LABELS_CN=(
    ["title"]="系统硬件信息报告"
    ["system_info"]="系统信息"
    ["cpu_info"]="处理器信息"
    ["ram_info"]="内存信息"
    ["disk_info"]="硬盘信息"
    ["raid_info"]="RAID控制器信息"
    ["network_info"]="网卡信息"
    ["gpu_info"]="显卡信息"
    ["motherboard_info"]="主板信息"
    ["ecc_info"]="ECC / 内存 RAS 信息"
    ["nvme_deep_info"]="NVMe 深度健康"
    ["pcie_info"]="PCIe 链路状态"
    ["platform_info"]="CPU / 平台状态"
    ["storage_info"]="文件系统 / 存储栈"
    ["hostname"]="主机名"
    ["os"]="操作系统"
    ["kernel"]="内核版本"
    ["uptime"]="运行时间"
    ["model"]="型号"
    ["cores"]="核心数"
    ["threads"]="线程数"
    ["frequency"]="频率"
    ["cache"]="缓存"
    ["usage"]="使用率"
    ["total"]="总计"
    ["used"]="已用"
    ["free"]="空闲"
    ["available"]="可用"
    ["speed"]="速度"
    ["type"]="类型"
    ["size"]="大小"
    ["vendor"]="厂商"
    ["status"]="状态"
    ["temperature"]="温度"
    ["manufacturer"]="制造商"
    ["configured_speed"]="配置速度"
    ["power_on_hours"]="通电时间"
    ["total_reads"]="总读取量"
    ["total_writes"]="总写入量"
    ["health_status"]="健康状态"
    ["smart_status"]="SMART状态"
    ["wear_level"]="剩余寿命"
    ["driver"]="驱动程序"
    ["resolution"]="分辨率"
    ["memory"]="显存"
    ["duplex"]="双工模式"
    ["link_detected"]="链接检测"
    ["serial_number"]="序列号"
    ["no_info"]="无可用信息"
    ["not_detected"]="未检测到"
    ["generating"]="正在生成硬件报告..."
    ["completed"]="报告生成完成！"
    ["percentage_used"]="已使用耐久度"
    ["available_spare"]="可用备用块"
    ["critical_warning"]="关键警告"
    ["mac_address"]="MAC地址"
    ["cpu_temperature"]="CPU温度"
    ["core_temps"]="核心温度"
    ["cpu_temp_high"]="高温警告"
    ["requires_root_sensors"]="需要root权限/sensors命令"
    ["reallocated_sectors"]="重映射扇区"
    ["pending_sectors"]="待处理扇区"
    ["offline_uncorrectable"]="离线不可校正"
    ["reported_uncorrect"]="报告的不可校正"
    ["uncorrected_errors"]="未校正错误"
    ["grown_defects"]="增长缺陷列表"
    ["non_medium_errors"]="非介质错误"
    ["bad_blocks"]="坏块统计"
    ["filesystem"]="文件系统"
    ["warning"]="警告"
    ["root_note"]="提示：部分硬件信息需要 root 权限。"
    ["root_hint"]="请使用 sudo 运行以获取完整信息。"
    ["generated_on"]="生成时间"
    ["platform"]="平台"
    ["hw_virt"]="硬件虚拟化"
    ["hypervisor"]="虚拟化环境"
    ["microcode"]="微码版本"
    ["governor"]="调频策略"
    ["turbo"]="睿频加速"
    ["yes"]="是"
    ["no"]="否"
    ["enabled"]="已启用"
    ["disabled"]="已禁用"
    ["version"]="版本"
    ["bios_vendor"]="BIOS 厂商"
    ["bios_version"]="BIOS 版本"
    ["nvme_cli_missing"]="未安装 nvme-cli"
    ["dmidecode_required"]="（需要 dmidecode）"
    ["ram_need_root"]="需要 root 权限才能获取详细内存信息"
    ["ram_need_dmidecode"]="未安装 dmidecode，无法获取内存模组详情"
    ["ram_lshw"]="使用 lshw 检测:"
    ["ram_dmidecode_try"]="尝试 dmidecode（非 root 可能失败）:"
    ["mdadm_arrays"]="mdadm 阵列"
    ["details_in_json"]="（详情见 JSON 输出）"
    ["needs_root"]="需要 root"
    ["ecc_errors"]="ECC 错误"
)

# Labels for the active language. Code reads ${LBL[key]} directly: a
# "$(get_label key)" substitution forks a subshell for every label.
declare -A LBL
init_labels() {
    local key=""
    LBL=()
    if [[ "$LANG_MODE" == "cn" ]]; then
        for key in "${!LABELS_CN[@]}"; do LBL[$key]="${LABELS_CN[$key]}"; done
    else
        for key in "${!LABELS_EN[@]}"; do LBL[$key]="${LABELS_EN[$key]}"; done
    fi
}
init_labels

# Function to get label based on current language (kept for compatibility)
get_label() {
    printf '%s\n' "${LBL[$1]}"
}

# Function to print colored output
print_color() {
    [[ "$QUIET_MODE" == true ]] && return
    local color="$1"
    local text="$2"
    printf '%s%s%s\n' "$color" "$text" "$NC"
}

# JSON helpers. The *_to variants write into a variable (printf -v) so that
# building a document costs no subshells; the plain forms print for "$(...)".
json_escape_to() {
    local __je="$2"
    __je=${__je//\\/\\\\}
    __je=${__je//\"/\\\"}
    __je=${__je//$'\n'/\\n}
    __je=${__je//$'\r'/\\r}
    __je=${__je//$'\t'/\\t}
    __je=${__je//$'\b'/\\b}
    __je=${__je//$'\f'/\\f}
    # Any other C0 control byte (e.g. ESC or NUL padding in DMI/SMART strings)
    # is invalid inside a JSON string; drop it.
    __je=${__je//[$'\001'-$'\037']/}
    printf -v "$1" '%s' "$__je"
}

json_escape() {
    local __jr=""
    json_escape_to __jr "$1"
    printf '%s' "$__jr"
}

# json_value_to VAR VALUE [s] - number when VALUE looks numeric, else a
# string; "" becomes null. Pass "s" to force a string (serials, versions,
# firmware: "2.10" must not turn into the number 2.1). Integers longer than 15
# digits stay strings so JSON parsers do not round them.
json_value_to() {
    local __jv="$2" __jesc=""
    if [[ -z "$__jv" ]]; then
        printf -v "$1" '%s' 'null'
    elif [[ "${3:-}" != "s" && "$__jv" =~ ^-?(0|[1-9][0-9]{0,14})(\.[0-9]+)?$ ]]; then
        printf -v "$1" '%s' "$__jv"
    else
        json_escape_to __jesc "$__jv"
        printf -v "$1" '"%s"' "$__jesc"
    fi
}

json_value() {
    [[ "$COLLECT_JSON" == true ]] || return
    local __jvr=""
    json_value_to __jvr "$1" "${2:-}"
    printf '%s' "$__jvr"
}

# json_kv_to VAR KEY VALUE [s] - VAR='"KEY":value'
json_kv_to() {
    local __jkv=""
    json_value_to __jkv "$3" "${4:-}"
    printf -v "$1" '"%s":%s' "$2" "$__jkv"
}

json_kv() {
    [[ "$COLLECT_JSON" == true ]] || return
    local __jkr=""
    json_kv_to __jkr "$1" "$2" "${3:-}"
    printf '%s' "$__jkr"
}

# String-typed variant of json_kv.
json_kv_s() {
    json_kv "$1" "$2" s
}

json_kv_raw() {
    [[ "$COLLECT_JSON" == true ]] || return
    local key="$1"
    local raw="$2"
    printf '"%s":%s' "$key" "$raw"
}

json_join() {
    local IFS=,
    printf '%s' "$*"
}

json_obj() {
    [[ "$COLLECT_JSON" == true ]] || return
    local IFS=,
    printf '{%s}' "$*"
}

json_array() {
    [[ "$COLLECT_JSON" == true ]] || return
    local IFS=,
    printf '[%s]' "$*"
}

json_array_values() {
    [[ "$COLLECT_JSON" == true ]] || return
    local vals=()
    local v=""
    local jv=""
    for v in "$@"; do
        [[ -z "$v" ]] && continue
        json_value_to jv "$v" s
        vals+=("$jv")
    done
    json_array "${vals[@]}"
}

json_reset() {
    JSON_SYSTEM_KV=()
    JSON_CPU_KV=()
    JSON_RAM_KV=()
    JSON_RAM_MODULES=()
    JSON_DISKS=()
    JSON_RAID_SW=()
    JSON_RAID_HW=()
    JSON_NETWORK=()
    JSON_GPU=()
    JSON_MOTHERBOARD_KV=()
    JSON_NVME_DEEP=()
    JSON_PLATFORM_KV=()
    JSON_RAID_TOOLS=()
    JSON_DISK_SMART_KV=()
    DISK_JSON_EXTRA=()
}

disk_smart_reset() {
    JSON_DISK_SMART_KV=()
    DISK_SMART_FIELDS=()
}

disk_smart_add() {
    local key="$1"
    local val="$2"
    [[ -z "$key" || -z "$val" ]] && return
    DISK_SMART_FIELDS[$key]="$val"
    [[ "$COLLECT_JSON" == true ]] || return
    local kv=""
    json_kv_to kv "$key" "$val"
    JSON_DISK_SMART_KV+=("$kv")
}

disk_extra_add() {
    local key="$1"
    local val="$2"
    [[ "$COLLECT_JSON" == true ]] || return
    [[ -z "$key" || -z "$val" ]] && return
    local kv=""
    json_kv_to kv "$key" "$val" "${3:-}"
    DISK_JSON_EXTRA+=("$kv")
}

disk_json_add() {
    local category="$1"
    local name="$2"
    local basic_info="$3"
    local pairs=()

    if [[ "$COLLECT_JSON" != true ]]; then
        DISK_JSON_EXTRA=()
        JSON_DISK_SMART_KV=()
        return
    fi

    local kv="" IFS=,
    json_kv_to kv "category" "$category"; pairs+=("$kv")
    json_kv_to kv "name" "$name" s; pairs+=("$kv")
    if [[ -n "$basic_info" ]]; then
        json_kv_to kv "basic_info" "$basic_info" s; pairs+=("$kv")
    fi

    if [[ ${#DISK_JSON_EXTRA[@]} -gt 0 ]]; then
        pairs+=("${DISK_JSON_EXTRA[@]}")
    fi
    if [[ ${#JSON_DISK_SMART_KV[@]} -gt 0 ]]; then
        pairs+=("\"smart\":{${JSON_DISK_SMART_KV[*]}}")
    fi

    JSON_DISKS+=("{${pairs[*]}}")
    DISK_JSON_EXTRA=()
    JSON_DISK_SMART_KV=()
}

# ---------------------------------------------------------------------------
# Health verdict. Sections call health_add while they collect; the text report
# ends with a summary block (render_health) and JSON gets
#   "health":{"status":"ok|warn|fail","issues":[{severity,subject,detail}]}.
# Severity: fail = needs action, warn = watch. The exit code stays 0.
# ---------------------------------------------------------------------------
HEALTH_SEV=()
HEALTH_SUBJ=()
HEALTH_EN=()
HEALTH_CN=()
declare -A HEALTH_SEEN

# health_add SEVERITY SUBJECT KIND DETAIL_EN [DETAIL_CN]
# KIND de-duplicates one problem seen by two sources (smartctl and nvme-cli);
# a later "fail" upgrades an earlier "warn".
health_add() {
    local sev="$1" subj="$2" key="$2|$3" idx=""
    idx="${HEALTH_SEEN[$key]:-}"
    if [[ -n "$idx" ]]; then
        if [[ "$sev" == "fail" && "${HEALTH_SEV[$idx]}" != "fail" ]]; then
            HEALTH_SEV[$idx]="fail"
            HEALTH_EN[$idx]="$4"
            HEALTH_CN[$idx]="${5:-$4}"
        fi
        return
    fi
    HEALTH_SEEN[$key]="${#HEALTH_SEV[@]}"
    HEALTH_SEV+=("$sev")
    HEALTH_SUBJ+=("$subj")
    HEALTH_EN+=("$4")
    HEALTH_CN+=("${5:-$4}")
}

health_is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

# Disk issues from DISK_SMART_FIELDS (+ SJ for fields the summary does not keep).
# health_check_disk SUBJECT IS_NVME
health_check_disk() {
    local subj="$1" is_nvme="${2:-false}"
    local st="${DISK_SMART_FIELDS[smart_status]:-}"
    local re="${DISK_SMART_FIELDS[reallocated_sectors]:-}"
    local pe="${DISK_SMART_FIELDS[pending_sectors]:-}"
    local of="${DISK_SMART_FIELDS[offline_uncorrectable]:-}"
    local ru="${DISK_SMART_FIELDS[reported_uncorrect]:-}"
    local gd="${DISK_SMART_FIELDS[grown_defects]:-}"
    local ue="${DISK_SMART_FIELDS[uncorrected_errors]:-}"
    local pu="${DISK_SMART_FIELDS[percentage_used]:-}"
    local cw="${DISK_SMART_FIELDS[critical_warning]:-}"
    local temp="${DISK_SMART_FIELDS[temperature]:-}"
    local me="${SJ[media_errors]:-}" wl="${SJ[wear_level]:-}" wname="${SJ[wear_name]:-}"
    local -a en=() cn=()
    local limit=60

    case "${st^^}" in
        *FAIL*) health_add fail "$subj" smart "SMART health check failed" "SMART 自检失败" ;;
    esac

    if health_is_uint "$re" && (( re > 0 )); then en+=("$re reallocated sectors"); cn+=("重映射扇区 $re"); fi
    if health_is_uint "$pe" && (( pe > 0 )); then en+=("$pe pending"); cn+=("待处理扇区 $pe"); fi
    if health_is_uint "$of" && (( of > 0 )); then en+=("$of offline uncorrectable"); cn+=("离线不可纠正 $of"); fi
    if [[ ${#en[@]} -gt 0 ]]; then
        local d_en="${en[0]}" d_cn="${cn[0]}" k=1
        while (( k < ${#en[@]} )); do d_en+=", ${en[$k]}"; d_cn+="，${cn[$k]}"; k=$((k + 1)); done
        health_add fail "$subj" sectors "$d_en" "$d_cn"
    fi
    if health_is_uint "$ue" && (( ue > 0 )); then
        health_add fail "$subj" uncorrected "$ue uncorrected errors" "未校正错误 $ue"
    fi
    if health_is_uint "$ru" && (( ru > 0 )); then
        health_add warn "$subj" reported "$ru reported uncorrectable errors" "报告不可纠正错误 $ru"
    fi
    if health_is_uint "$gd" && (( gd > 0 )); then
        health_add warn "$subj" grown "$gd grown defects" "增长缺陷 $gd"
    fi
    if health_is_uint "$cw" && (( cw != 0 )); then
        health_add fail "$subj" nvme_cw "NVMe critical warning $cw" "NVMe 严重告警 $cw"
    fi
    if health_is_uint "$me" && (( me > 0 )); then
        health_add fail "$subj" media "$me media errors" "介质错误 $me"
    fi
    if health_is_uint "$pu"; then
        if (( pu >= 100 )); then
            health_add fail "$subj" wear "${pu}% of rated endurance used" "已用寿命 ${pu}%"
        elif (( pu >= 80 )); then
            health_add warn "$subj" wear "${pu}% of rated endurance used" "已用寿命 ${pu}%"
        fi
    elif health_is_uint "$wl" && [[ "$wname" =~ Wear|Life|wear|life ]] && (( wl <= 20 )); then
        # ATA SSD wear attributes count down from 100 (= new)
        health_add warn "$subj" wear "${wl}% life left" "剩余寿命 ${wl}%"
    fi
    temp="${temp%%°*}"
    [[ "$is_nvme" == true ]] && limit=70
    if health_is_uint "$temp" && (( temp >= limit )); then
        health_add warn "$subj" temp "temperature ${temp}°C" "温度 ${temp}°C"
    fi
}

# Why the verdict may be incomplete (empty when nothing limits it).
health_limit_note_to() {
    local __n=""
    if [[ $EUID -ne 0 ]]; then
        __n="without root: SMART / RAID / DIMM data not readable"
        [[ "$LANG_MODE" == "cn" ]] && __n="非 root 运行：无法读取 SMART / RAID / 内存条数据"
    elif ! command -v smartctl >/dev/null 2>&1; then
        __n="smartctl not installed: disk health not checked"
        [[ "$LANG_MODE" == "cn" ]] && __n="未安装 smartctl：未检查硬盘健康"
    fi
    printf -v "$1" '%s' "$__n"
}

# Text block at the end of the report.
render_health() {
    [[ "$QUIET_MODE" == true ]] && return
    local fails=0 warns=0 i=0 title="Health" fill="" sev="" subj="" detail="" sw=0 w=0 pad=0
    [[ "$LANG_MODE" == "cn" ]] && title="健康检查"
    for sev in "${HEALTH_SEV[@]}"; do
        if [[ "$sev" == "fail" ]]; then fails=$((fails + 1)); else warns=$((warns + 1)); fi
    done
    get_display_width "$title"
    repeat_char_to fill '─' "$(( 47 - DISPLAY_WIDTH_RESULT ))"
    echo
    printf '%s── %s%s%s %s%s\n' "$RULE" "$BRAND" "$title" "$NC$RULE" "$fill" "$NC"

    local limit_note=""
    health_limit_note_to limit_note
    if (( fails + warns == 0 )); then
        if [[ "$LANG_MODE" == "cn" ]]; then
            printf '%s%s%s 未发现问题\n' "$GREEN" "$SYM_OK" "$NC"
        else
            printf '%s%s%s No problems found\n' "$GREEN" "$SYM_OK" "$NC"
        fi
        [[ -n "$limit_note" ]] && printf '  %s%s %s%s\n' "$DIM" "$SYM_DOT" "$limit_note" "$NC"
        return
    fi

    local summary="" part=""
    if (( fails > 0 )); then
        if [[ "$LANG_MODE" == "cn" ]]; then part="$fails 个问题"
        elif (( fails == 1 )); then part="1 problem"; else part="$fails problems"; fi
        summary="${RED}${SYM_FAIL} ${part}${NC}"
    fi
    if (( warns > 0 )); then
        if [[ "$LANG_MODE" == "cn" ]]; then part="$warns 个警告"
        elif (( warns == 1 )); then part="1 warning"; else part="$warns warnings"; fi
        summary+="${summary:+ $DIM$SYM_DOT$NC }${YELLOW}${SYM_WARN} ${part}${NC}"
    fi
    printf '%s\n' "$summary"

    # Subject column: widest subject (capped) so details line up
    for subj in "${HEALTH_SUBJ[@]}"; do
        get_display_width "$subj"
        (( DISPLAY_WIDTH_RESULT > sw )) && sw=$DISPLAY_WIDTH_RESULT
    done
    (( sw < 8 )) && sw=8
    (( sw > 18 )) && sw=18

    # Problems first, then warnings; within each, one subject's lines together
    local -a subjects=()
    local -A seen_subj=()
    for subj in "${HEALTH_SUBJ[@]}"; do
        [[ -n "${seen_subj[$subj]:-}" ]] && continue
        seen_subj[$subj]=1
        subjects+=("$subj")
    done
    local group=""
    for sev in fail warn; do
      for group in "${subjects[@]}"; do
        for i in "${!HEALTH_SEV[@]}"; do
            [[ "${HEALTH_SEV[$i]}" == "$sev" && "${HEALTH_SUBJ[$i]}" == "$group" ]] || continue
            subj="${HEALTH_SUBJ[$i]}"
            detail="${HEALTH_EN[$i]}"
            [[ "$LANG_MODE" == "cn" ]] && detail="${HEALTH_CN[$i]}"
            get_display_width "$subj"
            w=$DISPLAY_WIDTH_RESULT
            pad=$(( sw - w ))
            (( pad < 0 )) && pad=0
            if [[ "$sev" == "fail" ]]; then
                printf '  %s%s%s %s%*s  %s\n' "$RED" "$SYM_FAIL" "$NC" "$subj" "$pad" '' "$detail"
            else
                printf '  %s%s%s %s%*s  %s\n' "$YELLOW" "$SYM_WARN" "$NC" "$subj" "$pad" '' "$detail"
            fi
        done
      done
    done
    [[ -n "$limit_note" ]] && printf '  %s%s %s%s\n' "$DIM" "$SYM_DOT" "$limit_note" "$NC"
    return 0
}

# JSON object for build_json_report (details always in English).
health_json() {
    local status="ok" i="" sev="" kv1="" kv2="" kv3=""
    local -a items=()
    for sev in "${HEALTH_SEV[@]}"; do
        if [[ "$sev" == "fail" ]]; then status="fail"; elif [[ "$status" == "ok" ]]; then status="warn"; fi
    done
    for sev in fail warn; do
        for i in "${!HEALTH_SEV[@]}"; do
            [[ "${HEALTH_SEV[$i]}" == "$sev" ]] || continue
            json_kv_to kv1 severity "$sev" s
            json_kv_to kv2 subject "${HEALTH_SUBJ[$i]}" s
            json_kv_to kv3 detail "${HEALTH_EN[$i]}" s
            items+=("{$kv1,$kv2,$kv3}")
        done
    done
    local limited=false
    [[ $EUID -ne 0 ]] && limited=true
    command -v smartctl >/dev/null 2>&1 || limited=true
    local IFS=,
    printf '{"status":"%s","checks_limited":%s,"issues":[%s]}' "$status" "$limited" "${items[*]}"
}

# slurp_file VAR FILE - whole file into VAR without forking a subshell.
# Trailing newlines are dropped, like $(<FILE).
slurp_file() {
    local __data=""
    IFS= read -r -d '' __data 2>/dev/null < "$2"
    while [[ "$__data" == *$'\n' ]]; do __data="${__data%$'\n'}"; done
    printf -v "$1" '%s' "$__data"
}

# read_line VAR FILE - first line of FILE into VAR (empty when unreadable).
# Used for sysfs/procfs attributes; no subshell, no error noise.
read_line() {
    local __line=""
    IFS= read -r __line 2>/dev/null < "$2"
    printf -v "$1" '%s' "$__line"
}

# repeat_char_to VAR CHAR COUNT - like repeat_char, into VAR (no subshell)
repeat_char_to() {
    local __rc=""
    if [[ -n "$3" && "$3" -gt 0 ]]; then
        printf -v __rc '%*s' "$3" ''
        __rc=${__rc// /$2}
    fi
    printf -v "$1" '%s' "$__rc"
}

# Function to repeat a character N times without external commands
repeat_char() {
    local char="$1"
    local count="$2"
    local out=""

    if [[ -z "$count" || "$count" -le 0 ]]; then
        return
    fi

    printf -v out '%*s' "$count" ''
    out=${out// /$char}
    printf '%s' "$out"
}

# Function to print section header
print_header() {
    [[ "$QUIET_MODE" == true ]] && return
    local title="$1"
    local width=80
    local rule="" line=""
    # Center by display width so CJK titles (2 columns per glyph) line up too.
    get_display_width "$title"
    local left=$(( (width - DISPLAY_WIDTH_RESULT) / 2 ))
    local right=$(( width - DISPLAY_WIDTH_RESULT - left ))
    (( left < 0 )) && left=0
    (( right < 0 )) && right=0
    repeat_char_to rule '═' "$width"
    printf -v line '%*s%s%*s' "$left" '' "$title" "$right" ''

    echo
    print_color "$RULE" "$rule"
    print_color "$BRAND" "$line"
    print_color "$RULE" "$rule"
    echo
}

# Header chip shared by the catbash tools:  " SICK " v3.2.0 · tagline
print_brand_chip() {
    [[ "$QUIET_MODE" == true ]] && return
    local tagline="Server Info & Check Kit"
    [[ "$LANG_MODE" == "cn" ]] && tagline="服务器硬件检查"
    if [[ "$COLOR_ON" == true ]]; then
        printf '%s SICK %s v%s%s %s %s%s\n' "$CHIP" "$NC" "$VERSION" "$DIM" "$SYM_DOT" "$tagline" "$NC"
    else
        printf '[SICK] v%s %s %s\n' "$VERSION" "$SYM_DOT" "$tagline"
    fi
}

# Closing line of a section (precomputed; no subshell per section).
SECTION_END_LINE="└──────────────────────────────────────────────────"
section_end() {
    printf '%s\n' "$SECTION_END_LINE"
}

# Function to print sub-section
print_subsection() {
    [[ "$QUIET_MODE" == true ]] && return
    local title="$1"
    local width=50
    get_display_width "$title"
    local title_width="$DISPLAY_WIDTH_RESULT"
    local fill=$((width - title_width - 4))

    [[ "$fill" -lt 1 ]] && fill=1
    local fill_line="" rule_line=""
    repeat_char_to fill_line '─' "$fill"
    repeat_char_to rule_line '─' "$width"
    printf '%s┌─ %s%s%s %s%s\n' "$RULE" "$BRAND" "$title" "$NC$RULE" "$fill_line" "$NC"
    print_color "$RULE" "├$rule_line"
}

# Function to calculate display width of string (considering CJK characters)
# Pure-bash, no subprocess: byte count via a C-locale ${#..}, char count via the
# current UTF-8 locale ${#..}. Each CJK codepoint is 3 bytes / 1 char and renders
# 2 cols wide, so display_width = char_count + (byte_count - char_count)/2.
get_display_width() {
    local str="$1"

    if [[ -z "$str" ]]; then
        DISPLAY_WIDTH_RESULT=0
        return
    fi

    if [[ ${DISPLAY_WIDTH_CACHE[$str]+_} ]]; then
        DISPLAY_WIDTH_RESULT="${DISPLAY_WIDTH_CACHE[$str]}"
        return
    fi

    local char_count=${#str}
    local byte_count
    # Localize LC_ALL=C in this scope so ${#str} counts bytes, not characters.
    local LC_ALL=C
    byte_count=${#str}
    unset LC_ALL

    local display_width
    if (( byte_count == char_count )); then
        display_width=$char_count
    else
        # In UTF-8: ASCII=1 byte, CJK=3 bytes. cjk = (bytes - chars)/2,
        # display = chars + cjk. (Approximation; good enough for alignment.)
        display_width=$(( char_count + (byte_count - char_count) / 2 ))
    fi

    if (( char_count <= 64 )); then
        DISPLAY_WIDTH_CACHE[$str]=$display_width
    fi

    DISPLAY_WIDTH_RESULT="$display_width"
}

# Function to print info line with proper alignment
print_info() {
    [[ "$QUIET_MODE" == true ]] && return
    local label="$1"
    local value="$2"
    local target_width=20
    
    # Calculate the actual display width of the label
    get_display_width "$label"
    local label_width="$DISPLAY_WIDTH_RESULT"
    
    # Calculate needed padding
    local padding=$((target_width - label_width))
    if [[ $padding -lt 0 ]]; then
        padding=0
    fi
    
    # Print with calculated padding
    printf "│ %s%*s: %s\n" "$label" $padding "" "$value"
}

# Like print_info but colorizes the value.
print_info_colored() {
    [[ "$QUIET_MODE" == true ]] && return
    local label="$1"
    local value="$2"
    local color="${3:-}"
    local target_width=20

    get_display_width "$label"
    local label_width="$DISPLAY_WIDTH_RESULT"
    local padding=$((target_width - label_width))
    [[ $padding -lt 0 ]] && padding=0

    if [[ -n "$color" ]]; then
        printf "│ %s%*s: %b%s%b\n" "$label" $padding "" "$color" "$value" "$NC"
    else
        printf "│ %s%*s: %s\n" "$label" $padding "" "$value"
    fi
}

# Aligned warning/note line under a section: "│   ! <tag padded>  <detail>".
print_note() {
    [[ "$QUIET_MODE" == true ]] && return
    local tag="$1"
    local detail="$2"
    local color="${3:-$YELLOW}"
    local mark="${4:-$SYM_WARN}"
    local tagw=14
    get_display_width "$tag"
    local pad=$((tagw - DISPLAY_WIDTH_RESULT))
    [[ $pad -lt 0 ]] && pad=0
    printf "│   %b%s %s%*s  %s%b\n" "$color" "$mark" "$tag" "$pad" "" "$detail" "$NC"
}

print_wrapped_line() {
    [[ "$QUIET_MODE" == true ]] && return
    local prefix="$1"
    local text="${2:-}"
    local cont_prefix="${3:-$prefix}"
    local color="${4:-}"
    local max_width="${5:-78}"
    local current_prefix="$prefix"
    local available=0
    local chunk="" candidate="" rest="" cut=0

    [[ -z "$text" ]] && text="-"

    while [[ -n "$text" ]]; do
        get_display_width "$current_prefix"
        available=$((max_width - DISPLAY_WIDTH_RESULT))
        [[ "$available" -lt 10 ]] && available=10

        get_display_width "$text"
        if [[ "$DISPLAY_WIDTH_RESULT" -le "$available" ]]; then
            if [[ -n "$color" ]]; then
                printf '%s%b%s%b\n' "$current_prefix" "$color" "$text" "$NC"
            else
                printf '%s%s\n' "$current_prefix" "$text"
            fi
            break
        fi

        cut="$available"
        [[ "$cut" -gt "${#text}" ]] && cut="${#text}"
        chunk="${text:0:$cut}"
        while true; do
            get_display_width "$chunk"
            [[ "$DISPLAY_WIDTH_RESULT" -le "$available" || "$cut" -le 1 ]] && break
            cut=$((cut - 1))
            chunk="${text:0:$cut}"
        done

        candidate="${chunk% *}"
        if [[ "$candidate" != "$chunk" && ${#candidate} -ge 16 ]]; then
            chunk="$candidate"
            cut="${#chunk}"
        fi

        rest="${text:$cut}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        if [[ -n "$rest" && ${#rest} -lt 8 && "$chunk" == *" "* ]]; then
            candidate="${chunk% *}"
            if [[ "$candidate" != "$chunk" && ${#candidate} -ge 16 ]]; then
                chunk="$candidate"
                cut="${#chunk}"
            fi
        fi

        if [[ -n "$color" ]]; then
            printf '%s%b%s%b\n' "$current_prefix" "$color" "$chunk" "$NC"
        else
            printf '%s%s\n' "$current_prefix" "$chunk"
        fi

        rest="${text:$cut}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        text="$rest"
        current_prefix="$cont_prefix"
    done
}

print_detail_line() {
    local label="$1"
    local value="$2"
    local color="${3:-}"
    local label_width=12
    local prefix=""
    local cont_prefix=""
    local label_pad=0

    get_display_width "$label"
    label_pad=$((label_width - DISPLAY_WIDTH_RESULT))
    [[ "$label_pad" -lt 0 ]] && label_pad=0

    printf -v prefix '│   %s%*s: ' "$label" "$label_pad" ''
    printf -v cont_prefix '│   %*s  ' "$label_width" ''
    print_wrapped_line "$prefix" "$value" "$cont_prefix" "$color"
}

# Function to print table cell with proper alignment
print_table_cell() {
    [[ "$QUIET_MODE" == true ]] && return
    local content="$1"
    local width="$2"
    get_display_width "$content"
    local content_width="$DISPLAY_WIDTH_RESULT"
    local padding=$((width - content_width))
    
    if [[ $padding -lt 0 ]]; then
        padding=0
    fi
    
    printf "%s%*s" "$content" $padding ""
}

# Function to print table header
print_table_header() {
    [[ "$QUIET_MODE" == true ]] && return
    local cols=("$@")
    local line="├"
    local header="│"
    
    for col in "${cols[@]}"; do
        line+="$(repeat_char '─' 18)┬"
        header+="$(printf " %-16s │" "$col")"
    done
    
    line="${line%┬}┤"
    print_color "$YELLOW" "$line"
    print_color "$WHITE" "$header"
    
    line="├"
    for col in "${cols[@]}"; do
        line+="$(repeat_char '─' 18)┼"
    done
    line="${line%┼}┤"
    print_color "$YELLOW" "$line"
}

# Function to print table row
print_table_row() {
    [[ "$QUIET_MODE" == true ]] && return
    local cols=("$@")
    local row="│"
    
    for col in "${cols[@]}"; do
        row+="$(printf " %-16s │" "$col")"
    done
    
    echo "$row"
}

fit_display_to() {
    local __result_var="$1"
    local value="${2:-}"
    local width="$3"
    local candidate="$value"

    [[ -z "$candidate" ]] && candidate="-"

    get_display_width "$candidate"
    if [[ "$DISPLAY_WIDTH_RESULT" -gt "$width" ]]; then
        candidate="${candidate:0:$((width - 1))}~"
        while true; do
            get_display_width "$candidate"
            [[ "$DISPLAY_WIDTH_RESULT" -le "$width" || ${#candidate} -le 1 ]] && break
            candidate="${candidate:0:$(( ${#candidate} - 2 ))}~"
        done
    fi

    printf -v "$__result_var" '%s' "$candidate"
}

print_fixed_cell() {
    local value="${1:-}"
    local width="$2"
    local fitted=""
    local pad=0

    fit_display_to fitted "$value" "$width"
    get_display_width "$fitted"
    pad=$((width - DISPLAY_WIDTH_RESULT))
    [[ "$pad" -lt 0 ]] && pad=0
    printf '%s%*s' "$fitted" "$pad" ''
}

print_colored_fixed_cell() {
    local value="${1:-}"
    local width="$2"
    local color="${3:-}"
    local fitted=""
    local pad=0

    fit_display_to fitted "$value" "$width"
    get_display_width "$fitted"
    pad=$((width - DISPLAY_WIDTH_RESULT))
    [[ "$pad" -lt 0 ]] && pad=0

    if [[ -n "$color" ]]; then
        printf '%b%s%b%*s' "$color" "$fitted" "$NC" "$pad" ''
    else
        printf '%s%*s' "$fitted" "$pad" ''
    fi
}

# ---------------------------------------------------------------------------
# Generic bordered table renderer (used by GPU / RAID / Network / NVMe).
# Set TABLE_COL_W to the column widths, then call:
#   table_header  "Col1" "Col2" ...
#   table_row     val1 color1 val2 color2 ...   (color may be "")
#   table_close
# Alignment reuses print_fixed_cell so CJK headers/values stay aligned.
# ---------------------------------------------------------------------------
TABLE_COL_W=()

table_rule() {
    [[ "$QUIET_MODE" == true ]] && return
    local left="$1" right="$2" total=0 w=""
    for w in "${TABLE_COL_W[@]}"; do total=$((total + w)); done
    total=$(( total + 3 * ${#TABLE_COL_W[@]} - 1 ))
    local line=""
    repeat_char_to line '─' "$total"
    printf '%s%s%s\n' "$left" "$line" "$right"
}

table_header() {
    [[ "$QUIET_MODE" == true ]] && return
    local cells=("$@") i=0
    table_rule "├" "┤"
    printf "│ "
    for i in "${!cells[@]}"; do
        print_colored_fixed_cell "${cells[$i]}" "${TABLE_COL_W[$i]}" "$WHITE"
        if (( i < ${#cells[@]} - 1 )); then printf " │ "; else printf " │\n"; fi
    done
    table_rule "├" "┤"
}

table_row() {
    [[ "$QUIET_MODE" == true ]] && return
    local n=$(( $# / 2 )) idx=0 val="" col=""
    printf "│ "
    while (( idx < n )); do
        val="$1"; col="$2"; shift 2
        print_colored_fixed_cell "$val" "${TABLE_COL_W[$idx]}" "$col"
        if (( idx < n - 1 )); then printf " │ "; else printf " │\n"; fi
        ((idx++))
    done
}

table_close() {
    [[ "$QUIET_MODE" == true ]] && return
    table_rule "└" "┘"
}

# Function to read a value from /etc/os-release without sourcing executable shell
get_os_release_value() {
    local key="$1"
    local line=""
    local value=""

    [[ -r /etc/os-release ]] || return 1

    while IFS= read -r line; do
        [[ "$line" == "$key="* ]] || continue
        value="${line#*=}"
        case "$value" in
            \"*\")
                value="${value#\"}"
                value="${value%\"}"
                ;;
            \'*\')
                value="${value#\'}"
                value="${value%\'}"
                ;;
        esac
        printf '%s\n' "$value"
        return 0
    done < /etc/os-release

    return 1
}

# Function to detect distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        get_os_release_value "ID" || echo "unknown"
    elif [[ -f /etc/redhat-release ]]; then
        echo "centos"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    elif [[ -f /etc/SuSE-release ]]; then
        echo "opensuse"
    elif [[ -f /etc/alpine-release ]]; then
        echo "alpine"
    else
        echo "unknown"
    fi
}

# Map one os-release ID token to a package manager (empty if unknown).
pkg_manager_for_id() {
    case "$1" in
        ubuntu|debian|linuxmint|raspbian|pop|elementary|kali|zorin|deepin|uos|\
        kylin|neon|devuan|parrot|mx|armbian|proxmox)
            echo "apt" ;;
        rhel|centos|centos-stream|almalinux|rocky|cloudlinux|ol|amzn|\
        virtuozzo|eurolinux|openeuler|anolis|opencloudos|tencentos|alinux|\
        circle|navy|scientific|fedora)
            if command -v dnf >/dev/null 2>&1; then
                echo "dnf"
            elif command -v yum >/dev/null 2>&1; then
                echo "yum"
            fi
            ;;
        arch|archarm|manjaro|manjaro-arm|endeavouros|garuda|artix|cachyos)
            echo "pacman" ;;
        opensuse|opensuse-leap|opensuse-tumbleweed|opensuse-microos|sles|sled|suse)
            echo "zypper" ;;
        alpine|postmarketos)
            echo "apk" ;;
    esac
}

# Function to get package manager: os-release ID, then each ID_LIKE token
# (covers derivatives we do not list), then whichever tool is installed.
get_package_manager() {
    local distro="" like="" id="" pm=""
    distro=$(detect_distro)
    pm=$(pkg_manager_for_id "${distro,,}")
    if [[ -z "$pm" ]]; then
        like=$(get_os_release_value "ID_LIKE" 2>/dev/null)
        for id in ${like,,}; do
            pm=$(pkg_manager_for_id "$id")
            [[ -n "$pm" ]] && break
        done
    fi
    if [[ -z "$pm" ]]; then
        if command -v apt-get >/dev/null 2>&1; then pm="apt"
        elif command -v dnf >/dev/null 2>&1; then pm="dnf"
        elif command -v yum >/dev/null 2>&1; then pm="yum"
        elif command -v zypper >/dev/null 2>&1; then pm="zypper"
        elif command -v pacman >/dev/null 2>&1; then pm="pacman"
        elif command -v apk >/dev/null 2>&1; then pm="apk"
        fi
    fi
    echo "${pm:-unknown}"
}

get_lspci_output() {
    if [[ "$LSPCI_CACHE_DONE" == true ]]; then
        LSPCI_RESULT="$LSPCI_CACHE"
        return
    fi

    if command -v lspci >/dev/null 2>&1; then
        LSPCI_CACHE=$(run_limited 10 lspci 2>/dev/null)
    else
        LSPCI_CACHE=""
    fi

    LSPCI_CACHE_DONE=true
    LSPCI_RESULT="$LSPCI_CACHE"
}

# lscpu output (C locale), fetched once; used by the CPU and platform sections.
get_lscpu_output() {
    if [[ "$LSCPU_CACHE_DONE" != true ]]; then
        LSCPU_CACHE=""
        command -v lscpu >/dev/null 2>&1 && LSCPU_CACHE=$(LC_ALL=C lscpu 2>/dev/null)
        LSCPU_CACHE_DONE=true
    fi
}

# lscpu_field_to VAR "Field name" - value of one "Field name:   value" line.
lscpu_field_to() {
    local __out="$1" __field="$2" __line="" __val=""
    get_lscpu_output
    while IFS= read -r __line; do
        if [[ "$__line" == "$__field:"* ]]; then
            __val="${__line#*:}"
            __val="${__val#"${__val%%[![:space:]]*}"}"
            break
        fi
    done <<< "$LSCPU_CACHE"
    printf -v "$__out" '%s' "$__val"
}

# lshw is slow (seconds on big boxes). It is only a fallback GPU source when
# lspci is unavailable, so it is prefetched in the background only then, and
# always bounded by a timeout.
get_lshw_display_output() {
    if [[ "$LSHW_DISPLAY_CACHE_DONE" == true ]]; then
        LSHW_DISPLAY_RESULT="$LSHW_DISPLAY_CACHE"
        return
    fi

    if [[ -n "$LSHW_DISPLAY_PREFETCH_PID" ]]; then
        if kill -0 "$LSHW_DISPLAY_PREFETCH_PID" 2>/dev/null; then
            spin_start "lshw" "${LBL[gpu_info]}"
        fi
        wait "$LSHW_DISPLAY_PREFETCH_PID" 2>/dev/null || true
        spin_stop
        LSHW_DISPLAY_PREFETCH_PID=""
        LSHW_DISPLAY_CACHE=""
        if [[ -n "$LSHW_DISPLAY_PREFETCH_FILE" && -f "$LSHW_DISPLAY_PREFETCH_FILE" ]]; then
            slurp_file LSHW_DISPLAY_CACHE "$LSHW_DISPLAY_PREFETCH_FILE"
        fi
        LSHW_DISPLAY_CACHE_DONE=true
        LSHW_DISPLAY_RESULT="$LSHW_DISPLAY_CACHE"
        return
    fi

    if command -v lshw >/dev/null 2>&1; then
        spin_start "lshw" "${LBL[gpu_info]}"
        LSHW_DISPLAY_CACHE=$(run_limited "$LSHW_TIMEOUT_SECONDS" lshw -c display -short 2>/dev/null)
        spin_stop
    else
        LSHW_DISPLAY_CACHE=""
    fi

    LSHW_DISPLAY_CACHE_DONE=true
    LSHW_DISPLAY_RESULT="$LSHW_DISPLAY_CACHE"
}

start_lshw_display_prefetch() {
    if [[ "$LSHW_DISPLAY_CACHE_DONE" == true || -n "$LSHW_DISPLAY_PREFETCH_PID" ]]; then
        return
    fi

    command -v lshw >/dev/null 2>&1 || return
    # lspci is the primary GPU source; lshw is only consulted without it.
    command -v lspci >/dev/null 2>&1 && return

    local tmp_file=""
    tmp_file=$(mktemp 2>/dev/null) || return
    TEMP_FILES+=("$tmp_file")

    run_limited "$LSHW_TIMEOUT_SECONDS" lshw -c display -short > "$tmp_file" 2>/dev/null </dev/null &
    LSHW_DISPLAY_PREFETCH_PID=$!
    LSHW_DISPLAY_PREFETCH_FILE="$tmp_file"
}

# Packages this run installed (only ones that were absent before), for the
# optional cleanup after the report. CLEANUP_MODE: ask | always (--cleanup) |
# never (--keep-packages).
INSTALLED_PKGS=()
INSTALL_PKG_MANAGER=""
CLEANUP_MODE="ask"

# pkg_is_installed PM PKG - 0 installed, 1 not installed, 2 cannot tell
pkg_is_installed() {
    local pm="$1" pkg="$2" st=""
    case "$pm" in
        apt)
            if command -v dpkg-query >/dev/null 2>&1; then
                st=$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null)
            elif command -v dpkg >/dev/null 2>&1; then
                st=$(dpkg -s "$pkg" 2>/dev/null)
            else
                return 2
            fi
            [[ "$st" == *"install ok installed"* ]] ;;
        dnf|yum|zypper)
            command -v rpm >/dev/null 2>&1 || return 2
            rpm -q "$pkg" >/dev/null 2>&1 ;;
        pacman)
            pacman -Q "$pkg" >/dev/null 2>&1 ;;
        apk)
            apk info -e "$pkg" >/dev/null 2>&1 ;;
        *)
            return 2 ;;
    esac
}

# Ask a y/N question on the terminal (works under curl | bash). Returns 0 for
# yes, 1 for no, 2 when there is no way to ask.
ask_yes_no() {
    local prompt="$1" reply=""
    if have_tty; then
        { printf '%s' "$prompt" > /dev/tty; } 2>/dev/null || printf '%s' "$prompt"
        IFS= read -r reply < /dev/tty || true
    elif [[ -t 0 ]]; then
        printf '%s' "$prompt"
        IFS= read -r reply || true
    else
        return 2
    fi
    case "$reply" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
    esac
    return 1
}

# Remove exactly the packages in INSTALLED_PKGS: non-interactive, no
# autoremove / purge, nothing else touched.
remove_installed_packages() {
    local pm="$INSTALL_PKG_MANAGER"
    local -a sudo_prefix=() cmd=()
    [[ $EUID -ne 0 ]] && sudo_prefix=(sudo)
    case "$pm" in
        apt)    cmd=(env DEBIAN_FRONTEND=noninteractive apt-get remove -y) ;;
        dnf)    cmd=(dnf remove -y --setopt=clean_requirements_on_remove=False) ;;
        yum)    cmd=(yum remove -y --setopt=clean_requirements_on_remove=0) ;;
        pacman) cmd=(pacman -R --noconfirm) ;;
        zypper) cmd=(zypper --non-interactive remove) ;;
        apk)    cmd=(apk del) ;;
        *)      return 1 ;;
    esac
    if [[ "$LANG_MODE" == "cn" ]]; then
        echo "正在移除: ${INSTALLED_PKGS[*]}"
    else
        echo "Removing: ${INSTALLED_PKGS[*]}"
    fi
    if "${sudo_prefix[@]}" "${cmd[@]}" "${INSTALLED_PKGS[@]}" </dev/null; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            print_color "$GREEN" "$SYM_OK 已移除，系统已恢复原状。"
        else
            print_color "$GREEN" "$SYM_OK Removed; the system is back to how it was."
        fi
        INSTALLED_PKGS=()
        return 0
    fi
    if [[ "$LANG_MODE" == "cn" ]]; then
        print_color "$YELLOW" "$SYM_WARN 移除失败，请手动卸载: ${INSTALLED_PKGS[*]}"
    else
        print_color "$YELLOW" "$SYM_WARN Removal failed; uninstall manually: ${INSTALLED_PKGS[*]}"
    fi
    return 1
}

# After the report: offer to remove what install_packages() added.
cleanup_installed_packages() {
    [[ ${#INSTALLED_PKGS[@]} -gt 0 ]] || return 0
    [[ "$CLEANUP_MODE" == "never" ]] && return 0

    local n=${#INSTALLED_PKGS[@]} list="" i=0
    for (( i = 0; i < n && i < 4; i++ )); do list+="${list:+ }${INSTALLED_PKGS[$i]}"; done
    (( n > 4 )) && list+=" …"
    [[ "$UTF8_OK" == true ]] || list="${list/ …/ ...}"

    echo
    if [[ "$CLEANUP_MODE" == "always" ]]; then
        remove_installed_packages
        return 0
    fi

    local prompt=""
    if [[ "$LANG_MODE" == "cn" ]]; then
        prompt="移除本次为生成报告安装的 $n 个软件包（$list）？[y/N]: "
    elif (( n == 1 )); then
        prompt="Remove the package installed for this report ($list)? [y/N]: "
    else
        prompt="Remove the $n packages installed for this report ($list)? [y/N]: "
    fi

    local rc=2
    if [[ -t 1 ]]; then
        ask_yes_no "$prompt"
        rc=$?
    fi
    case "$rc" in
        0) remove_installed_packages ;;
        1)
            if [[ "$LANG_MODE" == "cn" ]]; then
                echo "保留已安装的软件包。"
            else
                echo "Keeping the installed packages."
            fi
            ;;
        *)
            # No terminal to ask on: one-line hint
            if [[ "$LANG_MODE" == "cn" ]]; then
                echo "本次安装了: ${INSTALLED_PKGS[*]} $SYM_ARROW 下次加 --cleanup 可在报告后自动移除"
            else
                echo "Installed for this report: ${INSTALLED_PKGS[*]} $SYM_ARROW pass --cleanup to remove them after the report"
            fi
            ;;
    esac
}

# Function to install required packages
install_packages() {
    # Map of required command -> package name (sensors/lspci overridden per distro)
    local pkg_manager
    pkg_manager=$(get_package_manager)

    local -a req_cmds=(dmidecode lshw smartctl ethtool nvme jq lspci sensors lsblk)
    local -A pkg_of=(
        [dmidecode]=dmidecode [lshw]=lshw [smartctl]=smartmontools
        [ethtool]=ethtool [nvme]=nvme-cli [jq]=jq [lspci]=pciutils
        [lsblk]=util-linux
    )
    # sensors / lsblk package names vary by distro
    case "$pkg_manager" in
        apt) pkg_of[sensors]=lm-sensors ;;
        dnf|yum|pacman) pkg_of[sensors]=lm_sensors ;;
        zypper) pkg_of[sensors]=sensors ;;
        apk) pkg_of[sensors]=lm-sensors; pkg_of[lsblk]=lsblk ;;
        *) pkg_of[sensors]=lm_sensors ;;
    esac

    local -a missing_cmds=() missing_pkgs=()
    local c=""
    for c in "${req_cmds[@]}"; do
        command -v "$c" >/dev/null 2>&1 && continue
        missing_cmds+=("$c")
        missing_pkgs+=("${pkg_of[$c]}")
    done

    if [[ ${#missing_cmds[@]} -eq 0 ]]; then
        return 0
    fi

    # De-duplicate package list
    local -A seen=()
    local -a uniq_pkgs=()
    local p=""
    for p in "${missing_pkgs[@]}"; do
        [[ -n "${seen[$p]:-}" ]] && continue
        seen[$p]=1
        uniq_pkgs+=("$p")
    done

    if [[ "$LANG_MODE" == "cn" ]]; then
        print_color "$YELLOW" "检测到缺少以下工具（部分硬件信息会缺失）:"
    else
        print_color "$YELLOW" "Missing tools (some hardware info will be incomplete):"
    fi
    printf '  %s\n' "${missing_cmds[*]}"
    if [[ "$LANG_MODE" == "cn" ]]; then
        echo "  需要安装的软件包: ${uniq_pkgs[*]}"
    else
        echo "  Packages to install: ${uniq_pkgs[*]}"
    fi
    echo

    # --no-install: never install, continue with what we have
    if [[ "$NO_INSTALL" == true ]]; then
        [[ "$LANG_MODE" == "cn" ]] && echo "已指定 --no-install，跳过安装，继续生成报告。" \
            || echo "--no-install set: skipping installation, continuing with partial data."
        echo
        return 1
    fi

    # Need root or sudo to install
    local can_install=true
    if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
        can_install=false
    fi
    if [[ "$can_install" != true || "$pkg_manager" == "unknown" ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            echo "无法自动安装（无 root/sudo 或未识别包管理器）。请手动安装后重试："
            echo "  ${uniq_pkgs[*]}"
        else
            echo "Cannot auto-install (no root/sudo or unknown package manager). Install manually:"
            echo "  ${uniq_pkgs[*]}"
        fi
        echo
        return 1
    fi

    # Decide whether to install: -y, or Y/N from the real TTY (works under curl | bash)
    local do_install=false
    if [[ "$AUTO_YES" == true ]]; then
        do_install=true
    else
        local prompt="Install these packages now? [y/N]: "
        [[ "$LANG_MODE" == "cn" ]] && prompt="现在安装这些软件包吗？[y/N]: "
        # ask_yes_no prefers /dev/tty so curl|bash (stdin = the script) can
        # still prompt; have_tty() really opens it, so ssh-without-tty / cron /
        # CI fall through to the no-TTY message instead of erroring.
        local rc=0
        ask_yes_no "$prompt"
        rc=$?
        if [[ $rc -eq 2 ]]; then
            if [[ "$LANG_MODE" == "cn" ]]; then
                echo "无法交互询问（无终端）。加 -y 可自动安装，或手动安装后重试。继续生成报告..."
            else
                echo "No TTY for Y/N prompt. Pass -y to auto-install, or install manually. Continuing..."
            fi
            echo
            return 1
        fi
        [[ $rc -eq 0 ]] && do_install=true
    fi

    if [[ "$do_install" != true ]]; then
        [[ "$LANG_MODE" == "cn" ]] && echo "跳过安装，继续生成报告（部分信息可能缺失）。" \
            || echo "Skipping install, continuing (some info may be missing)."
        echo
        return 1
    fi

    # Build install command
    local -a sudo_prefix=()
    [[ $EUID -ne 0 ]] && sudo_prefix=(sudo)
    local -a install_cmd=()
    case "$pkg_manager" in
        apt)    # No debconf dialogs: smartmontools Recommends an MTA (postfix /
                # exim4 config screen). `env` survives sudo's env_reset.
                if [[ "$LANG_MODE" == "cn" ]]; then echo "正在更新软件源..."; else echo "Updating package index..."; fi
                "${sudo_prefix[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>&1 || true
                install_cmd=("${sudo_prefix[@]}" env DEBIAN_FRONTEND=noninteractive
                             apt-get install -y --no-install-recommends) ;;
        dnf)    install_cmd=("${sudo_prefix[@]}" dnf install -y) ;;
        yum)    install_cmd=("${sudo_prefix[@]}" yum install -y) ;;
        pacman) install_cmd=("${sudo_prefix[@]}" pacman -S --noconfirm --needed) ;;
        zypper) install_cmd=("${sudo_prefix[@]}" zypper --non-interactive install) ;;
        apk)    install_cmd=("${sudo_prefix[@]}" apk add --no-cache) ;;
        *)
            [[ "$LANG_MODE" == "cn" ]] && echo "未识别的包管理器，请手动安装: ${uniq_pkgs[*]}" \
                || echo "Unknown package manager. Install manually: ${uniq_pkgs[*]}"
            echo
            return 1
            ;;
    esac

    # Remember which of these are genuinely absent now, so the optional cleanup
    # after the report removes exactly what this run added (and nothing that
    # was already there). Unknown state (no dpkg/rpm query tool) = not tracked.
    local -a pre_missing=()
    for p in "${uniq_pkgs[@]}"; do
        pkg_is_installed "$pkg_manager" "$p"
        [[ $? -eq 1 ]] && pre_missing+=("$p")
    done

    [[ "$LANG_MODE" == "cn" ]] && echo "正在安装: ${uniq_pkgs[*]}" || echo "Installing: ${uniq_pkgs[*]}"
    # Show install output so user can see progress / sudo password prompts
    local install_ok=true
    "${install_cmd[@]}" "${uniq_pkgs[@]}" || install_ok=false

    INSTALL_PKG_MANAGER="$pkg_manager"
    INSTALLED_PKGS=()
    for p in "${pre_missing[@]}"; do
        pkg_is_installed "$pkg_manager" "$p" && INSTALLED_PKGS+=("$p")
    done

    if [[ "$install_ok" == true ]]; then
        [[ "$LANG_MODE" == "cn" ]] && print_color "$GREEN" "安装完成。" || print_color "$GREEN" "Installation complete."
    else
        [[ "$LANG_MODE" == "cn" ]] && print_color "$YELLOW" "部分软件包安装失败，继续生成报告。" \
            || print_color "$YELLOW" "Some packages failed to install; continuing."
    fi
    echo
    return 0
}

# Hostname without depending on hostname(1) (missing in minimal containers).
get_hostname_to() {
    local __h="${HOSTNAME:-}"
    [[ -z "$__h" ]] && read_line __h /proc/sys/kernel/hostname
    [[ -z "$__h" ]] && __h=$(uname -n 2>/dev/null)
    printf -v "$1" '%s' "$__h"
}

# Uptime from /proc/uptime: "up 3 days, 4 hours, 5 minutes" / "3天 4小时 5分钟".
# format_uptime_to VAR [en|cn] (default: current language)
format_uptime_to() {
    local __out="$1" __lang="${2:-$LANG_MODE}" __raw="" __secs="" __d=0 __h=0 __m=0 __txt=""
    read_line __raw /proc/uptime
    __secs="${__raw%%[. ]*}"
    if [[ ! "$__secs" =~ ^[0-9]+$ ]]; then
        printf -v "$__out" '%s' ""
        return
    fi
    __d=$((__secs / 86400)); __h=$((__secs % 86400 / 3600)); __m=$((__secs % 3600 / 60))
    if [[ "$__lang" == "cn" ]]; then
        (( __d > 0 )) && __txt+="${__d}天 "
        (( __d > 0 || __h > 0 )) && __txt+="${__h}小时 "
        __txt+="${__m}分钟"
    else
        local __parts=() __sd="s" __sh="s" __sm="s"
        (( __d == 1 )) && __sd=""
        (( __h == 1 )) && __sh=""
        (( __m == 1 )) && __sm=""
        (( __d > 0 )) && __parts+=("$__d day$__sd")
        (( __h > 0 )) && __parts+=("$__h hour$__sh")
        (( __m > 0 || ${#__parts[@]} == 0 )) && __parts+=("$__m minute$__sm")
        __txt="up ${__parts[0]}"
        local __p=""
        for __p in "${__parts[@]:1}"; do __txt+=", $__p"; done
    fi
    printf -v "$__out" '%s' "$__txt"
}

# Function to get system information
get_system_info() {
    print_subsection "${LBL[system_info]}"

    local hostname_val=""
    local os_val=""
    local kernel_val=""
    local uptime_val=""

    get_hostname_to hostname_val
    os_val=$(get_os_release_value "PRETTY_NAME" 2>/dev/null)
    [[ -z "$os_val" ]] && os_val="${LBL[no_info]}"
    read_line kernel_val /proc/sys/kernel/osrelease
    [[ -z "$kernel_val" ]] && kernel_val=$(uname -r 2>/dev/null)
    format_uptime_to uptime_val
    [[ -z "$uptime_val" ]] && uptime_val=$(uptime -p 2>/dev/null)
    # JSON keeps one language-neutral format
    local uptime_json="$uptime_val"
    [[ "$LANG_MODE" == "cn" ]] && format_uptime_to uptime_json en

    print_info "${LBL[hostname]}" "$hostname_val"
    print_info "${LBL[os]}" "$os_val"
    print_info "${LBL[kernel]}" "$kernel_val"
    print_info "${LBL[uptime]}" "$uptime_val"

    if [[ "$COLLECT_JSON" == true ]]; then
        JSON_SYSTEM_KV=(
            "$(json_kv_s "hostname" "$hostname_val")"
            "$(json_kv_s "os" "$os_val")"
            "$(json_kv_s "kernel" "$kernel_val")"
            "$(json_kv_s "uptime" "$uptime_json")"
        )
    fi

    section_end
}

# First temperature on a `sensors` line whose label matches $2 (ERE), e.g.
#   "Package id 0:  +45.0°C  (high = +80.0°C, crit = +100.0°C)" -> 45.0
# Pure bash; the value is the first number after the label's colon.
sensors_temp_to() {
    local __out="$1" __label_re="$2" __data="$3" __line="" __rest="" __val=""
    local __num_re='^[^0-9+-]*([+-]?[0-9]+(\.[0-9]+)?)'
    while IFS= read -r __line; do
        [[ "$__line" =~ $__label_re ]] || continue
        __rest="${__line#*:}"
        [[ "$__rest" == "$__line" ]] && continue
        if [[ "$__rest" =~ $__num_re ]]; then
            __val="${BASH_REMATCH[1]#+}"
            break
        fi
    done <<< "$__data"
    printf -v "$__out" '%s' "$__val"
}

# Function to detect CPU temperature. Sets CPU_TEMP_RESULT (e.g. "45.0°C",
# "45.0°C (x86_pkg_temp)") or "" when nothing usable is exposed (common in VMs).
get_cpu_temperature() {
    local temp_data="" t=""
    CPU_TEMP_RESULT=""

    # Method 1: lm-sensors (C locale so the unit/labels are predictable)
    if command -v sensors >/dev/null 2>&1; then
        local sensors_output=""
        spin_start "sensors" "${LBL[cpu_temperature]}"
        sensors_output=$(LC_ALL=C run_limited 5 sensors 2>/dev/null)
        spin_stop
        if [[ -n "$sensors_output" ]]; then
            # Intel package temperature, then AMD k10temp Tctl/Tdie, then generic
            sensors_temp_to t '^[[:space:]]*Package id [0-9]+:' "$sensors_output"
            [[ -z "$t" ]] && sensors_temp_to t '^[[:space:]]*(Tctl|Tdie):' "$sensors_output"
            [[ -z "$t" ]] && sensors_temp_to t '[Cc][Pp][Uu].*[Tt][Ee][Mm][Pp]|^[[:space:]]*[Cc][Pp][Uu]:' "$sensors_output"
            [[ -n "$t" ]] && temp_data="${t}°C"
        fi
    fi

    # Method 2: thermal zones in /sys/class/thermal
    if [[ -z "$temp_data" ]]; then
        local zone="" zone_temp="" zone_type="" temp_celsius=""
        for zone in /sys/class/thermal/thermal_zone*/temp; do
            [[ -r "$zone" ]] || continue
            read_line zone_type "${zone%/temp}/type"
            [[ "$zone_type" =~ (cpu|x86_pkg_temp|CPU|Core|Package) ]] || continue
            read_line zone_temp "$zone"
            if [[ "$zone_temp" =~ ^[0-9]+$ && "$zone_temp" -gt 0 ]]; then
                millicelsius_to temp_celsius "$zone_temp"
                if [[ -n "$temp_celsius" ]]; then
                    temp_data="${temp_celsius}°C (${zone_type})"
                    break
                fi
            fi
        done
    fi

    # Method 3: hwmon interfaces
    if [[ -z "$temp_data" ]]; then
        local hwmon="" hwmon_name="" temp_input="" temp_val="" temp_label="" temp_celsius=""
        for hwmon in /sys/class/hwmon/hwmon*/; do
            [[ -r "${hwmon}name" ]] || continue
            read_line hwmon_name "${hwmon}name"
            [[ "$hwmon_name" =~ (coretemp|k10temp|k8temp|zenpower|fam15h_power|cpu) ]] || continue
            for temp_input in "${hwmon}"temp*_input; do
                [[ -r "$temp_input" ]] || continue
                read_line temp_val "$temp_input"
                [[ "$temp_val" =~ ^[0-9]+$ && "$temp_val" -gt 0 ]] || continue
                millicelsius_to temp_celsius "$temp_val"
                [[ -n "$temp_celsius" ]] || continue
                read_line temp_label "${temp_input%_input}_label"
                if [[ -n "$temp_label" ]]; then
                    temp_data="${temp_celsius}°C (${temp_label})"
                else
                    temp_data="${temp_celsius}°C"
                fi
                break 2
            done
        done
    fi

    # Method 4: vcgencmd for Raspberry Pi
    if [[ -z "$temp_data" ]] && command -v vcgencmd >/dev/null 2>&1; then
        local pi_out=""
        pi_out=$(vcgencmd measure_temp 2>/dev/null)
        if [[ "$pi_out" =~ ([0-9]+(\.[0-9]+)?) ]]; then
            temp_data="${BASH_REMATCH[1]}°C (Raspberry Pi)"
        fi
    fi

    CPU_TEMP_RESULT="$temp_data"
}

# Whole-system CPU usage over a short /proc/stat window. Sampled once per run,
# before any background prefetch starts, so the report's own probes do not
# inflate the number.
sample_cpu_usage() {
    [[ "$CPU_USAGE_SAMPLED" == true ]] && return
    CPU_USAGE_SAMPLED=true
    CPU_USAGE_RESULT=""
    [[ -r /proc/stat ]] || return

    local user1="" nice1="" system1="" idle1="" iowait1="" irq1="" softirq1="" steal1=""
    local user2="" nice2="" system2="" idle2="" iowait2="" irq2="" softirq2="" steal2=""
    read -r _ user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 _ < /proc/stat
    sleep 0.2
    read -r _ user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 _ < /proc/stat

    local total_diff=$(( (user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + ${steal2:-0}) \
        - (user1 + nice1 + system1 + idle1 + iowait1 + irq1 + softirq1 + ${steal1:-0}) ))
    local idle_diff=$(( (idle2 + iowait2) - (idle1 + iowait1) ))
    local active_diff=$(( total_diff - idle_diff ))

    if (( total_diff > 0 )); then
        local usage_tenths=$(( active_diff * 1000 / total_diff ))
        CPU_USAGE_RESULT="$((usage_tenths / 10)).$((usage_tenths % 10))"
    fi
}

# Function to get CPU information
get_cpu_info() {
    print_subsection "${LBL[cpu_info]}"

    local cpu_model="" cpu_cores="" cpu_threads="" cpu_freq="" cpu_cache=""
    IFS=$'\t' read -r cpu_model cpu_cores cpu_freq cpu_cache cpu_threads < <(
        awk -F: '
            function trim(v) { sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); return v }
            /^processor[[:space:]]*:/ {
                if (phys != "" && core != "") seen[phys ":" core] = 1
                phys = ""; core = ""
                threads++
            }
            /^model name[[:space:]]*:/ && !model {model=trim($2)}
            /^cpu cores[[:space:]]*:/ && !cores_per_socket {cores_per_socket=trim($2)}
            /^physical id[[:space:]]*:/ {phys=trim($2)}
            /^core id[[:space:]]*:/ {core=trim($2)}
            /^cpu MHz[[:space:]]*:/ && !freq {freq=trim($2)}
            /^cache size[[:space:]]*:/ && !cache {cache=trim($2)}
            END {
                if (phys != "" && core != "") seen[phys ":" core] = 1
                for (k in seen) total_cores++
                if (!total_cores) total_cores = cores_per_socket
                print model "\t" total_cores "\t" freq "\t" cache "\t" threads
            }
        ' /proc/cpuinfo 2>/dev/null
    )

    # ARM / some hypervisors omit fields from /proc/cpuinfo: fill from lscpu.
    if [[ -z "$cpu_model" || -z "$cpu_cores" || -z "$cpu_freq" || -z "$cpu_cache" ]]; then
        local l_model="" l_cps="" l_sockets="" l_mhz="" l_l3="" l_l2=""
        lscpu_field_to l_model "Model name"
        lscpu_field_to l_cps "Core(s) per socket"
        [[ -z "$l_cps" ]] && lscpu_field_to l_cps "Core(s) per cluster"
        lscpu_field_to l_sockets "Socket(s)"
        lscpu_field_to l_mhz "CPU max MHz"
        lscpu_field_to l_l3 "L3 cache"
        lscpu_field_to l_l2 "L2 cache"
        [[ -z "$cpu_model" && -n "$l_model" && "$l_model" != "-" ]] && cpu_model="$l_model"
        if [[ -z "$cpu_cores" && "$l_cps" =~ ^[0-9]+$ ]]; then
            [[ "$l_sockets" =~ ^[0-9]+$ ]] || l_sockets=1
            cpu_cores=$((l_cps * l_sockets))
        fi
        [[ -z "$cpu_freq" && -n "$l_mhz" ]] && cpu_freq="$l_mhz"
        [[ -z "$cpu_cache" ]] && cpu_cache="${l_l3:-$l_l2}"
    fi

    print_info "${LBL[model]}" "${cpu_model:-${LBL[no_info]}}"
    print_info "${LBL[cores]}" "${cpu_cores:-${LBL[no_info]}}"
    print_info "${LBL[threads]}" "${cpu_threads:-${LBL[no_info]}}"
    print_info "${LBL[frequency]}" "${cpu_freq:+${cpu_freq} MHz}"
    print_info "${LBL[cache]}" "${cpu_cache:-${LBL[no_info]}}"

    # CPU usage - /proc/stat delta (sampled once; see sample_cpu_usage)
    sample_cpu_usage
    local cpu_usage_val=""
    [[ -n "$CPU_USAGE_RESULT" ]] && cpu_usage_val="${CPU_USAGE_RESULT}%"
    print_info "${LBL[usage]}" "${cpu_usage_val:-${LBL[no_info]}}"

    # CPU Temperature
    get_cpu_temperature
    local cpu_temp="$CPU_TEMP_RESULT"
    if [[ -n "$cpu_temp" ]]; then
        # Above 80°C is generally considered high
        local temp_warn=false
        if [[ "$cpu_temp" =~ ^-?([0-9]+)(\.([0-9]+))? ]]; then
            local temp_whole="${BASH_REMATCH[1]}" temp_frac="${BASH_REMATCH[3]}"
            if (( 10#$temp_whole > 80 )); then
                temp_warn=true
            elif (( 10#$temp_whole == 80 )) && [[ -n "${temp_frac//0/}" ]]; then
                temp_warn=true
            fi
        fi
        if [[ "$temp_warn" == true ]]; then
            health_add warn "CPU" temp "temperature ${cpu_temp%% *}" "温度 ${cpu_temp%% *}"
            print_info_colored "${LBL[cpu_temperature]}" "$cpu_temp $SYM_WARN" "$RED"
        else
            print_info "${LBL[cpu_temperature]}" "$cpu_temp"
        fi
    else
        # If no temperature detected, show message based on permissions
        if [[ $EUID -ne 0 ]]; then
            print_info "${LBL[cpu_temperature]}" "${LBL[requires_root_sensors]}"
        else
            print_info "${LBL[cpu_temperature]}" "${LBL[not_detected]}"
        fi
    fi

    if [[ "$COLLECT_JSON" == true ]]; then
        JSON_CPU_KV=(
            "$(json_kv_s "model" "$cpu_model")"
            "$(json_kv "cores" "$cpu_cores")"
            "$(json_kv "threads" "$cpu_threads")"
            "$(json_kv_s "frequency" "${cpu_freq:+${cpu_freq} MHz}")"
            "$(json_kv_s "cache" "$cpu_cache")"
            "$(json_kv_s "usage" "$cpu_usage_val")"
            "$(json_kv_s "temperature" "$cpu_temp")"
        )
    fi

    section_end
}

# Add one memory module to both the render model and JSON model.
ram_add_module() {
    local size="$1"
    local type="$2"
    local speed="$3"
    local manufacturer="$4"
    local serial_number="$5"
    local part_number="$6"

    if [[ -z "$size" || "$size" =~ (No\ Module\ Installed|Unknown|Not\ Specified) ]]; then
        return
    fi

    local display_sn="$serial_number"
    if [[ -z "$display_sn" || "$display_sn" =~ (Not\ Specified|Unknown) ]]; then
        display_sn="N/A"
    fi

    RAM_MODULE_ROWS+=("${size}${RAM_FIELD_SEP}${type}${RAM_FIELD_SEP}${speed}${RAM_FIELD_SEP}${manufacturer}${RAM_FIELD_SEP}${display_sn}${RAM_FIELD_SEP}${part_number}")

    [[ "$COLLECT_JSON" == true ]] || return
    local module_kv=(
        "$(json_kv_s "size" "$size")"
        "$(json_kv_s "type" "$type")"
        "$(json_kv_s "frequency" "$speed")"
        "$(json_kv_s "manufacturer" "$manufacturer")"
        "$(json_kv_s "serial_number" "$display_sn")"
        "$(json_kv_s "model" "$part_number")"
    )
    JSON_RAM_MODULES+=("$(json_obj "${module_kv[@]}")")
}

collect_ram_info() {
    local key="" val="" unit="" mem_total_kb="" mem_avail_kb="" mem_free_kb="" mem_buf_kb="" mem_cached_kb=""

    # Pure-bash /proc/meminfo read. "Used" is total - available (what free(1)
    # reports on current procps); all three use the same unit (1024-based GB).
    while read -r key val unit; do
        case "$key" in
            MemTotal:) mem_total_kb="$val" ;;
            MemAvailable:) mem_avail_kb="$val" ;;
            MemFree:) mem_free_kb="$val" ;;
            Buffers:) mem_buf_kb="$val" ;;
            Cached:) mem_cached_kb="$val" ;;
        esac
    done < /proc/meminfo
    # Kernels < 3.14 have no MemAvailable: approximate it
    if [[ -z "$mem_avail_kb" && -n "$mem_free_kb" ]]; then
        mem_avail_kb=$(( mem_free_kb + ${mem_buf_kb:-0} + ${mem_cached_kb:-0} ))
    fi

    RAM_TOTAL="" RAM_USED="" RAM_AVAILABLE=""
    if [[ "$mem_total_kb" =~ ^[0-9]+$ ]]; then
        format_bytes_to RAM_TOTAL "$((mem_total_kb * 1024))"
        if [[ "$mem_avail_kb" =~ ^[0-9]+$ ]]; then
            format_bytes_to RAM_AVAILABLE "$((mem_avail_kb * 1024))"
            format_bytes_to RAM_USED "$(( (mem_total_kb - mem_avail_kb) * 1024 ))"
        fi
    fi
    RAM_MODULE_ROWS=()
    RAM_FALLBACK_LINES=()
    RAM_HAS_DETAILED_MODULES=false

    # ECC error counters from the kernel EDAC driver (absent on most VMs)
    RAM_ECC_CE="" RAM_ECC_UE=""
    local mc="" ce="" ue=""
    for mc in /sys/devices/system/edac/mc/mc[0-9]*; do
        [[ -r "$mc/ce_count" ]] || continue
        read_line ce "$mc/ce_count"
        read_line ue "$mc/ue_count"
        [[ "$ce" =~ ^[0-9]+$ ]] && RAM_ECC_CE=$(( ${RAM_ECC_CE:-0} + ce ))
        [[ "$ue" =~ ^[0-9]+$ ]] && RAM_ECC_UE=$(( ${RAM_ECC_UE:-0} + ue ))
    done
    if [[ "${RAM_ECC_UE:-0}" -gt 0 ]]; then
        health_add fail "RAM" ecc_ue "$RAM_ECC_UE uncorrectable ECC errors" "不可纠正 ECC 错误 $RAM_ECC_UE"
    fi
    if [[ "${RAM_ECC_CE:-0}" -gt 0 ]]; then
        health_add warn "RAM" ecc_ce "$RAM_ECC_CE corrected ECC errors" "已纠正 ECC 错误 $RAM_ECC_CE"
    fi

    if [[ "$COLLECT_JSON" == true ]]; then
        JSON_RAM_KV=(
            "$(json_kv_s "total" "$RAM_TOTAL")"
            "$(json_kv_s "used" "$RAM_USED")"
            "$(json_kv_s "available" "$RAM_AVAILABLE")"
        )
        [[ -n "$RAM_ECC_CE" ]] && JSON_RAM_KV+=("$(json_kv "ecc_corrected" "$RAM_ECC_CE")")
        [[ -n "$RAM_ECC_UE" ]] && JSON_RAM_KV+=("$(json_kv "ecc_uncorrected" "$RAM_ECC_UE")")
    fi
    JSON_RAM_MODULES=()

    if command -v dmidecode >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        local temp_file=""
        temp_file=$(mktemp 2>/dev/null) || return
        RAM_HAS_DETAILED_MODULES=true
        TEMP_FILES+=("$temp_file")
        spin_start "dmidecode" "${LBL[ram_info]}"
        run_limited 15 dmidecode -t memory 2>/dev/null > "$temp_file"
        spin_stop

        local size="" type="" speed="" manufacturer="" part_number="" serial_number=""
        local in_memory_device=0
        local line=""

        while IFS= read -r line; do
            if [[ "$line" =~ ^Handle.*DMI\ type\ 17 ]]; then
                ram_add_module "$size" "$type" "$speed" "$manufacturer" "$serial_number" "$part_number"
                size="" type="" speed="" manufacturer="" part_number="" serial_number=""
                in_memory_device=1
            elif [[ $in_memory_device -eq 1 ]]; then
                if [[ "$line" =~ ^[[:space:]]*Size:[[:space:]]*(.*) ]]; then
                    size="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*Type:[[:space:]]*(.*) ]] && [[ -z "$type" ]]; then
                    type="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*Speed:[[:space:]]*(.*) ]] && [[ -z "$speed" ]]; then
                    speed="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*Manufacturer:[[:space:]]*(.*) ]]; then
                    manufacturer="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*Part\ Number:[[:space:]]*(.*) ]]; then
                    part_number="${BASH_REMATCH[1]}"
                    part_number="${part_number%"${part_number##*[![:space:]]}"}"
                elif [[ "$line" =~ ^[[:space:]]*Serial\ Number:[[:space:]]*(.*) ]]; then
                    serial_number="${BASH_REMATCH[1]}"
                fi
            fi
        done < "$temp_file"

        ram_add_module "$size" "$type" "$speed" "$manufacturer" "$serial_number" "$part_number"
        return
    fi

    # Root without dmidecode is the common VM/container case: say what is
    # actually missing instead of asking for root.
    if [[ $EUID -eq 0 ]]; then
        RAM_FALLBACK_LINES+=("${LBL[ram_need_dmidecode]}")
    else
        RAM_FALLBACK_LINES+=("${LBL[ram_need_root]}")
    fi

    local line=""
    if command -v lshw >/dev/null 2>&1; then
        local lshw_output=""
        spin_start "lshw" "${LBL[ram_info]}"
        if [[ $EUID -eq 0 ]]; then
            lshw_output=$(run_limited "$LSHW_TIMEOUT_SECONDS" lshw -c memory 2>/dev/null)
        elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            lshw_output=$(run_limited "$LSHW_TIMEOUT_SECONDS" sudo -n lshw -c memory 2>/dev/null)
        else
            lshw_output=$(run_limited "$LSHW_TIMEOUT_SECONDS" lshw -c memory 2>/dev/null)
        fi
        spin_stop

        local -a lshw_lines=()
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            [[ -n "$line" ]] && lshw_lines+=("  $line")
        done < <(printf '%s\n' "$lshw_output" | grep -A5 -B1 "bank\|slot\|DIMM" | grep -E "description:|size:|clock:")
        if [[ ${#lshw_lines[@]} -gt 0 ]]; then
            RAM_FALLBACK_LINES+=("${LBL[ram_lshw]}" "${lshw_lines[@]}")
        fi
    fi

    if command -v dmidecode >/dev/null 2>&1 && [[ $EUID -ne 0 ]]; then
        local -a dmi_lines=()
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            [[ -n "$line" ]] && dmi_lines+=("  $line")
        done < <(run_limited 15 dmidecode -t 17 2>/dev/null | grep -E "Size:|Type:|Speed:|Manufacturer:" | head -20)
        if [[ ${#dmi_lines[@]} -gt 0 ]]; then
            RAM_FALLBACK_LINES+=("${LBL[ram_dmidecode_try]}" "${dmi_lines[@]}")
        fi
    fi
}

render_ram_info() {
    print_subsection "${LBL[ram_info]}"

    print_info_colored "${LBL[total]}" "$RAM_TOTAL" "$CYAN"
    print_info_colored "${LBL[used]}" "$RAM_USED" "$YELLOW"
    print_info_colored "${LBL[available]}" "$RAM_AVAILABLE" "$GREEN"
    if [[ -n "$RAM_ECC_CE$RAM_ECC_UE" ]]; then
        local ecc_color="$GREEN" ecc_txt=""
        [[ "${RAM_ECC_CE:-0}" -gt 0 ]] && ecc_color="$YELLOW"
        [[ "${RAM_ECC_UE:-0}" -gt 0 ]] && ecc_color="$RED"
        if [[ "$LANG_MODE" == "cn" ]]; then
            ecc_txt="已纠正 ${RAM_ECC_CE:-0} $SYM_DOT 不可纠正 ${RAM_ECC_UE:-0}"
        else
            ecc_txt="corrected ${RAM_ECC_CE:-0} $SYM_DOT uncorrected ${RAM_ECC_UE:-0}"
        fi
        print_info_colored "${LBL[ecc_errors]}" "$ecc_txt" "$ecc_color"
    fi

    echo "│"
    [[ "$LANG_MODE" == "cn" ]] && print_color "$CYAN" "│ 内存模组:" || print_color "$CYAN" "│ Memory Modules:"

    if [[ "$RAM_HAS_DETAILED_MODULES" == true && ${#RAM_MODULE_ROWS[@]} -eq 0 ]]; then
        # dmidecode ran but SMBIOS lists no DIMMs (typical for cloud VMs)
        echo "│   ${LBL[no_info]}"
    elif [[ "$RAM_HAS_DETAILED_MODULES" == true ]]; then
        TABLE_COL_W=(8 6 12 12 16 22)
        if [[ "$LANG_MODE" == "cn" ]]; then
            table_header "大小" "类型" "频率" "制造商" "序列号" "型号"
        else
            table_header "Size" "Type" "Frequency" "Manufacturer" "Serial" "Model"
        fi

        local row="" size="" type="" speed="" manufacturer="" display_sn="" part_number=""
        for row in "${RAM_MODULE_ROWS[@]}"; do
            IFS="$RAM_FIELD_SEP" read -r size type speed manufacturer display_sn part_number <<< "$row"
            local type_color="$WHITE"
            case "$type" in
                DDR5*) type_color="$GREEN" ;;
                DDR4*) type_color="$CYAN" ;;
                DDR3*) type_color="$YELLOW" ;;
            esac
            table_row \
                "$size" "$CYAN" \
                "$type" "$type_color" \
                "$speed" "" \
                "$manufacturer" "" \
                "$display_sn" "" \
                "$part_number" ""
        done
        table_close
    else
        for row in "${RAM_FALLBACK_LINES[@]}"; do
            echo "│   $row"
        done
    fi

    section_end
}

# Function to get RAM information
get_ram_info() {
    collect_ram_info
    render_ram_info
}

# Helper function: Convert bytes to human readable format
format_bytes_to() {
    local out_var="$1"
    local bytes="$2"
    local suffix="$3"  # Optional suffix like "(SMART)" or "(session)"

    if [[ -z "$bytes" || "$bytes" == "0" || ! "$bytes" =~ ^[0-9]+$ ]]; then
        printf -v "$out_var" ''
        return
    fi

    local divisor=1024
    local unit="KB"
    if (( bytes >= 1125899906842624 )); then
        divisor=1125899906842624
        unit="PB"
    elif (( bytes >= 1099511627776 )); then
        divisor=1099511627776
        unit="TB"
    elif (( bytes >= 1073741824 )); then
        divisor=1073741824
        unit="GB"
    elif (( bytes >= 1048576 )); then
        divisor=1048576
        unit="MB"
    fi

    local whole=$((bytes / divisor))
    local frac=$(((bytes % divisor) * 100 / divisor))
    local formatted_value=""
    printf -v formatted_value '%d.%02d %s' "$whole" "$frac" "$unit"
    [[ -n "$suffix" ]] && formatted_value="$formatted_value $suffix"
    printf -v "$out_var" '%s' "$formatted_value"
}

format_bytes() {
    local result=""
    format_bytes_to result "$1" "$2"
    echo "$result"
}

millicelsius_to() {
    local out_var="$1"
    local milli="$2"

    if [[ -z "$milli" || ! "$milli" =~ ^-?[0-9]+$ ]]; then
        printf -v "$out_var" ''
        return
    fi

    local sign=""
    if (( milli < 0 )); then
        sign="-"
        milli=$((-milli))
    fi

    local whole=$((milli / 1000))
    local frac=$(((milli % 1000) / 100))
    printf -v "$out_var" '%s%d.%d' "$sign" "$whole" "$frac"
}

run_limited() {
    local seconds="$1"
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
    else
        "$@"
    fi
}

kv_line_get() {
    local out_var="$1"
    local line="$2"
    local key="$3"
    local rest=""

    rest="${line#*"${key}"=\"}"
    if [[ "$rest" == "$line" ]]; then
        printf -v "$out_var" ''
    else
        printf -v "$out_var" '%s' "${rest%%\"*}"
    fi
}

# Hypervisor / container detection. Sets HYPERVISOR_VM and HYPERVISOR_CT
# (empty when bare metal / not containerized / unknown).
HYPERVISOR_VM=""
HYPERVISOR_CT=""
detect_hypervisor() {
    local has_hyp_flag="${1:-false}" env1=""
    HYPERVISOR_VM=""
    HYPERVISOR_CT=""
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        HYPERVISOR_VM=$(systemd-detect-virt -v 2>/dev/null)
        HYPERVISOR_CT=$(systemd-detect-virt -c 2>/dev/null)
        [[ "$HYPERVISOR_VM" == "none" ]] && HYPERVISOR_VM=""
        [[ "$HYPERVISOR_CT" == "none" ]] && HYPERVISOR_CT=""
    fi
    [[ -z "$HYPERVISOR_VM" ]] && lscpu_field_to HYPERVISOR_VM "Hypervisor vendor"
    [[ -z "$HYPERVISOR_VM" && "$has_hyp_flag" == true ]] && HYPERVISOR_VM="unknown"
    if [[ -z "$HYPERVISOR_CT" ]]; then
        if [[ -f /.dockerenv ]]; then
            HYPERVISOR_CT="docker"
        elif [[ -f /run/.containerenv ]]; then
            HYPERVISOR_CT="podman"
        elif [[ -d /proc/vz && ! -d /proc/bc ]]; then
            HYPERVISOR_CT="openvz"
        elif [[ -r /proc/1/environ ]]; then
            env1=$( { tr '\0' '\n' < /proc/1/environ; } 2>/dev/null )   # braces: the redirect itself may fail (EPERM)
            if [[ "$env1" =~ (^|$'\n')container=([^$'\n']+) ]]; then
                HYPERVISOR_CT="${BASH_REMATCH[2]}"
            fi
        fi
    fi
}

get_cpu_platform_info() {
    print_subsection "${LBL[platform_info]}"

    JSON_PLATFORM_KV=()

    local microcode=""
    local virtualization="No"
    local has_hyp_flag=false
    local numa_nodes=""
    local sockets=""
    local governor=""
    local turbo_status=""
    local hv_flag="" vt_flag="" f="" g="" val=""

    # One pass over /proc/cpuinfo: microcode, VT-x/AMD-V, hypervisor flag
    if [[ -r /proc/cpuinfo ]]; then
        IFS=$'\t' read -r microcode vt_flag hv_flag < <(
            awk -F': ' '
                /^microcode/ && mc == "" {mc = $2}
                /^flags/ && !seen {
                    seen = 1
                    if ($2 ~ /(^| )(vmx|svm)( |$)/) vt = 1
                    if ($2 ~ /(^| )hypervisor( |$)/) hv = 1
                }
                END {print mc "\t" (vt ? 1 : 0) "\t" (hv ? 1 : 0)}
            ' /proc/cpuinfo 2>/dev/null
        )
    fi
    [[ "$vt_flag" == "1" ]] && virtualization="Yes"
    [[ "$hv_flag" == "1" ]] && has_hyp_flag=true

    lscpu_field_to numa_nodes "NUMA node(s)"
    lscpu_field_to sockets "Socket(s)"

    local -A seen_gov=()
    for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
        [[ -r "$f" ]] || continue
        read_line g "$f"
        [[ -z "$g" || -n "${seen_gov[$g]:-}" ]] && continue
        seen_gov[$g]=1
        governor+="${governor:+,}$g"
    done

    if [[ -r /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
        read_line val /sys/devices/system/cpu/intel_pstate/no_turbo
        if [[ "$val" == "1" ]]; then turbo_status="Disabled"; else turbo_status="Enabled"; fi
    elif [[ -r /sys/devices/system/cpu/cpufreq/boost ]]; then
        read_line val /sys/devices/system/cpu/cpufreq/boost
        if [[ "$val" == "1" ]]; then turbo_status="Enabled"; else turbo_status="Disabled"; fi
    fi

    detect_hypervisor "$has_hyp_flag"
    local hyp_disp="$HYPERVISOR_VM"
    if [[ -n "$HYPERVISOR_CT" ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            hyp_disp+="${hyp_disp:+，}容器: $HYPERVISOR_CT"
        else
            hyp_disp+="${hyp_disp:+, }container: $HYPERVISOR_CT"
        fi
    fi

    local platform_disp="" virt_disp="" turbo_disp=""
    if [[ "$LANG_MODE" == "cn" ]]; then
        platform_disp="${sockets:-?} 路 CPU，${numa_nodes:-?} 个 NUMA 节点"
    else
        platform_disp="${sockets:-?} socket(s), ${numa_nodes:-?} NUMA node(s)"
    fi
    if [[ "$virtualization" == "Yes" ]]; then virt_disp="${LBL[yes]}"; else virt_disp="${LBL[no]}"; fi
    case "$turbo_status" in
        Enabled) turbo_disp="${LBL[enabled]}" ;;
        Disabled) turbo_disp="${LBL[disabled]}" ;;
    esac

    print_info "${LBL[platform]}" "$platform_disp"
    print_info "${LBL[hw_virt]}" "$virt_disp (VT-x/AMD-V)"
    [[ -n "$hyp_disp" ]] && print_info "${LBL[hypervisor]}" "$hyp_disp"
    [[ -n "$microcode" ]] && print_info "${LBL[microcode]}" "$microcode"
    [[ -n "$governor" ]] && print_info "${LBL[governor]}" "$governor"
    [[ -n "$turbo_disp" ]] && print_info "${LBL[turbo]}" "$turbo_disp"

    if [[ "$COLLECT_JSON" == true ]]; then
        [[ -n "$microcode" ]] && JSON_PLATFORM_KV+=("$(json_kv_s "microcode" "$microcode")")
        JSON_PLATFORM_KV+=("$(json_kv "virtualization" "$virtualization")")
        [[ -n "$HYPERVISOR_VM" ]] && JSON_PLATFORM_KV+=("$(json_kv_s "hypervisor" "$HYPERVISOR_VM")")
        [[ -n "$HYPERVISOR_CT" ]] && JSON_PLATFORM_KV+=("$(json_kv_s "container" "$HYPERVISOR_CT")")
        [[ -n "$sockets" ]] && JSON_PLATFORM_KV+=("$(json_kv "sockets" "$sockets")")
        [[ -n "$numa_nodes" ]] && JSON_PLATFORM_KV+=("$(json_kv "numa_nodes" "$numa_nodes")")
        [[ -n "$governor" ]] && JSON_PLATFORM_KV+=("$(json_kv_s "governor" "$governor")")
        [[ -n "$turbo_status" ]] && JSON_PLATFORM_KV+=("$(json_kv "turbo_boost" "$turbo_status")")
    fi

    section_end
}


compact_pci_name() {
    local out_var="$1"
    local name="$2"

    name="${name#PCI bridge: }"
    name="${name#Non-Volatile memory controller: }"
    name="${name#Serial Attached SCSI controller: }"
    name="${name#SATA controller: }"
    name="${name#SCSI storage controller: }"
    name="${name#Ethernet controller: }"
    name="${name#VGA compatible controller: }"
    name="${name//Intel Corporation /Intel }"
    name="${name//Broadcom Inc. and subsidiaries /Broadcom }"
    name="${name//Samsung Electronics Co Ltd /Samsung }"
    name="${name//Marvell Technology Group Ltd. /Marvell }"
    name="${name//PCI Express/PCIe}"
    name="${name//PCI-Express/PCIe}"
    name="${name//Xeon E7 v2\/Xeon E5 v2\/Core i7/Xeon E5 v2}"
    # "(rev 02)" is noise in a fixed-width cell
    [[ "$name" =~ ^(.*[^[:space:]])[[:space:]]+\(rev\ [0-9a-fA-F]+\)$ ]] && name="${BASH_REMATCH[1]}"

    printf -v "$out_var" '%s' "$name"
}




build_pcie_name_cache() {
    PCIE_NAME_CACHE=()

    local line="" slot="" name=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        slot="${line%% *}"
        name="${line#* }"
        [[ -z "$slot" || "$slot" == "$name" ]] && continue
        PCIE_NAME_CACHE["$slot"]="$name"
        PCIE_NAME_CACHE["0000:$slot"]="$name"
    done <<< "$LSPCI_RESULT"
}



get_nvme_deep_info() {
    print_subsection "${LBL[nvme_deep_info]}"

    JSON_NVME_DEEP=()

    if ! command -v nvme >/dev/null 2>&1; then
        print_info "${LBL[status]}" "${LBL[nvme_cli_missing]}"
        section_end
        return
    fi

    local nvme_disks=()
    local disk=""
    enumerate_disks
    for disk in "${DISK_NAMES[@]}"; do
        [[ "$disk" =~ ^nvme[0-9]+n[0-9]+$ ]] && nvme_disks+=("$disk")
    done
    if [[ ${#nvme_disks[@]} -eq 0 ]]; then
        for disk in /dev/nvme*n*; do
            [[ -e "$disk" ]] || continue
            nvme_disks+=("${disk##*/}")
        done
    fi

    if [[ ${#nvme_disks[@]} -eq 0 ]]; then
        print_info "${LBL[status]}" "${LBL[not_detected]}"
        section_end
        return
    fi

    local nvme_checked=0
    local nvme_warn_count=0
    local nvme_no_data=0
    local nvme_warn_lines=()
    local unsafe_summary=()
    local -a nvme_rows=()
    local sep=$'\034'   # non-whitespace: IFS=$'\t' would merge empty fields

    for disk in "${nvme_disks[@]}"; do
        local dev="/dev/$disk"
        local controller="${disk%%n[0-9]*}"
        local controller_dev="/dev/$controller"
        local smart_json="" error_json="" id_json=""
        local model="" serial="" firmware="" temperature="" critical_warning="" media_errors="" error_entries=""
        local unsafe_shutdowns="" percentage_used="" available_spare="" spare_threshold="" warning_temp_time="" critical_temp_time="" nonzero_error_entries=""
        local temperature_c=""
        local nvme_kv=()

        ((nvme_checked++))

        # Usually prefetched in the background (nvme_query_one); else query now
        local pf_smart=""
        prefetched_file_to pf_smart "nvme_${disk}.smart"
        if [[ -n "$pf_smart" ]]; then
            slurp_file smart_json "$pf_smart"
            slurp_file error_json "$PREFETCH_DIR/nvme_${disk}.err"
            slurp_file id_json "$PREFETCH_DIR/nvme_${disk}.id"
        else
            smart_json=$(run_limited "$NVME_TIMEOUT_SECONDS" nvme smart-log -o json "$dev" 2>/dev/null)
            error_json=$(run_limited "$NVME_TIMEOUT_SECONDS" nvme error-log -e 8 -o json "$dev" 2>/dev/null)
            id_json=$(run_limited "$NVME_TIMEOUT_SECONDS" nvme id-ctrl -o json "$controller_dev" 2>/dev/null)
            [[ -z "$id_json" ]] && id_json=$(run_limited "$NVME_TIMEOUT_SECONDS" nvme id-ctrl -o json "$dev" 2>/dev/null)
        fi

        if [[ -n "$id_json" ]] && command -v jq >/dev/null 2>&1; then
            local key="" value=""
            while IFS=$'\t' read -r key value; do
                case "$key" in
                    model) model="$value" ;;
                    serial) serial="$value" ;;
                    firmware) firmware="$value" ;;
                esac
            done < <(nvme_id_tsv "$id_json")
        fi

        if [[ -n "$smart_json" ]] && command -v jq >/dev/null 2>&1; then
            local key="" value=""
            while IFS=$'\t' read -r key value; do
                case "$key" in
                    model) [[ -z "$model" ]] && model="$value" ;;
                    serial) [[ -z "$serial" ]] && serial="$value" ;;
                    firmware) [[ -z "$firmware" ]] && firmware="$value" ;;
                    temperature) temperature="$value" ;;
                    critical_warning) critical_warning="$value" ;;
                    media_errors) media_errors="$value" ;;
                    error_log_entries) error_entries="$value" ;;
                    nonzero_error_log_slots) nonzero_error_entries="$value" ;;
                    unsafe_shutdowns) unsafe_shutdowns="$value" ;;
                    percentage_used) percentage_used="$value" ;;
                    available_spare) available_spare="$value" ;;
                    spare_threshold) spare_threshold="$value" ;;
                    warning_temp_time) warning_temp_time="$value" ;;
                    critical_temp_time) critical_temp_time="$value" ;;
                esac
            done < <(nvme_health_tsv "$smart_json")
        fi

        if [[ -n "$error_json" ]] && command -v jq >/dev/null 2>&1; then
            nonzero_error_entries=$(jq -r '[.errors[]? | select((.error_count // 0) != 0)] | length' 2>/dev/null <<< "$error_json")
        fi

        if [[ "$temperature" =~ ^[0-9]+$ ]]; then
            if [[ "$temperature" -gt 200 ]]; then
                temperature_c=$((temperature - 273))
            else
                temperature_c="$temperature"
            fi
        fi

        # nvme-cli space-pads id-ctrl fields (mn/sn/fr) to fixed width — trim.
        model="${model%"${model##*[![:space:]]}"}"
        serial="${serial%"${serial##*[![:space:]]}"}"
        firmware="${firmware%"${firmware##*[![:space:]]}"}"

        # No health data at all (non-root, jq missing, or the query failed):
        # show N/A rather than a green "OK" for a drive we could not read.
        local nvme_status="OK"
        [[ -z "$temperature$critical_warning$percentage_used$available_spare$media_errors" ]] && nvme_status="N/A"
        local nvme_warn=()
        # WARN only on genuine health signals. Historical counters (error-log
        # entries, cumulative warning/critical temp time, unsafe shutdowns) are
        # informational and must NOT flag a healthy drive.
        [[ "$critical_warning" =~ ^[0-9]+$ && "$critical_warning" -ne 0 ]] && nvme_warn+=("critical_warning=$critical_warning")
        [[ "$media_errors" =~ ^[0-9]+$ && "$media_errors" -gt 0 ]] && nvme_warn+=("media_errors=$media_errors")
        if [[ "$available_spare" =~ ^[0-9]+$ && "$spare_threshold" =~ ^[0-9]+$ && "$available_spare" -lt "$spare_threshold" ]]; then
            nvme_warn+=("spare ${available_spare}%<${spare_threshold}%")
        fi
        [[ "$percentage_used" =~ ^[0-9]+$ && "$percentage_used" -ge 90 ]] && nvme_warn+=("used=${percentage_used}%")
        [[ ${#nvme_warn[@]} -gt 0 ]] && nvme_status="WARN"

        # Health verdict (shares kinds with the smartctl disk check: no duplicates)
        if [[ "$critical_warning" =~ ^[0-9]+$ && "$critical_warning" -ne 0 ]]; then
            health_add fail "$disk" nvme_cw "NVMe critical warning $critical_warning" "NVMe 严重告警 $critical_warning"
        fi
        if [[ "$media_errors" =~ ^[0-9]+$ && "$media_errors" -gt 0 ]]; then
            health_add fail "$disk" media "$media_errors media errors" "介质错误 $media_errors"
        fi
        if [[ "$available_spare" =~ ^[0-9]+$ && "$spare_threshold" =~ ^[0-9]+$ && "$available_spare" -lt "$spare_threshold" ]]; then
            health_add fail "$disk" spare "available spare ${available_spare}% below threshold ${spare_threshold}%" \
                "可用备用空间 ${available_spare}% 低于阈值 ${spare_threshold}%"
        fi
        if [[ "$percentage_used" =~ ^[0-9]+$ ]]; then
            if (( percentage_used >= 100 )); then
                health_add fail "$disk" wear "${percentage_used}% of rated endurance used" "已用寿命 ${percentage_used}%"
            elif (( percentage_used >= 80 )); then
                health_add warn "$disk" wear "${percentage_used}% of rated endurance used" "已用寿命 ${percentage_used}%"
            fi
        fi
        if [[ "$temperature_c" =~ ^[0-9]+$ ]] && (( temperature_c >= 70 )); then
            health_add warn "$disk" temp "temperature ${temperature_c}°C" "温度 ${temperature_c}°C"
        fi

        # Row for the table
        local temp_disp="-" used_disp="-" spare_disp="-"
        [[ -n "$temperature_c" ]] && temp_disp="${temperature_c}°C"
        [[ -n "$percentage_used" ]] && used_disp="${percentage_used}%"
        [[ -n "$available_spare" ]] && spare_disp="${available_spare}%"
        nvme_rows+=("${dev}${sep}${model:-Unknown}${sep}${temp_disp}${sep}${used_disp}${sep}${spare_disp}${sep}${nvme_status}")

        [[ "$nvme_status" == "N/A" ]] && ((nvme_no_data++))
        [[ "$unsafe_shutdowns" =~ ^[0-9]+$ && "$unsafe_shutdowns" -gt 0 ]] && unsafe_summary+=("${disk}=$unsafe_shutdowns")
        if [[ "$nvme_status" == "WARN" ]]; then
            ((nvme_warn_count++))
            nvme_warn_lines+=("${dev}${sep}${nvme_warn[*]}")
        fi

        if [[ "$COLLECT_JSON" == true ]]; then
            nvme_kv=(
                "$(json_kv_s "device" "$dev")"
                "$(json_kv "status" "$nvme_status")"
            )
            [[ -n "$controller_dev" ]] && nvme_kv+=("$(json_kv_s "controller" "$controller_dev")")
            [[ -n "$model" ]] && nvme_kv+=("$(json_kv_s "model" "$model")")
            [[ -n "$serial" ]] && nvme_kv+=("$(json_kv_s "serial" "$serial")")
            [[ -n "$firmware" ]] && nvme_kv+=("$(json_kv_s "firmware" "$firmware")")
            [[ -n "$temperature" ]] && nvme_kv+=("$(json_kv "temperature_kelvin" "$temperature")")
            [[ -n "$temperature_c" ]] && nvme_kv+=("$(json_kv "temperature_c" "$temperature_c")")
            [[ -n "$critical_warning" ]] && nvme_kv+=("$(json_kv "critical_warning" "$critical_warning")")
            [[ -n "$media_errors" ]] && nvme_kv+=("$(json_kv "media_errors" "$media_errors")")
            [[ -n "$error_entries" ]] && nvme_kv+=("$(json_kv "error_log_entries" "$error_entries")")
            [[ -n "$nonzero_error_entries" ]] && nvme_kv+=("$(json_kv "nonzero_error_log_slots" "$nonzero_error_entries")")
            [[ -n "$unsafe_shutdowns" ]] && nvme_kv+=("$(json_kv "unsafe_shutdowns" "$unsafe_shutdowns")")
            [[ -n "$percentage_used" ]] && nvme_kv+=("$(json_kv "percentage_used" "$percentage_used")")
            [[ -n "$available_spare" ]] && nvme_kv+=("$(json_kv "available_spare" "$available_spare")")
            [[ -n "$warning_temp_time" ]] && nvme_kv+=("$(json_kv "warning_temp_time" "$warning_temp_time")")
            [[ -n "$critical_temp_time" ]] && nvme_kv+=("$(json_kv "critical_temp_time" "$critical_temp_time")")
            JSON_NVME_DEEP+=("$(json_obj "${nvme_kv[@]}")")
        fi
    done

    # Render table
    TABLE_COL_W=(14 26 7 7 7 7)
    if [[ "$LANG_MODE" == "cn" ]]; then
        table_header "设备" "型号" "温度" "耐久" "备用" "状态"
    else
        table_header "Device" "Model" "Temp" "Used" "Spare" "Status"
    fi
    local r="" d="" m="" t="" u="" sp="" st="" stc=""
    for r in "${nvme_rows[@]}"; do
        IFS="$sep" read -r d m t u sp st <<< "$r"
        stc="$GREEN"; [[ "$st" == "WARN" || "$st" == "N/A" ]] && stc="$YELLOW"
        # colorize temperature
        local tnum="${t%%°*}" tcolor=""
        if [[ "$tnum" =~ ^[0-9]+$ ]]; then
            if (( tnum >= 70 )); then tcolor="$RED"
            elif (( tnum >= 60 )); then tcolor="$YELLOW"
            else tcolor="$GREEN"; fi
        fi
        table_row "$d" "$CYAN" "$m" "" "$t" "$tcolor" "$u" "" "$sp" "" "$st" "$stc"
    done
    table_close
    if [[ "$nvme_no_data" -gt 0 ]]; then
        if [[ $EUID -ne 0 ]]; then
            print_note "N/A" "${LBL[needs_root]}"
        elif ! command -v jq >/dev/null 2>&1; then
            if [[ "$LANG_MODE" == "cn" ]]; then print_note "N/A" "未安装 jq"; else print_note "N/A" "jq not installed"; fi
        fi
    fi

    if [[ "$nvme_warn_count" -gt 0 ]]; then
        echo "│"
        [[ "$LANG_MODE" == "cn" ]] && print_color "$YELLOW" "│ 健康告警:" || print_color "$YELLOW" "│ Health warnings:"
        local nvme_warn_line="" wdev="" wdetail=""
        for nvme_warn_line in "${nvme_warn_lines[@]}"; do
            IFS="$sep" read -r wdev wdetail <<< "$nvme_warn_line"
            print_note "$wdev" "$wdetail"
        done
    fi
    if [[ ${#unsafe_summary[@]} -gt 0 ]]; then
        local us_label="Unsafe shutdowns (lifetime)"
        [[ "$LANG_MODE" == "cn" ]] && us_label="异常掉电(累计)"
        printf "│   %s%s %s: %s%s\n" "$DIM" "$SYM_DOT" "$us_label" "${unsafe_summary[*]}" "$NC"
    fi

    section_end
}


# Helper function: Query smartctl JSON with jq when available
json_query() {
    local filter="$1"
    local json="$2"
    local result=""

    command -v jq >/dev/null 2>&1 || return 1
    result=$(jq -r "($filter) | if . == null then empty else . end" 2>/dev/null <<< "$json") || return 1
    [[ -z "$result" || "$result" == "null" ]] && return 1
    printf '%s\n' "$result"
}

# One jq pass over a smartctl --json document -> "key<TAB>value" lines for
# every field the disk summary needs (identity, health, I/O, defects).
# Transfer counters are matched by attribute id *and* name, and their unit is
# taken from the name: Intel 241/242 count 32 MiB, Kingston/SandForce count
# GiB, others count LBAs. (Ids 247/248 are not used: on Micron/Crucial they
# are NAND page counts / lifetime %, not host reads/writes.)
smart_json_fields_tsv() {
    jq -r '
        def s($v): if $v == null then "" else ($v | tostring) end;
        (.ata_smart_attributes.table // []) as $t |
        (.logical_block_size // 512) as $lbs |
        def raw_id($id): ([$t[] | select(.id == $id) | .raw.value] | first);
        def unit($name):
            if ($name | test("32MiB"; "i")) then 33554432
            elif ($name | test("GiB|_GB$"; "i")) then 1073741824
            elif ($name | test("MiB"; "i")) then 1048576
            else $lbs end;
        ([$t[] | select(.id == 241 or .id == 246 or ((.name // "") |
            test("^(Total_LBAs_Written|Host_Writes_(32MiB|MiB|GiB)|Lifetime_Writes_GiB|Total_Writes_(32MiB|GiB))$"; "i")))]
            | first) as $w |
        ([$t[] | select(.id == 242 or ((.name // "") |
            test("^(Total_LBAs_Read|Host_Reads_(32MiB|MiB|GiB)|Lifetime_Reads_GiB|Total_Reads_(32MiB|GiB))$"; "i")))]
            | first) as $r |
        (([$t[] | select(.id == 177 or .id == 231 or .id == 233)] | first)
            // ([$t[] | select((.name // "") | test("Wear_Leveling_Count|SSD_Life_Left|Media_Wearout_Indicator"; "i"))] | first)
        ) as $wear |
        (.nvme_smart_health_information_log // {}) as $n |
        (.scsi_error_counter_log // {}) as $e |
        [
            ["smart_available", s(.smart_support.available)],
            ["smart_passed", s(.smart_status.passed)],
            ["temperature", s(.temperature.current)],
            ["power_on_hours", s(.power_on_time.hours)],
            ["model_family", s(.model_family)],
            ["model_name", s(.model_name)],
            ["serial_number", s(.serial_number)],
            ["firmware", s(.firmware_version // .scsi_revision)],
            ["scsi_vendor", s(.scsi_vendor)],
            ["scsi_product", s(.scsi_product)],
            ["capacity_bytes", s(.user_capacity.bytes)],
            ["device_type", s(.device.type)],
            ["protocol", s(.device.protocol)],
            ["data_units_read", s($n.data_units_read)],
            ["data_units_written", s($n.data_units_written)],
            ["percentage_used", s($n.percentage_used)],
            ["available_spare", s($n.available_spare)],
            ["critical_warning", s($n.critical_warning)],
            ["media_errors", s($n.media_errors)],
            ["lba_written", s($w.raw.value)],
            ["write_multiplier", (if $w then (unit($w.name // "") | tostring) else "" end)],
            ["lba_read", s($r.raw.value)],
            ["read_multiplier", (if $r then (unit($r.name // "") | tostring) else "" end)],
            ["wear_level", s($wear.value)],
            ["wear_name", s($wear.name)],
            ["grown_defects", s(.scsi_grown_defect_list)],
            ["read_uncorrected", s($e.read.total_uncorrected_errors)],
            ["write_uncorrected", s($e.write.total_uncorrected_errors)],
            ["verify_uncorrected", s($e.verify.total_uncorrected_errors)],
            ["non_medium_errors", s(.scsi_non_medium_error_count // .scsi_nonmedium_error_count // $e.non_medium_error_count)],
            ["reallocated_sectors", s(raw_id(5))],
            ["pending_sectors", s(raw_id(197))],
            ["offline_uncorrectable", s(raw_id(198))],
            ["reported_uncorrect", s(raw_id(187))]
        ][] | @tsv
    ' 2>/dev/null <<< "$1"
}

# sj_re KEY JSON REGEX [GROUP] - jq-less fallback: SJ[KEY] = regex capture.
sj_re() {
    [[ "$2" =~ $3 ]] && SJ[$1]="${BASH_REMATCH[${4:-1}]}"
}

# Same fields as smart_json_fields_tsv, extracted with bash regexes from the
# compact (--json=c) output. Used only when jq is not installed; needs no
# grep -P (absent on busybox / minimal systems) and forks nothing.
smart_json_load_regex() {
    local j="$1" k="" id="" name=""
    local attr_tail='[^{}]*(\{[^{}]*\}[^{}]*)?"raw":\{"value":([0-9]+)'

    sj_re smart_available "$j" '"smart_support":\{"available":(true|false)'
    sj_re smart_passed "$j" '"smart_status":\{"passed":(true|false)'
    sj_re temperature "$j" '"temperature":\{"current":([0-9]+)'
    sj_re power_on_hours "$j" '"power_on_time":\{"hours":([0-9]+)'
    for k in model_family model_name serial_number scsi_vendor scsi_product; do
        sj_re "$k" "$j" "\"$k\":\"([^\"]*)\""
    done
    sj_re firmware "$j" '"firmware_version":"([^"]*)"'
    [[ -z "${SJ[firmware]:-}" ]] && sj_re firmware "$j" '"scsi_revision":"([^"]*)"'
    sj_re capacity_bytes "$j" '"user_capacity":\{[^}]*"bytes":([0-9]+)'
    sj_re device_type "$j" '"device":\{[^}]*"type":"([^"]*)"'
    sj_re protocol "$j" '"device":\{[^}]*"protocol":"([^"]*)"'
    for k in data_units_read data_units_written percentage_used available_spare critical_warning media_errors; do
        sj_re "$k" "$j" "\"nvme_smart_health_information_log\":\\{[^}]*\"$k\":([0-9]+)"
    done
    sj_re grown_defects "$j" '"scsi_grown_defect_list":([0-9]+)'
    sj_re read_uncorrected "$j" '"read":\{[^}]*"total_uncorrected_errors":([0-9]+)'
    sj_re write_uncorrected "$j" '"write":\{[^}]*"total_uncorrected_errors":([0-9]+)'
    sj_re verify_uncorrected "$j" '"verify":\{[^}]*"total_uncorrected_errors":([0-9]+)'
    sj_re non_medium_errors "$j" '"(scsi_non_medium_error_count|scsi_nonmedium_error_count|non_medium_error_count)":([0-9]+)' 2

    for id in 5:reallocated_sectors 197:pending_sectors 198:offline_uncorrectable 187:reported_uncorrect; do
        sj_re "${id#*:}" "$j" "\"id\":${id%%:*},${attr_tail}" 2
    done

    # Host writes / reads (first matching id, unit from the attribute name)
    for id in 241 246; do
        if [[ "$j" =~ \"id\":${id},\"name\":\"([^\"]*)\"${attr_tail} ]]; then
            name="${BASH_REMATCH[1]}"
            SJ[lba_written]="${BASH_REMATCH[3]}"
            SJ[write_multiplier]=512
            case "$name" in
                *32MiB*) SJ[write_multiplier]=33554432 ;;
                *GiB*) SJ[write_multiplier]=1073741824 ;;
                *MiB*) SJ[write_multiplier]=1048576 ;;
            esac
            break
        fi
    done
    if [[ "$j" =~ \"id\":242,\"name\":\"([^\"]*)\"${attr_tail} ]]; then
        name="${BASH_REMATCH[1]}"
        SJ[lba_read]="${BASH_REMATCH[3]}"
        SJ[read_multiplier]=512
        case "$name" in
            *32MiB*) SJ[read_multiplier]=33554432 ;;
            *GiB*) SJ[read_multiplier]=1073741824 ;;
            *MiB*) SJ[read_multiplier]=1048576 ;;
        esac
    fi
    if [[ "$j" =~ \"id\":(177|231|233),\"name\":\"([^\"]*)\",\"value\":([0-9]+) ]]; then
        SJ[wear_name]="${BASH_REMATCH[2]}"
        SJ[wear_level]="${BASH_REMATCH[3]}"
    fi
}

# smart_json_load JSON - fill SJ[] from one smartctl JSON document.
smart_json_load() {
    local json="$1" key="" value=""
    SJ=()
    [[ -z "$json" ]] && return 1
    if command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r key value; do
            [[ -n "$key" && -n "$value" ]] && SJ[$key]="$value"
        done < <(smart_json_fields_tsv "$json")
        [[ ${#SJ[@]} -gt 0 ]] && return 0
    fi
    smart_json_load_regex "$json"
    return 0
}

nvme_health_tsv() {
    local json="$1"

    command -v jq >/dev/null 2>&1 || return 1
    jq -r '
        def s($v): if $v == null then "" else ($v | tostring) end;
        (.nvme_smart_health_information_log // .) as $n |
        [
            ["model", s(.model_name // .device.model_name // .model)],
            ["serial", s(.serial_number // .device.serial_number // .serial_number)],
            ["firmware", s(.firmware_version // .device.firmware_version // .firmware_version)],
            ["temperature", s($n.temperature // .temperature.current // .temperature_celsius)],
            ["critical_warning", s($n.critical_warning // .critical_warning)],
            ["media_errors", s($n.media_errors // .media_errors)],
            ["error_log_entries", s($n.num_err_log_entries // $n.error_log_entries // .num_err_log_entries)],
            ["nonzero_error_log_slots", s(([.nvme_error_information_log.table[]? | select((.error_count // 0) != 0)] | length))],
            ["unsafe_shutdowns", s($n.unsafe_shutdowns // .unsafe_shutdowns)],
            ["percentage_used", s($n.percentage_used // $n.percent_used // .percentage_used // .percent_used)],
            ["available_spare", s($n.available_spare // $n.avail_spare // .available_spare // .avail_spare)],
            ["spare_threshold", s($n.available_spare_threshold // $n.spare_thresh // .spare_thresh)],
            ["warning_temp_time", s($n.warning_temp_time // .warning_temp_time)],
            ["critical_temp_time", s($n.critical_comp_time // $n.critical_temp_time // .critical_temp_time)]
        ][] | @tsv
    ' 2>/dev/null <<< "$json"
}

nvme_id_tsv() {
    local json="$1"

    command -v jq >/dev/null 2>&1 || return 1
    jq -r '
        def s($v): if $v == null then "" else ($v | tostring) end;
        [
            ["model", s(.mn)],
            ["serial", s(.sn)],
            ["firmware", s(.fr)]
        ][] | @tsv
    ' 2>/dev/null <<< "$json"
}

# Skip BMC/IPMI virtual media and other non-storage pseudo-disks.
# Common on bare-metal with remote KVM: AMI "Virtual Floppy0" etc. as /dev/sdX, SIZE=0B.
is_pseudo_or_virtual_media() {
    local name="${1:-}" size="${2:-}" model="${3:-}" vendor="${4:-}"
    local m="${model,,}" v="${vendor,,}" s="${size,,}"
    v="${v%"${v##*[![:space:]]}"}"

    # Zero-capacity block devices (typical virtual floppy/CD stubs)
    if [[ -z "$s" || "$s" == "0b" || "$s" == "0" || "$s" == "0.0b" ]]; then
        return 0
    fi

    # Model / product strings from BMC virtual media
    if [[ "$m" =~ virtual[[:space:]]*floppy|virtual[[:space:]]*cd|virtual[[:space:]]*dvd|virtual[[:space:]]*disk|virtual[[:space:]]*media ]]; then
        return 0
    fi
    if [[ "$m" =~ ^(floppy|cdrom|cdrw|dvd|dvdram)$ ]]; then
        return 0
    fi
    # AMI / ASPEED / Avocent / iDRAC virtual media often use these vendors
    if [[ "$v" =~ ^(ami|american\ megatrends|aspeed|avocent|idrac|ilo)$ ]]; then
        if [[ "$m" =~ virtual|floppy|cd|dvd|rom|media ]]; then
            return 0
        fi
    fi

    # Name-based: never treat these as data disks
    case "$name" in
        fd[0-9]*|sr[0-9]*|scd[0-9]*|ram[0-9]*|loop[0-9]*|dm-[0-9]*|zram[0-9]*|nbd[0-9]*)
            return 0
            ;;
    esac

    return 1
}

# Record one whole-disk device for the disk section (unless it is pseudo media).
disk_register() {
    local name="${1#/dev/}" size="$2" model="$3" vendor="$4" type="${5:-disk}" info=""
    [[ -z "$name" ]] && return
    case "${type,,}" in
        rom|floppy) return ;;
    esac
    is_pseudo_or_virtual_media "$name" "$size" "$model" "$vendor" && return

    model="${model#"${model%%[![:space:]]*}"}"; model="${model%"${model##*[![:space:]]}"}"
    vendor="${vendor#"${vendor%%[![:space:]]*}"}"; vendor="${vendor%"${vendor##*[![:space:]]}"}"
    # "ATA" (libata placeholder) carries no information; 0x1af4 is virtio's PCI vendor id
    [[ "$vendor" == "ATA" ]] && vendor=""
    if [[ "$vendor" == "0x1af4" ]]; then
        vendor=""
        [[ -z "$model" ]] && model="virtio"
    fi
    info="$size $model $vendor"
    while [[ "$info" == *"  "* ]]; do info="${info//  / }"; done
    info="${info#"${info%%[![:space:]]*}"}"; info="${info%"${info##*[![:space:]]}"}"

    DISK_NAMES+=("$name")
    DISK_BASIC_INFO_CACHE[$name]="$info"
}

# Enumerate whole-disk block devices once: lsblk, or /sys/block without it
# (busybox systems). Fills DISK_NAMES / DISK_BASIC_INFO_CACHE.
enumerate_disks() {
    [[ "$DISK_ENUM_DONE" == true ]] && return
    DISK_ENUM_DONE=true
    DISK_NAMES=()

    local entry="" name="" size="" model="" vendor="" type=""
    if command -v lsblk >/dev/null 2>&1; then
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            kv_line_get name "$entry" NAME
            kv_line_get size "$entry" SIZE
            kv_line_get model "$entry" MODEL
            kv_line_get vendor "$entry" VENDOR
            kv_line_get type "$entry" TYPE
            disk_register "$name" "$size" "$model" "$vendor" "$type"
        done < <(run_limited 10 lsblk -d -n -P -o NAME,SIZE,MODEL,VENDOR,TYPE,TRAN 2>/dev/null)
    fi

    if [[ ${#DISK_NAMES[@]} -eq 0 ]]; then
        local dev="" sectors=""
        for dev in /sys/block/*; do
            [[ -e "$dev" ]] || continue
            name="${dev##*/}"
            read_line sectors "$dev/size"
            size=""
            [[ "$sectors" =~ ^[0-9]+$ && "$sectors" -gt 0 ]] && format_bytes_to size "$((sectors * 512))"
            [[ -z "$size" ]] && size="0B"
            read_line model "$dev/device/model"
            read_line vendor "$dev/device/vendor"
            type="disk"
            [[ "$name" == sr* ]] && type="rom"
            disk_register "$name" "$size" "$model" "$vendor" "$type"
        done
    fi
}

# Run smartctl with a short timeout so unhealthy devices do not stall the whole report.
run_smartctl() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$SMARTCTL_TIMEOUT_SECONDS" smartctl "$@"
    else
        smartctl "$@"
    fi
}

get_smartctl_major_version() {
    if [[ "$SMARTCTL_VERSION_CHECKED" == true ]]; then
        return
    fi

    SMARTCTL_VERSION_MAJOR=""
    if command -v smartctl >/dev/null 2>&1; then
        local smartctl_version=""
        smartctl_version=$(run_smartctl --version 2>/dev/null)
        if [[ "$smartctl_version" =~ ([0-9]+)\.[0-9]+ ]]; then
            SMARTCTL_VERSION_MAJOR="${BASH_REMATCH[1]}"
        fi
    fi

    SMARTCTL_VERSION_CHECKED=true
}

smartctl_supports_json() {
    get_smartctl_major_version
    [[ -n "$SMARTCTL_VERSION_MAJOR" && "$SMARTCTL_VERSION_MAJOR" -ge 7 ]]
}

# ---------------------------------------------------------------------------
# Background prefetch. smartctl / nvme-cli take 50 ms - several seconds per
# device, so every per-device query is started up front by one background
# dispatcher (at most SMARTCTL_PARALLEL at a time, each under a timeout) while
# the CPU / memory sections render. Results are files in PREFETCH_DIR; the
# disk / NVMe sections call prefetch_wait and read them. Anything not
# prefetched is still queried synchronously, so this is purely an optimization.
# bash 4.2-safe: no `wait -n`; the oldest job is waited for when the pool is full.
# ---------------------------------------------------------------------------
PF_PIDS=()
PF_DIR=""
PF_JOBNO=0
# pf_spawn KIND OUTFILE CMD... - KIND "dev" jobs count towards the spinner's
# progress bar (one per disk); each job drops PF_DIR/done.KIND.N when finished.
pf_spawn() {
    local kind="$1" out="$2"
    shift 2
    while (( ${#PF_PIDS[@]} >= SMARTCTL_PARALLEL )); do
        wait "${PF_PIDS[0]}" 2>/dev/null
        PF_PIDS=("${PF_PIDS[@]:1}")
    done
    PF_JOBNO=$((PF_JOBNO + 1))
    local marker="$PF_DIR/done.$kind.$PF_JOBNO"
    { "$@" > "$out" 2>/dev/null; : > "$marker"; } &
    PF_PIDS+=("$!")
}

# Key for a RAID member's prefetch file: /dev/bus/0 megaraid 8 -> _dev_bus_0-megaraid-8
raid_member_file_key() {
    local key="${1//\//_}-$2-$3"
    printf '%s' "${key//[^A-Za-z0-9_.-]/_}"
}

# One NVMe namespace: smart-log, error-log and controller identify.
nvme_query_one() {
    local disk="$1" dir="$2"
    local controller="${disk%%n[0-9]*}"
    run_limited "$NVME_TIMEOUT_SECONDS" nvme smart-log -o json "/dev/$disk" > "$dir/nvme_${disk}.smart" 2>/dev/null
    run_limited "$NVME_TIMEOUT_SECONDS" nvme error-log -e 8 -o json "/dev/$disk" > "$dir/nvme_${disk}.err" 2>/dev/null
    run_limited "$NVME_TIMEOUT_SECONDS" nvme id-ctrl -o json "/dev/$controller" > "$dir/nvme_${disk}.id" 2>/dev/null
    if [[ ! -s "$dir/nvme_${disk}.id" ]]; then
        run_limited "$NVME_TIMEOUT_SECONDS" nvme id-ctrl -o json "/dev/$disk" > "$dir/nvme_${disk}.id" 2>/dev/null
    fi
}

# Runs in the background (see start_hw_prefetch).
prefetch_dispatch() {
    local dir="$1" have_smart="$2" use_json="$3" have_nvme="$4"
    local disk="" scan_pid="" member="" device="" raid_type="" raid_id=""
    local total=0 nvme_kind="aux"
    PF_PIDS=()
    PF_DIR="$dir"
    PF_JOBNO=0

    # Progress total = disks queried (smartctl), or NVMe namespaces without it
    [[ "$have_smart" == true ]] || nvme_kind="dev"
    for disk in "${DISK_NAMES[@]}"; do
        [[ "$disk" =~ $DISK_NAME_REGEX ]] || continue
        if [[ "$have_smart" == true || "$disk" =~ ^nvme[0-9]+n[0-9]+$ ]]; then
            total=$((total + 1))
        fi
    done
    printf '%s\n' "$total" > "$dir/total"

    if [[ "$have_smart" == true ]]; then
        pf_spawn aux "$dir/scan" run_smartctl --scan
        scan_pid="${PF_PIDS[${#PF_PIDS[@]}-1]}"
    fi

    for disk in "${DISK_NAMES[@]}"; do
        [[ "$disk" =~ $DISK_NAME_REGEX ]] || continue
        if [[ "$have_smart" == true ]]; then
            if [[ "$use_json" == true ]]; then
                pf_spawn dev "$dir/smart_${disk}.json" run_smartctl -a --json=c "/dev/$disk"
            else
                pf_spawn dev "$dir/smart_${disk}.txt" run_smartctl -a "/dev/$disk"
            fi
        fi
        if [[ "$have_nvme" == true && "$disk" =~ ^nvme[0-9]+n[0-9]+$ ]]; then
            pf_spawn "$nvme_kind" /dev/null nvme_query_one "$disk" "$dir"
        fi
    done

    # RAID / HBA members behind the controller (megaraid, cciss, 3ware, areca)
    if [[ -n "$scan_pid" && "$use_json" == true ]]; then
        wait "$scan_pid" 2>/dev/null
        slurp_file SMARTCTL_SCAN_CACHE "$dir/scan"
        SMARTCTL_SCAN_DONE=true
        get_raid_member_devices
        while IFS= read -r member; do
            [[ -n "$member" ]] && total=$((total + 1))
        done <<< "$RAID_MEMBER_RESULT"
        printf '%s\n' "$total" > "$dir/total"
        while IFS= read -r member; do
            [[ -z "$member" ]] && continue
            IFS=: read -r device raid_type raid_id <<< "$member"
            pf_spawn dev "$dir/raid_$(raid_member_file_key "$device" "$raid_type" "$raid_id").json" \
                run_smartctl -a --json=c -d "$raid_type,$raid_id" "$device"
        done <<< "$RAID_MEMBER_RESULT"
    fi

    wait
}

start_hw_prefetch() {
    [[ -n "$PREFETCH_PID" || "$PREFETCH_DONE" == true || -n "$PREFETCH_DIR" ]] && return
    enumerate_disks

    local have_smart=false use_json=false have_nvme=false
    command -v smartctl >/dev/null 2>&1 && have_smart=true
    command -v nvme >/dev/null 2>&1 && have_nvme=true
    [[ "$have_smart" == false && "$have_nvme" == false ]] && return
    [[ "$have_smart" == true ]] && smartctl_supports_json && use_json=true

    PREFETCH_DIR=$(mktemp -d 2>/dev/null) || { PREFETCH_DIR=""; return; }
    TEMP_FILES+=("$PREFETCH_DIR")

    prefetch_dispatch "$PREFETCH_DIR" "$have_smart" "$use_json" "$have_nvme" </dev/null >/dev/null 2>&1 &
    PREFETCH_PID=$!
}

prefetch_wait() {
    [[ "$PREFETCH_DONE" == true ]] && return
    PREFETCH_DONE=true
    if [[ -n "$PREFETCH_PID" ]]; then
        if kill -0 "$PREFETCH_PID" 2>/dev/null; then
            local label="Reading SMART data"
            [[ "$LANG_MODE" == "cn" ]] && label="读取 SMART 数据"
            if ! command -v smartctl >/dev/null 2>&1; then
                label="Reading NVMe health"
                [[ "$LANG_MODE" == "cn" ]] && label="读取 NVMe 健康数据"
            fi
            spin_start "$label" "" "$PREFETCH_DIR"
        fi
        wait "$PREFETCH_PID" 2>/dev/null
        PREFETCH_PID=""
        spin_stop
    fi
}

# prefetched_file_to VAR NAME - VAR=path when the prefetch produced NAME.
prefetched_file_to() {
    local __path=""
    prefetch_wait
    [[ -n "$PREFETCH_DIR" && -f "$PREFETCH_DIR/$2" ]] && __path="$PREFETCH_DIR/$2"
    printf -v "$1" '%s' "$__path"
}

# Cached smartctl --scan output to avoid repeated scans
get_smartctl_scan() {
    if [[ "$SMARTCTL_SCAN_DONE" == true ]]; then
        SMARTCTL_SCAN_RESULT="$SMARTCTL_SCAN_CACHE"
        return
    fi

    local f=""
    SMARTCTL_SCAN_CACHE=""
    prefetched_file_to f scan
    if [[ -n "$f" ]]; then
        slurp_file SMARTCTL_SCAN_CACHE "$f"
    elif command -v smartctl >/dev/null 2>&1; then
        SMARTCTL_SCAN_CACHE=$(run_smartctl --scan 2>/dev/null)
    fi

    SMARTCTL_SCAN_DONE=true
    SMARTCTL_SCAN_RESULT="$SMARTCTL_SCAN_CACHE"
}

# Function to get RAID member disks from smartctl --scan
# Supports: megaraid (LSI/AVAGO), cciss (HP Smart Array), 3ware, areca
get_raid_member_devices() {
    local devices=() line="" device="" raid_id=""

    if [[ "$RAID_MEMBER_CACHE_READY" == true ]]; then
        RAID_MEMBER_RESULT="$RAID_MEMBER_CACHE"
        return
    fi

    # Run smartctl --scan and look for RAID devices (cached)
    get_smartctl_scan
    local scan_output="$SMARTCTL_SCAN_RESULT"

    # Extract RAID device entries
    # Format examples:
    #   /dev/bus/6 -d megaraid,32 # /dev/bus/6 [megaraid_disk_32], SCSI device
    #   /dev/sda -d cciss,0 # /dev/sda [cciss_disk_00], SCSI device
    #   /dev/twa0 -d 3ware,0 # /dev/twa0 [3ware_disk_00], ATA device
    while IFS= read -r line; do
        device="${line%% *}"
        if [[ "$line" =~ (megaraid|cciss|3ware|areca),([0-9]+) ]]; then
            raid_id="${BASH_REMATCH[2]}"
            devices+=("$device:${BASH_REMATCH[1]}:$raid_id")
        fi
    done <<< "$scan_output"

    RAID_MEMBER_CACHE=""
    [[ ${#devices[@]} -gt 0 ]] && RAID_MEMBER_CACHE=$(printf '%s\n' "${devices[@]}")
    RAID_MEMBER_CACHE_READY=true

    RAID_MEMBER_RESULT="$RAID_MEMBER_CACHE"
}

# Function to get SMART JSON for RAID member device
# Supports: megaraid, cciss, 3ware, areca
get_smart_json_raid() {
    local device="$1"
    local raid_type="$2"
    local raid_id="$3"
    local json_output="" f=""
    local cache_key="${device}|${raid_type}|${raid_id}"

    if [[ "${SMART_JSON_RAID_CACHE_READY[$cache_key]}" == "1" ]]; then
        SMART_JSON_RAID_RESULT="${SMART_JSON_RAID_CACHE[$cache_key]}"
        return
    fi

    prefetched_file_to f "raid_$(raid_member_file_key "$device" "$raid_type" "$raid_id").json"
    if [[ -n "$f" ]]; then
        slurp_file json_output "$f"
    else
        json_output=$(run_smartctl -a --json=c -d "$raid_type","$raid_id" "$device" 2>/dev/null)
    fi

    if [[ "$json_output" == *'"json_format_version"'* ]]; then
        SMART_JSON_RAID_CACHE[$cache_key]="$json_output"
        SMART_JSON_RAID_RESULT="$json_output"
    else
        SMART_JSON_RAID_CACHE[$cache_key]=""
        SMART_JSON_RAID_RESULT=""
    fi
    SMART_JSON_RAID_CACHE_READY[$cache_key]=1
}

# ==========================================================================
# Universal Bad Blocks Detection Function
# ==========================================================================
# This function detects and displays disk defects from either JSON or text input.
# It checks ALL available fields regardless of drive type (SAS or SATA).
#
# Usage:
#   detect_bad_blocks "sj"                    # Fields already loaded into SJ[]
#   detect_bad_blocks "json" "$json_data"     # For JSON input
#   detect_bad_blocks "text" "$smart_text"    # For text input
#
# Detected fields:
#   SAS/SCSI: scsi_grown_defect_list, total_uncorrected_errors, non_medium_error_count
#   SATA/ATA: Reallocated_Sector_Ct, Current_Pending_Sector, Offline_Uncorrectable, Reported_Uncorrect
# ==========================================================================
detect_bad_blocks() {
    local input_type="$1"  # "sj", "json" or "text"
    local data="${2:-}"

    if [[ "$input_type" == "json" ]]; then
        [[ -z "$data" ]] && return 1
        smart_json_load "$data"
        input_type="sj"
    fi
    if [[ "$input_type" == "text" && -z "$data" ]]; then
        return 1
    fi

    # Initialize all variables
    local grown_defects=""
    local read_uncorrected=""
    local write_uncorrected=""
    local verify_uncorrected=""
    local non_medium_errors=""
    local reallocated_sectors=""
    local pending_sectors=""
    local offline_uncorrectable=""
    local reported_uncorrect=""

    if [[ "$input_type" == "sj" ]]; then
        grown_defects="${SJ[grown_defects]:-}"
        read_uncorrected="${SJ[read_uncorrected]:-}"
        write_uncorrected="${SJ[write_uncorrected]:-}"
        verify_uncorrected="${SJ[verify_uncorrected]:-}"
        non_medium_errors="${SJ[non_medium_errors]:-}"
        reallocated_sectors="${SJ[reallocated_sectors]:-}"
        pending_sectors="${SJ[pending_sectors]:-}"
        offline_uncorrectable="${SJ[offline_uncorrectable]:-}"
        reported_uncorrect="${SJ[reported_uncorrect]:-}"
    else
        # ==========================================================================
        # Text Parsing (smartctl < 7)
        # ==========================================================================
        local line=""
        local section=""
        while IFS= read -r line; do
            case "$line" in
                *"Elements in grown defect list"*)
                    [[ "$line" =~ ([0-9]+) ]] && grown_defects="${BASH_REMATCH[1]}" ;;
                *"Non-medium error count"*)
                    [[ "$line" =~ ([0-9]+) ]] && non_medium_errors="${BASH_REMATCH[1]}" ;;
                read:*|write:*|verify:*)
                    # SCSI error counter log: last column = total uncorrected
                    section="${line%%:*}"
                    if [[ "$line" =~ ([0-9]+)[[:space:]]*$ ]]; then
                        case "$section" in
                            read) read_uncorrected="${BASH_REMATCH[1]}" ;;
                            write) write_uncorrected="${BASH_REMATCH[1]}" ;;
                            verify) verify_uncorrected="${BASH_REMATCH[1]}" ;;
                        esac
                    fi
                    ;;
                *Reallocated_Sector_Ct*)
                    [[ "$line" =~ ([0-9]+)[[:space:]]*$ ]] && reallocated_sectors="${BASH_REMATCH[1]}" ;;
                *Current_Pending_Sector*)
                    [[ "$line" =~ ([0-9]+)[[:space:]]*$ ]] && pending_sectors="${BASH_REMATCH[1]}" ;;
                *Offline_Uncorrectable*)
                    [[ "$line" =~ ([0-9]+)[[:space:]]*$ ]] && offline_uncorrectable="${BASH_REMATCH[1]}" ;;
                *Reported_Uncorrect*)
                    [[ "$line" =~ ([0-9]+)[[:space:]]*$ ]] && reported_uncorrect="${BASH_REMATCH[1]}" ;;
            esac
        done <<< "$data"
    fi

    # ==========================================================================
    # Display all available bad block fields
    # ==========================================================================

    # SAS/SCSI: Grown Defect List
    if [[ "$grown_defects" =~ ^[0-9]+$ ]]; then
        disk_smart_add "grown_defects" "$grown_defects"
        if [[ "$grown_defects" -gt 0 ]]; then
            printf '%s\n' "│   ${LBL[grown_defects]}: ${YELLOW}${grown_defects}${NC}"
        else
            echo "│   ${LBL[grown_defects]}: ${grown_defects}"
        fi
    fi

    # SAS/SCSI: Uncorrected Errors (with breakdown)
    local has_uncorrected=false
    [[ "$read_uncorrected" =~ ^[0-9]+$ ]] || read_uncorrected=""
    [[ "$write_uncorrected" =~ ^[0-9]+$ ]] || write_uncorrected=""
    [[ "$verify_uncorrected" =~ ^[0-9]+$ ]] || verify_uncorrected=""
    [[ -n "$read_uncorrected$write_uncorrected$verify_uncorrected" ]] && has_uncorrected=true

    if [[ "$has_uncorrected" == true ]]; then
        local total_uncorrected=$(( ${read_uncorrected:-0} + ${write_uncorrected:-0} + ${verify_uncorrected:-0} ))

        [[ -n "$read_uncorrected" ]] && disk_smart_add "read_uncorrected_errors" "$read_uncorrected"
        [[ -n "$write_uncorrected" ]] && disk_smart_add "write_uncorrected_errors" "$write_uncorrected"
        [[ -n "$verify_uncorrected" ]] && disk_smart_add "verify_uncorrected_errors" "$verify_uncorrected"
        disk_smart_add "uncorrected_errors" "$total_uncorrected"

        if [[ "$total_uncorrected" -gt 0 ]]; then
            printf '%s\n' "│   ${LBL[uncorrected_errors]}: ${RED}${total_uncorrected}${NC} (R:${read_uncorrected:-0}/W:${write_uncorrected:-0}/V:${verify_uncorrected:-0})"
        else
            echo "│   ${LBL[uncorrected_errors]}: 0 (R:${read_uncorrected:-0}/W:${write_uncorrected:-0}/V:${verify_uncorrected:-0})"
        fi
    fi

    # SAS/SCSI: Non-medium Errors
    if [[ "$non_medium_errors" =~ ^[0-9]+$ ]]; then
        disk_smart_add "non_medium_errors" "$non_medium_errors"
        if [[ "$non_medium_errors" != "0" ]]; then
            printf '%s\n' "│   ${LBL[non_medium_errors]}: ${YELLOW}${non_medium_errors}${NC}"
        fi
    fi

    local has_bad_blocks_metric=false
    local total_bad=0

    # SATA/ATA: Reallocated (5), Pending (197), Offline Uncorrectable (198)
    local metric="" metric_val=""
    for metric in reallocated_sectors pending_sectors offline_uncorrectable; do
        case "$metric" in
            reallocated_sectors) metric_val="$reallocated_sectors" ;;
            pending_sectors) metric_val="$pending_sectors" ;;
            offline_uncorrectable) metric_val="$offline_uncorrectable" ;;
        esac
        [[ "$metric_val" =~ ^[0-9]+$ ]] || continue
        has_bad_blocks_metric=true
        total_bad=$((total_bad + metric_val))
        disk_smart_add "$metric" "$metric_val"
        if [[ "$metric_val" -gt 0 ]]; then
            printf '%s\n' "│   ${LBL[$metric]}: ${YELLOW}${metric_val}${NC}"
        else
            echo "│   ${LBL[$metric]}: ${metric_val}"
        fi
    done

    # SATA/ATA: Reported Uncorrectable (ID 187)
    if [[ "$reported_uncorrect" =~ ^[0-9]+$ ]]; then
        disk_smart_add "reported_uncorrect" "$reported_uncorrect"
        if [[ "$reported_uncorrect" -gt 0 ]]; then
            printf '%s\n' "│   ${LBL[reported_uncorrect]}: ${RED}${reported_uncorrect}${NC}"
        else
            echo "│   ${LBL[reported_uncorrect]}: ${reported_uncorrect}"
        fi
    fi

    if [[ "$has_bad_blocks_metric" == true ]]; then
        disk_smart_add "bad_blocks" "$total_bad"
    fi

    if [[ "$total_bad" -gt 0 ]]; then
        printf '%s\n' "│   ${LBL[bad_blocks]}: ${RED}${total_bad}${NC}"
    fi

    return 0
}

# Function to parse SAS/SCSI/SATA SMART data from JSON (for RAID member disks)
parse_smart_json_sas() {
    local json="$1"

    if [[ -z "$json" ]]; then
        return 1
    fi
    # "--loaded": the caller already ran smart_json_load on this document
    [[ "${2:-}" == "--loaded" ]] || smart_json_load "$json"

    local vendor="${SJ[scsi_vendor]:-}"
    local product="${SJ[scsi_product]:-}"
    local model_name="${SJ[model_name]:-}"
    local model_family="${SJ[model_family]:-}"
    local serial="${SJ[serial_number]:-}"
    local capacity_bytes="${SJ[capacity_bytes]:-}"

    # Format capacity
    local capacity_formatted=""
    if [[ -n "$capacity_bytes" && "$capacity_bytes" != "0" ]]; then
        format_bytes_to capacity_formatted "$capacity_bytes"
    fi

    # Display disk info
    if [[ -n "$vendor" && -n "$product" ]]; then
        echo "│   Model: $vendor $product"
        disk_extra_add "model" "$vendor $product" s
    elif [[ -n "$model_name" ]]; then
        echo "│   Model: $model_name"
        disk_extra_add "model" "$model_name" s
    fi
    if [[ -n "$model_family" ]]; then
        echo "│   Family: $model_family"
        disk_extra_add "family" "$model_family" s
    fi
    if [[ -n "$serial" ]]; then
        echo "│   Serial: $serial"
        disk_extra_add "serial" "$serial" s
    fi
    [[ -n "${SJ[firmware]:-}" ]] && disk_extra_add "firmware" "${SJ[firmware]}" s
    if [[ -n "$capacity_formatted" ]]; then
        echo "│   Capacity: $capacity_formatted"
        disk_extra_add "capacity" "$capacity_formatted"
    fi

    # SMART status - smart_status.passed, else infer PASSED from an empty
    # grown defect list (some SAS drives report no overall status)
    local smart_passed="${SJ[smart_passed]:-}"
    if [[ -z "$smart_passed" && "${SJ[grown_defects]:-}" == "0" ]]; then
        smart_passed="true"
    fi

    if [[ "$smart_passed" == "true" ]]; then
        echo "│   ${LBL[smart_status]}: PASSED"
        disk_smart_add "smart_status" "PASSED"
    elif [[ "$smart_passed" == "false" ]]; then
        echo "│   ${LBL[smart_status]}: ${RED}FAILED${NC}"
        disk_smart_add "smart_status" "FAILED"
    else
        echo "│   ${LBL[smart_status]}: ${LBL[no_info]}"
    fi

    # Temperature
    local temperature="${SJ[temperature]:-}"
    if [[ -n "$temperature" && "$temperature" != "0" ]]; then
        echo "│   ${LBL[temperature]}: ${temperature}°C"
        disk_smart_add "temperature" "${temperature}°C"
    fi

    # Power on hours
    local power_on_hours="${SJ[power_on_hours]:-}"
    if [[ -n "$power_on_hours" ]]; then
        echo "│   ${LBL[power_on_hours]}: ${power_on_hours} hours"
        disk_smart_add "power_on_hours" "$power_on_hours"
    fi

    # Bad Blocks / Defect Detection for RAID member disks
    detect_bad_blocks "sj"

    return 0
}

# Function to get SMART data using JSON output (smartctl 7.0+)
get_smart_json() {
    local disk="$1"
    local json_output="" f=""

    if [[ "${SMART_JSON_CACHE_READY[$disk]}" == "1" ]]; then
        SMART_JSON_RESULT="${SMART_JSON_CACHE[$disk]}"
        return
    fi

    prefetched_file_to f "smart_${disk}.json"
    if [[ -n "$f" ]]; then
        slurp_file json_output "$f"
    else
        json_output=$(run_smartctl -a --json=c "/dev/$disk" 2>/dev/null)
    fi

    # Check if JSON output is valid
    if [[ "$json_output" == *'"json_format_version"'* ]]; then
        SMART_JSON_CACHE[$disk]="$json_output"
        SMART_JSON_RESULT="$json_output"
    else
        SMART_JSON_CACHE[$disk]=""
        SMART_JSON_RESULT=""
    fi
    SMART_JSON_CACHE_READY[$disk]=1
}

# Function to parse SMART data from JSON (fills DISK_SMART_FIELDS via
# disk_smart_add; the detail lines it prints are optional output)
parse_smart_json() {
    local disk="$1"
    local json="$2"

    if [[ -z "$json" ]]; then
        return 1
    fi
    smart_json_load "$json"

    local smart_status="${SJ[smart_passed]:-}"
    local temperature="${SJ[temperature]:-}"
    local power_on_hours="${SJ[power_on_hours]:-}"
    local model_family="${SJ[model_family]:-}"
    local data_units_read="${SJ[data_units_read]:-}"
    local data_units_written="${SJ[data_units_written]:-}"
    local percentage_used="${SJ[percentage_used]:-}"
    local available_spare="${SJ[available_spare]:-}"
    local critical_warning="${SJ[critical_warning]:-}"
    local lba_written="${SJ[lba_written]:-}"
    local lba_read="${SJ[lba_read]:-}"
    local write_multiplier="${SJ[write_multiplier]:-512}"
    local read_multiplier="${SJ[read_multiplier]:-512}"
    local wear_level="${SJ[wear_level]:-}"
    local formatted=""

    # SMART Status
    if [[ "$smart_status" == "true" ]]; then
        echo "│   ${LBL[smart_status]}: PASSED"
        disk_smart_add "smart_status" "PASSED"
    elif [[ "$smart_status" == "false" ]]; then
        echo "│   ${LBL[smart_status]}: ${RED}FAILED${NC}"
        disk_smart_add "smart_status" "FAILED"
    else
        echo "│   ${LBL[smart_status]}: ${LBL[no_info]}"
    fi

    # Power on hours
    if [[ -n "$power_on_hours" ]]; then
        echo "│   ${LBL[power_on_hours]}: ${power_on_hours} hours"
        disk_smart_add "power_on_hours" "$power_on_hours"
    fi

    # Data transfer - check if NVMe
    if [[ "$disk" =~ nvme || "${SJ[protocol]:-}" == "NVMe" ]]; then
        # NVMe: data_units_read/written (each unit = 512 * 1000 bytes)
        if [[ "$data_units_read" =~ ^[0-9]+$ && "$data_units_read" != "0" ]]; then
            format_bytes_to formatted "$((data_units_read * 512000))"
            if [[ -n "$formatted" ]]; then
                echo "│   ${LBL[total_reads]}: $formatted"
                disk_smart_add "total_reads" "$formatted"
            fi
        fi

        if [[ "$data_units_written" =~ ^[0-9]+$ && "$data_units_written" != "0" ]]; then
            format_bytes_to formatted "$((data_units_written * 512000))"
            if [[ -n "$formatted" ]]; then
                echo "│   ${LBL[total_writes]}: $formatted"
                disk_smart_add "total_writes" "$formatted"
            fi
        fi

        # NVMe health info
        if [[ "$percentage_used" =~ ^[0-9]+$ ]]; then
            echo "│   ${LBL[percentage_used]}: ${percentage_used}%"
            local health=$((100 - percentage_used))
            [[ $health -lt 0 ]] && health=0
            echo "│   ${LBL[health_status]}: ${health}%"
            disk_smart_add "percentage_used" "$percentage_used"
            disk_smart_add "health_status" "$health"
        fi

        if [[ -n "$available_spare" ]]; then
            echo "│   ${LBL[available_spare]}: ${available_spare}%"
            disk_smart_add "available_spare" "$available_spare"
        fi

        if [[ -n "$critical_warning" && "$critical_warning" != "0" ]]; then
            echo "│   ${LBL[critical_warning]}: ${critical_warning}"
            disk_smart_add "critical_warning" "$critical_warning"
        fi
    else
        # SATA/HDD/SSD: host read/write counters from ata_smart_attributes
        # (ids 241/242/246 or vendor names; unit decided in smart_json_fields_tsv)
        local io_stats_found=false

        if [[ "$lba_read" =~ ^[0-9]+$ && "$lba_read" != "0" && "$read_multiplier" =~ ^[0-9]+$ ]]; then
            format_bytes_to formatted "$((lba_read * read_multiplier))"
            if [[ -n "$formatted" ]]; then
                echo "│   ${LBL[total_reads]}: $formatted"
                disk_smart_add "total_reads" "$formatted"
                io_stats_found=true
            fi
        fi

        if [[ "$lba_written" =~ ^[0-9]+$ && "$lba_written" != "0" && "$write_multiplier" =~ ^[0-9]+$ ]]; then
            format_bytes_to formatted "$((lba_written * write_multiplier))"
            if [[ -n "$formatted" ]]; then
                echo "│   ${LBL[total_writes]}: $formatted"
                disk_smart_add "total_writes" "$formatted"
                io_stats_found=true
            fi
        fi

        # For SSDs without read/write stats, try to show wear level indicator
        if [[ "$io_stats_found" == false ]]; then
            if [[ -n "$wear_level" && "$wear_level" != "0" ]]; then
                echo "│   ${LBL[wear_level]}: ${wear_level}%"
                disk_smart_add "wear_level" "$wear_level"
                io_stats_found=true
            fi
        fi

        # If no I/O stats found at all, show a note with help info
        if [[ "$io_stats_found" == false ]]; then
            # Toshiba MG series enterprise HDDs don't have ID 241/242 attributes
            if [[ "$model_family" =~ Toshiba\ MG[0-9]+ACA ]]; then
                if [[ "$LANG_MODE" == "cn" ]]; then
                    echo "│   读写统计: 此型号硬盘不提供读写统计数据"
                else
                    echo "│   I/O Stats: This drive model does not report I/O statistics"
                fi
            else
                if [[ "$LANG_MODE" == "cn" ]]; then
                    echo "│   读写统计: 此硬盘型号暂不支持"
                else
                    echo "│   I/O Stats: Not supported for this drive model"
                fi
            fi
        fi
    fi

    # Temperature
    if [[ -n "$temperature" ]]; then
        echo "│   ${LBL[temperature]}: ${temperature}°C"
        disk_smart_add "temperature" "${temperature}°C"
    fi

    # Bad Blocks / Defect Detection
    detect_bad_blocks "sj"

    return 0
}

# Fallback: Parse SMART data from text output (for older smartctl)
parse_smart_text() {
    local disk="$1"
    local smart_all="" f="" line="" smart_health="" power_hours="" temp=""
    local reads="" writes="" pct_used="" spare=""
    # "Data Units Read: 123,456 [63.2 TB]" -> "63.2 TB"
    local bracket_re='[[(]([^])]+)[])]'

    prefetched_file_to f "smart_${disk}.txt"
    if [[ -n "$f" ]]; then
        slurp_file smart_all "$f"
    else
        smart_all=$(run_smartctl -a "/dev/$disk" 2>/dev/null)
    fi
    if [[ -z "$smart_all" ]]; then
        return 1
    fi

    # One pass over the text output
    while IFS= read -r line; do
        case "$line" in
            *"SMART overall-health"*|*"SMART Health Status"*)
                [[ -z "$smart_health" ]] && smart_health="${line#*: }" ;;
            *[Pp]ower[_\ ][Oo]n*[Hh]our*)
                if [[ -z "$power_hours" ]]; then
                    if [[ "$line" =~ hours:minutes[[:space:]]+([0-9]+): ]]; then
                        power_hours="${BASH_REMATCH[1]}"   # SAS: "... hours:minutes 51234:12"
                    elif [[ "$line" =~ Power_On_Hours.*[[:space:]]([0-9]+)[^[:space:]]*[[:space:]]*$ ]]; then
                        power_hours="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ :[[:space:]]*([0-9][0-9,]*) ]]; then
                        power_hours="${BASH_REMATCH[1]//,/}"
                    fi
                fi
                ;;
            Temperature:*|*Temperature_Celsius*|*"Current Drive Temperature:"*)
                if [[ -z "$temp" ]]; then
                    if [[ "$line" =~ Temperature_Celsius.*[[:space:]]([0-9]+)([[:space:]]|$) ]]; then
                        temp="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ :[[:space:]]*([0-9]+) ]]; then
                        temp="${BASH_REMATCH[1]}"
                    fi
                fi
                ;;
            *"Data Units Read"*)
                [[ "$line" =~ $bracket_re ]] && reads="${BASH_REMATCH[1]}" ;;
            *"Data Units Written"*)
                [[ "$line" =~ $bracket_re ]] && writes="${BASH_REMATCH[1]}" ;;
            *"Percentage Used"*)
                [[ "$line" =~ ([0-9]+)% ]] && pct_used="${BASH_REMATCH[1]}" ;;
            *"Available Spare:"*)
                [[ "$line" =~ ([0-9]+)% ]] && spare="${BASH_REMATCH[1]}" ;;
        esac
    done <<< "$smart_all"
    smart_health="${smart_health#"${smart_health%%[![:space:]]*}"}"

    # SMART Status
    echo "│   ${LBL[smart_status]}: ${smart_health:-${LBL[no_info]}}"
    [[ -n "$smart_health" ]] && disk_smart_add "smart_status" "$smart_health"

    # Power on hours
    if [[ -n "$power_hours" ]]; then
        echo "│   ${LBL[power_on_hours]}: ${power_hours} hours"
        disk_smart_add "power_on_hours" "$power_hours"
    fi

    # Temperature
    if [[ -n "$temp" ]]; then
        echo "│   ${LBL[temperature]}: ${temp}°C"
        disk_smart_add "temperature" "${temp}°C"
    fi

    # NVMe specific
    if [[ "$disk" =~ nvme ]]; then
        if [[ -n "$reads" ]]; then
            echo "│   ${LBL[total_reads]}: $reads"
            disk_smart_add "total_reads" "$reads"
        fi
        if [[ -n "$writes" ]]; then
            echo "│   ${LBL[total_writes]}: $writes"
            disk_smart_add "total_writes" "$writes"
        fi

        if [[ -n "$pct_used" ]]; then
            echo "│   ${LBL[percentage_used]}: ${pct_used}%"
            echo "│   ${LBL[health_status]}: $((100 - pct_used))%"
            disk_smart_add "percentage_used" "$pct_used"
            disk_smart_add "health_status" "$((100 - pct_used))"
        fi

        if [[ -n "$spare" ]]; then
            echo "│   ${LBL[available_spare]}: ${spare}%"
            disk_smart_add "available_spare" "$spare"
        fi
    fi

    # Bad Blocks Detection (Text Parsing Fallback)
    detect_bad_blocks "text" "$smart_all"

    return 0
}

DISK_SUMMARY_SMART="-"
DISK_SUMMARY_HOURS="-"
DISK_SUMMARY_TEMP="-"
DISK_SUMMARY_IO="-"
DISK_SUMMARY_BAD="-"
DISK_SUMMARY_NOTE="-"

disk_summary_reset() {
    DISK_SUMMARY_SMART="-"
    DISK_SUMMARY_HOURS="-"
    DISK_SUMMARY_TEMP="-"
    DISK_SUMMARY_IO="-"
    DISK_SUMMARY_BAD="-"
    DISK_SUMMARY_NOTE="-"
}

disk_summary_is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

disk_summary_note_add() {
    local note="$1"
    [[ -z "$note" || "$note" == "-" ]] && return

    if [[ -z "$DISK_SUMMARY_NOTE" || "$DISK_SUMMARY_NOTE" == "-" ]]; then
        DISK_SUMMARY_NOTE="$note"
    else
        DISK_SUMMARY_NOTE+=", $note"
    fi
}

disk_summary_compact_transfer_value() {
    local __result_var="$1"
    local value="${2:-}"
    local compact="$value"
    local int="" frac="" unit="" frac_part=""

    value="${value//,/}"
    value="${value//[/}"
    value="${value//]/}"
    value="${value//(/}"
    value="${value//)/}"

    if [[ "$value" =~ ^[[:space:]]*([0-9]+)(\.([0-9]+))?[[:space:]]*([KMGTPE]i?B|[KMGTPE]B|bytes?|Bytes?) ]]; then
        int="${BASH_REMATCH[1]}"
        frac="${BASH_REMATCH[3]}"
        unit="${BASH_REMATCH[4]}"

        case "$unit" in
            KiB|KB) unit="K" ;;
            MiB|MB) unit="M" ;;
            GiB|GB) unit="G" ;;
            TiB|TB) unit="T" ;;
            PiB|PB) unit="P" ;;
            EiB|EB) unit="E" ;;
            *) unit="B" ;;
        esac

        if [[ "${#int}" -ge 2 ]]; then
            frac="${frac:0:1}"
        else
            frac="${frac:0:2}"
        fi

        if [[ -n "$frac" && ! "$frac" =~ ^0+$ ]]; then
            frac_part=".$frac"
        fi

        compact="${int}${frac_part}${unit}"
    else
        compact="${compact//,/}"
        compact="${compact// /}"
        compact="${compact//KiB/K}"
        compact="${compact//KB/K}"
        compact="${compact//MiB/M}"
        compact="${compact//MB/M}"
        compact="${compact//GiB/G}"
        compact="${compact//GB/G}"
        compact="${compact//TiB/T}"
        compact="${compact//TB/T}"
        compact="${compact//PiB/P}"
        compact="${compact//PB/P}"
        compact="${compact//EiB/E}"
        compact="${compact//EB/E}"
    fi

    printf -v "$__result_var" '%s' "$compact"
}

disk_summary_set_io() {
    local total_reads="${1:-}"
    local total_writes="${2:-}"
    local reads_short="" writes_short=""

    [[ -z "$total_reads" && -z "$total_writes" ]] && return

    disk_summary_compact_transfer_value reads_short "$total_reads"
    disk_summary_compact_transfer_value writes_short "$total_writes"

    if [[ "$LANG_MODE" == "cn" ]]; then
        DISK_SUMMARY_IO="读${reads_short:-?} 写${writes_short:-?}"
    else
        DISK_SUMMARY_IO="R${reads_short:-?} W${writes_short:-?}"
    fi
}

disk_summary_set_smart() {
    local status="$1"

    case "$status" in
        true|TRUE|True|PASSED|passed|Passed|OK|ok|Ok)
            DISK_SUMMARY_SMART="PASS"
            ;;
        false|FALSE|False|FAILED|failed|Failed|FAIL|fail|Fail)
            DISK_SUMMARY_SMART="FAIL"
            if [[ "$LANG_MODE" == "cn" ]]; then
                disk_summary_note_add "SMART失败"
            else
                disk_summary_note_add "SMART failed"
            fi
            ;;
        "")
            DISK_SUMMARY_SMART="-"
            ;;
        *)
            DISK_SUMMARY_SMART="$status"
            ;;
    esac
}

disk_summary_set_bad_metrics() {
    local grown_defects="$1"
    local read_uncorrected="$2"
    local write_uncorrected="$3"
    local verify_uncorrected="$4"
    local non_medium_errors="$5"
    local reallocated_sectors="$6"
    local pending_sectors="$7"
    local offline_uncorrectable="$8"
    local reported_uncorrect="$9"
    local has_ata_metrics=false
    local has_sas_metrics=false
    local total_bad=0
    local total_uncorrected=0

    disk_summary_is_uint "$reallocated_sectors" && has_ata_metrics=true
    disk_summary_is_uint "$pending_sectors" && has_ata_metrics=true
    disk_summary_is_uint "$offline_uncorrectable" && has_ata_metrics=true

    if [[ "$has_ata_metrics" == true ]]; then
        disk_summary_is_uint "$reallocated_sectors" || reallocated_sectors=0
        disk_summary_is_uint "$pending_sectors" || pending_sectors=0
        disk_summary_is_uint "$offline_uncorrectable" || offline_uncorrectable=0
        total_bad=$((reallocated_sectors + pending_sectors + offline_uncorrectable))
        DISK_SUMMARY_BAD="${reallocated_sectors}/${pending_sectors}/${offline_uncorrectable}"
        if [[ "$total_bad" -gt 0 ]]; then
            if [[ "$LANG_MODE" == "cn" ]]; then
                disk_summary_note_add "坏块=$total_bad"
            else
                disk_summary_note_add "bad sectors=$total_bad"
            fi
        fi
    fi

    disk_summary_is_uint "$read_uncorrected" && total_uncorrected=$((total_uncorrected + read_uncorrected))
    disk_summary_is_uint "$write_uncorrected" && total_uncorrected=$((total_uncorrected + write_uncorrected))
    disk_summary_is_uint "$verify_uncorrected" && total_uncorrected=$((total_uncorrected + verify_uncorrected))
    disk_summary_is_uint "$grown_defects" && has_sas_metrics=true
    [[ "$total_uncorrected" -gt 0 ]] && has_sas_metrics=true
    disk_summary_is_uint "$non_medium_errors" && [[ "$non_medium_errors" -gt 0 ]] && has_sas_metrics=true

    if [[ "$has_ata_metrics" == false && "$has_sas_metrics" == true ]]; then
        disk_summary_is_uint "$grown_defects" || grown_defects=0
        DISK_SUMMARY_BAD="GD:${grown_defects}/UE:${total_uncorrected}"
    fi

    if disk_summary_is_uint "$reported_uncorrect" && [[ "$reported_uncorrect" -gt 0 ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            disk_summary_note_add "报告不可纠正=$reported_uncorrect"
        else
            disk_summary_note_add "reported uncorrect=$reported_uncorrect"
        fi
    fi
    if disk_summary_is_uint "$grown_defects" && [[ "$grown_defects" -gt 0 ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            disk_summary_note_add "增长缺陷=$grown_defects"
        else
            disk_summary_note_add "grown defects=$grown_defects"
        fi
    fi
    if [[ "$total_uncorrected" -gt 0 ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            disk_summary_note_add "未校正=$total_uncorrected"
        else
            disk_summary_note_add "uncorrected=$total_uncorrected"
        fi
    fi
    if disk_summary_is_uint "$non_medium_errors" && [[ "$non_medium_errors" -gt 0 ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            disk_summary_note_add "非介质=$non_medium_errors"
        else
            disk_summary_note_add "non-medium=$non_medium_errors"
        fi
    fi
}

disk_summary_from_fields() {
    local disk="$1"
    disk_summary_reset

    if [[ "${#DISK_SMART_FIELDS[@]}" -eq 0 ]]; then
        if [[ $EUID -ne 0 ]]; then
            DISK_SUMMARY_NOTE="${LBL[needs_root]}"
        elif [[ "$LANG_MODE" == "cn" ]]; then
            DISK_SUMMARY_NOTE="无SMART信息"
        else
            DISK_SUMMARY_NOTE="no SMART info"
        fi
        return 0
    fi

    local smart_status="${DISK_SMART_FIELDS[smart_status]:-}"
    local power_on_hours="${DISK_SMART_FIELDS[power_on_hours]:-}"
    local temperature="${DISK_SMART_FIELDS[temperature]:-}"
    local total_reads="${DISK_SMART_FIELDS[total_reads]:-}"
    local total_writes="${DISK_SMART_FIELDS[total_writes]:-}"
    local percentage_used="${DISK_SMART_FIELDS[percentage_used]:-}"
    local available_spare="${DISK_SMART_FIELDS[available_spare]:-}"
    local critical_warning="${DISK_SMART_FIELDS[critical_warning]:-}"
    local wear_level="${DISK_SMART_FIELDS[wear_level]:-}"
    local grown_defects="${DISK_SMART_FIELDS[grown_defects]:-}"
    local read_uncorrected="${DISK_SMART_FIELDS[read_uncorrected_errors]:-}"
    local write_uncorrected="${DISK_SMART_FIELDS[write_uncorrected_errors]:-}"
    local verify_uncorrected="${DISK_SMART_FIELDS[verify_uncorrected_errors]:-}"
    local uncorrected_errors="${DISK_SMART_FIELDS[uncorrected_errors]:-}"
    local non_medium_errors="${DISK_SMART_FIELDS[non_medium_errors]:-}"
    local reallocated_sectors="${DISK_SMART_FIELDS[reallocated_sectors]:-}"
    local pending_sectors="${DISK_SMART_FIELDS[pending_sectors]:-}"
    local offline_uncorrectable="${DISK_SMART_FIELDS[offline_uncorrectable]:-}"
    local reported_uncorrect="${DISK_SMART_FIELDS[reported_uncorrect]:-}"

    if [[ -z "$read_uncorrected" && -z "$write_uncorrected" && -z "$verify_uncorrected" ]]; then
        read_uncorrected="$uncorrected_errors"
    fi

    disk_summary_set_smart "$smart_status"
    [[ -n "$power_on_hours" ]] && DISK_SUMMARY_HOURS="${power_on_hours}h"
    [[ -n "$temperature" ]] && DISK_SUMMARY_TEMP="$temperature"
    local temp_num="${temperature%%°*}"
    if disk_summary_is_uint "$temp_num" && [[ "$temp_num" -ge 55 ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            disk_summary_note_add "高温"
        else
            disk_summary_note_add "hot"
        fi
    fi

    if [[ -n "$percentage_used" ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            disk_summary_note_add "已用${percentage_used}%"
        else
            disk_summary_note_add "used ${percentage_used}%"
        fi
    fi
    if [[ -n "$available_spare" ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            disk_summary_note_add "备用${available_spare}%"
        else
            disk_summary_note_add "spare ${available_spare}%"
        fi
    fi
    if disk_summary_is_uint "$critical_warning" && [[ "$critical_warning" -gt 0 ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            disk_summary_note_add "严重告警=$critical_warning"
        else
            disk_summary_note_add "critical=$critical_warning"
        fi
    fi
    if [[ -n "$wear_level" ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            disk_summary_note_add "寿命${wear_level}%"
        else
            disk_summary_note_add "wear ${wear_level}%"
        fi
    fi
    disk_summary_set_io "$total_reads" "$total_writes"

    disk_summary_set_bad_metrics \
        "$grown_defects" "$read_uncorrected" "$write_uncorrected" "$verify_uncorrected" \
        "$non_medium_errors" "$reallocated_sectors" "$pending_sectors" \
        "$offline_uncorrectable" "$reported_uncorrect"

    if [[ "$DISK_SUMMARY_IO" == "-" && ! "$disk" =~ nvme ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            DISK_SUMMARY_IO="无统计"
        else
            DISK_SUMMARY_IO="no stats"
        fi
    fi

    return 0
}

print_disk_summary_header() {
    local w_device=12 w_basic=34 w_smart=6 w_hours=8 w_temp=6 w_io=20 w_bad=9 w_note=20
    local table_width=$((w_device + w_basic + w_smart + w_hours + w_temp + w_io + w_bad + w_note + 23))
    local rule=""
    repeat_char_to rule '─' "$table_width"

    if [[ "$LANG_MODE" == "cn" ]]; then
        print_color "$WHITE" "│ 磁盘摘要（坏块=重映射/待处理/离线不可纠正）"
        echo "├${rule}┤"
        printf "│ "
        print_fixed_cell "设备" "$w_device"; printf " │ "
        print_fixed_cell "基本信息" "$w_basic"; printf " │ "
        print_fixed_cell "SMART" "$w_smart"; printf " │ "
        print_fixed_cell "通电" "$w_hours"; printf " │ "
        print_fixed_cell "温度" "$w_temp"; printf " │ "
        print_fixed_cell "读写" "$w_io"; printf " │ "
        print_fixed_cell "坏块" "$w_bad"; printf " │ "
        print_fixed_cell "备注" "$w_note"; printf " │\n"
        echo "├${rule}┤"
    else
        print_color "$WHITE" "│ Disk Summary (defects=reallocated/pending/offline)"
        echo "├${rule}┤"
        printf "│ "
        print_fixed_cell "Device" "$w_device"; printf " │ "
        print_fixed_cell "Basic Info" "$w_basic"; printf " │ "
        print_fixed_cell "SMART" "$w_smart"; printf " │ "
        print_fixed_cell "Hours" "$w_hours"; printf " │ "
        print_fixed_cell "Temp" "$w_temp"; printf " │ "
        print_fixed_cell "I/O" "$w_io"; printf " │ "
        print_fixed_cell "Defects" "$w_bad"; printf " │ "
        print_fixed_cell "Notes" "$w_note"; printf " │\n"
        echo "├${rule}┤"
    fi
}

print_disk_summary_footer() {
    local w_device=12 w_basic=34 w_smart=6 w_hours=8 w_temp=6 w_io=20 w_bad=9 w_note=20
    local table_width=$((w_device + w_basic + w_smart + w_hours + w_temp + w_io + w_bad + w_note + 23))
    local rule=""
    repeat_char_to rule '─' "$table_width"
    echo "└${rule}┘"
}

# Summary-cell colors. Each sets DISK_SUMMARY_COLOR (no subshell per cell).
DISK_SUMMARY_COLOR=""

disk_summary_smart_color() {
    case "$DISK_SUMMARY_SMART" in
        PASS|PASSED|OK)
            DISK_SUMMARY_COLOR="$GREEN"
            ;;
        FAIL|FAILED)
            DISK_SUMMARY_COLOR="$RED"
            ;;
        *)
            DISK_SUMMARY_COLOR="$YELLOW"
            ;;
    esac
}

disk_summary_temp_color() {
    local temp="${DISK_SUMMARY_TEMP%%°*}"
    temp="${temp#+}"
    DISK_SUMMARY_COLOR=""

    if ! disk_summary_is_uint "$temp"; then
        return
    fi

    if [[ "$temp" -ge 60 ]]; then
        DISK_SUMMARY_COLOR="$RED"
    elif [[ "$temp" -ge 50 ]]; then
        DISK_SUMMARY_COLOR="$YELLOW"
    else
        DISK_SUMMARY_COLOR="$GREEN"
    fi
}

disk_summary_bad_color() {
    local bad="$DISK_SUMMARY_BAD"
    DISK_SUMMARY_COLOR=""

    [[ -z "$bad" || "$bad" == "-" ]] && return

    if [[ "$bad" =~ (^|[^0-9])[1-9][0-9]* ]]; then
        DISK_SUMMARY_COLOR="$RED"
    else
        DISK_SUMMARY_COLOR="$GREEN"
    fi
}

disk_summary_io_color() {
    local io="$DISK_SUMMARY_IO"
    DISK_SUMMARY_COLOR=""

    [[ -z "$io" || "$io" == "-" ]] && return

    if [[ "$io" =~ 无统计|no\ stats|no\ I/O ]]; then
        DISK_SUMMARY_COLOR="$YELLOW"
    else
        DISK_SUMMARY_COLOR="$CYAN"
    fi
}

disk_summary_note_color() {
    local note="$DISK_SUMMARY_NOTE"
    DISK_SUMMARY_COLOR=""

    [[ -z "$note" || "$note" == "-" ]] && return

    if [[ "$note" =~ 失败|坏块|高温|严重|不可纠正|未校正|failed|bad|hot|critical|uncorrect|defect ]]; then
        DISK_SUMMARY_COLOR="$RED"
    elif [[ "$note" =~ 无SMART|无读写统计|smartctl|root|no\ SMART|no\ I/O|missing ]]; then
        DISK_SUMMARY_COLOR="$YELLOW"
    else
        DISK_SUMMARY_COLOR="$CYAN"
    fi
}

print_disk_summary_row() {
    local label="$1"
    local basic_info="$2"
    local w_device=12 w_basic=34 w_smart=6 w_hours=8 w_temp=6 w_io=20 w_bad=9 w_note=20

    printf "│ "
    print_colored_fixed_cell "$label" "$w_device" "$CYAN"; printf " │ "
    print_fixed_cell "$basic_info" "$w_basic"; printf " │ "
    disk_summary_smart_color
    print_colored_fixed_cell "$DISK_SUMMARY_SMART" "$w_smart" "$DISK_SUMMARY_COLOR"; printf " │ "
    print_fixed_cell "$DISK_SUMMARY_HOURS" "$w_hours"; printf " │ "
    disk_summary_temp_color
    print_colored_fixed_cell "$DISK_SUMMARY_TEMP" "$w_temp" "$DISK_SUMMARY_COLOR"; printf " │ "
    disk_summary_io_color
    print_colored_fixed_cell "$DISK_SUMMARY_IO" "$w_io" "$DISK_SUMMARY_COLOR"; printf " │ "
    disk_summary_bad_color
    print_colored_fixed_cell "$DISK_SUMMARY_BAD" "$w_bad" "$DISK_SUMMARY_COLOR"; printf " │ "
    disk_summary_note_color
    print_colored_fixed_cell "$DISK_SUMMARY_NOTE" "$w_note" "$DISK_SUMMARY_COLOR"; printf " │\n"
}

# Function to get disk information with enhanced SMART data
# Display structure:
#   1. Mounted filesystems
#   2. One summary table: direct disks (sd/vd/xvd/hd, NVMe, mmc) first, then
#      RAID controller member disks not already visible as a direct device
get_disk_info() {
    print_subsection "${LBL[disk_info]}"

    JSON_DISKS=()

    # Filesystem usage table (mounted /dev/* filesystems)
    local -a fs_rows=()
    local fsep=$'\034'
    local fs sz used avail usep mnt rest
    # Read-only mounts (ISO, squashfs, snaps) are always 100% used: not a problem
    local -A ro_mounts=()
    local m_dir="" m_opts=""
    while read -r _ m_dir _ m_opts _; do
        [[ ",$m_opts," == *,ro,* ]] && ro_mounts[$m_dir]=1
    done < /proc/mounts
    while read -r fs sz used avail usep mnt rest; do
        [[ "$fs" == /dev/* ]] || continue
        fs_rows+=("${fs}${fsep}${sz}${fsep}${used}${fsep}${avail}${fsep}${usep}${fsep}${mnt}")
        # Health: nearly full (writable) filesystems
        local hp="${usep%\%}"
        [[ "$hp" =~ ^[0-9]+$ && -z "${ro_mounts[$mnt]:-}" ]] || continue
        if (( hp >= 98 )); then
            health_add fail "$mnt" fs "${hp}% used" "已用 ${hp}%"
        elif (( hp >= 90 )); then
            health_add warn "$mnt" fs "${hp}% used" "已用 ${hp}%"
        fi
    done < <(run_limited 10 df -hP 2>/dev/null)

    if [[ ${#fs_rows[@]} -gt 0 ]]; then
        [[ "$LANG_MODE" == "cn" ]] && print_color "$CYAN" "│ 已挂载文件系统:" || print_color "$CYAN" "│ Mounted Filesystems:"
        TABLE_COL_W=(34 7 7 7 6 20)
        if [[ "$LANG_MODE" == "cn" ]]; then
            table_header "文件系统" "容量" "已用" "可用" "使用率" "挂载点"
        else
            table_header "Filesystem" "Size" "Used" "Avail" "Use%" "Mounted"
        fi
        local r=""
        for r in "${fs_rows[@]}"; do
            IFS="$fsep" read -r fs sz used avail usep mnt <<< "$r"
            local upn="${usep%\%}" ucolor="$GREEN"
            if [[ "$upn" =~ ^[0-9]+$ ]]; then
                if (( upn >= 90 )); then ucolor="$RED"
                elif (( upn >= 75 )); then ucolor="$YELLOW"; fi
            fi
            table_row "$fs" "$CYAN" "$sz" "" "$used" "" "$avail" "" "$usep" "$ucolor" "$mnt" ""
        done
        table_close
        echo "│"
    fi

    # Check smartctl version for JSON support (7.0+)
    local smartctl_available=false
    local use_json=false
    if command -v smartctl >/dev/null 2>&1; then
        smartctl_available=true
        smartctl_supports_json && use_json=true
    fi

    # Disk names + basic info (one lsblk call, BMC virtual media filtered);
    # SMART data was usually prefetched in the background already.
    enumerate_disks

    local no_smart_note="no SMART info"
    [[ "$LANG_MODE" == "cn" ]] && no_smart_note="无SMART信息"
    # Unprivileged smartctl always fails: say so instead of "no SMART info".
    if [[ $EUID -ne 0 ]]; then
        no_smart_note="${LBL[needs_root]}"
    fi

    # ==========================================================================
    # Unified disk summary table
    # Direct disks (sd*/nvme/mmc) plus RAID controller member disks that are not
    # already visible as a direct device. De-duplicated by serial so the same
    # physical drive (e.g. HBA passthrough visible both as /dev/sdX and
    # megaraid,N) is listed exactly once. RAID controller identity itself lives
    # in the "RAID Controller Information" section.
    # ==========================================================================
    local -A seen_serials=()
    local disk_summary_table_started=false
    local disk=""

    # ---- Direct disks first (they carry I/O stats) ----
    for disk in "${DISK_NAMES[@]}"; do
        [[ "$disk" =~ $DISK_NAME_REGEX ]] || continue
        local disk_info="${DISK_BASIC_INFO_CACHE[$disk]}"
        DISK_JSON_EXTRA=(); disk_smart_reset; disk_summary_reset
        local parsed=false json_data=""
        SJ=()

        if [[ "$smartctl_available" == true ]]; then
            if [[ "$use_json" == true ]]; then
                get_smart_json "$disk"; json_data="$SMART_JSON_RESULT"
                # Brace group (not a subshell) so DISK_SMART_FIELDS / SJ survive
                [[ -n "$json_data" ]] && { parse_smart_json "$disk" "$json_data"; } >/dev/null && parsed=true
            fi
            [[ "$parsed" == false ]] && { parse_smart_text "$disk"; } >/dev/null && parsed=true
            if [[ "$parsed" == true ]]; then
                disk_summary_from_fields "$disk"
            else
                DISK_SUMMARY_SMART="-"
                DISK_SUMMARY_NOTE="$no_smart_note"
            fi
        else
            [[ "$LANG_MODE" == "cn" ]] && DISK_SUMMARY_NOTE="smartctl未安装" || DISK_SUMMARY_NOTE="smartctl missing"
        fi

        if [[ "$disk" =~ ^nvme ]]; then
            health_check_disk "$disk" true
        else
            health_check_disk "$disk" false
        fi

        local dserial="${SJ[serial_number]:-}"
        [[ -n "$dserial" ]] && seen_serials["$dserial"]=1
        if [[ "$COLLECT_JSON" == true && -n "$json_data" ]]; then
            disk_extra_add "model" "${SJ[model_name]:-${SJ[scsi_vendor]:+${SJ[scsi_vendor]} }${SJ[scsi_product]:-}}" s
            disk_extra_add "serial" "$dserial" s
            disk_extra_add "firmware" "${SJ[firmware]:-}" s
            [[ -n "${SJ[capacity_bytes]:-}" ]] && disk_extra_add "capacity_bytes" "${SJ[capacity_bytes]}"
        fi

        if [[ "$disk_summary_table_started" != true ]]; then
            print_disk_summary_header
            disk_summary_table_started=true
        fi
        print_disk_summary_row "/dev/$disk" "$disk_info"
        disk_json_add "other" "/dev/$disk" "$disk_info"
    done

    # ---- RAID controller member disks not already shown above ----
    if [[ "$smartctl_available" == true ]]; then
        get_raid_member_devices
        local raid_devs="$RAID_MEMBER_RESULT"
        local member_entry=""
        while IFS= read -r member_entry; do
            [[ -z "$member_entry" ]] && continue
            local device="" raid_type="" raid_id=""
            IFS=: read -r device raid_type raid_id <<< "$member_entry"

            get_smart_json_raid "$device" "$raid_type" "$raid_id"
            local json_data="$SMART_JSON_RAID_RESULT"
            local mserial="" mbasic="-"
            SJ=()
            [[ -n "$json_data" ]] && smart_json_load "$json_data"
            mserial="${SJ[serial_number]:-}"
            # Skip if this physical drive is already listed as a direct disk
            [[ -n "$mserial" && -n "${seen_serials[$mserial]:-}" ]] && continue

            DISK_JSON_EXTRA=(); disk_smart_reset; disk_summary_reset
            disk_extra_add "raid_type" "$raid_type"
            disk_extra_add "raid_id" "$raid_id"
            disk_extra_add "controller_device" "$device" s

            if [[ -n "$json_data" ]]; then
                # parse_smart_json_sas prints detail lines; capture them to /dev/null
                # (brace group keeps DISK_SMART_FIELDS in the current shell).
                { parse_smart_json_sas "$json_data" --loaded; } >/dev/null
                disk_summary_from_fields "member"
                health_check_disk "${raid_type},${raid_id}" false
                local mmodel="${SJ[model_name]:-}"
                if [[ -z "$mmodel" ]]; then
                    mmodel="${SJ[scsi_vendor]:-} ${SJ[scsi_product]:-}"
                fi
                mbasic="${mmodel# }"
                mbasic="${mbasic% }"
                [[ -z "$mbasic" ]] && mbasic="-"
            else
                DISK_SUMMARY_NOTE="$no_smart_note"
            fi
            [[ -n "$mserial" ]] && seen_serials["$mserial"]=1

            if [[ "$disk_summary_table_started" != true ]]; then
                print_disk_summary_header
                disk_summary_table_started=true
            fi
            print_disk_summary_row "${raid_type},${raid_id}" "$mbasic"
            disk_json_add "raid_member" "$device" "$mbasic"
        done <<< "$raid_devs"
    fi

    if [[ "$disk_summary_table_started" == true ]]; then
        print_disk_summary_footer
    else
        print_info "${LBL[status]}" "${LBL[not_detected]}"
    fi
    section_end
}

# Function to get RAID information
get_raid_info() {
    print_subsection "${LBL[raid_info]}"

    local raid_found=false
    JSON_RAID_SW=()
    JSON_RAID_HW=()
    JSON_RAID_TOOLS=()
    local sep=$'\034'   # non-whitespace: IFS=$'\t' would merge empty fields

    # ---- Software RAID (mdraid) ----
    # /proc/mdstat: the "mdN : state level members" line, then a status line
    # ("... [2/1] [U_]") and optional resync/recovery lines. Health comes from
    # the [total/active] counts and (F) failed members, which only appear on
    # those following lines / member tokens - not from the first line's words.
    if [[ -r /proc/mdstat ]]; then
        local -a sw_rows=()
        local -a sw_warns=()
        local -a md_names=()
        local -A md_level_of=() md_status_of=() md_members_of=() md_failed_of=() md_total_of=() md_active_of=() md_sync_of=()
        local line="" cur="" tok="" lvl=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^(md[0-9]+|md_[^[:space:]]+)[[:space:]]+:[[:space:]]+(.*)$ ]]; then
                cur="${BASH_REMATCH[1]}"
                md_names+=("$cur")
                JSON_RAID_SW+=("$line")
                local -a toks=()
                read -r -a toks <<< "${BASH_REMATCH[2]}"
                md_status_of[$cur]="${toks[0]:-}"
                lvl="-"
                local mcount=0 fcount=0
                for tok in "${toks[@]:1}"; do
                    case "$tok" in
                        \(*\)) continue ;;                      # (auto-read-only), (read-only)
                        raid*|linear|multipath|faulty|container) lvl="$tok" ;;
                        *\[[0-9]*\]*)
                            ((mcount++))
                            [[ "$tok" == *"(F)"* ]] && ((fcount++))
                            ;;
                    esac
                done
                md_level_of[$cur]="$lvl"
                md_members_of[$cur]="$mcount"
                md_failed_of[$cur]="$fcount"
                continue
            fi
            [[ -z "$cur" ]] && continue
            if [[ "$line" =~ \[([0-9]+)/([0-9]+)\] ]]; then
                md_total_of[$cur]="${BASH_REMATCH[1]}"
                md_active_of[$cur]="${BASH_REMATCH[2]}"
            fi
            if [[ "$line" =~ (resync|recovery|reshape|check)[[:space:]]*=[[:space:]]*([0-9.]+%) ]]; then
                md_sync_of[$cur]="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
            elif [[ "$line" =~ (resync|recovery)=(DELAYED|PENDING) ]]; then
                md_sync_of[$cur]="${BASH_REMATCH[1]} ${BASH_REMATCH[2],,}"
            fi
            [[ -z "$line" ]] && cur=""
        done < /proc/mdstat

        local md_name=""
        for md_name in "${md_names[@]}"; do
            local raid_state="OK" raid_color="$GREEN"
            local md_status="${md_status_of[$md_name]}" md_level="${md_level_of[$md_name]}"
            local total="${md_total_of[$md_name]:-}" active="${md_active_of[$md_name]:-}"
            local member_disp="${md_members_of[$md_name]}"
            [[ -n "$total" && -n "$active" ]] && member_disp="${active}/${total}"
            # Only degraded/failed arrays are unhealthy. raid0 is healthy when
            # active - it just has no redundancy (noted separately below).
            if [[ "$md_status" == "inactive" || "${md_failed_of[$md_name]}" -gt 0 ]] ||
               [[ -n "$total" && -n "$active" && "$active" -lt "$total" ]]; then
                raid_state="FAIL"; raid_color="$RED"
                if [[ "$md_status" == "inactive" ]]; then
                    if [[ "$LANG_MODE" == "cn" ]]; then
                        sw_warns+=("${md_name}${sep}阵列未激活（未组装/成员缺失）")
                    else
                        sw_warns+=("${md_name}${sep}array inactive (not assembled / members missing)")
                    fi
                elif [[ "$LANG_MODE" == "cn" ]]; then
                    sw_warns+=("${md_name}${sep}阵列降级/失效：在线成员 ${active:-?}/${total:-?}，故障 ${md_failed_of[$md_name]} 个")
                else
                    sw_warns+=("${md_name}${sep}degraded/failed: ${active:-?}/${total:-?} members active, ${md_failed_of[$md_name]} failed")
                fi
            fi
            if [[ "$raid_state" == "FAIL" ]]; then
                if [[ "$md_status" == "inactive" ]]; then
                    health_add fail "$md_name" raid "array inactive" "阵列未激活"
                else
                    local hfail="${md_failed_of[$md_name]}" h_en="" h_cn=""
                    h_en="degraded: ${active:-?}/${total:-?} members active"
                    h_cn="降级：在线成员 ${active:-?}/${total:-?}"
                    if [[ "$hfail" -gt 0 ]]; then h_en+=", $hfail failed"; h_cn+="，故障 $hfail"; fi
                    health_add fail "$md_name" raid "$h_en" "$h_cn"
                fi
            fi
            if [[ -n "${md_sync_of[$md_name]:-}" ]]; then
                [[ "$raid_state" == "OK" ]] && { raid_state="SYNC"; raid_color="$YELLOW"; }
                md_status+=" (${md_sync_of[$md_name]})"
                health_add warn "$md_name" raid_sync "${md_sync_of[$md_name]}" "同步中 ${md_sync_of[$md_name]}"
            fi
            sw_rows+=("${md_name}${sep}${md_level}${sep}${md_status}${sep}${member_disp}${sep}${raid_state}${sep}${raid_color}")
            if [[ "$md_level" == "raid0" ]]; then
                if [[ "$LANG_MODE" == "cn" ]]; then
                    sw_warns+=("${md_name}${sep}raid0 无冗余，任一成员故障将导致阵列失效")
                else
                    sw_warns+=("${md_name}${sep}raid0 has no redundancy; any member failure breaks the array")
                fi
            fi
        done

        if [[ ${#sw_rows[@]} -gt 0 ]]; then
            [[ "$LANG_MODE" == "cn" ]] && print_color "$CYAN" "│ 软件 RAID (mdraid):" || print_color "$CYAN" "│ Software RAID (mdraid):"
            TABLE_COL_W=(8 10 26 9 6)   # State fits "active (recovery 100.0%)"
            if [[ "$LANG_MODE" == "cn" ]]; then
                table_header "阵列" "级别" "状态" "成员数" "健康"
            else
                table_header "Array" "Level" "State" "Members" "Health"
            fi
            local r="" a="" l="" s="" m="" hs="" hc=""
            for r in "${sw_rows[@]}"; do
                IFS="$sep" read -r a l s m hs hc <<< "$r"
                table_row "$a" "$CYAN" "$l" "" "$s" "" "$m" "" "$hs" "$hc"
            done
            table_close
            local wln="" ww_name="" ww_detail=""
            for wln in "${sw_warns[@]}"; do
                IFS="$sep" read -r ww_name ww_detail <<< "$wln"
                print_note "$ww_name" "$ww_detail"
            done
            raid_found=true
        fi
    fi

    if command -v mdadm >/dev/null 2>&1; then
        local mdadm_scan=""
        mdadm_scan=$(run_limited 5 mdadm --detail --scan 2>/dev/null || true)
        if [[ -n "$mdadm_scan" ]]; then
            local mdadm_count=0 line=""
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                ((mdadm_count++))
                JSON_RAID_SW+=("mdadm: $line")
            done <<< "$mdadm_scan"
            print_info "${LBL[mdadm_arrays]}" "$mdadm_count ${LBL[details_in_json]}"
            raid_found=true
        fi
    fi

    # ---- Hardware RAID / HBA / storage controllers (PCI) ----
    get_lspci_output
    if [[ -n "$LSPCI_RESULT" ]]; then
        local raid_controllers
        raid_controllers=$(printf '%s\n' "$LSPCI_RESULT" | grep -Ei 'RAID|Serial Attached SCSI|SAS|SATA controller|SCSI storage controller|Non-Volatile memory controller')
        if [[ -n "$raid_controllers" ]]; then
            local -a hw_rows=()
            local line=""
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                JSON_RAID_HW+=("$line")
                local slot="${line%% *}"
                local rest="${line#* }"
                local ctype="Storage"
                case "$rest" in
                    *RAID*) ctype="RAID" ;;
                    *"Serial Attached SCSI"*|*SAS*) ctype="SAS/HBA" ;;
                    *"Non-Volatile memory"*) ctype="NVMe" ;;
                    *"SATA controller"*) ctype="SATA" ;;
                    *"SCSI storage"*) ctype="SCSI" ;;
                esac
                # Only surface real RAID/HBA/SAS controllers in the table; plain
                # onboard SATA/NVMe are already covered by the disk section.
                case "$ctype" in
                    RAID|SAS/HBA|SCSI) ;;
                    *) continue ;;
                esac
                local cname=""
                compact_pci_name cname "${rest#*: }"
                hw_rows+=("${slot}${sep}${ctype}${sep}${cname}")
            done <<< "$raid_controllers"

            if [[ ${#hw_rows[@]} -gt 0 ]]; then
                [[ "$LANG_MODE" == "cn" ]] && print_color "$CYAN" "│ RAID/HBA 控制器:" || print_color "$CYAN" "│ RAID/HBA Controllers:"
                TABLE_COL_W=(10 9 48)
                if [[ "$LANG_MODE" == "cn" ]]; then
                    table_header "插槽" "类型" "控制器"
                else
                    table_header "Slot" "Type" "Controller"
                fi
                local r="" sl="" ty="" nm=""
                for r in "${hw_rows[@]}"; do
                    IFS="$sep" read -r sl ty nm <<< "$r"
                    table_row "$sl" "$CYAN" "$ty" "$YELLOW" "$nm" ""
                done
                table_close
                raid_found=true
            fi
        fi
    fi

    # ---- Vendor RAID CLI tools (presence only; no giant raw dumps) ----
    local -a tool_rows=()
    local tool="" tool_path=""
    for tool in storcli storcli64 perccli perccli64 ssacli hpssacli arcconf; do
        tool_path=$(command -v "$tool" 2>/dev/null || true)
        [[ -n "$tool_path" ]] || continue
        tool_rows+=("${tool}${sep}${tool_path}")
        [[ "$COLLECT_JSON" == true ]] && JSON_RAID_TOOLS+=("$(json_obj "$(json_kv "tool" "$tool")" "$(json_kv_s "path" "$tool_path")")")
    done
    if [[ ${#tool_rows[@]} -gt 0 ]]; then
        [[ "$LANG_MODE" == "cn" ]] && print_color "$CYAN" "│ 已安装的 RAID 工具:" || print_color "$CYAN" "│ Installed RAID Tools:"
        TABLE_COL_W=(12 52)
        if [[ "$LANG_MODE" == "cn" ]]; then
            table_header "工具" "路径"
        else
            table_header "Tool" "Path"
        fi
        local r="" tn="" tp=""
        for r in "${tool_rows[@]}"; do
            IFS="$sep" read -r tn tp <<< "$r"
            table_row "$tn" "$CYAN" "$tp" ""
        done
        table_close
        [[ "$LANG_MODE" == "cn" ]] && echo "│   提示: 运行对应工具查看阵列详情（如 storcli /call show）" \
            || echo "│   Tip: run the tool for array detail (e.g. storcli /call show)"
        raid_found=true
    fi

    if [[ "$raid_found" == false ]]; then
        print_info "${LBL[status]}" "${LBL[not_detected]}"
    fi

    section_end
}

# Function to mask IP addresses for privacy
mask_ip_address() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        echo ""
        return
    fi
    
    # Handle IPv4 addresses (e.g., 192.168.1.100/24 -> 192.168.XX.XX/24)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        # Extract the network part (CIDR notation)
        local ip_part="${ip%/*}"
        local cidr_part=""
        if [[ "$ip" =~ / ]]; then
            cidr_part="/${ip#*/}"
        fi
        
        # Split IP into octets
        local -a octets=()
        IFS='.' read -ra octets <<< "$ip_part"
        if [[ ${#octets[@]} -eq 4 ]]; then
            echo "${octets[0]}.${octets[1]}.XX.XX${cidr_part}"
        else
            echo "$ip"
        fi
    # Handle IPv6 addresses (e.g., 2001:41d0:727:3000:: -> 2001:41d0:XX:XX::)
    elif [[ "$ip" =~ : ]]; then
        # Extract the network part (CIDR notation)
        local ip_part="${ip%/*}"
        local cidr_part=""
        if [[ "$ip" =~ / ]]; then
            cidr_part="/${ip#*/}"
        fi
        
        # Split IPv6 into segments
        local -a segments=()
        IFS=':' read -ra segments <<< "$ip_part"
        if [[ ${#segments[@]} -ge 2 && -z "${segments[1]}" ]]; then
            # "fe80::1234" style: only the first group precedes "::"
            echo "${segments[0]}::XX:XX${cidr_part}"
        elif [[ ${#segments[@]} -ge 2 ]]; then
            # Show first two segments, mask the rest
            local result="${segments[0]}:${segments[1]}:XX:XX"
            # Add :: if the original had it
            if [[ "$ip_part" =~ :: ]]; then
                result="${result}::"
            fi
            echo "${result}${cidr_part}"
        else
            echo "$ip"
        fi
    else
        # Unknown format, return as-is
        echo "$ip"
    fi
}

# Function to mask MAC addresses for privacy
mask_mac_address() {
    local mac="$1"
    
    if [[ -z "$mac" ]]; then
        echo ""
        return
    fi
    
    # Handle standard MAC address format (aa:bb:cc:dd:ee:ff or AA:BB:CC:DD:EE:FF)
    if [[ "$mac" =~ ^([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})$ ]]; then
        # Show first 3 octets (OUI - Organizationally Unique Identifier), mask last 3
        # Format: aa:bb:cc:XX:XX:XX
        echo "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:XX:XX:XX"
    # Handle MAC address with dashes (aa-bb-cc-dd-ee-ff)
    elif [[ "$mac" =~ ^([0-9a-fA-F]{2})-([0-9a-fA-F]{2})-([0-9a-fA-F]{2})-([0-9a-fA-F]{2})-([0-9a-fA-F]{2})-([0-9a-fA-F]{2})$ ]]; then
        # Show first 3 octets, mask last 3
        # Format: aa-bb-cc-XX-XX-XX
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}-XX-XX-XX"
    # Handle MAC address without separators (aabbccddee​ff)
    elif [[ "$mac" =~ ^([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$ ]]; then
        # Show first 3 octets, mask last 3
        # Format: aabbccXXXXXX
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}XXXXXX"
    # Handle MAC address with dots (aaaa.bbbb.cccc)
    elif [[ "$mac" =~ ^([0-9a-fA-F]{4})\.([0-9a-fA-F]{4})\.([0-9a-fA-F]{4})$ ]]; then
        # Show first 6 characters (3 octets), mask last 6
        # Format: aaaa.bbXX.XXXX
        local first_part="${BASH_REMATCH[1]}"
        local second_part="${BASH_REMATCH[2]}"
        echo "${first_part}.${second_part:0:2}XX.XXXX"
    else
        # Unknown MAC format, try to mask generically if it looks like a MAC
        if [[ ${#mac} -ge 12 ]] && [[ "$mac" =~ [0-9a-fA-F] ]]; then
            # Generic masking: show first half, mask second half
            local len=${#mac}
            local half=$((len/2))
            local first_half="${mac:0:$half}"
            local masked_half=""
            masked_half=$(repeat_char 'X' $((len-half)))
            echo "${first_half}${masked_half}"
        else
            # Return as-is if it doesn't look like a MAC address
            echo "$mac"
        fi
    fi
}

# Function to check if interface is a physical network card
is_physical_interface() {
    local interface="$1"
    
    # Skip virtual/software interfaces
    case "$interface" in
        lo|lo:*)            return 1 ;;  # Loopback
        docker*)            return 1 ;;  # Docker interfaces
        br-*)               return 1 ;;  # Docker bridges
        veth*)              return 1 ;;  # Virtual ethernet pairs (Docker containers)
        virbr*)             return 1 ;;  # libvirt bridges
        tun*|tap*)          return 1 ;;  # VPN tunnels
        wg*)                return 1 ;;  # WireGuard VPN
        vlan*)              return 1 ;;  # VLAN interfaces
        bond*)              return 1 ;;  # Bonding interfaces (usually virtual)
        team*)              return 1 ;;  # Team interfaces
        dummy*)             return 1 ;;  # Dummy interfaces
        sit*)               return 1 ;;  # IPv6 in IPv4 tunnels
        gre*)               return 1 ;;  # GRE tunnels
        ipip*)              return 1 ;;  # IP in IP tunnels
        *@*)                return 1 ;;  # Interface pairs (e.g., veth123@if456)
    esac
    
    # Accept physical interfaces (including InfiniBand)
    case "$interface" in
        eth*)               return 0 ;;  # Traditional ethernet naming
        ens*|enp*|eno*)     return 0 ;;  # systemd predictable naming
        ib*)                return 0 ;;  # InfiniBand cards (user requested)
        wlan*|wlp*)         return 0 ;;  # Wireless cards
        em*|p*p*)           return 0 ;;  # Additional physical interface patterns
    esac
    
    # For unknown patterns, check if it has a physical device path
    local device_path="/sys/class/net/$interface/device"
    if [[ -L "$device_path" ]]; then
        # Has a device symlink, likely physical
        return 0
    fi
    
    # Default: assume virtual if pattern doesn't match known physical types
    return 1
}

# Function to get enhanced network information
get_network_info() {
    print_subsection "${LBL[network_info]}"

    JSON_NETWORK=()

    local -a interfaces=()
    declare -A iface_status
    declare -A iface_ipv4
    declare -A iface_ipv6
    declare -A iface_mac

    local line=""
    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local tmp="${line#*: }"
            local ifname="${tmp%%:*}"
            # "eth0@if7" (container veth peer) / "eth0.100@eth0" (VLAN): the
            # kernel name is the part before "@".
            ifname="${ifname%%@*}"
            local state="Unknown"
            local mac=""
            local parts=()

            interfaces+=("$ifname")
            read -r -a parts <<< "$line"
            local idx=0
            while (( idx < ${#parts[@]} )); do
                case "${parts[$idx]}" in
                    state) state="${parts[$((idx + 1))]}" ;;
                    link/ether) mac="${parts[$((idx + 1))]}" ;;
                esac
                ((idx++))
            done
            iface_status[$ifname]="$state"
            [[ -n "$mac" ]] && iface_mac[$ifname]="$mac"
        done < <(ip -o link show 2>/dev/null)

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local parts=()
            read -r -a parts <<< "$line"
            local ifname="${parts[1]%%@*}"
            local family="${parts[2]}"
            local addr="${parts[3]}"
            if [[ "$family" == "inet" ]]; then
                [[ -z "${iface_ipv4[$ifname]:-}" ]] && iface_ipv4[$ifname]="$addr"
            elif [[ "$family" == "inet6" ]]; then
                # Prefer a global address over the fe80:: link-local one
                if [[ -z "${iface_ipv6[$ifname]:-}" ]] ||
                   [[ "${iface_ipv6[$ifname]}" == fe80:* && "$addr" != fe80:* ]]; then
                    iface_ipv6[$ifname]="$addr"
                fi
            fi
        done < <(ip -o addr show 2>/dev/null)
    fi

    if [[ ${#interfaces[@]} -eq 0 ]]; then
        local path=""
        for path in /sys/class/net/*; do
            [[ ! -e "$path" ]] && break
            interfaces+=("${path##*/}")
        done
    fi

    local -a net_rows=()        # iface\tstatuscolor\tstatus\tlink\tmac\tipv4\tmodel
    local -a net_warns=()
    local sep=$'\034'   # non-whitespace: IFS=$'\t' would merge empty fields
    local printed_interfaces=0

    local interface
    for interface in "${interfaces[@]}"; do
        is_physical_interface "$interface" || continue
        ((printed_interfaces++))

        local pci_path="" device_path="/sys/class/net/$interface/device" link_target=""
        if [[ -L "$device_path" ]]; then
            # The symlink's last component is the bus address (e.g. 0000:02:00.0)
            link_target=$(readlink "$device_path" 2>/dev/null)
            pci_path="${link_target##*/}"
        fi

        local model_val="" ethtool_info="" driver_val="" firmware_val="" bus_info_val=""
        command -v ethtool >/dev/null 2>&1 && ethtool_info=$(LC_ALL=C run_limited 5 ethtool -i "$interface" 2>/dev/null)
        if [[ -n "$ethtool_info" ]]; then
            local eth_key="" eth_value=""
            while IFS=: read -r eth_key eth_value; do
                eth_value="${eth_value#"${eth_value%%[![:space:]]*}"}"
                eth_value="${eth_value%"${eth_value##*[![:space:]]}"}"
                case "$eth_key" in
                    driver) driver_val="$eth_value" ;;
                    firmware-version) firmware_val="$eth_value" ;;
                    bus-info) bus_info_val="$eth_value" ;;
                esac
            done <<< "$ethtool_info"
        fi

        if [[ -n "$pci_path" && "$pci_path" =~ ^([0-9a-fA-F]{4}:)?[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$ ]]; then
            local lspci_slot="$pci_path"
            [[ "$lspci_slot" =~ ^[0-9a-fA-F]{4}: ]] && lspci_slot="${lspci_slot#*:}"
            if [[ ${#PCIE_NAME_CACHE[@]} -eq 0 ]]; then
                get_lspci_output
                build_pcie_name_cache
            fi
            local pci_name="${PCIE_NAME_CACHE[$pci_path]:-}"
            [[ -z "$pci_name" ]] && pci_name="${PCIE_NAME_CACHE[$lspci_slot]:-}"
            [[ -n "$pci_name" ]] && model_val="${pci_name#*: }"
        fi
        [[ -z "$model_val" && -n "$driver_val" ]] && model_val="$driver_val"

        local status="${iface_status[$interface]:-}"
        if [[ -z "$status" ]]; then
            read_line status "/sys/class/net/$interface/operstate"
            status="${status^^}"
        fi

        local ipv4="${iface_ipv4[$interface]:-}" ipv6="${iface_ipv6[$interface]:-}"
        local masked_ipv4="" masked_ipv6=""
        [[ -n "$ipv4" ]] && masked_ipv4=$(mask_ip_address "$ipv4")
        [[ -n "$ipv6" ]] && masked_ipv6=$(mask_ip_address "$ipv6")

        local mac="${iface_mac[$interface]:-}" masked_mac=""
        [[ -z "$mac" ]] && read_line mac "/sys/class/net/$interface/address"
        [[ -n "$mac" ]] && masked_mac=$(mask_mac_address "$mac")

        local speed_val="" duplex_val="" link_detected=""
        local sysfs_net="/sys/class/net/$interface"
        # read_line (bash builtin read): no subshell; reading speed/duplex of a
        # down link fails with EINVAL, which simply yields "".
        local speed="" dtmp="" ctmp=""
        read_line speed "$sysfs_net/speed"
        [[ "$speed" =~ ^[0-9]+$ ]] && speed_val="$speed"
        read_line dtmp "$sysfs_net/duplex"
        [[ -n "$dtmp" && "$dtmp" != "unknown" ]] && duplex_val="$dtmp"
        if [[ -r "$sysfs_net/carrier" ]]; then
            read_line ctmp "$sysfs_net/carrier"
            if [[ "$ctmp" == "1" ]]; then link_detected="Yes"; else link_detected="No"; fi
        fi
        # Fallback to ethtool when sysfs speed/duplex is unavailable
        if [[ -z "$speed_val" || -z "$duplex_val" ]] && command -v ethtool >/dev/null 2>&1; then
            local eline=""
            while IFS= read -r eline; do
                case "$eline" in
                    *Speed:*)
                        if [[ -z "$speed_val" ]]; then
                            local sp="${eline##*Speed:}"; sp="${sp//[[:space:]]/}"
                            [[ "$sp" =~ ^([0-9]+)Mb/s$ ]] && speed_val="${BASH_REMATCH[1]}"
                        fi ;;
                    *Duplex:*)
                        if [[ -z "$duplex_val" ]]; then
                            local dp="${eline##*Duplex:}"; dp="${dp#"${dp%%[![:space:]]*}"}"
                            case "$dp" in Full|Half) duplex_val="${dp,,}" ;; esac
                        fi ;;
                esac
            done < <(LC_ALL=C run_limited 5 ethtool "$interface" 2>/dev/null)
        fi

        # Link column: speed + duplex initial (e.g. "1000M/full")
        local link_disp="-"
        if [[ -n "$speed_val" ]]; then
            link_disp="${speed_val}M"
            [[ -n "$duplex_val" ]] && link_disp+="/${duplex_val}"
        elif [[ -n "$duplex_val" ]]; then
            link_disp="$duplex_val"
        fi

        local status_disp="${status:-Unknown}"
        local status_color=""
        if [[ "$status" == "UP" && "$link_detected" != "No" ]]; then
            status_color="$GREEN"
        elif [[ "$status" == "DOWN" || "$link_detected" == "No" ]]; then
            status_color="$YELLOW"
        fi

        net_rows+=("${interface}${sep}${status_color}${sep}${status_disp}${sep}${link_disp}${sep}${masked_mac:--}${sep}${masked_ipv4:--}${sep}${model_val:--}")

        # Error / drop counters -> warnings only
        local rx_errors="" tx_errors="" rx_dropped="" tx_dropped="" collisions=""
        local stats="$sysfs_net/statistics"
        read_line rx_errors "$stats/rx_errors"
        read_line tx_errors "$stats/tx_errors"
        read_line rx_dropped "$stats/rx_dropped"
        read_line tx_dropped "$stats/tx_dropped"
        read_line collisions "$stats/collisions"
        local error_summary=()
        [[ -n "$rx_errors" && "$rx_errors" != "0" ]] && error_summary+=("rx_errors=$rx_errors")
        [[ -n "$tx_errors" && "$tx_errors" != "0" ]] && error_summary+=("tx_errors=$tx_errors")
        [[ -n "$rx_dropped" && "$rx_dropped" != "0" ]] && error_summary+=("rx_dropped=$rx_dropped")
        [[ -n "$tx_dropped" && "$tx_dropped" != "0" ]] && error_summary+=("tx_dropped=$tx_dropped")
        [[ -n "$collisions" && "$collisions" != "0" ]] && error_summary+=("collisions=$collisions")
        [[ ${#error_summary[@]} -gt 0 ]] && net_warns+=("${interface}${sep}${error_summary[*]}")

        [[ "$COLLECT_JSON" == true ]] || continue

        # (These used to be "$(<file 2>/dev/null || echo)", which is a null
        # command, so rx/tx were never reported.)
        local rx_bytes="" tx_bytes="" rx_display="" tx_display=""
        read_line rx_bytes "$stats/rx_bytes"
        read_line tx_bytes "$stats/tx_bytes"
        [[ -n "$rx_bytes" ]] && format_bytes_to rx_display "$rx_bytes"
        [[ -n "$tx_bytes" ]] && format_bytes_to tx_display "$tx_bytes"

        local net_kv=(
            "$(json_kv_s "name" "$interface")"
            "$(json_kv "status" "${status:-Unknown}")"
        )
        [[ -n "$model_val" ]] && net_kv+=("$(json_kv_s "model" "$model_val")")
        [[ -n "$driver_val" ]] && net_kv+=("$(json_kv_s "driver" "$driver_val")")
        [[ -n "$firmware_val" ]] && net_kv+=("$(json_kv_s "firmware" "$firmware_val")")
        [[ -n "$bus_info_val" ]] && net_kv+=("$(json_kv_s "bus_info" "$bus_info_val")")
        [[ -n "$masked_ipv4" ]] && net_kv+=("$(json_kv_s "ipv4" "$masked_ipv4")")
        [[ -n "$masked_ipv6" ]] && net_kv+=("$(json_kv_s "ipv6" "$masked_ipv6")")
        [[ -n "$masked_mac" ]] && net_kv+=("$(json_kv_s "mac" "$masked_mac")")
        [[ -n "$speed_val" ]] && net_kv+=("$(json_kv "speed_mbps" "$speed_val")")
        [[ -n "$duplex_val" ]] && net_kv+=("$(json_kv "duplex" "$duplex_val")")
        [[ -n "$link_detected" ]] && net_kv+=("$(json_kv "link_detected" "$link_detected")")
        [[ -n "$rx_display" ]] && net_kv+=("$(json_kv "rx" "$rx_display")")
        [[ -n "$tx_display" ]] && net_kv+=("$(json_kv "tx" "$tx_display")")
        [[ -n "$rx_errors" ]] && net_kv+=("$(json_kv "rx_errors" "$rx_errors")")
        [[ -n "$tx_errors" ]] && net_kv+=("$(json_kv "tx_errors" "$tx_errors")")
        [[ -n "$rx_dropped" ]] && net_kv+=("$(json_kv "rx_dropped" "$rx_dropped")")
        [[ -n "$tx_dropped" ]] && net_kv+=("$(json_kv "tx_dropped" "$tx_dropped")")
        [[ -n "$collisions" ]] && net_kv+=("$(json_kv "collisions" "$collisions")")
        JSON_NETWORK+=("$(json_obj "${net_kv[@]}")")
    done

    if [[ ${#net_rows[@]} -eq 0 ]]; then
        print_info "${LBL[status]}" "${LBL[not_detected]}"
        section_end
        return
    fi

    TABLE_COL_W=(12 8 12 18 20 24)
    if [[ "$LANG_MODE" == "cn" ]]; then
        table_header "网卡" "状态" "速率" "MAC地址" "IPv4" "型号"
    else
        table_header "Iface" "Status" "Link" "MAC" "IPv4" "Model"
    fi

    local row="" r_if="" r_col="" r_st="" r_link="" r_mac="" r_ip="" r_model=""
    for row in "${net_rows[@]}"; do
        IFS="$sep" read -r r_if r_col r_st r_link r_mac r_ip r_model <<< "$row"
        table_row "$r_if" "$CYAN" "$r_st" "$r_col" "$r_link" "" "$r_mac" "" "$r_ip" "" "$r_model" ""
    done
    table_close

    if [[ ${#net_warns[@]} -gt 0 ]]; then
        echo "│"
        if [[ "$LANG_MODE" == "cn" ]]; then
            print_color "$YELLOW" "│ 收发错误 / 丢包计数 (累计):"
        else
            print_color "$YELLOW" "│ RX/TX error & drop counters (cumulative):"
        fi
        local wln="" w_if="" w_detail=""
        for wln in "${net_warns[@]}"; do
            IFS="$sep" read -r w_if w_detail <<< "$wln"
            print_note "$w_if" "$w_detail"
        done
    fi

    section_end
}

# gpu_class_label VAR CLASS - localized label for a GPU class token.
gpu_class_label() {
    local __l="-"
    case "$2" in
        discrete)   __l="Discrete";   [[ "$LANG_MODE" == "cn" ]] && __l="独显" ;;
        integrated) __l="Integrated"; [[ "$LANG_MODE" == "cn" ]] && __l="集显" ;;
        bmc)        __l="BMC";        [[ "$LANG_MODE" == "cn" ]] && __l="管理" ;;
    esac
    printf -v "$1" '%s' "$__l"
}

# Function to get GPU information
get_gpu_info() {
    print_subsection "${LBL[gpu_info]}"

    JSON_GPU=()
    local -a gpu_rows=()          # each: type\tmodel\tmemory\tdriver\ttemp
    local sep=$'\034'   # non-whitespace: IFS=$'\t' would merge empty fields

    # NVIDIA GPUs (rich data)
    if command -v nvidia-smi >/dev/null 2>&1; then
        while IFS=',' read -r name memory driver temp power util; do
            local name_val="${name#"${name%%[![:space:]]*}"}"; name_val="${name_val%"${name_val##*[![:space:]]}"}"
            local memory_val="${memory//[[:space:]]/}"
            local driver_val="${driver//[[:space:]]/}"
            local temp_val="${temp//[[:space:]]/}"
            local power_val="${power//[[:space:]]/}"
            local util_val="${util//[[:space:]]/}"
            [[ -z "$name_val" ]] && continue

            # "[N/A]" / "[Not Supported]" fields (e.g. passive datacenter cards)
            [[ "$temp_val" =~ ^[0-9]+$ ]] || temp_val=""
            [[ "$power_val" =~ ^[0-9.]+$ ]] || power_val=""
            [[ "$util_val" =~ ^[0-9]+$ ]] || util_val=""
            [[ "$memory_val" =~ ^[0-9]+$ ]] || memory_val=""

            gpu_rows+=("NVIDIA${sep}discrete${sep}${name_val}${sep}${memory_val:+${memory_val} MB}${sep}${driver_val:--}${sep}${temp_val:+${temp_val}°C}")

            if [[ "$COLLECT_JSON" == true ]]; then
                local gpu_kv=(
                    "$(json_kv "source" "nvidia-smi")"
                    "$(json_kv_s "name" "$name_val")"
                    "$(json_kv "memory_mb" "$memory_val")"
                    "$(json_kv_s "driver" "$driver_val")"
                    "$(json_kv "temperature_c" "$temp_val")"
                    "$(json_kv "power_w" "$power_val")"
                    "$(json_kv "utilization_percent" "$util_val")"
                )
                JSON_GPU+=("$(json_obj "${gpu_kv[@]}")")
            fi
        done < <(run_limited 10 nvidia-smi --query-gpu=name,memory.total,driver_version,temperature.gpu,power.draw,utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
    fi

    # All GPUs visible on the PCI bus (covers AMD/Intel and NVIDIA without driver)
    local line=""
    get_lspci_output
    if [[ -n "$LSPCI_RESULT" ]]; then
        local gpu_devices
        gpu_devices=$(printf '%s\n' "$LSPCI_RESULT" | grep -E "(VGA|3D|Display)" | grep -v "Audio")
        if [[ -n "$gpu_devices" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local slot="${line%% *}"
                local desc="${line#* }"
                desc="${desc#*: }"                 # strip class label, keep vendor/device
                # NVIDIA already covered with rich data via nvidia-smi
                [[ "$desc" == *NVIDIA* ]] && command -v nvidia-smi >/dev/null 2>&1 && continue

                # Classify vendor + class (discrete/integrated/bmc)
                local vendor="Other" cls="-"
                case "$desc" in
                    *NVIDIA*)                          vendor="NVIDIA"; cls="discrete" ;;
                    *AMD*|*"Advanced Micro"*|*ATI*|*Radeon*) vendor="AMD"; cls="discrete" ;;
                    *Intel*)
                        vendor="Intel"
                        case "$desc" in *Arc*|*"DG2"*|*Flex*|*Battlemage*) cls="discrete" ;; *) cls="integrated" ;; esac ;;
                    *ASPEED*)                          vendor="ASPEED"; cls="bmc" ;;
                    *Matrox*)                          vendor="Matrox"; cls="bmc" ;;
                    *)                                 vendor="${desc%% *}"; cls="-" ;;
                esac

                local desc_short=""
                compact_pci_name desc_short "$desc"
                gpu_rows+=("${vendor}${sep}${cls}${sep}${desc_short}${sep}-${sep}-${sep}-")
                if [[ "$COLLECT_JSON" == true ]]; then
                    local gpu_kv=(
                        "$(json_kv "source" "lspci")"
                        "$(json_kv_s "slot" "$slot")"
                        "$(json_kv_s "vendor" "$vendor")"
                        "$(json_kv "class" "$cls")"
                        "$(json_kv_s "name" "$desc")"
                    )
                    JSON_GPU+=("$(json_obj "${gpu_kv[@]}")")
                fi
            done <<< "$gpu_devices"
        fi
    elif ! command -v lspci >/dev/null 2>&1; then
        # No lspci: fall back to `lshw -c display -short` (prefetched).
        # Columns: H/W path, [Device], Class, Description.
        get_lshw_display_output
        local lline="" ldesc=""
        while IFS= read -r lline; do
            [[ "$lline" =~ [[:space:]]display[[:space:]]+(.+)$ ]] || continue
            ldesc="${BASH_REMATCH[1]}"
            ldesc="${ldesc%"${ldesc##*[![:space:]]}"}"
            [[ -z "$ldesc" ]] && continue
            gpu_rows+=("${ldesc%% *}${sep}-${sep}${ldesc}${sep}-${sep}-${sep}-")
            if [[ "$COLLECT_JSON" == true ]]; then
                JSON_GPU+=("$(json_obj "$(json_kv "source" "lshw")" "$(json_kv_s "name" "$ldesc")")")
            fi
        done <<< "$LSHW_DISPLAY_RESULT"
    fi

    if [[ ${#gpu_rows[@]} -eq 0 ]]; then
        print_info "${LBL[status]}" "${LBL[not_detected]}"
        section_end
        return
    fi


    # Do any rows carry rich data (memory/driver/temp from nvidia-smi)?
    local has_rich=false row=""
    for row in "${gpu_rows[@]}"; do
        local _v="" _c="" _m="" _mem="" _drv="" _tmp=""
        IFS="$sep" read -r _v _c _m _mem _drv _tmp <<< "$row"
        if [[ ( -n "$_mem" && "$_mem" != "-" ) || ( -n "$_drv" && "$_drv" != "-" ) || ( -n "$_tmp" && "$_tmp" != "-" ) ]]; then
            has_rich=true; break
        fi
    done

    local gvendor="" gclass="" gmodel="" gmem="" gdriver="" gtemp="" clabel="" ccolor=""
    if [[ "$has_rich" == true ]]; then
        TABLE_COL_W=(7 8 34 10 13 6)
        if [[ "$LANG_MODE" == "cn" ]]; then
            table_header "厂商" "类别" "型号" "显存" "驱动" "温度"
        else
            table_header "Vendor" "Class" "Model" "Memory" "Driver" "Temp"
        fi
        for row in "${gpu_rows[@]}"; do
            IFS="$sep" read -r gvendor gclass gmodel gmem gdriver gtemp <<< "$row"
            gpu_class_label clabel "$gclass"
            case "$gclass" in discrete) ccolor="$GREEN" ;; integrated) ccolor="$CYAN" ;; bmc) ccolor="$YELLOW" ;; *) ccolor="" ;; esac
            local tcolor="" tnum="${gtemp%%°*}"
            if [[ "$tnum" =~ ^[0-9]+$ ]]; then
                if (( tnum >= 85 )); then tcolor="$RED"; elif (( tnum >= 75 )); then tcolor="$YELLOW"; else tcolor="$GREEN"; fi
            fi
            table_row "$gvendor" "$CYAN" "$clabel" "$ccolor" "$gmodel" "" "$gmem" "" "$gdriver" "" "$gtemp" "$tcolor"
        done
        table_close
    else
        TABLE_COL_W=(8 10 54)
        if [[ "$LANG_MODE" == "cn" ]]; then
            table_header "厂商" "类别" "型号"
        else
            table_header "Vendor" "Class" "Model"
        fi
        for row in "${gpu_rows[@]}"; do
            IFS="$sep" read -r gvendor gclass gmodel gmem gdriver gtemp <<< "$row"
            gpu_class_label clabel "$gclass"
            case "$gclass" in discrete) ccolor="$GREEN" ;; integrated) ccolor="$CYAN" ;; bmc) ccolor="$YELLOW" ;; *) ccolor="" ;; esac
            table_row "$gvendor" "$CYAN" "$clabel" "$ccolor" "$gmodel" ""
        done
        table_close
    fi

    section_end
}

# Function to get motherboard information
get_motherboard_info() {
    print_subsection "${LBL[motherboard_info]}"

    local mb_vendor=""
    local mb_product=""
    local mb_version=""
    local bios_vendor=""
    local bios_version=""

    local dmi=/sys/class/dmi/id
    read_line mb_vendor "$dmi/board_vendor"
    read_line mb_product "$dmi/board_name"
    read_line mb_version "$dmi/board_version"
    read_line bios_vendor "$dmi/bios_vendor"
    read_line bios_version "$dmi/bios_version"

    # sysfs DMI is world-readable; dmidecode needs root and is only a fallback.
    # Stop after the first empty answer (no SMBIOS table at all, e.g. ARM / microVMs).
    if [[ -z "$mb_vendor$mb_product$mb_version$bios_vendor$bios_version" && $EUID -eq 0 ]] &&
       command -v dmidecode >/dev/null 2>&1; then
        bios_vendor=$(run_limited 10 dmidecode -s bios-vendor 2>/dev/null)
        [[ "$bios_vendor" == "#"* ]] && bios_vendor=""
        if [[ -n "$bios_vendor" ]]; then
            bios_version=$(run_limited 10 dmidecode -s bios-version 2>/dev/null)
            mb_vendor=$(run_limited 10 dmidecode -s baseboard-manufacturer 2>/dev/null)
            mb_product=$(run_limited 10 dmidecode -s baseboard-product-name 2>/dev/null)
            mb_version=$(run_limited 10 dmidecode -s baseboard-version 2>/dev/null)
        fi
    fi

    if [[ -n "$mb_vendor$mb_product$mb_version$bios_vendor$bios_version" ]]; then
        print_info "${LBL[vendor]}" "${mb_vendor:-${LBL[no_info]}}"
        print_info "${LBL[model]}" "${mb_product:-${LBL[no_info]}}"
        print_info "${LBL[version]}" "${mb_version:-${LBL[no_info]}}"
        print_info "${LBL[bios_vendor]}" "${bios_vendor:-${LBL[no_info]}}"
        print_info "${LBL[bios_version]}" "${bios_version:-${LBL[no_info]}}"

        if [[ "$COLLECT_JSON" == true ]]; then
            JSON_MOTHERBOARD_KV=(
                "$(json_kv_s "vendor" "$mb_vendor")"
                "$(json_kv_s "model" "$mb_product")"
                "$(json_kv_s "version" "$mb_version")"
                "$(json_kv_s "bios_vendor" "$bios_vendor")"
                "$(json_kv_s "bios_version" "$bios_version")"
            )
        fi
    else
        print_info "${LBL[status]}" "${LBL[no_info]} ${LBL[dmidecode_required]}"
        JSON_MOTHERBOARD_KV=()
    fi

    section_end
}

print_report_overview() {
    local section_title="Report Overview"
    local version_name="Version"
    local mode_name="Mode"
    local privacy_name="Privacy"
    local mode_label="Text"
    local privacy_status="IP/MAC masked"

    if [[ "$LANG_MODE" == "cn" ]]; then
        section_title="报告概览"
        version_name="版本"
        mode_name="模式"
        privacy_name="隐私"
        mode_label="文本"
        privacy_status="IP/MAC 已脱敏"
    fi

    print_subsection "$section_title"
    print_info "$version_name" "$VERSION"
    print_info "$mode_name" "$mode_label"
    print_info "$privacy_name" "$privacy_status"
    if [[ "$LANG_MODE" == "cn" ]]; then
        print_info "序列号" "明文显示"
    else
        print_info "Serials" "shown in full"
    fi
    section_end
}

# Function to show usage
show_usage() {
    # Under `curl ... | bash`, $0 is just "bash": show how to pass options there.
    local prog="${0##*/}"
    case "$prog" in
        bash|-bash|sh|-sh|"") prog="curl -sL https://ba.sh/sick | bash -s --" ;;
        *) prog="$0" ;;
    esac
    cat << EOF
Usage: $prog [OPTIONS]

Hardware Information Collection Script v$VERSION
One-shot hardware inventory — collects and prints, never persists or monitors.

OPTIONS:
    -cn, --chinese     Display output in Chinese
    -us, --english     Display output in English (default)
    -j,  --json        Output JSON to stdout only
    -y,  --yes         Auto-install missing tools without prompting
         --no-install  Never install; report with whatever tools are present
         --no-color    Plain text, no ANSI colors (also: NO_COLOR=1)
         --color       Force colors even when stdout is not a terminal
         --no-clear    Do not clear the screen before the report
         --cleanup     After the report, remove packages this run installed
         --keep-packages  Keep packages this run installed (do not ask)
    -h,  --help        Show this help message
    -v,  --version     Show version information

SECTIONS:
    System, CPU (+platform), Memory, Disks/SMART, NVMe deep health,
    RAID/HBA, Network, GPU, Motherboard — all rendered as aligned tables.

HEALTH:
    The report ends with a health verdict: problems (✗, e.g. SMART failure,
    reallocated/pending sectors, degraded RAID, ECC errors) and warnings (!,
    e.g. high wear or temperature, filesystem >= 90% full). Also in JSON as
    "health". The exit code is always 0 (inventory tool).

PACKAGES:
    Missing tools can be installed for the report (asks first; -y installs
    without asking). Afterwards SICK offers to remove exactly the packages it
    installed in this run (--cleanup: remove without asking).

PRIVACY:
    IP and MAC addresses are masked. Serial numbers are shown in full.

Supported Distributions:
    Debian/Ubuntu/Mint, RHEL/CentOS/Alma/Rocky/CloudLinux/Oracle/Amazon,
    Fedora, Arch/Manjaro, openSUSE/SLES, Alpine (and derivatives via ID_LIKE)

Examples:
    $prog                 # Text report (English), prompts before installing tools
    $prog -cn             # Text report in Chinese
    $prog -y              # Auto-install missing tools, then report
    $prog --json | jq .   # Machine-readable JSON

Note: run with sudo for complete hardware access (dmidecode, SMART, etc.).

EOF
}

# Function to show version
show_version() {
    echo "$SCRIPT_NAME v$VERSION"
}

# Function to build JSON report string
build_json_report() {
    local host="" generated_at=""
    get_hostname_to host
    # ISO 8601 with UTC offset (bash 4.2 printf %(...)T; no date(1) fork)
    printf -v generated_at '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    local meta_kv=(
        "$(json_kv_s "version" "$VERSION")"
        "$(json_kv_s "generated_at" "$generated_at")"
        "$(json_kv_s "hostname" "$host")"
        "$(json_kv "language" "$LANG_MODE")"
    )

    local memory_kv=("${JSON_RAM_KV[@]}")
    memory_kv+=("$(json_kv_raw "modules" "$(json_array "${JSON_RAM_MODULES[@]}")")")

    local raid_kv=(
        "$(json_kv_raw "software" "$(json_array_values "${JSON_RAID_SW[@]}")")"
        "$(json_kv_raw "hardware" "$(json_array_values "${JSON_RAID_HW[@]}")")"
        "$(json_kv_raw "tools" "$(json_array "${JSON_RAID_TOOLS[@]}")")"
    )

    local platform_kv=("${JSON_PLATFORM_KV[@]}")

    local root_kv=(
        "$(json_kv_raw "meta" "$(json_obj "${meta_kv[@]}")")"
        "$(json_kv_raw "system" "$(json_obj "${JSON_SYSTEM_KV[@]}")")"
        "$(json_kv_raw "cpu" "$(json_obj "${JSON_CPU_KV[@]}")")"
        "$(json_kv_raw "platform" "$(json_obj "${platform_kv[@]}")")"
        "$(json_kv_raw "memory" "$(json_obj "${memory_kv[@]}")")"
        "$(json_kv_raw "disks" "$(json_array "${JSON_DISKS[@]}")")"
        "$(json_kv_raw "nvme_deep" "$(json_array "${JSON_NVME_DEEP[@]}")")"
        "$(json_kv_raw "raid" "$(json_obj "${raid_kv[@]}")")"
        "$(json_kv_raw "network" "$(json_array "${JSON_NETWORK[@]}")")"
        "$(json_kv_raw "gpu" "$(json_array "${JSON_GPU[@]}")")"
        "$(json_kv_raw "motherboard" "$(json_obj "${JSON_MOTHERBOARD_KV[@]}")")"
        "$(json_kv_raw "health" "$(health_json)")"
    )

    printf '%s' "$(json_obj "${root_kv[@]}")"
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -cn|--chinese)
                LANG_MODE="cn"
                shift
                ;;
            -us|--english)
                LANG_MODE="en"
                shift
                ;;
            -j|--json)
                OUTPUT_MODE="json"
                shift
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            --no-install)
                NO_INSTALL=true
                shift
                ;;
            --no-color|--no-colour)
                COLOR_MODE="never"
                shift
                ;;
            --color|--colour)
                COLOR_MODE="always"
                shift
                ;;
            --no-clear)
                NO_CLEAR=true
                shift
                ;;
            --cleanup)
                CLEANUP_MODE="always"
                shift
                ;;
            --keep-packages)
                CLEANUP_MODE="never"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage >&2
                exit 1
                ;;
        esac
    done

    init_labels
    [[ "$OUTPUT_MODE" == "json" ]] && COLOR_MODE="never"
    setup_colors
    # Spinner only on a real terminal: never for --json, files or pipes
    if [[ "$OUTPUT_MODE" != "json" && -t 1 && "${TERM:-}" != "dumb" ]]; then
        SPIN_ENABLED=true
    fi

    # Clear the terminal only when stdout is one (under `curl | bash` only
    # stdin is the pipe) and never for JSON or redirected output. Writing to
    # /dev/tty instead would fail without a controlling terminal and would wipe
    # the screen even when the report goes to a file.
    if [[ "$OUTPUT_MODE" != "json" && "$NO_CLEAR" != true && -z "${CATBASH_NO_CLEAR:-}" && -t 1 && "${TERM:-}" != "dumb" ]]; then
        printf '\033[2J\033[H'
    fi

    generate_report_text() {
        COLLECT_JSON=false
        # CPU usage is sampled before the background probes start so they do
        # not inflate it; smartctl / nvme-cli then run while the first
        # sections render.
        sample_cpu_usage
        start_hw_prefetch
        start_lshw_display_prefetch

        # Print title
        print_brand_chip
        print_header "${LBL[title]}"
        print_report_overview

        # Collect all hardware information
        get_system_info
        get_cpu_info
        get_cpu_platform_info
        get_ram_info
        get_disk_info
        get_nvme_deep_info
        get_raid_info
        get_network_info
        get_gpu_info
        get_motherboard_info

        render_health

        # Footer
        local now=""
        printf -v now '%(%Y-%m-%d %H:%M:%S %Z)T' -1
        echo
        print_color "$GREEN" "${LBL[completed]}"
        print_color "$DIM" "${LBL[generated_on]}: $now"
        echo
    }

    generate_report_json() {
        json_reset
        COLLECT_JSON=true
        local previous_quiet_mode="$QUIET_MODE"
        QUIET_MODE=true
        {
            sample_cpu_usage
            start_hw_prefetch
            start_lshw_display_prefetch
            collect_ram_info
            get_system_info
            get_cpu_info
            get_cpu_platform_info
            get_disk_info
            get_nvme_deep_info
            get_raid_info
            get_network_info
            get_gpu_info
            get_motherboard_info
        } >/dev/null 2>&1
        QUIET_MODE="$previous_quiet_mode"
        build_json_report
        echo
    }

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        generate_report_json
        return
    fi

    # Check if running as root for some commands (text output only)
    if [[ $EUID -ne 0 ]]; then
        print_color "$YELLOW" "${LBL[root_note]}"
        print_color "$YELLOW" "${LBL[root_hint]}"
        echo
    fi

    # Install required packages (text output only). install_packages handles
    # the Y/N confirmation itself and always lets us continue afterwards.
    print_color "$DIM" "${LBL[generating]}"
    echo

    install_packages || true

    generate_report_text

    # Optional removal of what install_packages() added in this run
    cleanup_installed_packages
}

# Run main function
main "$@"
