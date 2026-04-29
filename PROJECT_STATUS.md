# ESP32-S3 IoT Build Status

## Goal

Build a small ESP32-S3 IoT device on perfboard using this repo as the firmware base.

Current project direction:

- ESP32-S3 dev board
- 2.8 inch SPI TFT, 240x320, ILI9341
- Analog joystick
- 1 LED
- Active buzzer
- SDS011 dust sensor
- MPU6050 IMU
- DPDT switch
- Telegram alerts later

## Hardware Status

Completed wiring:

- ILI9341 TFT
- Joystick
- LED
- Active buzzer
- SDS011
- MPU6050

Pending wiring:

- DPDT switch

Dropped from scope:

- IR sensor
- WhatsApp integration in v1

## Current Pin Configuration

These are the working assumptions to use for firmware bring-up unless wiring changes.

### ILI9341 TFT

| Module Pin | ESP32-S3 Pin | Notes |
|---|---|---|
| SCK | GPIO12 | SPI clock |
| MOSI | GPIO11 | SPI data out |
| CS | GPIO10 | SPI chip select |
| DC | GPIO13 | Data/command |
| RST | GPIO14 | Panel reset |
| BL | GPIO15 | Backlight control |
| VCC | 5VIN or module-supported supply | Depends on module board input requirements |
| GND | GND | Common ground |

### Joystick

| Module Pin | ESP32-S3 Pin | Notes |
|---|---|---|
| VRx | GPIO1 | ADC input |
| VRy | GPIO2 | ADC input |
| SW | GPIO21 | Digital input |
| VCC | 3.3V | |
| GND | GND | |

### SDS011

| Module Pin | ESP32-S3 Pin | Notes |
|---|---|---|
| TXD | GPIO18 | ESP UART RX |
| RXD | GPIO17 | ESP UART TX |
| VCC | 5VIN | 5V supply |
| GND | GND | Common ground |

### MPU6050

| Module Pin | ESP32-S3 Pin | Notes |
|---|---|---|
| SDA | GPIO41 | I2C data |
| SCL | GPIO42 | I2C clock |
| VCC | 3.3V | |
| GND | GND | |

### Outputs and Switches

| Module | ESP32-S3 Pin | Notes |
|---|---|---|
| LED | GPIO38 | Status LED |
| Active buzzer | GPIO39 | Digital output |
| DPDT switch | GPIO16 | Planned as simple mode input with pull-up |

## Power Notes

- Use `5VIN` for SDS011 power.
- Use `3.3V` for joystick and MPU6050.
- Keep all grounds common.
- Do not feed 5V into ESP32-S3 GPIO pins.

## Firmware Plan

1. Validate the custom board profile under `application/edge_agent/boards/esp32_S3_DevKitC_1_ili9341_perfboard`.
2. Bring up the ILI9341 and show a test screen.
3. Read joystick ADC and button input.
4. Verify LED and buzzer control.
5. Wire and read the DPDT switch.
6. Read SDS011 over UART.
7. Add basic dashboard UI and alarm logic.
8. Add Telegram alerts.
9. Add MPU6050 support after MVP if needed.

## Current Repo Changes

- Added `application/edge_agent/boards/esp32_S3_DevKitC_1_ili9341_perfboard/`
- Configured `ILI9341` SPI display pins for the current perfboard wiring
- Configured `I2C` pins for future MPU6050 work

## Immediate Next Step

Run board-manager generation and build validation for `esp32_S3_DevKitC_1_ili9341_perfboard` in an ESP-IDF shell.
