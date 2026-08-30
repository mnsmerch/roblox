--!nonstrict
--[[
	Stampede
	.../EventService/Handlers/Stampede  (ModuleScript)

	docs/04 §3 #2: "A herd of 40 dinosaurs charges hub -> zone along a marked
	lane. Tag one mid-run to capture it. Rewards: free dinosaur (Rare-
	Legendary), knockback comedy."

	Forty anchored models moved by CFrame, the same technique the guardians use
	(deviation #25): no Humanoids, no physics, unambiguously server-authoritative,
	and cheap enough that forty of them is not a decision anyone has to defend.

	One capture per player (`MaxCaptures`), because forty free dinosaurs is not
	an event, it is an economy reset.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local RNG = require(Shared.Modules.RNG)
local RarityConfig = require(Shared.Config.RarityConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local Stampede = {}

local HERD_SPEED = 46
local LANE_HALF_WIDTH = 26
local RUNNER_SIZE = Vector3.new(5, 6, 9)

--[[
	docs/04 says "Rare-Legendary". Weighted so a Legendary is the story rather
	than the expectation - the event is a free dinosaur, not a free Legendary.
]]
local CAPTURE_WEIGHTS = { rare = 70, epic = 25, legendary = 5 }

local function speciesFor(ctx, rarity: string): string?
	--[[
		DinoConfig.Species holds only what ships, so matching on rarity is the
		whole filter. Sorted before the pick so a seeded run is reproducible -
		pairs() order is not.
	]]
	local candidates = {}
	for id, entry in DinoConfig.Species do
		if entry.Rarity == rarity then
			table.insert(candidates, id)
		end
	end
	if #candidates == 0 then
		return nil
	end
	table.sort(candidates)
	return candidates[ctx.Rng:NextInteger(1, #candidates)]
end

function Stampede.Start(ctx)
	--[[
		The lane: hub centre out to a random zone. Marked with a flat strip so
		players can see where to stand, and so "do not stand in the lane" is a
		thing they can choose rather than discover.
	]]
	local zoneId = ZoneConfig.Order[ctx.Rng:NextInteger(1, #ZoneConfig.Order)]
	local origin = ZoneConfig.OriginOf(zoneId)
	local finish = origin and origin.Position or Vector3.new(0, 0, 0)

	local direction = finish.Magnitude > 0 and finish.Unit or Vector3.new(1, 0, 0)
	local start = direction * -60 -- just behind the hub centre

	ctx.ZoneId = zoneId
	ctx.Direction = direction
	ctx.Finish = finish
	ctx.MarkerPosition = (start + finish) * 0.5
	ctx.Captured = {}
	ctx.Runners = {}

	local length = (finish - start).Magnitude
	local lane = Instance.new("Part")
	lane.Name = "Lane"
	lane.Size = Vector3.new(LANE_HALF_WIDTH * 2, 0.4, length)
	lane.CFrame = CFrame.lookAt(start + direction * (length * 0.5), finish) * CFrame.Angles(0, math.pi, 0)
	lane.Color = Color3.fromRGB(120, 80, 40)
	lane.Material = Enum.Material.Sand
	lane.Transparency = 0.5
	lane.Anchored = true
	lane.CanCollide = false
	lane.Parent = ctx.Folder

	--[[
		Runners are spawned strung out behind the start rather than in a block,
		so the herd arrives as a stream with time to react to rather than a
		wall that passes in one second.
	]]
	local herdSize = ctx.Params.HerdSize or 40
	for index = 1, herdSize do
		local lateral = ctx.Rng:NextNumber(-LANE_HALF_WIDTH * 0.8, LANE_HALF_WIDTH * 0.8)
		local back = (index / herdSize) * 220

		local runner = Instance.new("Part")
		runner.Name = "Runner"
		runner.Size = RUNNER_SIZE
		runner.Color = Color3.fromRGB(150, 120, 80)
		runner.Material = Enum.Material.SmoothPlastic
		runner.Anchored = true
		runner.CanCollide = false
		runner.CastShadow = false
		runner.CFrame = CFrame.lookAt(
			start + direction * -back + Vector3.new(-direction.Z, 0, direction.X) * lateral
				+ Vector3.new(0, 3, 0),
			finish)
		runner.Parent = ctx.Folder

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Tag"
		prompt.ObjectText = "STAMPEDING DINOSAUR"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = ctx.Params.TagRange or 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = runner

		table.insert(ctx.Runners, { Model = runner, Prompt = prompt })

		--[[
			Tagging is a request. The server checks the runner is still running,
			checks this player has not already captured one, and only then
			mints anything - the prompt firing is never itself the grant.
		]]
		ctx.Trove:Connect(prompt.Triggered, function(player)
			Stampede.Capture(ctx, player, runner)
		end)
	end
end

--[[
	Captures one runner for one player. Idempotent per runner AND per player,
	which are two different guards: the first stops two players sharing a
	dinosaur, the second stops one player taking the whole herd.
]]
function Stampede.Capture(ctx, player: Player, runner: BasePart)
	if not runner.Parent or runner:GetAttribute("Captured") then
		return
	end

	local limit = ctx.Params.MaxCaptures or 1
	if (ctx.Captured[player] or 0) >= limit then
		ctx.Get("NotificationService").Toast(player, "STAMPEDE",
			"You have already captured one")
		return
	end

	local rarity = RNG.WeightedPick(CAPTURE_WEIGHTS, ctx.Rng) or "rare"
	local speciesId = speciesFor(ctx, rarity)
	if not speciesId then
		return
	end

	local uid, entry, reason = ctx.Get("DinosaurService").Create(player, {
		SpeciesId = speciesId,
		Rarity = rarity,
		Origin = ctx.ZoneId,
		-- Caught, not hatched: the same distinction Step 15 drew for raids.
		Acquired = "event",
	})

	if not uid then
		ctx.Get("NotificationService").Toast(player, "STAMPEDE", reason or "no room")
		return
	end

	runner:SetAttribute("Captured", true)
	ctx.Captured[player] = (ctx.Captured[player] or 0) + 1
	ctx.Score(player, 5)

	ctx.Get("NotificationService").Takeover(player, {
		Title = "CAUGHT IT!",
		Subtitle = ctx.Get("DinosaurService").DisplayNameOf(entry),
		Headline = string.upper(RarityConfig.Tiers[rarity].DisplayName),
		Duration = 3,
	})

	ctx.Get("DinosaurService").PlaceBest(player)
	runner:Destroy()
end

function Stampede.Tick(ctx, dt)
	local step = ctx.Direction * (HERD_SPEED * dt)

	for index = #ctx.Runners, 1, -1 do
		local runner = ctx.Runners[index].Model
		if not runner.Parent then
			table.remove(ctx.Runners, index)
			continue
		end

		runner.CFrame = runner.CFrame + step

		--[[
			A runner that reaches the zone is gone. Left running it would
			continue out past the map edge for the rest of the event, which is
			both silly and a growing pile of parts nobody can reach.
		]]
		if (runner.Position - ctx.Finish).Magnitude < 40 then
			runner:Destroy()
			table.remove(ctx.Runners, index)
		end
	end
end

function Stampede.Stop(ctx)
	-- The lane and every runner belong to the ctx Folder, which the Trove
	-- destroys. This only drops the references.
	ctx.Runners = {}
	ctx.Captured = {}
end

return Stampede
