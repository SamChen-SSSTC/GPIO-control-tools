#!/bin/bash

#==============================================================================
# Aardvark GPIO Power Cycle Script
# Complete power cycle: OFF → Wait → ON → Wait for device
#
# Usage:
#   ./gpio_cycle_aardvark.sh -c plp.conf [off_ms]
#   ./gpio_cycle_aardvark.sh [off_ms] [aardvark_port] [gpio_pin]
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
Usage: gpio_cycle_aardvark.sh [options] [off_ms]

Options:
    -c, --config <file>   Load configuration (same format as plp.conf)
    -h, --help            Show this help message

Positional arguments:
    off_ms               Power-off time in ms (default: 2000)
    aardvark_port        Aardvark port number (default: 0)
    gpio_pin             GPIO pin number (default: 0)
EOF
}

# Default configuration
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
    AARDVARK_POWER_OFF_MS="${AARDVARK_POWER_OFF_MS:-2000}"
    NVME_DEVICE="${NVME_DEVICE:-/dev/nvme0n1}"
fi

# Positional overrides
if [ -n "$1" ]; then
    AARDVARK_POWER_OFF_MS="$1"
fi
if [ -n "$2" ]; then
    AARDVARK_PORT="$2"
fi
if [ -n "$3" ]; then
    AARDVARK_GPIO_PIN="$3"
fi

print_info "========================================"
print_info "Aardvark GPIO Power Cycle"
print_info "========================================"
print_info "Port: ${AARDVARK_PORT}"
print_info "GPIO Pin: ${AARDVARK_GPIO_PIN}"
print_info "Power-Off Duration: ${AARDVARK_POWER_OFF_MS} ms"
echo ""

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/../.." && pwd )"

# Execute power cycle using Python module directly
print_info "Starting power cycle..."

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

# Power OFF
print_info "Step 1: Power OFF (GPIO HIGH)"
if ! bash "${SCRIPT_DIR}/gpio_off_aardvark.sh" -c "${CONFIG_FILE:-/dev/null}" 2>&1 | grep -v "^$"; then
    print_error "Failed to power off device"
    exit 1
fi

# Wait
WAIT_SEC=$(echo "scale=2; ${AARDVARK_POWER_OFF_MS} / 1000" | bc)
print_info "Step 2: Waiting ${WAIT_SEC}s..."
sleep "${WAIT_SEC}"

# Power ON
print_info "Step 3: Power ON (GPIO LOW)"
if ! bash "${SCRIPT_DIR}/gpio_on_aardvark.sh" -c "${CONFIG_FILE:-/dev/null}" 2>&1 | grep -v "^$"; then
    print_error "Failed to power on device"
    exit 1
fi

print_info "✓ Power cycle completed successfully"
exit 0
