local uart = require("uart")
local delay = require("delay")

local UART_PORT = 1
local UART_TX_GPIO = 17
local UART_RX_GPIO = 18
local UART_BAUD = 9600

local function parse_frame(s)
    if #s ~= 10 then
        return nil, "frame_len"
    end

    local b = { string.byte(s, 1, #s) }
    if b[1] ~= 0xAA or b[2] ~= 0xC0 or b[10] ~= 0xAB then
        return nil, "frame_markers"
    end

    local checksum = (b[3] + b[4] + b[5] + b[6] + b[7] + b[8]) % 256
    if checksum ~= b[9] then
        return nil, string.format("checksum expected=0x%02X got=0x%02X", checksum, b[9])
    end

    local pm25_raw = b[3] + b[4] * 256
    local pm10_raw = b[5] + b[6] * 256

    return {
        pm25 = pm25_raw / 10.0,
        pm10 = pm10_raw / 10.0,
        id = string.format("%02X%02X", b[8], b[7]),
    }
end

local ok, u = pcall(uart.new, UART_PORT, UART_TX_GPIO, UART_RX_GPIO, UART_BAUD)
if not ok then
    error("[sds011_parse] uart.new failed: " .. tostring(u))
end

u:flush_input()
print("[sds011_parse] waiting for parsed SDS011 frames")

local parsed = 0
for i = 1, 30 do
    local avail = u:available()
    if avail >= 10 then
        local chunk = u:read(10, 300)
        local frame, err = parse_frame(chunk)
        if frame then
            parsed = parsed + 1
            print(string.format(
                "[sds011_parse] frame=%d pm25=%.1f ug/m3 pm10=%.1f ug/m3 sensor_id=%s",
                parsed, frame.pm25, frame.pm10, frame.id
            ))
            if parsed >= 5 then
                break
            end
        else
            print(string.format("[sds011_parse] sample=%d parse_error=%s len=%d", i, err, #chunk))
        end
    else
        print(string.format("[sds011_parse] sample=%d waiting bytes=%d", i, avail))
    end
    delay.delay_ms(250)
end

u:close()
print("[sds011_parse] done")
