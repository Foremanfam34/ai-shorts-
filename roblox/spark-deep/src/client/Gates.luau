-- Opens zone gates for this player only.
-- Gates are solid on the server. Each client makes the gates it has earned
-- passable and see-through. Walking through a gate early gains nothing: the
-- server checks the lantern again before paying out any crystal.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local State = require(script.Parent:WaitForChild("State"))

local GATE_TAG = "ZoneGate"
local OPEN_COLOR = Color3.fromRGB(140, 255, 170)

local Gates = {}

local function apply(gate: Instance)
	if not gate:IsA("BasePart") then
		return
	end
	local zone = Config.Zones[gate:GetAttribute("Zone")]
	if not zone then
		return
	end
	local required = zone.required
	local open = State.profile.sparks >= required

	gate.CanCollide = not open
	gate.Transparency = if open then 0.93 else 0.25

	local sign = gate:FindFirstChild("Sign")
	local label = sign and sign:FindFirstChild("Requirement")
	if label and label:IsA("TextLabel") then
		if open then
			label.Text = "OPEN"
			label.TextColor3 = OPEN_COLOR
		else
			label.Text = "🔒 " .. Format.abbreviate(required) .. " ✨"
			label.TextColor3 = gate.Color
		end
	end
end

local function applyAll()
	for _, gate in ipairs(CollectionService:GetTagged(GATE_TAG)) do
		apply(gate)
	end
end

function Gates.start()
	applyAll()
	CollectionService:GetInstanceAddedSignal(GATE_TAG):Connect(apply)
	State.onChanged(applyAll)
end

return Gates
