#!/bin/bash

#==============================================================================
# RPi GPIO Power Cycle Script (Host-Side)
# Complete power cycle: OFF → Wait → ON → Wait for device
#
# Usage:
#   ./rpi_gpio_cycle.sh -c plp.conf [off_ms] [device]
#   ./rpi_gpio_cycle.sh repeated_download.conf 2000 /dev/nvme0n1  # legacy
#   ./rpi_gpio_cycle.sh                                      # defaults
#==============================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

usage() {
        cat <<'EOF'
Usage: rpi_gpio_cycle.sh [options] [off_ms]

Options:
    -c, --config <file>   Load configuration (same format as plp.conf)
    -h, --help            Show this help message

Positional overrides:
    off_ms   Power-off time in ms (defaults to RPI_POWER_OFF_MS or 2000)

Legacy positional config path is still accepted for backwards compatibility.
EOF
}

# Default configuration
GPIO_MODE="${GPIO_MODE:-rpi}"  # "rpi" or "aardvark"
RPI_HOST="${RPI_HOST:-10.6.205.0}"
RPI_USER="${RPI_USER:-pi}"
RPI_SSH_PORT="${RPI_SSH_PORT:-22}"
RPI_SSH_KEY="${RPI_SSH_KEY:-}"
RPI_SSH_PASS="${RPI_SSH_PASS:-}"
RPI_GPIO_PIN="${RPI_GPIO_PIN:-17}"
RPI_POWER_OFF_MS="${RPI_POWER_OFF_MS:-2000}"
AARDVARK_PORT="${AARDVARK_PORT:-0}"
AARDVARK_GPIO_PIN="${AARDVARK_GPIO_PIN:-0}"
AARDVARK_POWER_OFF_MS="${AARDVARK_POWER_OFF_MS:-2000}"
NVME_DEVICE="${NVME_DEVICE:-/dev/nvme0n1}"

CONFIG_FILE=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [ -z "$CONFIG_FILE" ] && [ -n "$1" ] && [ -f "$1" ]; then
    CONFIG_FILE="$1"
    shift
fi

if [ -n "$CONFIG_FILE" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    print_info "Loading configuration from: $CONFIG_FILE"
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        export "$key=$value"
    done < "$CONFIG_FILE"
    GPIO_MODE="${GPIO_MODE:-rpi}"
    RPI_HOST="${RPI_HOST:-10.6.205.0}"
    RPI_USER="${RPI_USER:-pi}"
    RPI_SSH_PORT="${RPI_SSH_PORT:-22}"
    RPI_SSH_KEY="${RPI_SSH_KEY:-}"
    RPI_SSH_PASS="${RPI_SSH_PASS:-}"
    RPI_GPIO_PIN="${RPI_GPIO_PIN:-17}"
    RPI_POWER_OFF_MS="${RPI_POWER_OFF_MS:-2000}"
    AARDVARK_PORT="${AARDVARK_PORT:-0}"
    AARDVARK_GPIO_PIN="${AARDVARK_GPIO_PIN:-0}"
    AARDVARK_POWER_OFF_MS="${AARDVARK_POWER_OFF_MS:-2000}"
    NVME_DEVICE="${NVME_DEVICE:-/dev/nvme0n1}"
fi

# Normalize GPIO mode to lowercase
GPIO_MODE=$(echo "$GPIO_MODE" | tr '[:upper:]' '[:lower:]')

# Override with positional arguments after config processing
if [ "$GPIO_MODE" = "aardvark" ]; then
    [ -n "$1" ] && AARDVARK_POWER_OFF_MS="$1"
else
    [ -n "$1" ] && RPI_POWER_OFF_MS="$1"
fi

# Dispatch to appropriate implementation based on GPIO_MODE
if [ "$GPIO_MODE" = "aardvark" ]; then
    # Get script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    print_info "Using Aardvark GPIO mode"
    
    # Forward to Aardvark implementation
    if [ -n "$CONFIG_FILE" ]; then
        exec bash "${SCRIPT_DIR}/scripts/aardvark/gpio_cycle_aardvark.sh" -c "$CONFIG_FILE" "$AARDVARK_POWER_OFF_MS"
    else
        exec bash "${SCRIPT_DIR}/scripts/aardvark/gpio_cycle_aardvark.sh" "$AARDVARK_POWER_OFF_MS"
    fi
    exit $?
elif [ "$GPIO_MODE" != "rpi" ] && [ "$GPIO_MODE" != "rpi4" ]; then
    print_error "Invalid GPIO_MODE: $GPIO_MODE (must be 'rpi' or 'aardvark')"
    exit 1
fi

# Continue with RPI mode below
print_info "Using Raspberry Pi GPIO mode"

print_warning "========================================"
print_warning "RPi GPIO Power Cycle"
print_warning "========================================"
print_info "Target: ${RPI_USER}@${RPI_HOST}:${RPI_SSH_PORT}"
print_info "GPIO Pin: ${RPI_GPIO_PIN} (BCM)"
print_info "Power off duration: ${RPI_POWER_OFF_MS}ms"
echo ""

# Remote helper to write GPIO value with sysfs offset awareness
REMOTE_GPIO_SCRIPT=$(cat <<'EOF'
#!/bin/bash
set -e
PIN="$1"
VALUE="$2"

resolve_sysfs_gpio_number() {
    local bcm_pin="$1"
    local fallback_base=""
    local fallback_ngpio=""

    for chip_dir in /sys/class/gpio/gpiochip*; do
        [ -d "$chip_dir" ] || continue
        local label
        label=$(cat "$chip_dir/label" 2>/dev/null || true)
        local base
        base=$(cat "$chip_dir/base" 2>/dev/null || true)
        local ngpio
        ngpio=$(cat "$chip_dir/ngpio" 2>/dev/null || true)

        if [[ -z "$base" || -z "$ngpio" ]]; then
            continue
        fi

        if [ "$bcm_pin" -lt "$ngpio" ]; then
            if [[ "$label" =~ bcm2835|rp1|raspberrypi ]]; then
                echo $((base + bcm_pin))
                return 0
            fi

            if [ -z "$fallback_base" ]; then
                fallback_base="$base"
                fallback_ngpio="$ngpio"
            fi
        fi
    done

    if [ -n "$fallback_base" ]; then
        echo $((fallback_base + bcm_pin))
        return 0
    fi

    return 1
}

SYSFS_NUM=$(resolve_sysfs_gpio_number "$PIN") || {
    echo "[REMOTE] Unable to resolve sysfs GPIO for BCM ${PIN}" >&2
    exit 1
}
GPIO_PATH="/sys/class/gpio/gpio${SYSFS_NUM}"

if [ ! -d "$GPIO_PATH" ]; then
    echo "[REMOTE] Exporting GPIO${PIN} (sysfs ${SYSFS_NUM})"
    echo ${SYSFS_NUM} > /sys/class/gpio/export
    sleep 0.1
fi

echo out > "$GPIO_PATH/direction"
echo "$VALUE" > "$GPIO_PATH/value"
EOF
)

run_remote_gpio_write() {
    local value="$1"
    printf '%s\n' "$REMOTE_GPIO_SCRIPT" | "${SSH_PREFIX[@]}" "${RPI_USER}@${RPI_HOST}" sudo bash -s -- "$RPI_GPIO_PIN" "$value"
}

# Build SSH options array (always use default port 22)
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=5)

# Build SSH command prefix based on authentication method
if [ -n "$RPI_SSH_KEY" ]; then
    if [ ! -f "$RPI_SSH_KEY" ]; then
        print_error "SSH key file not found: $RPI_SSH_KEY"
        exit 1
    fi
    print_info "Using SSH key authentication: $RPI_SSH_KEY"
    SSH_PREFIX=(ssh -i "$RPI_SSH_KEY" "${SSH_OPTS[@]}")
elif [ -n "$RPI_SSH_PASS" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
        print_error "sshpass not installed. Install with: sudo apt-get install -y sshpass"
        exit 1
    fi
    print_info "Using SSH password authentication"
    SSH_PREFIX=(sshpass -p "$RPI_SSH_PASS" ssh "${SSH_OPTS[@]}")
else
    print_info "Using default SSH authentication (agent/keys)"
    SSH_PREFIX=(ssh "${SSH_OPTS[@]}")
fi

# Step 0: Reset GPIO to ensure known state (LOW = power ON)
print_info "Step 0: Resetting GPIO to known state (LOW = power ON)..."
if run_remote_gpio_write 0; then
    print_info "✓ GPIO reset to LOW (power ON)"
    sleep 2
else
    print_warning "GPIO reset failed, continuing anyway..."
fi

# Step 1: PCIe remove
if [ -e "${NVME_DEVICE}" ]; then
    print_warning "Step 1: Removing PCIe device..."
    NVME_BASE=$(basename "${NVME_DEVICE}")
    PCIE_ADDR=""
    
    # Try to find NVMe controller (nvme0 from nvme0n1)
    NVME_CTRL="${NVME_BASE%n*}"
    
    # Try multiple methods to find PCIe address
    if [ -L "/sys/class/nvme/${NVME_CTRL}/device" ]; then
        PCIE_ADDR=$(basename $(readlink "/sys/class/nvme/${NVME_CTRL}/device"))
        print_info "Found PCIe address via nvme controller: ${PCIE_ADDR}"
    elif [ -L "/sys/block/${NVME_BASE}/device" ]; then
        PCIE_ADDR=$(basename $(readlink "/sys/block/${NVME_BASE}/device"))
        print_info "Found PCIe address via block device: ${PCIE_ADDR}"
    fi
    
    if [ -n "$PCIE_ADDR" ]; then
        if [ -e "/sys/bus/pci/devices/${PCIE_ADDR}/remove" ]; then
            print_info "Running: echo 1 | sudo tee /sys/bus/pci/devices/${PCIE_ADDR}/remove"
            if echo 1 | sudo tee "/sys/bus/pci/devices/${PCIE_ADDR}/remove" > /dev/null 2>&1; then
                print_info "✓ PCIe device removed"
                sleep 0.5
            else
                print_warning "PCIe remove failed"
            fi
        else
            print_warning "PCIe device ${PCIE_ADDR} already removed or not present"
        fi
    else
        print_warning "Could not determine PCIe address - device may already be removed"
    fi
else
    print_info "Step 1: Device ${NVME_DEVICE} not present, skipping PCIe remove"
fi

# Step 2: Power OFF (GPIO HIGH = power off)
print_warning "Step 2: Powering OFF (GPIO${RPI_GPIO_PIN} = HIGH)..."
if run_remote_gpio_write 1; then
    print_info "✓ Power OFF command sent (GPIO = HIGH)"
else
    print_error "Failed to set GPIO OFF"
    exit 1
fi

# Step 3: Wait for specified duration
OFF_DURATION_SEC=$(echo "scale=3; ${RPI_POWER_OFF_MS}/1000" | bc)
print_info "Step 3: Waiting ${OFF_DURATION_SEC}s (${RPI_POWER_OFF_MS}ms) while power is off..."
sleep "$OFF_DURATION_SEC"

# Step 4: Power ON (GPIO LOW = power on)
print_warning "Step 4: Powering ON (GPIO${RPI_GPIO_PIN} = LOW)..."
if run_remote_gpio_write 0; then
    print_info "✓ Power ON command sent (GPIO = LOW)"
else
    print_error "Failed to set GPIO ON"
    exit 1
fi

# Step 5: Wait for stability before PCIe rescan
print_info "Step 5: Waiting 8s for power stabilization..."
sleep 8

# Step 6: PCIe rescan (try multiple times if needed)
print_warning "Step 6: Triggering PCIe bus rescan..."
print_info "Running: echo 1 | sudo tee /sys/bus/pci/rescan"
if echo 1 | sudo tee /sys/bus/pci/rescan > /dev/null 2>&1; then
    print_info "✓ PCIe rescan triggered"
    # Let udev settle to create device nodes
    if command -v udevadm >/dev/null 2>&1; then
        sudo udevadm settle
    fi
    sleep 2
else
    print_warning "PCIe rescan may have failed"
    if command -v udevadm >/dev/null 2>&1; then
        sudo udevadm settle
    fi
    sleep 2
fi

find_nvme_node() {
    # Prefer configured NVME_DEVICE if present
    if [ -n "$NVME_DEVICE" ] && [ -e "$NVME_DEVICE" ]; then
        echo "$NVME_DEVICE"
        return 0
    fi
    # Try controller nodes
    for dev in /dev/nvme*; do
        [ -e "$dev" ] || continue
        # Prefer namespaces (n1) if available; else use controller
        if [[ "$dev" =~ nvme[0-9]+n[0-9]+$ ]]; then
            echo "$dev"
            return 0
        fi
        candidate_ctrl="$dev"
    done
    if [ -n "$candidate_ctrl" ]; then
        echo "$candidate_ctrl"
        return 0
    fi
    return 1
}

# Step 7: Wait for device re-enumeration (controller or namespace)
print_info "Step 7: Waiting for NVMe device to re-enumerate..."
TIMEOUT=60
COUNT=0
NVME_NODE=""
while [ $COUNT -lt $TIMEOUT ]; do
    NVME_NODE=$(find_nvme_node) || true
    if [ -n "$NVME_NODE" ] && [ -e "$NVME_NODE" ]; then
        break
    fi
    sleep 1
    COUNT=$((COUNT + 1))
    # Try rescanning again every 10 seconds if device not found
    if [ $((COUNT % 10)) -eq 0 ]; then
        print_warning "  Still waiting... ${COUNT}s elapsed, triggering rescan again..."
        echo 1 | sudo tee /sys/bus/pci/rescan > /dev/null 2>&1
        if command -v udevadm >/dev/null 2>&1; then
            sudo udevadm settle
        fi
    elif [ $((COUNT % 5)) -eq 0 ]; then
        print_warning "  Still waiting... ${COUNT}s elapsed"
    fi
done

echo ""
if [ -n "$NVME_NODE" ] && [ -e "$NVME_NODE" ]; then
    print_info "✓ Device ${NVME_NODE} detected after ${COUNT}s"
    print_info "Waiting for device to fully initialize..."
    sleep 3
    
    # Verify device is accessible with nvme command
    print_info "Verifying device is accessible..."
    if sudo nvme list 2>/dev/null | grep -q "$(basename ${NVME_NODE})"; then
        print_info "✓ Device is accessible via nvme list"
        
        # Try to read firmware version to confirm full access
        print_info "Reading firmware version..."
        for attempt in 1 2 3 4 5; do
            FW_VER=$(sudo nvme id-ctrl ${NVME_NODE} 2>/dev/null | grep "fr " | awk '{print $3}')
            if [ -n "$FW_VER" ]; then
                print_info "✓ Firmware version: ${FW_VER}"
                print_info "✓ Device is fully accessible and ready"
                print_info "✓ Power cycle completed successfully"
                exit 0
            fi
            if [ $attempt -lt 5 ]; then
                print_warning "Attempt $attempt: Could not read firmware version, retrying in 2s..."
                sleep 2
            fi
        done
        
        print_error "✗ Device not accessible via nvme commands after 5 attempts"
        print_error "Device may need manual intervention"
        exit 1
    else
        print_error "✗ Device not visible in nvme list"
        exit 1
    fi
else
    print_error "✗ Device NOT detected within ${TIMEOUT}s"
    print_error "Power cycle may have failed or device enumeration issue"
    exit 1
fi
