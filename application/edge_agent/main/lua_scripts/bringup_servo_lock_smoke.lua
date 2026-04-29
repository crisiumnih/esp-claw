local mcpwm = require("mcpwm")
local delay = require("delay")

local SERVO_GPIO = 15
local SERVO_FREQ_HZ = 50
local SERVO_LOCK_DUTY = 11.5
local SERVO_UNLOCK_DUTY = 6.5

local servo = mcpwm.new({
    gpio = SERVO_GPIO,
    frequency_hz = SERVO_FREQ_HZ,
    duty_percent = SERVO_LOCK_DUTY,
    resolution_hz = 1000000,
})

print("[servo_lock_smoke] servo on GPIO15")
servo:start()

print("[servo_lock_smoke] unlock position")
servo:set_duty(SERVO_UNLOCK_DUTY)
delay.delay_ms(1200)

print("[servo_lock_smoke] lock position")
servo:set_duty(SERVO_LOCK_DUTY)
delay.delay_ms(1200)

print("[servo_lock_smoke] hold lock for 2s")
delay.delay_ms(2000)

servo:stop()
servo:close()
print("[servo_lock_smoke] done")
