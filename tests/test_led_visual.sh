#!/bin/bash

#==============================================================================
# LED Visual Test Script
# Simple test to visually verify GPIO control with LED indicators
#
# Usage:
#   ./test_led_visual.sh aardvark
#   ./test_led_visual.sh rpi
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
print_prompt() { echo -e "${CYAN}[PROMPT]${NC} $1"; }

usage() {
    cat <<'EOF'
Usage: test_led_visual.sh <mode>

Arguments:
    mode    GPIO mode to test: 'aardvark' or 'rpi'

This script performs visual LED tests to verify GPIO control.
Connect an LED to the GPIO pin to see the effects.

LED Behavior (with relay/proper wiring):
  - Power ON  (set_low)  → LED should turn ON/light up
  - Power OFF (set_high) → LED should turn OFF/go dark
EOF
}

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

MODE="$1"

if [ "$MODE" != "aardvark" ] && [ "$MODE" != "rpi" ]; then
    print_error "Invalid mode: $MODE"
    usage
    exit 1
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

print_info "========================================"
print_info "LED Visual Test - $MODE Mode"
print_info "========================================"
echo ""
print_info "This test will cycle the LED ON and OFF"
print_info "Watch your LED indicator to verify correct operation"
echo ""

# Create test config
TEST_CONFIG=$(mktemp)
if [ -f "plp.conf" ]; then
    cp plp.conf "$TEST_CONFIG"
else
    cat > "$TEST_CONFIG" <<EOF
GPIO_MODE="$MODE"
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"
RPI_HOST="192.168.0.40"
RPI_USER="pi"
RPI_GPIO_PIN="23"
RPI_SSH_PASS="rpi12345"
NVME_DEVICE="/dev/nvme0n1"
EOF
fi

# Update mode in config
sed -i "s/^GPIO_MODE=.*/GPIO_MODE=\"$MODE\"/" "$TEST_CONFIG"

read -p "Press ENTER to start the test..."
echo ""

# Test sequence
print_info "Step 1: Setting GPIO LOW (Power ON)"
print_prompt "→ LED should turn ON / light up"
echo ""

if [ "$MODE" = "aardvark" ]; then
    python3 "${SCRIPT_DIR}/lib/aardvark_gpio.py" --port 0 --pin 0 --low
else
    GPIO_MODE="rpi" bash "${SCRIPT_DIR}/gpio_on.sh" -c "$TEST_CONFIG" 2>&1 | head -15
fi

echo ""
read -p "Did the LED turn ON? (y/n): " response1
echo ""

sleep 2

print_info "Step 2: Setting GPIO HIGH (Power OFF)"
print_prompt "→ LED should turn OFF / go dark"
echo ""

if [ "$MODE" = "aardvark" ]; then
    python3 "${SCRIPT_DIR}/lib/aardvark_gpio.py" --port 0 --pin 0 --high
else
    GPIO_MODE="rpi" bash "${SCRIPT_DIR}/gpio_off.sh" -c "$TEST_CONFIG" 2>&1 | head -15
fi

echo ""
read -p "Did the LED turn OFF? (y/n): " response2
echo ""

sleep 2

print_info "Step 3: Rapid toggle test (5 cycles)"
print_prompt "→ LED should blink ON/OFF rapidly"
echo ""

for i in {1..5}; do
    printf "Cycle $i: ON  -> "
    if [ "$MODE" = "aardvark" ]; then
        python3 "${SCRIPT_DIR}/lib/aardvark_gpio.py" --port 0 --pin 0 --low -q 2>/dev/null && echo "✓" || echo "✗"
    else
        if GPIO_MODE="$MODE" bash "${SCRIPT_DIR}/gpio_on.sh" -c "$TEST_CONFIG" >/dev/null 2>&1; then
            echo "✓"
        else
            echo "✗"
        fi
    fi
    sleep 0.5
    
    printf "Cycle $i: OFF -> "
    if [ "$MODE" = "aardvark" ]; then
        python3 "${SCRIPT_DIR}/lib/aardvark_gpio.py" --port 0 --pin 0 --high -q 2>/dev/null && echo "✓" || echo "✗"
    else
        if GPIO_MODE="$MODE" bash "${SCRIPT_DIR}/gpio_off.sh" -c "$TEST_CONFIG" >/dev/null 2>&1; then
            echo "✓"
        else
            echo "✗"
        fi
    fi
    sleep 0.5
done

echo ""
read -p "Did the LED blink 5 times? (y/n): " response3
echo ""

# Cleanup
rm -f "$TEST_CONFIG"

# Summary
print_info "========================================"
print_info "Test Results Summary - $MODE Mode"
print_info "========================================"
echo ""

all_pass=true

if [[ $response1 =~ ^[Yy] ]]; then
    print_info "✓ LED ON test: PASS"
else
    print_error "✗ LED ON test: FAIL"
    all_pass=false
fi

if [[ $response2 =~ ^[Yy] ]]; then
    print_info "✓ LED OFF test: PASS"
else
    print_error "✗ LED OFF test: FAIL"
    all_pass=false
fi

if [[ $response3 =~ ^[Yy] ]]; then
    print_info "✓ LED blink test: PASS"
else
    print_error "✗ LED blink test: FAIL"
    all_pass=false
fi

echo ""

if $all_pass; then
    print_info "========================================"
    print_info "ALL TESTS PASSED!"
    print_info "$MODE mode is working correctly"
    print_info "========================================"
    exit 0
else
    print_error "========================================"
    print_error "SOME TESTS FAILED"
    print_error "Check your wiring and configuration"
    print_error "========================================"
    exit 1
fi
