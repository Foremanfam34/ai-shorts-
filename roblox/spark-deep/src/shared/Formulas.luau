-- Pure maths for the economy. Used by the server (authoritative) and by the
-- client (to preview numbers), and exercised directly by the tests.

local Config = require(script.Parent.Config)

local Formulas = {}

export type Perks = { sparkBoost: number, gemBoost: number }

local function upgradeLevel(profile, id: string): number
	local upgrades = profile.upgrades
	return (upgrades and upgrades[id]) or 0
end
Formulas.upgradeLevel = upgradeLevel

-- Gems for the next level of an upgrade, or nil when it is maxed (or unknown).
function Formulas.upgradeCost(id: string, currentLevel: number): number?
	local definition = Config.Upgrades[id]
	if not definition or currentLevel >= definition.maxLevel then
		return nil
	end
	return math.floor(definition.baseCost * definition.costGrowth ^ currentLevel + 0.5)
end

function Formulas.basePower(powerLevel: number): number
	return math.floor(Config.Upgrades.power.growth ^ powerLevel + powerLevel)
end

function Formulas.rebirthSparkMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.SparkBonus
end

function Formulas.rebirthGemMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.GemBonus
end

function Formulas.sparksPerPulse(profile, perks: Perks?): number
	local boost = if perks then perks.sparkBoost else 1
	local amount = Formulas.basePower(upgradeLevel(profile, "power"))
		* Formulas.rebirthSparkMultiplier(profile.rebirths)
		* boost
	return math.max(1, math.floor(amount))
end

function Formulas.autoPulsesPerSecond(profile): number
	return upgradeLevel(profile, "auto") * Config.Upgrades.auto.perLevel
end

function Formulas.gemMultiplier(profile, perks: Perks?): number
	local boost = if perks then perks.gemBoost else 1
	return (1 + upgradeLevel(profile, "gems") * Config.Upgrades.gems.perLevel)
		* Formulas.rebirthGemMultiplier(profile.rebirths)
		* boost
end

function Formulas.gemsForCrystal(profile, zoneIndex: number, perks: Perks?): number
	local zone = Config.Zones[zoneIndex]
	if not zone then
		return 0
	end
	return math.max(1, math.floor(zone.gemValue * Formulas.gemMultiplier(profile, perks)))
end

function Formulas.walkSpeed(profile): number
	return Config.BaseWalkSpeed + upgradeLevel(profile, "speed") * Config.Upgrades.speed.perLevel
end

function Formulas.rebirthRequirement(rebirths: number): number
	return math.floor(Config.Rebirth.BaseRequirement * Config.Rebirth.Growth ^ rebirths + 0.5)
end

-- Zone 0 is the camp and is always open.
function Formulas.zoneUnlocked(sparks: number, zoneIndex: number): boolean
	if zoneIndex == 0 then
		return true
	end
	local zone = Config.Zones[zoneIndex]
	return zone ~= nil and sparks >= zone.required
end

-- The deepest zone this many sparks can enter (0 = only the camp).
function Formulas.highestZone(sparks: number): number
	local highest = 0
	for index, zone in ipairs(Config.Zones) do
		if sparks >= zone.required then
			highest = index
		else
			break
		end
	end
	return highest
end

-- Index of the first locked zone, or nil when everything is open.
function Formulas.nextZone(sparks: number): number?
	local nextIndex = Formulas.highestZone(sparks) + 1
	if Config.Zones[nextIndex] then
		return nextIndex
	end
	return nil
end

function Formulas.lanternRange(sparks: number): number
	local lantern = Config.Lantern
	local decades = math.log10(math.max(sparks, 0) + 1)
	return math.clamp(lantern.MinRange + lantern.RangePerDecade * decades, lantern.MinRange, lantern.MaxRange)
end

function Formulas.lanternBrightness(sparks: number): number
	local lantern = Config.Lantern
	local decades = math.log10(math.max(sparks, 0) + 1)
	return math.clamp(
		lantern.MinBrightness + lantern.BrightnessPerDecade * decades,
		lantern.MinBrightness,
		lantern.MaxBrightness
	)
end

function Formulas.lanternColor(rebirths: number): { number }
	local colors = Config.LanternColors
	return colors[math.clamp(rebirths + 1, 1, #colors)]
end

return Formulas
