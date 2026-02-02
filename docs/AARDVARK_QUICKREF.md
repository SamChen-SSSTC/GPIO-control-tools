# Aardvark GPIO Quick Reference

## Quick Start

### 1. Install Aardvark Python Library
```bash
pip3 install aardvark_py
```

### 2. Configure Mode in plp.conf
```bash
GPIO_MODE="aardvark"
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"
```

### 3. Run Scripts
```bash
./gpio_on.sh -c plp.conf      # Power ON
./gpio_off.sh -c plp.conf     # Power OFF
./gpio_cycle.sh -c plp.conf   # Power Cycle
```

## Command Reference

### Python Module Commands
```bash
# Power ON (GPIO LOW)
python3 aardvark_gpio.py --port 0 --pin 0 --low

# Power OFF (GPIO HIGH)
python3 aardvark_gpio.py --port 0 --pin 0 --high

# Check GPIO state
python3 aardvark_gpio.py --port 0 --pin 0 --get

# Power cycle (2 seconds off)
python3 aardvark_gpio.py --port 0 --pin 0 --cycle --duration 2000
```

### Shell Script Commands
```bash
# Using unified scripts (auto-detects mode from config)
./gpio_on.sh -c plp.conf
./gpio_off.sh -c plp.conf
./gpio_cycle.sh -c plp.conf 2000

# Using direct Aardvark scripts
./gpio_on_aardvark.sh -c plp.conf
./gpio_off_aardvark.sh -c plp.conf
./gpio_cycle_aardvark.sh -c plp.conf 2000

# Override mode temporarily
GPIO_MODE="aardvark" ./gpio_on.sh
```

## GPIO Pin Options

| Pin # | Name | Use as GPIO |
|-------|------|-------------|
| 0     | SCL  | ✓ Default   |
| 1     | SDA  | ✓           |
| 2     | MISO | ✓           |
| 3     | SCK  | ✓           |
| 4     | MOSI | ✓           |
| 5     | SS   | ✓           |

## Configuration Variables

```bash
# Required
GPIO_MODE="aardvark"          # Select Aardvark mode
AARDVARK_PORT="0"             # Aardvark device port (0-based)
AARDVARK_GPIO_PIN="0"         # GPIO pin number (0-5)

# Optional
AARDVARK_POWER_OFF_MS="2000"  # Power-off duration (ms)
NVME_DEVICE="/dev/nvme0n1"    # NVMe device path
```

## Troubleshooting Quick Fixes

```bash
# Check Aardvark connection
lsusb | grep "Total Phase"

# Test Python module
python3 -c "import aardvark_py; print('OK')"

# Verify GPIO control
python3 aardvark_gpio.py --port 0 --pin 0 --get

# Add USB permissions (Linux)
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1679", MODE="0666"' | sudo tee /etc/udev/rules.d/99-totalphase.rules
sudo udevadm control --reload-rules
```

## Switch Between RPI and Aardvark

```bash
# Method 1: Edit plp.conf
# Change: GPIO_MODE="rpi" or GPIO_MODE="aardvark"

# Method 2: Environment variable
export GPIO_MODE="aardvark"  # Use Aardvark
export GPIO_MODE="rpi"        # Use RPI

# Method 3: Inline override
GPIO_MODE="aardvark" ./gpio_on.sh -c plp.conf
```

## GPIO Logic

- **HIGH (1)** = Power OFF (relay activated)
- **LOW (0)** = Power ON (relay deactivated)

This matches the Raspberry Pi GPIO behavior.
