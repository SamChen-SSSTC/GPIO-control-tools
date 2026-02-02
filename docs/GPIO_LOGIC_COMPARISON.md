# GPIO Logic and Transport Comparison

## Logic Convention

Both RPI and Aardvark GPIO modes now follow the **same logic convention**:

```
set_low()  → GPIO LOW  → Power ON  (relay activated)
set_high() → GPIO HIGH → Power OFF (relay deactivated)
```

This ensures **identical behavior** regardless of the transport method used.

---

## Hardware Differences

### Raspberry Pi Mode
- **Connection**: Network (SSH over TCP/IP)
- **Hardware**: Raspberry Pi GPIO → Relay Module → Power
- **Logic**: 
  - GPIO LOW → Relay ON → Power ON
  - GPIO HIGH → Relay OFF → Power OFF
- **Inversion**: Built-in relay provides physical inversion

### Aardvark Mode
- **Connection**: USB Direct
- **Hardware**: Aardvark GPIO → Relay/Control Circuit → Power
- **Logic**: 
  - GPIO LOW → Power ON
  - GPIO HIGH → Power OFF
- **Inversion**: Software handles matching RPI behavior

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

### Expected LED Behavior

With an LED connected to GPIO and GND:

| Command | GPIO State | LED State | Power State |
|---------|-----------|-----------|-------------|
| `set_low()` | LOW | ON (lit) | Power ON |
| `set_high()` | HIGH | OFF (dark) | Power OFF |

---

## Command Equivalence

### Power ON
```bash
# RPI Mode
GPIO_MODE="rpi" ./gpio_on.sh -c plp.conf

# Aardvark Mode
GPIO_MODE="aardvark" ./gpio_on.sh -c plp.conf

# Direct Aardvark
python3 lib/aardvark_gpio.py --port 0 --pin 0 --low
```

### Power OFF
```bash
# RPI Mode
GPIO_MODE="rpi" ./gpio_off.sh -c plp.conf

# Aardvark Mode
GPIO_MODE="aardvark" ./gpio_off.sh -c plp.conf

# Direct Aardvark
python3 lib/aardvark_gpio.py --port 0 --pin 0 --high
```

### Power Cycle
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
