# GPIO Transport Testing - Quick Reference

## 🎯 GPIO Logic (Direct Electrical Control)
```
set_low()  = GPIO outputs 0V (LOW)
set_high() = GPIO outputs 3.3V/5V (HIGH)
```

**The effect on your device depends on your circuit:**
- Active-low relay: LOW typically activates relay (powers device ON)
- Active-high relay: HIGH typically activates relay (powers device ON)
- LED configuration determines whether HIGH or LOW lights it up

## ⚡ Quick Tests

### Test Aardvark Mode
```bash
# Visual LED test
./test_led_visual.sh aardvark

# Direct control
python3 lib/aardvark_gpio.py --port 0 --pin 0 --low   # ON
python3 lib/aardvark_gpio.py --port 0 --pin 0 --high  # OFF
python3 lib/aardvark_gpio.py --port 0 --pin 0 --get   # READ
```

### Test RPI Mode
```bash
# Visual LED test
./test_led_visual.sh rpi

# Using unified scripts
GPIO_MODE="rpi" ./gpio_on.sh -c plp.conf
GPIO_MODE="rpi" ./gpio_off.sh -c plp.conf
```

### Compare Both Modes
```bash
# Full comparison (with device detection)
./test_gpio_transports.sh -c plp.conf

# Quick comparison (skip device detection)
./test_gpio_transports.sh -c plp.conf -s

# Test only one mode
./test_gpio_transports.sh -c plp.conf -m aardvark
./test_gpio_transports.sh -c plp.conf -m rpi
```

## 📋 Verification Checklist

- [ ] LED ON when running `./gpio_on.sh`
- [ ] LED OFF when running `./gpio_off.sh`  
- [ ] LED blinks during `./gpio_cycle.sh`
- [ ] Aardvark LOW sets LED ON
- [ ] Aardvark HIGH sets LED OFF
- [ ] RPI mode works correctly
- [ ] Both modes behave identically

## 🔧 Configuration

Edit `plp.conf`:
```bash
# Switch to Aardvark
GPIO_MODE="aardvark"
AARDVARK_PORT="0"
AARDVARK_GPIO_PIN="0"

# Switch to RPI
GPIO_MODE="rpi"
RPI_HOST="192.168.0.40"
RPI_GPIO_PIN="23"
```

## 📚 Documentation

- **Full guide**: `docs/GPIO_LOGIC_COMPARISON.md`
- **Setup**: `docs/AARDVARK_SETUP.md`
- **Quick ref**: `docs/AARDVARK_QUICKREF.md`

## 🐛 Troubleshooting

### GPIO behavior not as expected
→ Verify your circuit type (active-low vs active-high relay/LED)
→ Measure GPIO voltage with multimeter to confirm output
→ Check wiring connections

### Modes behave differently
→ Run: `./test_gpio_transports.sh -c plp.conf`
→ Verify both modes output same electrical voltage (use multimeter)

### Aardvark not found
→ Run: `lsusb | grep "Total Phase"`
→ Check: `python3 -c "import aardvark_py; print('OK')"`

## ✅ Success Indicators

Both modes should produce:
- ✓ Same LED behavior
- ✓ Same power control
- ✓ Same device detection
- ✓ Consistent timing
