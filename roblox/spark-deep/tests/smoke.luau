-- End-to-end smoke test of the built place file, without Roblox Studio.
-- Starts the real server script, joins a fake player, starts the real client
-- script, then plays: pulse, open a gate, collect crystals, buy upgrades, warp,
-- rekindle, leave, rejoin.
--
--   rojo build -o SparkDeep.rbxl
--   lune run tests/smoke.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = require("./harness")

local Enum = roblox.Enum
local placePath = process.args[1] or "SparkDeep.rbxl"

local checks = 0
local failures = {}

local function check(condition: any, label: string)
	checks += 1
	if not condition then
		table.insert(failures, label)
		print("  FAIL  " .. label)
	end
end

local function equal(actual: any, expected: any, label: string)
	check(actual == expected, string.format("%s (expected %s, got %s)", label, tostring(expected), tostring(actual)))
end

local function near(actual: number, expected: number, label: string)
	check(math.abs(actual - expected) < 1e-3, string.format("%s (expected %s, got %s)", label, tostring(expected), tostring(actual)))
end

local function stage(name: string)
	for _, message in ipairs(Harness.errors) do
		print("  SCRIPT ERROR before '" .. name .. "':\n" .. message)
		table.insert(failures, "script error before " .. name)
	end
	table.clear(Harness.errors)
	print("- " .. name)
end

-- Stops the run: the game's once-a-second loop would otherwise keep Lune alive.
local function fatal(message: string)
	for _, scriptError in ipairs(Harness.errors) do
		print("  SCRIPT ERROR:\n" .. scriptError)
	end
	print("\nSMOKE TEST ABORTED: " .. message)
	process.exit(1)
end

task.delay(90, fatal, "timed out")

local function find(root: any, ...: string): any
	local current = root
	for _, name in ipairs({ ... }) do
		local child = current:FindFirstChild(name)
		if not child then
			fatal(string.format("%s has no child %q", current:GetFullName(), name))
		end
		current = child
	end
	return current
end

----------------------------------------------------------------------------
stage("boot the place as a published experience")

local game = Harness.boot(placePath, 987654)
Harness.studio = false

local workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = find(ReplicatedStorage, "Shared")
local Remotes = find(ReplicatedStorage, "Remotes")
local Config = Harness.require(find(Shared, "Config"))
local Formulas = Harness.require(find(Shared, "Formulas"))

-- Shrink the numbers so one short session reaches every feature.
local GEMS_PASS = 777
Config.Crystals.RespawnSeconds = 0.3
Config.AutosaveSeconds = 2
Config.Rebirth.BaseRequirement = 60
Config.Zones[1].gemValue = 50
Config.GamePasses.DoubleGems = GEMS_PASS

----------------------------------------------------------------------------
stage("server starts and builds the cave")

Harness.runScript(find(game:GetService("ServerScriptService"), "Server", "Main"))

local world = workspace:FindFirstChild("World")
check(world ~= nil, "Workspace.World exists")
check(#Harness.prints > 0 and string.find(Harness.prints[1], "10 zones, 150 crystals", 1, true) ~= nil, "server reports 10 zones and 150 crystals")

local W = Config.World
local zMinWorld = -#Config.Zones * W.ZoneLength - W.WallThickness
local zMaxWorld = W.CampLength + W.WallThickness
local gates, hitboxes, rocks, partCount = {}, {}, {}, 0
for _, descendant in ipairs(world:GetDescendants()) do
	if descendant:IsA("BasePart") then
		partCount += 1
		local size, position = descendant.Size, descendant.CFrame.Position
		check(size.X > 0 and size.Y > 0 and size.Z > 0, descendant:GetFullName() .. " has a positive size")
		check(descendant.Anchored, descendant:GetFullName() .. " is anchored")
		check(
			math.abs(position.X) <= W.Width / 2 + W.WallThickness
				and position.Y >= -W.FloorThickness
				and position.Y <= W.Height + W.FloorThickness
				and position.Z >= zMinWorld
				and position.Z <= zMaxWorld,
			descendant:GetFullName() .. " is inside the cave"
		)
		if descendant:HasTag("ZoneGate") then
			table.insert(gates, descendant)
		elseif descendant.Name == "Hitbox" then
			table.insert(hitboxes, descendant)
		elseif descendant.Name == "Rock" then
			table.insert(rocks, descendant)
		end
	end
end
equal(#gates, #Config.Zones, "one gate per zone")
equal(#hitboxes, #Config.Zones * Config.Crystals.Columns * Config.Crystals.Rows, "crystal count")
check(partCount > 800 and partCount < 3000, "sensible part count (" .. partCount .. ")")

table.sort(gates, function(a, b)
	return a:GetAttribute("Zone") < b:GetAttribute("Zone")
end)
for index, gate in ipairs(gates) do
	equal(gate:GetAttribute("Zone"), index, "gate " .. index .. " zone attribute")
	near(gate.CFrame.Position.Z, -(index - 1) * W.ZoneLength, "gate " .. index .. " position")
	equal(find(gate, "Sign", "ZoneName").Text, Config.Zones[index].name, "gate " .. index .. " sign")
end

-- Every crystal sits inside its own zone and clear of the wall rocks.
local crystalsByZone = {}
for _, hitbox in ipairs(hitboxes) do
	local zone = hitbox:GetAttribute("Zone")
	crystalsByZone[zone] = crystalsByZone[zone] or {}
	table.insert(crystalsByZone[zone], hitbox)
	local position = hitbox.CFrame.Position
	local zMax = -(zone - 1) * W.ZoneLength
	check(position.Z < zMax - 8 and position.Z > zMax - W.ZoneLength + 8, "crystal inside zone " .. zone)
	check(math.abs(position.X) <= W.Width / 2 - 8, "crystal away from the side walls")
	for _, rock in ipairs(rocks) do
		local offset = rock.CFrame.Position - position
		if math.sqrt(offset.X ^ 2 + offset.Z ^ 2) < 6.5 then
			check(false, "crystal overlaps a rock in zone " .. zone)
		end
	end
end

local lighting = game:GetService("Lighting")
equal(lighting.Brightness, 0, "the cave is dark")
check(lighting:FindFirstChildOfClass("BloomEffect") ~= nil, "bloom effect added")
check(find(world, "Camp", "CampSpawn"):IsA("SpawnLocation"), "camp spawn exists")

----------------------------------------------------------------------------
stage("a new player joins and spawns")

local player = Harness.addPlayer("Tester", 1001)
Harness.setLocalPlayer(player)
equal(player:GetAttribute("Loaded"), true, "profile loaded")
equal(player:GetAttribute("Sparks"), 0, "starts with 0 sparks")
equal(player:GetAttribute("GemBoost"), 1, "no gem boost yet")
check(find(player, "leaderstats", "Sparks"):IsA("IntValue"), "leaderstats created")

local character, root, humanoid = Harness.spawnCharacter(player)
local lantern = find(character, "SparkLantern")
local lanternLight = lantern:FindFirstChildOfClass("PointLight")
near(lanternLight.Range, Config.Lantern.MinRange, "lantern starts at its smallest")
equal(humanoid.WalkSpeed, Config.BaseWalkSpeed, "base walk speed applied")

----------------------------------------------------------------------------
stage("client starts and draws the HUD")

Harness.runScript(find(game:GetService("StarterPlayer"), "StarterPlayerScripts", "Client", "Main"))
Harness.frame()

local hud = find(player, "PlayerGui", "SparkHud")
equal(hud.Enabled, true, "HUD is shown once loaded")
local sparksLabel = find(hud, "TopBar", "Sparks", "Value")
local gemsLabel = find(hud, "TopBar", "Gems", "Value")
local progressLabel = find(hud, "TopBar", "Progress", "Label")
local pulseButton = find(hud, "PulseArea", "Pulse")
local pulseAmount = find(pulseButton, "Amount")
local toast = find(hud, "ToastHolder", "Toast")
local panel = find(hud, "Panel")
equal(sparksLabel.Text, "✨ 0", "sparks counter")
equal(progressLabel.Text, "Next: Glowmoss Hollow  ·  0 / 25 ✨", "progress bar text")
equal(gates[1].CanCollide, true, "gate 1 starts closed")

local function sync()
	Harness.flushAttributes(player)
	Harness.frame()
end

----------------------------------------------------------------------------
stage("pulsing: taps, rate limit, hold")

local press = { UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.A }
local function tap()
	Harness.signal(pulseButton, "InputBegan"):Fire(press)
	Harness.signal(UserInputService, "InputEnded"):Fire(press)
end

for _ = 1, Config.PulseBurst do
	tap()
end
equal(player:GetAttribute("Sparks"), Config.PulseBurst, "a burst of taps all count")
tap()
equal(player:GetAttribute("Sparks"), Config.PulseBurst, "taps beyond the burst are ignored")

-- The server enforces the limit on its own, whatever the client sends.
for _ = 1, 200 do
	Harness.signal(find(Remotes, "Pulse"), "OnServerEvent"):Fire(player)
end
check(player:GetAttribute("Sparks") <= Config.PulseBurst + 2, "server ignores a flood of pulse requests")

task.wait(0.7)
local beforeHold = player:GetAttribute("Sparks")
Harness.signal(pulseButton, "InputBegan"):Fire(press) -- press and keep holding
Harness.frame(0.2)
Harness.frame(0.2)
equal(player:GetAttribute("Sparks"), beforeHold + 3, "holding keeps pulsing")
Harness.signal(UserInputService, "InputEnded"):Fire(press)
Harness.frame(0.2)
equal(player:GetAttribute("Sparks"), beforeHold + 3, "releasing stops pulsing")

local key = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.E }
Harness.signal(UserInputService, "InputBegan"):Fire(key, false)
Harness.signal(UserInputService, "InputEnded"):Fire(key)
equal(player:GetAttribute("Sparks"), beforeHold + 4, "E key pulses")
Harness.signal(UserInputService, "InputBegan"):Fire(key, true)
Harness.signal(UserInputService, "InputEnded"):Fire(key)
equal(player:GetAttribute("Sparks"), beforeHold + 4, "E while typing in chat is ignored")

while player:GetAttribute("Sparks") < Config.Zones[1].required do
	task.wait(0.1)
	tap()
end
sync()

----------------------------------------------------------------------------
stage("first gate opens for this player")

local sparks = player:GetAttribute("Sparks")
equal(sparksLabel.Text, "✨ " .. sparks, "sparks counter follows the server")
equal(gates[1].CanCollide, false, "gate 1 opens")
equal(find(gates[1], "Sign", "Requirement").Text, "OPEN", "gate 1 sign says OPEN")
equal(gates[2].CanCollide, true, "gate 2 stays closed")
equal(toast.Visible, true, "unlock toast shown")
equal(find(toast, "Label").Text, "🔓 Glowmoss Hollow unlocked!", "unlock toast text")
check(lanternLight.Range > Config.Lantern.MinRange, "lantern grew")
equal(find(player, "leaderstats", "Sparks").Value, sparks, "leaderboard follows")

----------------------------------------------------------------------------
stage("crystals")

local zoneOne = crystalsByZone[1]
local function touch(hitbox)
	Harness.signal(hitbox, "Touched"):Fire(root)
end

touch(zoneOne[1])
equal(player:GetAttribute("Gems"), 50, "crystal pays its zone value")
equal(zoneOne[1].CanTouch, false, "collected crystal switches off")
local shard = find(zoneOne[1].Parent, "Shard")
equal(shard.Transparency, 1, "collected crystal hides")
touch(zoneOne[1])
equal(player:GetAttribute("Gems"), 50, "a collected crystal cannot be collected twice")
check(#find(hud, "Popups"):GetChildren() >= 1, "gem popup shown")

touch(crystalsByZone[2][1])
equal(player:GetAttribute("Gems"), 50, "crystals behind a locked gate pay nothing")
equal(crystalsByZone[2][1].CanTouch, true, "locked crystal is left alone")

task.wait(0.5)
equal(shard.Transparency, 0, "crystal respawns")
equal(zoneOne[1].CanTouch, true, "respawned crystal is collectable")

----------------------------------------------------------------------------
stage("upgrades")

local function activate(button)
	Harness.signal(button, "Activated"):Fire()
end

activate(find(hud, "Menu", "upgrades"))
equal(panel.Visible, true, "upgrades panel opens")
local upgrades = find(panel, "Content", "Upgrades")
equal(upgrades.Visible, true, "upgrades list visible")

sync()
equal(find(hud, "Menu", "upgrades", "Badge").Visible, true, "badge shows an affordable upgrade")
equal(find(upgrades, "power", "Action").Text, "💎 4", "power upgrade price")

activate(find(upgrades, "power", "Action"))
sync()
equal(player:GetAttribute("Upgrade_power"), 1, "power upgrade bought")
equal(player:GetAttribute("Gems"), 46, "gems spent")
equal(find(upgrades, "power", "Name").Text, "Bigger Sparks  Lv 1", "upgrade row shows the level")
equal(pulseAmount.Text, "+2", "pulse button shows the new amount")

activate(find(upgrades, "speed", "Action"))
equal(player:GetAttribute("Upgrade_speed"), 0, "cannot buy without enough gems")
equal(find(toast, "Label").Text, "Not enough gems 💎", "denied toast")

touch(zoneOne[2])
touch(zoneOne[3])
equal(player:GetAttribute("Gems"), 146, "two more crystals")
activate(find(upgrades, "auto", "Action"))
activate(find(upgrades, "speed", "Action"))
activate(find(upgrades, "gems", "Action"))
sync()
equal(player:GetAttribute("Upgrade_auto"), 1, "auto upgrade bought")
equal(player:GetAttribute("Upgrade_speed"), 1, "speed upgrade bought")
equal(player:GetAttribute("Upgrade_gems"), 1, "gem upgrade bought")
equal(player:GetAttribute("Gems"), 26, "gems after three purchases")
equal(humanoid.WalkSpeed, Config.BaseWalkSpeed + 1, "walk speed raised")

touch(zoneOne[4])
equal(player:GetAttribute("Gems"), 26 + 62, "gem upgrade multiplies crystal value")

-- Game pass row and purchase.
local passRow = find(upgrades, "gemBoost", "Action")
sync()
equal(passRow.Text, "Get", "game pass offered")
activate(passRow)
equal(Harness.prompts[1], GEMS_PASS, "purchase prompt opened")
Harness.signal(MarketplaceService, "PromptGamePassPurchaseFinished"):Fire(player, GEMS_PASS, true)
sync()
equal(player:GetAttribute("GemBoost"), 2, "pass applied on purchase")
equal(passRow.Text, "Owned", "pass row shows owned")
touch(zoneOne[5])
equal(player:GetAttribute("Gems"), 26 + 62 + 125, "pass doubles crystal value")

----------------------------------------------------------------------------
stage("auto lantern and autosave")

local store = Harness.dataStores[Config.DataStoreName]
check(store ~= nil, "data store opened")
local beforeAuto = player:GetAttribute("Sparks")
task.wait(2.3)
local gainedAuto = player:GetAttribute("Sparks") - beforeAuto
check(gainedAuto == 4 or gainedAuto == 6, "auto lantern pulses every second (gained " .. gainedAuto .. ")")
check(store.sets >= 1, "autosave wrote to the data store")

----------------------------------------------------------------------------
stage("warping")

activate(find(hud, "Menu", "zones"))
equal(find(panel, "Content", "Zones").Visible, true, "zones list visible")
equal(upgrades.Visible, false, "upgrades list hidden")
sync()
local zones = find(panel, "Content", "Zones")
equal(find(zones, "Zone1", "Action").Text, "Warp", "open zone offers a warp")
equal(find(zones, "Zone3", "Action").Text, "🔒", "locked zone shows a lock")

activate(find(zones, "Zone1", "Action"))
near(root.CFrame.Position.Z, -12, "warped just inside zone 1")
equal(panel.Visible, false, "panel closes after warping")

task.wait(0.8)
Harness.signal(find(Remotes, "Warp"), "OnServerEvent"):Fire(player, 3)
near(root.CFrame.Position.Z, -12, "server refuses a warp to a locked zone")
Harness.signal(find(Remotes, "Warp"), "OnServerEvent"):Fire(player, "camp")
Harness.signal(find(Remotes, "Warp"), "OnServerEvent"):Fire(player, 99)
near(root.CFrame.Position.Z, -12, "server ignores nonsense warp requests")

----------------------------------------------------------------------------
stage("rekindle (rebirth)")

activate(find(hud, "Menu", "rebirth"))
local rebirth = find(panel, "Content", "Rebirth")
equal(rebirth.Visible, true, "rekindle panel visible")

if player:GetAttribute("Sparks") < 60 then
	activate(find(rebirth, "Rekindle"))
	equal(player:GetAttribute("Rebirths"), 0, "cannot rekindle early")
end
while player:GetAttribute("Sparks") < 60 do
	task.wait(0.2)
end
sync()
equal(find(hud, "Menu", "rebirth", "Badge").Visible, true, "badge shows rekindle is ready")

activate(find(rebirth, "Rekindle"))
sync()
equal(player:GetAttribute("Rebirths"), 1, "rekindled")
equal(player:GetAttribute("Sparks"), 0, "sparks reset")
equal(player:GetAttribute("Gems"), 0, "gems reset")
equal(player:GetAttribute("Upgrade_power"), 0, "power reset")
equal(player:GetAttribute("Upgrade_auto"), 0, "auto reset")
equal(player:GetAttribute("Upgrade_speed"), 1, "swift boots kept")
equal(humanoid.WalkSpeed, Config.BaseWalkSpeed + 1, "walk speed kept")
near(root.CFrame.Position.Z, 66, "sent back to camp")
equal(gates[1].CanCollide, true, "gate 1 closes again")
equal(pulseAmount.Text, "+2", "sparks doubled after one rekindle")
equal(find(toast, "Label").Text, "🔥 Rekindled! Sparks are now x2", "rekindle toast")
equal(panel.Visible, false, "panel closes after rekindling")
local tier = Config.LanternColors[2]
near(lantern.Color.G, tier[2] / 255, "lantern changes colour")
equal(find(player, "leaderstats", "Rekindles").Value, 1, "leaderboard shows rekindles")

----------------------------------------------------------------------------
stage("leaving saves, rejoining restores")

tap()
tap()
Harness.removePlayer(player)
local saved = store.data["player_1001"]
check(saved ~= nil, "profile saved on leave")
equal(saved.rebirths, 1, "saved rebirths")
equal(saved.sparks, 4, "saved sparks")
equal(saved.upgrades.speed, 1, "saved upgrades")

local again = Harness.addPlayer("Tester", 1001)
equal(again:GetAttribute("Loaded"), true, "returning player loads")
equal(again:GetAttribute("Rebirths"), 1, "rebirths restored")
equal(again:GetAttribute("Sparks"), 4, "sparks restored")
equal(again:GetAttribute("Upgrade_speed"), 1, "upgrades restored")

local setsBefore = store.sets
check(#Harness.closeCallbacks == 1, "shutdown handler registered")
Harness.run(Harness.closeCallbacks[1])
task.wait(0.3)
check(store.sets > setsBefore, "shutdown saves everyone")
Harness.removePlayer(again)

----------------------------------------------------------------------------
stage("data store outage")

Harness.dataStoreFails = true

-- In Studio: play on with a blank profile, and never write it back.
Harness.studio = true
local studioPlayer = Harness.addPlayer("StudioDev", 2002)
equal(studioPlayer:GetAttribute("Loaded"), true, "Studio session continues without saves")
check(Harness.kicked[studioPlayer] == nil, "Studio player is not kicked")
setsBefore = store.sets
Harness.dataStoreFails = false
Harness.removePlayer(studioPlayer)
equal(store.sets, setsBefore, "a profile that failed to load is never saved")
check(store.data["player_2002"] == nil, "no blank save written")

-- Live game: kick rather than risk overwriting the real save.
Harness.dataStoreFails = true
Harness.studio = false
local livePlayer = Harness.addPlayer("LivePlayer", 3003)
task.wait(5.2)
check(Harness.kicked[livePlayer] ~= nil, "live player is kicked when their save cannot be read")
check(livePlayer:GetAttribute("Loaded") ~= true, "kicked player never gets a session")
Harness.dataStoreFails = false

----------------------------------------------------------------------------
stage("done")

print("")
if #Harness.warnings > 0 then
	print("warnings logged by the game (expected for the outage test):")
	for _, warning in ipairs(Harness.warnings) do
		print("  " .. warning)
	end
end
if #failures > 0 then
	print(string.format("\nSMOKE TEST FAILED: %d of %d checks failed", #failures, checks))
	process.exit(1)
end
print(string.format("\nSMOKE TEST PASSED: %d checks", checks))
process.exit(0)
