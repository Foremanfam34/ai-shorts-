-- Number formatting shared by the HUD and the signs in the world.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 950 -> "950", 1250 -> "1.25K", 12500 -> "12.5K", 3000000 -> "3M".
-- Rounds down, so a requirement never looks met before it is.
function Format.abbreviate(value: number): string
	if type(value) ~= "number" or value ~= value then
		return "0"
	end

	local sign = if value < 0 then "-" else ""
	local scaled = math.abs(value)
	if scaled < 1000 then
		return sign .. tostring(math.floor(scaled + 1e-9))
	end

	local index = 1
	while scaled >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end

	local decimals = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	local factor = 10 ^ decimals
	scaled = math.floor(scaled * factor + 1e-9) / factor

	local text = string.format("%." .. decimals .. "f", scaled)
	if decimals > 0 then
		text = (string.gsub(text, "0+$", ""))
		text = (string.gsub(text, "%.$", ""))
	end
	return sign .. text .. SUFFIXES[index]
end

-- 2 -> "x2", 1.25 -> "x1.25", 1500 -> "x1.5K"
function Format.multiplier(value: number): string
	if value >= 1000 then
		return "x" .. Format.abbreviate(value)
	end
	local text = string.format("%.2f", value)
	text = (string.gsub(text, "0+$", ""))
	text = (string.gsub(text, "%.$", ""))
	return "x" .. text
end

return Format
