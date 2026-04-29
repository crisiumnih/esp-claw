local bm = require("board_manager")
local display = require("display")
local delay = require("delay")
local adc = require("adc")
local gpio = require("gpio")
local system = require("system")

local JOY_X_GPIO = 1
local JOY_Y_GPIO = 2
local JOY_SW_GPIO = 21

local JOY_LOW_MV = 900
local JOY_HIGH_MV = 2400
local JOY_NEUTRAL_LOW_MV = 1250
local JOY_NEUTRAL_HIGH_MV = 2050
local LOOP_DELAY_MS = 120
local LOOP_COUNT = 600

local PAGES = {
    { id = "home", title = "Switchboard", kind = "menu" },
    { id = "wifi", title = "Wi-Fi", kind = "wifi" },
    { id = "inputs", title = "Inputs", kind = "inputs" },
    { id = "future", title = "Future Devices", kind = "future" },
}

local function fail(msg)
    error("[dashboard_air_console] " .. msg)
end

local function color(r, g, b)
    return { r, g, b }
end

local MENU_ITEMS = {
    { title = "Wi-Fi", hint = "net", page = 2, accent = color(92, 214, 128), icon = "wifi" },
    { title = "Stick", hint = "joy", page = 3, accent = color(88, 186, 255), icon = "stick" },
    { title = "Ctrl", hint = "io", page = 4, accent = color(255, 207, 104), icon = "grid" },
}

local BG = color(248, 249, 251)
local TEXT = color(36, 44, 55)
local MUTED = color(108, 118, 132)
local LINE = color(214, 220, 228)
local BLUE = color(60, 118, 192)
local BLUE_DARK = color(44, 96, 164)
local BLUE_SOFT = color(224, 235, 248)
local GOOD = color(72, 158, 92)
local WARN = color(215, 136, 62)

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

local function draw_badge(x, y, w, label, rgb)
    display.fill_round_rect(x, y, w, 24, 10, 24, 46, 72)
    display.draw_round_rect(x, y, w, 24, 10, rgb[1], rgb[2], rgb[3])
    display.draw_text_aligned(x, y + 2, w, 20, label, {
        r = rgb[1],
        g = rgb[2],
        b = rgb[3],
        font_size = 15,
    })
end

local function draw_wifi_icon(x, y, rgb)
    display.fill_circle(x - 10, y + 10, 4, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x - 2, y + 2, 6, 12, 3, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x + 8, y - 8, 6, 22, 3, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x + 18, y - 18, 6, 32, 3, rgb[1], rgb[2], rgb[3])
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

local function draw_metric_value(y, label, value)
    draw_centered(y, label .. ": " .. value, TEXT, 18)
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

local function draw_grid_icon(x, y, rgb)
    display.fill_round_rect(x - 16, y - 16, 12, 12, 3, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x + 4, y - 16, 12, 12, 3, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x - 16, y + 4, 12, 12, 3, rgb[1], rgb[2], rgb[3])
    display.fill_round_rect(x + 4, y + 4, 12, 12, 3, rgb[1], rgb[2], rgb[3])
end

local function draw_menu_icon(kind, x, y, rgb)
    if kind == "wifi" then
        draw_wifi_icon(x, y, rgb)
    elseif kind == "stick" then
        draw_stick_icon(x, y, rgb)
    else
        draw_grid_icon(x, y, rgb)
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
gpio.set_direction(JOY_SW_GPIO, "input")

local state = {
    screen = 1,
    menu_index = 1,
    raw_x = 0,
    raw_y = 0,
    raw_sw = 1,
    last_event = "idle",
    x_latched = false,
    y_latched = false,
}

local function cleanup()
    pcall(function() joy_x:close() end)
    pcall(function() joy_y:close() end)
    pcall(display.deinit)
end

local function read_wifi_snapshot()
    local info = system.info()
    local ip = system.ip()
    local ssid = info and info.wifi_ssid or nil
    local rssi = info and info.wifi_rssi or nil
    local uptime_s = info and info.uptime_s or 0
    local status = "STA offline"
    local status_color = color(240, 166, 68)

    if ip and ssid then
        status = "STA connected"
        status_color = color(92, 214, 128)
    elseif ip then
        status = "IP ready"
        status_color = color(92, 214, 128)
    end

    return {
        ssid = ssid or "(not associated)",
        ip = ip or "(no STA IP)",
        rssi = rssi and string.format("%d dBm", rssi) or "(unknown)",
        uptime = string.format("%ds", uptime_s or 0),
        status = status,
        status_color = status_color,
        now = info and info.date or system.date("%H:%M:%S"),
    }
end

local function next_nav_event(x_mv, y_mv, sw_level)
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

local function draw_home_page(wifi)
    local net_label = wifi.ip ~= "(no STA IP)" and "Connected" or "Waiting"
    draw_header("ESP32 Home", wifi.ssid)
    draw_metric_value(82, "Temp", "--")
    draw_metric_value(108, "Hum", "--")
    draw_metric_value(134, "LDR", "--")
    draw_centered(158, "Wi-Fi: " .. net_label, wifi.ip ~= "(no STA IP)" and GOOD or WARN, 16)

    local card_y = 196
    for i, item in ipairs(MENU_ITEMS) do
        local active = (state.menu_index == i)
        draw_text(28, card_y - 16, item.title, MUTED, 13)
        draw_action_button(64, card_y, 112, 34, "OFF", active)
        draw_menu_icon(item.icon, 30, card_y + 17, active and BLUE or MUTED)
        card_y = card_y + 42
    end

    draw_footer("UP/DOWN  RIGHT")
end

local function draw_kv(y, label, value, rgb)
    draw_text(16, y, label, color(156, 174, 194), 16)
    draw_text(112, y, value, rgb, 16)
end

local function draw_wifi_page(wifi)
    draw_header("Wi-Fi", wifi.ip ~= "(no STA IP)" and "online" or "offline")
    draw_card(16, 82, 208, 146, wifi.ip ~= "(no STA IP)" and GOOD or WARN, true)
    draw_centered(98, wifi.ssid, TEXT, 18)
    draw_centered(124, wifi.ip, wifi.ip ~= "(no STA IP)" and GOOD or WARN, 18)
    draw_centered(148, "RSSI: " .. wifi.rssi, TEXT, 16)
    draw_centered(172, "Up: " .. wifi.uptime, TEXT, 16)
    draw_centered(196, wifi.now, MUTED, 15)
    draw_action_button(64, 244, 112, 34, wifi.ip ~= "(no STA IP)" and "ON" or "WAIT", true)
    draw_footer("LEFT  UP/DOWN")
end

local function draw_inputs_page()
    local sw_text = (state.raw_sw == 0) and "DOWN" or "UP"
    local sw_color = (state.raw_sw == 0) and color(255, 140, 140) or color(92, 214, 128)

    draw_header("Stick", "joy")
    draw_card(16, 82, 208, 170, BLUE, true)
    draw_stick_icon(54, 130, BLUE)
    draw_text(96, 100, "X", MUTED, 15)
    draw_text(132, 100, tostring(state.raw_x), TEXT, 18)
    draw_text(96, 130, "Y", MUTED, 15)
    draw_text(132, 130, tostring(state.raw_y), TEXT, 18)
    draw_text(96, 160, "SW", MUTED, 15)
    draw_text(132, 160, sw_text, sw_color, 18)
    draw_text(96, 190, "EV", MUTED, 15)
    draw_text(96, 212, state.last_event, BLUE_DARK, 17)
    draw_footer("LEFT  UP/DOWN")
end

local function draw_future_page()
    local items = {
        { label = "Light", value = "OFF" },
        { label = "Fan", value = "OFF" },
        { label = "TV", value = "OFF" },
    }
    draw_header("Control", "demo")
    draw_metric_value(82, "Temp", "--")
    draw_metric_value(106, "Hum", "--")
    draw_metric_value(130, "LDR", "--")

    local y = 172
    for _, item in ipairs(items) do
        draw_text(72, y - 16, item.label, MUTED, 12)
        draw_action_button(64, y, 112, 34, item.value, false)
        y = y + 44
    end

    draw_footer("LEFT  HOME")
end

local function render()
    local wifi = read_wifi_snapshot()

    display.begin_frame({ clear = true, r = BG[1], g = BG[2], b = BG[3] })

    if state.screen == 1 then
        draw_home_page(wifi)
    elseif state.screen == 2 then
        draw_wifi_page(wifi)
    elseif state.screen == 3 then
        draw_inputs_page()
    else
        draw_future_page()
    end

    display.present()
    display.end_frame()
end

local run_ok, run_err = xpcall(function()
    for _ = 1, LOOP_COUNT do
        state.raw_x = joy_x:read()
        state.raw_y = joy_y:read()
        state.raw_sw = gpio.get_level(JOY_SW_GPIO)

        handle_nav(next_nav_event(state.raw_x, state.raw_y, state.raw_sw))
        render()
        delay.delay_ms(LOOP_DELAY_MS)
    end
end, debug.traceback)

cleanup()
if not run_ok then
    error(run_err)
end

print("[dashboard_air_console] done")
