-- The whole on-screen interface, built in code: counters, the big PULSE
-- button, and the Upgrades / Zones / Rekindle panels. It only displays state
-- and sends requests; the server decides everything.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Formulas = require(Shared:WaitForChild("Formulas"))

local Sounds = require(script.Parent:WaitForChild("Sounds"))
local State = require(script.Parent:WaitForChild("State"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PulseRemote = Remotes:WaitForChild("Pulse")
local BuyUpgradeRemote = Remotes:WaitForChild("BuyUpgrade")
local RebirthRemote = Remotes:WaitForChild("Rebirth")
local WarpRemote = Remotes:WaitForChild("Warp")
local FeedbackRemote = Remotes:WaitForChild("Feedback")

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 214, 130)
local GEM = Color3.fromRGB(130, 222, 255)
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(196, 192, 216)
local PANEL = Color3.fromRGB(26, 23, 40)
local ROW = Color3.fromRGB(42, 38, 62)
local GREEN = Color3.fromRGB(84, 196, 118)
local RED = Color3.fromRGB(235, 95, 95)
local DISABLED = Color3.fromRGB(88, 84, 106)
local DARK_TEXT = Color3.fromRGB(54, 34, 6)

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium

local TITLES = { upgrades = "⬆️ Upgrades", zones = "🗺️ Zones", rebirth = "🔥 Rekindle" }

local PASSES = {
	{ key = "sparkBoost", id = Config.GamePasses.DoubleSparks, name = "2x Sparks", icon = "⚡", detail = "Double sparks from every pulse, forever" },
	{ key = "gemBoost", id = Config.GamePasses.DoubleGems, name = "2x Gems", icon = "💠", detail = "Double gems from every crystal, forever" },
}

local Hud = {}

local abbreviate = Format.abbreviate

----------------------------------------------------------------------------
-- Small building helpers
----------------------------------------------------------------------------

local function create(className: string, properties: { [string]: any }, children: { Instance }?): any
	local instance: any = Instance.new(className)
	for key, value in pairs(properties) do
		instance[key] = value
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end
	return instance
end

local function corner(radius: number): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function round(): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

local function border(color: Color3, thickness: number): UIStroke
	return create("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function text(properties: { [string]: any }): TextLabel
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = BODY_FONT,
		TextColor3 = WHITE,
		TextSize = 16,
		Text = "",
	})
	for key, value in pairs(properties) do
		label[key] = value
	end
	return label
end

local function listLayout(padding: number): UIListLayout
	return create("UIListLayout", { Padding = UDim.new(0, padding), SortOrder = Enum.SortOrder.LayoutOrder })
end

local function scrollList(name: string): ScrollingFrame
	return create("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Visible = false,
	}, { listLayout(8) })
end

----------------------------------------------------------------------------
-- Widgets that get refreshed
----------------------------------------------------------------------------

local gui: ScreenGui
local popupLayer: Frame
local scales: { UIScale } = {}
local currentScale = 1
local dirty = true

local sparksLabel: TextLabel
local gemsLabel: TextLabel
local progressFill: Frame
local progressLabel: TextLabel
local pulseAmountLabel: TextLabel
local pulseSquish: UIScale

local panel: Frame
local panelTitle: TextLabel
local bodies: { [string]: GuiObject } = {}
local openBody: string? = nil

local upgradeRows: { [string]: { name: TextLabel, detail: TextLabel, buy: TextButton } } = {}
local passRows: { { key: string, buy: TextButton } } = {}
local zoneRows: { [number]: { detail: TextLabel, warp: TextButton } } = {}
local badges: { [string]: Frame } = {}

local rebirthBoosts: TextLabel
local rebirthFill: Frame
local rebirthProgress: TextLabel
local rebirthButton: TextButton
local rebirthCount: TextLabel

local toastFrame: Frame
local toastLabel: TextLabel
local toastToken = 0

-- Every top-level widget gets a UIScale so the HUD fits phones and monitors.
local function scaled(instance: any): any
	local scale = Instance.new("UIScale")
	scale.Parent = instance
	table.insert(scales, scale)
	return instance
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	currentScale = math.clamp(math.min(viewport.X / 1150, viewport.Y / 640), 0.55, 1.35)
	for _, scale in ipairs(scales) do
		scale.Scale = currentScale
	end
end

----------------------------------------------------------------------------
-- Toasts and floating numbers
----------------------------------------------------------------------------

local function toast(message: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = message
	toastLabel.TextColor3 = color or WHITE
	toastFrame.Visible = true
	task.delay(2.8, function()
		if toastToken == token then
			toastFrame.Visible = false
		end
	end)
end

local livePopups = 0

local function popup(message: string, color: Color3, position: UDim2)
	if livePopups >= 14 then
		return
	end
	livePopups += 1
	local label = text({
		Name = "Popup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(220, 40),
		Font = TITLE_FONT,
		TextSize = math.floor(28 * currentScale + 0.5),
		TextColor3 = color,
		TextStrokeTransparency = 0.35,
		Text = message,
	})
	label.Parent = popupLayer

	local tween = TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = position + UDim2.fromOffset(0, -70),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	task.delay(0.75, function()
		label:Destroy()
		livePopups -= 1
	end)
end

----------------------------------------------------------------------------
-- Pulsing
----------------------------------------------------------------------------

local tokens = Config.PulseBurst
local lastRefill = os.clock()

local function pulse()
	if not State.loaded then
		return
	end
	-- Mirror the server's rate limit so we never show a number that won't count.
	local now = os.clock()
	tokens = math.min(Config.PulseBurst, tokens + (now - lastRefill) * Config.MaxPulsesPerSecond)
	lastRefill = now
	if tokens < 1 then
		return
	end
	tokens -= 1

	PulseRemote:FireServer()

	local gained = Formulas.sparksPerPulse(State.profile, State.perks)
	popup("+" .. abbreviate(gained), GOLD, UDim2.new(0.5, math.random(-80, 80), 1, -math.floor(190 * currentScale)))
	Sounds.play("pulse", 0.95 + math.random() * 0.2)

	pulseSquish.Scale = 0.9
	TweenService:Create(pulseSquish, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local heldInput: InputObject? = nil
local keyHeld = false
local holdTimer = 0

local function isPressInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isPulseKey(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX
end

local function stepHold(deltaTime: number)
	if heldInput == nil and not keyHeld then
		holdTimer = 0
		return
	end
	local interval = 1 / Config.HoldPulsesPerSecond
	holdTimer = math.min(holdTimer + deltaTime, interval * 2)
	while holdTimer >= interval do
		holdTimer -= interval
		pulse()
	end
end

----------------------------------------------------------------------------
-- Panels
----------------------------------------------------------------------------

local function showBody(name: string?)
	openBody = name
	panel.Visible = name ~= nil
	for bodyName, body in pairs(bodies) do
		body.Visible = bodyName == name
	end
	if name then
		panelTitle.Text = TITLES[name]
	end
	dirty = true
end

local function toggleBody(name: string)
	showBody(if openBody == name then nil else name)
end

local function upgradeDetail(id: string, level: number): string
	local definition = Config.Upgrades[id]
	local maxed = level >= definition.maxLevel
	local profile = State.profile

	if id == "power" then
		local multiplier = Formulas.rebirthSparkMultiplier(profile.rebirths) * State.perks.sparkBoost
		local now = "+" .. abbreviate(Formulas.basePower(level) * multiplier)
		if maxed then
			return now .. " sparks per pulse"
		end
		return now .. " → +" .. abbreviate(Formulas.basePower(level + 1) * multiplier) .. " sparks per pulse"
	elseif id == "auto" then
		local now = tostring(level * definition.perLevel) .. "/s"
		if maxed then
			return now .. " automatic pulses"
		end
		return now .. " → " .. tostring((level + 1) * definition.perLevel) .. "/s automatic pulses"
	elseif id == "gems" then
		local now = Format.multiplier(1 + level * definition.perLevel)
		if maxed then
			return now .. " gems from crystals"
		end
		return now .. " → " .. Format.multiplier(1 + (level + 1) * definition.perLevel) .. " gems from crystals"
	elseif id == "speed" then
		local now = "Speed " .. tostring(Config.BaseWalkSpeed + level * definition.perLevel)
		if maxed then
			return now .. " (kept when you rekindle)"
		end
		return now .. " → " .. tostring(Config.BaseWalkSpeed + (level + 1) * definition.perLevel) .. " (kept when you rekindle)"
	end
	return definition.description
end

local function buildRow(name: string, order: number, height: number, icon: string, title: string, buttonWidth: number)
	local nameLabel = text({
		Name = "Name",
		Position = UDim2.fromOffset(66, 8),
		Size = UDim2.new(1, -86 - buttonWidth, 0, 26),
		Font = TITLE_FONT,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = title,
	})
	local detail = text({
		Name = "Detail",
		Position = UDim2.fromOffset(66, 34),
		Size = UDim2.new(1, -86 - buttonWidth, 1, -40),
		TextSize = 14,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	})
	local action = create("TextButton", {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, buttonWidth, 1, -24),
		BackgroundColor3 = GREEN,
		BorderSizePixel = 0,
		Font = TITLE_FONT,
		TextSize = 19,
		TextColor3 = WHITE,
		Text = "",
	}, { corner(12) })
	local row = create("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, height),
		BackgroundColor3 = ROW,
		BorderSizePixel = 0,
	}, {
		corner(12),
		text({
			Name = "Icon",
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(0, 56, 1, 0),
			Font = TITLE_FONT,
			TextSize = 32,
			Text = icon,
		}),
		nameLabel,
		detail,
		action,
	})
	return row, nameLabel, detail, action
end

local function buildUpgrades(): ScrollingFrame
	local list = scrollList("Upgrades")

	for order, id in ipairs(Config.UpgradeOrder) do
		local definition = Config.Upgrades[id]
		local row, nameLabel, detail, buy = buildRow(id, order, 84, definition.icon, definition.name, 118)
		buy.Activated:Connect(function()
			BuyUpgradeRemote:FireServer(id)
		end)
		upgradeRows[id] = { name = nameLabel, detail = detail, buy = buy }
		row.Parent = list
	end

	-- Game passes only appear once their ids are filled in (see Config).
	for order, pass in ipairs(PASSES) do
		if pass.id ~= 0 then
			local row, _, detail, buy = buildRow(pass.key, 100 + order, 84, pass.icon, pass.name, 118)
			detail.Text = pass.detail
			buy.BackgroundColor3 = GOLD
			buy.TextColor3 = DARK_TEXT
			buy.Activated:Connect(function()
				if State.perks[pass.key] < 2 then
					MarketplaceService:PromptGamePassPurchase(player, pass.id)
				end
			end)
			table.insert(passRows, { key = pass.key, buy = buy })
			row.Parent = list
		end
	end

	return list
end

local function buildZones(): ScrollingFrame
	local list = scrollList("Zones")

	for index = 0, #Config.Zones do
		local zone = Config.Zones[index]
		local title = if zone then string.format("%d. %s", index, zone.name) else "Camp"
		local row, _, detail, warp = buildRow("Zone" .. index, index, 64, if zone then "💎" else "⛺", title, 96)
		if not zone then
			detail.Text = "Home base. Always open."
		end
		warp.Activated:Connect(function()
			if Formulas.zoneUnlocked(State.profile.sparks, index) then
				WarpRemote:FireServer(index)
				showBody(nil)
			end
		end)
		zoneRows[index] = { detail = detail, warp = warp }
		row.Parent = list
	end

	return list
end

local function buildRebirth(): Frame
	rebirthBoosts = text({
		Name = "Boosts",
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 62),
		Font = TITLE_FONT,
		TextSize = 22,
		TextColor3 = GOLD,
	})
	rebirthFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 140, 70),
		BorderSizePixel = 0,
	}, { corner(12) })
	rebirthProgress = text({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Font = TITLE_FONT,
		TextSize = 18,
		TextStrokeTransparency = 0.4,
		ZIndex = 2,
	})
	rebirthButton = create("TextButton", {
		Name = "Rekindle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 246),
		Size = UDim2.fromOffset(260, 64),
		BackgroundColor3 = DISABLED,
		BorderSizePixel = 0,
		Font = TITLE_FONT,
		TextSize = 26,
		TextColor3 = WHITE,
		Text = "🔥 REKINDLE",
	}, { corner(16) })
	rebirthCount = text({
		Name = "Count",
		Position = UDim2.fromOffset(0, 318),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 15,
		TextColor3 = MUTED,
	})

	rebirthButton.Activated:Connect(function()
		RebirthRemote:FireServer()
	end)

	return create("Frame", {
		Name = "Rebirth",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, {
		text({
			Name = "Description",
			Size = UDim2.new(1, 0, 0, 110),
			TextSize = 17,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = "Rekindle your lantern to start again, permanently stronger.\n\nYour sparks, gems and upgrades reset. Swift Boots stay.",
		}),
		rebirthBoosts,
		create("Frame", {
			Name = "Progress",
			Position = UDim2.fromOffset(0, 190),
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = ROW,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, { corner(12), rebirthFill, rebirthProgress }),
		rebirthButton,
		rebirthCount,
	})
end

local function buildPanel(): Frame
	panelTitle = text({
		Name = "Title",
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -90, 0, 42),
		Font = TITLE_FONT,
		TextSize = 28,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local close = create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = RED,
		BorderSizePixel = 0,
		Font = TITLE_FONT,
		TextSize = 22,
		TextColor3 = WHITE,
		Text = "X",
	}, { corner(12) })
	close.Activated:Connect(function()
		showBody(nil)
	end)

	bodies.upgrades = buildUpgrades()
	bodies.zones = buildZones()
	bodies.rebirth = buildRebirth()

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.new(1, -32, 1, -78),
	}, { bodies.upgrades, bodies.zones, bodies.rebirth })

	panel = create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 450),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = false,
	}, { corner(18), border(GOLD, 3), panelTitle, close, content })
	return panel
end

----------------------------------------------------------------------------
-- Always-visible HUD
----------------------------------------------------------------------------

local function buildPill(name: string, color: Color3, position: UDim2, anchor: Vector2): (Frame, TextLabel)
	local value = text({
		Name = "Value",
		Size = UDim2.fromScale(1, 1),
		Font = TITLE_FONT,
		TextSize = 28,
		TextColor3 = color,
	})
	local frame = create("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(214, 50),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, { round(), border(color, 2.5), value })
	return frame, value
end

local function buildTopBar(): Frame
	local sparksPill, sparksValue = buildPill("Sparks", GOLD, UDim2.fromScale(0, 0), Vector2.new(0, 0))
	local gemsPill, gemsValue = buildPill("Gems", GEM, UDim2.fromScale(1, 0), Vector2.new(1, 0))
	sparksLabel = sparksValue
	gemsLabel = gemsValue

	progressFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(214, 160, 60),
		BorderSizePixel = 0,
	}, { corner(12) })
	progressLabel = text({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Font = TITLE_FONT,
		TextSize = 17,
		TextStrokeTransparency = 0.4,
		ZIndex = 2,
	})

	return create("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(446, 100),
		BackgroundTransparency = 1,
	}, {
		sparksPill,
		gemsPill,
		create("Frame", {
			Name = "Progress",
			Position = UDim2.fromOffset(0, 58),
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, { corner(12), progressFill, progressLabel }),
	})
end

local function buildToast(): Frame
	toastLabel = text({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Font = TITLE_FONT,
		TextSize = 22,
	})
	toastFrame = create("Frame", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(446, 46),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
	}, { corner(14), border(WHITE, 2), toastLabel })
	return toastFrame
end

local function buildPulse(): Frame
	pulseAmountLabel = text({
		Name = "Amount",
		Position = UDim2.new(0, 0, 0.58, 0),
		Size = UDim2.new(1, 0, 0.3, 0),
		Font = TITLE_FONT,
		TextSize = 30,
		TextColor3 = DARK_TEXT,
		Text = "+1",
	})
	pulseSquish = Instance.new("UIScale")

	local pulseButton = create("TextButton", {
		Name = "Pulse",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, {
		round(),
		border(WHITE, 4),
		create("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 228, 140), Color3.fromRGB(255, 164, 60)),
			Rotation = 90,
		}),
		pulseSquish,
		text({
			Name = "Icon",
			Position = UDim2.new(0, 0, 0.1, 0),
			Size = UDim2.new(1, 0, 0.52, 0),
			Font = TITLE_FONT,
			TextSize = 58,
			Text = "✨",
		}),
		pulseAmountLabel,
	})

	pulseButton.InputBegan:Connect(function(input)
		if isPressInput(input) then
			heldInput = input
			holdTimer = 0
			pulse()
		end
	end)

	local hint = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then "Tap or hold to pulse"
		else "Click or hold  ·  E"

	return create("Frame", {
		Name = "PulseArea",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(240, 180),
		BackgroundTransparency = 1,
	}, {
		text({
			Name = "Hint",
			Size = UDim2.new(1, 0, 0, 22),
			Font = TITLE_FONT,
			TextSize = 16,
			TextTransparency = 0.15,
			TextStrokeTransparency = 0.5,
			Text = hint,
		}),
		pulseButton,
	})
end

local function buildMenuButton(name: string, order: number, icon: string, caption: string): TextButton
	local badge = create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 5, 0, -5),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = RED,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
	}, { round(), border(WHITE, 2) })
	badges[name] = badge

	local menuButton = create("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Text = "",
	}, {
		corner(18),
		border(GOLD, 2.5),
		text({
			Name = "Icon",
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 48),
			Font = TITLE_FONT,
			TextSize = 36,
			Text = icon,
		}),
		text({
			Name = "Caption",
			Position = UDim2.new(0, 0, 1, -28),
			Size = UDim2.new(1, 0, 0, 22),
			Font = TITLE_FONT,
			TextSize = 15,
			TextColor3 = GOLD,
			Text = caption,
		}),
		badge,
	})
	menuButton.Activated:Connect(function()
		toggleBody(name)
	end)
	return menuButton
end

local function buildMenu(): Frame
	return create("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.4, 0),
		Size = UDim2.fromOffset(84, 272),
		BackgroundTransparency = 1,
	}, {
		listLayout(10),
		buildMenuButton("upgrades", 1, "⬆️", "Upgrades"),
		buildMenuButton("zones", 2, "🗺️", "Zones"),
		buildMenuButton("rebirth", 3, "🔥", "Rekindle"),
	})
end

----------------------------------------------------------------------------
-- Refresh (runs at most once per frame, only when something changed)
----------------------------------------------------------------------------

local function setButton(button: TextButton, label: string, enabled: boolean, color: Color3?)
	button.Text = label
	button.BackgroundColor3 = if enabled then (color or GREEN) else DISABLED
	button.AutoButtonColor = enabled
end

local function refresh()
	local profile = State.profile
	local perks = State.perks
	gui.Enabled = State.loaded

	sparksLabel.Text = "✨ " .. abbreviate(profile.sparks)
	gemsLabel.Text = "💎 " .. abbreviate(profile.gems)
	pulseAmountLabel.Text = "+" .. abbreviate(Formulas.sparksPerPulse(profile, perks))

	local nextIndex = Formulas.nextZone(profile.sparks)
	if nextIndex then
		local zone = Config.Zones[nextIndex]
		local previous = if nextIndex > 1 then Config.Zones[nextIndex - 1].required else 0
		local fraction = math.clamp((profile.sparks - previous) / (zone.required - previous), 0, 1)
		progressFill.Size = UDim2.fromScale(fraction, 1)
		progressLabel.Text = string.format("Next: %s  ·  %s / %s ✨", zone.name, abbreviate(profile.sparks), abbreviate(zone.required))
	else
		progressFill.Size = UDim2.fromScale(1, 1)
		progressLabel.Text = "Every zone is open! Rekindle to grow stronger 🔥"
	end

	-- Upgrades
	local anyAffordable = false
	for _, id in ipairs(Config.UpgradeOrder) do
		local widgets = upgradeRows[id]
		local level = profile.upgrades[id] or 0
		local cost = Formulas.upgradeCost(id, level)
		widgets.name.Text = string.format("%s  Lv %d", Config.Upgrades[id].name, level)
		widgets.detail.Text = upgradeDetail(id, level)
		if cost == nil then
			setButton(widgets.buy, "MAX", false)
		else
			local affordable = profile.gems >= cost
			anyAffordable = anyAffordable or affordable
			setButton(widgets.buy, "💎 " .. abbreviate(cost), affordable)
		end
	end
	for _, pass in ipairs(passRows) do
		pass.buy.Text = if perks[pass.key] >= 2 then "Owned" else "Get"
	end

	-- Zones
	for index, widgets in pairs(zoneRows) do
		local zone = Config.Zones[index]
		local unlocked = Formulas.zoneUnlocked(profile.sparks, index)
		if zone then
			widgets.detail.Text = string.format(
				"Needs %s ✨  ·  💎 %s per crystal",
				abbreviate(zone.required),
				abbreviate(Formulas.gemsForCrystal(profile, index, perks))
			)
		end
		setButton(widgets.warp, if unlocked then "Warp" else "🔒", unlocked)
	end

	-- Rekindle
	local requirement = Formulas.rebirthRequirement(profile.rebirths)
	local canRebirth = profile.sparks >= requirement
	rebirthBoosts.Text = string.format(
		"✨ Sparks %s → %s\n💎 Gems %s → %s",
		Format.multiplier(Formulas.rebirthSparkMultiplier(profile.rebirths)),
		Format.multiplier(Formulas.rebirthSparkMultiplier(profile.rebirths + 1)),
		Format.multiplier(Formulas.rebirthGemMultiplier(profile.rebirths)),
		Format.multiplier(Formulas.rebirthGemMultiplier(profile.rebirths + 1))
	)
	rebirthFill.Size = UDim2.fromScale(math.clamp(profile.sparks / requirement, 0, 1), 1)
	rebirthProgress.Text = string.format("%s / %s ✨", abbreviate(profile.sparks), abbreviate(requirement))
	setButton(rebirthButton, "🔥 REKINDLE", canRebirth, Color3.fromRGB(240, 120, 50))
	rebirthCount.Text = string.format("Rekindled %d time%s", profile.rebirths, if profile.rebirths == 1 then "" else "s")

	badges.upgrades.Visible = anyAffordable
	badges.zones.Visible = false
	badges.rebirth.Visible = canRebirth
end

----------------------------------------------------------------------------
-- Messages from the server
----------------------------------------------------------------------------

local function onFeedback(kind: any, value: any)
	if kind == "collect" and type(value) == "number" then
		popup("+" .. abbreviate(value) .. " 💎", GEM, UDim2.new(0.5, math.random(-60, 60), 0.42, 0))
		Sounds.play("collect", 0.95 + math.random() * 0.2)
	elseif kind == "zone" then
		local zone = Config.Zones[value]
		if zone then
			toast("🔓 " .. zone.name .. " unlocked!", Color3.fromRGB(zone.crystal[1], zone.crystal[2], zone.crystal[3]))
			Sounds.play("unlock")
		end
	elseif kind == "bought" then
		Sounds.play("buy")
	elseif kind == "rebirth" and type(value) == "number" then
		showBody(nil)
		toast("🔥 Rekindled! Sparks are now " .. Format.multiplier(Formulas.rebirthSparkMultiplier(value)), GOLD)
		Sounds.play("unlock", 0.85)
	elseif kind == "denied" then
		Sounds.play("denied")
		if value == "gems" then
			toast("Not enough gems 💎", RED)
		elseif value == "rebirth" then
			toast("Your lantern isn't bright enough yet", RED)
		end
	end
end

----------------------------------------------------------------------------
-- Start
----------------------------------------------------------------------------

function Hud.start()
	local playerGui = player:WaitForChild("PlayerGui")

	popupLayer = create("Frame", {
		Name = "Popups",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
	})

	-- The toast sits just under the top bar.
	local toastHolder = create("Frame", {
		Name = "ToastHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(446, 160),
		BackgroundTransparency = 1,
	}, { buildToast() })
	toastFrame.Position = UDim2.new(0.5, 0, 0, 112)

	gui = create("ScreenGui", {
		Name = "SparkHud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Enabled = false,
	}, {
		scaled(buildTopBar()),
		scaled(toastHolder),
		scaled(buildPulse()),
		scaled(buildMenu()),
		scaled(buildPanel()),
		popupLayer,
	})
	gui.Parent = playerGui

	updateScale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	-- Releasing the press (anywhere on screen) stops the hold.
	UserInputService.InputEnded:Connect(function(input)
		if heldInput and (input == heldInput or (isPressInput(input) and input.UserInputType == heldInput.UserInputType and input.UserInputType == Enum.UserInputType.MouseButton1)) then
			heldInput = nil
		end
		if isPulseKey(input) then
			keyHeld = false
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not isPulseKey(input) then
			return
		end
		keyHeld = true
		holdTimer = 0
		pulse()
	end)

	FeedbackRemote.OnClientEvent:Connect(onFeedback)
	State.onChanged(function()
		dirty = true
	end)

	RunService.RenderStepped:Connect(function(deltaTime)
		stepHold(deltaTime)
		if dirty then
			dirty = false
			refresh()
		end
	end)
end

return Hud
