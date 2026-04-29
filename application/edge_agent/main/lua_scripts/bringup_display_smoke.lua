local bm = require("board_manager")
local display = require("display")
local delay = require("delay")

local function fail(msg)
    error("[display_smoke] " .. msg)
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

width = display.width()
height = display.height()
if width <= 0 or height <= 0 then
    pcall(display.deinit)
    fail("invalid display size: " .. tostring(width) .. "x" .. tostring(height))
end

pcall(display.backlight, true)

display.begin_frame({ clear = true, r = 255, g = 0, b = 0 })
display.draw_text(12, 12, "RED", { r = 255, g = 255, b = 255, font_size = 24 })
display.present()
delay.delay_ms(1000)
display.end_frame()

display.begin_frame({ clear = true, r = 0, g = 255, b = 0 })
display.draw_text(12, 12, "GREEN", { r = 0, g = 0, b = 0, font_size = 24 })
display.present()
delay.delay_ms(1000)
display.end_frame()

display.begin_frame({ clear = true, r = 0, g = 0, b = 255 })
display.draw_text(12, 12, "BLUE", { r = 255, g = 255, b = 255, font_size = 24 })
display.present()
delay.delay_ms(1000)
display.end_frame()

pcall(display.deinit)
print(string.format("[display_smoke] ok %dx%d", width, height))
