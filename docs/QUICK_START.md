# Quick Start Guide

## Overview

This project supports GPIO control for NVMe power cycling using:
- **Raspberry Pi** (via SSH)
- **TotalPhase Aardvark** (via USB)

## 🚀 Quick Start

### 1. Configure
```bash
# Edit configuration
nano plp.conf

# Set GPIO mode
GPIO_MODE="aardvark"    # or "rpi"
```

### 2. Install Dependencies (Aardvark only)
```bash
pip3 install aardvark_py
```

### 3. Test
```bash
# Test GPIO control
python3 lib/aardvark_gpio.py --port 0 --pin 0 --get

# Power cycle
./gpio_cycle.sh -c plp.conf
```

## 📁 Key Files

| File | Purpose |
|------|---------|
| `plp.conf` | Configuration file |
| `gpio_on.sh` | Power ON |
| `gpio_off.sh` | Power OFF |
| `gpio_cycle.sh` | Power cycle |
| `lib/aardvark_gpio.py` | Aardvark library |

## 📚 Documentation

- **Setup:** [docs/AARDVARK_SETUP.md](docs/AARDVARK_SETUP.md)
- **Quick Ref:** [docs/AARDVARK_QUICKREF.md](docs/AARDVARK_QUICKREF.md)
- **Structure:** [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)

## 🔧 Common Commands

```bash
# Power ON
./gpio_on.sh -c plp.conf

# Power OFF
./gpio_off.sh -c plp.conf

# Power cycle (2 sec off)
./gpio_cycle.sh -c plp.conf 2000

# Check GPIO state
python3 lib/aardvark_gpio.py --port 0 --pin 0 --get
```

## 🎯 Mode Selection

Edit `plp.conf`:

**For Aardvark:**
```bash
GPIO_MODE="aardvark"
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"
```

**For Raspberry Pi:**
```bash
GPIO_MODE="rpi"
RPI_HOST="192.168.0.40"
RPI_GPIO_PIN="23"
```

## ✅ Verification

```bash
# Test Aardvark connection
python3 lib/aardvark_gpio.py --port 0 --pin 0 --get

# Toggle GPIO
python3 lib/aardvark_gpio.py --port 0 --pin 0 --high
sleep 1
python3 lib/aardvark_gpio.py --port 0 --pin 0 --low
```

## 🆘 Troubleshooting

**Aardvark not found:**
```bash
lsusb | grep "Total Phase"
pip3 install aardvark_py
```

**GPIO not switching:**
```bash
# Check with verbose output
python3 lib/aardvark_gpio.py --port 0 --pin 0 --get
```

**Permission denied:**
```bash
sudo usermod -a -G dialout $USER
# Logout and login again
```

## 📖 Full Documentation

See [docs/AARDVARK_SETUP.md](docs/AARDVARK_SETUP.md) for complete setup instructions.
