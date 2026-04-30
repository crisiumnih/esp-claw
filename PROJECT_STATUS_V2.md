# PROJECT STATUS V2

Date: 2026-04-30
Project: `ESP32-S3 IoT Smart Switchboard / Alexa-like Prototype`

## Current Goal

Build a practical smart-home controller that supports:

- local TFT dashboard with joystick navigation
- manual control of core devices
- Telegram + LLM remote interaction
- fast hardware bring-up for lock/light/sensor features

## Hardware Mapped So Far

- TFT ILI9341 display
- joystick:
  - X: `GPIO1`
  - Y: `GPIO2`
  - SW: `GPIO21`
- LED mock light: `GPIO38`
- tactile button: `GPIO16`
- LDR: `GPIO4`
- servo lock: `GPIO15`
- BMP388 over I2C:
  - SDA: `GPIO41`
  - SCL: `GPIO42`
  - address: `0x76` with `SDO -> GND`
- RC522 RFID over SPI:
  - SCK: `GPIO5`
  - MOSI: `GPIO6`
  - MISO: `GPIO7`
  - CS/SS: `GPIO8`
  - RST: `GPIO9`
  - host: `SPI2`
- speaker / audio out:
  - current board audio path uses I2S out for `MAX98357A`
  - BCLK: `GPIO39`
  - LRCLK/WS: `GPIO40`
  - DIN: `GPIO47`
  - output mode: `mono`

## Full GPIO Map

- `GPIO1`:
  - joystick X axis
- `GPIO2`:
  - joystick Y axis
- `GPIO4`:
  - LDR analog input
- `GPIO5`:
  - RC522 `SCK`
- `GPIO6`:
  - RC522 `MOSI`
- `GPIO7`:
  - RC522 `MISO`
- `GPIO8`:
  - RC522 `CS` / `SS`
- `GPIO9`:
  - RC522 `RST`
- `GPIO10`:
  - TFT `CS`
- `GPIO11`:
  - TFT `MOSI` / `data0`
- `GPIO12`:
  - TFT `SCLK`
- `GPIO13`:
  - TFT `DC`
- `GPIO14`:
  - TFT `RESET`
- `GPIO15`:
  - servo PWM output
- `GPIO16`:
  - tactile button input
- `GPIO21`:
  - joystick switch
- `GPIO39`:
  - MAX98357A `BCLK`
- `GPIO40`:
  - MAX98357A `LRCLK/WS`
- `GPIO47`:
  - MAX98357A `DIN`
- `GPIO38`:
  - LED mock light output
- `GPIO41`:
  - BMP388 `SDA`
- `GPIO42`:
  - BMP388 `SCL`

## Device Wiring Summary

- Joystick:
  - `VRx -> GPIO1`
  - `VRy -> GPIO2`
  - `SW -> GPIO21`
- LED mock light:
  - signal -> `GPIO38`
- tactile button:
  - signal -> `GPIO16`
- LDR:
  - analog output -> `GPIO4`
- servo:
  - signal -> `GPIO15`
- BMP388:
  - `SDA/SDI -> GPIO41`
  - `SCL/SCK -> GPIO42`
  - `SDO -> GND`
  - `CS -> 3V3` for I2C mode
- RC522:
  - `SCK -> GPIO5`
  - `MOSI -> GPIO6`
  - `MISO -> GPIO7`
  - `SDA/SS -> GPIO8`
  - `RST -> GPIO9`
- MAX98357A:
  - `BCLK -> GPIO39`
  - `LRC/WS -> GPIO40`
  - `DIN -> GPIO47`

## What Was Added

- Wi-Fi verified and used for:
  - web UI
  - Telegram
  - LLM connectivity
- Telegram bot integration is working
- LLM provider path is working
- predefined direct Telegram command routing added for:
  - `light on/off/toggle`
  - `door open/close/toggle`
  - `status`
  - `temperature`
  - `pressure`
  - `ldr`
  - `wifi status`
  - `rfid status`
- BMP388 Lua helper and smoke test added
- tactile button to LED control added
- servo lock control added
- RC522 Lua module added
- RC522 smoke script added
- TFT dashboard expanded for:
  - light state
  - sensor state
  - lock state
  - RFID state
  - audio state
  - Wi-Fi state
  - integrated summary home page

## Hardware Verification Status

Verified on hardware:

- Wi-Fi connection and web UI
- Telegram bot path
- LLM provider path
- TFT rendering
- joystick navigation
- BMP388 readings
- LDR readings
- tactile button input
- LED mock light output
- servo control path
- direct predefined Telegram command path

Pending final hardware verification:

- speaker / audio tone output

Note:

- audio is the main remaining hardware path that was not fully validated on-board
- the rest of the current prototype stack has been brought up and exercised in some form

## Important Fixes Made

- RC522 moved off the display SPI bus path
  - display already uses SPI
  - RC522 now uses `SPI2` in the integration scripts
- dashboard startup was hardened so RFID module load/init failure does not need to kill the whole dashboard
- RC522 constructor was updated to better tolerate an already-initialized SPI host
- dashboard script was split into:
  - `dashboard_air_console.lua`
  - `lib_dashboard_air_console.lua`
  so it can fit under the Lua script runner size limit

## Known Issues / Current Debug Focus

- RC522 still needs final runtime verification on hardware after the constructor fixes
- repeated RC522 smoke runs previously failed with:
  - `SPI bus already initialized`
  this should now be reduced by the SPI reuse handling, but it still needs on-board confirmation
- the dashboard had exceeded the direct Lua runner size limit before the split
- speaker support is still tone-first only
  - not voice assistant playback yet
- predefined device control currently uses exact lowercase matches in router rules
  - natural-language paraphrasing still needs an LLM translation layer on top

## Speaker Note

Current board audio output is defined for `MAX98357A` on:

- `GPIO39` = `BCLK`
- `GPIO40` = `LRCLK/WS`
- `GPIO47` = `DIN`
- I2S output is configured as `mono`

The speaker should connect to the amplifier module, not directly to the ESP32:

- `MAX98357A SPK+` -> speaker `+`
- `MAX98357A SPK-` -> speaker `-`

Power and control wiring for the amplifier:

- `VIN` -> `5V`
- `GND` -> `GND`
- `SD/EN` -> `3V3` for always-on, or a GPIO later for mute control

For this phase, the software target is only:

- boot / feedback tones
- success / alert tones

## LLM Control Note

The LLM is connected, but it still does **not** have enough project-specific control context to operate the board properly by itself.

We still need to add explicit project control context such as:

- what devices exist
- what each device is called
- what states each device supports
- which commands should bypass free-form reasoning
- what tool/action should be used for:
  - `light on`
  - `light off`
  - `toggle light`
  - `lock`
  - `unlock`
  - `status`
  - `temperature`
  - `pressure`
  - `ldr`
  - RFID-based lock actions

## How To Make The LLM Actually Useful Here

The right pattern is:

1. keep simple device control out of open-ended chat logic
2. expose the board as a small, explicit device model
3. let the LLM translate natural language into known actions
4. let firmware execute those actions directly

For this project, the LLM becomes useful only when it knows:

- what controllable devices exist
- which states they support
- what status fields can be read
- what actions are safe to perform automatically
- what actions should require confirmation

Example useful actions:

- `turn the light on`
- `turn the light off`
- `open the door`
- `close the door`
- `show room status`
- `what is the temperature`

## Direct Command Layer

The current prototype now has a predefined command layer for Telegram so common actions do not depend on free-form LLM reasoning.

Current exact commands:

- `light on`
- `turn on light`
- `light off`
- `turn off light`
- `toggle light`
- `light status`
- `open door`
- `door open`
- `close door`
- `door close`
- `toggle door`
- `door status`
- `status`
- `temperature`
- `pressure`
- `ldr`
- `wifi status`
- `rfid status`

This is the correct control foundation for the project because:

- it avoids hallucinated GPIO/tool syntax
- it makes hardware actions deterministic
- it keeps small local/cloud models usable
- it gives the LLM a stable action vocabulary to target later

## Next LLM Step

The next LLM-facing improvement should not be “let the model control raw GPIO”.

It should be:

1. define a small action vocabulary:
   - `light_on`
   - `light_off`
   - `light_toggle`
   - `door_open`
   - `door_close`
   - `device_status`
   - `temperature_read`
   - `pressure_read`
   - `ldr_read`
2. inject current device context:
   - light state
   - door state
   - latest BMP388 values
   - LDR value
   - Wi-Fi status
   - last RFID UID
3. let the LLM translate flexible language into one of those actions
4. execute only through the direct command/device layer

That is how commands like `open the door via Telegram` become reliable instead of conversational guesses.
- `is the door locked`

## How To Add Context To The LLM Properly

Add context at 3 layers:

### 1. Static project context

The system/profile prompt should describe the board in a strict way:

- device name: `ESP32 Home Switchboard`
- light output: LED on `GPIO38`
- door lock actuator: servo on `GPIO15`
- door access sensor: RC522 RFID
- environment sensors:
  - BMP388 temperature/pressure
  - LDR light level
- local UI:
  - TFT
  - joystick
  - tactile button
- remote control path:
  - Telegram

### 2. Action schema

The LLM should not invent actions.
It should only be allowed to call a known action set such as:

- `light_on`
- `light_off`
- `light_toggle`
- `door_open`
- `door_close`
- `door_toggle`
- `get_status`
- `get_temperature`
- `get_pressure`
- `get_ldr`
- `get_lock_state`

### 3. Live state injection

Each request should include the latest state snapshot:

- Wi-Fi online/offline
- light on/off
- lock open/closed
- temperature
- pressure
- LDR level
- last RFID UID if available
- audio ready/not ready

That lets the LLM answer with awareness instead of guessing.

## Best Architecture For Telegram Device Control

Telegram message flow should become:

1. Telegram inbound message arrives
2. direct command router checks for exact commands first
3. if matched, firmware executes action immediately
4. if not matched, LLM interprets the request
5. LLM maps the request to a known action
6. firmware executes the action
7. Telegram gets structured reply with final state

This is how commands like:

- `open the door`
- `close the door`
- `turn light on`

become reliable and fast.

## What Needs To Be Added For Proper LLM Control

- a direct command layer for simple home-automation commands
- project/device context in the LLM prompt/profile
- clear action schema for hardware control
- fallback logic:
  - direct command first
  - LLM interpretation second
- state snapshot injection before each LLM request
- confirmation rules for risky actions if needed

Without that, the LLM can chat, but it cannot reliably behave like a smart-home controller.

## Recommended Next Phase

1. Finish RC522 hardware verification.
2. Stabilize the dashboard with all current properties visible.
3. Add direct command routing for:
   - `light on/off`
   - `lock/unlock`
   - `status`
   - `temperature`
   - `pressure`
   - `ldr`
4. Add LLM project context so Telegram commands can control the board safely.
5. Keep microphone / wake-word work for later.
