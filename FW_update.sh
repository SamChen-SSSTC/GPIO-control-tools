#!/bin/bash

# Repeated NVMe Firmware Download and Version Check Script
# This script continuously downloads firmware, checks version, and alternates between two firmware files

#==============================================================================
# Load configuration from file if provided
#==============================================================================
CONFIG_FILE=""
if [ "$1" = "-c" ] || [ "$1" = "--config" ]; then
    CONFIG_FILE="$2"
    shift 2
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    echo "[Config] Loading parameters from: $CONFIG_FILE"
    # Source the config file (skip comments and empty lines)
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        # Remove quotes from value if present
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        # Export the variable
        export "$key=$value"
        echo "[Config]   $key=$value"
    done < "$CONFIG_FILE"
    echo ""
fi

# Check if device is provided as command line argument
if [ -z "$CONFIG_FILE" ] && [ $# -lt 1 ]; then
    echo "Usage: $0 [-c|--config <config_file>] <nvme_device> [fw_file_1] [fw_file_2] [fw_file_3] [sleep_time] [xfer_size] [plp_mode] [plp_prob] [rpi_host] [rpi_user] [rpi_gpio]"
    echo ""
    echo "Config file mode:"
    echo "  $0 -c repeated_download.conf"
    echo "  $0 --config my_config.conf"
    echo ""
    echo "Command line mode:"
    echo "  $0 /dev/nvme0n1 FQZRDX1.bin FQZRDD2.bin FQZRDP3.bin 3 0x20000 software 30"
    echo "  $0 /dev/nvme0n1 FQZRDX1.bin FQZRDD2.bin FQZRDP3.bin 3 0x20000 rpi4 30 10.6.205.0 pi 23"
    echo ""
    echo "PLP Modes:"
    echo "  no       - Disable PLP simulation"
    echo "  software - Software-based PLP (nvme reset)"
    echo "  rpi4     - Hardware PLP via RPi4 GPIO (requires SSH access)"
    exit 1
fi

# Configuration

# Detect script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use config file variables if loaded, otherwise use positional/defaults
if [ -n "$CONFIG_FILE" ]; then
    NVME_DEVICE="${NVME_DEVICE:-/dev/nvme0n1}"
    FW_FILE_1="${FW_FILE_1:-FQZRDX1.bin}"
    FW_FILE_2="${FW_FILE_2:-FQZRDD2.bin}"
    FW_FILE_3="${FW_FILE_3:-FQZRDP3.bin}"
    SLEEP_TIME="${SLEEP_TIME:-3}"
    XFER_SIZE="${XFER_SIZE:-0x20000}"
    PLP_SIMULATION="${PLP_SIMULATION:-rpi4}"
    PLP_PROBABILITY="${PLP_PROBABILITY:-60}"
    RPI_HOST="${RPI_HOST:-10.6.205.0}"
    RPI_USER="${RPI_USER:-pi}"
    RPI_GPIO_PIN="${RPI_GPIO_PIN:-17}"
    RPI_SSH_KEY="${RPI_SSH_KEY:-}"
    RPI_SSH_PASS="${RPI_SSH_PASS:-}"
    RPI_POWER_OFF_MS="${RPI_POWER_OFF_MS:-2000}"
else
    NVME_DEVICE="${1:-/dev/nvme0n1}"
    FW_FILE_1="${2:-FQZRDX1.bin}"
    FW_FILE_2="${3:-FQZRDD2.bin}"
    FW_FILE_3="${4:-FQZRDP3.bin}"
    SLEEP_TIME="${5:-3}"
    XFER_SIZE="${6:-0x20000}"
    PLP_SIMULATION="${7:-rpi4}"
    PLP_PROBABILITY="${8:-60}"
    RPI_HOST="${9:-10.6.205.0}"
    RPI_USER="${10:-pi}"
    RPI_GPIO_PIN="${11:-17}"
    RPI_SSH_KEY="${RPI_SSH_KEY:-}"
    RPI_SSH_PASS="${RPI_SSH_PASS:-}"
    RPI_POWER_OFF_MS="${RPI_POWER_OFF_MS:-2000}"
fi

# PCIe timing defaults (can override via environment)
PCIE_REMOVE_DELAY="${PCIE_REMOVE_DELAY:-0.25}"
PCIE_RESCAN_DELAY="${PCIE_RESCAN_DELAY:-1.0}"

# Export variables for GPIO control scripts to inherit
export RPI_HOST RPI_USER RPI_GPIO_PIN RPI_SSH_KEY RPI_SSH_PASS RPI_POWER_OFF_MS

# GPIO control script paths (use absolute paths based on script directory)
RPI_ON_SCRIPT="$SCRIPT_DIR/gpio_on.sh"
RPI_OFF_SCRIPT="$SCRIPT_DIR/gpio_off.sh"
RPI_CYCLE_SCRIPT="$SCRIPT_DIR/gpio_cycle.sh"

# Resolve firmware file paths (absolute or relative to script directory)
resolve_fw_path() {
    local fw_file="$1"
    # If absolute path, use as-is
    if [[ "$fw_file" = /* ]]; then
        echo "$fw_file"
        return
    fi
    # Check in current directory
    if [ -f "$fw_file" ]; then
        echo "$(pwd)/$fw_file"
        return
    fi
    # Check in script directory
    if [ -f "$SCRIPT_DIR/$fw_file" ]; then
        echo "$SCRIPT_DIR/$fw_file"
        return
    fi
    # Check in parent FW_Bin directories
    if [ -f "$SCRIPT_DIR/../FW_Bin/*/$fw_file" ]; then
        echo "$(ls $SCRIPT_DIR/../FW_Bin/*/$fw_file 2>/dev/null | head -1)"
        return
    fi
    # Return original if not found (will fail validation later)
    echo "$fw_file"
}

FW_FILE_1=$(resolve_fw_path "${FW_FILE_1}")
FW_FILE_2=$(resolve_fw_path "${FW_FILE_2}")
FW_FILE_3=$(resolve_fw_path "${FW_FILE_3}")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

timestamp_short() {
    date +%Y-%m-%dT%H:%M:%S
}

LAST_STEP_TAG=""

ensure_step_spacing() {
    local msg="$1"
    local current_tag=""
    if [[ "$msg" =~ ^(\[Step[^]]*\]) ]]; then
        current_tag="${BASH_REMATCH[1]}"
    fi

    if [ -n "$current_tag" ] && [ "$current_tag" != "$LAST_STEP_TAG" ]; then
        echo ""
        LAST_STEP_TAG="$current_tag"
    fi
}

print_info() {
    ensure_step_spacing "$1"
    echo -e "$(timestamp_short) ${GREEN}[INFO]${NC} $1"
}

print_error() {
    ensure_step_spacing "$1"
    echo -e "$(timestamp_short) ${RED}[ERROR]${NC} $1"
}

print_warning() {
    ensure_step_spacing "$1"
    echo -e "$(timestamp_short) ${YELLOW}[WARN]${NC} $1"
}

print_banner() {
    local msg="$1"
    local line="======================================================================="
    echo "$line"
    print_info "$msg"
    echo "$line"
}

# Logging setup: save console output to a rotating log file
LOG_DIR="${LOG_DIR:-./logs}"
LOG_BASENAME="Log_$(basename "$NVME_DEVICE")"
LOG_FILE="${LOG_FILE:-$LOG_DIR/${LOG_BASENAME}_$(date +%Y%m%d_%H%M%S).log}"
mkdir -p "$LOG_DIR" 2>/dev/null
# Redirect all stdout/stderr to both console and log
exec > >(tee -a "$LOG_FILE") 2>&1
print_info "Logging to: $LOG_FILE"

# Expected firmware versions (extract from filename, e.g., FQZRDX1.bin -> FQZRDX1)
EXPECTED_FW_VER_1=$(basename ${FW_FILE_1} .bin)
EXPECTED_FW_VER_2=$(basename ${FW_FILE_2} .bin)
EXPECTED_FW_VER_3=$(basename ${FW_FILE_3} .bin)

# Check if fio is installed, install if not
if ! command -v fio &> /dev/null; then
    print_warning "fio is not installed. Installing fio..."
    sudo apt-get update && sudo apt-get install -y fio
    if [ $? -eq 0 ]; then
        print_info "fio installed successfully"
    else
        print_error "Failed to install fio. Please install it manually: sudo apt-get install fio"
        exit 1
    fi
else
    print_info "fio is already installed"
fi

# Check if sshpass is installed, install if not
if ! command -v sshpass &> /dev/null; then
    print_warning "sshpass is not installed. Installing sshpass..."
    sudo apt-get update && sudo apt-get install -y sshpass
    if [ $? -eq 0 ]; then
        print_info "sshpass installed successfully"
    else
        print_error "Failed to install sshpass. Please install it manually: sudo apt-get install sshpass"
        exit 1
    fi
else
    print_info "sshpass is already installed"
fi

# Function to get current firmware version
get_fw_version() {
    sudo nvme id-ctrl ${NVME_DEVICE} | grep "fr " | awk '{print $3}'
}

verify_firmware_version() {
    local step_label="$1"
    local expected_version="$2"

    print_warning "${step_label} Verify firmware version"

    local new_version=$(get_fw_version)
    if [ -z "$new_version" ]; then
        print_error "${step_label} ✗ Unable to read firmware version"
        return 1
    fi
    
    local new_version_last2="${new_version: -2}"
    local expected_version_last2="${expected_version: -2}"
    local new_version_prefix="${new_version%??}"
    local expected_version_prefix="${expected_version%??}"

    echo -e "${GREEN}${step_label}${NC} Firmware version: ${new_version_prefix}${CYAN}${new_version_last2}${NC}"
    echo -e "${GREEN}${step_label}${NC} Expected version: ${expected_version_prefix}${MAGENTA}${expected_version_last2}${NC}"
    echo -e "${GREEN}${step_label}${NC} Comparing last 2 digits: ${CYAN}${new_version_last2}${NC} vs ${MAGENTA}${expected_version_last2}${NC}"

    if [[ "${new_version_last2}" == "${expected_version_last2}" ]]; then
        print_info "${step_label} ✓ Firmware version matches expected value"
        return 0
    else
        print_error "${step_label} ✗ Firmware version mismatch!"
        echo -e "${RED}${step_label}${NC} Expected (last 2 digits): ${MAGENTA}${expected_version_last2}${NC}"
        echo -e "${RED}${step_label}${NC} Got (last 2 digits): ${CYAN}${new_version_last2}${NC}"
        return 1
    fi
}

# Function to download firmware
download_firmware() {
    local fw_file=$1
    local fw_slot=$2
    local fw_basename=$(basename "${fw_file}")
    
    print_warning "[Step 1] Download Firmware: ${fw_basename} to slot ${fw_slot}"
    
    if [ ! -f "${fw_file}" ]; then
        print_error "[Step 1] ✗ Firmware file not found: ${fw_file}"
        print_error "[Step 1]   Searched in: $(pwd), $SCRIPT_DIR, $SCRIPT_DIR/../FW_Bin/*/"
        return 1
    fi
    
    # Verify file size is reasonable (> 1MB, < 100MB)
    local fw_size=$(stat -c%s "${fw_file}" 2>/dev/null || stat -f%z "${fw_file}" 2>/dev/null)
    if [ -n "$fw_size" ]; then
        if [ $fw_size -lt 1048576 ]; then
            print_error "[Step 1] ✗ Firmware file too small (${fw_size} bytes): ${fw_file}"
            return 1
        fi
        print_info "[Step 1] File size: $((fw_size / 1048576)) MB"
    fi
    
    # Check device exists before download
    if [ ! -e "${NVME_DEVICE}" ]; then
        print_error "[Step 1] ✗ NVMe device not found: ${NVME_DEVICE}"
        return 1
    fi
    
    sudo nvme fw-download ${NVME_DEVICE} --fw="${fw_file}" --xfer=${XFER_SIZE}
    local result=$?
    
    if [ $result -eq 0 ]; then
        print_info "[Step 1] ✓ Firmware download successful"
        return 0
    else
        print_error "[Step 1] ✗ Firmware download failed (exit code: $result)"
        return 1
    fi
}

# Function to commit firmware with action=3 (replace and activate immediately)
commit_firmware() {
    local fw_slot=$1
    
    print_warning "[Step 3] Commit Firmware: slot ${fw_slot} with action=3 (activate immediately)"
    
    # Check device exists before commit
    if [ ! -e "${NVME_DEVICE}" ]; then
        print_error "[Step 3] ✗ NVMe device not found: ${NVME_DEVICE}"
        return 1
    fi
    
    sudo nvme fw-commit ${NVME_DEVICE} --slot=${fw_slot} --action=3
    local result=$?
    
    if [ $result -eq 0 ]; then
        print_info "[Step 3] ✓ Firmware commit successful"
        return 0
    else
        print_error "[Step 3] ✗ Firmware commit failed (exit code: $result)"
        return 1
    fi
}

# Function to verify RPi4 connection stability
verify_rpi_connection() {
    local max_retries=3
    local retry=0
    
    # Check script exists and is executable
    if [ ! -x "$RPI_ON_SCRIPT" ]; then
        print_error "[Step 0] RPi GPIO ON script not found or not executable: $RPI_ON_SCRIPT"
        return 1
    fi
    
    while [ $retry -lt $max_retries ]; do
        # Capture output for debugging
        local test_output=$("$RPI_ON_SCRIPT" 2>&1)
        local test_result=$?
        
        if [ $test_result -eq 0 ]; then
            print_info "[Step 0] ✓ RPi4 connection verified (attempt $((retry + 1))/$max_retries)"
            return 0
        fi
        
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            print_warning "[Step 0] RPi4 connection test failed (exit code: $test_result), retrying ($retry/$max_retries)..."
            # Show first line of error for debugging
            print_warning "[Step 0]   Detail: $(echo "$test_output" | head -1)"
            sleep 2
        fi
    done
    
    print_error "[Step 0] ✗ RPi4 connection unstable after $max_retries attempts"
    print_error "[Step 0] Last error: $(echo "$test_output" | tail -1)"
    return 1
}

preflight_gpio_cycle() {
    print_warning "[Pre-flight] Running gpio_cycle.sh to verify GPIO control and ensure POWER ON state"

    if [ ! -x "$RPI_CYCLE_SCRIPT" ]; then
        print_error "[Pre-flight] GPIO cycle script not found or not executable: $RPI_CYCLE_SCRIPT"
        return 1
    fi

    # Run gpio_cycle.sh which does: PCIE remove -> Power OFF (HIGH) -> Power ON (LOW) -> PCIE rescan
    print_info "[Pre-flight] Running: $RPI_CYCLE_SCRIPT"
    if "$RPI_CYCLE_SCRIPT" >/dev/null 2>&1; then
        print_info "[Pre-flight] ✓ GPIO cycle completed successfully"
        print_info "[Pre-flight] ✓ Initial state: POWER ON (GPIO LOW)"
    else
        print_error "[Pre-flight] ✗ GPIO cycle failed"
        print_error "[Pre-flight]   Run manually for details: $RPI_CYCLE_SCRIPT -c $CONFIG_FILE"
        return 1
    fi

    # Device should already be detected by gpio_cycle.sh, but verify
    if [ ! -e "${NVME_DEVICE}" ]; then
        print_warning "[Pre-flight] Device not immediately visible, waiting..."
        if ! wait_for_nvme_device "[Pre-flight]"; then
            print_error "[Pre-flight] NVMe device did not return after GPIO cycle"
            return 1
        fi
    fi
    print_info "[Pre-flight] ✓ NVMe device is accessible"

    return 0
}

# ==== Step 4: GPIO Power OFF =============================================
rpi4_gpio_off() {
    print_info "[Step 5] Triggering GPIO Power OFF via $RPI_OFF_SCRIPT"
    
    if [ ! -x "$RPI_OFF_SCRIPT" ]; then
        print_error "[Step 5] OFF script not found or not executable: $RPI_OFF_SCRIPT"
        return 1
    fi
    
    if "$RPI_OFF_SCRIPT"; then
        print_info "[Step 5] ✓ GPIO Power OFF executed successfully"
        return 0
    else
        print_error "[Step 5] ✗ RPi4 GPIO OFF command failed"
        print_warning "[Step 5]   Re-run ${RPI_OFF_SCRIPT} manually for details"
        return 1
    fi
}

# ==== Step 5: PCIe Remove =============================================
normalize_pcie_address() {
    local addr="$1"
    if [[ -z "$addr" ]]; then
        echo ""
        return
    fi
    if [[ "$addr" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]]; then
        echo "$addr"
    elif [[ "$addr" =~ ^[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]]; then
        echo "0000:$addr"
    else
        echo ""
    fi
}

run_sysfs_write() {
    local label="$1"
    local path="$2"
    local value="${3:-1}"
    local cmd="echo ${value} | sudo tee ${path}"

    print_info "${label} Running: ${cmd}"
    if echo "${value}" | sudo tee "${path}" > /dev/null 2>&1; then
        return 0
    fi

    print_error "${label} ✗ Failed to write '${value}' to ${path}"
    return 1
}

NVME_SERIAL=""

get_pcie_address() {
    local nvme_name=$(basename ${NVME_DEVICE})
    local candidate=""

    # Primary: resolve via class symlink for the NVMe device
    if [ -e "/sys/class/nvme/${nvme_name}/device" ]; then
        local link_target=$(readlink -f /sys/class/nvme/${nvme_name}/device 2>/dev/null)
        local base_name=$(basename "$link_target")
        candidate=$(normalize_pcie_address "$base_name")
    fi

    # Secondary: resolve via block device path
    if [ -z "$candidate" ] && [ -e "/sys/block/${nvme_name}" ]; then
        local sysfs_path=$(readlink -f /sys/block/${nvme_name} 2>/dev/null)
        local addr=$(echo "$sysfs_path" | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]' | head -1)
        candidate=$(normalize_pcie_address "$addr")
    fi

    # Tertiary: parse lspci (Non-Volatile memory controller) output
    if [ -z "$candidate" ] && command -v lspci >/dev/null 2>&1; then
        local lspci_addr=$(lspci | grep -i "Non-Volatile memory" | awk '{print $1}' | head -1)
        candidate=$(normalize_pcie_address "$lspci_addr")
    fi

    echo "$candidate"
}

refresh_nvme_device_path() {
    if [ -z "$NVME_SERIAL" ]; then
        return 1
    fi

    local node=$(sudo nvme list 2>/dev/null | awk -v sn="$NVME_SERIAL" 'NR>2 && $2==sn {print $1; exit}')
    if [ -z "$node" ]; then
        return 1
    fi

    if [ "$node" != "$NVME_DEVICE" ]; then
        print_info "[Detect] NVMe node changed: ${NVME_DEVICE} -> ${node}"
        NVME_DEVICE="$node"
    fi

    if [ -e "$NVME_DEVICE" ]; then
        return 0
    fi

    return 1
}

pcie_remove() {
    print_warning "[Step 5] PCIe Hot-unplug: Removing device"

    local pcie_addr=$(get_pcie_address)

    if [ -z "$pcie_addr" ]; then
        print_warning "[Step 5] Could not determine PCIe address, attempting subsystem reset"
        if run_sysfs_write "[Step 5]" "/sys/class/nvme/${NVME_DEVICE##*/}/device/reset"; then
            print_info "[Step 5] ✓ NVMe subsystem reset triggered"
        else
            print_error "[Step 5] ✗ NVMe subsystem reset failed"
            return 1
        fi
    else
        print_info "[Step 5] PCIe address: $pcie_addr"
        if ! run_sysfs_write "[Step 5]" "/sys/bus/pci/devices/${pcie_addr}/remove"; then
            return 1
        fi
        print_info "[Step 5] ✓ PCIe device removed"
    fi

    sleep "$PCIE_REMOVE_DELAY"
    return 0
}

pcie_rescan() {
    print_warning "[Step 5] PCIe Hot-plug: Rescanning bus"
    if run_sysfs_write "[Step 5]" "/sys/bus/pci/rescan"; then
        print_info "[Step 5] ✓ PCIe bus rescan triggered"
    else
        return 1
    fi
    sleep "$PCIE_RESCAN_DELAY"
    return 0
}

pcie_remove_rescan_cycle() {
    local label="${1:-[PCIe]}"
    local wait_for_device="${2:-true}"
    local removed=0

    print_warning "${label} PCIe remove/rescan cycle (wait=${wait_for_device})"

    if [ -e "${NVME_DEVICE}" ]; then
        if ! pcie_remove; then
            print_error "${label} ✗ PCIe remove failed"
            return 1
        fi
        removed=1
    else
        print_warning "${label} NVMe node ${NVME_DEVICE} not present; skipping remove"
    fi

    if ! pcie_rescan; then
        print_error "${label} ✗ PCIe rescan failed"
        return 1
    fi

    if [[ "$wait_for_device" == "true" ]]; then
        if ! wait_for_nvme_device "${label}"; then
            print_error "${label} ✗ NVMe device not detected after rescan"
            return 1
        fi
    fi

    print_info "${label} ✓ PCIe cycle completed (remove=${removed})"
    return 0
}

wait_for_nvme_device() {
    local label="$1"
    print_warning "${label} Waiting for NVMe device ${NVME_DEVICE}..."
    local timeout=60
    local count=0
    while [ ! -e "${NVME_DEVICE}" ] && [ $count -lt $timeout ]; do
        refresh_nvme_device_path
        sleep 1
        count=$((count + 1))
        if [ $((count % 5)) -eq 0 ]; then
            print_warning "${label} Still waiting... ${count}s elapsed"
        fi
    done

    if [ -e "${NVME_DEVICE}" ]; then
        print_info "${label} ✓ Device detected after ${count}s"
        sleep 3
        return 0
    fi

    print_error "${label} ✗ Device NOT detected within ${timeout}s"
    return 1
}

pre_iteration_pcie_recovery() {
    print_warning "[Pre-flight] Restoring PCIe link before iterations"

    if ! pcie_remove_rescan_cycle "[Pre-flight]" true; then
        return 1
    fi

    print_info "[Pre-flight] PCIe link restored"
    return 0
}

# ==== GPIO Power ON ==================================================
rpi4_gpio_on() {
    print_info "[Step 5] Triggering GPIO Power ON via $RPI_ON_SCRIPT"
    
    if [ ! -x "$RPI_ON_SCRIPT" ]; then
        print_error "[Step 5] ON script not found or not executable: $RPI_ON_SCRIPT"
        return 1
    fi
    
    if "$RPI_ON_SCRIPT"; then
        print_info "[Step 5] ✓ GPIO Power ON executed successfully"
    else
        print_error "[Step 5] ✗ RPi4 GPIO ON command failed"
        print_warning "[Step 5]   Re-run ${RPI_ON_SCRIPT} manually for details"
        return 1
    fi

    sleep 0.5  # brief settle time before PCIe operations resume
    return 0
}

perform_hot_swap() {
    case "${PLP_SIMULATION}" in
        "rpi4")
            print_warning "[Step 5] PLP trigger via gpio_cycle.sh (PCIE remove -> power OFF -> power ON -> PCIE rescan)"
            
            if [ ! -x "$RPI_CYCLE_SCRIPT" ]; then
                print_error "[Step 5] GPIO cycle script not found or not executable: $RPI_CYCLE_SCRIPT"
                return 1
            fi
            
            # Run gpio_cycle.sh which handles the complete sequence
            if "$RPI_CYCLE_SCRIPT"; then
                print_info "[Step 5] ✓ PLP trigger completed (gpio_cycle.sh)"
            else
                print_error "[Step 5] ✗ PLP trigger failed"
                return 1
            fi
            ;;
        "software")
            print_warning "[Step 5] Software hot swap (PCIe remove/rescan)"
            if ! pcie_remove_rescan_cycle "[Step 5]" true; then
                print_error "[Step 5] Software hot swap failed"
                return 1
            fi
            print_info "[Step 5] ✓ Software hot swap completed"
            ;;
        "no")
            print_warning "[Step 5] Hot swap skipped (PLP simulation disabled)"
            ;;
        *)
            print_error "[Step 5] Unknown PLP simulation mode: ${PLP_SIMULATION}"
            return 1
            ;;
    esac

    return 0
}


# Function to identify device
identify_device() {
    print_info "Identifying NVMe device (firmware info only)..."
    sudo nvme id-ctrl ${NVME_DEVICE} | grep -E "fr |frs"
}

# Main loop
iteration=0
current_fw=1  # Start with firmware 1
current_slot=1  # Start with slot 1

print_info "Starting NVMe firmware download loop..."
print_info "Device: ${NVME_DEVICE}"
print_info "Firmware 1: ${FW_FILE_1}"
print_info "Firmware 2: ${FW_FILE_2}"
print_info "Firmware 3: ${FW_FILE_3}"
print_info "Sleep time: ${SLEEP_TIME}s"
print_info "Transfer size: ${XFER_SIZE}"

# ===================================================================
# Pre-flight Validation
# ===================================================================
print_warning "Pre-flight validation..."

# Check NVMe device exists
if [ ! -e "${NVME_DEVICE}" ]; then
    print_error "✗ NVMe device not found: ${NVME_DEVICE}"
    exit 1
fi
print_info "✓ NVMe device exists: ${NVME_DEVICE}"

# Check firmware files exist
for fw in "${FW_FILE_1}" "${FW_FILE_2}" "${FW_FILE_3}"; do
    if [ ! -f "$fw" ]; then
        print_error "✗ Firmware file not found: $fw"
        print_error "  Searched in: $(pwd), $SCRIPT_DIR, $SCRIPT_DIR/../FW_Bin/*/"
        exit 1
    fi
    print_info "✓ Firmware file exists: $(basename "$fw") ($(stat -c%s "$fw" 2>/dev/null || stat -f%z "$fw" 2>/dev/null | awk '{printf "%.1f MB", $1/1048576}'))"
done

# Check nvme-cli is installed
if ! command -v nvme &> /dev/null; then
    print_error "✗ nvme-cli is not installed. Install with: sudo apt-get install nvme-cli"
    exit 1
fi
print_info "✓ nvme-cli is installed: $(nvme version | head -1)"

# Test NVMe device responds
if ! sudo nvme id-ctrl ${NVME_DEVICE} >/dev/null 2>&1; then
    print_error "✗ NVMe device not responding to commands: ${NVME_DEVICE}"
    exit 1
fi
print_info "✓ NVMe device responding to commands"

NVME_SERIAL=$(sudo nvme id-ctrl ${NVME_DEVICE} 2>/dev/null | awk 'tolower($1)=="sn" {print $2}' | xargs)
if [ -n "$NVME_SERIAL" ]; then
    print_info "Tracking NVMe serial: ${NVME_SERIAL}"
else
    print_warning "Unable to read NVMe serial; NVMe path auto-detection disabled"
fi

echo ""

# ==== Display PLP mode configuration =============================================
case "${PLP_SIMULATION}" in
    "no")
        print_info "PLP Simulation: DISABLED"
        ;;
    "software")
        print_warning "PLP Simulation: SOFTWARE MODE (PCIe remove/rescan every iteration)"
        print_info "  - Using NVMe subsystem reset and PCI hot-unplug"
        ;;
    "rpi4")
        print_warning "PLP Simulation: HARDWARE MODE via RPi4 (GPIO OFF/ON every iteration)"
        print_info "  - RPi4 Host: ${RPI_USER}@${RPI_HOST}"
        print_info "  - GPIO Control: Local scripts (gpio_on.sh / gpio_off.sh)"
        print_info "  - Power off duration: ${RPI_POWER_OFF_MS}ms"
        
        # Verify GPIO control scripts exist
        if [ ! -x "$RPI_ON_SCRIPT" ]; then
            print_error "ON script not found or not executable: $RPI_ON_SCRIPT"
            exit 1
        fi
        if [ ! -x "$RPI_OFF_SCRIPT" ]; then
            print_error "OFF script not found or not executable: $RPI_OFF_SCRIPT"
            exit 1
        fi
        if [ ! -x "$RPI_CYCLE_SCRIPT" ]; then
            print_error "CYCLE script not found or not executable: $RPI_CYCLE_SCRIPT"
            exit 1
        fi
        
        # Test RPi4 connectivity and ensure POWER ON state
        print_info "Testing RPi4 GPIO control via gpio_cycle.sh..."
        if preflight_gpio_cycle; then
            print_info "✓ RPi4 GPIO control verified, device in POWER ON state (GPIO LOW)"
        else
            print_error "✗ RPi4 GPIO control test failed"
            print_error "Please verify network, credentials, and GPIO setup, then rerun the script."
            exit 1
        fi
        ;;
    *)
        print_error "Invalid PLP_SIMULATION mode: ${PLP_SIMULATION}"
        print_error "Valid modes: no, software, rpi4"
        exit 1
        ;;
esac
echo ""

while true; do
    iteration=$((iteration + 1))
    print_banner "Iteration ${iteration}"
    
    # Get current firmware version
    current_version=$(get_fw_version)
    print_info "Current firmware version: ${current_version}"
    print_info "Using FW slot: ${current_slot}"
    
    # Determine which firmware to download (rotate through 3 firmwares)
    if [ ${current_fw} -eq 1 ]; then
        fw_to_download=${FW_FILE_1}
        expected_version=${EXPECTED_FW_VER_1}
        next_fw=2
    elif [ ${current_fw} -eq 2 ]; then
        fw_to_download=${FW_FILE_2}
        expected_version=${EXPECTED_FW_VER_2}
        next_fw=3
    else
        fw_to_download=${FW_FILE_3}
        expected_version=${EXPECTED_FW_VER_3}
        next_fw=1
    fi
    
    # ===================================================================
    # [Step 1] Download Firmware
    # ===================================================================
    download_firmware ${fw_to_download} ${current_slot}
    if [ $? -ne 0 ]; then
        print_error "[Step 1] Download failed! Stopping script..."
        exit 1
    fi

    # ===================================================================
    # [Step 2] FIO Workload
    # ===================================================================
    print_warning "[Step 2] FIO workload: Random R/W for 3 minutes"
    
    # Check device exists before FIO
    if [ ! -e "${NVME_DEVICE}" ]; then
        print_error "[Step 2] ✗ Device disappeared before FIO: ${NVME_DEVICE}"
        exit 1
    fi
    
    sudo fio --name=random_rw \
        --filename=${NVME_DEVICE} \
        --direct=1 \
        --rw=randrw \
        --rwmixread=50 \
        --bs=4k \
        --ioengine=libaio \
        --iodepth=32 \
        --numjobs=4 \
        --time_based \
        --runtime=180 \
        --group_reporting
    
    fio_result=$?
    
    if [ $fio_result -eq 0 ]; then
        print_info "[Step 2] ✓ FIO workload completed successfully"
    else
        print_warning "[Step 2] ⚠ FIO operation completed with warnings (exit code: $fio_result)"
    fi
    
    print_info "[Step 2] FIO workload finished"
    sleep 1
    
    # ===================================================================
    # [Step 3] Commit Firmware
    # ===================================================================
    commit_firmware ${current_slot}
    if [ $? -ne 0 ]; then
        print_error "[Step 3] Firmware commit failed! Stopping script..."
        exit 1
    fi
    
    # ===================================================================
    # [Step 4] Verify firmware before hot swap
    # ===================================================================
    print_info "Sleeping for ${SLEEP_TIME} seconds to allow firmware activation..."
    sleep ${SLEEP_TIME}
    identify_device
    if ! verify_firmware_version "[Step 4]" "${expected_version}"; then
        print_error "[Step 4] Firmware verification failed! Stopping script..."
        exit 1
    fi

    # ===================================================================
    # [Step 5] Hot swap (GPIO OFF -> ON)
    # ===================================================================
    if ! perform_hot_swap; then
        print_error "[Step 5] Hot swap sequence failed! Stopping script..."
        exit 1
    fi

    # ===================================================================
    # [Step 6] Verify firmware after hot swap
    # ===================================================================
    if ! verify_firmware_version "[Step 6]" "${expected_version}"; then
        print_error "[Step 6] Firmware verification failed after hot swap! Stopping script..."
        exit 1
    fi
    
    # Toggle firmware and slot for next iteration
    current_fw=${next_fw}
    
    # Alternate between slot 1 and slot 2
    if [ ${current_slot} -eq 1 ]; then
        current_slot=2
    else
        current_slot=1
    fi
    
    echo ""
    print_info "Press Ctrl+C to stop the loop"
    echo ""
    
    # Optional: Add a delay before next iteration
    sleep 1
done
