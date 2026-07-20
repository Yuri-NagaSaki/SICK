#!/bin/bash

# Hardware Information Collection Script (BETA)
# 硬件信息收集脚本（测试版）
# Compatible with Debian/Ubuntu/CentOS/AlmaLinux/Rocky Linux/CloudLinux/Arch Linux/openSUSE/Fedora
# 兼容 Debian/Ubuntu/CentOS/AlmaLinux/Rocky Linux/CloudLinux/Arch Linux/openSUSE/Fedora
#
# NOTE: This is a one-shot hardware inventory tool. It does NOT persist anything
# or run as a monitor. Strict mode (set -e/-u) is intentionally NOT enabled:
# collection is best-effort and many probes legitimately fail (missing tool,
# grep no-match); aborting on the first failure would truncate the report.

# Force a UTF-8 locale so CJK display-width math and box-drawing align correctly
# even when invoked from cron / CI / `curl | bash` (which often run under C).
if ! locale 2>/dev/null | grep -qiE 'LC_CTYPE=.*(UTF-8|utf8)'; then
    for _cand in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
        if locale -a 2>/dev/null | grep -qix "$_cand"; then
            export LC_ALL="$_cand"
            break
        fi
    done
fi

VERSION="3.0.0-beta.1"
SCRIPT_NAME="Hardware Info Collector (beta)"

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
RAID_CONTROLLER_RESULT=""
SMART_JSON_RESULT=""
SMART_JSON_RAID_RESULT=""
DISPLAY_WIDTH_RESULT=0
SMARTCTL_TIMEOUT_SECONDS=8
SMARTCTL_PARALLEL=4
SMARTCTL_VERSION_MAJOR=""
SMARTCTL_VERSION_CHECKED=false
LSPCI_CACHE=""
LSPCI_CACHE_DONE=false
LSPCI_RESULT=""
LSHW_DISPLAY_CACHE=""
LSHW_DISPLAY_CACHE_DONE=false
LSHW_DISPLAY_RESULT=""
LSHW_DISPLAY_PREFETCH_PID=""
LSHW_DISPLAY_PREFETCH_FILE=""
COLLECT_JSON=false
declare -A DISK_BASIC_INFO_CACHE
declare -A DISK_SMART_FIELDS
declare -A PCIE_NAME_CACHE

# Collected memory data. Rendering and JSON assembly consume these instead of
# mixing dmidecode parsing with terminal output.
RAM_TOTAL=""
RAM_USED=""
RAM_AVAILABLE=""
RAM_MODULE_ROWS=()
RAM_FALLBACK_LINES=()
RAM_HAS_DETAILED_MODULES=false
RAM_FIELD_SEP=$'\034'
FIELD_SEP=$'\034'

# JSON report data containers
JSON_SYSTEM_KV=()
JSON_CPU_KV=()
JSON_RAM_KV=()
JSON_RAM_MODULES=()
JSON_DISKS=()
JSON_RAID_SW=()
JSON_RAID_HW=()
JSON_RAID_CONTROLLERS=()
JSON_NETWORK=()
JSON_GPU=()
JSON_MOTHERBOARD_KV=()
JSON_ECC_KV=()
JSON_ECC_CONTROLLERS=()
JSON_ECC_EVENTS=()
JSON_NVME_DEEP=()
JSON_PCIE_LINKS=()
JSON_PLATFORM_KV=()
JSON_PLATFORM_VULNERABILITIES=()
JSON_STORAGE_BLOCKS=()
JSON_STORAGE_MOUNTS=()
JSON_STORAGE_LVM=()
JSON_STORAGE_ZFS=()
JSON_STORAGE_BTRFS=()
JSON_STORAGE_MULTIPATH=()
JSON_RAID_TOOLS=()
JSON_DISK_SMART_KV=()
DISK_JSON_EXTRA=()

# Cleanup function for temporary files
cleanup_temp_files() {
    for tmp_file in "${TEMP_FILES[@]}"; do
        [[ -f "$tmp_file" ]] && rm -f "$tmp_file"
    done
}

# Set trap to cleanup on exit
trap cleanup_temp_files EXIT

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' 

# Default language
LANG_MODE="en"
OUTPUT_MODE="text"
QUIET_MODE=false
AUTO_YES=false        # -y/--yes : install missing deps without prompting
NO_INSTALL=false      # --no-install : never install, just report with what's present

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
    ["model"]="Model"
    ["frequency"]="Frequency"
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
    ["model"]="型号"
    ["frequency"]="频率"
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
)

# Function to get label based on current language
get_label() {
    local key="$1"
    if [[ "$LANG_MODE" == "cn" ]]; then
        echo "${LABELS_CN[$key]}"
    else
        echo "${LABELS_EN[$key]}"
    fi
}

# Function to print colored output
print_color() {
    [[ "$QUIET_MODE" == true ]] && return
    local color="$1"
    local text="$2"
    printf '%b\n' "${color}${text}${NC}"
}

# JSON helpers
json_escape() {
    local str="$1"
    str=${str//\\/\\\\}
    str=${str//\"/\\\"}
    str=${str//$'\n'/\\n}
    str=${str//$'\r'/\\r}
    str=${str//$'\t'/\\t}
    str=${str//$'\b'/\\b}
    str=${str//$'\f'/\\f}
    printf '%s' "$str"
}

json_value() {
    [[ "$COLLECT_JSON" == true ]] || return
    local val="$1"
    if [[ -z "$val" ]]; then
        printf 'null'
        return
    fi
    # JSON numbers cannot have leading zeros (except "0" or "0.xxx")
    if [[ "$val" =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?$ ]]; then
        printf '%s' "$val"
        return
    fi
    printf '"%s"' "$(json_escape "$val")"
}

json_kv() {
    [[ "$COLLECT_JSON" == true ]] || return
    local key="$1"
    local val="$2"
    printf '"%s":%s' "$key" "$(json_value "$val")"
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
    local items=("$@")
    if [[ ${#items[@]} -eq 0 ]]; then
        printf '{}'
        return
    fi
    printf '{%s}' "$(json_join "${items[@]}")"
}

json_array() {
    [[ "$COLLECT_JSON" == true ]] || return
    local items=("$@")
    if [[ ${#items[@]} -eq 0 ]]; then
        printf '[]'
        return
    fi
    printf '[%s]' "$(json_join "${items[@]}")"
}

json_array_values() {
    [[ "$COLLECT_JSON" == true ]] || return
    local out=()
    local v=""
    for v in "$@"; do
        [[ -z "$v" ]] && continue
        out+=("$(json_value "$v")")
    done
    json_array "${out[@]}"
}

json_reset() {
    JSON_SYSTEM_KV=()
    JSON_CPU_KV=()
    JSON_RAM_KV=()
    JSON_RAM_MODULES=()
    JSON_DISKS=()
    JSON_RAID_SW=()
    JSON_RAID_HW=()
    JSON_RAID_CONTROLLERS=()
    JSON_NETWORK=()
    JSON_GPU=()
    JSON_MOTHERBOARD_KV=()
    JSON_ECC_KV=()
    JSON_ECC_CONTROLLERS=()
    JSON_ECC_EVENTS=()
    JSON_NVME_DEEP=()
    JSON_PCIE_LINKS=()
    JSON_PLATFORM_KV=()
    JSON_PLATFORM_VULNERABILITIES=()
    JSON_STORAGE_BLOCKS=()
    JSON_STORAGE_MOUNTS=()
    JSON_STORAGE_LVM=()
    JSON_STORAGE_ZFS=()
    JSON_STORAGE_BTRFS=()
    JSON_STORAGE_MULTIPATH=()
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
    JSON_DISK_SMART_KV+=("$(json_kv "$key" "$val")")
}

disk_extra_add() {
    local key="$1"
    local val="$2"
    [[ "$COLLECT_JSON" == true ]] || return
    [[ -z "$key" || -z "$val" ]] && return
    DISK_JSON_EXTRA+=("$(json_kv "$key" "$val")")
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

    pairs+=("$(json_kv "category" "$category")")
    pairs+=("$(json_kv "name" "$name")")
    [[ -n "$basic_info" ]] && pairs+=("$(json_kv "basic_info" "$basic_info")")

    if [[ ${#DISK_JSON_EXTRA[@]} -gt 0 ]]; then
        pairs+=("${DISK_JSON_EXTRA[@]}")
    fi
    if [[ ${#JSON_DISK_SMART_KV[@]} -gt 0 ]]; then
        pairs+=("$(json_kv_raw "smart" "$(json_obj "${JSON_DISK_SMART_KV[@]}")")")
    fi

    JSON_DISKS+=("$(json_obj "${pairs[@]}")")
    DISK_JSON_EXTRA=()
    JSON_DISK_SMART_KV=()
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
    local padding=$(( (width - ${#title}) / 2 ))
    
    echo
    print_color "$CYAN" "$(repeat_char '═' $width)"
    print_color "$WHITE" "$(printf '%*s%s%*s' $padding '' "$title" $padding '')"
    print_color "$CYAN" "$(repeat_char '═' $width)"
    echo
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
    print_color "$YELLOW" "┌─ $title $(repeat_char '─' "$fill")"
    print_color "$YELLOW" "├$(repeat_char '─' "$width")"
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

# Aligned warning/note line under a section: "│   ⚠ <tag padded>  <detail>".
print_note() {
    [[ "$QUIET_MODE" == true ]] && return
    local tag="$1"
    local detail="$2"
    local color="${3:-$YELLOW}"
    local mark="${4:-⚠}"
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
    printf '%s%s%s\n' "$left" "$(repeat_char '─' "$total")" "$right"
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
    else
        echo "unknown"
    fi
}

# Function to get package manager
get_package_manager() {
    local distro=$(detect_distro)
    case "$distro" in
        "ubuntu"|"debian"|"linuxmint")
            echo "apt"
            ;;
        "centos"|"rhel"|"almalinux"|"rocky"|"cloudlinux")
            if command -v dnf >/dev/null 2>&1; then
                echo "dnf"
            else
                echo "yum"
            fi
            ;;
        "fedora")
            echo "dnf"
            ;;
        "arch"|"manjaro")
            echo "pacman"
            ;;
        "opensuse"|"sles")
            echo "zypper"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

get_lspci_output() {
    if [[ "$LSPCI_CACHE_DONE" == true ]]; then
        LSPCI_RESULT="$LSPCI_CACHE"
        return
    fi

    if command -v lspci >/dev/null 2>&1; then
        LSPCI_CACHE=$(lspci 2>/dev/null)
    else
        LSPCI_CACHE=""
    fi

    LSPCI_CACHE_DONE=true
    LSPCI_RESULT="$LSPCI_CACHE"
}

get_lshw_display_output() {
    if [[ "$LSHW_DISPLAY_CACHE_DONE" == true ]]; then
        LSHW_DISPLAY_RESULT="$LSHW_DISPLAY_CACHE"
        return
    fi

    if [[ -n "$LSHW_DISPLAY_PREFETCH_PID" ]]; then
        wait "$LSHW_DISPLAY_PREFETCH_PID" 2>/dev/null || true
        if [[ -n "$LSHW_DISPLAY_PREFETCH_FILE" && -f "$LSHW_DISPLAY_PREFETCH_FILE" ]]; then
            LSHW_DISPLAY_CACHE=$(<"$LSHW_DISPLAY_PREFETCH_FILE")
        else
            LSHW_DISPLAY_CACHE=""
        fi
        LSHW_DISPLAY_CACHE_DONE=true
        LSHW_DISPLAY_RESULT="$LSHW_DISPLAY_CACHE"
        return
    fi

    if command -v lshw >/dev/null 2>&1; then
        LSHW_DISPLAY_CACHE=$(lshw -c display -short 2>/dev/null | grep -v "H/W path")
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

    local tmp_file=""
    tmp_file=$(mktemp 2>/dev/null) || return
    TEMP_FILES+=("$tmp_file")

    ( lshw -c display -short 2>/dev/null | grep -v "H/W path" > "$tmp_file" ) &
    LSHW_DISPLAY_PREFETCH_PID=$!
    LSHW_DISPLAY_PREFETCH_FILE="$tmp_file"
}

# Function to install required packages
install_packages() {
    # Map of required command -> package name (sensors/lspci overridden per distro)
    local pkg_manager
    pkg_manager=$(get_package_manager)

    local -a req_cmds=(dmidecode lshw smartctl ethtool nvme jq lspci sensors)
    local -A pkg_of=(
        [dmidecode]=dmidecode [lshw]=lshw [smartctl]=smartmontools
        [ethtool]=ethtool [nvme]=nvme-cli [jq]=jq [lspci]=pciutils
    )
    # sensors package name varies by distro
    case "$pkg_manager" in
        apt) pkg_of[sensors]=lm-sensors ;;
        dnf|yum|pacman) pkg_of[sensors]=lm_sensors ;;
        zypper) pkg_of[sensors]=sensors ;;
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

    # Decide whether to install: -y, or interactive Y/N, or skip when non-interactive
    local do_install=false
    if [[ "$AUTO_YES" == true ]]; then
        do_install=true
    elif [[ -t 0 ]]; then
        local prompt="Install these packages now? [y/N]: "
        [[ "$LANG_MODE" == "cn" ]] && prompt="现在安装这些软件包吗？[y/N]: "
        local reply=""
        read -r -p "$prompt" reply
        case "$reply" in
            [Yy]*) do_install=true ;;
            *) do_install=false ;;
        esac
    else
        # Non-interactive (e.g. curl | bash) and no -y: do not install silently
        if [[ "$LANG_MODE" == "cn" ]]; then
            echo "非交互式运行且未加 -y，跳过安装。加 -y 可自动安装。继续生成报告..."
        else
            echo "Non-interactive and no -y: skipping install. Pass -y to auto-install. Continuing..."
        fi
        echo
        return 1
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
        apt)    "${sudo_prefix[@]}" apt-get update >/dev/null 2>&1 || true
                install_cmd=("${sudo_prefix[@]}" apt-get install -y) ;;
        dnf)    install_cmd=("${sudo_prefix[@]}" dnf install -y) ;;
        yum)    install_cmd=("${sudo_prefix[@]}" yum install -y) ;;
        pacman) install_cmd=("${sudo_prefix[@]}" pacman -S --noconfirm) ;;
        zypper) install_cmd=("${sudo_prefix[@]}" zypper install -y) ;;
    esac

    [[ "$LANG_MODE" == "cn" ]] && echo "正在安装: ${uniq_pkgs[*]}" || echo "Installing: ${uniq_pkgs[*]}"
    if "${install_cmd[@]}" "${uniq_pkgs[@]}" >/dev/null 2>&1; then
        [[ "$LANG_MODE" == "cn" ]] && print_color "$GREEN" "安装完成。" || print_color "$GREEN" "Installation complete."
    else
        [[ "$LANG_MODE" == "cn" ]] && print_color "$YELLOW" "部分软件包安装失败，继续生成报告。" \
            || print_color "$YELLOW" "Some packages failed to install; continuing."
    fi
    echo
    return 0
}

# Function to get system information
get_system_info() {
    print_subsection "$(get_label "system_info")"

    local hostname_val=""
    local os_val=""
    local kernel_val=""
    local uptime_val=""

    hostname_val=$(hostname)
    os_val=$(get_os_release_value "PRETTY_NAME" 2>/dev/null)
    [[ -z "$os_val" ]] && os_val="$(get_label "no_info")"
    kernel_val=$(uname -r)
    uptime_val=$(uptime -p 2>/dev/null || uptime | cut -d',' -f1 | sed 's/.*up //')

    print_info "$(get_label "hostname")" "$hostname_val"
    print_info "$(get_label "os")" "$os_val"
    print_info "$(get_label "kernel")" "$kernel_val"
    print_info "$(get_label "uptime")" "$uptime_val"

    JSON_SYSTEM_KV=(
        "$(json_kv "hostname" "$hostname_val")"
        "$(json_kv "os" "$os_val")"
        "$(json_kv "kernel" "$kernel_val")"
        "$(json_kv "uptime" "$uptime_val")"
    )
    
    echo "└$(repeat_char '─' 50)"
}

# Function to detect CPU temperature
get_cpu_temperature() {
    local temp_found=false
    local cpu_temps=""
    local max_temp=0
    local temp_data=""

    # Method 1: Try using sensors command (lm-sensors)
    if command -v sensors >/dev/null 2>&1; then
        local sensors_output=$(sensors 2>/dev/null)

        # Priority 1: Intel CPU - look for "Package id X" (whole CPU package temperature)
        # Note: may have leading spaces, so don't use ^
        local pkg_line=$(echo "$sensors_output" | grep -E "Package id [0-9]+:" | head -1)
        if [[ -n "$pkg_line" ]]; then
            local temp_part=$(echo "$pkg_line" | sed 's/(.*//')
            local pkg_temp=$(echo "$temp_part" | grep -oE "[+-]?[0-9]+\.?[0-9]*" | tail -1)
            if [[ -n "$pkg_temp" ]]; then
                temp_found=true
                temp_data="${pkg_temp}°C"
            fi
        fi

        # Priority 2: AMD CPU - look for Tctl/Tdie (k10temp driver)
        if [[ -z "$temp_data" ]]; then
            local amd_line=$(echo "$sensors_output" | grep -E "Tctl:|Tdie:" | head -1)
            if [[ -n "$amd_line" ]]; then
                local temp_part=$(echo "$amd_line" | sed 's/(.*//')
                local amd_temp=$(echo "$temp_part" | grep -oE "[+-]?[0-9]+\.?[0-9]*" | tail -1)
                if [[ -n "$amd_temp" ]]; then
                    temp_found=true
                    temp_data="${amd_temp}°C"
                fi
            fi
        fi

        # Priority 3: Generic CPU temperature patterns
        if [[ -z "$temp_data" ]]; then
            local generic_line=$(echo "$sensors_output" | grep -iE "cpu.*temp|cpu:" | head -1)
            if [[ -n "$generic_line" ]]; then
                local temp_part=$(echo "$generic_line" | sed 's/(.*//')
                local generic_temp=$(echo "$temp_part" | grep -oE "[+-]?[0-9]+\.?[0-9]*" | tail -1)
                if [[ -n "$generic_temp" ]]; then
                    temp_found=true
                    temp_data="${generic_temp}°C"
                fi
            fi
        fi
    fi

    # Method 2: Check thermal zones in /sys/class/thermal
    if [[ "$temp_found" == false ]]; then
        for zone in /sys/class/thermal/thermal_zone*/temp; do
            if [[ -r "$zone" ]]; then
                local zone_temp=$(cat "$zone" 2>/dev/null)
                local zone_type_file="${zone%/temp}/type"
                local zone_type="unknown"

                if [[ -r "$zone_type_file" ]]; then
                    zone_type=$(cat "$zone_type_file" 2>/dev/null)
                fi

                # Check if this is a CPU-related thermal zone
                if [[ "$zone_type" =~ (cpu|x86_pkg_temp|CPU|Core|Package) ]]; then
                    if [[ "$zone_temp" =~ ^[0-9]+$ && "$zone_temp" -gt 0 ]]; then
                        # Convert millidegree to degree Celsius
                        local temp_celsius=""
                        millicelsius_to temp_celsius "$zone_temp"
                        if [[ -n "$temp_celsius" ]]; then
                            temp_found=true
                            temp_data="${temp_celsius}°C (${zone_type})"
                            break
                        fi
                    fi
                fi
            fi
        done
    fi

    # Method 3: Check hwmon interfaces
    if [[ "$temp_found" == false ]]; then
        for hwmon in /sys/class/hwmon/hwmon*/; do
            if [[ -r "${hwmon}name" ]]; then
                local hwmon_name=$(cat "${hwmon}name" 2>/dev/null)

                # Check if this is CPU-related
                if [[ "$hwmon_name" =~ (coretemp|k10temp|k8temp|fam15h_power|cpu) ]]; then
                    # Look for temperature inputs
                    for temp_input in "${hwmon}"temp*_input; do
                        if [[ -r "$temp_input" ]]; then
                            local temp_val=$(cat "$temp_input" 2>/dev/null)
                            if [[ "$temp_val" =~ ^[0-9]+$ && "$temp_val" -gt 0 ]]; then
                                # Convert millidegree to degree Celsius
                                local temp_celsius=""
                                millicelsius_to temp_celsius "$temp_val"

                                # Get label if available
                                local temp_label_file="${temp_input%_input}_label"
                                local temp_label=""
                                if [[ -r "$temp_label_file" ]]; then
                                    temp_label=$(cat "$temp_label_file" 2>/dev/null)
                                fi

                                if [[ -n "$temp_celsius" ]]; then
                                    temp_found=true
                                    if [[ -n "$temp_label" ]]; then
                                        temp_data="${temp_celsius}°C (${temp_label})"
                                    else
                                        temp_data="${temp_celsius}°C"
                                    fi
                                    break 2
                                fi
                            fi
                        fi
                    done
                fi
            fi
        done
    fi

    # Method 4: Try using vcgencmd for Raspberry Pi
    if [[ "$temp_found" == false ]] && command -v vcgencmd >/dev/null 2>&1; then
        local pi_temp=$(vcgencmd measure_temp 2>/dev/null | grep -oE "[0-9]+\.?[0-9]*")
        if [[ -n "$pi_temp" ]]; then
            temp_found=true
            temp_data="${pi_temp}°C (Raspberry Pi)"
        fi
    fi

    # Return the result
    if [[ "$temp_found" == true ]]; then
        echo "$temp_data"
    else
        echo ""
    fi
}

# Function to get CPU information
get_cpu_info() {
    print_subsection "$(get_label "cpu_info")"

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

    print_info "$(get_label "model")" "${cpu_model:-$(get_label "no_info")}"
    print_info "$(get_label "cores")" "${cpu_cores:-$(get_label "no_info")}"
    print_info "$(get_label "threads")" "${cpu_threads:-$(get_label "no_info")}"
    print_info "$(get_label "frequency")" "${cpu_freq:+${cpu_freq} MHz}"
    print_info "$(get_label "cache")" "${cpu_cache:-$(get_label "no_info")}"

    # CPU usage - using /proc/stat for more reliable detection
    local cpu_usage=""
    if [[ -r /proc/stat ]]; then
        # Read CPU stats twice with a short interval
        local user1="" nice1="" system1="" idle1="" iowait1="" irq1="" softirq1=""
        local user2="" nice2="" system2="" idle2="" iowait2="" irq2="" softirq2=""
        read -r _ user1 nice1 system1 idle1 iowait1 irq1 softirq1 _ < /proc/stat
        sleep 0.2
        read -r _ user2 nice2 system2 idle2 iowait2 irq2 softirq2 _ < /proc/stat

        # Calculate differences
        local user_diff=$((user2 - user1))
        local nice_diff=$((nice2 - nice1))
        local system_diff=$((system2 - system1))
        local idle_diff=$((idle2 - idle1))
        local iowait_diff=$((iowait2 - iowait1))
        local irq_diff=$((irq2 - irq1))
        local softirq_diff=$((softirq2 - softirq1))

        local total_diff=$((user_diff + nice_diff + system_diff + idle_diff + iowait_diff + irq_diff + softirq_diff))
        local active_diff=$((total_diff - idle_diff - iowait_diff))

        if [[ $total_diff -gt 0 ]]; then
            local usage_tenths=$((active_diff * 1000 / total_diff))
            cpu_usage="$((usage_tenths / 10)).$((usage_tenths % 10))"
        fi
    fi

    # Fallback to top if /proc/stat method fails
    if [[ -z "$cpu_usage" ]]; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null)
    fi
    local cpu_usage_val=""
    if [[ -n "$cpu_usage" ]]; then
        cpu_usage_val="${cpu_usage}%"
    fi
    print_info "$(get_label "usage")" "$cpu_usage_val"

    # CPU Temperature
    local cpu_temp=$(get_cpu_temperature)
    if [[ -n "$cpu_temp" ]]; then
        # Check if temperature is high (above 80°C is generally considered high)
        local temp_value=$(echo "$cpu_temp" | grep -oE "[0-9]+\.?[0-9]*" | head -1)
        local temp_warn=false
        if [[ -n "$temp_value" ]]; then
            local temp_whole="${temp_value%%.*}"
            local temp_frac="${temp_value#*.}"
            if [[ "$temp_whole" =~ ^[0-9]+$ ]]; then
                if (( temp_whole > 80 )); then
                    temp_warn=true
                elif (( temp_whole == 80 )) && [[ "$temp_frac" != "$temp_value" ]]; then
                    temp_frac="${temp_frac%%[^0-9]*}"
                    [[ -n "${temp_frac//0/}" ]] && temp_warn=true
                fi
            fi
        fi
        if [[ "$temp_warn" == true ]]; then
            # High temperature warning - print with color directly
            printf "│ %-20s: ${RED}%s ⚠${NC}\n" "$(get_label "cpu_temperature")" "$cpu_temp"
        else
            print_info "$(get_label "cpu_temperature")" "$cpu_temp"
        fi
    else
        # If no temperature detected, show message based on permissions
        if [[ $EUID -ne 0 ]]; then
            print_info "$(get_label "cpu_temperature")" "$(get_label "requires_root_sensors")"
        else
            print_info "$(get_label "cpu_temperature")" "$(get_label "not_detected")"
        fi
    fi

    JSON_CPU_KV=(
        "$(json_kv "model" "${cpu_model:-$(get_label "no_info")}")"
        "$(json_kv "cores" "${cpu_cores:-$(get_label "no_info")}")"
        "$(json_kv "threads" "${cpu_threads:-$(get_label "no_info")}")"
        "$(json_kv "frequency" "${cpu_freq:+${cpu_freq} MHz}")"
        "$(json_kv "cache" "${cpu_cache:-$(get_label "no_info")}")"
        "$(json_kv "usage" "$cpu_usage_val")"
        "$(json_kv "temperature" "$cpu_temp")"
    )

    echo "└$(repeat_char '─' 50)"
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

    local module_kv=(
        "$(json_kv "size" "$size")"
        "$(json_kv "type" "$type")"
        "$(json_kv "frequency" "$speed")"
        "$(json_kv "manufacturer" "$manufacturer")"
        "$(json_kv "serial_number" "$display_sn")"
        "$(json_kv "model" "$part_number")"
    )
    JSON_RAM_MODULES+=("$(json_obj "${module_kv[@]}")")
}

collect_ram_info() {
    local mem_total="" mem_available="" mem_used=""

    IFS=$'\t' read -r mem_total mem_available < <(
        awk '
            /MemTotal/ {total=$2}
            /MemAvailable/ {avail=$2}
            END {printf "%.2f GB\t%.2f GB", total/1024/1024, avail/1024/1024}
        ' /proc/meminfo 2>/dev/null
    )
    mem_used=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3; exit}')

    RAM_TOTAL="$mem_total"
    RAM_USED="$mem_used"
    RAM_AVAILABLE="$mem_available"
    RAM_MODULE_ROWS=()
    RAM_FALLBACK_LINES=()
    RAM_HAS_DETAILED_MODULES=false

    JSON_RAM_KV=(
        "$(json_kv "total" "$RAM_TOTAL")"
        "$(json_kv "used" "$RAM_USED")"
        "$(json_kv "available" "$RAM_AVAILABLE")"
    )
    JSON_RAM_MODULES=()

    if command -v dmidecode >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        local temp_file=""
        temp_file=$(mktemp 2>/dev/null) || return
        RAM_HAS_DETAILED_MODULES=true
        TEMP_FILES+=("$temp_file")
        dmidecode -t memory 2>/dev/null > "$temp_file"

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
                elif [[ "$line" =~ ^[[:space:]]*Serial\ Number:[[:space:]]*(.*) ]]; then
                    serial_number="${BASH_REMATCH[1]}"
                fi
            fi
        done < "$temp_file"

        ram_add_module "$size" "$type" "$speed" "$manufacturer" "$serial_number" "$part_number"
        return
    fi

    RAM_FALLBACK_LINES+=("Root privileges required for detailed memory information")

    if command -v lshw >/dev/null 2>&1; then
        RAM_FALLBACK_LINES+=("Alternative detection using lshw:")

        local lshw_output=""
        if [[ $EUID -eq 0 ]]; then
            lshw_output=$(lshw -c memory 2>/dev/null)
        elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            lshw_output=$(sudo -n lshw -c memory 2>/dev/null)
        else
            lshw_output=$(lshw -c memory 2>/dev/null)
        fi

        while IFS= read -r line; do
            [[ -n "$line" ]] && RAM_FALLBACK_LINES+=("$line")
        done < <(printf '%s\n' "$lshw_output" | grep -A5 -B1 "bank\|slot\|DIMM" | grep -E "description:|size:|clock:")
    fi

    if command -v dmidecode >/dev/null 2>&1; then
        RAM_FALLBACK_LINES+=("Attempting dmidecode (may fail without root):")
        while IFS= read -r line; do
            [[ -n "$line" ]] && RAM_FALLBACK_LINES+=("$line")
        done < <(dmidecode -t 17 2>/dev/null | grep -E "Size:|Type:|Speed:|Manufacturer:" | head -20)
    fi
}

render_ram_info() {
    print_subsection "$(get_label "ram_info")"

    print_info_colored "$(get_label "total")" "$RAM_TOTAL" "$CYAN"
    print_info_colored "$(get_label "used")" "$RAM_USED" "$YELLOW"
    print_info_colored "$(get_label "available")" "$RAM_AVAILABLE" "$GREEN"

    echo "│"
    [[ "$LANG_MODE" == "cn" ]] && print_color "$GREEN" "│ 内存模组:" || print_color "$GREEN" "│ Memory Modules:"

    if [[ "$RAM_HAS_DETAILED_MODULES" == true ]]; then
        local w1=8 w2=6 w3=12 w4=12 w5=16 w6=22
        TABLE_COL_W=($w1 $w2 $w3 $w4 $w5 $w6)
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

    echo "└$(repeat_char '─' 50)"
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

    rest="${line#*${key}=\"}"
    if [[ "$rest" == "$line" ]]; then
        printf -v "$out_var" ''
    else
        printf -v "$out_var" '%s' "${rest%%\"*}"
    fi
}

get_cpu_platform_info() {
    print_subsection "$(get_label "platform_info")"

    JSON_PLATFORM_KV=()
    JSON_PLATFORM_VULNERABILITIES=()

    local microcode=""
    local virtualization="No"
    local numa_nodes=""
    local sockets=""
    local governor=""
    local turbo_status=""
    local lscpu_output=""

    [[ -r /proc/cpuinfo ]] && microcode=$(awk -F': ' '/microcode/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)

    if grep -m1 -qwE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
        virtualization="Yes"
    fi

    if command -v lscpu >/dev/null 2>&1; then
        lscpu_output=$(lscpu 2>/dev/null)
        numa_nodes=$(printf '%s\n' "$lscpu_output" | awk -F: '/^NUMA node\(s\):/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
        sockets=$(printf '%s\n' "$lscpu_output" | awk -F: '/^Socket\(s\):/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
    fi

    if compgen -G "/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor" >/dev/null 2>&1; then
        governor=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
    fi

    if [[ -r /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
        if [[ "$(< /sys/devices/system/cpu/intel_pstate/no_turbo)" == "1" ]]; then
            turbo_status="Disabled"
        else
            turbo_status="Enabled"
        fi
    elif [[ -r /sys/devices/system/cpu/cpufreq/boost ]]; then
        if [[ "$(< /sys/devices/system/cpu/cpufreq/boost)" == "1" ]]; then
            turbo_status="Enabled"
        else
            turbo_status="Disabled"
        fi
    fi

    print_info "Platform" "${sockets:-?} socket(s), ${numa_nodes:-?} NUMA node(s)"
    print_info "Virtualization" "$virtualization"
    [[ -n "$microcode" ]] && print_info "Microcode" "$microcode"

    [[ -n "$microcode" ]] && JSON_PLATFORM_KV+=("$(json_kv "microcode" "$microcode")")
    JSON_PLATFORM_KV+=("$(json_kv "virtualization" "$virtualization")")
    [[ -n "$sockets" ]] && JSON_PLATFORM_KV+=("$(json_kv "sockets" "$sockets")")
    [[ -n "$numa_nodes" ]] && JSON_PLATFORM_KV+=("$(json_kv "numa_nodes" "$numa_nodes")")
    [[ -n "$governor" ]] && JSON_PLATFORM_KV+=("$(json_kv "governor" "$governor")")
    [[ -n "$turbo_status" ]] && JSON_PLATFORM_KV+=("$(json_kv "turbo_boost" "$turbo_status")")

    echo "└$(repeat_char '─' 50)"
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
    print_subsection "$(get_label "nvme_deep_info")"

    JSON_NVME_DEEP=()

    if ! command -v nvme >/dev/null 2>&1; then
        print_info "$(get_label "status")" "nvme-cli not installed"
        echo "└$(repeat_char '─' 50)"
        return
    fi

    local nvme_disks=()
    local disk=""
    if command -v lsblk >/dev/null 2>&1; then
        while IFS= read -r disk; do
            [[ "$disk" =~ ^nvme[0-9]+n[0-9]+$ ]] && nvme_disks+=("$disk")
        done < <(lsblk -d -n -o NAME 2>/dev/null)
    fi
    if [[ ${#nvme_disks[@]} -eq 0 ]]; then
        for disk in /dev/nvme*n*; do
            [[ -e "$disk" ]] || continue
            nvme_disks+=("${disk##*/}")
        done
    fi

    if [[ ${#nvme_disks[@]} -eq 0 ]]; then
        print_info "$(get_label "status")" "$(get_label "not_detected")"
        echo "└$(repeat_char '─' 50)"
        return
    fi

    local nvme_checked=0
    local nvme_warn_count=0
    local nvme_warn_lines=()
    local unsafe_summary=()
    local -a nvme_rows=()
    local sep=$'\t'

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

        smart_json=$(run_limited 6 nvme smart-log -o json "$dev" 2>/dev/null || true)
        error_json=$(run_limited 6 nvme error-log -e 8 -o json "$dev" 2>/dev/null || true)
        id_json=$(run_limited 6 nvme id-ctrl -o json "$controller_dev" 2>/dev/null || run_limited 6 nvme id-ctrl -o json "$dev" 2>/dev/null || true)

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

        local nvme_status="OK"
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

        # Row for the table
        local temp_disp="-" used_disp="-" spare_disp="-"
        [[ -n "$temperature_c" ]] && temp_disp="${temperature_c}°C"
        [[ -n "$percentage_used" ]] && used_disp="${percentage_used}%"
        [[ -n "$available_spare" ]] && spare_disp="${available_spare}%"
        nvme_rows+=("${dev}${sep}${model:-Unknown}${sep}${temp_disp}${sep}${used_disp}${sep}${spare_disp}${sep}${nvme_status}")

        [[ "$unsafe_shutdowns" =~ ^[0-9]+$ && "$unsafe_shutdowns" -gt 0 ]] && unsafe_summary+=("${disk}=$unsafe_shutdowns")
        if [[ "$nvme_status" == "WARN" ]]; then
            ((nvme_warn_count++))
            nvme_warn_lines+=("${dev}${sep}${nvme_warn[*]}")
        fi

        if [[ "$COLLECT_JSON" == true ]]; then
            nvme_kv=(
                "$(json_kv "device" "$dev")"
            )
            [[ -n "$controller_dev" ]] && nvme_kv+=("$(json_kv "controller" "$controller_dev")")
            [[ -n "$model" ]] && nvme_kv+=("$(json_kv "model" "$model")")
            [[ -n "$serial" ]] && nvme_kv+=("$(json_kv "serial" "$serial")")
            [[ -n "$firmware" ]] && nvme_kv+=("$(json_kv "firmware" "$firmware")")
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
    local w_dev=14 w_model=26 w_temp=7 w_used=7 w_spare=7 w_st=7
    TABLE_COL_W=($w_dev $w_model $w_temp $w_used $w_spare $w_st)
    if [[ "$LANG_MODE" == "cn" ]]; then
        table_header "设备" "型号" "温度" "耐久" "备用" "状态"
    else
        table_header "Device" "Model" "Temp" "Used" "Spare" "Status"
    fi
    local r="" d="" m="" t="" u="" sp="" st="" stc=""
    for r in "${nvme_rows[@]}"; do
        IFS="$sep" read -r d m t u sp st <<< "$r"
        stc="$GREEN"; [[ "$st" == "WARN" ]] && stc="$YELLOW"
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
        printf "│   %bℹ %s: %s%b\n" "$CYAN" "$us_label" "${unsafe_summary[*]}" "$NC"
    fi

    echo "└$(repeat_char '─' 50)"
}


# Helper function: Extract value from JSON using basic pattern matching
# Usage: json_extract "key" "$json_string"
json_extract() {
    local key="$1"
    local json="$2"
    echo "$json" | grep -oP "\"$key\"\s*:\s*\K[0-9]+" | head -1
}

# Helper function: Extract string value from JSON
json_extract_string() {
    local key="$1"
    local json="$2"
    echo "$json" | grep -oP "\"$key\"\s*:\s*\"\K[^\"]*" | head -1
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

smart_json_summary_tsv() {
    local json="$1"

    command -v jq >/dev/null 2>&1 || return 1
    jq -r '
        def s($v): if $v == null then "" else ($v | tostring) end;
        def table: (.ata_smart_attributes.table // []);
        def raw_by_id($ids):
            ([table[]? | select(.id as $id | $ids | index($id)) | .raw.value] | first) // "";
        def raw_by_name($re):
            ([table[]? | select((.name // "") | test($re; "i")) | .raw.value] | first) // "";
        def value_by_id($ids):
            ([table[]? | select(.id as $id | $ids | index($id)) | .value] | first) // "";
        def value_by_name($re):
            ([table[]? | select((.name // "") | test($re; "i")) | .value] | first) // "";
        def written_candidate:
            (raw_by_id([241,246])) as $lba512 |
            if (s($lba512) != "") then [$lba512, 512]
            else (raw_by_id([248])) as $id32 |
                if (s($id32) != "") then [$id32, 33554432]
                else (raw_by_name("Total_Writes_32MiB|Host_Writes_32MiB")) as $name32 |
                    if (s($name32) != "") then [$name32, 33554432]
                    else (raw_by_name("Host_Writes_MiB")) as $name_mib |
                        if (s($name_mib) != "") then [$name_mib, 1048576]
                        else ["", 512]
                        end
                    end
                end
            end;
        def read_candidate:
            (raw_by_id([242])) as $lba512 |
            if (s($lba512) != "") then [$lba512, 512]
            else (raw_by_id([247])) as $id32 |
                if (s($id32) != "") then [$id32, 33554432]
                else (raw_by_name("Total_Reads_32MiB|Host_Reads_32MiB")) as $name32 |
                    if (s($name32) != "") then [$name32, 33554432]
                    else (raw_by_name("Host_Reads_MiB")) as $name_mib |
                        if (s($name_mib) != "") then [$name_mib, 1048576]
                        else ["", 512]
                        end
                    end
                end
            end;
        def wear_candidate:
            (value_by_id([177,231,233])) as $wear |
            if (s($wear) != "") then $wear
            else value_by_name("Wear_Leveling_Count|SSD_Life_Left|Media_Wearout_Indicator")
            end;
        (written_candidate) as $written |
        (read_candidate) as $read |
        [
            ["smart_status", s(.smart_status.passed)],
            ["temperature", s(.temperature.current)],
            ["power_on_hours", s(.power_on_time.hours)],
            ["model_family", s(.model_family)],
            ["data_units_read", s(.nvme_smart_health_information_log.data_units_read // .data_units_read)],
            ["data_units_written", s(.nvme_smart_health_information_log.data_units_written // .data_units_written)],
            ["percentage_used", s(.nvme_smart_health_information_log.percentage_used // .percentage_used)],
            ["available_spare", s(.nvme_smart_health_information_log.available_spare // .available_spare)],
            ["critical_warning", s(.nvme_smart_health_information_log.critical_warning // .critical_warning)],
            ["lba_written", s($written[0])],
            ["write_multiplier", s($written[1])],
            ["lba_read", s($read[0])],
            ["read_multiplier", s($read[1])],
            ["wear_level", s(wear_candidate)]
        ][] | @tsv
    ' 2>/dev/null <<< "$json"
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

smart_json_bad_blocks_tsv() {
    local json="$1"

    command -v jq >/dev/null 2>&1 || return 1
    jq -r '
        def s($v): if $v == null then "" else ($v | tostring) end;
        def table: (.ata_smart_attributes.table // []);
        def raw_by_id($id):
            ([table[]? | select(.id == $id) | .raw.value] | first) // "";
        [
            ["grown_defects", s(.scsi_grown_defect_list)],
            ["read_uncorrected", s(.scsi_error_counter_log.read.total_uncorrected_errors)],
            ["write_uncorrected", s(.scsi_error_counter_log.write.total_uncorrected_errors)],
            ["verify_uncorrected", s(.scsi_error_counter_log.verify.total_uncorrected_errors)],
            ["non_medium_errors", s(.scsi_error_counter_log.non_medium_error_count)],
            ["reallocated_sectors", s(raw_by_id(5))],
            ["pending_sectors", s(raw_by_id(197))],
            ["offline_uncorrectable", s(raw_by_id(198))],
            ["reported_uncorrect", s(raw_by_id(187))]
        ][] | @tsv
    ' 2>/dev/null <<< "$json"
}

# Function to check if a disk is a RAID controller virtual disk
is_raid_controller_disk() {
    local disk="$1"
    local json="$2"

    # Check if SMART is not available (common for RAID controllers)
    local smart_available=$(json_query '.smart_support.available' "$json" || true)
    [[ -z "$smart_available" ]] && smart_available=$(echo "$json" | grep -oP '"smart_support"\s*:\s*\{[^}]*"available"\s*:\s*\K(true|false)' | head -1)

    # Check for known RAID controller vendors
    local scsi_vendor=$(json_query '.scsi_vendor' "$json" || true)
    local scsi_product=$(json_query '.scsi_product' "$json" || true)
    [[ -z "$scsi_vendor" ]] && scsi_vendor=$(echo "$json" | grep -oP '"scsi_vendor"\s*:\s*"\K[^"]*' | head -1)
    [[ -z "$scsi_product" ]] && scsi_product=$(echo "$json" | grep -oP '"scsi_product"\s*:\s*"\K[^"]*' | head -1)

    # RAID controller patterns: AVAGO (MegaRAID), LSI, DELL PERC, HP Smart Array, etc.
    if [[ "$smart_available" == "false" ]]; then
        case "$scsi_vendor" in
            AVAGO|LSI|"DELL"|"HP"|"Adaptec"|"3ware")
                return 0  # Is a RAID controller
                ;;
        esac
        # Also check product name for MegaRAID patterns
        if [[ "$scsi_product" =~ MR[0-9]|PERC|SmartArray|RAID|Logical ]]; then
            return 0  # Is a RAID controller
        fi
    fi

    return 1  # Not a RAID controller
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
        smartctl_version=$(smartctl --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$smartctl_version" ]]; then
            SMARTCTL_VERSION_MAJOR="${smartctl_version%%.*}"
        fi
    fi

    SMARTCTL_VERSION_CHECKED=true
}

# Cached smartctl --scan output to avoid repeated scans
get_smartctl_scan() {
    if [[ "$SMARTCTL_SCAN_DONE" == true ]]; then
        SMARTCTL_SCAN_RESULT="$SMARTCTL_SCAN_CACHE"
        return
    fi

    if command -v smartctl >/dev/null 2>&1; then
        SMARTCTL_SCAN_CACHE=$(run_smartctl --scan 2>/dev/null)
    else
        SMARTCTL_SCAN_CACHE=""
    fi

    SMARTCTL_SCAN_DONE=true
    SMARTCTL_SCAN_RESULT="$SMARTCTL_SCAN_CACHE"
}

# Function to get RAID member disks from smartctl --scan
# Supports: megaraid (LSI/AVAGO), cciss (HP Smart Array), 3ware, areca
get_raid_member_devices() {
    local parent_disk="$1"
    local devices=()

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
        local device="${line%% *}"
        if [[ "$line" =~ megaraid,([0-9]+) ]]; then
            local raid_id="${BASH_REMATCH[1]}"
            devices+=("$device:megaraid:$raid_id")
        elif [[ "$line" =~ cciss,([0-9]+) ]]; then
            local raid_id="${BASH_REMATCH[1]}"
            devices+=("$device:cciss:$raid_id")
        elif [[ "$line" =~ 3ware,([0-9]+) ]]; then
            local raid_id="${BASH_REMATCH[1]}"
            devices+=("$device:3ware:$raid_id")
        elif [[ "$line" =~ areca,([0-9]+) ]]; then
            local raid_id="${BASH_REMATCH[1]}"
            devices+=("$device:areca:$raid_id")
        fi
    done <<< "$scan_output"

    RAID_MEMBER_CACHE=$(printf '%s\n' "${devices[@]}")
    RAID_MEMBER_CACHE_READY=true

    RAID_MEMBER_RESULT="$RAID_MEMBER_CACHE"
}

# Function to get unique RAID controller device paths

# Backward compatibility alias
get_megaraid_devices() {
    get_raid_member_devices "$@"
    [[ -n "$RAID_MEMBER_RESULT" ]] && printf '%s\n' "$RAID_MEMBER_RESULT"
}

# Function to get SMART JSON for RAID member device
# Supports: megaraid, cciss, 3ware, areca
get_smart_json_raid() {
    local device="$1"
    local raid_type="$2"
    local raid_id="$3"
    local json_output=""
    local cache_key="${device}|${raid_type}|${raid_id}"

    if [[ "${SMART_JSON_RAID_CACHE_READY[$cache_key]}" == "1" ]]; then
        SMART_JSON_RAID_RESULT="${SMART_JSON_RAID_CACHE[$cache_key]}"
        return
    fi

    json_output=$(run_smartctl -a --json=c -d "$raid_type","$raid_id" "$device" 2>/dev/null)

    if [[ -n "$json_output" ]] && echo "$json_output" | grep -q '"json_format_version"'; then
        SMART_JSON_RAID_CACHE[$cache_key]="$json_output"
        SMART_JSON_RAID_CACHE_READY[$cache_key]=1
        SMART_JSON_RAID_RESULT="$json_output"
    else
        SMART_JSON_RAID_CACHE[$cache_key]=""
        SMART_JSON_RAID_CACHE_READY[$cache_key]=1
        SMART_JSON_RAID_RESULT=""
    fi
}

# Backward compatibility alias
get_smart_json_megaraid() {
    local device="$1"
    local megaraid_id="$2"
    get_smart_json_raid "$device" "megaraid" "$megaraid_id"
    [[ -n "$SMART_JSON_RAID_RESULT" ]] && printf '%s\n' "$SMART_JSON_RAID_RESULT"
}

# ==========================================================================
# Universal Bad Blocks Detection Function
# ==========================================================================
# This function detects and displays disk defects from either JSON or text input.
# It checks ALL available fields regardless of drive type (SAS or SATA).
#
# Usage:
#   detect_bad_blocks "json" "$json_data"     # For JSON input
#   detect_bad_blocks "text" "$smart_text"    # For text input
#
# Detected fields:
#   SAS/SCSI: scsi_grown_defect_list, total_uncorrected_errors, non_medium_error_count
#   SATA/ATA: Reallocated_Sector_Ct, Current_Pending_Sector, Offline_Uncorrectable, Reported_Uncorrect
# ==========================================================================
detect_bad_blocks() {
    local input_type="$1"  # "json" or "text"
    local data="$2"

    if [[ -z "$data" ]]; then
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

    if [[ "$input_type" == "json" ]]; then
        # ==========================================================================
        # JSON Parsing
        # ==========================================================================
        
        # Try to extract ALL fields with one jq process.
        if command -v jq >/dev/null 2>&1; then
            local key="" value=""
            while IFS=$'\t' read -r key value; do
                case "$key" in
                    grown_defects) grown_defects="$value" ;;
                    read_uncorrected) read_uncorrected="$value" ;;
                    write_uncorrected) write_uncorrected="$value" ;;
                    verify_uncorrected) verify_uncorrected="$value" ;;
                    non_medium_errors) non_medium_errors="$value" ;;
                    reallocated_sectors) reallocated_sectors="$value" ;;
                    pending_sectors) pending_sectors="$value" ;;
                    offline_uncorrectable) offline_uncorrectable="$value" ;;
                    reported_uncorrect) reported_uncorrect="$value" ;;
                esac
            done < <(smart_json_bad_blocks_tsv "$data")
        fi

        # Fallback to grep for SAS/SCSI fields
        if [[ -z "$grown_defects" || "$grown_defects" == "null" ]]; then
            grown_defects=$(echo "$data" | grep -oP '"scsi_grown_defect_list"\s*:\s*\K[0-9]+' | head -1)
        fi
        if [[ -z "$read_uncorrected" || "$read_uncorrected" == "null" ]]; then
            read_uncorrected=$(echo "$data" | grep -A5 '"read"' | grep -oP '"total_uncorrected_errors"\s*:\s*\K[0-9]+' | head -1)
        fi
        if [[ -z "$write_uncorrected" || "$write_uncorrected" == "null" ]]; then
            write_uncorrected=$(echo "$data" | grep -A5 '"write"' | grep -oP '"total_uncorrected_errors"\s*:\s*\K[0-9]+' | head -1)
        fi
        if [[ -z "$verify_uncorrected" || "$verify_uncorrected" == "null" ]]; then
            verify_uncorrected=$(echo "$data" | grep -A5 '"verify"' | grep -oP '"total_uncorrected_errors"\s*:\s*\K[0-9]+' | head -1)
        fi
        if [[ -z "$non_medium_errors" || "$non_medium_errors" == "null" ]]; then
            non_medium_errors=$(echo "$data" | grep -oP '"non_medium_error_count"\s*:\s*\K[0-9]+' | head -1)
        fi

        # Fallback to grep for SATA/ATA fields
        if [[ -z "$reallocated_sectors" || "$reallocated_sectors" == "null" ]]; then
            reallocated_sectors=$(echo "$data" | grep -A20 '"Reallocated_Sector_Ct"' | grep -oP '"raw"\s*:\s*\{\s*"value"\s*:\s*\K[0-9]+' | head -1)
        fi
        if [[ -z "$pending_sectors" || "$pending_sectors" == "null" ]]; then
            pending_sectors=$(echo "$data" | grep -A20 '"Current_Pending_Sector"' | grep -oP '"raw"\s*:\s*\{\s*"value"\s*:\s*\K[0-9]+' | head -1)
        fi
        if [[ -z "$offline_uncorrectable" || "$offline_uncorrectable" == "null" ]]; then
            offline_uncorrectable=$(echo "$data" | grep -A20 '"Offline_Uncorrectable"' | grep -oP '"raw"\s*:\s*\{\s*"value"\s*:\s*\K[0-9]+' | head -1)
        fi
        if [[ -z "$reported_uncorrect" || "$reported_uncorrect" == "null" ]]; then
            reported_uncorrect=$(echo "$data" | grep -A20 '"Reported_Uncorrect"' | grep -oP '"raw"\s*:\s*\{\s*"value"\s*:\s*\K[0-9]+' | head -1)
        fi

    else
        # ==========================================================================
        # Text Parsing
        # ==========================================================================
        
        # SAS/SCSI style fields
        grown_defects=$(echo "$data" | grep -i "Elements in grown defect list" | grep -oE '[0-9]+' | head -1)
        read_uncorrected=$(echo "$data" | grep -A2 "^read:" | grep -oE '[0-9]+$' | tail -1)
        write_uncorrected=$(echo "$data" | grep -A2 "^write:" | grep -oE '[0-9]+$' | tail -1)
        verify_uncorrected=$(echo "$data" | grep -A2 "^verify:" | grep -oE '[0-9]+$' | tail -1)
        non_medium_errors=$(echo "$data" | grep -i "Non-medium error count" | grep -oE '[0-9]+' | head -1)

        # SATA/ATA style fields (SMART attributes)
        reallocated_sectors=$(echo "$data" | grep -i "Reallocated_Sector_Ct" | awk '{print $NF}')
        pending_sectors=$(echo "$data" | grep -i "Current_Pending_Sector" | awk '{print $NF}')
        offline_uncorrectable=$(echo "$data" | grep -i "Offline_Uncorrectable" | awk '{print $NF}')
        reported_uncorrect=$(echo "$data" | grep -i "Reported_Uncorrect" | awk '{print $NF}')
    fi

    # ==========================================================================
    # Display all available bad block fields
    # ==========================================================================

    # SAS/SCSI: Grown Defect List
    if [[ -n "$grown_defects" && "$grown_defects" != "null" && "$grown_defects" =~ ^[0-9]+$ ]]; then
        disk_smart_add "grown_defects" "$grown_defects"
        if [[ "$grown_defects" -gt 0 ]]; then
            printf '%b\n' "│   $(get_label "grown_defects"): ${YELLOW}${grown_defects}${NC}"
        else
            echo "│   $(get_label "grown_defects"): ${grown_defects}"
        fi
    fi

    # SAS/SCSI: Uncorrected Errors (with breakdown)
    local has_uncorrected=false
    [[ -n "$read_uncorrected" && "$read_uncorrected" != "null" && "$read_uncorrected" =~ ^[0-9]+$ ]] && has_uncorrected=true
    [[ -n "$write_uncorrected" && "$write_uncorrected" != "null" && "$write_uncorrected" =~ ^[0-9]+$ ]] && has_uncorrected=true
    [[ -n "$verify_uncorrected" && "$verify_uncorrected" != "null" && "$verify_uncorrected" =~ ^[0-9]+$ ]] && has_uncorrected=true

    if [[ "$has_uncorrected" == true ]]; then
        local total_uncorrected=0
        [[ -n "$read_uncorrected" && "$read_uncorrected" != "null" && "$read_uncorrected" =~ ^[0-9]+$ ]] && total_uncorrected=$((total_uncorrected + read_uncorrected))
        [[ -n "$write_uncorrected" && "$write_uncorrected" != "null" && "$write_uncorrected" =~ ^[0-9]+$ ]] && total_uncorrected=$((total_uncorrected + write_uncorrected))
        [[ -n "$verify_uncorrected" && "$verify_uncorrected" != "null" && "$verify_uncorrected" =~ ^[0-9]+$ ]] && total_uncorrected=$((total_uncorrected + verify_uncorrected))

        [[ -n "$read_uncorrected" && "$read_uncorrected" != "null" && "$read_uncorrected" =~ ^[0-9]+$ ]] && disk_smart_add "read_uncorrected_errors" "$read_uncorrected"
        [[ -n "$write_uncorrected" && "$write_uncorrected" != "null" && "$write_uncorrected" =~ ^[0-9]+$ ]] && disk_smart_add "write_uncorrected_errors" "$write_uncorrected"
        [[ -n "$verify_uncorrected" && "$verify_uncorrected" != "null" && "$verify_uncorrected" =~ ^[0-9]+$ ]] && disk_smart_add "verify_uncorrected_errors" "$verify_uncorrected"
        disk_smart_add "uncorrected_errors" "$total_uncorrected"

        if [[ "$total_uncorrected" -gt 0 ]]; then
            printf '%b\n' "│   $(get_label "uncorrected_errors"): ${RED}${total_uncorrected}${NC} (R:${read_uncorrected:-0}/W:${write_uncorrected:-0}/V:${verify_uncorrected:-0})"
        else
            echo "│   $(get_label "uncorrected_errors"): 0 (R:${read_uncorrected:-0}/W:${write_uncorrected:-0}/V:${verify_uncorrected:-0})"
        fi
    fi

    # SAS/SCSI: Non-medium Errors
    if [[ -n "$non_medium_errors" && "$non_medium_errors" != "null" && "$non_medium_errors" =~ ^[0-9]+$ ]]; then
        disk_smart_add "non_medium_errors" "$non_medium_errors"
        if [[ "$non_medium_errors" != "0" ]]; then
            printf '%b\n' "│   $(get_label "non_medium_errors"): ${YELLOW}${non_medium_errors}${NC}"
        fi
    fi

    local has_bad_blocks_metric=false

    # SATA/ATA: Reallocated Sectors (ID 5)
    if [[ -n "$reallocated_sectors" && "$reallocated_sectors" != "null" && "$reallocated_sectors" =~ ^[0-9]+$ ]]; then
        has_bad_blocks_metric=true
        disk_smart_add "reallocated_sectors" "$reallocated_sectors"
        if [[ "$reallocated_sectors" -gt 0 ]]; then
            printf '%b\n' "│   $(get_label "reallocated_sectors"): ${YELLOW}${reallocated_sectors}${NC}"
        else
            echo "│   $(get_label "reallocated_sectors"): ${reallocated_sectors}"
        fi
    fi

    # SATA/ATA: Pending Sectors (ID 197)
    if [[ -n "$pending_sectors" && "$pending_sectors" != "null" && "$pending_sectors" =~ ^[0-9]+$ ]]; then
        has_bad_blocks_metric=true
        disk_smart_add "pending_sectors" "$pending_sectors"
        if [[ "$pending_sectors" -gt 0 ]]; then
            printf '%b\n' "│   $(get_label "pending_sectors"): ${YELLOW}${pending_sectors}${NC}"
        else
            echo "│   $(get_label "pending_sectors"): ${pending_sectors}"
        fi
    fi

    # SATA/ATA: Offline Uncorrectable (ID 198)
    if [[ -n "$offline_uncorrectable" && "$offline_uncorrectable" != "null" && "$offline_uncorrectable" =~ ^[0-9]+$ ]]; then
        has_bad_blocks_metric=true
        disk_smart_add "offline_uncorrectable" "$offline_uncorrectable"
        if [[ "$offline_uncorrectable" -gt 0 ]]; then
            printf '%b\n' "│   $(get_label "offline_uncorrectable"): ${YELLOW}${offline_uncorrectable}${NC}"
        else
            echo "│   $(get_label "offline_uncorrectable"): ${offline_uncorrectable}"
        fi
    fi

    # SATA/ATA: Reported Uncorrectable (ID 187)
    if [[ -n "$reported_uncorrect" && "$reported_uncorrect" != "null" && "$reported_uncorrect" =~ ^[0-9]+$ ]]; then
        disk_smart_add "reported_uncorrect" "$reported_uncorrect"
        if [[ "$reported_uncorrect" -gt 0 ]]; then
            printf '%b\n' "│   $(get_label "reported_uncorrect"): ${RED}${reported_uncorrect}${NC}"
        else
            echo "│   $(get_label "reported_uncorrect"): ${reported_uncorrect}"
        fi
    fi

    # Calculate and display total bad blocks summary (SATA style)
    local total_bad=0
    [[ -n "$reallocated_sectors" && "$reallocated_sectors" != "null" && "$reallocated_sectors" =~ ^[0-9]+$ ]] && total_bad=$((total_bad + reallocated_sectors))
    [[ -n "$pending_sectors" && "$pending_sectors" != "null" && "$pending_sectors" =~ ^[0-9]+$ ]] && total_bad=$((total_bad + pending_sectors))
    [[ -n "$offline_uncorrectable" && "$offline_uncorrectable" != "null" && "$offline_uncorrectable" =~ ^[0-9]+$ ]] && total_bad=$((total_bad + offline_uncorrectable))

    if [[ "$has_bad_blocks_metric" == true ]]; then
        disk_smart_add "bad_blocks" "$total_bad"
    fi

    if [[ "$total_bad" -gt 0 ]]; then
        printf '%b\n' "│   $(get_label "bad_blocks"): ${RED}${total_bad}${NC}"
    fi

    return 0
}

# Function to parse SAS/SCSI/SATA SMART data from JSON (for RAID member disks)
parse_smart_json_sas() {
    local json="$1"
    local disk_label="$2"

    if [[ -z "$json" ]]; then
        return 1
    fi

    # Detect if this is a SAS/SCSI or SATA disk
    local device_type=$(json_query '.device.type' "$json" || true)
    local protocol=$(json_query '.device.protocol' "$json" || true)
    [[ -z "$device_type" ]] && device_type=$(echo "$json" | grep -oP '"device"\s*:\s*\{[^}]*"type"\s*:\s*"\K[^"]*' | head -1)
    [[ -z "$protocol" ]] && protocol=$(echo "$json" | grep -oP '"device"\s*:\s*\{[^}]*"protocol"\s*:\s*"\K[^"]*' | head -1)

    # Extract basic info - try both SAS and SATA formats
    local vendor=$(json_query '.scsi_vendor' "$json" || true)
    local product=$(json_query '.scsi_product' "$json" || true)
    local model_name=$(json_query '.model_name' "$json" || true)
    local model_family=$(json_query '.model_family' "$json" || true)
    local serial=$(json_query '.serial_number' "$json" || true)
    local capacity_bytes=$(json_query '.user_capacity.bytes' "$json" || true)
    [[ -z "$vendor" ]] && vendor=$(echo "$json" | grep -oP '"scsi_vendor"\s*:\s*"\K[^"]*' | head -1)
    [[ -z "$product" ]] && product=$(echo "$json" | grep -oP '"scsi_product"\s*:\s*"\K[^"]*' | head -1)
    [[ -z "$model_name" ]] && model_name=$(echo "$json" | grep -oP '"model_name"\s*:\s*"\K[^"]*' | head -1)
    [[ -z "$model_family" ]] && model_family=$(echo "$json" | grep -oP '"model_family"\s*:\s*"\K[^"]*' | head -1)
    [[ -z "$serial" ]] && serial=$(echo "$json" | grep -oP '"serial_number"\s*:\s*"\K[^"]*' | head -1)
    [[ -z "$capacity_bytes" ]] && capacity_bytes=$(echo "$json" | grep -oP '"user_capacity"\s*:\s*\{[^}]*"bytes"\s*:\s*\K[0-9]+' | head -1)

    # Format capacity
    local capacity_formatted=""
    if [[ -n "$capacity_bytes" && "$capacity_bytes" != "0" ]]; then
        capacity_formatted=$(format_bytes "$capacity_bytes")
    fi

    # Display disk info
    if [[ -n "$vendor" && -n "$product" ]]; then
        echo "│   Model: $vendor $product"
        disk_extra_add "model" "$vendor $product"
    elif [[ -n "$model_name" ]]; then
        echo "│   Model: $model_name"
        disk_extra_add "model" "$model_name"
    fi
    if [[ -n "$model_family" ]]; then
        echo "│   Family: $model_family"
        disk_extra_add "family" "$model_family"
    fi
    if [[ -n "$serial" ]]; then
        echo "│   Serial: $serial"
        disk_extra_add "serial" "$serial"
    fi
    if [[ -n "$capacity_formatted" ]]; then
        echo "│   Capacity: $capacity_formatted"
        disk_extra_add "capacity" "$capacity_formatted"
    fi

    # SMART status - check for smart_status.passed
    local smart_passed=$(json_query '.smart_status.passed' "$json" || true)
    [[ -z "$smart_passed" ]] && smart_passed=$(echo "$json" | grep -oP '"smart_status"\s*:\s*\{[^}]*"passed"\s*:\s*\K(true|false)' | head -1)
    if [[ -z "$smart_passed" ]]; then
        # Try alternative method: check scsi_grown_defect_list element count
        local defect_count=$(json_query '.scsi_grown_defect_list' "$json" || true)
        [[ -z "$defect_count" ]] && defect_count=$(echo "$json" | grep -oP '"scsi_grown_defect_list"\s*:\s*\K[0-9]+' | head -1)
        if [[ -n "$defect_count" && "$defect_count" == "0" ]]; then
            smart_passed="true"
        fi
    fi

    if [[ "$smart_passed" == "true" ]]; then
        echo "│   $(get_label "smart_status"): PASSED"
        disk_smart_add "smart_status" "PASSED"
    elif [[ "$smart_passed" == "false" ]]; then
        echo "│   $(get_label "smart_status"): ${RED}FAILED${NC}"
        disk_smart_add "smart_status" "FAILED"
    else
        echo "│   $(get_label "smart_status"): $(get_label "no_info")"
    fi

    # Temperature
    local temperature=$(json_query '.temperature.current' "$json" || true)
    [[ -z "$temperature" ]] && temperature=$(echo "$json" | grep -oP '"temperature"\s*:\s*\{[^}]*"current"\s*:\s*\K[0-9]+' | head -1)
    if [[ -n "$temperature" && "$temperature" != "0" ]]; then
        echo "│   $(get_label "temperature"): ${temperature}°C"
        disk_smart_add "temperature" "${temperature}°C"
    fi

    # Power on hours - try multiple formats
    local power_on_hours=$(json_query '.power_on_time.hours' "$json" || true)
    [[ -z "$power_on_hours" ]] && power_on_hours=$(echo "$json" | grep -oP '"power_on_time"\s*:\s*\{[^}]*"hours"\s*:\s*\K[0-9]+' | head -1)
    if [[ -n "$power_on_hours" ]]; then
        echo "│   $(get_label "power_on_hours"): ${power_on_hours} hours"
        disk_smart_add "power_on_hours" "$power_on_hours"
    fi

    # ==========================================================================
    # Bad Blocks / Defect Detection for RAID member disks
    # ==========================================================================
    # Call the universal bad blocks detection function with JSON input
    # ==========================================================================
    detect_bad_blocks "json" "$json"

    return 0
}

# Function to display RAID member disks (supports megaraid, cciss, 3ware, areca)
# Parameters:
#   $1 - parent_disk (unused, kept for compatibility)
#   $2 - controller_device (optional): Only show disks from this controller (e.g., /dev/bus/6)

# Function to get SMART data using JSON output (smartctl 7.0+)
get_smart_json() {
    local disk="$1"
    local json_output=""

    if [[ "${SMART_JSON_CACHE_READY[$disk]}" == "1" ]]; then
        SMART_JSON_RESULT="${SMART_JSON_CACHE[$disk]}"
        return
    fi

    # Try to get JSON output from smartctl
    json_output=$(run_smartctl -a --json=c "/dev/$disk" 2>/dev/null)

    # Check if JSON output is valid
    if [[ -n "$json_output" ]] && echo "$json_output" | grep -q '"json_format_version"'; then
        SMART_JSON_CACHE[$disk]="$json_output"
        SMART_JSON_CACHE_READY[$disk]=1
        SMART_JSON_RESULT="$json_output"
    else
        SMART_JSON_CACHE[$disk]=""
        SMART_JSON_CACHE_READY[$disk]=1
        SMART_JSON_RESULT=""
    fi
}

prefetch_smart_json_for_disks() {
    local disk=""
    local tmp_file=""
    local pid=""
    local entry=""
    local json_output=""
    local -a pids=()
    local -a running_pids=()
    local disk_regex='^[sv]d[a-z]+$|^nvme[0-9]+n[0-9]+$|^mmcblk[0-9]+$'

    command -v smartctl >/dev/null 2>&1 || return

    for disk in "$@"; do
        [[ "$disk" =~ $disk_regex ]] || continue
        [[ "${SMART_JSON_CACHE_READY[$disk]}" == "1" ]] && continue

        tmp_file=$(mktemp 2>/dev/null) || continue
        TEMP_FILES+=("$tmp_file")

        ( run_smartctl -a --json=c "/dev/$disk" > "$tmp_file" 2>/dev/null ) &
        pid=$!
        pids+=("${pid}:${disk}:${tmp_file}")
        running_pids+=("$pid")

        if (( ${#running_pids[@]} >= SMARTCTL_PARALLEL )); then
            wait "${running_pids[0]}" 2>/dev/null || true
            running_pids=("${running_pids[@]:1}")
        fi
    done

    for pid in "${running_pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    for entry in "${pids[@]}"; do
        local cached_pid="" cached_disk="" cached_file=""
        IFS=: read -r cached_pid cached_disk cached_file <<< "$entry"

        if [[ -s "$cached_file" ]]; then
            json_output=$(<"$cached_file")
            if [[ -n "$json_output" ]] && grep -q '"json_format_version"' <<< "$json_output"; then
                SMART_JSON_CACHE[$cached_disk]="$json_output"
                SMART_JSON_CACHE_READY[$cached_disk]=1
                continue
            fi
        fi

        SMART_JSON_CACHE[$cached_disk]=""
        SMART_JSON_CACHE_READY[$cached_disk]=1
    done
}

# Function to parse SMART data from JSON
parse_smart_json() {
    local disk="$1"
    local json="$2"

    if [[ -z "$json" ]]; then
        return 1
    fi

    # Extract common/NVMe/ATA fields with one jq process when jq is available.
    local smart_status="" temperature="" power_on_hours="" model_family=""
    local data_units_read="" data_units_written=""
    local percentage_used="" available_spare="" critical_warning=""
    local lba_written="" lba_read="" write_multiplier=512 read_multiplier=512
    local wear_level=""

    if command -v jq >/dev/null 2>&1; then
        local key="" value=""
        while IFS=$'\t' read -r key value; do
            case "$key" in
                smart_status) smart_status="$value" ;;
                temperature) temperature="$value" ;;
                power_on_hours) power_on_hours="$value" ;;
                model_family) model_family="$value" ;;
                data_units_read) data_units_read="$value" ;;
                data_units_written) data_units_written="$value" ;;
                percentage_used) percentage_used="$value" ;;
                available_spare) available_spare="$value" ;;
                critical_warning) critical_warning="$value" ;;
                lba_written) lba_written="$value" ;;
                write_multiplier) [[ -n "$value" ]] && write_multiplier="$value" ;;
                lba_read) lba_read="$value" ;;
                read_multiplier) [[ -n "$value" ]] && read_multiplier="$value" ;;
                wear_level) wear_level="$value" ;;
            esac
        done < <(smart_json_summary_tsv "$json")
    fi

    [[ -z "$smart_status" ]] && smart_status=$(echo "$json" | grep -oP '"passed"\s*:\s*\K(true|false)' | head -1)
    [[ -z "$temperature" ]] && temperature=$(echo "$json" | grep -oP '"temperature"\s*:\s*\{\s*"current"\s*:\s*\K[0-9]+' | head -1)
    [[ -z "$power_on_hours" ]] && power_on_hours=$(echo "$json" | grep -oP '"power_on_time"\s*:\s*\{\s*"hours"\s*:\s*\K[0-9]+' | head -1)
    [[ -z "$model_family" ]] && model_family=$(echo "$json" | grep -oP '"model_family"\s*:\s*"\K[^"]*' | head -1)

    # SMART Status
    if [[ "$smart_status" == "true" ]]; then
        echo "│   $(get_label "smart_status"): PASSED"
        disk_smart_add "smart_status" "PASSED"
    elif [[ "$smart_status" == "false" ]]; then
        echo "│   $(get_label "smart_status"): ${RED}FAILED${NC}"
        disk_smart_add "smart_status" "FAILED"
    else
        echo "│   $(get_label "smart_status"): $(get_label "no_info")"
    fi

    # Power on hours
    if [[ -n "$power_on_hours" ]]; then
        echo "│   $(get_label "power_on_hours"): ${power_on_hours} hours"
        disk_smart_add "power_on_hours" "$power_on_hours"
    fi

    # Data transfer - check if NVMe
    if [[ "$disk" =~ nvme ]]; then
        # NVMe: data_units_read/written (each unit = 512 * 1000 bytes)
        [[ -z "$data_units_read" ]] && data_units_read=$(echo "$json" | grep -oP '"data_units_read"\s*:\s*\K[0-9]+' | head -1)
        [[ -z "$data_units_written" ]] && data_units_written=$(echo "$json" | grep -oP '"data_units_written"\s*:\s*\K[0-9]+' | head -1)

        if [[ -n "$data_units_read" && "$data_units_read" != "0" ]]; then
            local bytes_read=$((data_units_read * 512000))
            local formatted=$(format_bytes "$bytes_read")
            if [[ -n "$formatted" ]]; then
                echo "│   $(get_label "total_reads"): $formatted"
                disk_smart_add "total_reads" "$formatted"
            fi
        fi

        if [[ -n "$data_units_written" && "$data_units_written" != "0" ]]; then
            local bytes_written=$((data_units_written * 512000))
            local formatted=$(format_bytes "$bytes_written")
            if [[ -n "$formatted" ]]; then
                echo "│   $(get_label "total_writes"): $formatted"
                disk_smart_add "total_writes" "$formatted"
            fi
        fi

        # NVMe health info
        [[ -z "$percentage_used" ]] && percentage_used=$(echo "$json" | grep -oP '"percentage_used"\s*:\s*\K[0-9]+' | head -1)
        [[ -z "$available_spare" ]] && available_spare=$(echo "$json" | grep -oP '"available_spare"\s*:\s*\K[0-9]+' | head -1)
        [[ -z "$critical_warning" ]] && critical_warning=$(echo "$json" | grep -oP '"critical_warning"\s*:\s*\K[0-9]+' | head -1)

        if [[ -n "$percentage_used" ]]; then
            echo "│   $(get_label "percentage_used"): ${percentage_used}%"
            local health=$((100 - percentage_used))
            [[ $health -lt 0 ]] && health=0
            echo "│   $(get_label "health_status"): ${health}%"
            disk_smart_add "percentage_used" "$percentage_used"
            disk_smart_add "health_status" "$health"
        fi

        if [[ -n "$available_spare" ]]; then
            echo "│   $(get_label "available_spare"): ${available_spare}%"
            disk_smart_add "available_spare" "$available_spare"
        fi

        if [[ -n "$critical_warning" && "$critical_warning" != "0" ]]; then
            echo "│   $(get_label "critical_warning"): ${critical_warning}"
            disk_smart_add "critical_warning" "$critical_warning"
        fi
    else
        # SATA/HDD/SSD: Look for LBA counts in ata_smart_attributes
        # Different vendors use different attribute IDs:
        #   - ID 241: Total_LBAs_Written (most common)
        #   - ID 242: Total_LBAs_Read (most common)
        #   - ID 246: Total_LBAs_Written (some SSDs)
        #   - ID 247: Host_Reads_32MiB (some vendors)
        #   - ID 248: Host_Writes_32MiB (some vendors)
        #   - ID 233: Media_Wearout_Indicator (Intel SSDs, for wear level)
        # Fallback to grep if jq is unavailable or the compact extraction missed a vendor-specific name.
        if [[ -z "$lba_written" || "$lba_written" == "null" ]]; then
            # Try by attribute name patterns
            lba_written=$(echo "$json" | grep -A15 '"Total_LBAs_Written"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
            if [[ -z "$lba_written" ]]; then
                lba_written=$(echo "$json" | grep -A15 '"Total_Writes_32MiB"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
                [[ -n "$lba_written" ]] && write_multiplier=$((32 * 1024 * 1024))
            fi
            if [[ -z "$lba_written" ]]; then
                lba_written=$(echo "$json" | grep -A15 '"Host_Writes_32MiB"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
                [[ -n "$lba_written" ]] && write_multiplier=$((32 * 1024 * 1024))
            fi
            if [[ -z "$lba_written" ]]; then
                lba_written=$(echo "$json" | grep -A15 '"Host_Writes_MiB"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
                [[ -n "$lba_written" ]] && write_multiplier=$((1024 * 1024))
            fi
        fi

        if [[ -z "$lba_read" || "$lba_read" == "null" ]]; then
            lba_read=$(echo "$json" | grep -A15 '"Total_LBAs_Read"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
            if [[ -z "$lba_read" ]]; then
                lba_read=$(echo "$json" | grep -A15 '"Total_Reads_32MiB"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
                [[ -n "$lba_read" ]] && read_multiplier=$((32 * 1024 * 1024))
            fi
            if [[ -z "$lba_read" ]]; then
                lba_read=$(echo "$json" | grep -A15 '"Host_Reads_32MiB"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
                [[ -n "$lba_read" ]] && read_multiplier=$((32 * 1024 * 1024))
            fi
            if [[ -z "$lba_read" ]]; then
                lba_read=$(echo "$json" | grep -A15 '"Host_Reads_MiB"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
                [[ -n "$lba_read" ]] && read_multiplier=$((1024 * 1024))
            fi
        fi

        if [[ -n "$lba_read" && "$lba_read" != "0" && "$lba_read" != "null" ]]; then
            local bytes_read=$((lba_read * read_multiplier))
            local formatted=$(format_bytes "$bytes_read")
            if [[ -n "$formatted" ]]; then
                echo "│   $(get_label "total_reads"): $formatted"
                disk_smart_add "total_reads" "$formatted"
            fi
        fi

        if [[ -n "$lba_written" && "$lba_written" != "0" && "$lba_written" != "null" ]]; then
            local bytes_written=$((lba_written * write_multiplier))
            local formatted=$(format_bytes "$bytes_written")
            if [[ -n "$formatted" ]]; then
                echo "│   $(get_label "total_writes"): $formatted"
                disk_smart_add "total_writes" "$formatted"
            fi
        fi

        # Track if we found any I/O stats
        local io_stats_found=false
        [[ -n "$lba_read" && "$lba_read" != "0" && "$lba_read" != "null" ]] && io_stats_found=true
        [[ -n "$lba_written" && "$lba_written" != "0" && "$lba_written" != "null" ]] && io_stats_found=true

        # For SSDs without read/write stats, try to show wear level indicator
        if [[ "$io_stats_found" == false ]]; then
            if [[ -z "$wear_level" || "$wear_level" == "null" ]]; then
                wear_level=$(echo "$json" | grep -A10 '"Wear_Leveling_Count"\|"SSD_Life_Left"\|"Media_Wearout_Indicator"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
            fi
            if [[ -n "$wear_level" && "$wear_level" != "null" && "$wear_level" != "0" ]]; then
                echo "│   $(get_label "wear_level"): ${wear_level}%"
                disk_smart_add "wear_level" "$wear_level"
                io_stats_found=true
            fi
        fi

        # If no I/O stats found at all, show a note with help info
        if [[ "$io_stats_found" == false ]]; then
            # Check for known drive families that don't report I/O statistics
            # Toshiba MG series enterprise HDDs don't have ID 241/242 attributes
            local known_no_io_stats=false
            if [[ "$model_family" =~ Toshiba\ MG[0-9]+ACA ]]; then
                known_no_io_stats=true
            fi

            if [[ "$known_no_io_stats" == true ]]; then
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
        echo "│   $(get_label "temperature"): ${temperature}°C"
        disk_smart_add "temperature" "${temperature}°C"
    fi

    # ==========================================================================
    # Bad Blocks / Defect Detection
    # ==========================================================================
    # Call the universal bad blocks detection function with JSON input
    # ==========================================================================
    detect_bad_blocks "json" "$json"

    return 0
}

# Fallback: Parse SMART data from text output (for older smartctl)
parse_smart_text() {
    local disk="$1"

    local smart_all=$(run_smartctl -a "/dev/$disk" 2>/dev/null)
    if [[ -z "$smart_all" ]]; then
        return 1
    fi

    # SMART Status
    local smart_health=$(echo "$smart_all" | grep -E "SMART overall-health|SMART Health Status" | awk -F': ' '{print $2}')
    echo "│   $(get_label "smart_status"): ${smart_health:-$(get_label "no_info")}"
    [[ -n "$smart_health" ]] && disk_smart_add "smart_status" "$smart_health"

    # Power on hours
    local power_hours=""
    power_hours=$(echo "$smart_all" | grep -i "power.on" | grep -i hour | head -1 | grep -oE '[0-9,]+' | tr -d ',' | head -1)
    if [[ -n "$power_hours" ]]; then
        echo "│   $(get_label "power_on_hours"): ${power_hours} hours"
        disk_smart_add "power_on_hours" "$power_hours"
    fi

    # Temperature
    local temp=""
    temp=$(echo "$smart_all" | grep -iE "^Temperature:|Temperature_Celsius" | grep -oE '[0-9]+' | head -1)
    if [[ -n "$temp" ]]; then
        echo "│   $(get_label "temperature"): ${temp}°C"
        disk_smart_add "temperature" "${temp}°C"
    fi

    # NVMe specific
    if [[ "$disk" =~ nvme ]]; then
        # Data units (with human readable in parentheses)
        local reads=$(echo "$smart_all" | grep -i "Data Units Read" | grep -oE '\([^)]+\)' | tr -d '()' | head -1)
        local writes=$(echo "$smart_all" | grep -i "Data Units Written" | grep -oE '\([^)]+\)' | tr -d '()' | head -1)
        if [[ -n "$reads" ]]; then
            echo "│   $(get_label "total_reads"): $reads"
            disk_smart_add "total_reads" "$reads"
        fi
        if [[ -n "$writes" ]]; then
            echo "│   $(get_label "total_writes"): $writes"
            disk_smart_add "total_writes" "$writes"
        fi

        # Percentage used
        local pct_used=$(echo "$smart_all" | grep -i "Percentage Used" | grep -oE '[0-9]+' | head -1)
        if [[ -n "$pct_used" ]]; then
            echo "│   $(get_label "percentage_used"): ${pct_used}%"
            echo "│   $(get_label "health_status"): $((100 - pct_used))%"
            disk_smart_add "percentage_used" "$pct_used"
            disk_smart_add "health_status" "$((100 - pct_used))"
        fi

        # Available spare
        local spare=$(echo "$smart_all" | grep -i "Available Spare:" | grep -oE '[0-9]+' | head -1)
        if [[ -n "$spare" ]]; then
            echo "│   $(get_label "available_spare"): ${spare}%"
            disk_smart_add "available_spare" "$spare"
        fi
    fi

    # ==========================================================================
    # Bad Blocks Detection (Text Parsing Fallback)
    # ==========================================================================
    # Call the universal bad blocks detection function with text input
    # ==========================================================================
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
        if [[ "$LANG_MODE" == "cn" ]]; then
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
    local w_device=12 w_basic=34 w_smart=6 w_hours=8 w_temp=6 w_io=16 w_bad=9 w_note=20
    local table_width=$((w_device + w_basic + w_smart + w_hours + w_temp + w_io + w_bad + w_note + 23))

    if [[ "$LANG_MODE" == "cn" ]]; then
        print_color "$WHITE" "│ 磁盘摘要（坏块=重映射/待处理/离线不可纠正）"
        echo "├$(repeat_char '─' "$table_width")┤"
        printf "│ "
        print_fixed_cell "设备" "$w_device"; printf " │ "
        print_fixed_cell "基本信息" "$w_basic"; printf " │ "
        print_fixed_cell "SMART" "$w_smart"; printf " │ "
        print_fixed_cell "通电" "$w_hours"; printf " │ "
        print_fixed_cell "温度" "$w_temp"; printf " │ "
        print_fixed_cell "读写" "$w_io"; printf " │ "
        print_fixed_cell "坏块" "$w_bad"; printf " │ "
        print_fixed_cell "备注" "$w_note"; printf " │\n"
        echo "├$(repeat_char '─' "$table_width")┤"
    else
        print_color "$WHITE" "│ Disk Summary (defects=reallocated/pending/offline)"
        echo "├$(repeat_char '─' "$table_width")┤"
        printf "│ "
        print_fixed_cell "Device" "$w_device"; printf " │ "
        print_fixed_cell "Basic Info" "$w_basic"; printf " │ "
        print_fixed_cell "SMART" "$w_smart"; printf " │ "
        print_fixed_cell "Hours" "$w_hours"; printf " │ "
        print_fixed_cell "Temp" "$w_temp"; printf " │ "
        print_fixed_cell "I/O" "$w_io"; printf " │ "
        print_fixed_cell "Defects" "$w_bad"; printf " │ "
        print_fixed_cell "Notes" "$w_note"; printf " │\n"
        echo "├$(repeat_char '─' "$table_width")┤"
    fi
}

print_disk_summary_footer() {
    local w_device=12 w_basic=34 w_smart=6 w_hours=8 w_temp=6 w_io=16 w_bad=9 w_note=20
    local table_width=$((w_device + w_basic + w_smart + w_hours + w_temp + w_io + w_bad + w_note + 23))
    echo "└$(repeat_char '─' "$table_width")┘"
}

disk_summary_smart_color() {
    case "$DISK_SUMMARY_SMART" in
        PASS|PASSED|OK)
            printf '%s' "$GREEN"
            ;;
        FAIL|FAILED)
            printf '%s' "$RED"
            ;;
        -|"")
            printf '%s' "$YELLOW"
            ;;
        *)
            printf '%s' "$YELLOW"
            ;;
    esac
}

disk_summary_temp_color() {
    local temp="${DISK_SUMMARY_TEMP%%°*}"
    temp="${temp#+}"

    if ! disk_summary_is_uint "$temp"; then
        return
    fi

    if [[ "$temp" -ge 60 ]]; then
        printf '%s' "$RED"
    elif [[ "$temp" -ge 50 ]]; then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$GREEN"
    fi
}

disk_summary_bad_color() {
    local bad="$DISK_SUMMARY_BAD"

    [[ -z "$bad" || "$bad" == "-" ]] && return

    if [[ "$bad" =~ (^|[^0-9])[1-9][0-9]* ]]; then
        printf '%s' "$RED"
    else
        printf '%s' "$GREEN"
    fi
}

disk_summary_io_color() {
    local io="$DISK_SUMMARY_IO"

    [[ -z "$io" || "$io" == "-" ]] && return

    if [[ "$io" =~ 无统计|no\ stats|no\ I/O ]]; then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$CYAN"
    fi
}

disk_summary_note_color() {
    local note="$DISK_SUMMARY_NOTE"

    [[ -z "$note" || "$note" == "-" ]] && return

    if [[ "$note" =~ 失败|坏块|高温|严重|不可纠正|未校正|failed|bad|hot|critical|uncorrect|defect ]]; then
        printf '%s' "$RED"
    elif [[ "$note" =~ 无SMART|无读写统计|smartctl|no\ SMART|no\ I/O|missing ]]; then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$CYAN"
    fi
}

print_disk_summary_row() {
    local label="$1"
    local basic_info="$2"
    local w_device=12 w_basic=34 w_smart=6 w_hours=8 w_temp=6 w_io=16 w_bad=9 w_note=20
    local smart_color="" temp_color="" io_color="" bad_color="" note_color=""

    smart_color="$(disk_summary_smart_color)"
    temp_color="$(disk_summary_temp_color)"
    io_color="$(disk_summary_io_color)"
    bad_color="$(disk_summary_bad_color)"
    note_color="$(disk_summary_note_color)"

    printf "│ "
    print_colored_fixed_cell "$label" "$w_device" "$CYAN"; printf " │ "
    print_fixed_cell "$basic_info" "$w_basic"; printf " │ "
    print_colored_fixed_cell "$DISK_SUMMARY_SMART" "$w_smart" "$smart_color"; printf " │ "
    print_fixed_cell "$DISK_SUMMARY_HOURS" "$w_hours"; printf " │ "
    print_colored_fixed_cell "$DISK_SUMMARY_TEMP" "$w_temp" "$temp_color"; printf " │ "
    print_colored_fixed_cell "$DISK_SUMMARY_IO" "$w_io" "$io_color"; printf " │ "
    print_colored_fixed_cell "$DISK_SUMMARY_BAD" "$w_bad" "$bad_color"; printf " │ "
    print_colored_fixed_cell "$DISK_SUMMARY_NOTE" "$w_note" "$note_color"; printf " │\n"
}

# Function to get disk information with enhanced SMART data
# Display structure:
#   1. First: RAID controllers and their member disks (grouped by controller)
#   2. Then: Other disks (NVMe, non-RAID SATA/SAS, etc.)
get_disk_info() {
    print_subsection "$(get_label "disk_info")"

    JSON_DISKS=()
    JSON_RAID_CONTROLLERS=()

    # Filesystem usage table (mounted /dev/* filesystems)
    local -a fs_rows=()
    local fsep=$'\t'
    local fs sz used avail usep mnt rest
    while read -r fs sz used avail usep mnt rest; do
        [[ "$fs" == /dev/* ]] || continue
        fs_rows+=("${fs}${fsep}${sz}${fsep}${used}${fsep}${avail}${fsep}${usep}${fsep}${mnt}")
    done < <(df -hP 2>/dev/null)

    if [[ ${#fs_rows[@]} -gt 0 ]]; then
        [[ "$LANG_MODE" == "cn" ]] && print_color "$GREEN" "│ 已挂载文件系统:" || print_color "$GREEN" "│ Mounted Filesystems:"
        local w_fs=34 w_sz=7 w_used=7 w_avail=7 w_use=6 w_mnt=20
        TABLE_COL_W=($w_fs $w_sz $w_used $w_avail $w_use $w_mnt)
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
        get_smartctl_major_version
        [[ -n "$SMARTCTL_VERSION_MAJOR" && "$SMARTCTL_VERSION_MAJOR" -ge 7 ]] && use_json=true
    fi

    # Cache disk names and basic info to avoid one lsblk call per disk.
    local disk_names=()
    if command -v lsblk >/dev/null 2>&1; then
        while read -r disk disk_info; do
            [[ -z "$disk" ]] && continue
            disk_names+=("$disk")
            DISK_BASIC_INFO_CACHE[$disk]="${disk_info//  / }"
        done < <(lsblk -d -n -o NAME,SIZE,MODEL,VENDOR 2>/dev/null)
    fi

    if [[ "$smartctl_available" == true && "$use_json" == true && ${#disk_names[@]} -gt 0 ]]; then
        prefetch_smart_json_for_disks "${disk_names[@]}"
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
    local other_disk_regex='^[sv]d[a-z]+$|^nvme[0-9]+n[0-9]+$|^mmcblk[0-9]+$'

    # ---- Direct disks first (they carry I/O stats) ----
    for disk in "${disk_names[@]}"; do
        [[ "$disk" =~ $other_disk_regex ]] || continue
        local disk_info="${DISK_BASIC_INFO_CACHE[$disk]}"
        DISK_JSON_EXTRA=(); disk_smart_reset; disk_summary_reset
        local parsed=false json_data=""

        if [[ "$smartctl_available" == true ]]; then
            if [[ "$use_json" == true ]]; then
                get_smart_json "$disk"; json_data="$SMART_JSON_RESULT"
                [[ -n "$json_data" ]] && parse_smart_json "$disk" "$json_data" >/dev/null && parsed=true
            fi
            [[ "$parsed" == false ]] && parse_smart_text "$disk" >/dev/null && parsed=true
            if [[ "$parsed" == true ]]; then
                disk_summary_from_fields "$disk"
            else
                DISK_SUMMARY_SMART="-"
                [[ "$LANG_MODE" == "cn" ]] && DISK_SUMMARY_NOTE="无SMART信息" || DISK_SUMMARY_NOTE="no SMART info"
            fi
        else
            [[ "$LANG_MODE" == "cn" ]] && DISK_SUMMARY_NOTE="smartctl未安装" || DISK_SUMMARY_NOTE="smartctl missing"
        fi

        local dserial=""
        [[ -n "$json_data" ]] && dserial=$(json_query '.serial_number' "$json_data" 2>/dev/null || true)
        [[ -n "$dserial" ]] && seen_serials["$dserial"]=1

        if [[ "$disk_summary_table_started" != true ]]; then
            print_disk_summary_header
            disk_summary_table_started=true
        fi
        print_disk_summary_row "/dev/$disk" "$disk_info"
        disk_json_add "other" "/dev/$disk" "$disk_info"
    done

    # ---- RAID controller member disks not already shown above ----
    if [[ "$smartctl_available" == true ]]; then
        get_raid_member_devices ""
        local raid_devs="$RAID_MEMBER_RESULT"
        local member_entry=""
        while IFS= read -r member_entry; do
            [[ -z "$member_entry" ]] && continue
            local device="" raid_type="" raid_id=""
            IFS=: read -r device raid_type raid_id <<< "$member_entry"

            get_smart_json_raid "$device" "$raid_type" "$raid_id"
            local json_data="$SMART_JSON_RAID_RESULT"
            local mserial=""
            [[ -n "$json_data" ]] && mserial=$(json_query '.serial_number' "$json_data" 2>/dev/null || true)
            # Skip if this physical drive is already listed as a direct disk
            [[ -n "$mserial" && -n "${seen_serials[$mserial]:-}" ]] && continue

            DISK_JSON_EXTRA=(); disk_smart_reset; disk_summary_reset
            disk_extra_add "raid_type" "$raid_type"
            disk_extra_add "raid_id" "$raid_id"
            disk_extra_add "controller_device" "$device"

            local mbasic="-"
            if [[ -n "$json_data" ]]; then
                # parse_smart_json_sas prints detail lines; capture them to /dev/null
                # (brace group keeps DISK_SMART_FIELDS in the current shell).
                { parse_smart_json_sas "$json_data" "$raid_type,$raid_id"; } >/dev/null
                disk_summary_from_fields "member"
                local mmodel=""
                mmodel=$(json_query '.model_name' "$json_data" 2>/dev/null || true)
                if [[ -z "$mmodel" ]]; then
                    local mv="" mp=""
                    mv=$(json_query '.scsi_vendor' "$json_data" 2>/dev/null || true)
                    mp=$(json_query '.scsi_product' "$json_data" 2>/dev/null || true)
                    mmodel="${mv} ${mp}"
                fi
                mbasic="${mmodel# }"
            fi
            [[ -n "$mserial" ]] && seen_serials["$mserial"]=1

            if [[ "$disk_summary_table_started" != true ]]; then
                print_disk_summary_header
                disk_summary_table_started=true
            fi
            print_disk_summary_row "${raid_type},${raid_id}" "${mbasic:--}"
            disk_json_add "raid_member" "$device" "$mbasic"
        done <<< "$raid_devs"
    fi

    if [[ "$disk_summary_table_started" == true ]]; then
        print_disk_summary_footer
    else
        print_info "$(get_label "status")" "$(get_label "not_detected")"
    fi
    echo "└$(repeat_char '─' 50)"
}

# Function to get RAID information
get_raid_info() {
    print_subsection "$(get_label "raid_info")"

    local raid_found=false
    JSON_RAID_SW=()
    JSON_RAID_HW=()
    JSON_RAID_TOOLS=()
    local sep=$'\t'

    # ---- Software RAID (mdraid) ----
    if [[ -f /proc/mdstat ]]; then
        local md_info
        md_info=$(grep -E '^md[0-9]' /proc/mdstat 2>/dev/null)
        if [[ -n "$md_info" ]]; then
            local -a sw_rows=()
            local -a sw_warns=()
            local line=""
            while IFS= read -r line; do
                local raid_state="OK" raid_color="$GREEN"
                local md_name="" md_status="" md_level="" members="" member_count=0
                # Only degraded/faulty arrays are unhealthy. raid0 is healthy when
                # active — it just has no redundancy (noted separately below).
                if [[ "$line" =~ faulty|degraded|inactive|failed ]]; then
                    raid_state="FAIL"; raid_color="$RED"
                fi
                if [[ "$line" =~ ^(md[0-9]+)[[:space:]]+:[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]*(.*)$ ]]; then
                    md_name="${BASH_REMATCH[1]}"
                    md_status="${BASH_REMATCH[2]}"
                    md_level="${BASH_REMATCH[3]}"
                    members="${BASH_REMATCH[4]}"
                    member_count=$(grep -o '\[[0-9]\+\]' <<< "$members" | wc -l)
                    sw_rows+=("${md_name}${sep}${md_level}${sep}${md_status}${sep}${member_count}${sep}${raid_state}${sep}${raid_color}")
                    if [[ "$md_level" == "raid0" ]]; then
                        if [[ "$LANG_MODE" == "cn" ]]; then
                            sw_warns+=("${md_name}${sep}raid0 无冗余，任一成员故障将导致阵列失效")
                        else
                            sw_warns+=("${md_name}${sep}raid0 has no redundancy; any member failure breaks the array")
                        fi
                    fi
                fi
                JSON_RAID_SW+=("$line")
            done <<< "$md_info"

            if [[ ${#sw_rows[@]} -gt 0 ]]; then
                [[ "$LANG_MODE" == "cn" ]] && print_color "$GREEN" "│ 软件 RAID (mdraid):" || print_color "$GREEN" "│ Software RAID (mdraid):"
                local w_a=8 w_l=10 w_s=12 w_m=9 w_h=6
                TABLE_COL_W=($w_a $w_l $w_s $w_m $w_h)
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
            print_info "mdadm arrays" "$mdadm_count (details in JSON)"
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
                [[ "$LANG_MODE" == "cn" ]] && print_color "$GREEN" "│ RAID/HBA 控制器:" || print_color "$GREEN" "│ RAID/HBA Controllers:"
                local w_slot=10 w_type=9 w_name=48
                TABLE_COL_W=($w_slot $w_type $w_name)
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
        JSON_RAID_TOOLS+=("$(json_obj "$(json_kv "tool" "$tool")" "$(json_kv "path" "$tool_path")")")
    done
    if [[ ${#tool_rows[@]} -gt 0 ]]; then
        [[ "$LANG_MODE" == "cn" ]] && print_color "$GREEN" "│ 已安装的 RAID 工具:" || print_color "$GREEN" "│ Installed RAID Tools:"
        local w_tool=12 w_path=52
        TABLE_COL_W=($w_tool $w_path)
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
        print_info "$(get_label "status")" "$(get_label "not_detected")"
    fi

    echo "└$(repeat_char '─' 50)"
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
        IFS=':' read -ra segments <<< "$ip_part"
        if [[ ${#segments[@]} -ge 2 ]]; then
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
            local masked_half=$(repeat_char 'X' $((len-half)))
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
    print_subsection "$(get_label "network_info")"

    JSON_NETWORK=()

    local -a interfaces=()
    declare -A iface_status
    declare -A iface_ipv4
    declare -A iface_ipv6
    declare -A iface_mac

    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local tmp="${line#*: }"
            local ifname="${tmp%%:*}"
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
            local ifname="${parts[1]}"
            local family="${parts[2]}"
            local addr="${parts[3]}"
            if [[ "$family" == "inet" ]]; then
                [[ -z "${iface_ipv4[$ifname]:-}" ]] && iface_ipv4[$ifname]="$addr"
            elif [[ "$family" == "inet6" ]]; then
                [[ -z "${iface_ipv6[$ifname]:-}" ]] && iface_ipv6[$ifname]="$addr"
            fi
        done < <(ip -o addr show 2>/dev/null)
    fi

    if [[ ${#interfaces[@]} -eq 0 ]]; then
        for path in /sys/class/net/*; do
            [[ ! -e "$path" ]] && break
            interfaces+=("${path##*/}")
        done
    fi

    local -a net_rows=()        # iface\tstatuscolor\tstatus\tlink\tmac\tipv4\tmodel
    local -a net_warns=()
    local sep=$'\t'
    local printed_interfaces=0

    local interface
    for interface in "${interfaces[@]}"; do
        is_physical_interface "$interface" || continue
        ((printed_interfaces++))

        local pci_path="" device_path="/sys/class/net/$interface/device"
        if [[ -L "$device_path" ]]; then
            local real_path=$(readlink -f "$device_path" 2>/dev/null)
            [[ -n "$real_path" ]] && pci_path=$(basename "$real_path")
        fi

        local nic_model="" model_val="" ethtool_info="" driver_val="" firmware_val="" bus_info_val=""
        command -v ethtool >/dev/null 2>&1 && ethtool_info=$(ethtool -i "$interface" 2>/dev/null || true)
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
            local operstate_file="/sys/class/net/$interface/operstate"
            [[ -r "$operstate_file" ]] && status="$(<"$operstate_file")" && status="${status^^}"
        fi

        local ipv4="${iface_ipv4[$interface]:-}" ipv6="${iface_ipv6[$interface]:-}"
        local masked_ipv4="" masked_ipv6=""
        [[ -n "$ipv4" ]] && masked_ipv4=$(mask_ip_address "$ipv4")
        [[ -n "$ipv6" ]] && masked_ipv6=$(mask_ip_address "$ipv6")

        local mac="${iface_mac[$interface]:-}" masked_mac=""
        if [[ -z "$mac" ]]; then
            local mac_file="/sys/class/net/$interface/address"
            [[ -r "$mac_file" ]] && mac=$(<"$mac_file")
        fi
        [[ -n "$mac" ]] && masked_mac=$(mask_mac_address "$mac")

        local speed_val="" duplex_val="" link_detected=""
        local speed_file="/sys/class/net/$interface/speed"
        local duplex_file="/sys/class/net/$interface/duplex"
        local carrier_file="/sys/class/net/$interface/carrier"
        # NOTE: $(<file) is bash's fast read; do NOT append 2>/dev/null or the
        # redirection turns it into a null command that yields an empty string.
        if [[ -r "$speed_file" ]]; then
            local speed=""; speed=$(<"$speed_file") 2>/dev/null
            [[ "$speed" != "-1" && -n "$speed" ]] && speed_val="$speed"
        fi
        if [[ -r "$duplex_file" ]]; then
            local dtmp=""; dtmp=$(<"$duplex_file") 2>/dev/null
            [[ -n "$dtmp" && "$dtmp" != "unknown" ]] && duplex_val="$dtmp"
        fi
        if [[ -r "$carrier_file" ]]; then
            local ctmp=""; ctmp=$(<"$carrier_file") 2>/dev/null
            [[ "$ctmp" == "1" ]] && link_detected="Yes" || link_detected="No"
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
            done < <(ethtool "$interface" 2>/dev/null)
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
        [[ -r "/sys/class/net/$interface/statistics/rx_errors" ]] && rx_errors=$(<"/sys/class/net/$interface/statistics/rx_errors")
        [[ -r "/sys/class/net/$interface/statistics/tx_errors" ]] && tx_errors=$(<"/sys/class/net/$interface/statistics/tx_errors")
        [[ -r "/sys/class/net/$interface/statistics/rx_dropped" ]] && rx_dropped=$(<"/sys/class/net/$interface/statistics/rx_dropped")
        [[ -r "/sys/class/net/$interface/statistics/tx_dropped" ]] && tx_dropped=$(<"/sys/class/net/$interface/statistics/tx_dropped")
        [[ -r "/sys/class/net/$interface/statistics/collisions" ]] && collisions=$(<"/sys/class/net/$interface/statistics/collisions")
        local error_summary=()
        [[ -n "$rx_errors" && "$rx_errors" != "0" ]] && error_summary+=("rx_errors=$rx_errors")
        [[ -n "$tx_errors" && "$tx_errors" != "0" ]] && error_summary+=("tx_errors=$tx_errors")
        [[ -n "$rx_dropped" && "$rx_dropped" != "0" ]] && error_summary+=("rx_dropped=$rx_dropped")
        [[ -n "$tx_dropped" && "$tx_dropped" != "0" ]] && error_summary+=("tx_dropped=$tx_dropped")
        [[ -n "$collisions" && "$collisions" != "0" ]] && error_summary+=("collisions=$collisions")
        [[ ${#error_summary[@]} -gt 0 ]] && net_warns+=("${interface}${sep}${error_summary[*]}")

        local rx_bytes=$(<"/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "")
        local tx_bytes=$(<"/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "")
        local rx_display="" tx_display=""
        [[ -n "$rx_bytes" ]] && format_bytes_to rx_display "$rx_bytes"
        [[ -n "$tx_bytes" ]] && format_bytes_to tx_display "$tx_bytes"

        local net_kv=(
            "$(json_kv "name" "$interface")"
            "$(json_kv "status" "${status:-Unknown}")"
        )
        [[ -n "$model_val" ]] && net_kv+=("$(json_kv "model" "$model_val")")
        [[ -n "$driver_val" ]] && net_kv+=("$(json_kv "driver" "$driver_val")")
        [[ -n "$firmware_val" ]] && net_kv+=("$(json_kv "firmware" "$firmware_val")")
        [[ -n "$bus_info_val" ]] && net_kv+=("$(json_kv "bus_info" "$bus_info_val")")
        [[ -n "$masked_ipv4" ]] && net_kv+=("$(json_kv "ipv4" "$masked_ipv4")")
        [[ -n "$masked_ipv6" ]] && net_kv+=("$(json_kv "ipv6" "$masked_ipv6")")
        [[ -n "$masked_mac" ]] && net_kv+=("$(json_kv "mac" "$masked_mac")")
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
        print_info "$(get_label "status")" "$(get_label "not_detected")"
        echo "└$(repeat_char '─' 50)"
        return
    fi

    local w_if=12 w_st=8 w_link=12 w_mac=18 w_ip=20 w_model=24
    TABLE_COL_W=($w_if $w_st $w_link $w_mac $w_ip $w_model)
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

    echo "└$(repeat_char '─' 50)"
}

# Function to get GPU information
get_gpu_info() {
    print_subsection "$(get_label "gpu_info")"

    JSON_GPU=()
    local -a gpu_rows=()          # each: type\tmodel\tmemory\tdriver\ttemp
    local sep=$'\t'

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

            gpu_rows+=("NVIDIA${sep}discrete${sep}${name_val}${sep}${memory_val} MB${sep}${driver_val}${sep}${temp_val}°C")

            local gpu_kv=(
                "$(json_kv "source" "nvidia-smi")"
                "$(json_kv "name" "$name_val")"
                "$(json_kv "memory_mb" "$memory_val")"
                "$(json_kv "driver" "$driver_val")"
                "$(json_kv "temperature_c" "$temp_val")"
                "$(json_kv "power_w" "$power_val")"
                "$(json_kv "utilization_percent" "$util_val")"
            )
            JSON_GPU+=("$(json_obj "${gpu_kv[@]}")")
        done < <(nvidia-smi --query-gpu=name,memory.total,driver_version,temperature.gpu,power.draw,utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
    fi

    # All GPUs visible on the PCI bus (covers AMD/Intel and NVIDIA without driver)
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

                gpu_rows+=("${vendor}${sep}${cls}${sep}${desc}${sep}-${sep}-${sep}-")
                local gpu_kv=(
                    "$(json_kv "source" "lspci")"
                    "$(json_kv "slot" "$slot")"
                    "$(json_kv "vendor" "$vendor")"
                    "$(json_kv "class" "$cls")"
                    "$(json_kv "name" "$desc")"
                )
                JSON_GPU+=("$(json_obj "${gpu_kv[@]}")")
            done <<< "$gpu_devices"
        fi
    fi

    if [[ ${#gpu_rows[@]} -eq 0 ]]; then
        print_info "$(get_label "status")" "$(get_label "not_detected")"
        echo "└$(repeat_char '─' 50)"
        return
    fi

    # Map a class token to a localized label.
    gpu_class_label() {
        case "$1" in
            discrete)   [[ "$LANG_MODE" == "cn" ]] && echo "独显" || echo "Discrete" ;;
            integrated) [[ "$LANG_MODE" == "cn" ]] && echo "集显" || echo "Integrated" ;;
            bmc)        [[ "$LANG_MODE" == "cn" ]] && echo "管理" || echo "BMC" ;;
            *)          echo "-" ;;
        esac
    }

    # Do any rows carry rich data (memory/driver/temp from nvidia-smi)?
    local has_rich=false row=""
    for row in "${gpu_rows[@]}"; do
        local _v="" _c="" _m="" _mem="" _drv="" _tmp=""
        IFS="$sep" read -r _v _c _m _mem _drv _tmp <<< "$row"
        if [[ ( -n "$_mem" && "$_mem" != "-" && "$_mem" != "- MB" ) || ( -n "$_drv" && "$_drv" != "-" ) || ( -n "$_tmp" && "$_tmp" != "-" ) ]]; then
            has_rich=true; break
        fi
    done

    local gvendor="" gclass="" gmodel="" gmem="" gdriver="" gtemp="" clabel="" ccolor=""
    if [[ "$has_rich" == true ]]; then
        local w_v=7 w_c=8 w_model=34 w_mem=10 w_driver=13 w_temp=6
        TABLE_COL_W=($w_v $w_c $w_model $w_mem $w_driver $w_temp)
        if [[ "$LANG_MODE" == "cn" ]]; then
            table_header "厂商" "类别" "型号" "显存" "驱动" "温度"
        else
            table_header "Vendor" "Class" "Model" "Memory" "Driver" "Temp"
        fi
        for row in "${gpu_rows[@]}"; do
            IFS="$sep" read -r gvendor gclass gmodel gmem gdriver gtemp <<< "$row"
            clabel=$(gpu_class_label "$gclass")
            case "$gclass" in discrete) ccolor="$GREEN" ;; integrated) ccolor="$CYAN" ;; bmc) ccolor="$YELLOW" ;; *) ccolor="" ;; esac
            local tcolor="" tnum="${gtemp%%°*}"
            if [[ "$tnum" =~ ^[0-9]+$ ]]; then
                if (( tnum >= 85 )); then tcolor="$RED"; elif (( tnum >= 75 )); then tcolor="$YELLOW"; else tcolor="$GREEN"; fi
            fi
            table_row "$gvendor" "$CYAN" "$clabel" "$ccolor" "$gmodel" "" "$gmem" "" "$gdriver" "" "$gtemp" "$tcolor"
        done
        table_close
    else
        local w_v=8 w_c=10 w_model=54
        TABLE_COL_W=($w_v $w_c $w_model)
        if [[ "$LANG_MODE" == "cn" ]]; then
            table_header "厂商" "类别" "型号"
        else
            table_header "Vendor" "Class" "Model"
        fi
        for row in "${gpu_rows[@]}"; do
            IFS="$sep" read -r gvendor gclass gmodel gmem gdriver gtemp <<< "$row"
            clabel=$(gpu_class_label "$gclass")
            case "$gclass" in discrete) ccolor="$GREEN" ;; integrated) ccolor="$CYAN" ;; bmc) ccolor="$YELLOW" ;; *) ccolor="" ;; esac
            table_row "$gvendor" "$CYAN" "$clabel" "$ccolor" "$gmodel" ""
        done
        table_close
    fi

    echo "└$(repeat_char '─' 50)"
}

# Function to get motherboard information
get_motherboard_info() {
    print_subsection "$(get_label "motherboard_info")"

    local mb_vendor=""
    local mb_product=""
    local mb_version=""
    local bios_vendor=""
    local bios_version=""

    [[ -r /sys/class/dmi/id/board_vendor ]] && mb_vendor=$(< /sys/class/dmi/id/board_vendor)
    [[ -r /sys/class/dmi/id/board_name ]] && mb_product=$(< /sys/class/dmi/id/board_name)
    [[ -r /sys/class/dmi/id/board_version ]] && mb_version=$(< /sys/class/dmi/id/board_version)
    [[ -r /sys/class/dmi/id/bios_vendor ]] && bios_vendor=$(< /sys/class/dmi/id/bios_vendor)
    [[ -r /sys/class/dmi/id/bios_version ]] && bios_version=$(< /sys/class/dmi/id/bios_version)

    if [[ -z "$mb_vendor$mb_product$mb_version$bios_vendor$bios_version" ]] && command -v dmidecode >/dev/null 2>&1; then
        mb_vendor=$(dmidecode -s baseboard-manufacturer 2>/dev/null)
        mb_product=$(dmidecode -s baseboard-product-name 2>/dev/null)
        mb_version=$(dmidecode -s baseboard-version 2>/dev/null)
        bios_vendor=$(dmidecode -s bios-vendor 2>/dev/null)
        bios_version=$(dmidecode -s bios-version 2>/dev/null)
    fi

    if [[ -n "$mb_vendor$mb_product$mb_version$bios_vendor$bios_version" ]]; then
        
        print_info "$(get_label "vendor")" "${mb_vendor:-$(get_label "no_info")}"
        print_info "$(get_label "model")" "${mb_product:-$(get_label "no_info")}"
        print_info "Version" "${mb_version:-$(get_label "no_info")}"
        print_info "BIOS Vendor" "${bios_vendor:-$(get_label "no_info")}"
        print_info "BIOS Version" "${bios_version:-$(get_label "no_info")}"

        JSON_MOTHERBOARD_KV=(
            "$(json_kv "vendor" "$mb_vendor")"
            "$(json_kv "model" "$mb_product")"
            "$(json_kv "version" "$mb_version")"
            "$(json_kv "bios_vendor" "$bios_vendor")"
            "$(json_kv "bios_version" "$bios_version")"
        )
    else
        print_info "$(get_label "status")" "$(get_label "no_info") (dmidecode required)"
        JSON_MOTHERBOARD_KV=()
    fi
    
    echo "└$(repeat_char '─' 50)"
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
    echo "└$(repeat_char '─' 50)"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Hardware Information Collection Script v$VERSION (BETA)
One-shot hardware inventory — collects and prints, never persists or monitors.

OPTIONS:
    -cn, --chinese     Display output in Chinese
    -us, --english     Display output in English (default)
    -j,  --json        Output JSON to stdout only
    -y,  --yes         Auto-install missing tools without prompting
         --no-install  Never install; report with whatever tools are present
    -h,  --help        Show this help message
    -v,  --version     Show version information

SECTIONS:
    System, CPU (+platform), Memory, Disks/SMART, NVMe deep health,
    RAID/HBA, Network, GPU, Motherboard — all rendered as aligned tables.

PRIVACY:
    IP and MAC addresses are masked. Serial numbers are shown in full.

Supported Distributions:
    Debian/Ubuntu/Mint, RHEL/CentOS/Alma/Rocky/CloudLinux, Fedora,
    Arch/Manjaro, openSUSE/SLES

Examples:
    $0                 # Text report (English), prompts before installing tools
    $0 -cn             # Text report in Chinese
    $0 -y              # Auto-install missing tools, then report
    $0 --json | jq .   # Machine-readable JSON

Note: run with sudo for complete hardware access (dmidecode, SMART, etc.).

EOF
}

# Function to show version
show_version() {
    echo "$SCRIPT_NAME v$VERSION"
}

# Function to build JSON report string
build_json_report() {
    local meta_kv=(
        "$(json_kv "version" "$VERSION")"
        "$(json_kv "generated_at" "$(date)")"
        "$(json_kv "hostname" "$(hostname)")"
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
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    generate_report_text() {
        COLLECT_JSON=false
        # Print title
        print_header "$(get_label "title")"
        print_report_overview
        start_lshw_display_prefetch

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

        # Footer
        echo
        print_color "$GREEN" "$(get_label "completed")"
        print_color "$CYAN" "Generated on: $(date)"
        echo
    }

    generate_report_json() {
        json_reset
        COLLECT_JSON=true
        start_lshw_display_prefetch
        collect_ram_info
        local previous_quiet_mode="$QUIET_MODE"
        QUIET_MODE=true
        {
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
        print_color "$YELLOW" "Note: Some hardware information requires root privileges."
        print_color "$YELLOW" "Run with sudo for complete information."
        echo
    fi

    # Install required packages (text output only). install_packages handles
    # the Y/N confirmation itself and always lets us continue afterwards.
    print_color "$BLUE" "$(get_label "generating")"
    echo

    install_packages || true

    generate_report_text
}

# Run main function
main "$@"
