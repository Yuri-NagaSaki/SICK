#!/bin/bash

# Hardware Information Collection Script
# 硬件信息收集脚本
# Compatible with Debian/Ubuntu/CentOS/AlmaLinux/Rocky Linux/CloudLinux/Arch Linux/openSUSE/Fedora/Alpine Linux
# 兼容 Debian/Ubuntu/CentOS/AlmaLinux/Rocky Linux/CloudLinux/Arch Linux/openSUSE/Fedora/Alpine Linux

VERSION="2.5.0"
SCRIPT_NAME="Hardware Info Collector"

# Temporary files tracking for cleanup
TEMP_FILES=()

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
    ["read_io"]="Read I/O"
    ["write_io"]="Write I/O"
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
    ["read_io"]="读取IO"
    ["write_io"]="写入IO"
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
    local color="$1"
    local text="$2"
    echo -e "${color}${text}${NC}"
}

# Function to print section header
print_header() {
    local title="$1"
    local width=80
    local padding=$(( (width - ${#title}) / 2 ))
    
    echo
    print_color "$CYAN" "$(printf '═%.0s' $(seq 1 $width))"
    print_color "$WHITE" "$(printf '%*s%s%*s' $padding '' "$title" $padding '')"
    print_color "$CYAN" "$(printf '═%.0s' $(seq 1 $width))"
    echo
}

# Function to print sub-section
print_subsection() {
    local title="$1"
    print_color "$YELLOW" "┌─ $title"
    print_color "$YELLOW" "├$(printf '─%.0s' $(seq 1 $((${#title} + 2))))"
}

# Function to calculate display width of string (considering CJK characters)
get_display_width() {
    local str="$1"
    
    # Calculate display width for mixed ASCII/CJK strings
    local byte_count=$(echo -n "$str" | wc -c)
    local char_count=$(echo -n "$str" | wc -m)
    
    if [[ $byte_count -eq $char_count ]]; then
        # All ASCII characters, display width = character count
        echo $char_count
    else
        # Mixed or all CJK characters
        # In UTF-8: ASCII=1 byte, CJK=3 bytes
        # Let a=ascii_chars, c=cjk_chars
        # a + c = char_count
        # a + 3c = byte_count
        # Solving: c = (byte_count - char_count) / 2
        # display_width = a*1 + c*2 = char_count + c
        local cjk_chars=$(( (byte_count - char_count) / 2 ))
        local display_width=$((char_count + cjk_chars))
        echo $display_width
    fi
}

# Function to print info line with proper alignment
print_info() {
    local label="$1"
    local value="$2"
    local target_width=20
    
    # Calculate the actual display width of the label
    local label_width=$(get_display_width "$label")
    
    # Calculate needed padding
    local padding=$((target_width - label_width))
    if [[ $padding -lt 0 ]]; then
        padding=0
    fi
    
    # Print with calculated padding
    printf "│ %s%*s: %s\n" "$label" $padding "" "$value"
}

# Function to print table cell with proper alignment
print_table_cell() {
    local content="$1"
    local width="$2"
    local content_width=$(get_display_width "$content")
    local padding=$((width - content_width))
    
    if [[ $padding -lt 0 ]]; then
        padding=0
    fi
    
    printf "%s%*s" "$content" $padding ""
}

# Function to print table header
print_table_header() {
    local cols=("$@")
    local line="├"
    local header="│"
    
    for col in "${cols[@]}"; do
        line+="$(printf '─%.0s' $(seq 1 18))┬"
        header+="$(printf " %-16s │" "$col")"
    done
    
    line="${line%┬}┤"
    print_color "$YELLOW" "$line"
    print_color "$WHITE" "$header"
    
    line="├"
    for col in "${cols[@]}"; do
        line+="$(printf '─%.0s' $(seq 1 18))┼"
    done
    line="${line%┼}┤"
    print_color "$YELLOW" "$line"
}

# Function to print table row
print_table_row() {
    local cols=("$@")
    local row="│"
    
    for col in "${cols[@]}"; do
        row+="$(printf " %-16s │" "$col")"
    done
    
    echo "$row"
}

# Function to detect distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ -f /etc/redhat-release ]]; then
        echo "centos"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/alpine-release ]]; then
        echo "alpine"
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
        "alpine")
            echo "apk"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to install required packages
install_packages() {
    local pkg_manager=$(get_package_manager)
    local packages_needed=()
    local packages_installed=()
    
    # Check for required commands
    echo "Checking for required tools..."
    
    if ! command -v dmidecode >/dev/null 2>&1; then
        packages_needed+=("dmidecode")
        echo "  ❌ dmidecode not found"
    else
        echo "  ✓ dmidecode found"
    fi
    
    if ! command -v lshw >/dev/null 2>&1; then
        packages_needed+=("lshw")
        echo "  ❌ lshw not found"
    else
        echo "  ✓ lshw found"
    fi
    
    if ! command -v smartctl >/dev/null 2>&1; then
        packages_needed+=("smartmontools")
        echo "  ❌ smartctl not found"
    else
        echo "  ✓ smartctl found"
    fi
    
    if ! command -v iostat >/dev/null 2>&1; then
        packages_needed+=("sysstat")
        echo "  ❌ iostat not found"
    else
        echo "  ✓ iostat found"
    fi
    
    if ! command -v bc >/dev/null 2>&1; then
        packages_needed+=("bc")
        echo "  ❌ bc not found"
    else
        echo "  ✓ bc found"
    fi
    
    if ! command -v ethtool >/dev/null 2>&1; then
        packages_needed+=("ethtool")
        echo "  ❌ ethtool not found"
    else
        echo "  ✓ ethtool found"
    fi
    
    if ! command -v nvme >/dev/null 2>&1; then
        packages_needed+=("nvme-cli")
        echo "  ❌ nvme not found"
    else
        echo "  ✓ nvme found"
    fi

    if ! command -v jq >/dev/null 2>&1; then
        packages_needed+=("jq")
        echo "  ❌ jq not found (for JSON parsing)"
    else
        echo "  ✓ jq found"
    fi

    # Check for sensors command (for CPU temperature)
    if ! command -v sensors >/dev/null 2>&1; then
        case "$pkg_manager" in
            apt)
                packages_needed+=("lm-sensors")
                echo "  ❌ sensors not found (for CPU temperature)"
                ;;
            yum|dnf)
                packages_needed+=("lm_sensors")
                echo "  ❌ sensors not found (for CPU temperature)"
                ;;
            pacman)
                packages_needed+=("lm_sensors")
                echo "  ❌ sensors not found (for CPU temperature)"
                ;;
            zypper)
                packages_needed+=("sensors")
                echo "  ❌ sensors not found (for CPU temperature)"
                ;;
            apk)
                packages_needed+=("lm-sensors")
                echo "  ❌ sensors not found (for CPU temperature)"
                ;;
            *)
                echo "  ❌ sensors not found (package name varies by distro)"
                ;;
        esac
    else
        echo "  ✓ sensors found"
    fi

    # Check for optional but useful commands
    if ! command -v lspci >/dev/null 2>&1; then
        case "$pkg_manager" in
            "apt")
                packages_needed+=("pciutils")
                echo "  ❌ lspci not found"
                ;;
            "dnf"|"yum")
                packages_needed+=("pciutils")
                echo "  ❌ lspci not found"
                ;;
            "pacman")
                packages_needed+=("pciutils")
                echo "  ❌ lspci not found"
                ;;
            "zypper")
                packages_needed+=("pciutils")
                echo "  ❌ lspci not found"
                ;;
            "apk")
                packages_needed+=("pciutils")
                echo "  ❌ lspci not found"
                ;;
        esac
    else
        echo "  ✓ lspci found"
    fi
    
    if [[ ${#packages_needed[@]} -eq 0 ]]; then
        echo "All required tools are already installed!"
        echo
        return 0
    fi
    
    echo
    if [[ "$LANG_MODE" == "cn" ]]; then
        echo "需要安装以下软件包: ${packages_needed[*]}"
    else
        echo "Need to install the following packages: ${packages_needed[*]}"
    fi
    
    # Check if we have permission to install packages
    if ! command -v sudo >/dev/null 2>&1 && [[ $EUID -ne 0 ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            echo "❌ 错误: 没有sudo权限且不是root用户，无法自动安装软件包"
            echo "请手动安装以下软件包: ${packages_needed[*]}"
            echo "然后重新运行此脚本。"
        else
            echo "❌ Error: No sudo access and not running as root, cannot auto-install packages"
            echo "Please manually install the following packages: ${packages_needed[*]}"
            echo "Then run this script again."
        fi
        echo
        return 1
    fi
    
    local install_cmd=""
    local update_cmd=""
    
    case "$pkg_manager" in
        "apt")
            update_cmd="sudo apt-get update"
            install_cmd="sudo apt-get install -y"
            ;;
        "dnf")
            install_cmd="sudo dnf install -y"
            ;;
        "yum")
            install_cmd="sudo yum install -y"
            ;;
        "pacman")
            install_cmd="sudo pacman -S --noconfirm"
            ;;
        "zypper")
            install_cmd="sudo zypper install -y"
            ;;
        "apk")
            install_cmd="sudo apk add"
            ;;
        "unknown")
            if [[ "$LANG_MODE" == "cn" ]]; then
                echo "❌ 错误: 无法识别包管理器，请手动安装: ${packages_needed[*]}"
            else
                echo "❌ Error: Cannot detect package manager, please install manually: ${packages_needed[*]}"
            fi
            echo
            return 1
            ;;
    esac
    
    if [[ $EUID -eq 0 ]]; then
        # Running as root, remove sudo from commands
        update_cmd="${update_cmd#sudo }"
        install_cmd="${install_cmd#sudo }"
    fi
    
    # Update package list for apt-based systems
    if [[ -n "$update_cmd" ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            echo "正在更新软件包列表..."
        else
            echo "Updating package list..."
        fi
        
        if ! eval "$update_cmd" >/dev/null 2>&1; then
            if [[ "$LANG_MODE" == "cn" ]]; then
                echo "⚠️  警告: 软件包列表更新失败，继续安装..."
            else
                echo "⚠️  Warning: Package list update failed, continuing with installation..."
            fi
        fi
    fi
    
    # Install packages
    if [[ "$LANG_MODE" == "cn" ]]; then
        echo "正在安装软件包..."
    else
        echo "Installing packages..."
    fi
    
    local all_success=true
    
    for package in "${packages_needed[@]}"; do
        echo "  Installing $package..."
        if eval "$install_cmd $package" >/dev/null 2>&1; then
            echo "  ✓ $package installed successfully"
            packages_installed+=("$package")
        else
            echo "  ❌ Failed to install $package"
            all_success=false
        fi
    done
    
    echo
    
    # Verify installation by checking commands again
    if [[ "$LANG_MODE" == "cn" ]]; then
        echo "验证安装结果..."
    else
        echo "Verifying installation..."
    fi
    
    local verification_success=true
    
    # Re-check all commands
    if [[ " ${packages_needed[*]} " =~ " dmidecode " ]]; then
        if command -v dmidecode >/dev/null 2>&1; then
            echo "  ✓ dmidecode now available"
        else
            echo "  ❌ dmidecode still not available"
            verification_success=false
        fi
    fi
    
    if [[ " ${packages_needed[*]} " =~ " lshw " ]]; then
        if command -v lshw >/dev/null 2>&1; then
            echo "  ✓ lshw now available"
        else
            echo "  ❌ lshw still not available"
            verification_success=false
        fi
    fi
    
    if [[ " ${packages_needed[*]} " =~ " smartmontools " ]]; then
        if command -v smartctl >/dev/null 2>&1; then
            echo "  ✓ smartctl now available"
        else
            echo "  ❌ smartctl still not available"
            verification_success=false
        fi
    fi
    
    if [[ " ${packages_needed[*]} " =~ " sysstat " ]]; then
        if command -v iostat >/dev/null 2>&1; then
            echo "  ✓ iostat now available"
        else
            echo "  ❌ iostat still not available"
            verification_success=false
        fi
    fi
    
    if [[ " ${packages_needed[*]} " =~ " bc " ]]; then
        if command -v bc >/dev/null 2>&1; then
            echo "  ✓ bc now available"
        else
            echo "  ❌ bc still not available"
            verification_success=false
        fi
    fi
    
    if [[ " ${packages_needed[*]} " =~ " ethtool " ]]; then
        if command -v ethtool >/dev/null 2>&1; then
            echo "  ✓ ethtool now available"
        else
            echo "  ❌ ethtool still not available"
            verification_success=false
        fi
    fi
    
    if [[ " ${packages_needed[*]} " =~ " pciutils " ]]; then
        if command -v lspci >/dev/null 2>&1; then
            echo "  ✓ lspci now available"
        else
            echo "  ❌ lspci still not available"
            verification_success=false
        fi
    fi
    
    if [[ " ${packages_needed[*]} " =~ " nvme-cli " ]]; then
        if command -v nvme >/dev/null 2>&1; then
            echo "  ✓ nvme now available"
        else
            echo "  ❌ nvme still not available"
            verification_success=false
        fi
    fi

    if [[ " ${packages_needed[*]} " =~ " jq " ]]; then
        if command -v jq >/dev/null 2>&1; then
            echo "  ✓ jq now available"
        else
            echo "  ❌ jq still not available"
            verification_success=false
        fi
    fi

    if [[ " ${packages_needed[*]} " =~ " lm-sensors " ]] || [[ " ${packages_needed[*]} " =~ " lm_sensors " ]] || [[ " ${packages_needed[*]} " =~ " sensors " ]]; then
        if command -v sensors >/dev/null 2>&1; then
            echo "  ✓ sensors now available"
            # Try to detect sensors if just installed
            if which sensors-detect >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
                echo "  Detecting sensors..."
                yes "" | sensors-detect >/dev/null 2>&1 || true
            fi
        else
            echo "  ❌ sensors still not available"
            verification_success=false
        fi
    fi

    echo
    
    if [[ "$all_success" == true && "$verification_success" == true ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            echo "✅ 所有软件包安装成功！"
        else
            echo "✅ All packages installed successfully!"
        fi
        echo
        return 0
    else
        if [[ "$LANG_MODE" == "cn" ]]; then
            echo "⚠️  警告: 某些软件包安装可能失败。硬件信息可能不完整。"
            echo "请检查上述错误并手动安装失败的软件包。"
        else
            echo "⚠️  Warning: Some packages may have failed to install. Hardware information may be incomplete."
            echo "Please check the errors above and manually install any failed packages."
        fi
        echo
        return 1
    fi
}

# Function to get system information
get_system_info() {
    print_subsection "$(get_label "system_info")"
    
    print_info "$(get_label "hostname")" "$(hostname)"
    print_info "$(get_label "os")" "$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "$(get_label "no_info")")"
    print_info "$(get_label "kernel")" "$(uname -r)"
    print_info "$(get_label "uptime")" "$(uptime -p 2>/dev/null || uptime | cut -d',' -f1 | sed 's/.*up //')"
    
    echo "└$(printf '─%.0s' $(seq 1 50))"
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
                    if [[ -n "$zone_temp" && "$zone_temp" -gt 0 ]]; then
                        # Convert millidegree to degree Celsius
                        local temp_celsius=$(echo "scale=1; $zone_temp / 1000" | bc -l 2>/dev/null)
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
                            if [[ -n "$temp_val" && "$temp_val" -gt 0 ]]; then
                                # Convert millidegree to degree Celsius
                                local temp_celsius=$(echo "scale=1; $temp_val / 1000" | bc -l 2>/dev/null)

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

    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ *//')
    local cpu_cores=$(grep "cpu cores" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ *//')
    local cpu_threads=$(grep "processor" /proc/cpuinfo | wc -l)
    local cpu_freq=$(grep "cpu MHz" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ *//')
    local cpu_cache=$(grep "cache size" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ *//')

    print_info "$(get_label "model")" "${cpu_model:-$(get_label "no_info")}"
    print_info "$(get_label "cores")" "${cpu_cores:-$(get_label "no_info")}"
    print_info "$(get_label "threads")" "${cpu_threads:-$(get_label "no_info")}"
    print_info "$(get_label "frequency")" "${cpu_freq:+${cpu_freq} MHz}"
    print_info "$(get_label "cache")" "${cpu_cache:-$(get_label "no_info")}"

    # CPU usage - using /proc/stat for more reliable detection
    local cpu_usage=""
    if [[ -r /proc/stat ]]; then
        # Read CPU stats twice with a short interval
        local cpu1=($(grep '^cpu ' /proc/stat | awk '{print $2,$3,$4,$5,$6,$7,$8}'))
        sleep 0.2
        local cpu2=($(grep '^cpu ' /proc/stat | awk '{print $2,$3,$4,$5,$6,$7,$8}'))

        # Calculate differences
        local user_diff=$((${cpu2[0]} - ${cpu1[0]}))
        local nice_diff=$((${cpu2[1]} - ${cpu1[1]}))
        local system_diff=$((${cpu2[2]} - ${cpu1[2]}))
        local idle_diff=$((${cpu2[3]} - ${cpu1[3]}))
        local iowait_diff=$((${cpu2[4]} - ${cpu1[4]}))
        local irq_diff=$((${cpu2[5]} - ${cpu1[5]}))
        local softirq_diff=$((${cpu2[6]} - ${cpu1[6]}))

        local total_diff=$((user_diff + nice_diff + system_diff + idle_diff + iowait_diff + irq_diff + softirq_diff))
        local active_diff=$((total_diff - idle_diff - iowait_diff))

        if [[ $total_diff -gt 0 ]]; then
            cpu_usage=$(echo "scale=1; $active_diff * 100 / $total_diff" | bc -l 2>/dev/null)
        fi
    fi

    # Fallback to top if /proc/stat method fails
    if [[ -z "$cpu_usage" ]]; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null)
    fi
    print_info "$(get_label "usage")" "${cpu_usage:+${cpu_usage}%}"

    # CPU Temperature
    local cpu_temp=$(get_cpu_temperature)
    if [[ -n "$cpu_temp" ]]; then
        # Check if temperature is high (above 80°C is generally considered high)
        local temp_value=$(echo "$cpu_temp" | grep -oE "[0-9]+\.?[0-9]*" | head -1)
        if [[ -n "$temp_value" ]] && (( $(echo "$temp_value > 80" | bc -l 2>/dev/null || echo 0) )); then
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

    echo "└$(printf '─%.0s' $(seq 1 50))"
}

# Function to get RAM information
get_ram_info() {
    print_subsection "$(get_label "ram_info")"
    
    # Memory from /proc/meminfo
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{printf "%.2f GB", $2/1024/1024}')
    local mem_available=$(grep MemAvailable /proc/meminfo | awk '{printf "%.2f GB", $2/1024/1024}')
    local mem_used=$(free -h | grep Mem | awk '{print $3}')
    
    print_info "$(get_label "total")" "$mem_total"
    print_info "$(get_label "used")" "$mem_used"
    print_info "$(get_label "available")" "$mem_available"
    
    # Memory modules information
    echo "│"
    print_color "$GREEN" "│ Memory Modules:"
    
    if command -v dmidecode >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        # Define column widths
        local w1=8 w2=6 w3=12 w4=12 w5=15 w6=20
        
        # Print enhanced table header with proper alignment
        echo "├$(printf '─%.0s' $(seq 1 100))┤"
        printf "│ "
        print_table_cell "$(get_label "size")" $w1
        printf " │ "
        print_table_cell "$(get_label "type")" $w2
        printf " │ "
        print_table_cell "$(get_label "frequency")" $w3
        printf " │ "
        print_table_cell "$(get_label "manufacturer")" $w4
        printf " │ "
        print_table_cell "$(get_label "serial_number")" $w5
        printf " │ "
        print_table_cell "$(get_label "model")" $w6
        printf " │\n"
        echo "├$(printf '─%.0s' $(seq 1 100))┤"
        
        # Parse memory modules using bash processing
        local temp_file=$(mktemp)
        TEMP_FILES+=("$temp_file")
        dmidecode -t memory 2>/dev/null > "$temp_file"
        
        # Process memory modules
        local size="" type="" speed="" manufacturer="" part_number="" serial_number=""
        local in_memory_device=0
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^Handle.*DMI\ type\ 17 ]]; then
                # Print previous module if we have valid data
                if [[ -n "$size" && ! "$size" =~ (No\ Module\ Installed|Unknown|Not\ Specified) ]]; then
                    # Format serial number for display
                    local display_sn="$serial_number"
                    if [[ -z "$display_sn" || "$display_sn" =~ (Not\ Specified|Unknown) ]]; then
                        display_sn="N/A"
                    fi
                    
                    # Print row with proper alignment
                    printf "│ "
                    print_table_cell "${size:0:8}" $w1
                    printf " │ "
                    print_table_cell "${type:0:6}" $w2
                    printf " │ "
                    print_table_cell "${speed:0:12}" $w3
                    printf " │ "
                    print_table_cell "${manufacturer:0:12}" $w4
                    printf " │ "
                    print_table_cell "${display_sn:0:15}" $w5
                    printf " │ "
                    print_table_cell "${part_number:0:20}" $w6
                    printf " │\n"
                fi
                # Reset for new module
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
        
        # Print last module if valid
        if [[ -n "$size" && ! "$size" =~ (No\ Module\ Installed|Unknown|Not\ Specified) ]]; then
            local display_sn="$serial_number"
            if [[ -z "$display_sn" || "$display_sn" =~ (Not\ Specified|Unknown) ]]; then
                display_sn="N/A"
            fi
            
            printf "│ "
            print_table_cell "${size:0:8}" $w1
            printf " │ "
            print_table_cell "${type:0:6}" $w2
            printf " │ "
            print_table_cell "${speed:0:12}" $w3
            printf " │ "
            print_table_cell "${manufacturer:0:12}" $w4
            printf " │ "
            print_table_cell "${display_sn:0:15}" $w5
            printf " │ "
            print_table_cell "${part_number:0:20}" $w6
            printf " │\n"
        fi

        # Print table footer
        echo "└$(printf '─%.0s' $(seq 1 100))┘"
    else
        # Alternative method using /proc/meminfo and lshw
        echo "│   Root privileges required for detailed memory information"
        if command -v lshw >/dev/null 2>&1; then
            echo "│   Alternative detection using lshw:"
            sudo lshw -c memory 2>/dev/null | grep -A5 -B1 "bank\|slot\|DIMM" | grep -E "description:|size:|clock:" | while IFS= read -r line; do
                echo "│   $line"
            done
        fi
        
        # Try alternative dmidecode without root (some systems allow it)
        if command -v dmidecode >/dev/null 2>&1; then
            echo "│   Attempting dmidecode (may fail without root):"
            dmidecode -t 17 2>/dev/null | grep -E "Size:|Type:|Speed:|Manufacturer:" | head -20 | while IFS= read -r line; do
                echo "│   $line"
            done
        fi
    fi
    
    echo "└$(printf '─%.0s' $(seq 1 50))"
}

# Helper function: Convert bytes to human readable format
format_bytes() {
    local bytes="$1"
    local suffix="$2"  # Optional suffix like "(SMART)" or "(session)"

    if [[ -z "$bytes" || "$bytes" == "0" || ! "$bytes" =~ ^[0-9]+$ ]]; then
        echo ""
        return
    fi

    local result=""
    if (( bytes >= 1125899906842624 )); then  # >= 1 PB
        result=$(echo "scale=2; $bytes / 1125899906842624" | bc -l 2>/dev/null)
        result="${result} PB"
    elif (( bytes >= 1099511627776 )); then  # >= 1 TB
        result=$(echo "scale=2; $bytes / 1099511627776" | bc -l 2>/dev/null)
        result="${result} TB"
    elif (( bytes >= 1073741824 )); then  # >= 1 GB
        result=$(echo "scale=2; $bytes / 1073741824" | bc -l 2>/dev/null)
        result="${result} GB"
    elif (( bytes >= 1048576 )); then  # >= 1 MB
        result=$(echo "scale=2; $bytes / 1048576" | bc -l 2>/dev/null)
        result="${result} MB"
    else
        result=$(echo "scale=2; $bytes / 1024" | bc -l 2>/dev/null)
        result="${result} KB"
    fi

    [[ -n "$suffix" ]] && result="$result $suffix"
    echo "$result"
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

# Function to check if a disk is a RAID controller virtual disk
is_raid_controller_disk() {
    local disk="$1"
    local json="$2"

    # Check if SMART is not available (common for RAID controllers)
    local smart_available=$(echo "$json" | grep -oP '"smart_support"\s*:\s*\{[^}]*"available"\s*:\s*\K(true|false)' | head -1)

    # Check for known RAID controller vendors
    local scsi_vendor=$(echo "$json" | grep -oP '"scsi_vendor"\s*:\s*"\K[^"]*' | head -1)
    local scsi_product=$(echo "$json" | grep -oP '"scsi_product"\s*:\s*"\K[^"]*' | head -1)

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

# Function to get RAID member disks from smartctl --scan
# Supports: megaraid (LSI/AVAGO), cciss (HP Smart Array), 3ware, areca
get_raid_member_devices() {
    local parent_disk="$1"
    local devices=()

    # Run smartctl --scan and look for RAID devices
    local scan_output=$(smartctl --scan 2>/dev/null)

    # Extract RAID device entries
    # Format examples:
    #   /dev/bus/6 -d megaraid,32 # /dev/bus/6 [megaraid_disk_32], SCSI device
    #   /dev/sda -d cciss,0 # /dev/sda [cciss_disk_00], SCSI device
    #   /dev/twa0 -d 3ware,0 # /dev/twa0 [3ware_disk_00], ATA device
    while IFS= read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
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

    # Return devices array as newline-separated string
    printf '%s\n' "${devices[@]}"
}

# Backward compatibility alias
get_megaraid_devices() {
    get_raid_member_devices "$@"
}

# Function to get SMART JSON for RAID member device
# Supports: megaraid, cciss, 3ware, areca
get_smart_json_raid() {
    local device="$1"
    local raid_type="$2"
    local raid_id="$3"
    local json_output=""

    json_output=$(smartctl -a --json=c -d "$raid_type","$raid_id" "$device" 2>/dev/null)

    if [[ -n "$json_output" ]] && echo "$json_output" | grep -q '"json_format_version"'; then
        echo "$json_output"
    else
        echo ""
    fi
}

# Backward compatibility alias
get_smart_json_megaraid() {
    local device="$1"
    local megaraid_id="$2"
    get_smart_json_raid "$device" "megaraid" "$megaraid_id"
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
        
        # Try to extract ALL fields using jq if available
        if command -v jq >/dev/null 2>&1; then
            # SAS/SCSI style fields
            grown_defects=$(echo "$data" | jq -r '.scsi_grown_defect_list // empty' 2>/dev/null)
            read_uncorrected=$(echo "$data" | jq -r '.scsi_error_counter_log.read.total_uncorrected_errors // empty' 2>/dev/null)
            write_uncorrected=$(echo "$data" | jq -r '.scsi_error_counter_log.write.total_uncorrected_errors // empty' 2>/dev/null)
            verify_uncorrected=$(echo "$data" | jq -r '.scsi_error_counter_log.verify.total_uncorrected_errors // empty' 2>/dev/null)
            non_medium_errors=$(echo "$data" | jq -r '.scsi_error_counter_log.non_medium_error_count // empty' 2>/dev/null)
            
            # SATA/ATA style fields (SMART attributes)
            reallocated_sectors=$(echo "$data" | jq -r '.ata_smart_attributes.table[] | select(.id == 5) | .raw.value' 2>/dev/null)
            pending_sectors=$(echo "$data" | jq -r '.ata_smart_attributes.table[] | select(.id == 197) | .raw.value' 2>/dev/null)
            offline_uncorrectable=$(echo "$data" | jq -r '.ata_smart_attributes.table[] | select(.id == 198) | .raw.value' 2>/dev/null)
            reported_uncorrect=$(echo "$data" | jq -r '.ata_smart_attributes.table[] | select(.id == 187) | .raw.value' 2>/dev/null)
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
        if [[ "$grown_defects" -gt 0 ]]; then
            echo -e "│   $(get_label "grown_defects"): ${YELLOW}${grown_defects}${NC}"
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

        if [[ "$total_uncorrected" -gt 0 ]]; then
            echo -e "│   $(get_label "uncorrected_errors"): ${RED}${total_uncorrected}${NC} (R:${read_uncorrected:-0}/W:${write_uncorrected:-0}/V:${verify_uncorrected:-0})"
        else
            echo "│   $(get_label "uncorrected_errors"): 0 (R:${read_uncorrected:-0}/W:${write_uncorrected:-0}/V:${verify_uncorrected:-0})"
        fi
    fi

    # SAS/SCSI: Non-medium Errors
    if [[ -n "$non_medium_errors" && "$non_medium_errors" != "null" && "$non_medium_errors" =~ ^[0-9]+$ && "$non_medium_errors" != "0" ]]; then
        echo -e "│   $(get_label "non_medium_errors"): ${YELLOW}${non_medium_errors}${NC}"
    fi

    # SATA/ATA: Reallocated Sectors (ID 5)
    if [[ -n "$reallocated_sectors" && "$reallocated_sectors" != "null" && "$reallocated_sectors" =~ ^[0-9]+$ ]]; then
        if [[ "$reallocated_sectors" -gt 0 ]]; then
            echo -e "│   $(get_label "reallocated_sectors"): ${YELLOW}${reallocated_sectors}${NC}"
        else
            echo "│   $(get_label "reallocated_sectors"): ${reallocated_sectors}"
        fi
    fi

    # SATA/ATA: Pending Sectors (ID 197)
    if [[ -n "$pending_sectors" && "$pending_sectors" != "null" && "$pending_sectors" =~ ^[0-9]+$ ]]; then
        if [[ "$pending_sectors" -gt 0 ]]; then
            echo -e "│   $(get_label "pending_sectors"): ${YELLOW}${pending_sectors}${NC}"
        else
            echo "│   $(get_label "pending_sectors"): ${pending_sectors}"
        fi
    fi

    # SATA/ATA: Offline Uncorrectable (ID 198)
    if [[ -n "$offline_uncorrectable" && "$offline_uncorrectable" != "null" && "$offline_uncorrectable" =~ ^[0-9]+$ ]]; then
        if [[ "$offline_uncorrectable" -gt 0 ]]; then
            echo -e "│   $(get_label "offline_uncorrectable"): ${YELLOW}${offline_uncorrectable}${NC}"
        else
            echo "│   $(get_label "offline_uncorrectable"): ${offline_uncorrectable}"
        fi
    fi

    # SATA/ATA: Reported Uncorrectable (ID 187)
    if [[ -n "$reported_uncorrect" && "$reported_uncorrect" != "null" && "$reported_uncorrect" =~ ^[0-9]+$ ]]; then
        if [[ "$reported_uncorrect" -gt 0 ]]; then
            echo -e "│   $(get_label "reported_uncorrect"): ${RED}${reported_uncorrect}${NC}"
        else
            echo "│   $(get_label "reported_uncorrect"): ${reported_uncorrect}"
        fi
    fi

    # Calculate and display total bad blocks summary (SATA style)
    local total_bad=0
    [[ -n "$reallocated_sectors" && "$reallocated_sectors" != "null" && "$reallocated_sectors" =~ ^[0-9]+$ ]] && total_bad=$((total_bad + reallocated_sectors))
    [[ -n "$pending_sectors" && "$pending_sectors" != "null" && "$pending_sectors" =~ ^[0-9]+$ ]] && total_bad=$((total_bad + pending_sectors))
    [[ -n "$offline_uncorrectable" && "$offline_uncorrectable" != "null" && "$offline_uncorrectable" =~ ^[0-9]+$ ]] && total_bad=$((total_bad + offline_uncorrectable))

    if [[ "$total_bad" -gt 0 ]]; then
        echo -e "│   $(get_label "bad_blocks"): ${RED}${total_bad}${NC}"
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
    local device_type=$(echo "$json" | grep -oP '"device"\s*:\s*\{[^}]*"type"\s*:\s*"\K[^"]*' | head -1)
    local protocol=$(echo "$json" | grep -oP '"device"\s*:\s*\{[^}]*"protocol"\s*:\s*"\K[^"]*' | head -1)

    # Extract basic info - try both SAS and SATA formats
    local vendor=$(echo "$json" | grep -oP '"scsi_vendor"\s*:\s*"\K[^"]*' | head -1)
    local product=$(echo "$json" | grep -oP '"scsi_product"\s*:\s*"\K[^"]*' | head -1)
    local model_name=$(echo "$json" | grep -oP '"model_name"\s*:\s*"\K[^"]*' | head -1)
    local model_family=$(echo "$json" | grep -oP '"model_family"\s*:\s*"\K[^"]*' | head -1)
    local serial=$(echo "$json" | grep -oP '"serial_number"\s*:\s*"\K[^"]*' | head -1)
    local capacity_bytes=$(echo "$json" | grep -oP '"user_capacity"\s*:\s*\{[^}]*"bytes"\s*:\s*\K[0-9]+' | head -1)

    # Format capacity
    local capacity_formatted=""
    if [[ -n "$capacity_bytes" && "$capacity_bytes" != "0" ]]; then
        capacity_formatted=$(format_bytes "$capacity_bytes")
    fi

    # Display disk info
    if [[ -n "$vendor" && -n "$product" ]]; then
        echo "│   Model: $vendor $product"
    elif [[ -n "$model_name" ]]; then
        echo "│   Model: $model_name"
    fi
    if [[ -n "$model_family" ]]; then
        echo "│   Family: $model_family"
    fi
    if [[ -n "$serial" ]]; then
        echo "│   Serial: $serial"
    fi
    if [[ -n "$capacity_formatted" ]]; then
        echo "│   Capacity: $capacity_formatted"
    fi

    # SMART status - check for smart_status.passed
    local smart_passed=$(echo "$json" | grep -oP '"smart_status"\s*:\s*\{[^}]*"passed"\s*:\s*\K(true|false)' | head -1)
    if [[ -z "$smart_passed" ]]; then
        # Try alternative method: check scsi_grown_defect_list element count
        local defect_count=$(echo "$json" | grep -oP '"scsi_grown_defect_list"\s*:\s*\K[0-9]+' | head -1)
        if [[ -n "$defect_count" && "$defect_count" == "0" ]]; then
            smart_passed="true"
        fi
    fi

    if [[ "$smart_passed" == "true" ]]; then
        echo "│   $(get_label "smart_status"): PASSED"
    elif [[ "$smart_passed" == "false" ]]; then
        echo "│   $(get_label "smart_status"): ${RED}FAILED${NC}"
    else
        echo "│   $(get_label "smart_status"): $(get_label "no_info")"
    fi

    # Temperature
    local temperature=$(echo "$json" | grep -oP '"temperature"\s*:\s*\{[^}]*"current"\s*:\s*\K[0-9]+' | head -1)
    if [[ -n "$temperature" && "$temperature" != "0" ]]; then
        echo "│   $(get_label "temperature"): ${temperature}°C"
    fi

    # Power on hours - try multiple formats
    local power_on_hours=$(echo "$json" | grep -oP '"power_on_time"\s*:\s*\{[^}]*"hours"\s*:\s*\K[0-9]+' | head -1)
    if [[ -n "$power_on_hours" ]]; then
        echo "│   $(get_label "power_on_hours"): ${power_on_hours} hours"
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
display_megaraid_disks() {
    local parent_disk="$1"

    # Get RAID member devices
    local raid_devs=$(get_raid_member_devices "$parent_disk")

    if [[ -z "$raid_devs" ]]; then
        if [[ "$LANG_MODE" == "cn" ]]; then
            echo "│   阵列成员: 无法检测到阵列成员磁盘"
            echo "│   → 请尝试: smartctl --scan"
        else
            echo "│   RAID Members: Unable to detect member disks"
            echo "│   → Try: smartctl --scan"
        fi
        return 1
    fi

    echo "│"
    if [[ "$LANG_MODE" == "cn" ]]; then
        print_color "$YELLOW" "│   ══ 阵列成员磁盘 ══"
    else
        print_color "$YELLOW" "│   ══ RAID Member Disks ══"
    fi

    local disk_count=0
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue

        # Parse format: device:raid_type:raid_id
        local device=$(echo "$entry" | cut -d: -f1)
        local raid_type=$(echo "$entry" | cut -d: -f2)
        local raid_id=$(echo "$entry" | cut -d: -f3)

        ((disk_count++))
        echo "│"
        print_color "$CYAN" "│   ─── Disk $disk_count ($raid_type,$raid_id) ───"

        # Get SMART data for this RAID member disk
        local json_data=$(get_smart_json_raid "$device" "$raid_type" "$raid_id")

        if [[ -n "$json_data" ]]; then
            parse_smart_json_sas "$json_data" "$raid_type,$raid_id"
        else
            # Try text-based parsing as fallback
            local smart_text=$(smartctl -a -d "$raid_type","$raid_id" "$device" 2>/dev/null)
            if [[ -n "$smart_text" ]]; then
                # Extract basic info from text output (works for both SAS and SATA)
                local vendor=$(echo "$smart_text" | grep "^Vendor:" | awk '{print $2}')
                local product=$(echo "$smart_text" | grep "^Product:" | awk '{print $2}')
                local model=$(echo "$smart_text" | grep "^Device Model:" | sed 's/^Device Model:\s*//')
                local serial=$(echo "$smart_text" | grep -E "^Serial [Nn]umber:" | awk '{print $3}')
                local health=$(echo "$smart_text" | grep -E "SMART (overall-health|Health Status):" | awk -F': ' '{print $2}')
                local temp=$(echo "$smart_text" | grep -E "Current Drive Temperature:|^Temperature:" | grep -oE '[0-9]+' | head -1)
                local power_hours=$(echo "$smart_text" | grep -E "Accumulated power on time|Power_On_Hours" | grep -oE '[0-9]+' | head -1)

                # Display model (SAS format: Vendor Product, SATA format: Device Model)
                if [[ -n "$vendor" && -n "$product" ]]; then
                    echo "│   Model: $vendor $product"
                elif [[ -n "$model" ]]; then
                    echo "│   Model: $model"
                fi
                [[ -n "$serial" ]] && echo "│   Serial: $serial"

                if [[ -n "$health" ]]; then
                    if [[ "$health" == "OK" || "$health" == "PASSED" ]]; then
                        echo "│   $(get_label "smart_status"): PASSED"
                    else
                        echo "│   $(get_label "smart_status"): ${RED}${health}${NC}"
                    fi
                fi

                [[ -n "$power_hours" ]] && echo "│   $(get_label "power_on_hours"): ${power_hours} hours"
                [[ -n "$temp" && "$temp" != "0" ]] && echo "│   $(get_label "temperature"): ${temp}°C"

                # ==========================================================================
                # Bad Blocks Detection for RAID member disks (text fallback)
                # ==========================================================================
                # Call the universal bad blocks detection function with text input
                # ==========================================================================
                detect_bad_blocks "text" "$smart_text"
            else
                if [[ "$LANG_MODE" == "cn" ]]; then
                    echo "│   SMART状态: 无法读取"
                else
                    echo "│   SMART Status: Unable to read"
                fi
            fi
        fi
    done <<< "$raid_devs"

    if [[ "$LANG_MODE" == "cn" ]]; then
        echo "│   ─── 共检测到 $disk_count 块成员磁盘 ───"
    else
        echo "│   ─── Total: $disk_count member disk(s) ───"
    fi

    return 0
}

# Function to get SMART data using JSON output (smartctl 7.0+)
get_smart_json() {
    local disk="$1"
    local json_output=""

    # Try to get JSON output from smartctl
    json_output=$(smartctl -a --json=c "/dev/$disk" 2>/dev/null)

    # Check if JSON output is valid
    if [[ -n "$json_output" ]] && echo "$json_output" | grep -q '"json_format_version"'; then
        echo "$json_output"
    else
        echo ""
    fi
}

# Function to parse SMART data from JSON
parse_smart_json() {
    local disk="$1"
    local json="$2"

    if [[ -z "$json" ]]; then
        return 1
    fi

    # Extract common fields
    local smart_status=$(echo "$json" | grep -oP '"passed"\s*:\s*\K(true|false)' | head -1)
    local temperature=$(echo "$json" | grep -oP '"temperature"\s*:\s*\{\s*"current"\s*:\s*\K[0-9]+' | head -1)
    local power_on_hours=$(echo "$json" | grep -oP '"power_on_time"\s*:\s*\{\s*"hours"\s*:\s*\K[0-9]+' | head -1)
    local model_family=$(echo "$json" | grep -oP '"model_family"\s*:\s*"\K[^"]*' | head -1)

    # SMART Status
    if [[ "$smart_status" == "true" ]]; then
        echo "│   $(get_label "smart_status"): PASSED"
    elif [[ "$smart_status" == "false" ]]; then
        echo "│   $(get_label "smart_status"): ${RED}FAILED${NC}"
    else
        echo "│   $(get_label "smart_status"): $(get_label "no_info")"
    fi

    # Power on hours
    if [[ -n "$power_on_hours" ]]; then
        echo "│   $(get_label "power_on_hours"): ${power_on_hours} hours"
    fi

    # Data transfer - check if NVMe
    if [[ "$disk" =~ nvme ]]; then
        # NVMe: data_units_read/written (each unit = 512 * 1000 bytes)
        local data_units_read=$(echo "$json" | grep -oP '"data_units_read"\s*:\s*\K[0-9]+' | head -1)
        local data_units_written=$(echo "$json" | grep -oP '"data_units_written"\s*:\s*\K[0-9]+' | head -1)

        if [[ -n "$data_units_read" && "$data_units_read" != "0" ]]; then
            local bytes_read=$((data_units_read * 512000))
            local formatted=$(format_bytes "$bytes_read")
            [[ -n "$formatted" ]] && echo "│   $(get_label "total_reads"): $formatted"
        fi

        if [[ -n "$data_units_written" && "$data_units_written" != "0" ]]; then
            local bytes_written=$((data_units_written * 512000))
            local formatted=$(format_bytes "$bytes_written")
            [[ -n "$formatted" ]] && echo "│   $(get_label "total_writes"): $formatted"
        fi

        # NVMe health info
        local percentage_used=$(echo "$json" | grep -oP '"percentage_used"\s*:\s*\K[0-9]+' | head -1)
        local available_spare=$(echo "$json" | grep -oP '"available_spare"\s*:\s*\K[0-9]+' | head -1)
        local critical_warning=$(echo "$json" | grep -oP '"critical_warning"\s*:\s*\K[0-9]+' | head -1)

        if [[ -n "$percentage_used" ]]; then
            echo "│   $(get_label "percentage_used"): ${percentage_used}%"
            local health=$((100 - percentage_used))
            [[ $health -lt 0 ]] && health=0
            echo "│   $(get_label "health_status"): ${health}%"
        fi

        if [[ -n "$available_spare" ]]; then
            echo "│   $(get_label "available_spare"): ${available_spare}%"
        fi

        if [[ -n "$critical_warning" && "$critical_warning" != "0" ]]; then
            echo "│   $(get_label "critical_warning"): ${critical_warning}"
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
        local lba_written=""
        local lba_read=""
        local write_multiplier=512  # Default: LBA size in bytes
        local read_multiplier=512

        # Method 1: Try using jq if available (most reliable)
        if command -v jq >/dev/null 2>&1; then
            # Try common attribute IDs for writes: 241, 246, 248
            lba_written=$(echo "$json" | jq -r '.ata_smart_attributes.table[] | select(.id == 241) | .raw.value' 2>/dev/null)
            if [[ -z "$lba_written" || "$lba_written" == "null" ]]; then
                lba_written=$(echo "$json" | jq -r '.ata_smart_attributes.table[] | select(.id == 246) | .raw.value' 2>/dev/null)
            fi
            if [[ -z "$lba_written" || "$lba_written" == "null" ]]; then
                # ID 248: Host_Writes_32MiB - value is in 32MiB units
                lba_written=$(echo "$json" | jq -r '.ata_smart_attributes.table[] | select(.id == 248) | .raw.value' 2>/dev/null)
                if [[ -n "$lba_written" && "$lba_written" != "null" ]]; then
                    write_multiplier=$((32 * 1024 * 1024))  # 32 MiB
                fi
            fi

            # Try common attribute IDs for reads: 242, 247
            lba_read=$(echo "$json" | jq -r '.ata_smart_attributes.table[] | select(.id == 242) | .raw.value' 2>/dev/null)
            if [[ -z "$lba_read" || "$lba_read" == "null" ]]; then
                # ID 247: Host_Reads_32MiB - value is in 32MiB units
                lba_read=$(echo "$json" | jq -r '.ata_smart_attributes.table[] | select(.id == 247) | .raw.value' 2>/dev/null)
                if [[ -n "$lba_read" && "$lba_read" != "null" ]]; then
                    read_multiplier=$((32 * 1024 * 1024))  # 32 MiB
                fi
            fi
        fi

        # Method 2: Fallback to grep if jq not available or failed
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
            [[ -n "$formatted" ]] && echo "│   $(get_label "total_reads"): $formatted"
        fi

        if [[ -n "$lba_written" && "$lba_written" != "0" && "$lba_written" != "null" ]]; then
            local bytes_written=$((lba_written * write_multiplier))
            local formatted=$(format_bytes "$bytes_written")
            [[ -n "$formatted" ]] && echo "│   $(get_label "total_writes"): $formatted"
        fi

        # Track if we found any I/O stats
        local io_stats_found=false
        [[ -n "$lba_read" && "$lba_read" != "0" && "$lba_read" != "null" ]] && io_stats_found=true
        [[ -n "$lba_written" && "$lba_written" != "0" && "$lba_written" != "null" ]] && io_stats_found=true

        # For SSDs without read/write stats, try to show wear level indicator
        if [[ "$io_stats_found" == false ]]; then
            local wear_level=""
            if command -v jq >/dev/null 2>&1; then
                # ID 177: Wear_Leveling_Count (Samsung, etc.)
                # ID 231: SSD_Life_Left (various)
                # ID 233: Media_Wearout_Indicator (Intel)
                wear_level=$(echo "$json" | jq -r '.ata_smart_attributes.table[] | select(.id == 177 or .id == 231 or .id == 233) | .value' 2>/dev/null | head -1)
            fi
            if [[ -z "$wear_level" || "$wear_level" == "null" ]]; then
                wear_level=$(echo "$json" | grep -A10 '"Wear_Leveling_Count"\|"SSD_Life_Left"\|"Media_Wearout_Indicator"' | grep -oP '"value"\s*:\s*\K[0-9]+' | head -1)
            fi
            if [[ -n "$wear_level" && "$wear_level" != "null" && "$wear_level" != "0" ]]; then
                echo "│   $(get_label "wear_level"): ${wear_level}%"
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
                    echo "│   → 如需支持请提交: smartctl -a -j /dev/$disk"
                    echo "│   → 反馈地址: https://github.com/Yuri-NagaSaki/SICK/issues"
                else
                    echo "│   I/O Stats: Not supported for this drive model"
                    echo "│   → To request support: smartctl -a -j /dev/$disk"
                    echo "│   → Report to: https://github.com/Yuri-NagaSaki/SICK/issues"
                fi
            fi
        fi
    fi

    # Temperature
    if [[ -n "$temperature" ]]; then
        echo "│   $(get_label "temperature"): ${temperature}°C"
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

    local smart_all=$(smartctl -a "/dev/$disk" 2>/dev/null)
    if [[ -z "$smart_all" ]]; then
        return 1
    fi

    # SMART Status
    local smart_health=$(echo "$smart_all" | grep -E "SMART overall-health|SMART Health Status" | awk -F': ' '{print $2}')
    echo "│   $(get_label "smart_status"): ${smart_health:-$(get_label "no_info")}"

    # Power on hours
    local power_hours=""
    power_hours=$(echo "$smart_all" | grep -i "power.on" | grep -i hour | head -1 | grep -oE '[0-9,]+' | tr -d ',' | head -1)
    [[ -n "$power_hours" ]] && echo "│   $(get_label "power_on_hours"): ${power_hours} hours"

    # Temperature
    local temp=""
    temp=$(echo "$smart_all" | grep -iE "^Temperature:|Temperature_Celsius" | grep -oE '[0-9]+' | head -1)
    [[ -n "$temp" ]] && echo "│   $(get_label "temperature"): ${temp}°C"

    # NVMe specific
    if [[ "$disk" =~ nvme ]]; then
        # Data units (with human readable in parentheses)
        local reads=$(echo "$smart_all" | grep -i "Data Units Read" | grep -oE '\([^)]+\)' | tr -d '()' | head -1)
        local writes=$(echo "$smart_all" | grep -i "Data Units Written" | grep -oE '\([^)]+\)' | tr -d '()' | head -1)
        [[ -n "$reads" ]] && echo "│   $(get_label "total_reads"): $reads"
        [[ -n "$writes" ]] && echo "│   $(get_label "total_writes"): $writes"

        # Percentage used
        local pct_used=$(echo "$smart_all" | grep -i "Percentage Used" | grep -oE '[0-9]+' | head -1)
        if [[ -n "$pct_used" ]]; then
            echo "│   $(get_label "percentage_used"): ${pct_used}%"
            echo "│   $(get_label "health_status"): $((100 - pct_used))%"
        fi

        # Available spare
        local spare=$(echo "$smart_all" | grep -i "Available Spare:" | grep -oE '[0-9]+' | head -1)
        [[ -n "$spare" ]] && echo "│   $(get_label "available_spare"): ${spare}%"
    fi

    # ==========================================================================
    # Bad Blocks Detection (Text Parsing Fallback)
    # ==========================================================================
    # Call the universal bad blocks detection function with text input
    # ==========================================================================
    detect_bad_blocks "text" "$smart_all"

    return 0
}

# Function to get disk information with enhanced SMART data
get_disk_info() {
    print_subsection "$(get_label "disk_info")"

    # Disk usage
    df -h | grep -E '^/dev/' | while IFS= read -r line; do
        echo "│ $line"
    done

    echo "│"
    print_color "$GREEN" "│ Physical Disks Details:"

    # Physical disk information with enhanced details
    for disk in $(lsblk -d -n -o NAME | grep -E '^[sv]d[a-z]$|^nvme[0-9]+n[0-9]+$|^mmcblk[0-9]+$'); do
        echo "│"
        print_color "$CYAN" "│ ═══ /dev/$disk ═══"

        # Basic disk information
        local disk_info=$(lsblk -d -n -o SIZE,MODEL,VENDOR "/dev/$disk" 2>/dev/null | sed 's/  */ /g')
        echo "│   Basic Info: $disk_info"

        # SMART information
        if command -v smartctl >/dev/null 2>&1; then
            # Check smartctl version for JSON support (7.0+)
            local smartctl_version=$(smartctl --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
            local use_json=false

            if [[ -n "$smartctl_version" ]]; then
                local major_version=$(echo "$smartctl_version" | cut -d. -f1)
                [[ "$major_version" -ge 7 ]] && use_json=true
            fi

            # Try JSON parsing first (more reliable)
            local parsed=false
            if [[ "$use_json" == true ]]; then
                local json_data=$(get_smart_json "$disk")
                if [[ -n "$json_data" ]]; then
                    # Check if this is a RAID controller virtual disk
                    if is_raid_controller_disk "$disk" "$json_data"; then
                        # Extract RAID controller info
                        local scsi_vendor=$(echo "$json_data" | grep -oP '"scsi_vendor"\s*:\s*"\K[^"]*' | head -1)
                        local scsi_product=$(echo "$json_data" | grep -oP '"scsi_product"\s*:\s*"\K[^"]*' | head -1)

                        if [[ "$LANG_MODE" == "cn" ]]; then
                            echo "│   类型: 硬件RAID阵列"
                            echo "│   控制器: $scsi_vendor $scsi_product"
                        else
                            echo "│   Type: Hardware RAID Array"
                            echo "│   Controller: $scsi_vendor $scsi_product"
                        fi

                        # Display member disks
                        display_megaraid_disks "$disk"
                        parsed=true
                    else
                        parse_smart_json "$disk" "$json_data" && parsed=true
                    fi
                fi
            fi

            # Fallback to text parsing
            if [[ "$parsed" == false ]]; then
                parse_smart_text "$disk" || echo "│   SMART: $(get_label "not_detected")"
            fi
        else
            # smartctl not installed
            if [[ "$LANG_MODE" == "cn" ]]; then
                echo "│   SMART状态: smartctl未安装"
            else
                echo "│   SMART Status: smartctl not installed"
            fi
        fi
    done

    echo "└$(printf '─%.0s' $(seq 1 50))"
}

# Function to get RAID information
get_raid_info() {
    print_subsection "$(get_label "raid_info")"
    
    local raid_found=false
    
    # Check for software RAID
    if [[ -f /proc/mdstat ]]; then
        local md_info=$(cat /proc/mdstat | grep -E '^md[0-9]')
        if [[ -n "$md_info" ]]; then
            echo "│ Software RAID:"
            echo "$md_info" | while IFS= read -r line; do
                echo "│   $line"
            done
            raid_found=true
        fi
    fi
    
    # Check for hardware RAID controllers
    if command -v lspci >/dev/null 2>&1; then
        local raid_controllers=$(lspci | grep -i raid)
        if [[ -n "$raid_controllers" ]]; then
            echo "│ Hardware RAID Controllers:"
            echo "$raid_controllers" | while IFS= read -r line; do
                echo "│   $line"
            done
            raid_found=true
        fi
    fi
    
    if [[ "$raid_found" == false ]]; then
        print_info "$(get_label "status")" "$(get_label "not_detected")"
    fi
    
    echo "└$(printf '─%.0s' $(seq 1 50))"
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
            local masked_half=$(printf "X%.0s" $(seq 1 $((len-half))))
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
    
    # Network interfaces with enhanced information (physical only)
    for interface in $(ip link show 2>/dev/null | grep -E '^[0-9]+:' | cut -d':' -f2 | sed 's/^ *//' | grep -v lo); do
        # Skip virtual interfaces
        if ! is_physical_interface "$interface"; then
            continue
        fi
        echo "│"
        print_color "$CYAN" "│ ═══ $interface ═══"
        
        # Get PCI device path for this interface
        local pci_path=""
        local device_path="/sys/class/net/$interface/device"
        if [[ -L "$device_path" ]]; then
            local real_path=$(readlink -f "$device_path" 2>/dev/null)
            if [[ -n "$real_path" ]]; then
                pci_path=$(basename "$real_path")
            fi
        fi
        
        # Network card model/vendor information
        local nic_model=""
        local nic_vendor=""
        
        if [[ -n "$pci_path" ]] && command -v lspci >/dev/null 2>&1; then
            local pci_info=$(lspci -s "$pci_path" 2>/dev/null | head -1)
            if [[ -n "$pci_info" ]]; then
                # Extract model info from lspci output
                nic_model=$(echo "$pci_info" | cut -d':' -f3- | sed 's/^ *//')
                echo "│   $(get_label "model"): $nic_model"
            fi
        fi
        
        # Alternative method using ethtool
        if [[ -z "$nic_model" ]] && command -v ethtool >/dev/null 2>&1; then
            local ethtool_info=$(ethtool -i "$interface" 2>/dev/null)
            if [[ -n "$ethtool_info" ]]; then
                nic_vendor=$(echo "$ethtool_info" | grep "driver:" | cut -d':' -f2 | sed 's/^ *//')
                local bus_info=$(echo "$ethtool_info" | grep "bus-info:" | cut -d':' -f2- | sed 's/^ *//')
                if [[ -n "$bus_info" ]]; then
                    echo "│   $(get_label "model"): $nic_vendor ($bus_info)"
                fi
            fi
        fi
        
        # Try to get vendor info from sysfs
        if [[ -z "$nic_model" ]]; then
            local vendor_file="/sys/class/net/$interface/device/vendor"
            local device_file="/sys/class/net/$interface/device/device"
            if [[ -r "$vendor_file" && -r "$device_file" ]]; then
                local vendor_id=$(cat "$vendor_file" 2>/dev/null)
                local device_id=$(cat "$device_file" 2>/dev/null)
                if [[ -n "$vendor_id" && -n "$device_id" ]]; then
                    echo "│   Device ID: $vendor_id:$device_id"
                fi
            fi
        fi
        
        # Interface status
        local status=$(ip link show "$interface" 2>/dev/null | grep -o "state [A-Z]*" | cut -d' ' -f2)
        echo "│   $(get_label "status"): ${status:-"Unknown"}"
        
        # IP addresses (with privacy masking)
        local ipv4=$(ip addr show "$interface" 2>/dev/null | grep "inet " | head -1 | awk '{print $2}')
        local ipv6=$(ip addr show "$interface" 2>/dev/null | grep "inet6" | head -1 | awk '{print $2}')
        
        if [[ -n "$ipv4" ]]; then
            local masked_ipv4=$(mask_ip_address "$ipv4")
            echo "│   IPv4: $masked_ipv4"
        fi
        if [[ -n "$ipv6" ]]; then
            local masked_ipv6=$(mask_ip_address "$ipv6")
            echo "│   IPv6: $masked_ipv6"
        fi
        
        # MAC address (with privacy masking)
        local mac=$(ip link show "$interface" 2>/dev/null | grep "link/ether" | awk '{print $2}')
        if [[ -n "$mac" ]]; then
            local masked_mac=$(mask_mac_address "$mac")
            echo "│   $(get_label "mac_address"): $masked_mac"
        fi
        
        # Speed and duplex information
        local speed_file="/sys/class/net/$interface/speed"
        local duplex_file="/sys/class/net/$interface/duplex"
        
        if [[ -r "$speed_file" ]]; then
            local speed=$(cat "$speed_file" 2>/dev/null)
            if [[ "$speed" != "-1" && -n "$speed" ]]; then
                echo "│   $(get_label "speed"): ${speed} Mbps"
            fi
        fi
        
        if [[ -r "$duplex_file" ]]; then
            local duplex=$(cat "$duplex_file" 2>/dev/null)
            if [[ -n "$duplex" ]]; then
                echo "│   $(get_label "duplex"): $duplex"
            fi
        fi
        
        # Link detection
        local carrier_file="/sys/class/net/$interface/carrier"
        if [[ -r "$carrier_file" ]]; then
            local carrier=$(cat "$carrier_file" 2>/dev/null)
            if [[ "$carrier" == "1" ]]; then
                echo "│   $(get_label "link_detected"): Yes"
            else
                echo "│   $(get_label "link_detected"): No"
            fi
        fi
        

        
        # Network statistics with smart unit selection
        local rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null)
        local tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null)
        
        if [[ -n "$rx_bytes" ]]; then
            local rx_gb=$(echo "scale=2; $rx_bytes / 1024 / 1024 / 1024" | bc -l 2>/dev/null)
            # Add leading zero if needed and choose appropriate unit
            if [[ -n "$rx_gb" ]]; then
                # Add leading zero for decimal numbers starting with dot
                if [[ "$rx_gb" =~ ^\. ]]; then
                    rx_gb="0$rx_gb"
                fi
                # Convert to TB if >= 1024 GB
                if [[ $(echo "$rx_gb > 1024" | bc -l 2>/dev/null) -eq 1 ]]; then
                    local rx_tb=$(echo "scale=2; $rx_gb / 1024" | bc -l 2>/dev/null)
                    # Add leading zero for TB as well
                    if [[ "$rx_tb" =~ ^\. ]]; then
                        rx_tb="0$rx_tb"
                    fi
                    echo "│   RX: ${rx_tb} TB"
                else
                    echo "│   RX: ${rx_gb} GB"
                fi
            else
                echo "│   RX: 0.00 GB"
            fi
        fi
        
        if [[ -n "$tx_bytes" ]]; then
            local tx_gb=$(echo "scale=2; $tx_bytes / 1024 / 1024 / 1024" | bc -l 2>/dev/null)
            # Add leading zero if needed and choose appropriate unit
            if [[ -n "$tx_gb" ]]; then
                # Add leading zero for decimal numbers starting with dot
                if [[ "$tx_gb" =~ ^\. ]]; then
                    tx_gb="0$tx_gb"
                fi
                # Convert to TB if >= 1024 GB
                if [[ $(echo "$tx_gb > 1024" | bc -l 2>/dev/null) -eq 1 ]]; then
                    local tx_tb=$(echo "scale=2; $tx_gb / 1024" | bc -l 2>/dev/null)
                    # Add leading zero for TB as well
                    if [[ "$tx_tb" =~ ^\. ]]; then
                        tx_tb="0$tx_tb"
                    fi
                    echo "│   TX: ${tx_tb} TB"
                else
                    echo "│   TX: ${tx_gb} GB"
                fi
            else
                echo "│   TX: 0.00 GB"
            fi
        fi
    done
    
    echo "└$(printf '─%.0s' $(seq 1 50))"
}

# Function to get GPU information
get_gpu_info() {
    print_subsection "$(get_label "gpu_info")"
    
    local gpu_found=false
    
    # NVIDIA GPUs
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "│"
        print_color "$GREEN" "│ NVIDIA Graphics Cards:"
        
        # Get NVIDIA GPU information
        nvidia-smi --query-gpu=name,memory.total,driver_version,temperature.gpu,power.draw,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r name memory driver temp power util; do
            echo "│   ═══ $(echo "$name" | xargs) ═══"
            echo "│   $(get_label "memory"): $(echo "$memory" | xargs) MB"
            echo "│   $(get_label "driver"): $(echo "$driver" | xargs)"
            echo "│   $(get_label "temperature"): $(echo "$temp" | xargs)°C"
            echo "│   Power Draw: $(echo "$power" | xargs) W"
            echo "│   GPU Usage: $(echo "$util" | xargs)%"
            echo "│"
        done
        gpu_found=true
    fi
    
    # AMD GPUs
    if command -v rocm-smi >/dev/null 2>&1; then
        echo "│"
        print_color "$GREEN" "│ AMD Graphics Cards:"
        rocm-smi --showproductname --showmeminfo --showtemp 2>/dev/null | grep -E "Card|Memory|Temperature" | while IFS= read -r line; do
            echo "│   $line"
        done
        gpu_found=true
    fi
    
    # Intel GPUs and general GPU detection
    if command -v lspci >/dev/null 2>&1; then
        local gpu_devices=$(lspci | grep -E "(VGA|3D|Display)" | grep -v "Audio")
        if [[ -n "$gpu_devices" ]]; then
            if [[ "$gpu_found" == false ]]; then
                echo "│"
                print_color "$GREEN" "│ Graphics Cards (PCI):"
            fi
            echo "$gpu_devices" | while IFS= read -r line; do
                echo "│   $line"
            done
            gpu_found=true
        fi
    fi
    
    # Additional GPU information from lshw
    if command -v lshw >/dev/null 2>&1; then
        local gpu_lshw=$(lshw -c display -short 2>/dev/null | grep -v "H/W path")
        if [[ -n "$gpu_lshw" ]]; then
            echo "│"
            print_color "$GREEN" "│ Display Hardware Summary:"
            echo "$gpu_lshw" | while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    echo "│   $line"
                fi
            done
            gpu_found=true
        fi
    fi
    
    if [[ "$gpu_found" == false ]]; then
        print_info "$(get_label "status")" "$(get_label "not_detected")"
    fi
    
    echo "└$(printf '─%.0s' $(seq 1 50))"
}

# Function to get motherboard information
get_motherboard_info() {
    print_subsection "$(get_label "motherboard_info")"
    
    if command -v dmidecode >/dev/null 2>&1; then
        local mb_vendor=$(dmidecode -s baseboard-manufacturer 2>/dev/null)
        local mb_product=$(dmidecode -s baseboard-product-name 2>/dev/null)
        local mb_version=$(dmidecode -s baseboard-version 2>/dev/null)
        local bios_vendor=$(dmidecode -s bios-vendor 2>/dev/null)
        local bios_version=$(dmidecode -s bios-version 2>/dev/null)
        
        print_info "$(get_label "vendor")" "${mb_vendor:-$(get_label "no_info")}"
        print_info "$(get_label "model")" "${mb_product:-$(get_label "no_info")}"
        print_info "Version" "${mb_version:-$(get_label "no_info")}"
        print_info "BIOS Vendor" "${bios_vendor:-$(get_label "no_info")}"
        print_info "BIOS Version" "${bios_version:-$(get_label "no_info")}"
    else
        print_info "$(get_label "status")" "$(get_label "no_info") (dmidecode required)"
    fi
    
    echo "└$(printf '─%.0s' $(seq 1 50))"
}



# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Hardware Information Collection Script v$VERSION

OPTIONS:
    -cn, --chinese     Display output in Chinese
    -us, --english     Display output in English (default)
    -h, --help         Show this help message
    -v, --version      Show version information

FEATURES:
    - Automatically saves report to txt file in current directory
    - File format: hardware_report_[hostname]_[timestamp].txt
    - Supports bilingual output (English/Chinese)
    - Comprehensive hardware detection

Supported Distributions:
    - Debian/Ubuntu/Linux Mint
    - CentOS/RHEL/AlmaLinux/Rocky Linux/CloudLinux
    - Fedora
    - Arch Linux/Manjaro
    - openSUSE/SLES
    - Alpine Linux

Examples:
    $0                 # Show hardware info in English & save to file
    $0 -cn             # Show hardware info in Chinese & save to file
    $0 --chinese       # Show hardware info in Chinese & save to file

Note: Run with sudo for complete hardware information access.

EOF
}

# Function to show version
show_version() {
    echo "$SCRIPT_NAME v$VERSION"
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
    
    # Generate report filename with timestamp
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local hostname_clean=$(hostname | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g')
    local report_file="hardware_report_${hostname_clean}_${timestamp}.txt"
    
    # Check if running as root for some commands
    if [[ $EUID -ne 0 ]]; then
        print_color "$YELLOW" "Note: Some hardware information requires root privileges."
        print_color "$YELLOW" "Run with sudo for complete information."
        echo
    fi
    
    # Install required packages
    print_color "$BLUE" "$(get_label "generating")"
    echo
    
    if ! install_packages; then
        # Installation failed or incomplete
        if [[ "$LANG_MODE" == "cn" ]]; then
            echo "⚠️  某些工具缺失，硬件信息可能不完整。"
            echo "您可以选择："
            echo "1. 继续生成报告（某些信息可能缺失）"
            echo "2. 手动安装缺失的软件包后重新运行脚本"
        else
            echo "⚠️  Some tools are missing, hardware information may be incomplete."
            echo "You can choose to:"
            echo "1. Continue generating report (some information may be missing)"
            echo "2. Manually install missing packages and re-run the script"
        fi
        echo
        
        read -p "Continue anyway? [y/N]: " -r choice
        case "$choice" in
            [Yy]*)
                if [[ "$LANG_MODE" == "cn" ]]; then
                    echo "继续生成报告..."
                else
                    echo "Continuing with report generation..."
                fi
                ;;
            *)
                if [[ "$LANG_MODE" == "cn" ]]; then
                    echo "脚本已退出。请安装所需软件包后重新运行。"
                else
                    echo "Script exited. Please install required packages and re-run."
                fi
                exit 1
                ;;
        esac
        echo
    fi
    
    # Generate report and save to file using a function
    generate_report() {
        # Print title
        print_header "$(get_label "title")"
        
        # Collect all hardware information
        get_system_info
        get_cpu_info
        get_ram_info
        get_disk_info
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
    
    # Generate report both to screen and file
    echo "Generating report to screen and file: $report_file"
    echo
    
    # Use tee to output to both screen and file, but strip ANSI color codes from file
    generate_report | tee >(sed 's/\x1b\[[0-9;]*m//g' > "$report_file")
    
    # Final message about saved file
    echo
    if [[ "$LANG_MODE" == "cn" ]]; then
        print_color "$GREEN" "✓ 报告已保存到文件: $report_file"
        print_color "$CYAN" "文件大小: $(du -h "$report_file" 2>/dev/null | cut -f1 || echo "未知")"
        print_color "$CYAN" "文件路径: $(pwd)/$report_file"
    else
        print_color "$GREEN" "✓ Report saved to file: $report_file"
        print_color "$CYAN" "File size: $(du -h "$report_file" 2>/dev/null | cut -f1 || echo "Unknown")"
        print_color "$CYAN" "File path: $(pwd)/$report_file"
    fi
    echo
}

# Run main function
main "$@"
