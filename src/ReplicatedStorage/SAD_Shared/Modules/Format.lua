--!strict
--[[
	Format
	ReplicatedStorage/SAD_Shared/Modules/Format  (ModuleScript)

	Every number a player sees goes through here. Consistency matters more than
	cleverness: 1.2K in the HUD must be 1.2K in the shop and 1.2K in a toast.

	Number() uses short-scale suffixes to Dc (1e33), then two-letter notation
	(aa, ab, ...) which is the convention Roblox idle-game players already read.

	Depends on: nothing.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local LETTER_A = 97

--- Two-letter suffix for tiers past the named list. index 1 -> "aa".
local function letterSuffix(index: number): string
	local n = index - 1
	local first = math.floor(n / 26) % 26
	local second = n % 26
	return string.char(LETTER_A + first) .. string.char(LETTER_A + second)
end

local function suffixFor(tier: number): string
	if tier < #SUFFIXES then
		return SUFFIXES[tier + 1]
	end
	return letterSuffix(tier - #SUFFIXES + 1)
end

--- Trims "1.00" -> "1", "1.20" -> "1.2". Only touches strings with a decimal point.
local function trimZeros(text: string): string
	if not string.find(text, ".", 1, true) then
		return text
	end
	local trimmed = string.gsub(text, "0+$", "")
	trimmed = string.gsub(trimmed, "%.$", "")
	return trimmed
end

--[[
	Compact display: 999 -> "999", 1234 -> "1.23K", 45600000 -> "45.6M".
	Always at most 3 significant digits so column widths stay stable.
]]
function Format.Number(value: number): string
	if value ~= value then -- NaN
		return "0"
	end
	if value == math.huge then
		return "MAX"
	end

	local sign = if value < 0 then "-" else ""
	local abs = math.abs(value)

	if abs < 1000 then
		return sign .. tostring(math.floor(abs))
	end

	local tier = math.floor(math.log(abs, 10) / 3)

	-- log10 drift can put us one tier out at exact boundaries; correct it.
	local mantissa = abs / (1000 ^ tier)
	if mantissa >= 1000 then
		tier += 1
		mantissa = abs / (1000 ^ tier)
	elseif mantissa < 1 and tier > 0 then
		tier -= 1
		mantissa = abs / (1000 ^ tier)
	end

	local text: string
	if mantissa < 10 then
		text = string.format("%.2f", mantissa)
	elseif mantissa < 100 then
		text = string.format("%.1f", mantissa)
	else
		text = string.format("%.0f", mantissa)
	end

	-- Rounding can push 999.995 -> "1000"; promote a tier rather than show it.
	if (tonumber(text) or 0) >= 1000 then
		tier += 1
		mantissa = abs / (1000 ^ tier)
		text = string.format("%.2f", mantissa)
	end

	return sign .. trimZeros(text) .. suffixFor(tier)
end

--- Full precision with thousands separators: 1234567 -> "1,234,567".
function Format.Comma(value: number): string
	local sign = if value < 0 then "-" else ""
	local digits = tostring(math.floor(math.abs(value)))

	local out = digits
	while true do
		local replaced: number
		out, replaced = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end

	return sign .. out
end

--- Human duration: "2d 4h", "3h 12m", "5m 30s", "42s".
function Format.Time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))

	local days = math.floor(seconds / 86400)
	local hours = math.floor(seconds % 86400 / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	local secs = seconds % 60

	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

--- Countdown display: "04:32", or "1:04:32" past an hour.
function Format.Clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))

	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	local secs = seconds % 60

	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%02d:%02d", minutes, secs)
end

--[[
	The number players screenshot: "1 IN 5,263,157".
	weight and total come straight from the integer weight tables, so this is
	exact - no float odds, no rounding surprises in an announcement.
]]
function Format.Odds(weight: number, total: number): string
	if weight <= 0 then
		return "IMPOSSIBLE"
	end
	if weight >= total then
		return "1 IN 1"
	end
	return "1 IN " .. Format.Comma(math.floor(total / weight + 0.5))
end

--- 0.35 -> "35%". Pass decimals for finer granularity.
function Format.Percent(fraction: number, decimals: number?): string
	local places = decimals or 0
	return string.format("%." .. places .. "f%%", fraction * 100)
end

--- Multiplier chips: 2 -> "x2", 3.5 -> "x3.5".
function Format.Multiplier(value: number): string
	return "x" .. trimZeros(string.format("%.2f", value))
end

return Format
