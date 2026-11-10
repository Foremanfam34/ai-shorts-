-- Economy simulation: plays the real rules with a simple bot and prints when
-- each zone opens, so pacing can be tuned in Config without guessing.
--
--   rojo build -o SparkDeep.rbxl
--   lune run tests/sim.luau            (rekindles as soon as it can)
--   lune run tests/sim.luau never      (never rekindles)
--
-- The bot holds the pulse button most of the time, farms crystals in the
-- deepest open zone, and always buys the cheapest upgrade it can afford.

local process = require("@lune/process")

local Harness = require("./harness")

local game = Harness.boot("SparkDeep.rbxl")
local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local Config = Harness.require(Shared:FindFirstChild("Config"))
local Format = Harness.require(Shared:FindFirstChild("Format"))
local Formulas = Harness.require(Shared:FindFirstChild("Formulas"))
local Profile = Harness.require(Shared:FindFirstChild("Profile"))

local neverRebirth = process.args[1] == "never"

local PULSES_PER_SECOND = Config.HoldPulsesPerSecond * 0.7 -- holding 70% of the time
local CRYSTALS_PER_SECOND = 0.5 -- walking between crystals, menus, etc.
local HOURS = 6

local function clock(seconds: number): string
	return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
end

local profile = Profile.new()
local pulseBank, crystalBank = 0, 0
local reachedThisRun = 0
local deepestEver = 0
local lastRebirthAt = 0

print(string.format("%-9s %-28s %s", "time", "event", "state"))

local function state(): string
	return string.format(
		"power %d  auto %d  gems-up %d  speed %d  | +%s/pulse  %s gems",
		profile.upgrades.power,
		profile.upgrades.auto,
		profile.upgrades.gems,
		profile.upgrades.speed,
		Format.abbreviate(Formulas.sparksPerPulse(profile, nil)),
		Format.abbreviate(profile.gems)
	)
end

for second = 1, HOURS * 3600 do
	pulseBank += PULSES_PER_SECOND + Formulas.autoPulsesPerSecond(profile)
	local pulses = math.floor(pulseBank)
	pulseBank -= pulses
	Profile.pulse(profile, pulses, nil)

	local zone = Formulas.highestZone(profile.sparks)
	if zone > 0 then
		crystalBank += CRYSTALS_PER_SECOND
		while crystalBank >= 1 do
			crystalBank -= 1
			Profile.collect(profile, zone, nil)
		end
	end

	-- Buy the cheapest affordable upgrade until nothing is affordable.
	while true do
		local cheapestId, cheapestCost = nil, math.huge
		for _, id in ipairs(Config.UpgradeOrder) do
			local cost = Formulas.upgradeCost(id, profile.upgrades[id])
			if cost and cost <= profile.gems and cost < cheapestCost then
				cheapestId, cheapestCost = id, cost
			end
		end
		if not cheapestId then
			break
		end
		Profile.buyUpgrade(profile, cheapestId)
	end

	if zone > reachedThisRun then
		reachedThisRun = zone
		local marker = if zone > deepestEver then "NEW " else ""
		deepestEver = math.max(deepestEver, zone)
		print(string.format("%-9s %-28s %s", clock(second), marker .. "zone " .. zone .. " " .. Config.Zones[zone].name, state()))
	end

	if not neverRebirth and Profile.canRebirth(profile) then
		print(string.format("%-9s %-28s (run took %s)", clock(second), "REKINDLE #" .. (profile.rebirths + 1), clock(second - lastRebirthAt)))
		Profile.rebirth(profile)
		reachedThisRun = 0
		lastRebirthAt = second
	end
end

print(string.format("\nafter %d hours: deepest zone %d of %d, %d rekindles", HOURS, deepestEver, #Config.Zones, profile.rebirths))
process.exit(0)
