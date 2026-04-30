local adc = require("adc")
local delay = require("delay")
local gpio = require("gpio")
local system = require("system")
local bmp388 = require("lib_bmp388")
local capability = require("capability")
local state_store = require("lib_home_state")
local mcpwm_ok, mcpwm = pcall(require, "mcpwm")
local rc522_ok, rc522 = pcall(require, "rc522")

local LED_GPIO = 38
local LDR_GPIO = 4
local SERVO_GPIO = 15
local SERVO_FREQ_HZ = 50
local SERVO_LOCK_DUTY = 11.5
local SERVO_UNLOCK_DUTY = 6.5

local BMP_I2C_PORT = 0
local BMP_SDA_GPIO = 41
local BMP_SCL_GPIO = 42
local BMP_FREQ_HZ = 400000

local RFID_SCK_GPIO = 5
local RFID_MOSI_GPIO = 6
local RFID_MISO_GPIO = 7
local RFID_CS_GPIO = 8
local RFID_RST_GPIO = 9

local a = type(args) == "table" and args or {}

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$") or ""
end

local function normalize(value)
    return string.lower(trim(value))
end

local function canonicalize_command(value)
    local cmd = normalize(value)
    cmd = cmd:gsub("^lua%s+", "")
    return cmd
end

local function reply(text)
    print(text)
    if type(a.chat_id) == "string" and a.chat_id ~= "" and type(a.channel) == "string" and a.channel ~= "" then
        local cap_name = a.channel == "telegram" and "tg_send_message" or nil
        if cap_name then
            pcall(function()
                capability.call(cap_name, {
                    message = text,
                }, {
                    channel = a.channel,
                    chat_id = a.chat_id,
                    source_cap = "lua_script",
                })
            end)
        end
    end
end

local function wifi_snapshot()
    local info = system.info()
    local ip = system.ip()
    return {
        ssid = (info and info.wifi_ssid) or "(no STA)",
        ip = ip or "(no IP)",
        rssi = info and info.wifi_rssi or nil,
        online = ip ~= nil,
    }
end

local function init_led()
    gpio.set_direction(LED_GPIO, "output")
end

local function set_light_level(on)
    init_led()
    gpio.set_level(LED_GPIO, on and 1 or 0)
end

local function with_servo(fn)
    if not mcpwm_ok then
        return nil, "mcpwm unavailable"
    end

    local ok_new, servo_or_err = pcall(mcpwm.new, {
        gpio = SERVO_GPIO,
        frequency_hz = SERVO_FREQ_HZ,
        duty_percent = SERVO_LOCK_DUTY,
        resolution_hz = 1000000,
    })
    if not ok_new then
        return nil, tostring(servo_or_err)
    end

    local servo = servo_or_err
    local ok_start, start_err = pcall(function()
        servo:start()
    end)
    if not ok_start then
        pcall(function() servo:close() end)
        return nil, tostring(start_err)
    end
    local ok, out1, out2 = pcall(fn, servo)
    pcall(function() servo:stop() end)
    pcall(function() servo:close() end)
    if not ok then
        return nil, tostring(out1)
    end
    return out1, out2
end

local function move_lock(locked)
    local duty = locked and SERVO_LOCK_DUTY or SERVO_UNLOCK_DUTY
    local _, err = with_servo(function(servo)
        servo:set_duty(duty)
        delay.delay_ms(900)
    end)
    return err
end

local function read_bmp_sample()
    local sensor, err = bmp388.new({
        port = BMP_I2C_PORT,
        sda = BMP_SDA_GPIO,
        scl = BMP_SCL_GPIO,
        frequency = BMP_FREQ_HZ,
    })
    if not sensor then
        return nil, err
    end

    local sample, serr = sensor:read()
    sensor:close()
    return sample, serr
end

local function read_ldr_mv()
    local ldr = adc.new(LDR_GPIO)
    local value = ldr:read()
    ldr:close()
    return value
end

local function read_rfid_uid()
    if not rc522_ok then
        return nil, tostring(rc522)
    end

    local ok_reader, reader_or_err = pcall(rc522.new, {
        host = 2,
        sck = RFID_SCK_GPIO,
        mosi = RFID_MOSI_GPIO,
        miso = RFID_MISO_GPIO,
        cs = RFID_CS_GPIO,
        rst = RFID_RST_GPIO,
        clock_hz = 1000000,
    })
    if not ok_reader then
        return nil, tostring(reader_or_err)
    end

    local reader = reader_or_err
    local uid = reader:read_uid()
    pcall(function() reader:close() end)
    return uid, nil
end

local function save_state(state)
    local ok, err = state_store.save(state)
    if not ok then
        error("state save failed: " .. tostring(err))
    end
end

local function handle_light(command, state)
    if command == "light on" or command == "turn on light" then
        state.light_on = true
        state.light_origin = "tg"
        set_light_level(true)
        save_state(state)
        return "Light is ON."
    end
    if command == "light off" or command == "turn off light" then
        state.light_on = false
        state.light_origin = "tg"
        set_light_level(false)
        save_state(state)
        return "Light is OFF."
    end
    if command == "light toggle" or command == "toggle light" then
        state.light_on = not state.light_on
        state.light_origin = "tg"
        set_light_level(state.light_on)
        save_state(state)
        return string.format("Light toggled to %s.", state.light_on and "ON" or "OFF")
    end
    if command == "light status" then
        return string.format("Light is %s.", state.light_on and "ON" or "OFF")
    end
    return nil
end

local function handle_lock(command, state)
    if command == "door open" or command == "open door" then
        local err = move_lock(false)
        if err then
            return "Door open failed: " .. tostring(err)
        end
        state.servo_locked = false
        state.servo_last = "tg-open"
        save_state(state)
        return "Door is OPEN."
    end
    if command == "door close" or command == "close door" then
        local err = move_lock(true)
        if err then
            return "Door close failed: " .. tostring(err)
        end
        state.servo_locked = true
        state.servo_last = "tg-close"
        save_state(state)
        return "Door is LOCKED."
    end
    if command == "door toggle" or command == "toggle door" then
        local new_locked = not state.servo_locked
        local err = move_lock(new_locked)
        if err then
            return "Door toggle failed: " .. tostring(err)
        end
        state.servo_locked = new_locked
        state.servo_last = "tg-toggle"
        save_state(state)
        return string.format("Door toggled to %s.", new_locked and "LOCKED" or "OPEN")
    end
    if command == "door status" then
        return string.format("Door is %s.", state.servo_locked and "LOCKED" or "OPEN")
    end
    return nil
end

local function handle_sensors(command, state)
    if command == "temperature" or command == "pressure" or command == "status" then
        local sample, err = read_bmp_sample()
        if sample then
            if command == "temperature" then
                return string.format("Temperature: %.1f C", sample.temperature_c)
            end
            if command == "pressure" then
                return string.format("Pressure: %.1f hPa", sample.pressure_hpa)
            end
            state.last_temp_c = sample.temperature_c
            state.last_pressure_hpa = sample.pressure_hpa
        elseif command ~= "status" then
            return "BMP388 read failed: " .. tostring(err)
        end
    end

    if command == "ldr" then
        return string.format("LDR: %d mV", read_ldr_mv())
    end

    if command == "rfid status" then
        local uid, err = read_rfid_uid()
        if uid then
            state.rfid_uid = uid
            state.rfid_last = "tag"
            save_state(state)
            return "RFID UID: " .. uid
        end
        state.rfid_last = "idle"
        save_state(state)
        if err then
            return "RFID idle (" .. tostring(err) .. ")"
        end
        return "RFID idle."
    end

    if command == "wifi status" then
        local wifi = wifi_snapshot()
        local rssi = wifi.rssi and string.format("%d dBm", wifi.rssi) or "n/a"
        return string.format("Wi-Fi: %s\nIP: %s\nRSSI: %s", wifi.ssid, wifi.ip, rssi)
    end

    if command == "status" then
        local wifi = wifi_snapshot()
        local ldr_mv = read_ldr_mv()
        local uid, _ = read_rfid_uid()
        if uid then
            state.rfid_uid = uid
            state.rfid_last = "tag"
            save_state(state)
        end
        return string.format(
            "ESP Home\nLight: %s\nDoor: %s\nTemp: %s\nPressure: %s\nLDR: %d mV\nWi-Fi: %s\nIP: %s\nRFID: %s",
            state.light_on and "ON" or "OFF",
            state.servo_locked and "LOCKED" or "OPEN",
            state.last_temp_c and string.format("%.1f C", state.last_temp_c) or "--",
            state.last_pressure_hpa and string.format("%.1f hPa", state.last_pressure_hpa) or "--",
            ldr_mv,
            wifi.ssid,
            wifi.ip,
            uid or state.rfid_uid or "--"
        )
    end

    return nil
end

local function main()
    local command = canonicalize_command(a.command or a.text or "")
    if command == "" then
        error("args.command is required")
    end

    local state = state_store.load()
    local response = handle_light(command, state)
    if not response then
        response = handle_lock(command, state)
    end
    if not response then
        response = handle_sensors(command, state)
    end
    if not response then
        response = "Unknown device command."
    end

    reply(response)
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
    error(err)
end
