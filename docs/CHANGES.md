# GPIO Control Mode Implementation Summary

## What Was Added

This project has been enhanced to support **TotalPhase Aardvark** as an alternative to Raspberry Pi for GPIO control, while maintaining full backward compatibility with existing RPI scripts.

---

## New Files Created

### 1. Python Library
- **`aardvark_gpio.py`** - Core Python library for Aardvark GPIO control
  - Supports all 6 GPIO pins (SCL, SDA, MISO, SCK, MOSI, SS)
  - Command-line interface for direct control
  - Context manager support
  - Compatible with TotalPhase Aardvark Python API

### 2. Aardvark Shell Scripts
- **`gpio_on_aardvark.sh`** - Power ON using Aardvark GPIO
- **`gpio_off_aardvark.sh`** - Power OFF using Aardvark GPIO
- **`gpio_cycle_aardvark.sh`** - Power cycle using Aardvark GPIO

### 3. Documentation
- **`AARDVARK_SETUP.md`** - Complete setup guide and documentation
- **`AARDVARK_QUICKREF.md`** - Quick reference guide for common operations

---

## Modified Files

### 1. Configuration File: `plp.conf`
**Added:**
```bash
# GPIO Mode Selection
GPIO_MODE="rpi"  # or "aardvark"

# Aardvark Configuration
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"
AARDVARK_POWER_OFF_MS="2000"
```

### 2. Existing GPIO Scripts
Modified to support both modes with automatic detection:
- **`gpio_on.sh`** - Now detects mode and forwards to appropriate implementation
- **`gpio_off.sh`** - Now detects mode and forwards to appropriate implementation
- **`gpio_cycle.sh`** - Now detects mode and forwards to appropriate implementation

**Changes:**
- Added `GPIO_MODE` variable (default: "rpi")
- Added Aardvark configuration variables
- Added mode detection logic
- Added dispatcher to forward to Aardvark scripts when mode="aardvark"
- Maintained full backward compatibility

---

## Architecture

### Mode Detection Flow
```
User runs: ./gpio_on.sh -c plp.conf
           ↓
      Load configuration
           ↓
   Check GPIO_MODE value
           ↓
    ┌──────┴──────┐
    ↓             ↓
  "rpi"      "aardvark"
    ↓             ↓
RPI GPIO    Aardvark GPIO
 (SSH)         (USB)
```

### File Organization
```
Original Scripts (Modified)
├── gpio_on.sh       → Dispatcher script
├── gpio_off.sh      → Dispatcher script
└── gpio_cycle.sh    → Dispatcher script

New Aardvark Scripts
├── gpio_on_aardvark.sh       → Aardvark power ON
├── gpio_off_aardvark.sh      → Aardvark power OFF
├── gpio_cycle_aardvark.sh    → Aardvark power cycle
└── aardvark_gpio.py          → Core library

Configuration
└── plp.conf                   → Enhanced with GPIO_MODE

Documentation
├── AARDVARK_SETUP.md         → Full setup guide
└── AARDVARK_QUICKREF.md      → Quick reference
```

---

## Key Features

### 1. Backward Compatibility
✓ All existing RPI scripts continue to work unchanged
✓ Default mode is "rpi" if GPIO_MODE is not specified
✓ Existing configuration files work without modification

### 2. Mode Selection
- **Configuration file**: Set `GPIO_MODE="aardvark"` in plp.conf
- **Environment variable**: `export GPIO_MODE="aardvark"`
- **Inline override**: `GPIO_MODE="aardvark" ./gpio_on.sh`

### 3. Feature Parity
Both modes support:
- Power ON (GPIO LOW)
- Power OFF (GPIO HIGH)
- Power Cycle with configurable duration
- PCIe device detection and verification
- Configuration file support
- Command-line options

### 4. Unified Interface
```bash
# Same commands work for both modes
./gpio_on.sh -c plp.conf      # Uses mode from config
./gpio_off.sh -c plp.conf     # Uses mode from config
./gpio_cycle.sh -c plp.conf   # Uses mode from config
```

---

## Configuration Options

### RPI Mode (Original)
```bash
GPIO_MODE="rpi"
RPI_HOST="192.168.0.40"
RPI_USER="pi"
RPI_GPIO_PIN="23"
RPI_SSH_PORT="22"
RPI_POWER_OFF_MS="2000"
RPI_SSH_PASS="rpi12345"
```

### Aardvark Mode (New)
```bash
GPIO_MODE="aardvark"
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"
AARDVARK_POWER_OFF_MS="2000"
```

---

## Usage Examples

### Using RPI Mode (Default)
```bash
# No changes needed - existing scripts work as before
./gpio_on.sh -c plp.conf
```

### Using Aardvark Mode
```bash
# Method 1: Change plp.conf
GPIO_MODE="aardvark"

# Method 2: Environment variable
export GPIO_MODE="aardvark"
./gpio_on.sh -c plp.conf

# Method 3: Direct Aardvark script
./gpio_on_aardvark.sh -c plp.conf
```

### Python Direct Control
```bash
# Power ON
python3 aardvark_gpio.py --port 0 --pin 0 --low

# Power OFF
python3 aardvark_gpio.py --port 0 --pin 0 --high

# Power Cycle
python3 aardvark_gpio.py --port 0 --pin 0 --cycle --duration 2000
```

---

## Requirements

### For RPI Mode (Existing)
- Raspberry Pi with GPIO access
- SSH connectivity
- Optional: sshpass for password authentication

### For Aardvark Mode (New)
- TotalPhase Aardvark I2C/SPI Host Adapter
- Python 3
- `aardvark_py` Python module
- USB connection to host

---

## Installation for Aardvark

```bash
# 1. Install Python library
pip3 install aardvark_py

# 2. Make scripts executable
chmod +x gpio_*_aardvark.sh aardvark_gpio.py

# 3. Configure mode in plp.conf
GPIO_MODE="aardvark"
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"

# 4. Test connection
python3 aardvark_gpio.py --port 0 --pin 0 --get
```

---

## Benefits

### Flexibility
- Choose the GPIO control method that best fits your setup
- Switch between modes without changing scripts
- Use both modes in the same environment

### Reliability
- USB direct connection (Aardvark) vs network SSH (RPI)
- No network dependency for Aardvark
- Faster response time with Aardvark

### Ease of Use
- Simple mode selection via configuration
- Unified script interface
- No need to learn different commands

---

## Testing

### Quick Test Sequence
```bash
# 1. Verify Aardvark connection
python3 aardvark_gpio.py --port 0 --pin 0 --get

# 2. Test power OFF
./gpio_off_aardvark.sh

# 3. Test power ON
./gpio_on_aardvark.sh

# 4. Test power cycle
./gpio_cycle_aardvark.sh -c plp.conf 2000
```

### Mode Switching Test
```bash
# Test RPI mode
GPIO_MODE="rpi" ./gpio_on.sh -c plp.conf

# Test Aardvark mode
GPIO_MODE="aardvark" ./gpio_on.sh -c plp.conf
```

---

## Support and Documentation

- **Setup Guide**: See [AARDVARK_SETUP.md](AARDVARK_SETUP.md)
- **Quick Reference**: See [AARDVARK_QUICKREF.md](AARDVARK_QUICKREF.md)
- **TotalPhase Docs**: https://www.totalphase.com/products/aardvark-i2cspi/

---

## Summary

✓ **Backward Compatible** - All existing RPI scripts work unchanged
✓ **Flexible** - Easy switching between RPI and Aardvark modes
✓ **Well Documented** - Complete setup guides and examples
✓ **Feature Complete** - Full parity between RPI and Aardvark modes
✓ **Easy to Use** - Unified interface for both modes
