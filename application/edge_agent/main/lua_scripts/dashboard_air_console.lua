local bm = require("board_manager")
local display = require("display")
local delay = require("delay")
local adc = require("adc")
local gpio = require("gpio")
local system = require("system")
local button = require("button")
local bmp388 = require("lib_bmp388")

local JOY_X_GPIO = 1
local JOY_Y_GPIO = 2
local JOY_SW_GPIO = 21
local LED_GPIO = 38
local BTN_GPIO = 16
local LDR_GPIO = 4

local BMP_I2C_PORT = 0
local BMP_SDA_GPIO = 41
local BMP_SCL_GPIO = 42
local BMP_FREQ_HZ = 400000

local JOY_LOW_MV = 900
local JOY_HIGH_MV = 2400
local JOY_NEUTRAL_LOW_MV = 1250
local JOY_NEUTRAL_HIGH_MV = 2050
local LOOP_DELAY_MS = 120
local LOOP_COUNT = 900
local SENSOR_REFRESH_EVERY = 5

local function fail(msg)
    error("[dashboard_air_console] " .. msg)
end

local function color(r, g, b)
    return { r, g, b }
end

local BG = color(248, 249, 251)
local TEXT = color(36, 44, 55)
local MUTED = color(108, 118, 132)
local LINE = color(214, 220, 228)
local BLUE = color(60, 118, 192)
local BLUE_DARK = color(44, 96, 164)
local GOOD = color(72, 158, 92)
local WARN = color(215, 136, 62)
local BAD = color(205, 85, 85)

local PAGES = {
    { id = "home", title = "Home" },
    { id = "light", title = "Light" },
    { id = "sense", title = "Sense" },
    { id = "wifi", title = "Wi-Fi" },
    { id = "inputs", title = "Stick" },
}

local MENU_ITEMS = {
    { title = "Light", page = 2, icon = "light" },
    { title = "Sense", page = 3, icon = "sense" },
    { title = "Wi-Fi", page = 4, icon = "wifi" },
    { title = "Stick", page = 5, icon = "stick" },
}

local function draw_text(x, y, text, rgb, font_size)
    display.draw_text(x, y, text, {
        r = rgb[1],
        g = rgb[2],
        b = rgb[3],
        font_size = font_size,
    })
end

local function draw_centered(y, text, rgb, font_size)
    local tw = display.measure_text(text, { font_size = font_size })
    local x = math.floor((display.width() - tw) / 2)
    draw_text(x, y, text, rgb, font_size)
end

local function draw_card(x, y, w, h, accent, active)
    local shadow = active and color(224, 232, 242) or color(236, 240, 244)
    local fill = active and color(255, 255, 255) or color(252, 253, 255)
    local border = active and accent or LINE

    display.fill_round_rect(x + 2, y + 3, w, h, 12, shadow[1], shadow[2], shadow[3])
    display.fill_round_rect(x, y, w, h, 12, fill[1], fill[2], fill[3])
    display.draw_round_rect(x, y, w, h, 12, border[1], border[2], border[3])
end

local function draw_header(title, subtitle)
    draw_centered(14, title, TEXT, 24)
    draw_centered(40, subtitle, MUTED, 15)
    display.draw_line(18, 64, 222, 64, LINE[1], LINE[2], LINE[3])
end

local function draw_footer(text)
    draw_text(12, 300, text, MUTED, 14)
end

local function draw_action_button(x, y, w, h, label, active)
    local fill = active and BLUE_DARK or BLUE
    local border = active and color(29, 73, 132) or color(52, 104, 174)
    display.fill_round_rect(x, y, w, h, 8, fill[1], fill[2], fill[3])
    display.draw_round_rect(x, y, w, h, 8, border[1], border[2], border[3])
    display.draw_text_aligned(x, y + 6, w, h - 6, label, {
        r = 248,
        g = 250,
        b = 253,
        font_size = 20,
    })
end

local function draw_metric_row(y, label, value, rgb)
    draw_text(36, y, label, MUTED, 15)
    draw_text(132, y, value, rgb or TEXT, 18)
end

local function draw_wifi_icon(x, y, rgb)
    display.fill_circle(x - 10, y + 10, 4, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x - 2, y + 2, 6, 12, 3, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x + 8, y - 8, 6, 22, 3, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x + 18, y - 18, 6, 32, 3, rgb[1], rgb[2], rgb[3])
end

local function draw_stick_icon(x, y, rgb)
    display.draw_circle(x, y, 16, rgb[1], rgb[2], rgb[3])
    display.draw_line(x, y + 14, x, y - 12, rgb[1], rgb[2], rgb[3])
    display.fill_circle(x, y - 16, 7, rgb[1], rgb[2], rgb[3])
    display.fill_circle(x - 20, y, 3, rgb[1], rgb[2], rgb[3])
    display.fill_circle(x + 20, y, 3, rgb[1], rgb[2], rgb[3])
    display.fill_circle(x, y - 20, 3, rgb[1], rgb[2], rgb[3])
    display.fill_circle(x, y + 20, 3, rgb[1], rgb[2], rgb[3])
end

local function draw_light_icon(x, y, rgb)
    display.fill_circle(x, y - 10, 12, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x - 7, y, 14, 14, 4, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x - 4, y + 15, 8, 6, 2, rgb[1], rgb[2], rgb[3])
end

local function draw_sense_icon(x, y, rgb)
    display.draw_circle(x, y, 18, rgb[1], rgb[2], rgb[3])
    display.fill_circle(x, y, 5, rgb[1], rgb[2], rgb[3])
    display.draw_line(x, y, x + 12, y - 10, rgb[1], rgb[2], rgb[3])
    display.fill_circle(x + 12, y - 10, 3, rgb[1], rgb[2], rgb[3])
end

local function draw_menu_icon(kind, x, y, rgb)
    if kind == "wifi" then
        draw_wifi_icon(x, y, rgb)
    elseif kind == "stick" then
        draw_stick_icon(x, y, rgb)
    elseif kind == "sense" then
        draw_sense_icon(x, y, rgb)
    else
        draw_light_icon(x, y, rgb)
    end
end

local function axis_dir(mv)
    if mv <= JOY_LOW_MV then
        return -1
    end
    if mv >= JOY_HIGH_MV then
        return 1
    end
    if mv >= JOY_NEUTRAL_LOW_MV and mv <= JOY_NEUTRAL_HIGH_MV then
        return 0
    end
    return nil
end

local function clamp(v, lo, hi)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
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

local joy_x = adc.new(JOY_X_GPIO)
local joy_y = adc.new(JOY_Y_GPIO)
local ldr = adc.new(LDR_GPIO)
local tactile, tactile_err = button.new(BTN_GPIO, 0)
if not tactile then
    fail("button.new failed: " .. tostring(tactile_err))
end
local bmp, bmp_err = bmp388.new({
    port = BMP_I2C_PORT,
    sda = BMP_SDA_GPIO,
    scl = BMP_SCL_GPIO,
    frequency = BMP_FREQ_HZ,
})

gpio.set_direction(JOY_SW_GPIO, "input")
gpio.set_direction(LED_GPIO, "output")
gpio.set_level(LED_GPIO, 0)

local state = {
    screen = 1,
    menu_index = 1,
    raw_x = 0,
    raw_y = 0,
    raw_sw = 1,
    raw_btn = 1,
    last_event = "idle",
    x_latched = false,
    y_latched = false,
    light_on = false,
    light_origin = "boot",
    ldr_mv = 0,
    bmp_ok = bmp ~= nil,
    bmp_addr = bmp and bmp:address() or nil,
    bmp_error = bmp_err,
    temp_c = nil,
    pressure_hpa = nil,
}

local function cleanup()
    pcall(function() joy_x:close() end)
    pcall(function() joy_y:close() end)
    pcall(function() ldr:close() end)
    if tactile then
        pcall(button.off, tactile)
        pcall(button.close, tactile)
    end
    if bmp then
        pcall(function() bmp:close() end)
    end
    pcall(display.deinit)
end

local function apply_light(origin)
    gpio.set_level(LED_GPIO, state.light_on and 1 or 0)
    if origin then
        state.light_origin = origin
    end
end

local function set_light(on, origin)
    state.light_on = on and true or false
    apply_light(origin)
end

local function toggle_light(origin)
    set_light(not state.light_on, origin)
end

button.on(tactile, "press_down", function()
    set_light(true, "btn")
end)

button.on(tactile, "press_up", function()
    set_light(false, "btn")
end)

local function read_wifi_snapshot()
    local info = system.info()
    local ip = system.ip()
    local ssid = info and info.wifi_ssid or nil
    local rssi = info and info.wifi_rssi or nil
    local uptime_s = info and info.uptime_s or 0

    return {
        ssid = ssid or "(no STA)",
        ip = ip or "(no IP)",
        rssi = rssi and string.format("%d dBm", rssi) or "(n/a)",
        uptime = string.format("%ds", uptime_s or 0),
        now = info and info.date or system.date("%H:%M:%S"),
        online = ip ~= nil,
    }
end

local function refresh_sensors()
    state.ldr_mv = ldr:read()

    local btn_level = button.get_key_level(tactile)
    if btn_level ~= nil then
        state.raw_btn = btn_level
    end

    if bmp then
        local sample, serr = bmp:read()
        if sample then
            state.bmp_ok = true
            state.bmp_error = nil
            state.temp_c = sample.temperature_c
            state.pressure_hpa = sample.pressure_hpa
        else
            state.bmp_ok = false
            state.bmp_error = serr
        end
    end
end

local function next_nav_event(x_mv, y_mv)
    local x_dir = axis_dir(x_mv)
    local y_dir = axis_dir(y_mv)

    if x_dir == 0 then
        state.x_latched = false
    end
    if y_dir == 0 then
        state.y_latched = false
    end

    if y_dir == -1 and not state.y_latched then
        state.y_latched = true
        return "up"
    end
    if y_dir == 1 and not state.y_latched then
        state.y_latched = true
        return "down"
    end
    if x_dir == -1 and not state.x_latched then
        state.x_latched = true
        return "left"
    end
    if x_dir == 1 and not state.x_latched then
        state.x_latched = true
        return "right"
    end

    return nil
end

local function handle_nav(event)
    if not event then
        return
    end

    state.last_event = event

    if state.screen == 1 then
        if event == "up" then
            state.menu_index = clamp(state.menu_index - 1, 1, #MENU_ITEMS)
        elseif event == "down" then
            state.menu_index = clamp(state.menu_index + 1, 1, #MENU_ITEMS)
        elseif event == "right" then
            state.screen = MENU_ITEMS[state.menu_index].page
        end
        return
    end

    if event == "left" then
        state.screen = 1
        return
    end

    if state.screen == 2 and event == "right" then
        toggle_light("joy")
        return
    end

    if event == "up" then
        state.screen = state.screen - 1
        if state.screen < 2 then
            state.screen = #PAGES
        end
    elseif event == "down" then
        state.screen = state.screen + 1
        if state.screen > #PAGES then
            state.screen = 2
        end
    end
end

local function temp_text()
    if state.temp_c == nil then
        return "--"
    end
    return string.format("%.1fC", state.temp_c)
end

local function pressure_text()
    if state.pressure_hpa == nil then
        return "--"
    end
    return string.format("%.1fhPa", state.pressure_hpa)
end

local function ldr_text()
    return string.format("%dmV", state.ldr_mv or 0)
end

local function light_text()
    return state.light_on and "ON" or "OFF"
end

local function draw_home_page(wifi)
    draw_header("ESP Home", wifi.ssid)
    draw_metric_row(82, "Temp", temp_text(), state.bmp_ok and TEXT or WARN)
    draw_metric_row(108, "Press", pressure_text(), state.bmp_ok and TEXT or WARN)
    draw_metric_row(134, "LDR", ldr_text(), TEXT)
    draw_metric_row(160, "Light", light_text(), state.light_on and GOOD or BAD)

    for i, item in ipairs(MENU_ITEMS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 18 + col * 104
        local y = 208 + row * 50
        local active = (state.menu_index == i)
        draw_text(x + 32, y - 16, item.title, MUTED, 13)
        draw_action_button(x + 24, y, 66, 34, item.title, active)
        draw_menu_icon(item.icon, x, y + 17, active and BLUE or MUTED)
    end

    draw_footer("UP/DN  RIGHT")
end

local function draw_light_page()
    draw_header("Light", "btn or right")
    draw_card(16, 84, 208, 128, state.light_on and GOOD or BAD, true)
    draw_centered(104, "Mock Light", TEXT, 18)
    draw_action_button(54, 134, 132, 42, light_text(), state.light_on)
    draw_centered(194, "Src: " .. state.light_origin, MUTED, 15)
    draw_metric_row(236, "LED", "GPIO38", TEXT)
    draw_metric_row(262, "BTN", "GPIO16", TEXT)
    draw_footer("LEFT  RIGHT")
end

local function draw_sense_page()
    draw_header("Sense", state.bmp_ok and "BMP388" or "BMP off")
    draw_card(16, 84, 208, 164, state.bmp_ok and GOOD or WARN, true)
    draw_metric_row(104, "Temp", temp_text(), state.bmp_ok and TEXT or WARN)
    draw_metric_row(132, "Press", pressure_text(), state.bmp_ok and TEXT or WARN)
    draw_metric_row(160, "LDR", ldr_text(), TEXT)
    draw_metric_row(188, "Addr", state.bmp_addr and string.format("0x%02X", state.bmp_addr) or "--", TEXT)
    draw_metric_row(216, "I2C", "41/42", TEXT)
    draw_footer("LEFT  UP/DN")
end

local function draw_wifi_page(wifi)
    draw_header("Wi-Fi", wifi.online and "online" or "offline")
    draw_card(16, 82, 208, 146, wifi.online and GOOD or WARN, true)
    draw_centered(98, wifi.ssid, TEXT, 18)
    draw_centered(124, wifi.ip, wifi.online and GOOD or WARN, 18)
    draw_centered(148, "RSSI: " .. wifi.rssi, TEXT, 16)
    draw_centered(172, "Up: " .. wifi.uptime, TEXT, 16)
    draw_centered(196, wifi.now, MUTED, 15)
    draw_action_button(64, 244, 112, 34, wifi.online and "ON" or "WAIT", true)
    draw_footer("LEFT  UP/DN")
end

local function draw_inputs_page()
    local joy_sw_text = (state.raw_sw == 0) and "DOWN" or "UP"
    local btn_text = (state.raw_btn == 0) and "DOWN" or "UP"

    draw_header("Stick", "raw")
    draw_card(16, 82, 208, 170, BLUE, true)
    draw_stick_icon(54, 130, BLUE)
    draw_text(96, 98, "X", MUTED, 15)
    draw_text(132, 98, tostring(state.raw_x), TEXT, 18)
    draw_text(96, 126, "Y", MUTED, 15)
    draw_text(132, 126, tostring(state.raw_y), TEXT, 18)
    draw_text(96, 154, "SW", MUTED, 15)
    draw_text(132, 154, joy_sw_text, state.raw_sw == 0 and BAD or GOOD, 18)
    draw_text(96, 182, "BTN", MUTED, 15)
    draw_text(132, 182, btn_text, state.raw_btn == 0 and BAD or GOOD, 18)
    draw_text(96, 210, "EV", MUTED, 15)
    draw_text(96, 232, state.last_event, BLUE_DARK, 17)
    draw_footer("LEFT  UP/DN")
end

local function render()
    local wifi = read_wifi_snapshot()

    display.begin_frame({ clear = true, r = BG[1], g = BG[2], b = BG[3] })

    if state.screen == 1 then
        draw_home_page(wifi)
    elseif state.screen == 2 then
        draw_light_page()
    elseif state.screen == 3 then
        draw_sense_page()
    elseif state.screen == 4 then
        draw_wifi_page(wifi)
    else
        draw_inputs_page()
    end

    display.present()
    display.end_frame()
end

local run_ok, run_err = xpcall(function()
    refresh_sensors()

    for i = 1, LOOP_COUNT do
        button.dispatch()

        state.raw_x = joy_x:read()
        state.raw_y = joy_y:read()
        state.raw_sw = gpio.get_level(JOY_SW_GPIO)

        handle_nav(next_nav_event(state.raw_x, state.raw_y))

        if (i % SENSOR_REFRESH_EVERY) == 0 then
            refresh_sensors()
        end

        render()
        delay.delay_ms(LOOP_DELAY_MS)
    end
end, debug.traceback)

cleanup()
if not run_ok then
    error(run_err)
end

print("[dashboard_air_console] done")
