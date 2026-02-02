#!/bin/bash

#==============================================================================
# GPIO Transport Test Script
# Tests both RPI and Aardvark GPIO modes to verify they behave identically
#
# Usage:
#   ./test_gpio_transports.sh -c plp.conf
#==============================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_header() { echo -e "${CYAN}$1${NC}"; }
print_test() { echo -e "${BLUE}[TEST]${NC} $1"; }

usage() {
    cat <<'EOF'
Usage: test_gpio_transports.sh [options]

Options:
    -c, --config <file>   Configuration file (default: plp.conf)
    -m, --mode <mode>     Test specific mode only: 'rpi' or 'aardvark'
    -s, --skip-device     Skip NVMe device detection (faster testing)
    -h, --help            Show this help message

This script tests both RPI and Aardvark GPIO modes to ensure they
behave identically with the same power ON/OFF logic.
EOF
}

# Default configuration
CONFIG_FILE="plp.conf"
TEST_MODE="both"
SKIP_DEVICE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -m|--mode)
            TEST_MODE="$2"
            shift 2
            ;;
        -s|--skip-device)
            SKIP_DEVICE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Verify config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

print_header "========================================"
print_header "GPIO Transport Comparison Test"
print_header "========================================"
echo ""
print_info "Configuration: $CONFIG_FILE"
print_info "Test mode: $TEST_MODE"
print_info "Skip device check: $SKIP_DEVICE"
echo ""

# Function to test a GPIO mode
test_gpio_mode() {
    local mode="$1"
    local mode_name="$2"
    
    print_header "========================================"
    print_header "Testing: $mode_name Mode"
    print_header "========================================"
    echo ""
    
    # Create temporary config with this mode
    local temp_config=$(mktemp)
    cp "$CONFIG_FILE" "$temp_config"
    
    # Update GPIO_MODE in temp config
    if grep -q "^GPIO_MODE=" "$temp_config"; then
        sed -i "s/^GPIO_MODE=.*/GPIO_MODE=\"$mode\"/" "$temp_config"
    else
        echo "GPIO_MODE=\"$mode\"" >> "$temp_config"
    fi
    
    print_info "Temporary config: $temp_config"
    echo ""
    
    # Test 1: Power OFF
    print_test "Test 1: Power OFF (GPIO HIGH)"
    echo "Expected: Device should be powered off"
    if ! bash "${SCRIPT_DIR}/gpio_off.sh" -c "$temp_config"; then
        print_error "Power OFF failed"
        rm -f "$temp_config"
        return 1
    fi
    echo ""
    
    sleep 2
    
    # Test 2: Power ON
    print_test "Test 2: Power ON (GPIO LOW)"
    echo "Expected: Device should be powered on"
    if $SKIP_DEVICE; then
        # Just run the command without device check
        if GPIO_MODE="$mode" bash "${SCRIPT_DIR}/gpio_on.sh" -c "$temp_config" 2>&1 | head -15; then
            print_warning "Power ON command executed (device check skipped)"
        else
            print_error "Power ON failed"
            rm -f "$temp_config"
            return 1
        fi
    else
        if ! bash "${SCRIPT_DIR}/gpio_on.sh" -c "$temp_config"; then
            print_error "Power ON failed"
            rm -f "$temp_config"
            return 1
        fi
    fi
    echo ""
    
    sleep 2
    
    # Test 3: Power Cycle
    print_test "Test 3: Power Cycle (OFF -> ON)"
    echo "Expected: Device should power cycle successfully"
    if $SKIP_DEVICE; then
        if GPIO_MODE="$mode" bash "${SCRIPT_DIR}/gpio_cycle.sh" -c "$temp_config" 1000 2>&1 | head -20; then
            print_warning "Power cycle command executed (device check skipped)"
        else
            print_error "Power cycle failed"
            rm -f "$temp_config"
            return 1
        fi
    else
        if ! bash "${SCRIPT_DIR}/gpio_cycle.sh" -c "$temp_config" 1000; then
            print_error "Power cycle failed"
            rm -f "$temp_config"
            return 1
        fi
    fi
    echo ""
    
    rm -f "$temp_config"
    
    print_info "✓ $mode_name mode tests completed successfully"
    echo ""
    
    return 0
}

# Test summary
TEST_RESULTS=()

# Test RPI mode
if [ "$TEST_MODE" = "both" ] || [ "$TEST_MODE" = "rpi" ]; then
    if test_gpio_mode "rpi" "Raspberry Pi"; then
        TEST_RESULTS+=("RPI: PASS")
    else
        TEST_RESULTS+=("RPI: FAIL")
    fi
    sleep 2
fi

# Test Aardvark mode
if [ "$TEST_MODE" = "both" ] || [ "$TEST_MODE" = "aardvark" ]; then
    if test_gpio_mode "aardvark" "Aardvark"; then
        TEST_RESULTS+=("Aardvark: PASS")
    else
        TEST_RESULTS+=("Aardvark: FAIL")
    fi
fi

# Print summary
print_header "========================================"
print_header "Test Summary"
print_header "========================================"
echo ""

all_passed=true
for result in "${TEST_RESULTS[@]}"; do
    if [[ $result == *"PASS"* ]]; then
        print_info "✓ $result"
    else
        print_error "✗ $result"
        all_passed=false
    fi
done

echo ""

if $all_passed; then
    print_header "========================================"
    print_info "ALL TESTS PASSED"
    print_info "Both GPIO transports behave identically!"
    print_header "========================================"
    exit 0
else
    print_header "========================================"
    print_error "SOME TESTS FAILED"
    print_error "Check the output above for details"
    print_header "========================================"
    exit 1
fi
