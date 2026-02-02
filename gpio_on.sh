#!/bin/bash

#==============================================================================
# RPi GPIO Power ON Script (Host-Side)
# Triggers GPIO on Raspberry Pi via SSH to turn power ON
#
# Usage:
#   ./gpio_on.sh -c plp.conf
#   ./gpio_on.sh plp.conf                   # legacy shorthand
#   ./gpio_on.sh                            # Uses defaults
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
Usage: gpio_on.sh [options]

Options:
    -c, --config <file>   Load configuration (same format as plp.conf)
    -h, --help            Show this help message

Legacy positional use is still supported: gpio_on.sh plp.conf
EOF
}

# Default configuration
GPIO_MODE="${GPIO_MODE:-rpi}"  # "rpi" or "aardvark"
RPI_HOST="${RPI_HOST:-10.6.205.0}"
RPI_USER="${RPI_USER:-pi}"
RPI_SSH_KEY="${RPI_SSH_KEY:-}"
RPI_SSH_PASS="${RPI_SSH_PASS:-}"
RPI_GPIO_PIN="${RPI_GPIO_PIN:-17}"
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
    GPIO_MODE="${GPIO_MODE:-rpi}"
    RPI_HOST="${RPI_HOST:-10.6.205.0}"
    RPI_USER="${RPI_USER:-pi}"
    RPI_SSH_KEY="${RPI_SSH_KEY:-}"
    RPI_SSH_PASS="${RPI_SSH_PASS:-}"
    RPI_GPIO_PIN="${RPI_GPIO_PIN:-17}"
    AARDVARK_PORT="${AARDVARK_PORT:-0}"
    AARDVARK_GPIO_PIN="${AARDVARK_GPIO_PIN:-0}"
    NVME_DEVICE="${NVME_DEVICE:-/dev/nvme0n1}"
fi

# Normalize GPIO mode to lowercase
GPIO_MODE=$(echo "$GPIO_MODE" | tr '[:upper:]' '[:lower:]')

# Dispatch to appropriate implementation based on GPIO_MODE
if [ "$GPIO_MODE" = "aardvark" ]; then
    # Get script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    print_info "Using Aardvark GPIO mode"
    
    # Forward to Aardvark implementation
    if [ -n "$CONFIG_FILE" ]; then
        exec bash "${SCRIPT_DIR}/scripts/aardvark/gpio_on_aardvark.sh" -c "$CONFIG_FILE"
    else
        exec bash "${SCRIPT_DIR}/scripts/aardvark/gpio_on_aardvark.sh"
    fi
    exit $?
elif [ "$GPIO_MODE" != "rpi" ] && [ "$GPIO_MODE" != "rpi4" ]; then
    print_error "Invalid GPIO_MODE: $GPIO_MODE (must be 'rpi' or 'aardvark')"
    exit 1
fi

# Continue with RPI mode below
print_info "Using Raspberry Pi GPIO mode"

print_info "========================================"
print_info "RPi GPIO Power ON"
print_info "========================================"
print_info "Target: ${RPI_USER}@${RPI_HOST}"
print_info "GPIO Pin: ${RPI_GPIO_PIN} (BCM)"
print_info "Sequence: export -> set LOW (power ON)"
echo ""

# Build SSH options array (always use default port 22)
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=5)

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

REMOTE_SCRIPT=$(cat <<'EOF'
#!/bin/bash
set -e
GPIO_PIN="$1"
BASE_GPIO_PATH=/sys/class/gpio

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

SYSFS_NUM=$(resolve_sysfs_gpio_number "$GPIO_PIN") || {
    echo "[REMOTE] Unable to resolve sysfs GPIO for BCM ${GPIO_PIN}" >&2
    exit 1
}
OP_GPIO_PATH=$BASE_GPIO_PATH/gpio${SYSFS_NUM}

log() { echo "[REMOTE] $1"; }

if [ -d "$OP_GPIO_PATH" ]; then
    log "GPIO${GPIO_PIN} already exported -> unexport"
    echo ${SYSFS_NUM} > $BASE_GPIO_PATH/unexport
    sleep 0.1
fi

log "Export GPIO${GPIO_PIN}"
echo ${SYSFS_NUM} > $BASE_GPIO_PATH/export
sleep 0.1

log "Set direction OUT"
echo out > $OP_GPIO_PATH/direction

log "Drive LOW (power ON)"
echo 0 > $OP_GPIO_PATH/value

log "GPIO${GPIO_PIN} remains exported to hold LOW state"
EOF
)

run_remote_sequence() {
    local target="${RPI_USER}@${RPI_HOST}"
    printf '%s\n' "$REMOTE_SCRIPT" | "${SSH_PREFIX[@]}" "$target" sudo bash -s -- "$RPI_GPIO_PIN"
}

if run_remote_sequence; then
    print_info "✓ GPIO${RPI_GPIO_PIN} power-on sequence completed"
else
    print_error "✗ Failed to execute GPIO${RPI_GPIO_PIN} power-on sequence"
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
