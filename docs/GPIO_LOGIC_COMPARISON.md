# GPIO Logic and Transport Comparison

## Logic Convention

Both RPI and Aardvark GPIO modes now follow **direct electrical GPIO control**:

```
set_low()  → GPIO outputs LOW (0V)
set_high() → GPIO outputs HIGH (3.3V/5V)
```

The actual effect on your connected device (relay, LED, etc.) depends on your circuit design:
- **Active-low relay**: LOW activates relay (power ON), HIGH deactivates (power OFF)
- **Active-high relay**: HIGH activates relay (power ON), LOW deactivates (power OFF)
- **LED with pull-up**: LOW turns LED ON, HIGH turns LED OFF
- **LED with pull-down**: HIGH turns LED ON, LOW turns LED OFF

This ensures **identical electrical behavior** regardless of the transport method used.

---

## Hardware Differences

### Raspberry Pi Mode
- **Connection**: Network (SSH over TCP/IP)
- **Hardware**: Raspberry Pi GPIO → Relay/LED/Device
- **Logic**: Direct electrical control
  - GPIO LOW = 0V output
  - GPIO HIGH = 3.3V output

### Aardvark Mode
- **Connection**: USB Direct
- **Hardware**: Aardvark GPIO → Relay/LED/Device  
- **Logic**: Direct electrical control
  - GPIO LOW = 0V output
  - GPIO HIGH = 3.3V/5V output

---

## Verification Tests

### Test Scripts Available

1. **`test_gpio_transports.sh`** - Automated transport comparison
   ```bash
   # Test both modes
   ./test_gpio_transports.sh -c plp.conf
   
   # Test specific mode only
   ./test_gpio_transports.sh -c plp.conf -m aardvark
   
   # Quick test (skip device detection)
   ./test_gpio_transports.sh -c plp.conf -s
   ```

2. **`test_led_visual.sh`** - Visual LED verification
   ```bash
   # Test Aardvark with LED
   ./test_led_visual.sh aardvark
   
   # Test RPI with LED
   ./test_led_visual.sh rpi
   ```

### Expected Behavior

The GPIO output voltage depends on the command:

| Command | GPIO Output | Notes |
|---------|------------|-------|
| `set_low()` | 0V (LOW) | Effect depends on your circuit |
| `set_high()` | 3.3V/5V (HIGH) | Effect depends on your circuit |

**Common circuit behaviors:**
- **Active-low relay + set_low()**: Relay activates (typically powers device ON)
- **Active-low relay + set_high()**: Relay deactivates (typically powers device OFF)
- **LED with current-limiting resistor to GND + set_low()**: LED OFF (no voltage difference)
- **LED with current-limiting resistor to GND + set_high()**: LED ON (voltage drives current)

---

## Command Equivalence

### Set GPIO LOW (0V)
```bash
# RPI Mode
GPIO_MODE="rpi" ./gpio_on.sh -c plp.conf

# Aardvark Mode
GPIO_MODE="aardvark" ./gpio_on.sh -c plp.conf

# Direct Aardvark
python3 lib/aardvark_gpio.py --port 0 --pin 0 --low
```

### Set GPIO HIGH (3.3V/5V)
```bash
# RPI Mode
GPIO_MODE="rpi" ./gpio_off.sh -c plp.conf

# Aardvark Mode
GPIO_MODE="aardvark" ./gpio_off.sh -c plp.conf

# Direct Aardvark
python3 lib/aardvark_gpio.py --port 0 --pin 0 --high
```

### GPIO Cycle (HIGH → LOW → HIGH)
```bash
# RPI Mode
GPIO_MODE="rpi" ./gpio_cycle.sh -c plp.conf 2000

# Aardvark Mode
GPIO_MODE="aardvark" ./gpio_cycle.sh -c plp.conf 2000

# Direct Aardvark
python3 lib/aardvark_gpio.py --port 0 --pin 0 --cycle --duration 2000
```

---

## Troubleshooting

### LED Behaves Opposite to Expected

**Problem**: LED turns ON when it should turn OFF and vice versa.

**Cause**: Hardware wiring or relay logic differs from expected.

**Solution**:
1. Check LED wiring:
   - LED Anode → GPIO pin
   - LED Cathode → GND (through resistor)
   
2. For relay modules, check if it's active-HIGH or active-LOW
   - Active-LOW relay: LOW activates relay (current design)
   - Active-HIGH relay: HIGH activates relay (needs inversion)

### Different Behavior Between RPI and Aardvark

**Problem**: Same command produces different results.

**Cause**: Likely hardware wiring difference.

**Solution**:
1. Verify both use the same type of relay/control circuit
2. Run the visual test for each:
   ```bash
   ./test_led_visual.sh aardvark
   ./test_led_visual.sh rpi
   ```
3. Compare the results and adjust wiring if needed

### GPIO Shows Unexpected Values

**Problem**: `aa_gpio_get()` returns unexpected values.

**Note**: This is normal! The `aa_gpio_get()` function reads the *input buffer*, not the output value you set. Other pins may show HIGH even when you didn't set them.

**What matters**: Your target pin (bit 0 for SCL) should match your intended state:
- Power ON: Bit 0 should be 0 (LOW)
- Power OFF: Bit 0 should be 1 (HIGH)

---

## Implementation Details

### Aardvark GPIO Functions

```python
# Set pin LOW (Power ON)
current = aa.aa_gpio_get(handle)
new_value = current & ~pin_mask  # Clear the bit
aa.aa_gpio_set(handle, new_value)

# Set pin HIGH (Power OFF)
current = aa.aa_gpio_get(handle)
new_value = current | pin_mask   # Set the bit
aa.aa_gpio_set(handle, new_value)
```

### RPI GPIO (via SSH)

```bash
# Set pin LOW (Power ON)
echo 0 > /sys/class/gpio/gpio${PIN}/value

# Set pin HIGH (Power OFF)
echo 1 > /sys/class/gpio/gpio${PIN}/value
```

Both implementations produce the same logical result: **LOW=ON, HIGH=OFF**

---

## Quick Reference

| Operation | Unified Command | Direct RPI | Direct Aardvark |
|-----------|----------------|-----------|-----------------|
| Power ON | `./gpio_on.sh` | `scripts/gpio_on_rpi.sh` | `python3 lib/aardvark_gpio.py --low` |
| Power OFF | `./gpio_off.sh` | `scripts/gpio_off_rpi.sh` | `python3 lib/aardvark_gpio.py --high` |
| Power Cycle | `./gpio_cycle.sh` | `scripts/gpio_cycle_rpi.sh` | `python3 lib/aardvark_gpio.py --cycle` |
| Get State | N/A | N/A | `python3 lib/aardvark_gpio.py --get` |

---

## Testing Checklist

- [ ] LED turns ON when running `gpio_on.sh`
- [ ] LED turns OFF when running `gpio_off.sh`
- [ ] LED blinks during `gpio_cycle.sh`
- [ ] RPI mode works correctly
- [ ] Aardvark mode works correctly
- [ ] Both modes produce identical results
- [ ] Device powers on/off correctly
- [ ] PCIe rescan detects device after power on

---

## Summary

✅ **Unified Logic**: LOW=ON, HIGH=OFF for both transports  
✅ **Hardware Abstraction**: Software handles transport differences  
✅ **Test Tools**: Automated and visual verification available  
✅ **Consistent Behavior**: Same commands work regardless of mode  
✅ **Well Documented**: Clear explanation of logic and hardware
