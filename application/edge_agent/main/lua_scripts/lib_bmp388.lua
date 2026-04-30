local i2c = require("i2c")
local delay = require("delay")

local M = {}

local DEFAULT_FREQ_HZ = 400000
local DEFAULT_ADDRS = { 0x76, 0x77 }

local REG_CHIP_ID = 0x00
local REG_PRESS_MSB_LSB_XLSB = 0x04
local REG_PWR_CTRL = 0x1B
local REG_CMD = 0x7E
local REG_CALIB_START = 0x31

local CHIP_ID = 0x50
local CMD_SOFT_RESET = 0xB6
local PWR_CTRL_NORMAL_PT = 0x33

local mt = {}
mt.__index = mt

local function u16le(data, idx)
    local lo = string.byte(data, idx) or 0
    local hi = string.byte(data, idx + 1) or 0
    return lo | (hi << 8)
end

local function s8(data, idx)
    local v = string.byte(data, idx) or 0
    if v >= 0x80 then
        return v - 0x100
    end
    return v
end

local function s16le(data, idx)
    local v = u16le(data, idx)
    if v >= 0x8000 then
        return v - 0x10000
    end
    return v
end

local function u24le(data, idx)
    local b0 = string.byte(data, idx) or 0
    local b1 = string.byte(data, idx + 1) or 0
    local b2 = string.byte(data, idx + 2) or 0
    return b0 | (b1 << 8) | (b2 << 16)
end

local function new_device_from_opts(opts)
    local bus
    local owns_bus = false

    if opts.bus ~= nil then
        bus = opts.bus
    else
        bus = i2c.new(
            assert(opts.port, "bmp388.new: missing 'port'"),
            assert(opts.sda, "bmp388.new: missing 'sda'"),
            assert(opts.scl, "bmp388.new: missing 'scl'"),
            opts.frequency or opts.freq_hz or DEFAULT_FREQ_HZ
        )
        owns_bus = opts.owns_bus ~= false
    end

    local addrs = opts.addr and { opts.addr } or DEFAULT_ADDRS
    for _, addr in ipairs(addrs) do
        local dev = bus:device(addr)
        local ok, chip_id = pcall(dev.read_byte, dev, REG_CHIP_ID)
        if ok and chip_id == CHIP_ID then
            return bus, dev, owns_bus, addr
        end
        pcall(dev.close, dev)
    end

    if owns_bus and bus then
        bus:close()
    end
    return nil, nil, false, nil
end

local function convert_calibration(raw)
    local nvm_par_t1 = u16le(raw, 1)
    local nvm_par_t2 = u16le(raw, 3)
    local nvm_par_t3 = s8(raw, 5)
    local nvm_par_p1 = s16le(raw, 6)
    local nvm_par_p2 = s16le(raw, 8)
    local nvm_par_p3 = s8(raw, 10)
    local nvm_par_p4 = s8(raw, 11)
    local nvm_par_p5 = u16le(raw, 12)
    local nvm_par_p6 = u16le(raw, 14)
    local nvm_par_p7 = s8(raw, 16)
    local nvm_par_p8 = s8(raw, 17)
    local nvm_par_p9 = s16le(raw, 18)
    local nvm_par_p10 = s8(raw, 20)
    local nvm_par_p11 = s8(raw, 21)

    return {
        par_t1 = nvm_par_t1 / (2 ^ -8),
        par_t2 = nvm_par_t2 / (2 ^ 30),
        par_t3 = nvm_par_t3 / (2 ^ 48),
        par_p1 = (nvm_par_p1 - (2 ^ 14)) / (2 ^ 20),
        par_p2 = (nvm_par_p2 - (2 ^ 14)) / (2 ^ 29),
        par_p3 = nvm_par_p3 / (2 ^ 32),
        par_p4 = nvm_par_p4 / (2 ^ 37),
        par_p5 = nvm_par_p5 / (2 ^ -3),
        par_p6 = nvm_par_p6 / (2 ^ 6),
        par_p7 = nvm_par_p7 / (2 ^ 8),
        par_p8 = nvm_par_p8 / (2 ^ 15),
        par_p9 = nvm_par_p9 / (2 ^ 48),
        par_p10 = nvm_par_p10 / (2 ^ 48),
        par_p11 = nvm_par_p11 / (2 ^ 65),
        t_lin = 0.0,
    }
end

local function compensate_temperature(uncomp_temp, calib)
    local partial_data1 = uncomp_temp - calib.par_t1
    local partial_data2 = partial_data1 * calib.par_t2
    calib.t_lin = partial_data2 + (partial_data1 * partial_data1) * calib.par_t3
    return calib.t_lin
end

local function compensate_pressure(uncomp_press, calib)
    local partial_data1 = calib.par_p6 * calib.t_lin
    local partial_data2 = calib.par_p7 * (calib.t_lin * calib.t_lin)
    local partial_data3 = calib.par_p8 * (calib.t_lin * calib.t_lin * calib.t_lin)
    local partial_out1 = calib.par_p5 + partial_data1 + partial_data2 + partial_data3

    partial_data1 = calib.par_p2 * calib.t_lin
    partial_data2 = calib.par_p3 * (calib.t_lin * calib.t_lin)
    partial_data3 = calib.par_p4 * (calib.t_lin * calib.t_lin * calib.t_lin)
    local partial_out2 = uncomp_press * (calib.par_p1 + partial_data1 + partial_data2 + partial_data3)

    partial_data1 = uncomp_press * uncomp_press
    partial_data2 = calib.par_p9 + calib.par_p10 * calib.t_lin
    partial_data3 = partial_data1 * partial_data2
    local partial_data4 = partial_data3 + (uncomp_press * uncomp_press * uncomp_press) * calib.par_p11
    return partial_out1 + partial_out2 + partial_data4
end

function M.new(opts)
    opts = type(opts) == "table" and opts or {}

    local bus, dev, owns_bus, addr = new_device_from_opts(opts)
    if not dev then
        return nil, "BMP388 not found at 0x76 or 0x77"
    end

    dev:write_byte(CMD_SOFT_RESET, REG_CMD)
    delay.delay_ms(5)
    dev:write_byte(PWR_CTRL_NORMAL_PT, REG_PWR_CTRL)
    delay.delay_ms(20)

    local raw_calib = dev:read(21, REG_CALIB_START)
    if #raw_calib ~= 21 then
        dev:close()
        if owns_bus and bus then
            bus:close()
        end
        return nil, "BMP388 calibration read failed"
    end

    return setmetatable({
        _bus = bus,
        _dev = dev,
        _owns_bus = owns_bus,
        _addr = addr,
        _calib = convert_calibration(raw_calib),
    }, mt)
end

function mt:address()
    return self._addr
end

function mt:read()
    local raw = self._dev:read(6, REG_PRESS_MSB_LSB_XLSB)
    if #raw ~= 6 then
        return nil, "BMP388 data read failed"
    end

    local uncomp_press = u24le(raw, 1)
    local uncomp_temp = u24le(raw, 4)
    local temp_c = compensate_temperature(uncomp_temp, self._calib)
    local pressure_pa = compensate_pressure(uncomp_press, self._calib)

    return {
        address = self._addr,
        temperature_c = temp_c,
        pressure_pa = pressure_pa,
        pressure_hpa = pressure_pa / 100.0,
    }
end

function mt:close()
    if self._dev then
        self._dev:close()
        self._dev = nil
    end
    if self._owns_bus and self._bus then
        self._bus:close()
        self._bus = nil
    end
end

function mt:__gc()
    pcall(function()
        self:close()
    end)
end

return M
