# Aardvark GPIO Support - Setup Guide

## Overview

This project now supports **two GPIO control methods** for NVMe power cycle testing:

1. **Raspberry Pi GPIO** (via SSH) - Original method
2. **TotalPhase Aardvark I2C/SPI Adapter** (via USB) - New alternative

Both methods are fully supported and can be selected via configuration.

---

## Hardware Requirements

### Aardvark Setup

- **TotalPhase Aardvark I2C/SPI Host Adapter**
- USB connection to host computer
- Relay module connected to one of the Aardvark GPIO pins

### GPIO Pin Mapping

The Aardvark has 6 GPIO pins available:

| Pin # | Pin Name | Description |
|-------|----------|-------------|
| 0     | SCL      | I2C Clock (can be used as GPIO) |
| 1     | SDA      | I2C Data (can be used as GPIO) |
| 2     | MISO     | SPI Master In Slave Out |
| 3     | SCK      | SPI Clock |
| 4     | MOSI     | SPI Master Out Slave In |
| 5     | SS       | SPI Slave Select |

**Default:** Pin 0 (SCL) is used for GPIO control

---

## Software Installation

### 1. Install TotalPhase Aardvark Python API

Download and install the Aardvark Software API from TotalPhase:

```bash
# Download from: https://www.totalphase.com/products/aardvark-i2cspi/
# Or install via pip (if available)
pip3 install aardvark_py
```

### 2. Install Python Dependencies

```bash
# Ensure Python 3 is installed
python3 --version

# The project includes aardvark_gpio.py which uses the aardvark_py module
```

### 3. Verify Aardvark Connection

```bash
# List connected Aardvark devices
python3 aardvark_gpio.py --port 0 --pin 0 --get

# Expected output:
# [AARDVARK] Found 1 Aardvark device(s)
# [AARDVARK] Opened Aardvark adapter on port 0 (handle: 1)
# GPIO SCL is LOW
```

---

## Configuration

### Method 1: Using plp.conf (Recommended)

Edit the `plp.conf` file to set the GPIO mode:

```bash
# ============================================================================
# GPIO Control Mode Selection
# ============================================================================
# Choose GPIO control method: "rpi" or "aardvark"
GPIO_MODE="aardvark"

# ============================================================================
# Aardvark Configuration (for aardvark mode)
# ============================================================================
# Port number (0 for first device, 1 for second, etc.)
AARDVARK_PORT="0"

# GPIO pin number (0-5) or name (SCL, SDA, MISO, SCK, MOSI, SS)
AARDVARK_GPIO_PIN="0"

# Power-off duration in milliseconds
AARDVARK_POWER_OFF_MS="2000"
```

### Method 2: Environment Variables

```bash
export GPIO_MODE="aardvark"
export AARDVARK_PORT="0"
export AARDVARK_GPIO_PIN="0"
export AARDVARK_POWER_OFF_MS="2000"
```

---

## Usage

### Unified Scripts (Automatic Mode Detection)

The main GPIO scripts automatically detect the mode from configuration:

```bash
# Power ON (uses mode from plp.conf)
./gpio_on.sh -c plp.conf

# Power OFF (uses mode from plp.conf)
./gpio_off.sh -c plp.conf

# Power Cycle (uses mode from plp.conf)
./gpio_cycle.sh -c plp.conf 2000
```

### Direct Aardvark Scripts

Use these scripts to explicitly control Aardvark GPIO:

```bash
# Power ON
./gpio_on_aardvark.sh -c plp.conf

# Power OFF
./gpio_off_aardvark.sh -c plp.conf

# Power Cycle (2000ms off time)
./gpio_cycle_aardvark.sh -c plp.conf 2000
```

### Python Module Direct Usage

Control GPIO directly using Python:

```bash
# Set GPIO HIGH (~3.3V/5V)
python3 aardvark_gpio.py --port 0 --pin 0 --high

# Set GPIO LOW (~0V)
python3 aardvark_gpio.py --port 0 --pin 0 --low

# Read GPIO state
python3 aardvark_gpio.py --port 0 --pin 0 --get

# GPIO cycle (2000ms)
python3 aardvark_gpio.py --port 0 --pin 0 --cycle --duration 2000
```

---

## Hardware Wiring

### Aardvark to Relay Module

Connect the Aardvark GPIO pin to your relay module:

```
Aardvark Pin (SCL/Pin 0) → Relay Module Control Pin
Aardvark GND             → Relay Module GND
Relay Module VCC         → External Power Supply (if needed)
```

### GPIO Logic Levels (Direct Electrical Output)

- **GPIO HIGH** = Outputs ~3.3V/5V
- **GPIO LOW** = Outputs ~0V

The effect depends on your relay type:
- **Active-low relay**: LOW activates relay, HIGH deactivates
- **Active-high relay**: HIGH activates relay, LOW deactivates

---

## Switching Between Modes

### To Use Raspberry Pi GPIO:

```bash
# Edit plp.conf
GPIO_MODE="rpi"

# Or use environment variable
export GPIO_MODE="rpi"

# Then run scripts normally
./gpio_on.sh -c plp.conf
```

### To Use Aardvark:

```bash
# Edit plp.conf
GPIO_MODE="aardvark"

# Or use environment variable
export GPIO_MODE="aardvark"

# Then run scripts normally
./gpio_on.sh -c plp.conf
```

---

## Troubleshooting

### Issue: "aardvark_py module not found"

**Solution:**
```bash
pip3 install aardvark_py
# Or download from https://www.totalphase.com/products/aardvark-i2cspi/
```

### Issue: "No Aardvark adapters found"

**Solution:**
1. Check USB connection
2. Verify device permissions:
   ```bash
   lsusb | grep "Total Phase"
   # Should show: Bus XXX Device XXX: ID 1679:2001 Total Phase Aardvark I2C/SPI Host Adapter
   ```
3. Add udev rules (Linux):
   ```bash
   sudo vim /etc/udev/rules.d/99-totalphase.rules
   # Add: SUBSYSTEM=="usb", ATTR{idVendor}=="1679", MODE="0666"
   sudo udevadm control --reload-rules
   ```

### Issue: "Failed to open Aardvark on port 0"

**Solution:**
1. Device may be in use by another application
2. Try a different port number if multiple Aardvarks are connected
3. Reconnect the USB cable

### Issue: GPIO doesn't switch

**Solution:**
1. Verify wiring connections
2. Check relay module power supply
3. Test GPIO state:
   ```bash
   python3 aardvark_gpio.py --port 0 --pin 0 --get
   ```
4. Manually toggle GPIO:
   ```bash
   python3 aardvark_gpio.py --port 0 --pin 0 --high
   sleep 1
   python3 aardvark_gpio.py --port 0 --pin 0 --low
   ```

---

## Comparison: RPI vs Aardvark

| Feature | Raspberry Pi | Aardvark |
|---------|-------------|----------|
| Connection | SSH (Network) | USB (Direct) |
| Setup Complexity | Higher (requires RPi setup) | Lower (plug & play) |
| Speed | Slower (network latency) | Faster (direct USB) |
| Reliability | Network dependent | Hardware dependent |
| Cost | ~$35-45 + accessories | ~$300 |
| GPIO Pins | Many (40 pins) | Limited (6 pins) |
| Remote Control | Yes (via SSH) | No (must be local) |
| Multiple Devices | Requires multiple RPis | Can use multiple Aardvarks |

---

## Examples

### Example 1: Quick Test with Aardvark

```bash
# Configure for Aardvark mode
cat > test_aardvark.conf << EOF
GPIO_MODE="aardvark"
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"
NVME_DEVICE="/dev/nvme0n1"
EOF

# Power cycle
./gpio_cycle.sh -c test_aardvark.conf 2000
```

### Example 2: Switching Between Modes

```bash
# Test with Aardvark
./gpio_on.sh -c plp.conf  # Uses GPIO_MODE from plp.conf

# Temporarily test with RPI (override)
GPIO_MODE="rpi" ./gpio_on.sh -c plp.conf
```

### Example 3: Python Integration

```python
#!/usr/bin/env python3
from aardvark_gpio import AardvarkGPIO
import time

# Open Aardvark GPIO
with AardvarkGPIO(port=0, pin=0) as gpio:
    # Power cycle
    print("Powering OFF...")
    gpio.set_high()
    time.sleep(2)
    
    print("Powering ON...")
    gpio.set_low()
    time.sleep(5)
    
    print("Verifying state...")
    if not gpio.get_state():
        print("✓ Power is ON")
    else:
        print("✗ Power is OFF")
```

---

## File Structure

```
.
├── aardvark_gpio.py           # Python library for Aardvark GPIO control
├── gpio_on.sh                 # Unified power-on script (auto-detects mode)
├── gpio_off.sh                # Unified power-off script (auto-detects mode)
├── gpio_cycle.sh              # Unified power-cycle script (auto-detects mode)
├── gpio_on_aardvark.sh       # Direct Aardvark power-on script
├── gpio_off_aardvark.sh      # Direct Aardvark power-off script
├── gpio_cycle_aardvark.sh    # Direct Aardvark power-cycle script
├── gpio_setup.sh             # RPI GPIO setup script
├── plp.conf                   # Configuration file
└── AARDVARK_SETUP.md         # This documentation
```

---

## Support

For issues or questions:
- Aardvark Documentation: https://www.totalphase.com/products/aardvark-i2cspi/
- Python API Reference: https://www.totalphase.com/support/articles/200349176/
- Project Issues: (Add your issue tracker link here)
