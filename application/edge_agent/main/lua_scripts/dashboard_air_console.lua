local bm = require("board_manager")
local display = require("display")
local delay = require("delay")
local uart = require("uart")
local adc = require("adc")
local gpio = require("gpio")
local i2c = require("i2c")

local SDS_UART_PORT = 1
local SDS_TX_GPIO = 17
local SDS_RX_GPIO = 18
local SDS_BAUD = 9600

local JOY_X_GPIO = 1
local JOY_Y_GPIO = 2
local JOY_SW_GPIO = 21

local I2C_PORT = 0
local I2C_SDA_GPIO = 41
local I2C_SCL_GPIO = 42
local I2C_FREQ_HZ = 400000
local MPU_ADDR = 0x68
local MPU_REG_WHO_AM_I = 0x75

local function fail(msg)
    error("[dashboard_air_console] " .. msg)
end

local function parse_sds011_frame(s)
    if #s ~= 10 then
        return nil
    end

    local b = { string.byte(s, 1, #s) }
    if b[1] ~= 0xAA or b[2] ~= 0xC0 or b[10] ~= 0xAB then
        return nil
    end

    local checksum = (b[3] + b[4] + b[5] + b[6] + b[7] + b[8]) % 256
    if checksum ~= b[9] then
        return nil
    end

    return {
        pm25 = (b[3] + b[4] * 256) / 10.0,
        pm10 = (b[5] + b[6] * 256) / 10.0,
    }
end

local function centered_text(y, text, color, font_size)
    local w = display.width()
    local tw = display.measure_text(text, { font_size = font_size })
    local x = math.floor((w - tw) / 2)
    display.draw_text(x, y, text, {
        r = color[1],
        g = color[2],
        b = color[3],
        font_size = font_size,
    })
end

local function draw_label_value(y, label, value, color)
    display.draw_text(12, y, label, { r = 170, g = 184, b = 196, font_size = 18 })
    display.draw_text(128, y, value, { r = color[1], g = color[2], b = color[3], font_size = 18 })
end

local function pm_color(pm25)
    if not pm25 then
        return { 180, 180, 180 }
    end
    if pm25 < 15 then
        return { 88, 210, 124 }
    end
    if pm25 < 35 then
        return { 255, 200, 80 }
    end
    return { 235, 90, 90 }
end

local ok, err = pcall(bm.init_device, "display_lcd")
if not ok then
    fail("board_manager.init_device failed: " .. tostring(err))
end

local panel_handle, io_handle, width, height, panel_if = bm.get_display_lcd_params("display_lcd")
if not panel_handle then
    fail("get_display_lcd_params failed: " .. tostring(io_handle))
end

ok, err = pcall(display.init, panel_handle, io_handle, width, height, panel_if)
if not ok then
    fail("display.init failed: " .. tostring(err))
end

pcall(display.backlight, true)

local sds_ok, sds = pcall(uart.new, SDS_UART_PORT, SDS_TX_GPIO, SDS_RX_GPIO, SDS_BAUD)
if not sds_ok then
    pcall(display.deinit)
    fail("uart.new failed: " .. tostring(sds))
end
sds:flush_input()

local joy_x = adc.new(JOY_X_GPIO)
local joy_y = adc.new(JOY_Y_GPIO)
gpio.set_direction(JOY_SW_GPIO, "input")

local imu_status = "missing"
local imu_bus_ok, imu_bus = pcall(i2c.new, I2C_PORT, I2C_SDA_GPIO, I2C_SCL_GPIO, I2C_FREQ_HZ)
if imu_bus_ok then
    local addrs = imu_bus:scan()
    for _, addr in ipairs(addrs) do
        if addr == MPU_ADDR then
            local dev = imu_bus:device(MPU_ADDR)
            local who = dev:read_byte(MPU_REG_WHO_AM_I)
            imu_status = string.format("0x%02X", who)
            dev:close()
            break
        end
    end
    imu_bus:close()
else
    imu_status = "i2c_err"
end

local latest_pm25 = nil
local latest_pm10 = nil
local samples = 0

local function cleanup()
    pcall(function() sds:close() end)
    pcall(function() joy_x:close() end)
    pcall(function() joy_y:close() end)
    pcall(display.deinit)
end

local run_ok, run_err = xpcall(function()
    for _ = 1, 120 do
        local avail = sds:available()
        if avail >= 10 then
            local chunk = sds:read(10, 200)
            local frame = parse_sds011_frame(chunk)
            if frame then
                latest_pm25 = frame.pm25
                latest_pm10 = frame.pm10
                samples = samples + 1
            end
        end

        local x_mv = joy_x:read()
        local y_mv = joy_y:read()
        local pressed = (gpio.get_level(JOY_SW_GPIO) == 0) and "YES" or "NO"
        local color = pm_color(latest_pm25)

        display.begin_frame({ clear = true, r = 12, g = 18, b = 28 })
        centered_text(10, "Air Console", { 245, 244, 238 }, 24)
        display.draw_line(12, 40, 228, 40, 60, 90, 120)

        draw_label_value(54, "PM2.5", latest_pm25 and string.format("%.1f ug/m3", latest_pm25) or "--", color)
        draw_label_value(80, "PM10", latest_pm10 and string.format("%.1f ug/m3", latest_pm10) or "--", color)
        draw_label_value(106, "Frames", tostring(samples), { 80, 190, 255 })
        draw_label_value(132, "MPU6050", imu_status, { 255, 190, 90 })
        draw_label_value(158, "Joy X", string.format("%d mV", x_mv), { 180, 220, 255 })
        draw_label_value(184, "Joy Y", string.format("%d mV", y_mv), { 180, 220, 255 })
        draw_label_value(210, "Joy SW", pressed, pressed == "YES" and { 235, 90, 90 } or { 88, 210, 124 })

        display.draw_text(12, 286, "30s live bring-up dashboard", {
            r = 180,
            g = 190,
            b = 205,
            font_size = 16,
        })
        display.present()
        display.end_frame()
        delay.delay_ms(250)
    end
end, debug.traceback)

cleanup()
if not run_ok then
    error(run_err)
end

print("[dashboard_air_console] done")
