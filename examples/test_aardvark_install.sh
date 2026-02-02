#!/bin/bash

#==============================================================================
# Aardvark Installation Test Script
# Verifies that Aardvark GPIO support is properly installed and functional
#==============================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_section() { echo -e "\n${CYAN}==== $1 ====${NC}"; }

ERRORS=0
WARNINGS=0

print_section "Aardvark Installation Test"

# Test 1: Check Python 3
print_section "Checking Python Installation"
if command -v python3 >/dev/null 2>&1; then
    VERSION=$(python3 --version)
    print_info "Python 3 found: $VERSION"
else
    print_error "Python 3 not found"
    ERRORS=$((ERRORS + 1))
fi

# Test 2: Check aardvark_py module
print_section "Checking Aardvark Python Module"
if python3 -c "import aardvark_py" 2>/dev/null; then
    print_info "aardvark_py module is installed"
    VERSION=$(python3 -c "import aardvark_py as aa; v=aa.aa_version(0); print(f'{v[0]}.{v[1]}')" 2>/dev/null || echo "unknown")
    print_info "API Version: $VERSION"
else
    print_error "aardvark_py module not found"
    print_warning "Install with: pip3 install aardvark_py"
    print_warning "Or download from: https://www.totalphase.com/products/aardvark-i2cspi/"
    ERRORS=$((ERRORS + 1))
fi

# Test 3: Check for Aardvark device
print_section "Checking Aardvark Hardware"
if command -v lsusb >/dev/null 2>&1; then
    if lsusb | grep -q "Total Phase"; then
        DEVICE=$(lsusb | grep "Total Phase")
        print_info "Aardvark device found:"
        echo "    $DEVICE"
    else
        print_warning "No Aardvark device detected via USB"
        print_warning "Connect Aardvark and try again"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_warning "lsusb not available, cannot check USB devices"
    WARNINGS=$((WARNINGS + 1))
fi

# Test 4: Check file permissions
print_section "Checking File Permissions"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS=(
    "aardvark_gpio.py"
    "gpio_on_aardvark.sh"
    "gpio_off_aardvark.sh"
    "gpio_cycle_aardvark.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -f "${SCRIPT_DIR}/${script}" ]; then
        if [ -x "${SCRIPT_DIR}/${script}" ]; then
            print_info "${script} is executable"
        else
            print_warning "${script} is not executable"
            print_warning "Run: chmod +x ${script}"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        print_error "${script} not found"
        ERRORS=$((ERRORS + 1))
    fi
done

# Test 5: Check configuration
print_section "Checking Configuration"
if [ -f "${SCRIPT_DIR}/plp.conf" ]; then
    print_info "Configuration file found"
    
    # Check for GPIO_MODE
    if grep -q "^GPIO_MODE=" "${SCRIPT_DIR}/plp.conf"; then
        MODE=$(grep "^GPIO_MODE=" "${SCRIPT_DIR}/plp.conf" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
        print_info "GPIO_MODE is configured: $MODE"
    else
        print_warning "GPIO_MODE not found in plp.conf"
        print_warning "Add: GPIO_MODE=\"aardvark\" to use Aardvark mode"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    # Check for Aardvark settings
    if grep -q "^AARDVARK_PORT=" "${SCRIPT_DIR}/plp.conf"; then
        print_info "Aardvark configuration found in plp.conf"
    else
        print_warning "Aardvark configuration not found in plp.conf"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_error "plp.conf not found"
    ERRORS=$((ERRORS + 1))
fi

# Test 6: Check documentation
print_section "Checking Documentation"
DOCS=(
    "AARDVARK_SETUP.md"
    "AARDVARK_QUICKREF.md"
    "CHANGES.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "${SCRIPT_DIR}/${doc}" ]; then
        print_info "${doc} found"
    else
        print_warning "${doc} not found"
        WARNINGS=$((WARNINGS + 1))
    fi
done

# Test 7: Test Python module loading (if hardware available)
print_section "Testing Python Module"
if python3 -c "import aardvark_py" 2>/dev/null; then
    TEST_OUTPUT=$(python3 "${SCRIPT_DIR}/aardvark_gpio.py" --help 2>&1)
    if echo "$TEST_OUTPUT" | grep -q "Control GPIO on TotalPhase Aardvark"; then
        print_info "Python module help works correctly"
    else
        print_error "Python module help failed"
        ERRORS=$((ERRORS + 1))
    fi
    
    # Try to detect devices (won't fail if no hardware)
    DEVICE_TEST=$(python3 -c "
import aardvark_py as aa
import sys
try:
    (num, ports, ids) = aa.aa_find_devices_ext(16, 16)
    print(f'{num} device(s) found')
    sys.exit(0)
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
" 2>&1)
    
    if [[ "$DEVICE_TEST" == *"device(s) found"* ]]; then
        print_info "Device detection works: $DEVICE_TEST"
    else
        print_warning "Device detection issue (may be OK if no hardware connected)"
        print_warning "Details: $DEVICE_TEST"
    fi
fi

# Test 8: Check unified script integration
print_section "Checking Unified Script Integration"
UNIFIED_SCRIPTS=(
    "gpio_on.sh"
    "gpio_off.sh"
    "gpio_cycle.sh"
)

for script in "${UNIFIED_SCRIPTS[@]}"; do
    if [ -f "${SCRIPT_DIR}/${script}" ]; then
        if grep -q "GPIO_MODE" "${SCRIPT_DIR}/${script}"; then
            print_info "${script} has GPIO_MODE support"
        else
            print_error "${script} missing GPIO_MODE support"
            ERRORS=$((ERRORS + 1))
        fi
    else
        print_error "${script} not found"
        ERRORS=$((ERRORS + 1))
    fi
done

# Summary
print_section "Test Summary"
echo ""
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    print_info "All tests passed! Aardvark support is properly installed."
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  1. Connect your Aardvark device via USB"
    echo "  2. Set GPIO_MODE=\"aardvark\" in plp.conf"
    echo "  3. Configure AARDVARK_PORT and AARDVARK_GPIO_PIN"
    echo "  4. Run: ./gpio_on.sh -c plp.conf"
    echo ""
    echo "See AARDVARK_SETUP.md for detailed instructions"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    print_warning "$WARNINGS warning(s) found - system should work but review warnings above"
    echo ""
    echo "See AARDVARK_SETUP.md for troubleshooting"
    exit 0
else
    print_error "$ERRORS error(s) and $WARNINGS warning(s) found"
    echo ""
    echo -e "${RED}Please fix the errors above before using Aardvark mode${NC}"
    echo ""
    echo "Common fixes:"
    echo "  - Install Python 3: sudo apt-get install python3"
    echo "  - Install aardvark_py: pip3 install aardvark_py"
    echo "  - Make scripts executable: chmod +x *.sh *.py"
    echo "  - Connect Aardvark device via USB"
    echo ""
    echo "See AARDVARK_SETUP.md for detailed troubleshooting"
    exit 1
fi
