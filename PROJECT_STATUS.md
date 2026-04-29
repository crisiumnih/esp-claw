# ESP32-S3 Air Console Status

## Goal

Build a small ESP32-S3-based air-quality console on perfboard using this repo as the firmware base.

Current product direction:

- ESP32-S3 dev board
- 2.8 inch SPI TFT, 240x320, ILI9341
- Analog joystick
- 1 LED
- Active buzzer
- SDS011 dust sensor
- MPU6050 IMU
- DPDT switch
- Telegram alerts later
- Optional laptop-side local AI such as Qwen for summaries and richer automation

## Current Hardware Map

### ILI9341 TFT

| Module Pin | ESP32-S3 Pin | Notes |
|---|---|---|
| SCK | GPIO12 | SPI clock |
| MOSI / SDI / DIN | GPIO11 | SPI data out |
| CS | GPIO10 | SPI chip select |
| DC | GPIO13 | Data/command |
| RST | GPIO14 | Panel reset |
| BL | 3.3V for bring-up | Backlight is currently tied high for stable testing |
| VCC | External module-supported supply | Verify module input rail on real wiring |
| GND | GND | Common ground |

### Joystick

| Module Pin | ESP32-S3 Pin | Notes |
|---|---|---|
| VRx | GPIO1 | ADC input |
| VRy | GPIO2 | ADC input |
| SW | GPIO21 | Digital input, currently reads stuck low |
| VCC | 3.3V | Must not be powered from 5V when feeding ESP ADC pins |
| GND | GND | |

### SDS011

| Module Pin | ESP32-S3 Pin | Notes |
|---|---|---|
| TXD | GPIO18 | ESP UART RX |
| RXD | GPIO17 | ESP UART TX |
| VCC | External 5V | Sensor supply |
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
| LED | GPIO38 | Works in basic GPIO test |
| Active buzzer | GPIO39 | Needs polarity/wiring cleanup |
| DPDT switch | GPIO16 | Planned as simple mode input with pull-up |

## Power Notes

- Use external `5V` for the SDS011.
- Use `3.3V` for joystick and MPU6050.
- Keep all grounds common between ESP32, external supply, and modules.
- Do not feed 5V into ESP32-S3 GPIO pins.
- The joystick originally produced bad values because it was powered from 5V; it now behaves correctly on 3.3V.
- The TFT backlight is currently tied directly to 3.3V because that was the fastest stable bring-up path.

## Bring-Up Procedure Used

This is the procedure that got the board from dead wiring to working sensors.

1. Wire the TFT, joystick, LED, buzzer, SDS011, and MPU6050.
2. Fix power problems before touching firmware.
3. Add a custom board target under `application/edge_agent/boards/esp32_S3_DevKitC_1_ili9341_perfboard/`.
4. Install `esp-bmgr-assist` in the ESP-IDF environment.
5. Use `ESP-IDF v5.5.4`, not a newer IDF, because this repo applies an ESP-IDF patch tied to the 5.5.x tree.
6. Regenerate board-manager config after board YAML changes:
   - `idf.py gen-bmgr-config -c ./boards -b esp32_S3_DevKitC_1_ili9341_perfboard`
7. Build and flash:
   - `idf.py build`
   - `idf.py flash monitor`
8. Validate hardware one subsystem at a time with dedicated Lua bring-up scripts.

## Bring-Up Results

### Board and Runtime

- `edge_agent` builds successfully with the custom board target.
- Device boots cleanly into the app and CLI.
- Board-manager init passes.

### Display

- TFT is working.
- Backlight is stable when tied to 3.3V.
- Screen orientation is still being tuned; left-right mirroring behavior has been observed depending on generated board config.

### Joystick

- Analog axes are working.
- Stable center is about `1640 mV` on both axes when powered from 3.3V.
- Motion to extremes reaches near `0 mV` and near `3139 mV`, which is correct behavior.
- Joystick button line currently reads pressed all the time.

### SDS011

- UART link works.
- Valid SDS011 frames are being received.
- Parsed values are working.
- Example observed values:
  - `PM2.5 ≈ 10.5 to 10.7 ug/m3`
  - `PM10 ≈ 18.7 to 19.2 ug/m3`

### MPU6050

- Device is detected on I2C at `0x68`.
- `WHO_AM_I=0x68` is correct.
- Current smoke test reads all-zero raw accel/gyro/temp values, so the bus is alive but sensor data path still needs refinement.

### LED and Buzzer

- LED responds in GPIO testing.
- Buzzer behavior is not clean yet and likely needs polarity or wiring correction.

## Repo Changes Made

### Board Support

- Added `application/edge_agent/boards/esp32_S3_DevKitC_1_ili9341_perfboard/`
- Added:
  - `board_info.yaml`
  - `board_devices.yaml`
  - `board_peripherals.yaml`
  - `sdkconfig.defaults.board`
  - `setup_device.c`

### Lua Bring-Up Scripts

Added under `application/edge_agent/main/lua_scripts/`:

- `bringup_display_smoke.lua`
- `bringup_joystick_smoke.lua`
- `bringup_output_smoke.lua`
- `bringup_sds011_smoke.lua`
- `bringup_sds011_parse.lua`
- `bringup_mpu6050_smoke.lua`
- `dashboard_air_console.lua`

## Known Issues

- TFT orientation is not fully locked yet. After changing board display flags, board-manager config must be regenerated before rebuilding or the old orientation persists.
- Joystick `SW` is stuck low. Likely needs pull-up or wiring correction.
- Buzzer polarity or signal wiring is still unresolved.
- MPU6050 responds on I2C but current raw data test shows zeros.
- DPDT switch is not integrated yet.

## Intended Product

The intended app is a local air-quality console with optional laptop-side AI help.

### Local Device Responsibilities

- Read SDS011 PM2.5 / PM10
- Read MPU6050 status and later motion/tamper
- Show live dashboard on TFT
- Navigate UI with joystick
- Use LED and buzzer for alerts
- Read DPDT as a mode switch

### Laptop / Local LLM Responsibilities

Optional later:

- Run Qwen or another local model on laptop
- Pull readings from ESP32
- Produce human-readable summaries
- Format Telegram alerts
- Possibly provide richer historical analysis than the ESP32 should do locally

## Intended UI

Planned screen flow:

1. Home screen
   - PM2.5
   - PM10
   - air quality status
   - IMU detected status

2. Live diagnostics
   - joystick X/Y
   - sensor health
   - frame/update count

3. Alerts/settings
   - PM threshold
   - buzzer enabled
   - alarm active

4. Later
   - DPDT mode
   - motion/tamper view
   - Telegram status

## Intended Next Steps

### Immediate

1. Lock TFT orientation.
2. Build one stable joystick-driven dashboard script from `dashboard_air_console.lua`.
3. Convert joystick voltages into discrete navigation directions.
4. Add PM threshold editing in the UI.

### After That

5. Clean up joystick button input.
6. Clean up buzzer behavior.
7. Add DPDT mode input.
8. Add alert logic with LED/buzzer.
9. Refine MPU6050 readout beyond device detection.
10. Add Telegram alerts.

## Useful Commands

From `application/edge_agent`:

```bash
idf.py gen-bmgr-config -c ./boards -b esp32_S3_DevKitC_1_ili9341_perfboard
idf.py build
idf.py flash monitor
```

Useful CLI scripts:

```text
lua --run --path builtin/bringup_display_smoke.lua --timeout-ms 5000
lua --run --path builtin/bringup_joystick_smoke.lua --timeout-ms 5000
lua --run --path builtin/bringup_sds011_parse.lua --timeout-ms 8000
lua --run --path builtin/bringup_mpu6050_smoke.lua --timeout-ms 5000
lua --run --path builtin/dashboard_air_console.lua --timeout-ms 35000
```
