-- Unit tests for the shared rules (Format, Formulas, Profile) with the real Config.
--
--   rojo build -o SparkDeep.rbxl
--   lune run tests/unit.luau

local process = require("@lune/process")

local Harness = require("./harness")

local game = Harness.boot(process.args[1] or "SparkDeep.rbxl")
local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local Config = Harness.require(Shared:FindFirstChild("Config"))
local Format = Harness.require(Shared:FindFirstChild("Format"))
local Formulas = Harness.require(Shared:FindFirstChild("Formulas"))
local Profile = Harness.require(Shared:FindFirstChild("Profile"))

local checks, failures = 0, 0

local function check(condition: any, label: string)
	checks += 1
	if not condition then
		failures += 1
		print("  FAIL  " .. label)
	end
end

local function equal(actual: any, expected: any, label: string)
	check(actual == expected, string.format("%s (expected %s, got %s)", label, tostring(expected), tostring(actual)))
end

-- Format ---------------------------------------------------------------------

for _, case in ipairs({
	{ 0, "0" },
	{ 7, "7" },
	{ 999, "999" },
	{ 1000, "1K" },
	{ 1150, "1.15K" },
	{ 1250, "1.25K" },
	{ 1999, "1.99K" },
	{ 12500, "12.5K" },
	{ 99999, "99.9K" },
	{ 125000, "125K" },
	{ 999999, "999K" },
	{ 1000000, "1M" },
	{ 2500000, "2.5M" },
	{ 6000000000, "6B" },
	{ 1e12, "1T" },
	{ 1e15, "1Qa" },
	{ 1e18, "1Qi" },
	{ -1500, "-1.5K" },
	{ 0 / 0, "0" },
}) do
	equal(Format.abbreviate(case[1]), case[2], "abbreviate " .. tostring(case[1]))
end
equal(Format.multiplier(2), "x2", "multiplier whole")
equal(Format.multiplier(1.25), "x1.25", "multiplier fraction")
equal(Format.multiplier(1.5), "x1.5", "multiplier trims zeros")
equal(Format.multiplier(11), "x11", "multiplier two digits")

-- Config sanity --------------------------------------------------------------

local previousRequired, previousValue = 0, 0
for index, zone in ipairs(Config.Zones) do
	check(zone.required > previousRequired, "zone " .. index .. " needs more sparks than the one before")
	check(zone.gemValue > previousValue, "zone " .. index .. " pays more than the one before")
	check(#zone.crystal == 3 and #zone.floor == 3 and #zone.wall == 3, "zone " .. index .. " has full colours")
	previousRequired, previousValue = zone.required, zone.gemValue
end
for _, id in ipairs(Config.UpgradeOrder) do
	local definition = Config.Upgrades[id]
	check(definition ~= nil, "upgrade " .. id .. " is defined")
	local previousCost = 0
	for level = 0, definition.maxLevel - 1 do
		local cost = Formulas.upgradeCost(id, level)
		check(cost ~= nil and cost > previousCost, id .. " level " .. level .. " costs more than the level before")
		check(cost ~= nil and cost <= Config.MaxValue, id .. " level " .. level .. " is affordable under the value cap")
		previousCost = cost or previousCost
	end
	equal(Formulas.upgradeCost(id, definition.maxLevel), nil, id .. " has no price once maxed")
end
equal(Formulas.upgradeCost("nope", 0), nil, "unknown upgrade has no price")

-- Formulas -------------------------------------------------------------------

local previousPower = 0
for level = 0, Config.Upgrades.power.maxLevel do
	local power = Formulas.basePower(level)
	check(power > previousPower, "power level " .. level .. " is stronger than the level before")
	previousPower = power
end
equal(Formulas.basePower(0), 1, "first pulse is +1")

equal(Formulas.highestZone(0), 0, "no sparks: camp only")
equal(Formulas.highestZone(Config.Zones[1].required - 1), 0, "just short of zone 1")
equal(Formulas.highestZone(Config.Zones[1].required), 1, "exactly zone 1")
equal(Formulas.highestZone(Config.MaxValue), #Config.Zones, "max sparks opens everything")
equal(Formulas.nextZone(0), 1, "next zone from camp")
equal(Formulas.nextZone(Config.MaxValue), nil, "no next zone at the end")
equal(Formulas.zoneUnlocked(0, 0), true, "camp is always open")
equal(Formulas.zoneUnlocked(0, 1), false, "zone 1 starts locked")
equal(Formulas.zoneUnlocked(1e18, 99), false, "unknown zone is never open")

equal(Formulas.lanternRange(0), Config.Lantern.MinRange, "lantern minimum")
equal(Formulas.lanternRange(Config.MaxValue), Config.Lantern.MaxRange, "lantern maximum")
check(Formulas.lanternRange(1000) > Formulas.lanternRange(10), "lantern grows with sparks")
check(Formulas.rebirthRequirement(1) > Formulas.rebirthRequirement(0), "rebirths get harder")
equal(#Formulas.lanternColor(0), 3, "lantern colour for tier 0")
equal(Formulas.lanternColor(500), Config.LanternColors[#Config.LanternColors], "lantern colour clamps")

-- Profile --------------------------------------------------------------------

local fresh = Profile.new()
equal(fresh.sparks, 0, "new profile sparks")
equal(Formulas.sparksPerPulse(fresh, nil), 1, "new profile pulses +1")
equal(Formulas.walkSpeed(fresh), Config.BaseWalkSpeed, "new profile walk speed")

equal(Profile.pulse(fresh, 1, nil), 1, "one pulse gains one spark")
equal(Profile.pulse(fresh, 0, nil), 0, "zero pulses gain nothing")
equal(Profile.pulse(fresh, -5, nil), 0, "negative pulses gain nothing")
equal(Profile.pulse(fresh, 3, { sparkBoost = 2, gemBoost = 1 }), 6, "spark boost doubles pulses")
equal(fresh.sparks, 7, "sparks accumulate")
equal(fresh.totalSparks, 7, "lifetime sparks accumulate")

equal(Profile.collect(fresh, 1, nil), nil, "cannot collect behind a locked gate")
fresh.sparks = Config.Zones[1].required
equal(Profile.collect(fresh, 1, nil), Config.Zones[1].gemValue, "collect pays the zone value")
equal(Profile.collect(fresh, 2, nil), nil, "next zone still locked")
equal(Profile.collect(fresh, 0, nil), nil, "the camp has no crystals")
equal(Profile.collect(fresh, "1", nil), nil, "bad zone index is rejected")
equal(Profile.collect(fresh, 1, { sparkBoost = 1, gemBoost = 2 }), Config.Zones[1].gemValue * 2, "gem boost doubles crystals")

local shopper = Profile.new()
local okBuy, reason = Profile.buyUpgrade(shopper, "power")
equal(okBuy, false, "cannot buy with no gems")
equal(reason, "gems", "reason is gems")
shopper.gems = Formulas.upgradeCost("power", 0)
equal(Profile.buyUpgrade(shopper, "power"), true, "buys with exactly enough gems")
equal(shopper.gems, 0, "gems are spent")
equal(shopper.upgrades.power, 1, "level goes up")
equal(select(2, Profile.buyUpgrade(shopper, "teleport")), "unknown", "unknown upgrade rejected")
equal(select(2, Profile.buyUpgrade(shopper, 42)), "unknown", "non-string upgrade rejected")
equal(select(2, Profile.buyUpgrade(shopper, nil)), "unknown", "missing upgrade rejected")
shopper.upgrades.auto = Config.Upgrades.auto.maxLevel
shopper.gems = Config.MaxValue
equal(select(2, Profile.buyUpgrade(shopper, "auto")), "maxed", "maxed upgrade rejected")
equal(Formulas.autoPulsesPerSecond(shopper), Config.Upgrades.auto.maxLevel * Config.Upgrades.auto.perLevel, "auto pulses per second")

local veteran = Profile.new()
equal(Profile.rebirth(veteran), false, "cannot rebirth at zero")
veteran.sparks = Formulas.rebirthRequirement(0)
veteran.gems = 500
veteran.upgrades = { power = 30, auto = 4, gems = 9, speed = 5 }
equal(Profile.rebirth(veteran), true, "rebirth at the requirement")
equal(veteran.rebirths, 1, "rebirth counted")
equal(veteran.sparks, 0, "rebirth resets sparks")
equal(veteran.gems, 0, "rebirth resets gems")
equal(veteran.upgrades.power, 0, "rebirth resets power")
equal(veteran.upgrades.speed, 5, "rebirth keeps swift boots")
equal(Formulas.sparksPerPulse(veteran, nil), 2, "one rebirth doubles sparks")
equal(Profile.rebirth(veteran), false, "second rebirth needs sparks again")

-- A capped profile never overflows.
local capped = Profile.new()
capped.sparks = Config.MaxValue
capped.gems = Config.MaxValue
capped.upgrades.power = Config.Upgrades.power.maxLevel
Profile.pulse(capped, 1000, { sparkBoost = 2, gemBoost = 2 })
Profile.collect(capped, #Config.Zones, { sparkBoost = 2, gemBoost = 2 })
equal(capped.sparks, Config.MaxValue, "sparks stop at the cap")
equal(capped.gems, Config.MaxValue, "gems stop at the cap")

-- Sanitize: whatever the data store returns, the result is a valid profile.
for _, raw in ipairs({ false, 5, "text", {}, { sparks = "many" }, { upgrades = 3 }, { sparks = -5, gems = 0 / 0 } }) do
	local clean = Profile.sanitize(raw)
	equal(clean.sparks, 0, "sanitize junk: sparks")
	equal(clean.gems, 0, "sanitize junk: gems")
	equal(clean.upgrades.power, 0, "sanitize junk: upgrades")
end
equal(Profile.sanitize(nil).rebirths, 0, "sanitize nil gives a new profile")

local restored = Profile.sanitize({
	sparks = 12345.9,
	gems = math.huge,
	rebirths = 3,
	upgrades = { power = 9999, auto = 2, hacked = 50 },
	bestZone = 99,
	totalSparks = 5,
})
equal(restored.sparks, 12345, "sanitize floors numbers")
equal(restored.gems, Config.MaxValue, "sanitize caps infinity")
equal(restored.rebirths, 3, "sanitize keeps rebirths")
equal(restored.upgrades.power, Config.Upgrades.power.maxLevel, "sanitize caps upgrade levels")
equal(restored.upgrades.auto, 2, "sanitize keeps valid levels")
equal(restored.upgrades.hacked, nil, "sanitize drops unknown upgrades")
equal(restored.upgrades.speed, 0, "sanitize fills missing upgrades")
equal(restored.bestZone, #Config.Zones, "sanitize caps best zone")
equal(restored.totalSparks, 12345, "lifetime sparks never below current sparks")

if failures > 0 then
	print(string.format("\nUNIT TESTS FAILED: %d of %d checks failed", failures, checks))
	process.exit(1)
end
print(string.format("UNIT TESTS PASSED: %d checks", checks))
process.exit(0)
