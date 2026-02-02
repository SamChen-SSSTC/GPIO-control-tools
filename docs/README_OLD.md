# NVMe Firmware Update Testing Suite

This repository contains a comprehensive testing framework for NVMe SSD firmware updates with Power Loss Protection (PLP) simulation capabilities. It supports automated firmware cycling between multiple versions with hardware-based power interruption testing via Raspberry Pi GPIO control.

## Overview

The test suite is designed for reliability testing of NVMe firmware updates under various conditions, including:
- **Repeated firmware download/commit cycles** across multiple firmware versions
- **Power Loss Protection (PLP) simulation** using Raspberry Pi GPIO to control power supply
- **Automated logging** of firmware update cycles and device behavior
- **Support for multiple firmware binaries** organized by version and device capacity

## Hardware Requirements

- **Host System**: Linux system with NVMe device
- **NVMe SSD**: VAIL B0 DWPD1 U.2 drives (4TB, 8TB, or 16TB)
- **Raspberry Pi 4** (for hardware PLP simulation)
  - GPIO relay module connected to RPi GPIO pin (BCM numbering)
  - Network connectivity between host and RPi
  - SSH access configured

## Firmware Binary Structure

```
Bin_<VERSION>/
└── VAIL_B0_DWPD1_U2_<CAPACITY>TB_TCG0/
    ├── 1333_Standard_E2e_NAND_IceLoader.dfw
    ├── 1333_Standard_E2e_NAND_IceLoader.tim
    ├── 1333_Standard_E2e_NAND_Main.dfw
    ├── 1333_Standard_E2e_NAND_MbistLoader.dfw
    ├── 1333_Standard_E2e_NAND_SBL.dfw
    ├── FclBin
    └── Main.dfw
```

Available firmware versions:
- **Bin_A7**: Firmware version A7
- **Bin_A8**: Firmware version A8
- **Bin_D2_WITHOUT_CHK**: Firmware version D2 (without FWversion check)
- **Bin_P3_CHK**: Firmware version P3 (with FWversion check)
- **Bin_X1_WITHOUT_CHK**: Firmware version X1 (without FWversion check)

## Scripts

### Main Testing Script

#### `FW_update.sh`
The primary automated firmware update testing script with PLP simulation support.

**Features:**
- Cycles through multiple firmware versions (up to 3)
- Supports three PLP modes: `no`, `software`, `rpi4`
- Configurable transfer sizes and sleep intervals
- Comprehensive logging with timestamps
- PCIe hot-plug/rescan support for recovery
- Progress tracking and error handling

**Usage:**
```bash
# Using configuration file (recommended)
./FW_update.sh -c plp.conf

# Command line mode
./FW_update.sh <nvme_device> [fw_file_1] [fw_file_2] [fw_file_3] [sleep_time] \
               [xfer_size] [plp_mode] [plp_prob] [rpi_host] [rpi_user] [rpi_gpio]

# Examples
./FW_update.sh -c plp.conf
./FW_update.sh /dev/nvme0n1 FQZRDX1.bin FQZRDD2.bin FQZRDP3.bin 3 0x20000 rpi4 30 192.168.0.40 pi 23
```

**PLP Modes:**
- `no`: Disable PLP simulation (normal firmware updates)
- `software`: Software-based PLP using `nvme reset` command
- `rpi4`: Hardware PLP via Raspberry Pi GPIO relay control

### GPIO Control Scripts

#### `gpio_setup.sh`
Configures Raspberry Pi GPIO for relay-based power control.

**Usage:**
```bash
# Remote setup from host (recommended)
./gpio_setup.sh -c plp.conf -p 23 --test

# Direct setup on RPi
./gpio_setup.sh --local 23 test
```

#### `gpio_cycle.sh`
Performs complete power cycle: OFF → Wait → ON → Wait for device recovery.

**Usage:**
```bash
./gpio_cycle.sh -c plp.conf [off_ms]
./gpio_cycle.sh -c plp.conf 2000
```

#### `gpio_on.sh` / `gpio_off.sh`
Direct GPIO control for power on/off operations.

#### `test_rpi_gpio.sh`
Validates GPIO control setup and SSH connectivity.

**Usage:**
```bash
./test_rpi_gpio.sh -c plp.conf
```

### Simple Update Script

#### `FWUpdate.sh`
Basic firmware update script without PLP features.

**Usage:**
```bash
./FWUpdate.sh <device> <firmware_file>
```

## Configuration

### Configuration File Format (`plp.conf`)

```bash
# Basic NVMe Configuration
NVME_DEVICE="/dev/nvme0n1"
FW_FILE_1="FQZRDA7.bin"
FW_FILE_2="FQZRDA8.bin"
FW_FILE_3="FQZRDP3.bin"
SLEEP_TIME="3"
XFER_SIZE="0x20000"

# PLP Configuration
PLP_SIMULATION="rpi4"        # no, software, or rpi4
PLP_PROBABILITY="100"        # Percentage (0-100)

# Raspberry Pi Configuration
RPI_HOST="192.168.0.40"
RPI_USER="pi"
RPI_GPIO_PIN="23"
RPI_SSH_PORT="22"
RPI_POWER_OFF_MS="2000"

# SSH Authentication
RPI_SSH_KEY="/path/to/ssh/key"    # Optional: SSH key path
RPI_SSH_PASS="password"            # Optional: SSH password

# Logging Configuration
#LOG_DIR="./logs"
#LOG_FILE="./logs/custom_name.log"
```

## Logging

### Log Directory Structure

```
logs/
├── Log_nvme0n1_20251201_171712.log
├── Log_nvme0n1_20251202_131217.log
└── ...

TraceLog_<SERIAL_NUMBER>/
└── Tracelog_Decoded.txt
```

### Log Information
- Automatic log file creation with timestamps
- Firmware version tracking before/after updates
- PLP event logging
- Device detection and recovery status
- Error conditions and warnings

## Setup Instructions

### 1. Host System Setup

```bash
# Ensure nvme-cli is installed
sudo apt-get install nvme-cli

# Make scripts executable
chmod +x *.sh

# Verify NVMe device
sudo nvme list
```

### 2. Raspberry Pi Setup

```bash
# On RPi: Install required packages
sudo apt-get update
sudo apt-get install python3-lgpio

# Configure SSH access from host
ssh-keygen -t ed25519
ssh-copy-id pi@<rpi_ip_address>

# Test SSH connectivity
ssh pi@<rpi_ip_address> "echo 'SSH connection successful'"
```

### 3. Hardware Connections

1. Connect relay module to Raspberry Pi GPIO pin (default: GPIO 23, BCM numbering)
2. Connect relay to power supply control circuit
3. Configure relay logic:
   - **HIGH** = Power OFF
   - **LOW** = Power ON

### 4. Initial Testing

```bash
# Test GPIO setup
./test_rpi_gpio.sh -c plp.conf

# Run GPIO setup with validation
./gpio_setup.sh -c plp.conf --test

# Test single power cycle
./gpio_cycle.sh -c plp.conf 2000
```

## Usage Examples

### Basic Firmware Cycling (No PLP)

```bash
# Edit plp.conf
PLP_SIMULATION="no"

# Run test
./FW_update.sh -c plp.conf
```

### Hardware PLP Testing

```bash
# Edit plp.conf
PLP_SIMULATION="rpi4"
PLP_PROBABILITY="50"
RPI_HOST="192.168.0.40"
RPI_GPIO_PIN="23"

# Run test
./FW_update.sh -c plp.conf
```

### Software PLP Testing

```bash
# Edit plp.conf
PLP_SIMULATION="software"
PLP_PROBABILITY="30"

# Run test
./FW_update.sh -c plp.conf
```

## Troubleshooting

### Common Issues

**Device not detected after power cycle:**
- Increase `RPI_POWER_OFF_MS` duration
- Check PCIe rescan delays: `PCIE_REMOVE_DELAY`, `PCIE_RESCAN_DELAY`
- Verify power supply stability

**GPIO control not working:**
- Run `./test_rpi_gpio.sh -c plp.conf` to diagnose
- Verify SSH connectivity and authentication
- Check GPIO pin configuration matches hardware

**Firmware update failures:**
- Check log files in `logs/` directory
- Verify firmware binary compatibility
- Ensure adequate transfer size (`XFER_SIZE`)

**SSH authentication issues:**
- Use SSH key authentication (recommended over password)
- Verify SSH key permissions: `chmod 600 ~/.ssh/id_ed25519`
- Test manual SSH: `ssh pi@<rpi_ip>`

## Safety Considerations

- **Power cycling can stress hardware** - use appropriate test intervals
- **Verify firmware compatibility** before running automated tests
- **Monitor logs regularly** for anomalies
- **Backup important data** before testing
- **Use dedicated test hardware** when possible

## Development & Debugging

### Enable Verbose Logging

Set environment variables:
```bash
export DEBUG=1
./FW_update.sh -c plp.conf
```

### Manual Firmware Update

```bash
sudo nvme fw-download /dev/nvme0n1 --fw=firmware.bin --xfer=0x20000
sudo nvme fw-commit /dev/nvme0n1 --slot=1 --action=3
```

### Check Firmware Version

```bash
sudo nvme fw-log /dev/nvme0n1
```

## License

Internal testing tool - check with your organization for usage rights.

## Contributors

Testing framework for NVMe firmware reliability validation.
