# NVMe Firmware Testing with Dual GPIO Control

NVMe firmware update testing framework with power cycle capabilities using **Raspberry Pi** or **TotalPhase Aardvark** GPIO control.

## 🚀 Quick Start

```bash
# 1. Choose GPIO mode in plp.conf
GPIO_MODE="aardvark"   # or "rpi"

# 2. Run power control
./gpio_on.sh -c plp.conf      # Power ON
./gpio_off.sh -c plp.conf     # Power OFF
./gpio_cycle.sh -c plp.conf   # Power cycle

# 3. Test your setup
./tests/test_led_visual.sh aardvark
```

## 📁 Directory Structure

```
├── gpio_on.sh, gpio_off.sh, gpio_cycle.sh    # Main GPIO scripts (unified)
├── FW_update.sh                               # Firmware update with PLP testing
├── plp.conf                                   # Configuration file
├── lib/
│   └── aardvark_gpio.py                      # Aardvark GPIO library
├── scripts/
│   ├── rpi/                                  # RPI-specific scripts
│   └── aardvark/                             # Aardvark-specific scripts
├── tests/
│   ├── test_led_visual.sh                    # Interactive LED verification
│   └── test_gpio_transports.sh               # Automated mode comparison
└── docs/
    ├── AARDVARK_SETUP.md                     # Aardvark setup guide
    ├── GPIO_LOGIC_COMPARISON.md              # Logic reference
    └── QUICK_START.md                        # Command quick reference
```

## ⚙️ Configuration (`plp.conf`)

```bash
# GPIO Mode Selection
GPIO_MODE="aardvark"              # or "rpi"

# Aardvark Settings
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"

# Raspberry Pi Settings
RPI_HOST="192.168.0.40"
RPI_USER="pi"
RPI_GPIO_PIN="23"
RPI_SSH_PASS="password"

# NVMe Settings
NVME_DEVICE="/dev/nvme0n1"
```

## 🎯 GPIO Logic (Both Modes Identical)

```
gpio_on.sh  → GPIO LOW  → Power ON  → LED ON
gpio_off.sh → GPIO HIGH → Power OFF → LED OFF
```

## 🔧 Installation

### Aardvark Mode
```bash
pip3 install aardvark_py
python3 lib/aardvark_gpio.py --port 0 --pin 0 --get
```

### Raspberry Pi Mode
```bash
sudo apt-get install sshpass
ssh pi@<RPI_IP>
```

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [AARDVARK_SETUP.md](docs/AARDVARK_SETUP.md) | Complete Aardvark setup and troubleshooting |
| [GPIO_LOGIC_COMPARISON.md](docs/GPIO_LOGIC_COMPARISON.md) | Logic convention and mode comparison |
| [QUICK_START.md](docs/QUICK_START.md) | Command reference |
| [README_OLD.md](docs/README_OLD.md) | Original detailed documentation |

## 🧪 Testing

```bash
# Visual LED test
./tests/test_led_visual.sh aardvark
./tests/test_led_visual.sh rpi

# Automated comparison
./tests/test_gpio_transports.sh -c plp.conf
./tests/test_gpio_transports.sh -m aardvark -s
```

## 💡 Usage Examples

### Switch Between Modes
```bash
# Temporary override
GPIO_MODE="aardvark" ./gpio_on.sh -c plp.conf
GPIO_MODE="rpi" ./gpio_on.sh -c plp.conf

# Or edit plp.conf
GPIO_MODE="aardvark"
```

### Direct Aardvark Control
```bash
python3 lib/aardvark_gpio.py --port 0 --pin 0 --low   # ON
python3 lib/aardvark_gpio.py --port 0 --pin 0 --high  # OFF
python3 lib/aardvark_gpio.py --port 0 --pin 0 --cycle # Cycle
```

### Firmware Testing with PLP
```bash
# Configure PLP testing in plp.conf
PLP_SIMULATION="rpi4"      # or "no", "software"
PLP_PROBABILITY="100"

# Run firmware update test
./FW_update.sh -c plp.conf
```

## 🔄 Mode Comparison

| Feature | Raspberry Pi | Aardvark |
|---------|-------------|----------|
| **Connection** | SSH/Network | USB Direct |
| **Speed** | Slower | Faster |
| **Setup** | Complex | Simple |
| **Cost** | ~$40 | ~$300 |
| **Remote** | Yes | No |

## 🐛 Troubleshooting

### LED behavior is inverted
→ Check relay type (active-HIGH vs active-LOW)  
→ See [GPIO_LOGIC_COMPARISON.md](docs/GPIO_LOGIC_COMPARISON.md)

### Aardvark not found
```bash
lsusb | grep "Total Phase"
python3 -c "import aardvark_py; print('OK')"
```

### RPI connection fails
```bash
ping <RPI_IP>
ssh pi@<RPI_IP>
```

### Different behavior between modes
```bash
./tests/test_gpio_transports.sh -c plp.conf
```

## ✅ Verification Checklist

- [ ] LED ON when running `./gpio_on.sh -c plp.conf`
- [ ] LED OFF when running `./gpio_off.sh -c plp.conf`
- [ ] Device powers on successfully
- [ ] Device detected after power cycle
- [ ] Both RPI and Aardvark behave identically

## 📝 License

NVMe firmware testing and validation framework.
