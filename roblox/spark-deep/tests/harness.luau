-- Headless stand-in for the Roblox engine, for running the built place file
-- under Lune (https://lune-org.github.io/docs). It loads the real instance tree
-- and real script sources out of the .rbxl, and fakes just enough engine
-- behaviour (events, services, remotes, a data store) to drive the game.
--
-- What this proves: scripts load, paths resolve, every property and enum used
-- exists with the right type, and the game logic behaves. What it cannot
-- prove: physics, rendering, and how it feels. That needs Roblox Studio.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Instance = roblox.Instance

local Harness = {}

Harness.errors = {} :: { string }
Harness.warnings = {} :: { string }
Harness.prints = {} :: { string }
Harness.clientEvents = {} :: { { remote: string, player: any, args: { any } } }
Harness.kicked = {} :: { [any]: string }
Harness.prompts = {} :: { number }
Harness.soundsPlayed = {} :: { [string]: number }
Harness.closeCallbacks = {} :: { () -> () }
Harness.ownedPasses = {} :: { [number]: boolean }
Harness.dataStores = {} :: { [string]: any }
Harness.dataStoreFails = false
Harness.studio = true
Harness.localPlayer = nil :: any
Harness.game = nil :: any
Harness.env = nil :: any

----------------------------------------------------------------------------
-- Signals
----------------------------------------------------------------------------

-- Runs a callback in its own thread and records any error instead of losing it.
function Harness.run(callback, ...)
	task.spawn(function(...)
		local ok, message = xpcall(callback, function(err)
			return debug.traceback(tostring(err), 2)
		end, ...)
		if not ok then
			table.insert(Harness.errors, message)
		end
	end, ...)
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(callback)
	local connection = { Connected = true }
	function connection:Disconnect()
		self.Connected = false
	end
	table.insert(self.handlers, { callback = callback, connection = connection })
	return connection
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...)
	for _, handler in ipairs(table.clone(self.handlers)) do
		if handler.connection.Connected then
			Harness.run(handler.callback, ...)
		end
	end
end

local signals = {}

-- The fake event `name` on `instance` (created on first use).
function Harness.signal(instance, name: string)
	local bucket = signals[instance]
	if not bucket then
		bucket = {}
		signals[instance] = bucket
	end
	local signal = bucket[name]
	if not signal then
		signal = Signal.new()
		bucket[name] = signal
	end
	return signal
end

----------------------------------------------------------------------------
-- Engine members that Lune does not provide
----------------------------------------------------------------------------

local EVENTS = {
	Instance = { "AttributeChanged", "ChildAdded", "ChildRemoved", "DescendantAdded", "Destroying", "Changed" },
	BasePart = { "Touched", "TouchEnded" },
	Humanoid = { "Died" },
	Player = { "CharacterAdded", "CharacterRemoving" },
	Players = { "PlayerAdded", "PlayerRemoving" },
	RunService = { "Heartbeat", "RenderStepped", "Stepped" },
	UserInputService = { "InputBegan", "InputEnded", "InputChanged" },
	GuiObject = { "InputBegan", "InputEnded", "MouseEnter", "MouseLeave" },
	GuiButton = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" },
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	MarketplaceService = { "PromptGamePassPurchaseFinished" },
	DataModel = { "Loaded" },
}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[key] = deepCopy(item)
	end
	return copy
end

local function newDataStore()
	local store = { data = {}, gets = 0, sets = 0 }
	function store:GetAsync(key)
		self.gets += 1
		if Harness.dataStoreFails then
			error("DataStore request failed (simulated outage)")
		end
		return deepCopy(self.data[key])
	end
	function store:SetAsync(key, value)
		self.sets += 1
		if Harness.dataStoreFails then
			error("DataStore request failed (simulated outage)")
		end
		self.data[key] = deepCopy(value)
	end
	return store
end

local installed = false

local function install()
	if installed then
		return
	end
	installed = true

	for className, names in pairs(EVENTS) do
		for _, name in ipairs(names) do
			roblox.implementProperty(className, name, function(self)
				return Harness.signal(self, name)
			end)
		end
	end

	roblox.implementMethod("Instance", "WaitForChild", function(self, name, timeout)
		local child = self:FindFirstChild(name)
		if child == nil and timeout == nil then
			error(string.format("WaitForChild(%q) would wait forever on %s", tostring(name), self:GetFullName()), 2)
		end
		return child
	end)
	roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, property)
		return Harness.signal(self, "Changed:" .. property)
	end)
	roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, attribute)
		return Harness.signal(self, "Attribute:" .. attribute)
	end)

	roblox.implementMethod("Players", "GetPlayers", function(self)
		local list = {}
		for _, child in ipairs(self:GetChildren()) do
			if child.ClassName == "Player" then
				table.insert(list, child)
			end
		end
		return list
	end)
	roblox.implementMethod("Players", "GetPlayerFromCharacter", function(self, character)
		for _, child in ipairs(self:GetChildren()) do
			if child.ClassName == "Player" and child.Character == character then
				return child
			end
		end
		return nil
	end)
	roblox.implementMethod("Player", "Kick", function(self, message)
		Harness.kicked[self] = message or ""
		self.Parent = nil
	end)

	roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
		Harness.signal(self, "OnServerEvent"):Fire(Harness.localPlayer, ...)
	end)
	roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
		table.insert(Harness.clientEvents, { remote = self.Name, player = player, args = { ... } })
		if player == Harness.localPlayer then
			Harness.signal(self, "OnClientEvent"):Fire(...)
		end
	end)

	roblox.implementMethod("RunService", "IsStudio", function()
		return Harness.studio
	end)
	roblox.implementMethod("RunService", "IsServer", function()
		return true
	end)
	roblox.implementMethod("RunService", "IsClient", function()
		return true
	end)

	-- Tweens jump straight to their goal, which still checks every property.
	roblox.implementMethod("TweenService", "Create", function(_, instance, _, goals)
		local tween = { Completed = Signal.new() }
		function tween:Play()
			for property, value in pairs(goals) do
				instance[property] = value
			end
			self.Completed:Fire()
		end
		function tween:Cancel() end
		return tween
	end)

	roblox.implementMethod("CollectionService", "GetTagged", function(_, tag)
		local list = {}
		for _, descendant in ipairs(Harness.game:GetDescendants()) do
			if descendant:HasTag(tag) then
				table.insert(list, descendant)
			end
		end
		return list
	end)
	roblox.implementMethod("CollectionService", "GetInstanceAddedSignal", function(self, tag)
		return Harness.signal(self, "Added:" .. tag)
	end)

	roblox.implementMethod("DataStoreService", "GetDataStore", function(_, name)
		local store = Harness.dataStores[name]
		if not store then
			store = newDataStore()
			Harness.dataStores[name] = store
		end
		return store
	end)

	roblox.implementMethod("MarketplaceService", "UserOwnsGamePassAsync", function(_, _, passId)
		return Harness.ownedPasses[passId] == true
	end)
	roblox.implementMethod("MarketplaceService", "PromptGamePassPurchase", function(_, _, passId)
		table.insert(Harness.prompts, passId)
	end)

	roblox.implementMethod("DataModel", "BindToClose", function(_, callback)
		table.insert(Harness.closeCallbacks, callback)
	end)
	roblox.implementMethod("DataModel", "IsLoaded", function()
		return true
	end)

	roblox.implementMethod("Sound", "Play", function(self)
		Harness.soundsPlayed[self.Name] = (Harness.soundsPlayed[self.Name] or 0) + 1
	end)

	roblox.implementMethod("Model", "PivotTo", function(self, cframe)
		local root = self:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = cframe
		end
	end)
	roblox.implementMethod("Model", "GetPivot", function(self)
		local root = self:FindFirstChild("HumanoidRootPart")
		return if root then root.CFrame else roblox.CFrame.new()
	end)
end

----------------------------------------------------------------------------
-- Loading and running scripts out of the place file
----------------------------------------------------------------------------

local moduleCache = {}

local function compile(scriptInstance)
	local environment = table.clone(Harness.env)
	environment.script = scriptInstance
	return luau.load(scriptInstance.Source, {
		debugName = scriptInstance:GetFullName(),
		environment = environment,
	})
end

-- `require` for ModuleScripts inside the place, with Roblox's caching.
function Harness.require(moduleScript)
	if typeof(moduleScript) ~= "Instance" or moduleScript.ClassName ~= "ModuleScript" then
		error("require expects a ModuleScript, got " .. tostring(moduleScript), 2)
	end
	local cached = moduleCache[moduleScript]
	if cached then
		return cached.value
	end
	local value = compile(moduleScript)()
	moduleCache[moduleScript] = { value = value }
	return value
end

-- Runs a Script or LocalScript; errors are recorded in Harness.errors.
function Harness.runScript(scriptInstance)
	Harness.run(compile(scriptInstance))
end

-- Loads the place and prepares the fake engine. `gameId` 0 means "not published".
function Harness.boot(placePath: string, gameId: number?)
	install()

	local game = roblox.deserializePlace(fs.readFile(placePath))
	Harness.game = game
	game.GameId = gameId or 0
	game.PlaceId = gameId or 0

	local workspace = game:GetService("Workspace")
	local camera = Instance.new("Camera")
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	camera.Parent = workspace
	workspace.CurrentCamera = camera

	local input = game:GetService("UserInputService")
	input.TouchEnabled = false
	input.KeyboardEnabled = true

	local environment = {}
	for key, value in pairs(roblox) do
		environment[key] = value
	end
	environment.game = game
	environment.workspace = workspace
	environment.task = task
	environment.require = Harness.require
	environment.TweenInfo = {
		new = function(...)
			return { ... }
		end,
	}
	environment.tick = os.clock
	environment.time = os.clock
	environment.wait = task.wait
	environment.print = function(...)
		local parts = {}
		for index = 1, select("#", ...) do
			parts[index] = tostring((select(index, ...)))
		end
		table.insert(Harness.prints, table.concat(parts, " "))
	end
	environment.warn = function(...)
		local parts = {}
		for index = 1, select("#", ...) do
			parts[index] = tostring((select(index, ...)))
		end
		table.insert(Harness.warnings, table.concat(parts, " "))
	end
	Harness.env = environment

	return game
end

----------------------------------------------------------------------------
-- Driving the game
----------------------------------------------------------------------------

function Harness.addPlayer(name: string, userId: number)
	local players = Harness.game:GetService("Players")
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	local playerGui = Instance.new("PlayerGui")
	playerGui.Parent = player
	player.Parent = players
	Harness.signal(players, "PlayerAdded"):Fire(player)
	return player
end

-- Makes `player` the one the client scripts see as Players.LocalPlayer.
function Harness.setLocalPlayer(player)
	Harness.localPlayer = player
	Harness.game:GetService("Players").LocalPlayer = player
end

function Harness.spawnCharacter(player, cframe)
	local character = Instance.new("Model")
	character.Name = player.Name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = cframe or roblox.CFrame.new(0, 4, 66)
	root.Parent = character

	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character

	character.Parent = Harness.game:GetService("Workspace")
	player.Character = character
	Harness.signal(player, "CharacterAdded"):Fire(character)
	return character, root, humanoid
end

function Harness.removePlayer(player)
	local players = Harness.game:GetService("Players")
	Harness.signal(players, "PlayerRemoving"):Fire(player)
	player.Parent = nil
end

-- Lune sets attributes natively without telling anyone, so tests announce
-- "the server changed this player's attributes" themselves.
function Harness.flushAttributes(player)
	Harness.signal(player, "AttributeChanged"):Fire("*")
end

-- One rendered frame on the client.
function Harness.frame(deltaTime: number?)
	local runService = Harness.game:GetService("RunService")
	Harness.signal(runService, "Heartbeat"):Fire(deltaTime or 1 / 60)
	Harness.signal(runService, "RenderStepped"):Fire(deltaTime or 1 / 60)
end

return Harness
