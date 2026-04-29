local adc = require("adc")
local gpio = require("gpio")
local delay = require("delay")

local VRX_GPIO = 1
local VRY_GPIO = 2
local SW_GPIO = 21

local function fail(msg)
    error("[joystick_smoke] " .. msg)
end

local ok, vrx = pcall(adc.new, VRX_GPIO)
if not ok then
    fail("adc.new(" .. tostring(VRX_GPIO) .. ") failed: " .. tostring(vrx))
end

ok, vry = pcall(adc.new, VRY_GPIO)
if not ok then
    vrx:close()
    fail("adc.new(" .. tostring(VRY_GPIO) .. ") failed: " .. tostring(vry))
end

ok, sw = pcall(function()
    gpio.set_direction(SW_GPIO, "input")
end)
if not ok then
    vrx:close()
    vry:close()
    fail("gpio.set_direction(" .. tostring(SW_GPIO) .. ", input) failed: " .. tostring(sw))
end

print("[joystick_smoke] reading for 10 samples")
for i = 1, 10 do
    local x = vrx:read()
    local y = vry:read()
    local pressed = (gpio.get_level(SW_GPIO) == 0)
    print(string.format("[joystick_smoke] sample=%d x_mv=%d y_mv=%d pressed=%s", i, x, y, tostring(pressed)))
    delay.delay_ms(300)
end

vrx:close()
vry:close()
print("[joystick_smoke] done")
