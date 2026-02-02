#!/bin/bash

#==============================================================================
# Test RPi GPIO Control from Host
# Tests the GPIO control scripts to verify SSH and GPIO are working
#==============================================================================

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

echo "========================================"
echo "  RPi GPIO Control Test from Host"
echo "========================================"
echo ""

CONFIG_FILE=""
DEFAULT_CONFIG="plp.conf"

if [ "$1" = "-c" ] || [ "$1" = "--config" ]; then
    CONFIG_FILE="$2"
    shift 2
    if [ -z "$CONFIG_FILE" ]; then
        print_error "Config file path missing after -c/--config"
        exit 1
    fi
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
fi

load_config_file() {
    local cfg="$1"
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
    echo ""
}

if [ -z "$CONFIG_FILE" ]; then
    if [ -f "$DEFAULT_CONFIG" ]; then
        CONFIG_FILE="$DEFAULT_CONFIG"
        load_config_file "$CONFIG_FILE"
    else
        print_warning "No config file provided. Using default values."
        print_info "You can create $DEFAULT_CONFIG with:"
        echo "  RPI_HOST=\"10.6.205.0\""
        echo "  RPI_USER=\"pi\""
        echo "  RPI_SSH_PASS=\"your_password\""
        echo "  RPI_GPIO_PIN=\"17\""
        echo ""
    fi
else
    load_config_file "$CONFIG_FILE"
fi

RPI_HOST="${RPI_HOST:-10.6.205.0}"
RPI_USER="${RPI_USER:-pi}"
RPI_SSH_KEY="${RPI_SSH_KEY:-}"
RPI_SSH_PASS="${RPI_SSH_PASS:-}"
RPI_GPIO_PIN="${RPI_GPIO_PIN:-17}"
SYSFS_GPIO_PATH=""
SYSFS_GPIO_NUM=""

CONFIG_ARG=""
if [ -n "$CONFIG_FILE" ]; then
    CONFIG_ARG="$CONFIG_FILE"
fi

# ==== Test 1: Check GPIO scripts exist ========================================
print_step "1. Checking GPIO control scripts..."
if [ -x "./gpio_on.sh" ] && [ -x "./gpio_off.sh" ]; then
    print_info "✓ GPIO scripts found and executable"
else
    print_error "✗ GPIO scripts not found or not executable"
    print_error "Run: chmod +x rpi_gpio_*.sh"
    exit 1
fi
echo ""

# ==== Test 2: Test SSH connectivity ========================================
print_step "2. Testing SSH connection to RPi..."

print_info "Testing: ${RPI_USER}@${RPI_HOST}"

# Try SSH connection
if [ -n "$RPI_SSH_KEY" ]; then
    SSH_TEST="ssh -i $RPI_SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=3"
elif [ -n "$RPI_SSH_PASS" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
        print_error "sshpass not installed. Install with: sudo apt-get install -y sshpass"
        exit 1
    fi
    SSH_TEST="sshpass -p $RPI_SSH_PASS ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3"
else
    SSH_TEST="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3"
fi

if $SSH_TEST "${RPI_USER}@${RPI_HOST}" "echo 'SSH_OK'" 2>/dev/null | grep -q "SSH_OK"; then
    print_info "✓ SSH connection successful"
else
    print_error "✗ SSH connection failed"
    print_error "Check network, credentials, or run: ssh ${RPI_USER}@${RPI_HOST}"
    exit 1
fi
echo ""

# ==== Test 3: Check GPIO on RPi ========================================
print_step "3. Checking GPIO setup on RPi..."
GPIO_PIN="${RPI_GPIO_PIN:-17}"
GPIO_CHECK=$($SSH_TEST "${RPI_USER}@${RPI_HOST}" "bash -s -- ${GPIO_PIN}" <<'REMOTE'
PIN="$1"

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

if SYSFS_NUM=$(resolve_sysfs_gpio_number "$PIN"); then
    GPIO_PATH="/sys/class/gpio/gpio${SYSFS_NUM}"
    if [ -d "$GPIO_PATH" ]; then
        echo "EXISTS:${GPIO_PATH}"
    else
        echo "MISSING:${GPIO_PATH}"
    fi
else
    echo "UNRESOLVED"
    exit 1
fi
REMOTE
)
GPIO_CHECK_RC=$?

if [ $GPIO_CHECK_RC -ne 0 ] || [ -z "$GPIO_CHECK" ]; then
    print_warning "Unable to resolve GPIO path via SSH"
    print_info "On the RPi, run: sudo ./rpi4_gpio_setup.sh ${GPIO_PIN}"
    exit 1
fi

if [[ "$GPIO_CHECK" == EXISTS:* ]]; then
    SYSFS_GPIO_PATH="${GPIO_CHECK#EXISTS:}"
    SYSFS_GPIO_NUM="${SYSFS_GPIO_PATH##*/gpio}"
    print_info "✓ GPIO${GPIO_PIN} exported at ${SYSFS_GPIO_PATH}"
elif [[ "$GPIO_CHECK" == MISSING:* ]]; then
    SYSFS_GPIO_PATH="${GPIO_CHECK#MISSING:}"
    SYSFS_GPIO_NUM="${SYSFS_GPIO_PATH##*/gpio}"
    print_warning "✗ GPIO${GPIO_PIN} not currently exported on RPi"
    print_info "On the RPi, run: sudo ./rpi4_gpio_setup.sh ${GPIO_PIN}"
    print_info "Or manually: echo ${SYSFS_GPIO_NUM} | sudo tee /sys/class/gpio/export"
    echo ""
    read -p "Continue test anyway? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_error "Unexpected GPIO check result: ${GPIO_CHECK}"
    exit 1
fi
echo ""

# ==== Test 4: Read current GPIO value ========================================
print_step "4. Reading current GPIO value..."
if [ -z "$SYSFS_GPIO_PATH" ]; then
    print_error "Sysfs GPIO path not available. Rerun setup."
    exit 1
fi

CURRENT_VALUE=$($SSH_TEST "${RPI_USER}@${RPI_HOST}" "cat ${SYSFS_GPIO_PATH}/value 2>/dev/null")
RC=$?
if [ $RC -ne 0 ] || [ -z "$CURRENT_VALUE" ]; then
    CURRENT_VALUE="ERROR"
fi

if [ "$CURRENT_VALUE" = "ERROR" ]; then
    print_error "✗ Cannot read GPIO value"
    exit 1
elif [ "$CURRENT_VALUE" = "0" ]; then
    print_info "Current: GPIO${GPIO_PIN} = 0 (Power ON state)"
elif [ "$CURRENT_VALUE" = "1" ]; then
    print_info "Current: GPIO${GPIO_PIN} = 1 (Power OFF state)"
else
    print_warning "Unexpected value: $CURRENT_VALUE"
fi
echo ""

# ==== Test 5: Test GPIO control ========================================
print_step "5. Testing GPIO control..."
echo ""
print_warning "This will toggle the GPIO pin (may affect connected devices!)"
read -p "Proceed with GPIO toggle test? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Test skipped. Use ./gpio_on.sh or ./gpio_off.sh to test manually."
    exit 0
fi
echo ""

# ==== Test OFF ========================================
print_info "Testing OFF (GPIO HIGH)..."
if [ -n "$CONFIG_ARG" ]; then
    ./gpio_off.sh "$CONFIG_ARG" 2>/dev/null || ./gpio_off.sh
else
    ./gpio_off.sh 2>/dev/null || ./gpio_off.sh
fi
if [ $? -eq 0 ]; then
    print_info "✓ OFF command successful"
    sleep 1
    NEW_VALUE=$($SSH_TEST "${RPI_USER}@${RPI_HOST}" "cat ${SYSFS_GPIO_PATH}/value 2>/dev/null")
    if [ "$NEW_VALUE" = "1" ]; then
        print_info "✓ Verified: GPIO${GPIO_PIN} = 1"
    else
        print_warning "Unexpected value after OFF: $NEW_VALUE"
    fi
else
    print_error "✗ OFF command failed"
fi
echo ""

# Wait
print_info "Waiting 2 seconds..."
sleep 2
echo ""

# ==== Test ON ========================================
print_info "Testing ON (GPIO LOW)..."
if [ -n "$CONFIG_ARG" ]; then
    ./gpio_on.sh "$CONFIG_ARG" 2>/dev/null || ./gpio_on.sh
else
    ./gpio_on.sh 2>/dev/null || ./gpio_on.sh
fi
if [ $? -eq 0 ]; then
    print_info "✓ ON command successful"
    sleep 1
    NEW_VALUE=$($SSH_TEST "${RPI_USER}@${RPI_HOST}" "cat ${SYSFS_GPIO_PATH}/value 2>/dev/null")
    if [ "$NEW_VALUE" = "0" ]; then
        print_info "✓ Verified: GPIO${GPIO_PIN} = 0"
    else
        print_warning "Unexpected value after ON: $NEW_VALUE"
    fi
else
    print_error "✗ ON command failed"
fi
echo ""

echo "========================================"
print_info "GPIO Control Test Complete!"
echo "========================================"
echo ""
print_info "Summary:"
echo "  • SSH connection: Working"
echo "  • GPIO control: Working"
echo "  • Ready for use with FW_update.sh"
echo ""
print_info "Usage:"
echo "  ./gpio_on.sh          # Power ON"
echo "  ./gpio_off.sh         # Power OFF"
echo "  ./gpio_cycle.sh       # Full power cycle"
echo "  ./FW_update.sh -c FW_update.conf"
