-- Thin wrapper around DataStoreService with retries.
-- Saving only works in a published experience (in Studio it also needs
-- Game Settings > Security > "Enable Studio Access to API Services").

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Store = {}

local dataStore = nil
local unavailable = false

local function getDataStore()
	if dataStore or unavailable then
		return dataStore
	end
	-- An unpublished place file has no experience to save into.
	if game.GameId == 0 then
		unavailable = true
		warn("[Store] This place is not published yet, so progress will not be saved.")
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		dataStore = result
	else
		unavailable = true
		warn("[Store] Data stores are unavailable: " .. tostring(result))
	end
	return dataStore
end

local function keyFor(userId: number): string
	return "player_" .. tostring(userId)
end

local function attempt(callback: () -> any): (boolean, any)
	-- In Studio a failure is almost always "API access is off", so don't make
	-- the developer wait through retries.
	local attempts = if RunService:IsStudio() then 1 else 3
	local lastError
	for try = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		if try < attempts then
			task.wait(try * 1.5)
		end
	end
	return false, lastError
end

-- Returns (true, savedData or nil) on success, (false, nil) when the load failed.
function Store.load(userId: number): (boolean, any)
	local store = getDataStore()
	if not store then
		return false, nil
	end
	local ok, result = attempt(function()
		return store:GetAsync(keyFor(userId))
	end)
	if not ok then
		warn("[Store] Could not load " .. keyFor(userId) .. ": " .. tostring(result))
		return false, nil
	end
	return true, result
end

function Store.save(userId: number, data: any): boolean
	local store = getDataStore()
	if not store then
		return false
	end
	local ok, result = attempt(function()
		store:SetAsync(keyFor(userId), data)
		return nil
	end)
	if not ok then
		warn("[Store] Could not save " .. keyFor(userId) .. ": " .. tostring(result))
	end
	return ok
end

-- True when a failed load should be forgiven (Studio or an unpublished file)
-- instead of kicking the player to protect their real save.
function Store.isTestSession(): boolean
	return RunService:IsStudio() or game.GameId == 0
end

return Store
