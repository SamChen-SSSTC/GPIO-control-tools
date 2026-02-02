#!/bin/bash

#==============================================================================
# Aardvark GPIO Power OFF Script
# Controls GPIO on TotalPhase Aardvark adapter to turn power OFF
#
# Usage:
#   ./gpio_off_aardvark.sh -c plp.conf
#   ./gpio_off_aardvark.sh [aardvark_port] [gpio_pin]
#==============================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

usage() {
    cat <<'EOF'
Usage: gpio_off_aardvark.sh [options]

Options:
    -c, --config <file>   Load configuration (same format as plp.conf)
    -h, --help            Show this help message

Positional arguments (legacy):
    aardvark_port        Aardvark port number (default: 0)
    gpio_pin             GPIO pin number (default: 0)
EOF
}

# Default configuration
AARDVARK_PORT="${AARDVARK_PORT:-0}"
AARDVARK_GPIO_PIN="${AARDVARK_GPIO_PIN:-0}"
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
    AARDVARK_PORT="${AARDVARK_PORT:-0}"
    AARDVARK_GPIO_PIN="${AARDVARK_GPIO_PIN:-0}"
    NVME_DEVICE="${NVME_DEVICE:-/dev/nvme0n1}"
fi

# Positional overrides
if [ -n "$1" ]; then
    AARDVARK_PORT="$1"
fi
if [ -n "$2" ]; then
    AARDVARK_GPIO_PIN="$2"
fi

print_info "========================================"
print_info "Aardvark GPIO Power OFF"
print_info "========================================"
print_info "Port: ${AARDVARK_PORT}"
print_info "GPIO Pin: ${AARDVARK_GPIO_PIN}"
print_info "Action: Set HIGH (power OFF)"
echo ""

# PCIe remove before power off
if [ -e "${NVME_DEVICE}" ]; then
    print_info "Removing PCIe device before power off..."
    NVME_BASE=$(basename "${NVME_DEVICE}")
    PCIE_ADDR=""
    
    # Try to find NVMe controller (nvme0 from nvme0n1)
    NVME_CTRL="${NVME_BASE%n*}"
    
    # Try multiple methods to find PCIe address
    if [ -L "/sys/class/nvme/${NVME_CTRL}/device" ]; then
        PCIE_ADDR=$(basename $(readlink "/sys/class/nvme/${NVME_CTRL}/device"))
    elif [ -L "/sys/block/${NVME_BASE}/device" ]; then
        PCIE_ADDR=$(basename $(readlink "/sys/block/${NVME_BASE}/device"))
    fi
    
    if [ -n "$PCIE_ADDR" ]; then
        print_info "Found PCIe address: ${PCIE_ADDR}"
        if [ -e "/sys/bus/pci/devices/${PCIE_ADDR}/remove" ]; then
            print_info "Running: echo 1 | sudo tee /sys/bus/pci/devices/${PCIE_ADDR}/remove"
            if echo 1 | sudo tee "/sys/bus/pci/devices/${PCIE_ADDR}/remove" > /dev/null 2>&1; then
                print_info "✓ PCIe device removed"
                sleep 0.5
            else
                print_warning "PCIe remove failed (may need sudo)"
            fi
        else
            print_warning "PCIe device ${PCIE_ADDR} already removed or not present"
        fi
    else
        print_warning "Could not determine PCIe address - device may already be removed"
    fi
else
    print_warning "Device ${NVME_DEVICE} not present, skipping PCIe remove"
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/../.." && pwd )"

# Check for Python and aardvark_gpio module
if ! command -v python3 >/dev/null 2>&1; then
    print_error "python3 not found. Please install Python 3"
    exit 1
fi

if ! python3 -c "import aardvark_py" 2>/dev/null; then
    print_error "aardvark_py module not found"
    print_error "Install from: https://www.totalphase.com/products/aardvark-i2cspi/"
    exit 1
fi

if [ ! -f "${PROJECT_ROOT}/lib/aardvark_gpio.py" ]; then
    print_error "aardvark_gpio.py not found in ${PROJECT_ROOT}/lib"
    exit 1
fi

# Execute GPIO command
print_info "Setting GPIO${AARDVARK_GPIO_PIN} HIGH (power OFF)..."
if python3 "${PROJECT_ROOT}/lib/aardvark_gpio.py" --port "${AARDVARK_PORT}" --pin "${AARDVARK_GPIO_PIN}" --high; then
    print_info "✓ GPIO${AARDVARK_GPIO_PIN} power-off sequence completed"
    
    # Verify device is gone
    print_info "Verifying device is powered off..."
    sleep 2
    
    if [ ! -e "${NVME_DEVICE}" ]; then
        print_info "✓ Device ${NVME_DEVICE} is no longer present"
        exit 0
    else
        print_warning "Device node still exists after power off"
        if sudo nvme list 2>/dev/null | grep -q "$(basename ${NVME_DEVICE})"; then
            print_error "✗ Device is still accessible - power off may have failed"
            exit 1
        else
            print_info "✓ Device is not accessible (node exists but inactive)"
            exit 0
        fi
    fi
else
    print_error "✗ Failed to execute GPIO${AARDVARK_GPIO_PIN} power-off sequence"
    exit 1
fi
