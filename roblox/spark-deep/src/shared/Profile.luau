-- A player's saved progress and every rule that changes it.
-- Nothing in here touches Roblox instances, so the rules can be tested alone.

local Config = require(script.Parent.Config)
local Formulas = require(script.Parent.Formulas)

local Profile = {}

export type Profile = {
	version: number,
	sparks: number,
	gems: number,
	rebirths: number,
	upgrades: { [string]: number },
	bestZone: number,
	totalSparks: number,
	playSeconds: number,
}

function Profile.new(): Profile
	local upgrades = {}
	for _, id in ipairs(Config.UpgradeOrder) do
		upgrades[id] = 0
	end
	return {
		version = Config.DataVersion,
		sparks = 0,
		gems = 0,
		rebirths = 0,
		upgrades = upgrades,
		bestZone = 0,
		totalSparks = 0,
		playSeconds = 0,
	}
end

local function cleanNumber(value: any, maximum: number): number
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return math.min(math.floor(value), maximum)
end

-- Turns whatever came out of the data store into a valid profile.
function Profile.sanitize(raw: any): Profile
	local profile = Profile.new()
	if type(raw) ~= "table" then
		return profile
	end

	profile.sparks = cleanNumber(raw.sparks, Config.MaxValue)
	profile.gems = cleanNumber(raw.gems, Config.MaxValue)
	profile.rebirths = cleanNumber(raw.rebirths, 1000)
	profile.totalSparks = math.max(cleanNumber(raw.totalSparks, Config.MaxValue), profile.sparks)
	profile.playSeconds = cleanNumber(raw.playSeconds, Config.MaxValue)

	if type(raw.upgrades) == "table" then
		for _, id in ipairs(Config.UpgradeOrder) do
			profile.upgrades[id] = cleanNumber(raw.upgrades[id], Config.Upgrades[id].maxLevel)
		end
	end

	profile.bestZone = math.max(
		math.min(cleanNumber(raw.bestZone, #Config.Zones), #Config.Zones),
		Formulas.highestZone(profile.sparks)
	)
	return profile
end

-- Adds `pulses` pulses worth of sparks. Returns the sparks gained.
function Profile.pulse(profile: Profile, pulses: number, perks: Formulas.Perks?): number
	if pulses <= 0 then
		return 0
	end
	local before = profile.sparks
	local gained = Formulas.sparksPerPulse(profile, perks) * pulses
	profile.sparks = math.min(before + gained, Config.MaxValue)
	profile.totalSparks = math.min(profile.totalSparks + gained, Config.MaxValue)
	profile.bestZone = math.max(profile.bestZone, Formulas.highestZone(profile.sparks))
	return profile.sparks - before
end

-- Buys one level. Returns true, or false plus a reason ("unknown", "maxed", "gems").
function Profile.buyUpgrade(profile: Profile, id: any): (boolean, string?)
	if type(id) ~= "string" or Config.Upgrades[id] == nil then
		return false, "unknown"
	end
	local level = profile.upgrades[id] or 0
	local cost = Formulas.upgradeCost(id, level)
	if cost == nil then
		return false, "maxed"
	end
	if profile.gems < cost then
		return false, "gems"
	end
	profile.gems -= cost
	profile.upgrades[id] = level + 1
	return true, nil
end

function Profile.canRebirth(profile: Profile): boolean
	return profile.sparks >= Formulas.rebirthRequirement(profile.rebirths)
end

-- Resets sparks, gems and upgrades in exchange for one rebirth.
function Profile.rebirth(profile: Profile): boolean
	if not Profile.canRebirth(profile) then
		return false
	end
	profile.rebirths += 1
	profile.sparks = 0
	profile.gems = 0
	for _, id in ipairs(Config.UpgradeOrder) do
		if not Config.Upgrades[id].keepOnRebirth then
			profile.upgrades[id] = 0
		end
	end
	return true
end

-- Collects one crystal in a zone. Returns the gems gained, or nil if the
-- player's lantern is not bright enough for that zone.
function Profile.collect(profile: Profile, zoneIndex: any, perks: Formulas.Perks?): number?
	if type(zoneIndex) ~= "number" or Config.Zones[zoneIndex] == nil then
		return nil
	end
	if not Formulas.zoneUnlocked(profile.sparks, zoneIndex) then
		return nil
	end
	local before = profile.gems
	profile.gems = math.min(before + Formulas.gemsForCrystal(profile, zoneIndex, perks), Config.MaxValue)
	return profile.gems - before
end

return Profile
