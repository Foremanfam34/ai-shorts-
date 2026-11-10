-- Server game loop: owns every player's progress and is the only place that
-- changes it. The client only sends requests ("I pulsed", "buy this").

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Profile = require(Shared:WaitForChild("Profile"))

local Store = require(script.Parent:WaitForChild("Store"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PulseRemote = Remotes:WaitForChild("Pulse")
local BuyUpgradeRemote = Remotes:WaitForChild("BuyUpgrade")
local RebirthRemote = Remotes:WaitForChild("Rebirth")
local WarpRemote = Remotes:WaitForChild("Warp")
local FeedbackRemote = Remotes:WaitForChild("Feedback")

local Game = {}

type Lantern = { orb: Part, light: PointLight }

type Session = {
	profile: Profile.Profile,
	perks: Formulas.Perks,
	canSave: boolean,
	saving: boolean,
	lastSave: number,
	tokens: number,
	lastRefill: number,
	lastWarp: number,
	highestZone: number,
	lantern: Lantern?,
}

local sessions: { [Player]: Session } = {}
local world = nil

local PASS_PERKS = {
	{ perk = "sparkBoost", attribute = "SparkBoost", id = Config.GamePasses.DoubleSparks },
	{ perk = "gemBoost", attribute = "GemBoost", id = Config.GamePasses.DoubleGems },
}

----------------------------------------------------------------------------
-- Lantern (the light every player carries)
----------------------------------------------------------------------------

local function updateLantern(session: Session)
	local lantern = session.lantern
	if not lantern or not lantern.orb.Parent then
		return
	end
	local sparks = session.profile.sparks
	local rgb = Formulas.lanternColor(session.profile.rebirths)
	local color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	local range = Formulas.lanternRange(sparks)
	local diameter = 1.2 + (range - Config.Lantern.MinRange) / (Config.Lantern.MaxRange - Config.Lantern.MinRange) * 1.4

	lantern.light.Range = range
	lantern.light.Brightness = Formulas.lanternBrightness(sparks)
	lantern.light.Color = color
	lantern.orb.Color = color
	lantern.orb.Size = Vector3.new(diameter, diameter, diameter)
end

local function createLantern(character: Model, root: BasePart): Lantern
	local orb = Instance.new("Part")
	orb.Name = "SparkLantern"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(1.2, 1.2, 1.2)
	orb.Material = Enum.Material.Neon
	orb.CanCollide = false
	orb.CanTouch = false
	orb.CanQuery = false
	orb.Massless = true
	orb.CastShadow = false
	orb.CFrame = root.CFrame * CFrame.new(1.9, 2.4, -0.4)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = orb
	weld.Parent = orb

	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Parent = orb

	orb.Parent = character
	return { orb = orb, light = light }
end

local function onCharacterAdded(player: Player, character: Model)
	local session = sessions[player]
	if not session then
		return -- still loading; setupPlayer calls this again once the profile is ready
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not root or not humanoid or sessions[player] ~= session then
		return
	end
	if character:FindFirstChild("SparkLantern") then
		return
	end
	humanoid.WalkSpeed = Formulas.walkSpeed(session.profile)
	session.lantern = createLantern(character, root)
	updateLantern(session)
end

----------------------------------------------------------------------------
-- Keeping the client, leaderboard and lantern in step with the profile
----------------------------------------------------------------------------

local function sync(player: Player, session: Session)
	local profile = session.profile

	player:SetAttribute("Sparks", profile.sparks)
	player:SetAttribute("Gems", profile.gems)
	player:SetAttribute("Rebirths", profile.rebirths)
	player:SetAttribute("BestZone", profile.bestZone)
	for _, id in ipairs(Config.UpgradeOrder) do
		player:SetAttribute("Upgrade_" .. id, profile.upgrades[id])
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local sparksValue = leaderstats:FindFirstChild("Sparks")
		local rebirthsValue = leaderstats:FindFirstChild("Rekindles")
		if sparksValue then
			sparksValue.Value = profile.sparks
		end
		if rebirthsValue then
			rebirthsValue.Value = profile.rebirths
		end
	end

	updateLantern(session)

	local highest = Formulas.highestZone(profile.sparks)
	if highest > session.highestZone then
		FeedbackRemote:FireClient(player, "zone", highest)
	end
	session.highestZone = highest
end

local function applyWalkSpeed(player: Player, session: Session)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Formulas.walkSpeed(session.profile)
	end
end

local function teleport(player: Player, cframe: CFrame)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(cframe)
	end
end

----------------------------------------------------------------------------
-- Saving
----------------------------------------------------------------------------

local function save(player: Player, session: Session)
	if not session.canSave or session.saving then
		return
	end
	session.saving = true
	session.lastSave = os.clock()
	Store.save(player.UserId, session.profile)
	session.saving = false
end

----------------------------------------------------------------------------
-- Players joining and leaving
----------------------------------------------------------------------------

local function loadPerks(player: Player, session: Session)
	local perks: { [string]: number } = session.perks :: any
	for _, pass in ipairs(PASS_PERKS) do
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns then
				perks[pass.perk] = 2
			end
		end
		player:SetAttribute(pass.attribute, perks[pass.perk])
	end
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	local loaded, raw = Store.load(player.UserId)
	if player.Parent == nil then
		return -- left while we were loading
	end
	if not loaded and not Store.isTestSession() then
		player:Kick("Your progress could not be loaded. Please rejoin in a moment so nothing is lost.")
		return
	end

	local profile = Profile.sanitize(raw)
	local now = os.clock()
	local session: Session = {
		profile = profile,
		perks = { sparkBoost = 1, gemBoost = 1 },
		canSave = loaded,
		saving = false,
		lastSave = now,
		tokens = Config.PulseBurst,
		lastRefill = now,
		lastWarp = 0,
		highestZone = Formulas.highestZone(profile.sparks),
		lantern = nil,
	}

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local sparksValue = Instance.new("IntValue")
	sparksValue.Name = "Sparks"
	sparksValue.Parent = leaderstats
	local rebirthsValue = Instance.new("IntValue")
	rebirthsValue.Name = "Rekindles"
	rebirthsValue.Parent = leaderstats
	leaderstats.Parent = player

	sessions[player] = session
	loadPerks(player, session)
	sync(player, session)
	player:SetAttribute("Loaded", true)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function removePlayer(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	session.saving = false
	save(player, session)
end

----------------------------------------------------------------------------
-- Requests from the client
----------------------------------------------------------------------------

local function onPulse(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	-- Token bucket: ignores auto-clickers faster than MaxPulsesPerSecond.
	local now = os.clock()
	session.tokens = math.min(Config.PulseBurst, session.tokens + (now - session.lastRefill) * Config.MaxPulsesPerSecond)
	session.lastRefill = now
	if session.tokens < 1 then
		return
	end
	session.tokens -= 1

	Profile.pulse(session.profile, 1, session.perks)
	sync(player, session)
end

local function onBuyUpgrade(player: Player, id: any)
	local session = sessions[player]
	if not session then
		return
	end
	local bought, reason = Profile.buyUpgrade(session.profile, id)
	if bought then
		sync(player, session)
		applyWalkSpeed(player, session)
		FeedbackRemote:FireClient(player, "bought", id)
	else
		FeedbackRemote:FireClient(player, "denied", reason)
	end
end

local function onRebirth(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	if not Profile.rebirth(session.profile) then
		FeedbackRemote:FireClient(player, "denied", "rebirth")
		return
	end
	session.highestZone = 0
	sync(player, session)
	applyWalkSpeed(player, session)
	teleport(player, world.campSpawn)
	FeedbackRemote:FireClient(player, "rebirth", session.profile.rebirths)
	task.spawn(save, player, session)
end

local function onWarp(player: Player, zoneIndex: any)
	local session = sessions[player]
	if not session or type(zoneIndex) ~= "number" then
		return
	end
	local target = world.zoneSpawns[zoneIndex]
	if not target or not Formulas.zoneUnlocked(session.profile.sparks, zoneIndex) then
		return
	end
	local now = os.clock()
	if now - session.lastWarp < 0.75 then
		return
	end
	session.lastWarp = now
	teleport(player, target)
end

----------------------------------------------------------------------------
-- Crystals
----------------------------------------------------------------------------

local function setCrystalActive(crystal, active: boolean)
	crystal.active = active
	crystal.hitbox.CanTouch = active
	crystal.light.Enabled = active
	for _, part in ipairs(crystal.visuals) do
		part.Transparency = if active then 0 else 1
	end
end

local function onCrystalTouched(crystal, hit: BasePart)
	if not crystal.active then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	local session = player and sessions[player]
	if not session then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local gained = Profile.collect(session.profile, crystal.zone, session.perks)
	if not gained then
		return -- lantern too dim for this zone
	end

	setCrystalActive(crystal, false)
	task.delay(Config.Crystals.RespawnSeconds, setCrystalActive, crystal, true)
	sync(player, session)
	FeedbackRemote:FireClient(player, "collect", gained)
end

----------------------------------------------------------------------------
-- Start
----------------------------------------------------------------------------

function Game.start(builtWorld)
	world = builtWorld

	for _, crystal in ipairs(world.crystals) do
		crystal.hitbox.Touched:Connect(function(hit)
			onCrystalTouched(crystal, hit)
		end)
	end

	PulseRemote.OnServerEvent:Connect(onPulse)
	BuyUpgradeRemote.OnServerEvent:Connect(onBuyUpgrade)
	RebirthRemote.OnServerEvent:Connect(onRebirth)
	WarpRemote.OnServerEvent:Connect(onWarp)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local session = sessions[player]
		if not purchased or not session then
			return
		end
		local perks: { [string]: number } = session.perks :: any
		for _, pass in ipairs(PASS_PERKS) do
			if pass.id ~= 0 and pass.id == passId then
				perks[pass.perk] = 2
				player:SetAttribute(pass.attribute, 2)
			end
		end
	end)

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(removePlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end

	-- Once a second: auto-pulses, play time and autosave.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, session in pairs(sessions) do
				session.profile.playSeconds += 1
				local autoPulses = Formulas.autoPulsesPerSecond(session.profile)
				if autoPulses > 0 then
					Profile.pulse(session.profile, autoPulses, session.perks)
					sync(player, session)
				end
				if now - session.lastSave >= Config.AutosaveSeconds then
					task.spawn(save, player, session)
				end
			end
		end
	end)

	-- Save everyone when the server shuts down.
	game:BindToClose(function()
		local pending = 0
		for player, session in pairs(sessions) do
			pending += 1
			task.spawn(function()
				session.saving = false
				save(player, session)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return Game
