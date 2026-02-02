# NVMe Firmware Update Testing - Project Structure

## Directory Layout

```
NVMe-FW-update-testing-main/
├── README.md                   # Main project documentation
├── plp.conf                    # Active configuration file
│
├── gpio_on.sh                  # Main power ON script (auto-detects mode)
├── gpio_off.sh                 # Main power OFF script (auto-detects mode)
├── gpio_cycle.sh               # Main power cycle script (auto-detects mode)
│
├── FW_update.sh                # Firmware update script
├── FWUpdate.sh                 # Firmware update script (alternative)
│
├── config/                     # Configuration files
│   └── plp.conf.example        # Example configuration template
│
├── lib/                        # Library files
│   └── aardvark_gpio.py        # Aardvark GPIO control Python library
│
├── scripts/                    # Implementation scripts
│   ├── aardvark/              # Aardvark-specific GPIO scripts
│   │   ├── gpio_on_aardvark.sh
│   │   ├── gpio_off_aardvark.sh
│   │   └── gpio_cycle_aardvark.sh
│   │
│   └── rpi/                   # Raspberry Pi scripts
│       ├── gpio_setup.sh      # RPI GPIO setup script
│       └── test_rpi_gpio.sh   # RPI GPIO test script
│
├── docs/                       # Documentation
│   ├── AARDVARK_SETUP.md      # Aardvark setup guide
│   ├── AARDVARK_QUICKREF.md   # Aardvark quick reference
│   └── CHANGES.md             # Change log and implementation summary
│
└── examples/                   # Example scripts and tests
    └── test_aardvark_install.sh # Aardvark installation test
```

## File Descriptions

### Main Scripts (Project Root)

| File | Description |
|------|-------------|
| `gpio_on.sh` | Unified power ON script - detects mode from config |
| `gpio_off.sh` | Unified power OFF script - detects mode from config |
| `gpio_cycle.sh` | Unified power cycle script - detects mode from config |
| `FW_update.sh` | NVMe firmware update script |
| `plp.conf` | Active configuration file (copy of config/plp.conf.example) |

### Configuration (`config/`)

| File | Description |
|------|-------------|
| `plp.conf.example` | Template configuration with all options documented |

**Note:** Copy `config/plp.conf.example` to `plp.conf` and customize for your setup.

### Library (`lib/`)

| File | Description |
|------|-------------|
| `aardvark_gpio.py` | Python library for TotalPhase Aardvark GPIO control |

**Features:**
- Command-line interface
- Python module for integration
- Supports all 6 GPIO pins
- Context manager support

### Aardvark Scripts (`scripts/aardvark/`)

| File | Description |
|------|-------------|
| `gpio_on_aardvark.sh` | Power ON using Aardvark |
| `gpio_off_aardvark.sh` | Power OFF using Aardvark |
| `gpio_cycle_aardvark.sh` | Power cycle using Aardvark |

**Note:** These are called automatically by main scripts when `GPIO_MODE="aardvark"`.

### Raspberry Pi Scripts (`scripts/rpi/`)

| File | Description |
|------|-------------|
| `gpio_setup.sh` | Setup and configure RPI GPIO pins |
| `test_rpi_gpio.sh` | Test RPI GPIO functionality |

### Documentation (`docs/`)

| File | Description |
|------|-------------|
| `AARDVARK_SETUP.md` | Complete Aardvark setup and usage guide |
| `AARDVARK_QUICKREF.md` | Quick reference for common operations |
| `CHANGES.md` | Implementation summary and change log |

### Examples (`examples/`)

| File | Description |
|------|-------------|
| `test_aardvark_install.sh` | Test Aardvark installation and connectivity |

## Usage Patterns

### Using Main Scripts (Recommended)

The main GPIO scripts automatically detect the mode from configuration:

```bash
# Edit plp.conf to set GPIO_MODE="rpi" or GPIO_MODE="aardvark"

# Then use the main scripts
./gpio_on.sh -c plp.conf
./gpio_off.sh -c plp.conf
./gpio_cycle.sh -c plp.conf
```

### Direct Script Usage

You can also call implementation scripts directly:

```bash
# Aardvark
./scripts/aardvark/gpio_on_aardvark.sh -c plp.conf

# RPI
./scripts/rpi/gpio_setup.sh -c plp.conf
```

### Python Library Usage

Use the library directly from Python or command line:

```bash
# Command line
python3 lib/aardvark_gpio.py --port 0 --pin 0 --low

# Or add lib/ to PYTHONPATH
export PYTHONPATH="${PYTHONPATH}:$(pwd)/lib"
python3 -c "from aardvark_gpio import AardvarkGPIO; print('Import OK')"
```

## Configuration

Main configuration file: `plp.conf`

Key settings:
```bash
# GPIO Mode Selection
GPIO_MODE="rpi"              # or "aardvark"

# RPI Configuration
RPI_HOST="192.168.0.40"
RPI_USER="pi"
RPI_GPIO_PIN="23"

# Aardvark Configuration
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"
```

## Getting Started

1. **Copy configuration template:**
   ```bash
   cp config/plp.conf.example plp.conf
   ```

2. **Edit configuration:**
   ```bash
   nano plp.conf
   # Set GPIO_MODE and relevant settings
   ```

3. **For Aardvark mode:**
   ```bash
   # Install Python library
   pip3 install aardvark_py
   
   # Test connection
   python3 lib/aardvark_gpio.py --port 0 --pin 0 --get
   ```

4. **Run scripts:**
   ```bash
   ./gpio_on.sh -c plp.conf
   ```

## Documentation

- **Setup Guide:** [docs/AARDVARK_SETUP.md](docs/AARDVARK_SETUP.md)
- **Quick Reference:** [docs/AARDVARK_QUICKREF.md](docs/AARDVARK_QUICKREF.md)
- **Changes:** [docs/CHANGES.md](docs/CHANGES.md)
- **Main README:** [README.md](README.md)

## Architecture

The project uses a dispatcher pattern:

```
User Command (gpio_on.sh -c plp.conf)
           ↓
    Load Configuration
           ↓
    Detect GPIO_MODE
           ↓
    ┌──────┴──────┐
    ↓             ↓
  "rpi"      "aardvark"
    ↓             ↓
RPI Logic    scripts/aardvark/
(Built-in)   gpio_*_aardvark.sh
                   ↓
              lib/aardvark_gpio.py
```

## Maintenance

### Adding New GPIO Mode

1. Create implementation in `scripts/<mode>/`
2. Add configuration variables to `config/plp.conf.example`
3. Update dispatcher logic in main scripts
4. Add documentation to `docs/`

### Testing

```bash
# Test Aardvark
python3 lib/aardvark_gpio.py --port 0 --pin 0 --cycle

# Test RPI
./scripts/rpi/test_rpi_gpio.sh

# Test unified scripts
./gpio_cycle.sh -c plp.conf
```

## Support

For issues or questions:
- Check documentation in `docs/`
- Review configuration in `plp.conf`
- Test individual components
- Check script output for error messages
