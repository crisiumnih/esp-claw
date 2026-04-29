local gpio = require("gpio")
local delay = require("delay")

local LED_GPIO = 38
local BUZZER_GPIO = 39

local function pulse(name, pin, level, hold_ms)
    print(string.format("[output_smoke] %s pin=%d level=%d", name, pin, level))
    gpio.set_level(pin, level)
    delay.delay_ms(hold_ms)
    gpio.set_level(pin, 0)
    delay.delay_ms(300)
end

gpio.set_direction(LED_GPIO, "output")
gpio.set_direction(BUZZER_GPIO, "output")

gpio.set_level(LED_GPIO, 0)
gpio.set_level(BUZZER_GPIO, 0)

print("[output_smoke] testing LED active-high")
pulse("led_high", LED_GPIO, 1, 700)

print("[output_smoke] testing buzzer active-high")
pulse("buzzer_high", BUZZER_GPIO, 1, 500)

print("[output_smoke] testing LED active-low")
gpio.set_level(LED_GPIO, 1)
delay.delay_ms(200)
print(string.format("[output_smoke] led_low pin=%d level=0", LED_GPIO))
gpio.set_level(LED_GPIO, 0)
delay.delay_ms(700)
gpio.set_level(LED_GPIO, 1)
delay.delay_ms(300)
gpio.set_level(LED_GPIO, 0)

print("[output_smoke] testing buzzer active-low")
gpio.set_level(BUZZER_GPIO, 1)
delay.delay_ms(200)
print(string.format("[output_smoke] buzzer_low pin=%d level=0", BUZZER_GPIO))
gpio.set_level(BUZZER_GPIO, 0)
delay.delay_ms(500)
gpio.set_level(BUZZER_GPIO, 1)
delay.delay_ms(300)
gpio.set_level(BUZZER_GPIO, 0)

print("[output_smoke] done")
