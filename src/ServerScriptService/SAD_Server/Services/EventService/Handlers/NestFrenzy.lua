--!nonstrict
--[[
	NestFrenzy
	.../EventService/Handlers/NestFrenzy  (ModuleScript)

	docs/04 §3 #3: "Every nest server-wide respawns in 3 s and guardians are
	20 % slower. Pure volume - the best farming window."

	The cheapest event in the game to run and one of the best to play, because
	it builds nothing: it changes two numbers other services already read, and
	puts them back on Stop.

	That is also what makes it the one to get wrong quietly. A multiplier left
	behind is a permanently trivial game, and nothing throws.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local ZoneConfig = require(Shared.Config.ZoneConfig)

local NestFrenzy = {}

function NestFrenzy.Start(ctx)
	local NestService = ctx.Get("NestService")
	local WildAIService = ctx.Get("WildAIService")
	local EggService = ctx.Get("EggService")

	--[[
		Stored so Stop restores what was THERE rather than assuming 1. If
		anything else is ever scaling these, restoring to 1 would silently
		cancel it instead of ending this event.
	]]
	ctx.PreviousRespawn = NestService.EventRespawnMultiplier
	ctx.PreviousGuardian = WildAIService.EventSpeedMultiplier

	--[[
		docs/04 gives an absolute "respawns in 3 s", but the respawn pipeline
		is multiplicative (weather scales it too). Derived from the SLOWEST
		nest in the game, so the slowest becomes 3 s and every other nest is
		quicker - which is what "every nest respawns in 3 s" promises as a
		ceiling rather than as an exact figure.
	]]
	local target = ctx.Params.RespawnSecs or 3
	local slowest = 0
	for _, zoneId in ZoneConfig.Order do
		local zone = ZoneConfig.Get(zoneId)
		if zone then
			slowest = math.max(slowest, zone.RespawnSecs)
		end
	end

	NestService.EventRespawnMultiplier = if slowest > 0 then target / slowest else 1
	WildAIService.EventSpeedMultiplier = ctx.Params.GuardianSpeedMult or 0.8

	--[[
		A frenzy has nothing to tag or collect, so participation is measured
		the only honest way available: by taking eggs. The connection is on the
		ctx Trove, so it cannot outlive the event.
	]]
	ctx.Trove:Connect(EggService.EggPickedUp, function(player)
		ctx.Score(player, 1)
	end)
end

function NestFrenzy.Stop(ctx)
	local NestService = ctx.Get("NestService")
	local WildAIService = ctx.Get("WildAIService")

	NestService.EventRespawnMultiplier = ctx.PreviousRespawn or 1
	WildAIService.EventSpeedMultiplier = ctx.PreviousGuardian or 1
end

return NestFrenzy
