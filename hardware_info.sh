#!/bin/bash

# Hardware Information Collection Script
# 硬件信息收集脚本
# Compatible with Debian/Ubuntu/CentOS/AlmaLinux/Rocky Linux/CloudLinux/Arch Linux/openSUSE/Fedora/Alpine Linux
# 兼容 Debian/Ubuntu/CentOS/AlmaLinux/Rocky Linux/CloudLinux/Arch Linux/openSUSE/Fedora/Alpine Linux

VERSION="2.3.0"
SCRIPT_NAME="Hardware Info Collector"

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
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null)
    print_info "$(get_label "usage")" "${cpu_usage:+${cpu_usage}%}"
    
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
        
        rm -f "$temp_file"
        
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
        local disk_info=$(lsblk -d -n -o SIZE,MODEL,VENDOR "/dev/$disk" 2>/dev/null)
        echo "│   Basic Info: $disk_info"
        
        # SMART information
        if command -v smartctl >/dev/null 2>&1; then
            # Try different methods to check SMART support
            local smart_check=""
            
            # For NVMe drives, try without -d option first
            if [[ "$disk" =~ nvme ]]; then
                smart_check=$(smartctl -i "/dev/$disk" 2>/dev/null)
                if [[ -z "$smart_check" ]]; then
                    smart_check=$(smartctl -d nvme -i "/dev/$disk" 2>/dev/null)
                fi
            else
                smart_check=$(smartctl -i "/dev/$disk" 2>/dev/null)
            fi
            
            # Check if device responds to SMART commands
            if [[ -n "$smart_check" ]] && [[ ! "$smart_check" =~ "Unable to detect device type" ]]; then
                local smart_health=$(smartctl -H "/dev/$disk" 2>/dev/null | grep "SMART overall-health" | awk -F': ' '{print $2}')
                echo "│   $(get_label "smart_status"): ${smart_health:-"$(get_label "no_info")"}"
                
                # Get all SMART attributes with device-specific methods
                local smart_data=""
                local smart_all=""
                
                if [[ "$disk" =~ nvme ]]; then
                    smart_data=$(smartctl -A "/dev/$disk" 2>/dev/null)
                    smart_all=$(smartctl -a "/dev/$disk" 2>/dev/null)
                    if [[ -z "$smart_data" ]]; then
                        smart_data=$(smartctl -d nvme -A "/dev/$disk" 2>/dev/null)
                        smart_all=$(smartctl -d nvme -a "/dev/$disk" 2>/dev/null)
                    fi
                else
                    smart_data=$(smartctl -A "/dev/$disk" 2>/dev/null)
                    smart_all=$(smartctl -a "/dev/$disk" 2>/dev/null)
                fi
                
                # Power on hours - try multiple sources
                local power_hours=""
                # Traditional SMART attribute
                power_hours=$(echo "$smart_data" | grep -E "Power_On_Hours|9 Power_On_Hours|Power On Hours" | head -1 | awk '{print $10}')
                if [[ -z "$power_hours" ]]; then
                    power_hours=$(echo "$smart_data" | grep -E "^[ ]*9[ ]" | awk '{print $10}')
                fi
                # NVMe format
                if [[ -z "$power_hours" ]]; then
                    power_hours=$(echo "$smart_all" | grep -i "power on hours" | awk '{print $4}' | tr -d '[]')
                fi
                # Alternative format
                if [[ -z "$power_hours" ]]; then
                    power_hours=$(echo "$smart_data" | grep -i "power.on\|power_on" | awk '{print $NF}' | tr -d 'h[]')
                fi
                echo "│   $(get_label "power_on_hours"): ${power_hours:-"$(get_label "no_info")"} hours"
                
                # Data read/written - comprehensive detection
                echo "│   Data Transfer Statistics:"
                
                local data_found=false
                
                # Method 1: For NVMe drives - use NVMe specific commands
                if [[ "$disk" =~ nvme ]]; then
                    # Try nvme command first (most accurate for NVMe drives)
                    local nvme_reads_converted=""
                    local nvme_writes_converted=""
                    
                    if command -v nvme >/dev/null 2>&1; then
                        local nvme_log=$(nvme smart-log "/dev/$disk" 2>/dev/null)
                        if [[ -n "$nvme_log" ]]; then
                            nvme_reads_converted=$(echo "$nvme_log" | grep "Data Units Read" | grep -o '([^)]*[PTGM]B)' | tr -d '()' | head -1)
                            nvme_writes_converted=$(echo "$nvme_log" | grep "Data Units Written" | grep -o '([^)]*[PTGM]B)' | tr -d '()' | head -1)
                        fi
                    fi
                    
                    # Fallback: try to get the converted values directly from smartctl output
                    if [[ -z "$nvme_reads_converted" ]]; then
                        nvme_reads_converted=$(echo "$smart_all" | grep -i "data units read" | grep -o '([^)]*[PTGM]B)' | tr -d '()' | head -1)
                    fi
                    if [[ -z "$nvme_writes_converted" ]]; then
                        nvme_writes_converted=$(echo "$smart_all" | grep -i "data units written" | grep -o '([^)]*[PTGM]B)' | tr -d '()' | head -1)
                    fi
                    
                    if [[ -n "$nvme_reads_converted" ]]; then
                        echo "│     $(get_label "total_reads"): $nvme_reads_converted"
                        data_found=true
                    elif [[ -n "$(echo "$smart_all" | grep -i "data units read")" ]]; then
                        # Fallback: calculate from raw data units (NVMe spec: 1 data unit = 512 * 1000 bytes = 512KB)
                        local nvme_reads=$(echo "$smart_all" | grep -i "data units read" | awk '{print $4}' | tr -d '[],' | head -1)
                        if [[ -n "$nvme_reads" && "$nvme_reads" != "0" ]]; then
                            # Convert: data_units * 512 * 1000 / 1024^3 for GB, / 1024^4 for TB, / 1024^5 for PB
                            local nvme_reads_pb=$(echo "scale=2; $nvme_reads * 512 * 1000 / 1024 / 1024 / 1024 / 1024 / 1024" | bc -l 2>/dev/null)
                            local nvme_reads_tb=$(echo "scale=2; $nvme_reads * 512 * 1000 / 1024 / 1024 / 1024 / 1024" | bc -l 2>/dev/null)
                            if [[ $(echo "$nvme_reads_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                echo "│     $(get_label "total_reads"): ${nvme_reads_pb} PB"
                            elif [[ $(echo "$nvme_reads_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                echo "│     $(get_label "total_reads"): ${nvme_reads_tb} TB"
                            else
                                local nvme_reads_gb=$(echo "scale=2; $nvme_reads * 512 * 1000 / 1024 / 1024 / 1024" | bc -l 2>/dev/null)
                                echo "│     $(get_label "total_reads"): ${nvme_reads_gb} GB"
                            fi
                            data_found=true
                        fi
                    fi
                    
                    if [[ -n "$nvme_writes_converted" ]]; then
                        echo "│     $(get_label "total_writes"): $nvme_writes_converted"
                        data_found=true
                    elif [[ -n "$(echo "$smart_all" | grep -i "data units written")" ]]; then
                        # Fallback: calculate from raw data units (NVMe spec: 1 data unit = 512 * 1000 bytes = 512KB)
                        local nvme_writes=$(echo "$smart_all" | grep -i "data units written" | awk '{print $4}' | tr -d '[],' | head -1)
                        if [[ -n "$nvme_writes" && "$nvme_writes" != "0" ]]; then
                            # Convert: data_units * 512 * 1000 / 1024^3 for GB, / 1024^4 for TB, / 1024^5 for PB
                            local nvme_writes_pb=$(echo "scale=2; $nvme_writes * 512 * 1000 / 1024 / 1024 / 1024 / 1024 / 1024" | bc -l 2>/dev/null)
                            local nvme_writes_tb=$(echo "scale=2; $nvme_writes * 512 * 1000 / 1024 / 1024 / 1024 / 1024" | bc -l 2>/dev/null)
                            if [[ $(echo "$nvme_writes_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                echo "│     $(get_label "total_writes"): ${nvme_writes_pb} PB"
                            elif [[ $(echo "$nvme_writes_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                echo "│     $(get_label "total_writes"): ${nvme_writes_tb} TB"
                            else
                                local nvme_writes_gb=$(echo "scale=2; $nvme_writes * 512 * 1000 / 1024 / 1024 / 1024" | bc -l 2>/dev/null)
                                echo "│     $(get_label "total_writes"): ${nvme_writes_gb} GB"
                            fi
                            data_found=true
                        fi
                    fi
                else
                    # Method 1: For SATA/HDD drives - use SMART hardware-level data (PRIORITY METHOD)
                    # Try various SMART attribute patterns for read data (enhanced for more vendors)
                    local reads_lba=""
                    # Method 1: Standard naming patterns
                    reads_lba=$(echo "$smart_data" | grep -E "Total_LBAs_Read|Host_Reads_32MiB" | grep -i read | head -1 | awk '{print $10}')
                    # Method 2: Attribute ID 241 (most common for read LBAs)
                    if [[ -z "$reads_lba" ]]; then
                        reads_lba=$(echo "$smart_data" | grep -E "^[ ]*241[ ]" | awk '{print $10}')
                    fi
                    # Method 3: Attribute ID 242 (some vendors reverse 241/242)
                    if [[ -z "$reads_lba" ]]; then
                        reads_lba=$(echo "$smart_data" | grep -E "^[ ]*242[ ].*[Rr]ead" | awk '{print $10}')
                    fi
                    # Method 4: Alternative IDs for specific vendors
                    if [[ -z "$reads_lba" ]]; then
                        reads_lba=$(echo "$smart_data" | grep -E "^[ ]*246[ ]" | awk '{print $10}') # Some Samsung/SSSTC SSDs
                    fi
                    # Method 5: Other vendor-specific patterns
                    if [[ -z "$reads_lba" ]]; then
                        reads_lba=$(echo "$smart_data" | grep -E "Lifetime_Reads_GiB|Total_Host_Reads|NAND_Reads_GiB" | awk '{print $10}' | head -1)
                    fi
                    
                    # Try various SMART attribute patterns for write data (enhanced for more vendors)
                    local writes_lba=""
                    # Method 1: Standard naming patterns
                    writes_lba=$(echo "$smart_data" | grep -E "Total_LBAs_Written|Host_Writes_32MiB" | grep -i writ | head -1 | awk '{print $10}')
                    # Method 2: Attribute ID 242 (most common for write LBAs)
                    if [[ -z "$writes_lba" ]]; then
                        writes_lba=$(echo "$smart_data" | grep -E "^[ ]*242[ ]" | awk '{print $10}')
                    fi
                    # Method 3: Attribute ID 241 (some vendors reverse 241/242)
                    if [[ -z "$writes_lba" ]]; then
                        writes_lba=$(echo "$smart_data" | grep -E "^[ ]*241[ ].*[Ww]rit" | awk '{print $10}')
                    fi
                    # Method 4: Alternative IDs for specific vendors
                    if [[ -z "$writes_lba" ]]; then
                        writes_lba=$(echo "$smart_data" | grep -E "^[ ]*247[ ]" | awk '{print $10}') # Some Intel/Micron SSDs
                    fi
                    # Method 5: Other vendor-specific patterns
                    if [[ -z "$writes_lba" ]]; then
                        writes_lba=$(echo "$smart_data" | grep -E "Lifetime_Writes_GiB|Total_Host_Writes|NAND_Writes_GiB" | awk '{print $10}' | head -1)
                    fi
                    
                    # Convert LBA and display with enhanced precision for small values
                    if [[ -n "$reads_lba" && "$reads_lba" != "0" ]] && [[ "$reads_lba" =~ ^[0-9]+$ ]]; then
                        local reads_mb=$(echo "scale=3; $reads_lba * 512 / 1024 / 1024" | bc -l 2>/dev/null)
                        local reads_gb=$(echo "scale=3; $reads_mb / 1024" | bc -l 2>/dev/null)
                        local reads_tb=$(echo "scale=3; $reads_gb / 1024" | bc -l 2>/dev/null)
                        local reads_pb=$(echo "scale=3; $reads_tb / 1024" | bc -l 2>/dev/null)
                        
                        # Choose appropriate unit based on magnitude (including PB)
                        if [[ $(echo "$reads_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_reads"): ${reads_pb} PB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_reads"): ${reads_pb} PB (SMART lifetime)"
                            fi
                        elif [[ $(echo "$reads_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_reads"): ${reads_tb} TB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_reads"): ${reads_tb} TB (SMART lifetime)"
                            fi
                        elif [[ $(echo "$reads_gb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_reads"): ${reads_gb} GB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_reads"): ${reads_gb} GB (SMART lifetime)"
                            fi
                        elif [[ $(echo "$reads_mb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_reads"): ${reads_mb} MB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_reads"): ${reads_mb} MB (SMART lifetime)"
                            fi
                        else
                            # For very small values, show in KB
                            local reads_kb=$(echo "scale=1; $reads_lba * 512 / 1024" | bc -l 2>/dev/null)
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_reads"): ${reads_kb} KB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_reads"): ${reads_kb} KB (SMART lifetime)"
                            fi
                        fi
                        data_found=true
                    fi
                    
                    if [[ -n "$writes_lba" && "$writes_lba" != "0" ]] && [[ "$writes_lba" =~ ^[0-9]+$ ]]; then
                        local writes_mb=$(echo "scale=3; $writes_lba * 512 / 1024 / 1024" | bc -l 2>/dev/null)
                        local writes_gb=$(echo "scale=3; $writes_mb / 1024" | bc -l 2>/dev/null)
                        local writes_tb=$(echo "scale=3; $writes_gb / 1024" | bc -l 2>/dev/null)
                        local writes_pb=$(echo "scale=3; $writes_tb / 1024" | bc -l 2>/dev/null)
                        
                        # Choose appropriate unit based on magnitude (including PB)
                        if [[ $(echo "$writes_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_writes"): ${writes_pb} PB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_writes"): ${writes_pb} PB (SMART lifetime)"
                            fi
                        elif [[ $(echo "$writes_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_writes"): ${writes_tb} TB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_writes"): ${writes_tb} TB (SMART lifetime)"
                            fi
                        elif [[ $(echo "$writes_gb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_writes"): ${writes_gb} GB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_writes"): ${writes_gb} GB (SMART lifetime)"
                            fi
                        elif [[ $(echo "$writes_mb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_writes"): ${writes_mb} MB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_writes"): ${writes_mb} MB (SMART lifetime)"
                            fi
                        else
                            # For very small values, show in KB
                            local writes_kb=$(echo "scale=1; $writes_lba * 512 / 1024" | bc -l 2>/dev/null)
                            if [[ "$LANG_MODE" == "cn" ]]; then
                                echo "│     $(get_label "total_writes"): ${writes_kb} KB (SMART硬件累计)"
                            else
                                echo "│     $(get_label "total_writes"): ${writes_kb} KB (SMART lifetime)"
                            fi
                        fi
                        data_found=true
                    fi
                fi
                
                # Method 2: SMART attribute variations (MiB, GiB, TB formats)
                # Method 3: iostat system statistics (fallback - session data only, not lifetime)
                if [[ "$data_found" == false ]] && command -v iostat >/dev/null 2>&1; then
                    # Get session I/O statistics from iostat (WARNING: only since last boot)
                    local iostat_full_output=$(iostat -d "/dev/$disk" 2>/dev/null)
                    if [[ -n "$iostat_full_output" ]]; then
                        # Try to get the last data line (skip headers)
                        local iostat_output=$(echo "$iostat_full_output" | grep "^$disk" | tail -1)
                        
                        # Alternative: get last line that contains numbers
                        if [[ -z "$iostat_output" ]]; then
                            iostat_output=$(echo "$iostat_full_output" | grep -E '[0-9]+\.[0-9]+.*[0-9]+\.[0-9]+' | tail -1)
                        fi
                        
                        if [[ -n "$iostat_output" ]]; then
                            # Parse iostat output: Device tps kB_read/s kB_wrtn/s kB_dscd/s kB_read kB_wrtn kB_dscd
                            local total_read_kb=$(echo "$iostat_output" | awk '{print $6}')
                            local total_write_kb=$(echo "$iostat_output" | awk '{print $7}')
                            
                            # Handle both integer and decimal numbers
                            if [[ -n "$total_read_kb" && "$total_read_kb" != "0" ]] && [[ "$total_read_kb" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                                # Convert KB to MB/GB/TB/PB
                                local reads_mb=$(echo "scale=2; $total_read_kb / 1024" | bc -l 2>/dev/null)
                                local reads_gb=$(echo "scale=2; $reads_mb / 1024" | bc -l 2>/dev/null)
                                local reads_tb=$(echo "scale=2; $reads_gb / 1024" | bc -l 2>/dev/null)
                                local reads_pb=$(echo "scale=2; $reads_tb / 1024" | bc -l 2>/dev/null)
                                
                                if [[ $(echo "$reads_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_reads"): ${reads_pb} PB (本次开机累计)"
                                    else
                                        echo "│     $(get_label "total_reads"): ${reads_pb} PB (session only)"
                                    fi
                                elif [[ $(echo "$reads_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_reads"): ${reads_tb} TB (本次开机累计)"
                                    else
                                        echo "│     $(get_label "total_reads"): ${reads_tb} TB (session only)"
                                    fi
                                elif [[ $(echo "$reads_gb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_reads"): ${reads_gb} GB (本次开机累计)"
                                    else
                                        echo "│     $(get_label "total_reads"): ${reads_gb} GB (session only)"
                                    fi
                                else
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_reads"): ${reads_mb} MB (本次开机累计)"
                                    else
                                        echo "│     $(get_label "total_reads"): ${reads_mb} MB (session only)"
                                    fi
                                fi
                                data_found=true
                            fi
                            
                            if [[ -n "$total_write_kb" && "$total_write_kb" != "0" ]] && [[ "$total_write_kb" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                                # Convert KB to MB/GB/TB/PB
                                local writes_mb=$(echo "scale=2; $total_write_kb / 1024" | bc -l 2>/dev/null)
                                local writes_gb=$(echo "scale=2; $writes_mb / 1024" | bc -l 2>/dev/null)
                                local writes_tb=$(echo "scale=2; $writes_gb / 1024" | bc -l 2>/dev/null)
                                local writes_pb=$(echo "scale=2; $writes_tb / 1024" | bc -l 2>/dev/null)
                                
                                if [[ $(echo "$writes_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_writes"): ${writes_pb} PB (本次开机累计)"
                                    else
                                        echo "│     $(get_label "total_writes"): ${writes_pb} PB (session only)"
                                    fi
                                elif [[ $(echo "$writes_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_writes"): ${writes_tb} TB (本次开机累计)"
                                    else
                                        echo "│     $(get_label "total_writes"): ${writes_tb} TB (session only)"
                                    fi
                                elif [[ $(echo "$writes_gb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_writes"): ${writes_gb} GB (本次开机累计)"
                                    else
                                        echo "│     $(get_label "total_writes"): ${writes_gb} GB (session only)"
                                    fi
                                else
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_writes"): ${writes_mb} MB (本次开机累计)"
                                    else
                                        echo "│     $(get_label "total_writes"): ${writes_mb} MB (session only)"
                                    fi
                                fi
                                data_found=true
                            fi
                        fi
                    fi
                fi
                
                # Method 4: SMART attribute variations (MiB, GiB, TB formats)
                if [[ "$data_found" == false ]]; then
                    # Try different attribute patterns for various vendors and formats
                    local reads_mb=""
                    local reads_gb=""
                    local writes_mb=""
                    local writes_gb=""
                    
                    # Look for MiB format
                    reads_mb=$(echo "$smart_data" | grep -E "Host_Reads_MiB|Lifetime_Reads_MiB|^[ ]*241[ ].*MiB" | awk '{print $10}' | head -1)
                    writes_mb=$(echo "$smart_data" | grep -E "Host_Writes_MiB|Lifetime_Writes_MiB|^[ ]*242[ ].*MiB" | awk '{print $10}' | head -1)
                    
                    # Look for GiB format (standard) - enhanced pattern matching
                    if [[ -z "$reads_mb" ]]; then
                        # Try multiple patterns for reads including attribute ID-based matching
                        reads_gb=$(echo "$smart_data" | grep -E "Host_Reads_GiB|Lifetime_Reads_GiB|Total.*Read.*GiB|^[ ]*242[ ].*Host_Reads_GiB|^[ ]*242[ ].*Reads.*GiB" | awk '{print $10}' | head -1)
                        if [[ -n "$reads_gb" && "$reads_gb" != "0" && "$reads_gb" != "-" ]]; then
                            reads_mb=$(echo "scale=0; $reads_gb * 1024" | bc -l 2>/dev/null)
                        fi
                    fi
                    if [[ -z "$writes_mb" ]]; then
                        # Try multiple patterns for writes including attribute ID-based matching
                        writes_gb=$(echo "$smart_data" | grep -E "Host_Writes_GiB|Lifetime_Writes_GiB|Total.*Writ.*GiB|^[ ]*241[ ].*Host_Writes_GiB|^[ ]*241[ ].*Writes.*GiB" | awk '{print $10}' | head -1)
                        if [[ -n "$writes_gb" && "$writes_gb" != "0" && "$writes_gb" != "-" ]]; then
                            writes_mb=$(echo "scale=0; $writes_gb * 1024" | bc -l 2>/dev/null)
                        fi
                    fi
                    
                    # Look for NAND_Writes_GiB format (SSSTC and other vendors)
                    if [[ -z "$writes_mb" ]]; then
                        local nand_writes_gb=$(echo "$smart_data" | grep -E "NAND_Writes_GiB|^[ ]*243[ ]" | awk '{print $10}' | head -1)
                        if [[ -n "$nand_writes_gb" && "$nand_writes_gb" != "0" ]]; then
                            writes_mb=$(echo "scale=0; $nand_writes_gb * 1024" | bc -l 2>/dev/null)
                        fi
                    fi
                    
                    # Look for NAND_Reads_GiB format (some vendors may have read equivalent)
                    if [[ -z "$reads_mb" ]]; then
                        local nand_reads_gb=$(echo "$smart_data" | grep -E "NAND_Reads_GiB|^[ ]*244[ ]" | awk '{print $10}' | head -1)
                        if [[ -n "$nand_reads_gb" && "$nand_reads_gb" != "0" ]]; then
                            reads_mb=$(echo "scale=0; $nand_reads_gb * 1024" | bc -l 2>/dev/null)
                        fi
                    fi
                    
                    # Look for other vendor-specific GiB formats with enhanced pattern matching
                    if [[ -z "$reads_mb" ]]; then
                        # Check for any attribute with "Read" and GiB, including attribute number matching
                        local generic_reads_gb=$(echo "$smart_data" | grep -i -E "[^_]reads?_gib|reads?.*gib|^[ ]*242[ ].*gib" | awk '{print $10}' | head -1)
                        if [[ -n "$generic_reads_gb" && "$generic_reads_gb" != "0" && "$generic_reads_gb" != "-" ]]; then
                            reads_mb=$(echo "scale=0; $generic_reads_gb * 1024" | bc -l 2>/dev/null)
                        fi
                    fi
                    if [[ -z "$writes_mb" ]]; then
                        # Check for any attribute with "Write" and GiB, including attribute number matching
                        local generic_writes_gb=$(echo "$smart_data" | grep -i -E "[^_]writes?_gib|writes?.*gib|^[ ]*241[ ].*gib" | awk '{print $10}' | head -1)
                        if [[ -n "$generic_writes_gb" && "$generic_writes_gb" != "0" && "$generic_writes_gb" != "-" ]]; then
                            writes_mb=$(echo "scale=0; $generic_writes_gb * 1024" | bc -l 2>/dev/null)
                        fi
                    fi
                    
                    if [[ -n "$reads_mb" && "$reads_mb" != "0" ]]; then
                        local reads_gb=$(echo "scale=2; $reads_mb / 1024" | bc -l 2>/dev/null)
                        local reads_tb=$(echo "scale=2; $reads_gb / 1024" | bc -l 2>/dev/null)
                        local reads_pb=$(echo "scale=2; $reads_tb / 1024" | bc -l 2>/dev/null)
                        if [[ $(echo "$reads_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            echo "│     $(get_label "total_reads"): ${reads_pb} PB (SMART GiB)"
                        elif [[ $(echo "$reads_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            echo "│     $(get_label "total_reads"): ${reads_tb} TB (SMART GiB)"
                        elif [[ $(echo "$reads_gb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            echo "│     $(get_label "total_reads"): ${reads_gb} GB (SMART GiB)"
                        else
                            echo "│     $(get_label "total_reads"): ${reads_mb} MB (SMART GiB)"
                        fi
                        data_found=true
                    fi
                    
                    if [[ -n "$writes_mb" && "$writes_mb" != "0" ]]; then
                        local writes_gb=$(echo "scale=2; $writes_mb / 1024" | bc -l 2>/dev/null)
                        local writes_tb=$(echo "scale=2; $writes_gb / 1024" | bc -l 2>/dev/null)
                        local writes_pb=$(echo "scale=2; $writes_tb / 1024" | bc -l 2>/dev/null)
                        if [[ $(echo "$writes_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            echo "│     $(get_label "total_writes"): ${writes_pb} PB (SMART GiB)"
                        elif [[ $(echo "$writes_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            echo "│     $(get_label "total_writes"): ${writes_tb} TB (SMART GiB)"
                        elif [[ $(echo "$writes_gb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                            echo "│     $(get_label "total_writes"): ${writes_gb} GB (SMART GiB)"
                        else
                            echo "│     $(get_label "total_writes"): ${writes_mb} MB (SMART GiB)"
                        fi
                        data_found=true
                    fi
                fi
                
                # Method 5: Try to get stats from /sys filesystem
                if [[ "$data_found" == false ]]; then
                    local disk_name=$(basename "$disk")
                    local read_sectors_file="/sys/block/$disk_name/stat"
                    if [[ -r "$read_sectors_file" ]]; then
                        # Format: read_ios read_merges read_sectors read_ticks write_ios write_merges write_sectors write_ticks
                        local disk_stats=$(cat "$read_sectors_file" 2>/dev/null)
                        if [[ -n "$disk_stats" ]]; then
                            local read_sectors=$(echo "$disk_stats" | awk '{print $3}')
                            local write_sectors=$(echo "$disk_stats" | awk '{print $7}')
                            
                            # Enhanced validation - ensure we have valid numbers
                            if [[ -n "$read_sectors" && "$read_sectors" != "0" ]] && [[ "$read_sectors" =~ ^[0-9]+$ ]]; then
                                # Convert sectors (512 bytes each) and choose appropriate unit including PB
                                local reads_mb=$(echo "scale=2; $read_sectors * 512 / 1024 / 1024" | bc -l 2>/dev/null)
                                local reads_gb=$(echo "scale=2; $reads_mb / 1024" | bc -l 2>/dev/null)
                                local reads_tb=$(echo "scale=2; $reads_gb / 1024" | bc -l 2>/dev/null)
                                local reads_pb=$(echo "scale=2; $reads_tb / 1024" | bc -l 2>/dev/null)
                                
                                if [[ $(echo "$reads_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_reads"): ${reads_pb} PB (系统统计)"
                                    else
                                        echo "│     $(get_label "total_reads"): ${reads_pb} PB (system stats)"
                                    fi
                                elif [[ $(echo "$reads_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_reads"): ${reads_tb} TB (系统统计)"
                                    else
                                        echo "│     $(get_label "total_reads"): ${reads_tb} TB (system stats)"
                                    fi
                                elif [[ $(echo "$reads_gb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_reads"): ${reads_gb} GB (系统统计)"
                                    else
                                        echo "│     $(get_label "total_reads"): ${reads_gb} GB (system stats)"
                                    fi
                                else
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_reads"): ${reads_mb} MB (系统统计)"
                                    else
                                        echo "│     $(get_label "total_reads"): ${reads_mb} MB (system stats)"
                                    fi
                                fi
                                data_found=true
                            fi
                            
                            if [[ -n "$write_sectors" && "$write_sectors" != "0" ]] && [[ "$write_sectors" =~ ^[0-9]+$ ]]; then
                                # Convert sectors (512 bytes each) and choose appropriate unit including PB
                                local writes_mb=$(echo "scale=2; $write_sectors * 512 / 1024 / 1024" | bc -l 2>/dev/null)
                                local writes_gb=$(echo "scale=2; $writes_mb / 1024" | bc -l 2>/dev/null)
                                local writes_tb=$(echo "scale=2; $writes_gb / 1024" | bc -l 2>/dev/null)
                                local writes_pb=$(echo "scale=2; $writes_tb / 1024" | bc -l 2>/dev/null)
                                
                                if [[ $(echo "$writes_pb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_writes"): ${writes_pb} PB (系统统计)"
                                    else
                                        echo "│     $(get_label "total_writes"): ${writes_pb} PB (system stats)"
                                    fi
                                elif [[ $(echo "$writes_tb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_writes"): ${writes_tb} TB (系统统计)"
                                    else
                                        echo "│     $(get_label "total_writes"): ${writes_tb} TB (system stats)"
                                    fi
                                elif [[ $(echo "$writes_gb > 1" | bc -l 2>/dev/null) -eq 1 ]]; then
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_writes"): ${writes_gb} GB (系统统计)"
                                    else
                                        echo "│     $(get_label "total_writes"): ${writes_gb} GB (system stats)"
                                    fi
                                else
                                    if [[ "$LANG_MODE" == "cn" ]]; then
                                        echo "│     $(get_label "total_writes"): ${writes_mb} MB (系统统计)"
                                    else
                                        echo "│     $(get_label "total_writes"): ${writes_mb} MB (system stats)"
                                    fi
                                fi
                                data_found=true
                            fi
                        fi
                    fi
                fi
                
                # Method 6: Final fallback - show limited SMART info if available
                if [[ "$data_found" == false ]]; then
                    # Only show useful SMART attributes that might contain data info
                    local smart_data_info=$(echo "$smart_all" | grep -E -i "workload|host.*read|host.*writ|data.*read|data.*writ|lifetime.*read|lifetime.*writ" | grep -v -E "command|error|rate|status" | head -2)
                    if [[ -n "$smart_data_info" ]]; then
                        if [[ "$LANG_MODE" == "cn" ]]; then
                            echo "│     $(get_label "no_info") - 可用SMART属性:"
                        else
                            echo "│     $(get_label "no_info") - Available SMART attributes:"
                        fi
                        echo "$smart_data_info" | while IFS= read -r line; do
                            # Clean up the line for better display
                            local clean_line=$(echo "$line" | sed 's/^[[:space:]]*//' | cut -c1-60)
                            if [[ -n "$clean_line" ]]; then
                                echo "│       $clean_line"
                            fi
                        done
                    else
                        if [[ "$LANG_MODE" == "cn" ]]; then
                            echo "│     $(get_label "no_info") - 此硬盘不支持数据传输统计"
                        else
                            echo "│     $(get_label "no_info") - Disk does not support data transfer statistics"
                        fi
                    fi
                fi
                
                # SSD wear level (for SSDs)
                local wear_level=$(echo "$smart_data" | grep -E "Wear_Leveling_Count|177 Wear_Leveling_Count|Percentage Used" | awk '{print $4}' | head -1)
                if [[ -n "$wear_level" ]]; then
                    echo "│   $(get_label "wear_level"): ${wear_level}%"
                fi
                
                # Temperature detection with multiple methods
                local temp=""
                
                # Method 1: Traditional SMART temperature (SATA drives)
                temp=$(echo "$smart_data" | grep -E "Temperature_Celsius|194 Temperature_Celsius" | awk '{print $10}' | head -1)
                
                # Method 2: NVMe temperature from smartctl -a output
                if [[ -z "$temp" ]]; then
                    temp=$(echo "$smart_all" | grep -E "^Temperature:" | awk '{print $2}' | head -1)
                fi
                
                # Method 3: NVMe temperature sensor
                if [[ -z "$temp" ]]; then
                    temp=$(echo "$smart_all" | grep "Temperature Sensor 1:" | awk '{print $3}' | head -1)
                fi
                
                # Method 4: General temperature search
                if [[ -z "$temp" ]]; then
                    temp=$(echo "$smart_all" | grep -i temperature | grep -o '[0-9]\+ Celsius' | head -1 | grep -o '[0-9]\+')
                fi
                
                if [[ -n "$temp" ]]; then
                    echo "│   $(get_label "temperature"): ${temp}°C"
                else
                    echo "│   $(get_label "temperature"): $(get_label "no_info")"
                fi
                
                # Health percentage (only for NVMe drives using nvme-cli data)
                local health_score=""
                
                if [[ "$disk" =~ nvme ]]; then
                    # NVMe specific health calculation using nvme-cli data
                    local percentage_used=""
                    local available_spare=""
                    local critical_warning=""
                    
                    # Method 1: Try to get Percentage Used from smartctl with multiple patterns
                    # Pattern 1: Standard format "Percentage Used: XX%"
                    percentage_used=$(echo "$smart_all" | grep -i "Percentage Used" | awk '{print $3}' | tr -d '%' | head -1)
                    
                    # Pattern 2: Alternative format with colon
                    if [[ -z "$percentage_used" || ! "$percentage_used" =~ ^[0-9]+$ ]]; then
                        percentage_used=$(echo "$smart_all" | grep -i "Percentage Used" | sed 's/.*://g' | grep -o '[0-9]\+' | head -1)
                    fi
                    
                    # Pattern 3: Look for "XX% used" or similar patterns
                    if [[ -z "$percentage_used" || ! "$percentage_used" =~ ^[0-9]+$ ]]; then
                        percentage_used=$(echo "$smart_all" | grep -i "used" | grep -o '[0-9]\+%' | tr -d '%' | head -1)
                    fi
                    
                    # Pattern 4: Check for specific SMART attribute fields (some drives use different field positions)
                    if [[ -z "$percentage_used" || ! "$percentage_used" =~ ^[0-9]+$ ]]; then
                        percentage_used=$(echo "$smart_all" | grep -i "Percentage Used" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+%?$/) {gsub(/%/,"",$i); print $i; exit}}')
                    fi
                    
                    # Method 2: Try nvme command for more accurate data
                    if [[ -z "$percentage_used" || ! "$percentage_used" =~ ^[0-9]+$ ]] && command -v nvme >/dev/null 2>&1; then
                        local nvme_smart=$(nvme smart-log "/dev/$disk" 2>/dev/null)
                        if [[ -n "$nvme_smart" ]]; then
                            # Pattern 1: "Percentage Used : XX%"
                            percentage_used=$(echo "$nvme_smart" | grep -i "Percentage Used" | awk '{print $4}' | tr -d '%' | head -1)
                            # Pattern 2: Alternative nvme format
                            if [[ -z "$percentage_used" || ! "$percentage_used" =~ ^[0-9]+$ ]]; then
                                percentage_used=$(echo "$nvme_smart" | grep -i "Percentage Used" | sed 's/.*://g' | grep -o '[0-9]\+' | head -1)
                            fi
                        fi
                    fi
                    
                    # Method 3: Debug output for troubleshooting (show relevant lines)
                    if [[ -z "$percentage_used" || ! "$percentage_used" =~ ^[0-9]+$ ]]; then
                        local debug_lines=$(echo "$smart_all" | grep -i -E "percentage|used|worn|wear" | head -3)
                        if [[ -n "$debug_lines" ]]; then
                            echo "│   Debug - Related SMART data:"
                            echo "$debug_lines" | while IFS= read -r line; do
                                echo "│     $line"
                            done
                        fi
                    fi
                    
                    # Get Available Spare percentage with multiple patterns
                    # Pattern 1: Standard format
                    available_spare=$(echo "$smart_all" | grep -i "Available Spare" | grep -v "Threshold" | awk '{print $3}' | tr -d '%' | head -1)
                    
                    # Pattern 2: Alternative format with colon
                    if [[ -z "$available_spare" || ! "$available_spare" =~ ^[0-9]+$ ]]; then
                        available_spare=$(echo "$smart_all" | grep -i "Available Spare" | grep -v "Threshold" | sed 's/.*://g' | grep -o '[0-9]\+' | head -1)
                    fi
                    
                    # Pattern 3: Try different field positions
                    if [[ -z "$available_spare" || ! "$available_spare" =~ ^[0-9]+$ ]]; then
                        available_spare=$(echo "$smart_all" | grep -i "Available Spare" | grep -v "Threshold" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+%?$/) {gsub(/%/,"",$i); print $i; exit}}')
                    fi
                    
                    # Pattern 4: Try nvme command
                    if [[ -z "$available_spare" || ! "$available_spare" =~ ^[0-9]+$ ]] && command -v nvme >/dev/null 2>&1; then
                        local nvme_spare=$(nvme smart-log "/dev/$disk" 2>/dev/null | grep -i "Available Spare" | grep -v "Threshold")
                        if [[ -n "$nvme_spare" ]]; then
                            available_spare=$(echo "$nvme_spare" | awk '{print $4}' | tr -d '%' | head -1)
                            if [[ -z "$available_spare" || ! "$available_spare" =~ ^[0-9]+$ ]]; then
                                available_spare=$(echo "$nvme_spare" | sed 's/.*://g' | grep -o '[0-9]\+' | head -1)
                            fi
                        fi
                    fi
                    
                    # Get Critical Warning status with multiple patterns
                    # Pattern 1: Standard format
                    critical_warning=$(echo "$smart_all" | grep -i "Critical Warning" | awk '{print $3}' | head -1)
                    
                    # Pattern 2: Alternative format with colon
                    if [[ -z "$critical_warning" ]]; then
                        critical_warning=$(echo "$smart_all" | grep -i "Critical Warning" | sed 's/.*://g' | sed 's/^[[:space:]]*//' | awk '{print $1}' | head -1)
                    fi
                    
                    # Pattern 3: Try nvme command
                    if [[ -z "$critical_warning" ]] && command -v nvme >/dev/null 2>&1; then
                        local nvme_warning=$(nvme smart-log "/dev/$disk" 2>/dev/null | grep -i "Critical Warning")
                        if [[ -n "$nvme_warning" ]]; then
                            critical_warning=$(echo "$nvme_warning" | awk '{print $4}' | head -1)
                            if [[ -z "$critical_warning" ]]; then
                                critical_warning=$(echo "$nvme_warning" | sed 's/.*://g' | sed 's/^[[:space:]]*//' | awk '{print $1}' | head -1)
                            fi
                        fi
                    fi
                    
                    # Calculate health score for NVMe only if we have reliable nvme-cli data
                    if [[ -n "$percentage_used" && "$percentage_used" =~ ^[0-9]+$ ]]; then
                        # Health = 100 - Percentage Used
                        health_score=$((100 - percentage_used))
                        
                        # Adjust based on Available Spare if available
                        if [[ -n "$available_spare" && "$available_spare" =~ ^[0-9]+$ ]]; then
                            if [[ "$available_spare" -lt 10 ]]; then
                                health_score=$((health_score - 10))  # Penalty for low spare blocks
                            fi
                        fi
                        
                        # Adjust based on Critical Warning
                        if [[ -n "$critical_warning" && "$critical_warning" != "0x00" && "$critical_warning" != "0" ]]; then
                            health_score=$((health_score - 20))  # Penalty for critical warnings
                        fi
                        
                        # Ensure health score is within valid range
                        if [[ "$health_score" -lt 0 ]]; then health_score=0; fi
                        if [[ "$health_score" -gt 100 ]]; then health_score=100; fi
                    else
                        # Fallback: estimate based on available spare only
                        if [[ -n "$available_spare" && "$available_spare" =~ ^[0-9]+$ ]]; then
                            health_score="$available_spare"
                        else
                            health_score=""  # No health data available
                        fi
                    fi
                    
                    # Display additional NVMe health details
                    if [[ -n "$percentage_used" && "$percentage_used" =~ ^[0-9]+$ ]]; then
                        echo "│   $(get_label "percentage_used"): ${percentage_used}%"
                    fi
                    if [[ -n "$available_spare" && "$available_spare" =~ ^[0-9]+$ ]]; then
                        echo "│   $(get_label "available_spare"): ${available_spare}%"
                    fi
                    if [[ -n "$critical_warning" ]]; then
                        echo "│   $(get_label "critical_warning"): ${critical_warning}"
                    fi
                    
                    # Only display health status for NVMe drives with valid data
                    if [[ -n "$health_score" && "$health_score" != "" ]]; then
                        echo "│   $(get_label "health_status"): ${health_score}%"
                    fi
                else
                    # Skip health calculation for HDD/SATA drives as smartctl calculation is unreliable
                    # Only show basic SMART status if available
                    : # No health status display for HDD/SATA drives
                fi
            else
                echo "│   SMART not supported on this device"
            fi
        else
            # Show detailed error message with installation instructions
            if [[ "$LANG_MODE" == "cn" ]]; then
                echo "│   SMART状态: smartctl工具未安装"
                echo "│   请安装smartmontools软件包来获取SMART信息:"
                local pkg_manager=$(get_package_manager)
                case "$pkg_manager" in
                    "apt")
                        echo "│     sudo apt-get install smartmontools"
                        ;;
                    "dnf"|"yum")
                        echo "│     sudo $pkg_manager install smartmontools"
                        ;;
                    "pacman")
                        echo "│     sudo pacman -S smartmontools"
                        ;;
                    "zypper")
                        echo "│     sudo zypper install smartmontools"
                        ;;
                    "apk")
                        echo "│     sudo apk add smartmontools"
                        ;;
                    *)
                        echo "│     请使用系统包管理器安装smartmontools"
                        ;;
                esac
            else
                echo "│   SMART Status: smartctl tool not installed"
                echo "│   Please install smartmontools package to get SMART information:"
                local pkg_manager=$(get_package_manager)
                case "$pkg_manager" in
                    "apt")
                        echo "│     sudo apt-get install smartmontools"
                        ;;
                    "dnf"|"yum")
                        echo "│     sudo $pkg_manager install smartmontools"
                        ;;
                    "pacman")
                        echo "│     sudo pacman -S smartmontools"
                        ;;
                    "zypper")
                        echo "│     sudo zypper install smartmontools"
                        ;;
                    "apk")
                        echo "│     sudo apk add smartmontools"
                        ;;
                    *)
                        echo "│     Please use your system's package manager to install smartmontools"
                        ;;
                esac
            fi
        fi
        
        # I/O statistics
        if command -v iostat >/dev/null 2>&1; then
            local io_stats=$(iostat -d "$disk" 1 2 2>/dev/null | tail -1)
            if [[ -n "$io_stats" ]]; then
                local read_kb=$(echo "$io_stats" | awk '{print $3}')
                local write_kb=$(echo "$io_stats" | awk '{print $4}')
                echo "│   Current $(get_label "read_io"): ${read_kb} KB/s"
                echo "│   Current $(get_label "write_io"): ${write_kb} KB/s"
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
