-- The client's read-only copy of the player's progress.
-- The server publishes progress as attributes on the Player; this module
-- mirrors them into a table shaped like the server's profile so the shared
-- Formulas work on both sides.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

local State = {}

State.loaded = false
State.profile = { sparks = 0, gems = 0, rebirths = 0, bestZone = 0, upgrades = {} :: { [string]: number } }
State.perks = { sparkBoost = 1, gemBoost = 1 }

local listeners: { () -> () } = {}

local function numberAttribute(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function read()
	local profile = State.profile
	profile.sparks = numberAttribute("Sparks", 0)
	profile.gems = numberAttribute("Gems", 0)
	profile.rebirths = numberAttribute("Rebirths", 0)
	profile.bestZone = numberAttribute("BestZone", 0)
	for _, id in ipairs(Config.UpgradeOrder) do
		profile.upgrades[id] = numberAttribute("Upgrade_" .. id, 0)
	end
	State.perks.sparkBoost = numberAttribute("SparkBoost", 1)
	State.perks.gemBoost = numberAttribute("GemBoost", 1)
	State.loaded = player:GetAttribute("Loaded") == true
end

-- Calls `callback` every time anything in the state changes.
function State.onChanged(callback: () -> ())
	table.insert(listeners, callback)
end

function State.start()
	read()
	player.AttributeChanged:Connect(function()
		read()
		for _, callback in ipairs(listeners) do
			callback()
		end
	end)
end

return State
