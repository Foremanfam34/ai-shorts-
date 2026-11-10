-- Builds the whole cave out of plain parts when the server starts.
-- Nothing is placed by hand in Studio: change Config (sizes, colours, zones)
-- and the map follows.
--
-- Layout: one long hall running along -Z. The camp sits at z = 0..CampLength,
-- then zone 1, zone 2, ... each behind a gate wall. +Y is up, the floor is y = 0.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

local World = {}

export type Crystal = {
	zone: number,
	active: boolean,
	hitbox: BasePart,
	visuals: { BasePart },
	light: PointLight,
}

export type Built = {
	folder: Folder,
	campSpawn: CFrame,
	zoneSpawns: { [number]: CFrame },
	crystals: { Crystal },
}

local W = Config.World
local HALF_WIDTH = W.Width / 2
local HEIGHT = W.Height
local WALL = W.WallThickness
local FLOOR = W.FloorThickness
local HALF_DOOR = W.DoorWidth / 2
local GATE_HALF_DEPTH = 2

local SIGN_FONT = Enum.Font.FredokaOne

-- Small deterministic random generator (Park-Miller), so the cave is identical
-- on every server and in the tests.
local function makeRandom(seed: number)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(low: number, high: number): number
		state = (state * 48271) % 2147483647
		return low + (high - low) * ((state - 1) / 2147483646)
	end
end

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function scaleColor(color: { number }, factor: number): Color3
	return Color3.fromRGB(
		math.clamp(math.floor(color[1] * factor), 0, 255),
		math.clamp(math.floor(color[2] * factor), 0, 255),
		math.clamp(math.floor(color[3] * factor), 0, 255)
	)
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

-- Start of zone `index` (its gate), where zone 0 is the camp. Zones run toward -Z.
local function zoneStartZ(index: number): number
	return -(index - 1) * W.ZoneLength
end

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, partMaterial: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = partMaterial
	return part
end

-- An axis-aligned block described by its two opposite corners.
local function box(
	parent: Instance,
	name: string,
	minCorner: Vector3,
	maxCorner: Vector3,
	color: Color3,
	partMaterial: Enum.Material
): Part
	local part = newPart(name, maxCorner - minCorner, CFrame.new((minCorner + maxCorner) / 2), color, partMaterial)
	part.Parent = parent
	return part
end

-- Decoration that players walk straight through and that never fires touches.
local function ghost(part: BasePart): BasePart
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	return part
end

local function pointLight(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	return light
end

-- An upright cylinder standing on the floor at (x, z).
local function pillar(
	parent: Instance,
	name: string,
	x: number,
	z: number,
	baseY: number,
	height: number,
	diameter: number,
	color: Color3,
	partMaterial: Enum.Material
): Part
	local part = newPart(
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(x, baseY + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		partMaterial
	)
	part.Shape = Enum.PartType.Cylinder
	part.Parent = parent
	return part
end

local function ball(
	parent: Instance,
	name: string,
	position: Vector3,
	diameter: number,
	color: Color3,
	partMaterial: Enum.Material
): Part
	local part = newPart(name, Vector3.new(diameter, diameter, diameter), CFrame.new(position), color, partMaterial)
	part.Shape = Enum.PartType.Ball
	part.Parent = parent
	return part
end

-- A camera-facing sign measured in studs. `lines` is a list of
-- { name, text, color, heightFraction }.
local function sign(
	parent: Instance,
	name: string,
	width: number,
	height: number,
	offset: Vector3,
	lines: { { any } }
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.MaxDistance = 260

	local y = 0
	for _, line in ipairs(lines) do
		local label = Instance.new("TextLabel")
		label.Name = line[1]
		label.Text = line[2]
		label.TextColor3 = line[3]
		label.Size = UDim2.new(1, 0, line[4], 0)
		label.Position = UDim2.new(0, 0, y, 0)
		label.BackgroundTransparency = 1
		label.Font = SIGN_FONT
		label.TextScaled = true
		label.TextStrokeTransparency = 0.2
		label.TextStrokeColor3 = Color3.fromRGB(10, 8, 20)
		label.Parent = gui
		y += line[4]
	end

	gui.Parent = parent
	return gui
end

-- Floor, both side walls and ceiling for one stretch of the hall.
local function buildShell(
	parent: Instance,
	zMin: number,
	zMax: number,
	floorColor: Color3,
	floorMaterial: Enum.Material,
	wallColor: Color3,
	wallMaterial: Enum.Material
)
	box(parent, "Floor", Vector3.new(-HALF_WIDTH, -FLOOR, zMin), Vector3.new(HALF_WIDTH, 0, zMax), floorColor, floorMaterial)
	box(
		parent,
		"WallLeft",
		Vector3.new(-HALF_WIDTH - WALL, -FLOOR, zMin),
		Vector3.new(-HALF_WIDTH, HEIGHT, zMax),
		wallColor,
		wallMaterial
	)
	box(
		parent,
		"WallRight",
		Vector3.new(HALF_WIDTH, -FLOOR, zMin),
		Vector3.new(HALF_WIDTH + WALL, HEIGHT, zMax),
		wallColor,
		wallMaterial
	)
	box(
		parent,
		"Ceiling",
		Vector3.new(-HALF_WIDTH - WALL, HEIGHT, zMin),
		Vector3.new(HALF_WIDTH + WALL, HEIGHT + FLOOR, zMax),
		wallColor,
		wallMaterial
	)
end

-- A wall that closes the hall completely (behind the camp, after the last zone).
local function buildEndWall(parent: Instance, name: string, zMin: number, zMax: number, color: Color3, wallMaterial: Enum.Material)
	box(
		parent,
		name,
		Vector3.new(-HALF_WIDTH - WALL, -FLOOR, zMin),
		Vector3.new(HALF_WIDTH + WALL, HEIGHT + FLOOR, zMax),
		color,
		wallMaterial
	)
end

local function buildLamp(parent: Instance, x: number, z: number, color: Color3, range: number)
	local post = pillar(parent, "LampPost", x, z, 0, 9, 0.9, Color3.fromRGB(40, 36, 44), Enum.Material.Metal)
	post.CanTouch = false
	local orb = ball(parent, "LampOrb", Vector3.new(x, 10, z), 2.2, color, Enum.Material.Neon)
	orb.CanTouch = false
	pointLight(orb, color, range, 1.6)
end

-- The wall at the start of a zone, with the doorway and the gate that fills it.
-- The gate is solid on the server; each client opens it locally once that
-- player has enough sparks (see client/Gates).
local function buildGate(parent: Instance, zoneIndex: number, zone, z: number)
	local wallColor = rgb(zone.wall)
	local wallMaterial = material(zone.wallMaterial)
	local crystalColor = rgb(zone.crystal)
	local zMin, zMax = z - GATE_HALF_DEPTH, z + GATE_HALF_DEPTH

	box(parent, "GateWallLeft", Vector3.new(-HALF_WIDTH, 0, zMin), Vector3.new(-HALF_DOOR, HEIGHT, zMax), wallColor, wallMaterial)
	box(parent, "GateWallRight", Vector3.new(HALF_DOOR, 0, zMin), Vector3.new(HALF_WIDTH, HEIGHT, zMax), wallColor, wallMaterial)
	box(
		parent,
		"GateLintel",
		Vector3.new(-HALF_DOOR, W.DoorHeight, zMin),
		Vector3.new(HALF_DOOR, HEIGHT, zMax),
		wallColor,
		wallMaterial
	)

	local gate = newPart(
		"Gate",
		Vector3.new(W.DoorWidth, W.DoorHeight, 2),
		CFrame.new(0, W.DoorHeight / 2, z),
		crystalColor,
		Enum.Material.Neon
	)
	gate.Transparency = 0.25
	gate.CanTouch = false
	gate:SetAttribute("Zone", zoneIndex)
	gate:AddTag("ZoneGate")

	sign(gate, "Sign", 26, 8, Vector3.new(0, W.DoorHeight / 2 + 6, 4), {
		{ "ZoneName", zone.name, Color3.fromRGB(255, 255, 255), 0.55 },
		{ "Requirement", "🔒 " .. Format.abbreviate(zone.required) .. " ✨", crystalColor, 0.45 },
	})
	gate.Parent = parent

	buildLamp(parent, -HALF_DOOR - 4, z + 6, crystalColor, 30)
	buildLamp(parent, HALF_DOOR + 4, z + 6, crystalColor, 30)
end

local function buildCrystal(parent: Instance, zoneIndex: number, x: number, z: number, color: Color3, random): Crystal
	local model = Instance.new("Model")
	model.Name = "Crystal"

	local hitbox = newPart("Hitbox", Vector3.new(6, 9, 6), CFrame.new(x, 4.5, z), color, Enum.Material.SmoothPlastic)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox:SetAttribute("Zone", zoneIndex)
	hitbox.Parent = model

	local visuals = {}
	local main = newPart(
		"Shard",
		Vector3.new(2, 6.5, 2),
		CFrame.new(x, 3, z) * CFrame.Angles(math.rad(random(-12, 12)), math.rad(random(0, 360)), math.rad(random(-12, 12))),
		color,
		Enum.Material.Neon
	)
	ghost(main).Parent = model
	table.insert(visuals, main)

	for side = -1, 1, 2 do
		local shard = newPart(
			"Shard",
			Vector3.new(1.2, 3.6, 1.2),
			CFrame.new(x + side * random(1.3, 1.9), 1.5, z + random(-1.4, 1.4))
				* CFrame.Angles(math.rad(random(-26, 26)), math.rad(random(0, 360)), math.rad(side * random(10, 28))),
			color,
			Enum.Material.Neon
		)
		ghost(shard).Parent = model
		table.insert(visuals, shard)
	end

	local light = pointLight(main, color, 13, 1.1)
	model.Parent = parent

	return { zone = zoneIndex, active = true, hitbox = hitbox, visuals = visuals, light = light }
end

local function buildMushrooms(parent: Instance, zMin: number, zMax: number, random)
	local caps = { Color3.fromRGB(90, 240, 220), Color3.fromRGB(255, 120, 210), Color3.fromRGB(170, 130, 255) }
	for index = 1, 12 do
		local side = if index % 2 == 0 then 1 else -1
		local x = side * random(34, 39)
		local z = random(zMin + 8, zMax - 8)
		local height = random(2.5, 7)
		local capColor = caps[index % #caps + 1]
		ghost(pillar(parent, "MushroomStem", x, z, 0, height, random(0.8, 1.5), Color3.fromRGB(226, 216, 196), Enum.Material.SmoothPlastic))
		local cap = pillar(parent, "MushroomCap", x, z, height, random(0.7, 1.2), random(3.5, 7), capColor, Enum.Material.Neon)
		ghost(cap)
		if index % 3 == 0 then
			pointLight(cap, capColor, 14, 0.9)
		end
	end
end

local function buildStars(parent: Instance, zMin: number, zMax: number, random)
	for _ = 1, 70 do
		local star = ball(
			parent,
			"Star",
			Vector3.new(random(-HALF_WIDTH + 2, HALF_WIDTH - 2), random(HEIGHT - 7, HEIGHT - 0.6), random(zMin + 3, zMax - 3)),
			random(0.35, 0.9),
			Color3.fromRGB(255, 244, 200),
			Enum.Material.Neon
		)
		ghost(star)
	end
end

local function buildHeart(parent: Instance, zMin: number, color: Color3, random)
	local z = zMin + 9
	for index = 1, 7 do
		local angle = (index / 7) * math.pi * 2
		local radius = if index == 1 then 0 else random(2.5, 5)
		local height = if index == 1 then 30 else random(10, 22)
		local shard = newPart(
			"HeartShard",
			Vector3.new(random(3, 5), height, random(3, 5)),
			CFrame.new(math.cos(angle) * radius, height / 2 - 1, z + math.sin(angle) * radius * 0.6)
				* CFrame.Angles(math.rad(random(-9, 9)), math.rad(random(0, 360)), math.rad(random(-9, 9))),
			color,
			Enum.Material.Neon
		)
		shard.CanTouch = false
		shard.Parent = parent
		if index == 1 then
			pointLight(shard, color, 60, 3)
			sign(shard, "Sign", 30, 6, Vector3.new(0, 4, 10), {
				{ "Title", "💖 The Heart of the Deep", Color3.fromRGB(255, 255, 255), 0.6 },
				{ "Subtitle", "You lit the whole way down!", color, 0.4 },
			})
		end
	end
end

local function buildZone(root: Instance, zoneIndex: number, zone, crystals: { Crystal })
	local folder = Instance.new("Folder")
	folder.Name = string.format("Zone%02d", zoneIndex)

	local zMax = zoneStartZ(zoneIndex)
	local zMin = zMax - W.ZoneLength
	local random = makeRandom(7919 * zoneIndex + 13)
	local crystalColor = rgb(zone.crystal)
	local wallMaterial = material(zone.wallMaterial)

	buildShell(folder, zMin, zMax, rgb(zone.floor), material(zone.floorMaterial), rgb(zone.wall), wallMaterial)
	buildGate(folder, zoneIndex, zone, zMax)

	-- Crystals on a jittered grid so every zone is evenly filled.
	local columns, rows = Config.Crystals.Columns, Config.Crystals.Rows
	local rowStep = (W.ZoneLength - 32) / rows
	for column = 1, columns do
		for row = 1, rows do
			local x = (column - (columns + 1) / 2) * 26 + random(-5, 5)
			local z = zMax - 16 - (row - 0.5) * rowStep + random(-4, 4)
			table.insert(crystals, buildCrystal(folder, zoneIndex, x, z, crystalColor, random))
		end
	end

	-- Rocks hugging the side walls (kept clear of the crystal grid).
	local rockColor = scaleColor(zone.wall, 1.25)
	for index = 1, 12 do
		local side = if index % 2 == 0 then 1 else -1
		local height = random(4, 14)
		local rock = newPart(
			"Rock",
			Vector3.new(random(3, 5), height, random(3, 5)),
			CFrame.new(side * random(38, 41), height / 2 - 0.5, random(zMin + 6, zMax - 6))
				* CFrame.Angles(math.rad(random(-7, 7)), math.rad(random(0, 360)), math.rad(random(-7, 7))),
			rockColor,
			wallMaterial
		)
		rock.CanTouch = false
		rock.Parent = folder
	end

	-- Stalactites, high enough that nobody can reach them.
	for _ = 1, 16 do
		local length = random(4, 11)
		local width = random(1.2, 2.6)
		local stalactite = newPart(
			"Stalactite",
			Vector3.new(width, length, width),
			CFrame.new(random(-HALF_WIDTH + 3, HALF_WIDTH - 3), HEIGHT - length / 2 + 0.3, random(zMin + 4, zMax - 4))
				* CFrame.Angles(math.rad(random(-6, 6)), math.rad(random(0, 360)), math.rad(random(-6, 6))),
			rockColor,
			wallMaterial
		)
		ghost(stalactite).Parent = folder
	end

	-- Glowing patches on the floor.
	for _ = 1, 10 do
		local diameter = random(2.5, 6)
		local patch = newPart(
			"GlowPatch",
			Vector3.new(0.15, diameter, diameter),
			CFrame.new(random(-HALF_WIDTH + 5, HALF_WIDTH - 5), 0.06, random(zMin + 6, zMax - 6)) * CFrame.Angles(0, 0, math.rad(90)),
			crystalColor,
			Enum.Material.Neon
		)
		patch.Shape = Enum.PartType.Cylinder
		patch.Transparency = 0.45
		ghost(patch).Parent = folder
	end

	if zone.feature == "mushrooms" then
		buildMushrooms(folder, zMin, zMax, random)
	elseif zone.feature == "stars" then
		buildStars(folder, zMin, zMax, random)
	elseif zone.feature == "heart" then
		buildHeart(folder, zMin, crystalColor, random)
	end

	folder.Parent = root
end

local function buildCamp(root: Instance): CFrame
	local folder = Instance.new("Folder")
	folder.Name = "Camp"

	local zMin, zMax = 0, W.CampLength
	local floorColor = Color3.fromRGB(78, 68, 60)
	local wallColor = Color3.fromRGB(52, 48, 46)
	buildShell(folder, zMin, zMax, floorColor, Enum.Material.Cobblestone, wallColor, Enum.Material.Slate)
	buildEndWall(folder, "BackWall", zMax, zMax + WALL, wallColor, Enum.Material.Slate)

	-- Campfire.
	local fireZ = 40
	local warm = Color3.fromRGB(255, 170, 80)
	for index = 1, 10 do
		local angle = (index / 10) * math.pi * 2
		local stone = ball(
			folder,
			"FireStone",
			Vector3.new(math.cos(angle) * 4.6, 0.6, fireZ + math.sin(angle) * 4.6),
			2,
			Color3.fromRGB(90, 86, 84),
			Enum.Material.Slate
		)
		stone.CanTouch = false
	end
	for index = 0, 2 do
		local log = newPart(
			"FireLog",
			Vector3.new(6, 1.1, 1.1),
			CFrame.new(0, 0.6 + index * 0.25, fireZ) * CFrame.Angles(0, math.rad(index * 60), math.rad(8)),
			Color3.fromRGB(86, 56, 36),
			Enum.Material.Wood
		)
		log.Shape = Enum.PartType.Cylinder
		ghost(log).Parent = folder
	end
	local ember = ball(folder, "Ember", Vector3.new(0, 1.6, fireZ), 1.6, warm, Enum.Material.Neon)
	ghost(ember)
	local fire = Instance.new("Fire")
	fire.Heat = 12
	fire.Size = 9
	fire.Color = warm
	fire.SecondaryColor = Color3.fromRGB(255, 90, 40)
	fire.Parent = ember
	pointLight(ember, warm, 50, 2.4)

	sign(ember, "Title", 34, 15, Vector3.new(0, 15, 0), {
		{ "Name", "✨ " .. Config.GameName .. " ✨", Color3.fromRGB(255, 220, 130), 0.44 },
		{ "Tip1", "Pulse to charge your lantern", Color3.fromRGB(255, 255, 255), 0.2 },
		{ "Tip2", "Brighter lantern = deeper caves", Color3.fromRGB(255, 255, 255), 0.18 },
		{ "Tip3", "Grab crystals and buy upgrades!", Color3.fromRGB(140, 225, 255), 0.18 },
	})

	-- Warm lamps so the camp feels safe compared with the dark ahead.
	for _, corner in ipairs({ { -30, 16 }, { 30, 16 }, { -30, 74 }, { 30, 74 } }) do
		buildLamp(folder, corner[1], corner[2], warm, 38)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CampSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 66)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder

	folder.Parent = root
	return CFrame.new(0, 4, 66)
end

-- Darkness is the whole point: no sun, almost no ambient light, black fog.
-- Everything you can see is lit by lanterns, lamps and crystals.
function World.applyLighting()
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") or child:IsA("PostEffect") then
			child:Destroy()
		end
	end

	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.GlobalShadows = false
	Lighting.Ambient = Color3.fromRGB(22, 22, 34)
	Lighting.OutdoorAmbient = Color3.fromRGB(22, 22, 34)
	Lighting.FogColor = Color3.fromRGB(0, 0, 0)
	Lighting.FogStart = 30
	Lighting.FogEnd = 200
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.ExposureCompensation = 0.15

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 30
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Contrast = 0.06
	grade.Saturation = 0.12
	grade.Parent = Lighting
end

function World.build(): Built
	local existing = Workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "World"

	local crystals: { Crystal } = {}
	local zoneSpawns: { [number]: CFrame } = {}

	local campSpawn = buildCamp(root)
	zoneSpawns[0] = campSpawn

	for zoneIndex, zone in ipairs(Config.Zones) do
		buildZone(root, zoneIndex, zone, crystals)
		zoneSpawns[zoneIndex] = CFrame.new(0, 4, zoneStartZ(zoneIndex) - 12)
	end

	local lastZone = Config.Zones[#Config.Zones]
	local endZ = zoneStartZ(#Config.Zones) - W.ZoneLength
	buildEndWall(root, "EndWall", endZ - WALL, endZ, rgb(lastZone.wall), material(lastZone.wallMaterial))

	root.Parent = Workspace
	return { folder = root, campSpawn = campSpawn, zoneSpawns = zoneSpawns, crystals = crystals }
end

return World
