--!nonstrict
--[[
	MeteorImpact
	.../EventService/Handlers/MeteorImpact  (ModuleScript)

	docs/04 §3 #1: "A meteor lands at a random zone with a 15 s telegraphed
	shadow. Crater spawns 8 mutated eggs (guaranteed mutation, Radioactive
	weight x20). Rewards: eggs, first-to-arrive bonus."

	Two halves ship and one does not. The guaranteed mutation is the half that
	matters and it ships; the Radioactive skew needs the Radioactive mutation,
	which is V1.6 content (docs/12). Skewing towards something that cannot be
	rolled would be a line of code that does nothing, so it waits for the thing
	it skews towards.

	The 15-second shadow is the event: it is what turns "eggs appeared" into
	"everyone is already running". Nothing spawns until it lands.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local RarityConfig = require(Shared.Config.RarityConfig)
local RNG = require(Shared.Modules.RNG)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local MeteorImpact = {}

local CRATER_RADIUS = 34
local EGG_RING_RADIUS = 18
local FIRST_BONUS_RANGE = 60

--[[
	Crater eggs skew a tier up on the zone they land in, because a meteor
	should be worth crossing the map for. Rolled per egg from the zone's own
	weights so a Zone 1 crater is still a Zone 1 crater - the event improves
	the odds, it does not ignore progression.
]]
local function rollRarity(ctx, zoneId): string
	local weights = RarityConfig.WeightsForZone(zoneId)
	if not weights then
		return "common"
	end

	local picked = RNG.WeightedPick(weights, ctx.Rng) or "common"

	--[[
		One free upgrade, but only into a tier the zone can already produce -
		so a crater never hands out a rarity the zone's own nest sign does not
		advertise. In V1 that means Mythic and Ancient stay unreachable here,
		because their zone weights are zero (deviation #6).
	]]
	local upgraded = RarityConfig.TierAbove(picked)
	return if (weights[upgraded] or 0) > 0 then upgraded else picked
end

function MeteorImpact.Start(ctx)
	local EggService = ctx.Get("EggService")

	--[[
		"A random zone" - and any zone, not only the ones this server's players
		have unlocked. docs/04 §3.1: "Events never require a zone unlock to
		participate in - they are the main catch-up mechanism."
	]]
	local zoneId = ZoneConfig.Order[ctx.Rng:NextInteger(1, #ZoneConfig.Order)]
	local origin = ZoneConfig.OriginOf(zoneId)
	local landing = origin and (origin * CFrame.new(0, 0, 0)).Position or Vector3.new(0, 0, 0)

	ctx.ZoneId = zoneId
	ctx.Landing = landing
	ctx.MarkerPosition = landing
	ctx.Landed = false
	ctx.FirstClaimed = false

	--[[
		The telegraph. A flat dark disc on the ground, growing for fifteen
		seconds - readable from across the map and cheap enough to be one part.
	]]
	local shadow = Instance.new("Part")
	shadow.Name = "MeteorShadow"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Size = Vector3.new(1, 4, 4)
	shadow.CFrame = CFrame.new(landing + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shadow.Color = Color3.fromRGB(20, 12, 8)
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Transparency = 0.35
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.Parent = ctx.Folder
	ctx.Shadow = shadow

	ctx.TelegraphSecs = ctx.Entry.TelegraphSecs or 15
	ctx.Elapsed = 0
end

--[[
	The impact. Everything that exists afterwards is created here, in one
	place, so the teardown is the ctx Folder and nothing else.
]]
local function land(ctx)
	local EggService = ctx.Get("EggService")
	ctx.Landed = true

	if ctx.Shadow then
		ctx.Shadow:Destroy()
		ctx.Shadow = nil
	end

	local crater = Instance.new("Part")
	crater.Name = "Crater"
	crater.Shape = Enum.PartType.Cylinder
	crater.Size = Vector3.new(3, CRATER_RADIUS * 2, CRATER_RADIUS * 2)
	crater.CFrame = CFrame.new(ctx.Landing + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	crater.Color = Color3.fromRGB(38, 26, 20)
	crater.Material = Enum.Material.Ground
	crater.Anchored = true
	crater.CanCollide = false
	crater.Parent = ctx.Folder

	local core = Instance.new("Part")
	core.Name = "MeteorCore"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(12, 12, 12)
	core.CFrame = CFrame.new(ctx.Landing + Vector3.new(0, 4, 0))
	core.Color = Color3.fromRGB(255, 120, 40)
	core.Material = Enum.Material.Neon
	core.Anchored = true
	core.CanCollide = false
	core.Parent = ctx.Folder

	--[[
		The eggs. Spawned through EggService.SpawnEventEgg so they are ordinary
		loose eggs from that moment on - same grab prompt, same carry token,
		same deposit. An event egg is never a second kind of egg.
	]]
	local count = ctx.Params.EggCount or 8
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local position = ctx.Landing + Vector3.new(
			math.cos(angle) * EGG_RING_RADIUS, 3, math.sin(angle) * EGG_RING_RADIUS)

		EggService.SpawnEventEgg({
			Rarity = rollRarity(ctx, ctx.ZoneId),
			Origin = ctx.ZoneId,
			Mutated = ctx.Params.Guaranteed == true,
		}, position)
	end
end

function MeteorImpact.Tick(ctx, dt)
	ctx.Elapsed += dt

	if not ctx.Landed then
		-- The shadow grows to the crater's size over the telegraph.
		local progress = math.clamp(ctx.Elapsed / ctx.TelegraphSecs, 0, 1)
		if ctx.Shadow then
			local diameter = 4 + (CRATER_RADIUS * 2 - 4) * progress
			ctx.Shadow.Size = Vector3.new(1, diameter, diameter)
			ctx.Shadow.Transparency = 0.35 - progress * 0.2
		end

		if progress >= 1 then
			land(ctx)
		end
		return
	end

	--[[
		The first-to-arrive bonus, paid once. Awarded on presence rather than
		on grabbing an egg, so the player who sprinted and lost the race to the
		egg itself still gets something for having run.
	]]
	if not ctx.FirstClaimed then
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - ctx.Landing).Magnitude <= FIRST_BONUS_RANGE then
				ctx.FirstClaimed = true
				ctx.Get("EconomyService").AddFossils(player,
					ctx.Params.FirstBonusFossils or 2500, "meteor first arrival")
				ctx.Get("NotificationService").Banner(player, "FIRST TO THE CRATER!", { Duration = 3 })
				ctx.Score(player, 3)
				break
			end
		end
	end
end

function MeteorImpact.Stop(ctx)
	--[[
		The crater and the meteor go with the ctx Folder. The EGGS deliberately
		do not: they are loose eggs now, with EggService's own lifetime timer,
		and destroying an egg out from under someone running for it would be a
		worse bug than one that lingers thirty seconds.
	]]
	ctx.Shadow = nil
end

return MeteorImpact
