local rc522 = require("rc522")
local delay = require("delay")

local reader = rc522.new({
    host = 2,
    sck = 5,
    mosi = 6,
    miso = 7,
    cs = 8,
    rst = 9,
    clock_hz = 1000000,
})

print(string.format("[rc522_smoke] version=0x%02X", reader:version()))
print("[rc522_smoke] tap a tag within 15 seconds")

local last_uid = nil
for _ = 1, 150 do
    local uid = reader:read_uid()
    if uid and uid ~= last_uid then
        print("[rc522_smoke] uid=" .. uid)
        last_uid = uid
    end
    delay.delay_ms(100)
end

reader:close()
print("[rc522_smoke] done")
