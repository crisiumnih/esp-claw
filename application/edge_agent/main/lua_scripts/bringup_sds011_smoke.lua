local uart = require("uart")
local delay = require("delay")

local UART_PORT = 1
local UART_TX_GPIO = 17
local UART_RX_GPIO = 18
local UART_BAUD = 9600

local function to_hex(s)
    local out = {}
    for i = 1, #s do
        out[#out + 1] = string.format("%02X", string.byte(s, i))
    end
    return table.concat(out, " ")
end

local ok, u = pcall(uart.new, UART_PORT, UART_TX_GPIO, UART_RX_GPIO, UART_BAUD)
if not ok then
    error("[sds011_smoke] uart.new failed: " .. tostring(u))
end

u:flush_input()
print("[sds011_smoke] waiting for UART data")

for i = 1, 20 do
    local avail = u:available()
    if avail > 0 then
        local n = avail
        if n > 64 then
            n = 64
        end
        local chunk = u:read(n, 200)
        print(string.format("[sds011_smoke] sample=%d bytes=%d hex=%s", i, #chunk, to_hex(chunk)))
    else
        print(string.format("[sds011_smoke] sample=%d no_data", i))
    end
    delay.delay_ms(250)
end

u:close()
print("[sds011_smoke] done")
