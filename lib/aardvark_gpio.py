#!/usr/bin/env python3
"""
Aardvark GPIO Control Library
TotalPhase Aardvark I2C/SPI Host Adapter GPIO Control

This module provides GPIO control functionality using the TotalPhase Aardvark adapter.
The Aardvark has 6 GPIO pins that can be controlled via the Python API.

Requirements:
    - TotalPhase Aardvark Python library (aardvark_py)
    - Install from: https://www.totalphase.com/products/aardvark-i2cspi/

Hardware Setup:
    - Connect Aardvark GPIO pin to power control circuit (relay/MOSFET)
    
Logic Convention (matches RPI relay behavior):
    - set_low()  → GPIO LOW  → Power ON  (relay activated)
    - set_high() → GPIO HIGH → Power OFF (relay deactivated)
    
    This matches the RPI behavior where:
    - RPI sends LOW → relay activates → power ON
    - RPI sends HIGH → relay deactivates → power OFF
    
Usage:
    from aardvark_gpio import AardvarkGPIO
    
    gpio = AardvarkGPIO(port=0, pin=0)
    gpio.set_low()   # Power ON
    gpio.set_high()  # Power OFF
    gpio.close()
"""

import sys
import time
from typing import Optional

try:
    import aardvark_py as aa
except ImportError:
    print("Error: aardvark_py module not found.", file=sys.stderr)
    print("Install from: https://www.totalphase.com/products/aardvark-i2cspi/", file=sys.stderr)
    print("Or install via: pip install aardvark_py", file=sys.stderr)
    sys.exit(1)


class AardvarkGPIO:
    """Aardvark GPIO Controller
    
    Provides simple GPIO control interface for TotalPhase Aardvark adapter.
    """
    
    # GPIO pin masks (Aardvark has 6 GPIO pins: SCL, SDA, MISO, SCK, MOSI, SS)
    GPIO_PINS = {
        'SCL': aa.AA_GPIO_SCL,   # Pin 0
        'SDA': aa.AA_GPIO_SDA,   # Pin 1
        'MISO': aa.AA_GPIO_MISO, # Pin 2
        'SCK': aa.AA_GPIO_SCK,   # Pin 3
        'MOSI': aa.AA_GPIO_MOSI, # Pin 4
        'SS': aa.AA_GPIO_SS,     # Pin 5
    }
    
    def __init__(self, port: int = 0, pin: int = 0, verbose: bool = True):
        """Initialize Aardvark GPIO controller
        
        Args:
            port: Aardvark adapter port number (0 for first device)
            pin: GPIO pin number (0-5) or pin name ('SCL', 'SDA', etc.)
            verbose: Enable verbose output
        """
        self.port = port
        self.verbose = verbose
        self.handle = None
        
        # Convert pin number to mask
        if isinstance(pin, int):
            if pin < 0 or pin > 5:
                raise ValueError(f"Invalid GPIO pin: {pin}. Must be 0-5")
            pin_names = list(self.GPIO_PINS.keys())
            self.pin_name = pin_names[pin]
            self.pin_mask = self.GPIO_PINS[self.pin_name]
        elif isinstance(pin, str):
            pin_upper = pin.upper()
            if pin_upper not in self.GPIO_PINS:
                raise ValueError(f"Invalid GPIO pin name: {pin}. Must be one of {list(self.GPIO_PINS.keys())}")
            self.pin_name = pin_upper
            self.pin_mask = self.GPIO_PINS[pin_upper]
        else:
            raise TypeError("pin must be int (0-5) or str (pin name)")
        
        self.pin_num = list(self.GPIO_PINS.keys()).index(self.pin_name)
        
        # Open Aardvark adapter
        self._open()
    
    def _log(self, message: str):
        """Print log message if verbose is enabled"""
        if self.verbose:
            print(f"[AARDVARK] {message}")
    
    def _open(self):
        """Open connection to Aardvark adapter"""
        # Find all connected Aardvark devices
        (num_devices, ports, unique_ids) = aa.aa_find_devices_ext(16, 16)
        
        if num_devices == 0:
            raise RuntimeError("No Aardvark adapters found. Check USB connection.")
        
        self._log(f"Found {num_devices} Aardvark device(s)")
        
        if self.port >= num_devices:
            raise ValueError(f"Port {self.port} not available. Found {num_devices} device(s)")
        
        # Open the specified port
        self.handle = aa.aa_open(self.port)
        
        if self.handle <= 0:
            raise RuntimeError(f"Failed to open Aardvark on port {self.port}. Error code: {self.handle}")
        
        self._log(f"Opened Aardvark adapter on port {self.port} (handle: {self.handle})")
        
        # Get version info
        version = aa.aa_version(self.handle)
        self._log(f"API version: {version[0]}, Firmware: {version[1]}")
        
        # IMPORTANT: Configure Aardvark to disable I2C/SPI modes
        # This allows us to use the pins as GPIO
        # AA_CONFIG_GPIO_ONLY = 0x00 means GPIO mode (no I2C/SPI)
        aa.aa_configure(self.handle, aa.AA_CONFIG_GPIO_ONLY)
        self._log("Configured Aardvark to GPIO-only mode (I2C/SPI disabled)")
        
        # Configure GPIO - set pin as output
        # All pins start as inputs by default, we need to set direction
        self._configure_gpio()
    
    def _configure_gpio(self):
        """Configure GPIO pin as output"""
        # Set pin as output by setting the corresponding bit in the direction register
        # aa_gpio_direction sets pins as outputs (1) or inputs (0)
        aa.aa_gpio_direction(self.handle, self.pin_mask)
        
        # Enable GPIO (disable I2C/SPI on these pins if needed)
        # aa_gpio_pullup enables internal pullup resistors
        aa.aa_gpio_pullup(self.handle, 0x00)  # Disable pullups for cleaner output
        
        # Initialize to LOW (LED OFF, Power OFF) to match RPI behavior at startup
        current = aa.aa_gpio_get(self.handle)
        new_value = current & ~self.pin_mask  # Set physical GPIO LOW
        aa.aa_gpio_set(self.handle, new_value)
        
        self._log(f"Configured GPIO pin {self.pin_name} (pin {self.pin_num}) as output")
        self._log(f"Initialized GPIO to LOW (LED OFF, Power OFF)")
    
    def set_high(self):
        """Set GPIO pin HIGH (power OFF in our application)
        
        Note: Physical GPIO inversion to match RPI relay behavior
        - RPI: GPIO HIGH → relay OFF → power OFF → LED OFF
        - Aardvark: Set physical GPIO LOW → LED OFF (inverted in software)
        """
        # INVERTED: To turn power OFF, set physical GPIO LOW
        current = aa.aa_gpio_get(self.handle)
        new_value = current & ~self.pin_mask  # Clear bit = physical LOW
        aa.aa_gpio_set(self.handle, new_value)
        # Verify by reading back
        actual = aa.aa_gpio_get(self.handle)
        self._log(f"GPIO pin {self.pin_name} set HIGH (power OFF)")
        self._log(f"  Physical GPIO: LOW, Before: 0x{current:02X}, After: 0x{actual:02X}, Pin mask: 0x{self.pin_mask:02X}")
    
    def set_low(self):
        """Set GPIO pin LOW (power ON in our application)
        
        Note: Physical GPIO inversion to match RPI relay behavior
        - RPI: GPIO LOW → relay ON → power ON → LED ON
        - Aardvark: Set physical GPIO HIGH → LED ON (inverted in software)
        """
        # INVERTED: To turn power ON, set physical GPIO HIGH
        current = aa.aa_gpio_get(self.handle)
        new_value = current | self.pin_mask  # Set bit = physical HIGH
        aa.aa_gpio_set(self.handle, new_value)
        # Verify by reading back
        actual = aa.aa_gpio_get(self.handle)
        self._log(f"GPIO pin {self.pin_name} set LOW (power ON)")
        self._log(f"  Physical GPIO: HIGH, Before: 0x{current:02X}, After: 0x{actual:02X}, Pin mask: 0x{self.pin_mask:02X}")
    
    def get_state(self) -> bool:
        """Get current GPIO pin state
        
        Returns:
            True if HIGH, False if LOW
        """
        value = aa.aa_gpio_get(self.handle)
        is_high = (value & self.pin_mask) != 0
        if self.verbose:
            self._log(f"GPIO readback: 0x{value:02X} (binary: {value:08b})")
            self._log(f"Pin {self.pin_name} (mask 0x{self.pin_mask:02X}): {'HIGH' if is_high else 'LOW'}")
        return is_high
    
    def pulse(self, duration_ms: int = 100):
        """Generate a pulse (LOW -> HIGH -> LOW)
        
        Args:
            duration_ms: Pulse duration in milliseconds
        """
        self.set_low()
        time.sleep(duration_ms / 1000.0)
        self.set_high()
        self._log(f"Generated {duration_ms}ms pulse")
    
    def close(self):
        """Close connection to Aardvark adapter"""
        if self.handle:
            aa.aa_close(self.handle)
            self._log(f"Closed Aardvark adapter")
            self.handle = None
    
    def __enter__(self):
        """Context manager entry"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()
    
    def __del__(self):
        """Destructor"""
        self.close()


def main():
    """Command-line interface for Aardvark GPIO control"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Control GPIO on TotalPhase Aardvark adapter',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Set GPIO pin 0 HIGH (power on)
  python3 aardvark_gpio.py --port 0 --pin 0 --high
  
  # Set GPIO pin 0 LOW (power on)
  python3 aardvark_gpio.py --port 0 --pin 0 --low
  
  # Read GPIO pin state
  python3 aardvark_gpio.py --port 0 --pin 0 --get
  
  # Power cycle (high -> low -> high)
  python3 aardvark_gpio.py --port 0 --pin 0 --cycle --duration 2000
        """
    )
    
    parser.add_argument('-p', '--port', type=int, default=0,
                        help='Aardvark port number (default: 0)')
    parser.add_argument('--pin', type=str, default='0',
                        help='GPIO pin number (0-5) or name (SCL, SDA, MISO, SCK, MOSI, SS)')
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='Suppress verbose output')
    
    action_group = parser.add_mutually_exclusive_group(required=True)
    action_group.add_argument('--high', action='store_true',
                              help='Set GPIO HIGH (power ON)')
    action_group.add_argument('--low', action='store_true',
                              help='Set GPIO LOW (power OFF)')
    action_group.add_argument('--get', action='store_true',
                              help='Get GPIO state')
    action_group.add_argument('--cycle', action='store_true',
                              help='Power cycle (HIGH -> LOW -> HIGH)')
    
    parser.add_argument('--duration', type=int, default=2000,
                        help='Duration in ms for cycle command (default: 2000)')
    
    args = parser.parse_args()
    
    # Convert pin to int if it's a number
    try:
        pin = int(args.pin)
    except ValueError:
        pin = args.pin
    
    try:
        with AardvarkGPIO(port=args.port, pin=pin, verbose=not args.quiet) as gpio:
            if args.high:
                gpio.set_high()
            elif args.low:
                gpio.set_low()
            elif args.get:
                state = gpio.get_state()
                print(f"GPIO {gpio.pin_name} is {'HIGH' if state else 'LOW'}")
            elif args.cycle:
                print(f"Power cycling: OFF -> ON ({args.duration}ms) -> OFF")
                gpio.set_high()  # OFF
                time.sleep(0.5)
                gpio.set_low()   # ON
                time.sleep(args.duration / 1000.0)
                gpio.set_high()  # OFF
                print("Power cycle complete")
    
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
