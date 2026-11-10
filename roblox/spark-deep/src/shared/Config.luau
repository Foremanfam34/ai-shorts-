-- Every tunable number in the game lives here.
-- This module is plain data (no Roblox types) so the tests can load it outside Roblox.

local Config = {}

Config.GameName = "+1 Spark"

-- Saving
Config.DataStoreName = "SparkDeepSave"
Config.DataVersion = 1
Config.AutosaveSeconds = 90

-- Hard ceiling for sparks and gems so numbers can never overflow.
Config.MaxValue = 1e18

-- Tapping
Config.MaxPulsesPerSecond = 14 -- the server ignores taps faster than this
Config.PulseBurst = 20
Config.HoldPulsesPerSecond = 6 -- how fast holding the button pulses

Config.BaseWalkSpeed = 20

-- The lantern grows with every power of ten of sparks.
Config.Lantern = {
	MinRange = 14,
	MaxRange = 60, -- the engine caps PointLight.Range at 60
	RangePerDecade = 5,
	MinBrightness = 1.5,
	MaxBrightness = 4.5,
	BrightnessPerDecade = 0.3,
}

-- Lantern colour for each rebirth tier (the last one repeats).
Config.LanternColors = {
	{ 255, 214, 130 },
	{ 130, 255, 170 },
	{ 120, 210, 255 },
	{ 215, 150, 255 },
	{ 255, 130, 170 },
	{ 255, 255, 255 },
}

-- Zones, from the camp outward. `required` is the sparks needed to pass the
-- gate; `gemValue` is what one crystal pays before multipliers.
Config.Zones = {
	{
		name = "Glowmoss Hollow",
		required = 25,
		gemValue = 1,
		crystal = { 120, 255, 140 },
		floor = { 38, 66, 44 },
		wall = { 44, 52, 46 },
		floorMaterial = "LeafyGrass",
		wallMaterial = "Slate",
	},
	{
		name = "Amber Tunnels",
		required = 300,
		gemValue = 5,
		crystal = { 255, 180, 60 },
		floor = { 96, 72, 46 },
		wall = { 70, 54, 38 },
		floorMaterial = "Sandstone",
		wallMaterial = "Rock",
	},
	{
		name = "Crystal Gallery",
		required = 3000,
		gemValue = 30,
		crystal = { 255, 110, 220 },
		floor = { 60, 58, 84 },
		wall = { 48, 44, 70 },
		floorMaterial = "Slate",
		wallMaterial = "Slate",
	},
	{
		name = "Mushroom Grotto",
		required = 25000,
		gemValue = 180,
		crystal = { 80, 240, 230 },
		floor = { 70, 52, 62 },
		wall = { 52, 40, 52 },
		floorMaterial = "Mud",
		wallMaterial = "Rock",
		feature = "mushrooms",
	},
	{
		name = "Sapphire Falls",
		required = 200000,
		gemValue = 1100,
		crystal = { 70, 140, 255 },
		floor = { 36, 46, 78 },
		wall = { 30, 36, 60 },
		floorMaterial = "Basalt",
		wallMaterial = "Basalt",
	},
	{
		name = "Echo Chasm",
		required = 1500000,
		gemValue = 7000,
		crystal = { 190, 160, 255 },
		floor = { 58, 58, 64 },
		wall = { 44, 44, 52 },
		floorMaterial = "Granite",
		wallMaterial = "Slate",
	},
	{
		name = "Magma Vein",
		required = 15000000,
		gemValue = 45000,
		crystal = { 255, 96, 40 },
		floor = { 96, 34, 22 },
		wall = { 52, 30, 28 },
		floorMaterial = "CrackedLava",
		wallMaterial = "Basalt",
	},
	{
		name = "Frost Hollow",
		required = 150000000,
		gemValue = 300000,
		crystal = { 170, 235, 255 },
		floor = { 150, 190, 220 },
		wall = { 110, 150, 190 },
		floorMaterial = "Glacier",
		wallMaterial = "Ice",
	},
	{
		name = "Starlit Abyss",
		required = 1500000000,
		gemValue = 2000000,
		crystal = { 255, 240, 170 },
		floor = { 16, 16, 32 },
		wall = { 14, 14, 26 },
		floorMaterial = "Basalt",
		wallMaterial = "Basalt",
		feature = "stars",
	},
	{
		name = "Heart of the Deep",
		required = 15000000000,
		gemValue = 14000000,
		crystal = { 255, 70, 150 },
		floor = { 44, 22, 54 },
		wall = { 36, 18, 44 },
		floorMaterial = "Marble",
		wallMaterial = "Slate",
		feature = "heart",
	},
}

-- Upgrades bought with gems. Cost of the next level = baseCost * costGrowth ^ level.
Config.UpgradeOrder = { "power", "auto", "gems", "speed" }
Config.Upgrades = {
	power = {
		name = "Bigger Sparks",
		icon = "✨",
		description = "More sparks every pulse",
		baseCost = 4,
		costGrowth = 1.33,
		maxLevel = 120,
		growth = 1.2, -- sparks per pulse = floor(growth ^ level + level)
	},
	auto = {
		name = "Auto Lantern",
		icon = "🔁",
		description = "Pulses by itself every second",
		baseCost = 40,
		costGrowth = 5,
		maxLevel = 10,
		perLevel = 1, -- automatic pulses per second, per level
	},
	gems = {
		name = "Gem Sense",
		icon = "💎",
		description = "Crystals pay more gems",
		baseCost = 20,
		costGrowth = 1.7,
		maxLevel = 40,
		perLevel = 0.25, -- +25% gems per level
	},
	speed = {
		name = "Swift Boots",
		icon = "👟",
		description = "Walk faster (kept when you rekindle)",
		baseCost = 60,
		costGrowth = 3,
		maxLevel = 12,
		perLevel = 1, -- +1 walk speed per level
		keepOnRebirth = true,
	},
}

-- Rebirth ("Rekindle"): reset sparks, gems and upgrades for a permanent boost.
Config.Rebirth = {
	BaseRequirement = 2500000,
	Growth = 9,
	SparkBonus = 1, -- +100% sparks per rebirth
	GemBonus = 0.5, -- +50% gems per rebirth
}

-- Optional game passes. Leave an id at 0 to switch that pass off.
-- Create passes on the Creator Dashboard, then paste their ids here.
Config.GamePasses = {
	DoubleSparks = 0,
	DoubleGems = 0,
}

Config.Crystals = {
	Columns = 3,
	Rows = 5,
	RespawnSeconds = 7,
}

-- Cave dimensions in studs. The cave is one long hall running along -Z:
-- the camp first, then each zone behind its gate.
Config.World = {
	Width = 84,
	Height = 34,
	CampLength = 90,
	ZoneLength = 112,
	WallThickness = 6,
	FloorThickness = 4,
	DoorWidth = 24,
	DoorHeight = 18,
}

return Config
