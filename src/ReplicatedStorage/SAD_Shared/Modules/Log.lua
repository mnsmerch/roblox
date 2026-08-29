--!strict
--[[
	Log
	ReplicatedStorage/SAD_Shared/Modules/Log  (ModuleScript)

	Scoped, level-filtered logging. Every SAD system logs through this so that
	output is greppable ("[SAD]") and so verbosity is one config change, not a
	find-and-replace across 24 services.

	Usage:
		local Log = require(Modules.Log)
		Log.info("DataService", "Loaded profile for %s", player.Name)
		Log.warn("Net", "Rate limit hit")

	Formatting only happens when varargs are supplied, so a message containing
	a literal '%' is safe to pass on its own.

	Depends on: GameConfig (for LogLevel).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("SAD_Shared")
	:WaitForChild("Config"):WaitForChild("GameConfig"))

local Log = {}

local LEVELS: { [string]: number } = {
	debug = 10,
	info = 20,
	warn = 30,
	error = 40,
	none = 100,
}

local CONTEXT = if RunService:IsServer() then "S" else "C"

local function threshold(): number
	return LEVELS[GameConfig.LogLevel] or LEVELS.info
end

local function compose(scope: string, message: string, ...: any): string
	local body = message
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, message, ...)
		body = if ok then formatted else message .. " <malformed log args>"
	end
	return string.format("[SAD/%s][%s] %s", CONTEXT, scope, body)
end

function Log.debug(scope: string, message: string, ...: any)
	if threshold() > LEVELS.debug then
		return
	end
	print(compose(scope, message, ...))
end

function Log.info(scope: string, message: string, ...: any)
	if threshold() > LEVELS.info then
		return
	end
	print(compose(scope, message, ...))
end

function Log.warn(scope: string, message: string, ...: any)
	if threshold() > LEVELS.warn then
		return
	end
	warn(compose(scope, message, ...))
end

--- Logs at error level. Does NOT throw - callers decide whether to propagate.
function Log.error(scope: string, message: string, ...: any)
	if threshold() > LEVELS.error then
		return
	end
	warn(compose(scope, "ERROR: " .. message, ...))
end

--- Big, hard-to-miss separator. Used by Bootstrap for phase boundaries.
function Log.banner(text: string)
	if threshold() > LEVELS.info then
		return
	end
	print(string.format("[SAD/%s] %s %s %s", CONTEXT, string.rep("=", 8), text, string.rep("=", 8)))
end

return Log
