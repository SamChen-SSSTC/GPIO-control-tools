#!/bin/bash

#==============================================================================
# Aardvark GPIO Power ON Script
# Controls GPIO on TotalPhase Aardvark adapter to turn power ON
#
# Usage:
#   ./gpio_on_aardvark.sh -c plp.conf
#   ./gpio_on_aardvark.sh [aardvark_port] [gpio_pin]
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
Usage: gpio_on_aardvark.sh [options]

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
print_info "Aardvark GPIO Power ON"
print_info "========================================"
print_info "Port: ${AARDVARK_PORT}"
print_info "GPIO Pin: ${AARDVARK_GPIO_PIN}"
print_info "Action: Set LOW (power ON)"
echo ""

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
print_info "Setting GPIO${AARDVARK_GPIO_PIN} LOW (power ON)..."
if python3 "${PROJECT_ROOT}/lib/aardvark_gpio.py" --port "${AARDVARK_PORT}" --pin "${AARDVARK_GPIO_PIN}" --low; then
    print_info "✓ GPIO${AARDVARK_GPIO_PIN} power-on sequence completed"
else
    print_error "✗ Failed to execute GPIO${AARDVARK_GPIO_PIN} power-on sequence"
    exit 1
fi

# PCIe rescan to detect device
print_info "Triggering PCIe bus rescan..."
print_info "Running: echo 1 | sudo tee /sys/bus/pci/rescan"
if echo 1 | sudo tee /sys/bus/pci/rescan > /dev/null 2>&1; then
    print_info "✓ PCIe rescan triggered"
    sleep 2
else
    print_warning "PCIe rescan failed (may need sudo)"
    sleep 2
fi

# Wait for device
print_info "Waiting for device ${NVME_DEVICE}..."
TIMEOUT=60
COUNT=0
while [ ! -e "${NVME_DEVICE}" ] && [ $COUNT -lt $TIMEOUT ]; do
    sleep 1
    COUNT=$((COUNT + 1))
    if [ $((COUNT % 5)) -eq 0 ]; then
        print_warning "  Still waiting... ${COUNT}s elapsed"
    fi
done

if [ -e "${NVME_DEVICE}" ]; then
    print_info "✓ Device ${NVME_DEVICE} detected after ${COUNT}s"
    sleep 2
    
    # Verify device is accessible with nvme command
    print_info "Verifying device is accessible..."
    if sudo nvme list 2>/dev/null | grep -q "$(basename ${NVME_DEVICE})"; then
        print_info "✓ Device is accessible and ready"
        exit 0
    else
        print_warning "Device node exists but nvme command cannot access it yet"
        sleep 3
        if sudo nvme list 2>/dev/null | grep -q "$(basename ${NVME_DEVICE})"; then
            print_info "✓ Device is now accessible and ready"
            exit 0
        else
            print_error "✗ Device not accessible via nvme command after waiting"
            exit 1
        fi
    fi
else
    print_error "✗ Device ${NVME_DEVICE} NOT detected within ${TIMEOUT}s"
    exit 1
fi
