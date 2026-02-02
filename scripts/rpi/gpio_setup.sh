#!/bin/bash

#==============================================================================
# RPi4 GPIO Power Control Setup Script (Host + Remote)
# Configures Raspberry Pi GPIO for relay-based PLP testing from the JHost.
#
# Hardware Setup:
#   - Connect relay module to Raspberry Pi GPIO pin (BCM numbering)
#   - Active HIGH = Power OFF, Active LOW = Power ON
#
# Usage:
#   ./gpio_setup.sh -c plp.conf -p 23 --test   # Remote run from JHost
#   ./gpio_setup.sh --local 23 test            # Direct run on RPi (legacy)
#   ./gpio_setup.sh                            # Uses defaults/config
#==============================================================================

set -e
set -o pipefail

#--------------------------------------
# Colors & helpers
#--------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

usage() {
    cat <<'EOF'
Usage: gpio_setup.sh [options] [gpio_pin] [test]

Options:
  -c, --config <file>   Load RPi/JHost settings from config file (plp.conf)
  -p, --pin <gpio>      Override GPIO pin (BCM number, default 17)
      --test            Run a short power-cycle validation after setup
      --local           Run directly on the RPi (script must be executed there)
      --remote          Force remote SSH mode (default)
  -h, --help            Show this help message

Positional compatibility:
  gpio_setup.sh 23 test    # Same as --pin 23 --test

Remote mode requires RPI_HOST / RPI_USER and optional auth vars in the config
file or environment. When --local is used, the script must be run with sudo on
the Raspberry Pi.
EOF
}

#--------------------------------------
# Defaults & CLI parsing
#--------------------------------------
CONFIG_FILE=""
GPIO_PIN="${GPIO_PIN:-17}"
TEST_MODE=""
RUN_LOCAL=false

# Default configuration (can be overridden by env/config)
RPI_HOST="${RPI_HOST:-10.6.205.0}"
RPI_USER="${RPI_USER:-pi}"
RPI_SSH_KEY="${RPI_SSH_KEY:-}"
RPI_SSH_PASS="${RPI_SSH_PASS:-}"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -p|--pin)
            GPIO_PIN="$2"
            shift 2
            ;;
        --test)
            TEST_MODE="test"
            shift
            ;;
        --local)
            RUN_LOCAL=true
            shift
            ;;
        --remote)
            RUN_LOCAL=false
            shift
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

# Backwards compatibility: positional GPIO + optional "test"
if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    GPIO_PIN="$1"
    shift
fi
if [[ $# -gt 0 && "$1" == "test" ]]; then
    TEST_MODE="test"
    shift
fi

#--------------------------------------
# Config loader
#--------------------------------------
load_config() {
    local cfg="$1"
    if [ ! -f "$cfg" ]; then
        print_error "Config file not found: $cfg"
        exit 1
    fi
    print_info "Loading configuration from: $cfg"
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
    done < "$cfg"

    RPI_HOST="${RPI_HOST:-10.6.205.0}"
    RPI_USER="${RPI_USER:-pi}"
    RPI_SSH_KEY="${RPI_SSH_KEY:-}"
    RPI_SSH_PASS="${RPI_SSH_PASS:-}"
    if [ -n "${RPI_GPIO_PIN:-}" ]; then
        GPIO_PIN="$RPI_GPIO_PIN"
    fi
}

if [ -n "$CONFIG_FILE" ]; then
    load_config "$CONFIG_FILE"
fi

#--------------------------------------
# Validation
#--------------------------------------
if ! [[ "$GPIO_PIN" =~ ^[0-9]+$ ]] || [ "$GPIO_PIN" -lt 2 ] || [ "$GPIO_PIN" -gt 27 ]; then
    print_error "Invalid GPIO pin: $GPIO_PIN (valid BCM range 2-27)"
    exit 1
fi

if $RUN_LOCAL && [ "$EUID" -ne 0 ]; then
    print_error "Local mode requires sudo/root access"
    exit 1
fi

if ! $RUN_LOCAL && [ -z "$RPI_HOST" ]; then
    print_error "Remote mode requires RPI_HOST configured"
    exit 1
fi

print_info "========================================"
print_info "RPi4 GPIO Power Control Setup"
print_info "========================================"
if $RUN_LOCAL; then
    print_info "Mode : Local (executing on Raspberry Pi)"
    print_info "GPIO : BCM $GPIO_PIN"
else
    print_info "Mode : Remote via SSH"
    print_info "Host : ${RPI_USER}@${RPI_HOST}"
    if [ -n "$RPI_SSH_KEY" ]; then
        print_info "Auth : SSH key (${RPI_SSH_KEY})"
    elif [ -n "$RPI_SSH_PASS" ]; then
        print_info "Auth : Password"
    else
        print_info "Auth : Default SSH agent/keys"
    fi
    print_info "GPIO : BCM $GPIO_PIN"
fi
if [ "$TEST_MODE" == "test" ]; then
    print_warning "Test mode enabled: relay will toggle"
fi
echo ""

#--------------------------------------
# Remote script body (executed on RPi)
#--------------------------------------
REMOTE_SCRIPT=$(cat <<'REMOTE_SCRIPT'
#!/bin/bash
set -e

GPIO_PIN="$1"
TEST_MODE="$2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

resolve_sysfs_gpio_number() {
    local bcm_pin="$1"
    local fallback_chip=""
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

            if [ -z "$fallback_chip" ]; then
                fallback_chip="$chip_dir"
                fallback_base="$base"
                fallback_ngpio="$ngpio"
            fi
        fi
    done

    if [ -n "$fallback_chip" ]; then
        echo $((fallback_base + bcm_pin))
        return 0
    fi

    return 1
}

NON_INTERACTIVE=0
if [ ! -t 0 ]; then
    NON_INTERACTIVE=1
fi

echo ""
print_info "========================================"
print_info "RPi4 GPIO Power Control Setup (On-Device)"
print_info "========================================"
print_info "GPIO Pin: ${GPIO_PIN} (BCM numbering)"
echo ""

diagnose_export_failure() {
    print_error "Failed to export GPIO${GPIO_PIN}"
    if [ ! -e /sys/class/gpio/export ]; then
        print_warning "Node /sys/class/gpio/export is missing (legacy GPIO sysfs disabled)."
        print_warning "Add 'dtoverlay=gpio-no-irq' to /boot/firmware/config.txt (or /boot/config.txt) and reboot."
        return
    fi

    print_warning "Kernel: $(uname -a)"
    print_warning "Overlays: $(tr '\0' ' ' </proc/device-tree/chosen/bootargs 2>/dev/null | grep -o 'dtoverlay[^ ]*' || echo 'unknown')"
    print_warning "Existing GPIO nodes: $(ls /sys/class/gpio 2>/dev/null | xargs)"
    print_warning "Last dmesg GPIO lines:"
    dmesg | grep -i gpio | tail -5
}

if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    print_warning "This device does not appear to be a Raspberry Pi"
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        print_error "Non-interactive session cannot confirm continuation"
        exit 1
    else
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
fi

if ! [[ "$GPIO_PIN" =~ ^[0-9]+$ ]] || [ "$GPIO_PIN" -lt 2 ] || [ "$GPIO_PIN" -gt 27 ]; then
    print_error "Invalid GPIO pin: ${GPIO_PIN}"
    exit 1
fi

if [ ! -d /sys/class/gpio ]; then
    print_error "GPIO sysfs interface not available"
    exit 1
fi

# Determine actual sysfs GPIO number (newer kernels offset BCM index)
SYSFS_GPIO_NUM=""
if SYSFS_GPIO_NUM=$(resolve_sysfs_gpio_number "$GPIO_PIN"); then
    :
else
    print_error "Unable to determine sysfs GPIO number for BCM ${GPIO_PIN}"
    diagnose_export_failure
    exit 1
fi

SYSFS_GPIO_PATH="/sys/class/gpio/gpio${SYSFS_GPIO_NUM}"
print_info "Resolved sysfs GPIO number: ${SYSFS_GPIO_NUM}"

if [ ! -d "$SYSFS_GPIO_PATH" ]; then
    print_info "Exporting GPIO${GPIO_PIN} (sysfs ${SYSFS_GPIO_NUM})..."
    if echo ${SYSFS_GPIO_NUM} > /sys/class/gpio/export 2>/dev/null; then
        print_info "GPIO${GPIO_PIN} exported successfully"
        sleep 0.5
    elif [ -d "$SYSFS_GPIO_PATH" ]; then
        print_info "GPIO${GPIO_PIN} already accessible"
    else
        diagnose_export_failure
        exit 1
    fi
else
    print_info "GPIO${GPIO_PIN} already exported (sysfs ${SYSFS_GPIO_NUM})"
fi

if [ ! -d "$SYSFS_GPIO_PATH" ]; then
    print_error "GPIO${GPIO_PIN} directory missing after export"
    exit 1
fi

print_info "Setting GPIO${GPIO_PIN} as output..."
echo "out" > "$SYSFS_GPIO_PATH/direction"

print_info "Initializing GPIO${GPIO_PIN} to LOW (Power ON)..."
echo 0 > "$SYSFS_GPIO_PATH/value"

echo ""
print_info "✓ GPIO${GPIO_PIN} configured successfully"
if current_value=$(cat /sys/class/gpio/gpio${GPIO_PIN}/value 2>/dev/null); then
    print_info "Current state: ${current_value}"
fi
echo ""

if [ "${TEST_MODE}" == "test" ]; then
    print_warning "========================================"
    print_warning "Test Mode: Power Cycle"
    print_warning "========================================"
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        print_warning "Non-interactive session → continuing without prompt"
    else
        read -p "Press Enter to continue or Ctrl+C to cancel... "
    fi
    print_info "Switching GPIO HIGH (Power OFF)..."
    echo 1 > "$SYSFS_GPIO_PATH/value"
    sleep 3
    print_info "Switching GPIO LOW (Power ON)..."
    echo 0 > "$SYSFS_GPIO_PATH/value"
    print_info "✓ Test power cycle completed"
    echo ""
fi

cat <<'EOF'

========================================
Quick Setup Checklist
========================================

1. Wiring
   • Relay VCC → 5V, GND → GND, IN → selected GPIO pin
   • Relay COM/NO wired to DUT power rail

2. Host-Side Validation
   • From JHost: ./test_rpi_gpio.sh -c plp.conf
   • Confirms GPIO read/write over SSH

3. Integration
   • FW_update.sh uses rpi_gpio_on/off.sh automatically
   • Ensure RPI_GPIO_PIN matches this setup script

4. Troubleshooting
   • sudo cat /sys/class/gpio/gpio${GPIO_PIN}/value
   • sudo cat /sys/kernel/debug/gpio | grep ${GPIO_PIN}
   • Verify relay clicks when toggling values

========================================
EOF

print_info "Setup complete on $(hostname). GPIO${GPIO_PIN} is ready."
REMOTE_SCRIPT
)

#--------------------------------------
# Execution helper
#--------------------------------------
run_local() {
    printf '%s\n' "$REMOTE_SCRIPT" | sudo bash -s -- "$GPIO_PIN" "$TEST_MODE"
}

run_remote() {
    local ssh_target="${RPI_USER}@${RPI_HOST}"
    local ssh_opts=(-o StrictHostKeyChecking=no -o ConnectTimeout=5)

    if [ -n "$RPI_SSH_KEY" ]; then
        ssh_opts+=(-i "$RPI_SSH_KEY")
    fi

    if [ -n "$RPI_SSH_PASS" ] && [ -z "$RPI_SSH_KEY" ]; then
        if ! command -v sshpass >/dev/null 2>&1; then
            print_error "sshpass not installed. Install with: sudo apt-get install -y sshpass"
            exit 1
        fi
        if printf '%s\n' "$REMOTE_SCRIPT" | sshpass -p "$RPI_SSH_PASS" ssh "${ssh_opts[@]}" "$ssh_target" sudo bash -s -- "$GPIO_PIN" "$TEST_MODE"; then
            return 0
        else
            return 1
        fi
    else
        if printf '%s\n' "$REMOTE_SCRIPT" | ssh "${ssh_opts[@]}" "$ssh_target" sudo bash -s -- "$GPIO_PIN" "$TEST_MODE"; then
            return 0
        else
            return 1
        fi
    fi
}

#--------------------------------------
# Run
#--------------------------------------
if $RUN_LOCAL; then
    if run_local; then
        print_info "Local GPIO setup finished"
    else
        print_error "Local GPIO setup failed"
        exit 1
    fi
else
    if run_remote; then
        print_info "Remote GPIO setup finished"
    else
        print_error "Remote GPIO setup failed"
        exit 1
    fi
fi

exit 0
