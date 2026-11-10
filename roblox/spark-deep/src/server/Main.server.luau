-- Server entry point. Build the cave first (so it exists before anyone
-- spawns), then start the game loop.

local World = require(script.Parent:WaitForChild("World"))
local Game = require(script.Parent:WaitForChild("Game"))

World.applyLighting()
local built = World.build()
Game.start(built)

print(string.format("[+1 Spark] Cave ready: %d zones, %d crystals.", #built.zoneSpawns, #built.crystals))
