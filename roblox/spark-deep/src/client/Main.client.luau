-- Client entry point.

local State = require(script.Parent:WaitForChild("State"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local Gates = require(script.Parent:WaitForChild("Gates"))
local Hud = require(script.Parent:WaitForChild("Hud"))

State.start()
Sounds.start()
Gates.start()
Hud.start()
