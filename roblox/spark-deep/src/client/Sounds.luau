-- Tiny sound player. These are placeholder sounds that ship with Roblox;
-- swap in your own audio by replacing a path with "rbxassetid://<your id>".

local SoundService = game:GetService("SoundService")

local DEFINITIONS = {
	pulse = { id = "rbxasset://sounds/clickfast.wav", volume = 0.25 },
	collect = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.45 },
	buy = { id = "rbxasset://sounds/button.wav", volume = 0.5 },
	unlock = { id = "rbxasset://sounds/victory.wav", volume = 0.5 },
	denied = { id = "rbxasset://sounds/switch.wav", volume = 0.4 },
}

local Sounds = {}

local sounds: { [string]: Sound } = {}

function Sounds.start()
	for name, definition in pairs(DEFINITIONS) do
		local sound = Instance.new("Sound")
		sound.Name = "Spark_" .. name
		sound.SoundId = definition.id
		sound.Volume = definition.volume
		sound.Parent = SoundService
		sounds[name] = sound
	end
end

-- `pitch` is optional (1 = normal).
function Sounds.play(name: string, pitch: number?)
	local sound = sounds[name]
	if not sound then
		return
	end
	sound.PlaybackSpeed = pitch or 1
	sound:Play()
end

return Sounds
