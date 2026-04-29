local audio = require("audio")
local bm = require("board_manager")
local delay = require("delay")

local function open_output()
    local names = { "audio_dac" }

    for _, name in ipairs(names) do
        local codec, rate, channels, bits = bm.get_audio_codec_output_params(name)
        if codec then
            local output, err = audio.new_output(codec, rate, channels, bits)
            if output then
                return output, name, rate, channels, bits
            end
            print("[audio_tone_smoke] new_output(" .. name .. ") failed: " .. tostring(err))
        else
            print("[audio_tone_smoke] get_audio_codec_output_params(" .. name .. ") failed: " .. tostring(rate))
        end
    end

    return nil, nil, nil, nil, nil
end

local output, name, rate, channels, bits = open_output()
if not output then
    error("[audio_tone_smoke] no usable audio output")
end

print(string.format(
    "[audio_tone_smoke] output=%s %dHz/%dch/%dbit",
    name,
    rate,
    channels,
    bits
))

audio.set_volume(output, 90)
audio.play_tone(output, 523, 120, 90, true)
delay.delay_ms(80)
audio.play_tone(output, 659, 120, 90, true)
delay.delay_ms(80)
audio.play_tone(output, 784, 180, 90, true)

audio.close(output)
print("[audio_tone_smoke] done")
