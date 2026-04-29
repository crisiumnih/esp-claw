local button = require("button")
local gpio = require("gpio")
local delay = require("delay")

local BTN_GPIO = 16
local LED_GPIO = 38
local ACTIVE_LEVEL = 0
local DURATION_MS = 30000
local POLL_MS = 10

local btn

local function cleanup()
    gpio.set_level(LED_GPIO, 0)
    if btn then
        pcall(button.off, btn)
        pcall(button.close, btn)
        btn = nil
    end
end

local function run()
    gpio.set_direction(LED_GPIO, "output")
    gpio.set_level(LED_GPIO, 0)

    local handle, err = button.new(BTN_GPIO, ACTIVE_LEVEL)
    if not handle then
        error("[button_led_smoke] button.new failed: " .. tostring(err))
    end
    btn = handle

    button.on(btn, "press_down", function()
        gpio.set_level(LED_GPIO, 1)
        print("[button_led_smoke] press_down -> LED ON")
    end)

    button.on(btn, "press_up", function()
        gpio.set_level(LED_GPIO, 0)
        print("[button_led_smoke] press_up -> LED OFF")
    end)

    print("[button_led_smoke] hold button on GPIO16, LED on GPIO38 should stay ON while pressed")

    local iters = math.max(1, math.floor(DURATION_MS / POLL_MS))
    for _ = 1, iters do
        button.dispatch()
        delay.delay_ms(POLL_MS)
    end
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
print("[button_led_smoke] done")
if not ok then
    error(err)
end
