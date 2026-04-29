local bmp388 = require("lib_bmp388")
local delay = require("delay")

local I2C_PORT = 0
local SDA_GPIO = 41
local SCL_GPIO = 42
local FREQ_HZ = 400000
local SAMPLE_COUNT = 5

local sensor, err = bmp388.new({
    port = I2C_PORT,
    sda = SDA_GPIO,
    scl = SCL_GPIO,
    frequency = FREQ_HZ,
})

if not sensor then
    error("[bmp388_smoke] init failed: " .. tostring(err))
end

print(string.format("[bmp388_smoke] sensor found at 0x%02X", sensor:address()))

for i = 1, SAMPLE_COUNT do
    local sample, serr = sensor:read()
    if not sample then
        sensor:close()
        error("[bmp388_smoke] read failed: " .. tostring(serr))
    end

    print(string.format(
        "[bmp388_smoke] sample %d/%d temp=%.2fC pressure=%.2fhPa",
        i,
        SAMPLE_COUNT,
        sample.temperature_c,
        sample.pressure_hpa
    ))
    delay.delay_ms(500)
end

sensor:close()
print("[bmp388_smoke] done")
