local i2c = require("i2c")

local I2C_PORT = 0
local SDA_GPIO = 41
local SCL_GPIO = 42
local FREQ_HZ = 400000
local MPU_ADDR = 0x68

local REG_WHO_AM_I = 0x75
local REG_PWR_MGMT_1 = 0x6B
local REG_ACCEL_XOUT_H = 0x3B

local function u16(msb, lsb)
    return msb * 256 + lsb
end

local function s16(msb, lsb)
    local v = u16(msb, lsb)
    if v >= 0x8000 then
        v = v - 0x10000
    end
    return v
end

local bus = i2c.new(I2C_PORT, SDA_GPIO, SCL_GPIO, FREQ_HZ)

print(string.format("[mpu6050_smoke] scanning i2c port=%d sda=%d scl=%d", I2C_PORT, SDA_GPIO, SCL_GPIO))
local addrs = bus:scan()
for _, addr in ipairs(addrs) do
    print(string.format("[mpu6050_smoke] found device 0x%02X", addr))
end

local found = false
for _, addr in ipairs(addrs) do
    if addr == MPU_ADDR then
        found = true
        break
    end
end

if not found then
    bus:close()
    error("[mpu6050_smoke] device 0x68 not found on bus")
end

local dev = bus:device(MPU_ADDR)
local who = dev:read_byte(REG_WHO_AM_I)
print(string.format("[mpu6050_smoke] WHO_AM_I=0x%02X", who))

dev:write_byte(0x00, REG_PWR_MGMT_1)

local raw = dev:read(14, REG_ACCEL_XOUT_H)
if #raw ~= 14 then
    dev:close()
    bus:close()
    error("[mpu6050_smoke] expected 14 bytes, got " .. tostring(#raw))
end

local b = { string.byte(raw, 1, #raw) }
local ax = s16(b[1], b[2])
local ay = s16(b[3], b[4])
local az = s16(b[5], b[6])
local temp = s16(b[7], b[8])
local gx = s16(b[9], b[10])
local gy = s16(b[11], b[12])
local gz = s16(b[13], b[14])

print(string.format("[mpu6050_smoke] accel_raw x=%d y=%d z=%d", ax, ay, az))
print(string.format("[mpu6050_smoke] temp_raw=%d", temp))
print(string.format("[mpu6050_smoke] gyro_raw x=%d y=%d z=%d", gx, gy, gz))

dev:close()
bus:close()
print("[mpu6050_smoke] done")
