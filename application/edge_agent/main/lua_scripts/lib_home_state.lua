local M = {}

local STATE_FILE = "/fatfs/scripts/home_state.txt"

local DEFAULTS = {
    light_on = false,
    light_origin = "boot",
    servo_locked = true,
    servo_last = "boot",
    rfid_uid = "--",
    rfid_last = "idle",
}

local function clone_defaults()
    local out = {}
    for k, v in pairs(DEFAULTS) do
        out[k] = v
    end
    return out
end

local function decode_value(key, value)
    if key == "light_on" or key == "servo_locked" then
        return value == "1" or value == "true"
    end
    return value
end

local function encode_value(value)
    if type(value) == "boolean" then
        return value and "1" or "0"
    end
    if value == nil then
        return ""
    end
    return tostring(value)
end

function M.load()
    local state = clone_defaults()
    local file = io.open(STATE_FILE, "r")
    if not file then
        return state
    end

    for line in file:lines() do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key and DEFAULTS[key] ~= nil then
            state[key] = decode_value(key, value)
        end
    end

    file:close()
    return state
end

function M.save(partial)
    local state = clone_defaults()
    if type(partial) == "table" then
        for k, v in pairs(partial) do
            if DEFAULTS[k] ~= nil then
                state[k] = v
            end
        end
    end

    local file, err = io.open(STATE_FILE, "w")
    if not file then
        return false, err
    end

    local keys = {
        "light_on",
        "light_origin",
        "servo_locked",
        "servo_last",
        "rfid_uid",
        "rfid_last",
    }

    for _, key in ipairs(keys) do
        file:write(string.format("%s=%s\n", key, encode_value(state[key])))
    end

    file:close()
    return true
end

function M.defaults()
    return clone_defaults()
end

return M
