--!nonstrict
--[[
	AmberRain
	.../EventService/Handlers/AmberRain  (ModuleScript)

	docs/04 §3 #8: "Amber chunks rain over the hub; collect for Fossils + DNA.
	Fossils, DNA - the catch-up mechanic."

	Catch-up is the design intent, and it decides the reward shape: a FLAT
	amount per chunk rather than a share of income. Scaling it would make it
	worth most to the player who needs it least, which is the opposite of what
	docs/04 says this event is for.

	Chunks are claimed server-side. The part is scenery; touching it is a
	request, and the server decides whether that chunk was still there.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local ZoneConfig = require(Shared.Config.ZoneConfig)

local AmberRain = {}

local FALL_SPEED = 26
local CHUNK_SIZE = Vector3.new(3, 3, 3)
local CLAIM_RANGE = 9
local GROUND_Y = 3

local function spawnChunk(ctx)
	local angle = ctx.Rng:NextNumber(0, math.pi * 2)
	local radius = ctx.Rng:NextNumber(0, ctx.Params.SpawnRadius or 260)

	local chunk = Instance.new("Part")
	chunk.Name = "AmberChunk"
	chunk.Size = CHUNK_SIZE
	chunk.Shape = Enum.PartType.Block
	chunk.Material = Enum.Material.Neon
	chunk.Color = Color3.fromHex("FFB020")
	chunk.Transparency = 0.15
	chunk.Anchored = true
	chunk.CanCollide = false
	chunk.CastShadow = false
	chunk.CFrame = CFrame.new(
		math.cos(angle) * radius,
		ctx.Rng:NextNumber(140, 220),
		math.sin(angle) * radius
	) * CFrame.Angles(ctx.Rng:NextNumber(0, 3), ctx.Rng:NextNumber(0, 3), 0)
	chunk.Parent = ctx.Folder

	return chunk
end

function AmberRain.Start(ctx)
	--[[
		Falling amber is the marker: it is visible from anywhere in the hub, so
		the event does not need a separate arrow pointing at itself.
	]]
	ctx.MarkerPosition = Vector3.new(0, 0, 0)
	ctx.Chunks = {}
	ctx.Spawned = 0
	ctx.SpawnAccumulator = 0

	--[[
		Spread across the whole event rather than dumped at the start, so
		arriving thirty seconds late still leaves something to collect - the
		catch-up mechanic being unreachable if you were slow would be a poor
		joke.
	]]
	ctx.SpawnRate = (ctx.Params.ChunkCount or 60) / math.max(1, ctx.Entry.DurationSecs)
end

function AmberRain.Tick(ctx, dt)
	local EconomyService = ctx.Get("EconomyService")

	-- Spawn.
	ctx.SpawnAccumulator += ctx.SpawnRate * dt
	while ctx.SpawnAccumulator >= 1 and ctx.Spawned < (ctx.Params.ChunkCount or 60) do
		ctx.SpawnAccumulator -= 1
		ctx.Spawned += 1
		table.insert(ctx.Chunks, spawnChunk(ctx))
	end

	-- Fall, and be claimed.
	for index = #ctx.Chunks, 1, -1 do
		local chunk = ctx.Chunks[index]
		if not chunk.Parent then
			table.remove(ctx.Chunks, index)
			continue
		end

		local position = chunk.Position - Vector3.new(0, FALL_SPEED * dt, 0)
		chunk.CFrame = CFrame.new(position) * (chunk.CFrame - chunk.CFrame.Position)

		--[[
			Claimed by proximity, measured on the SERVER at the moment of the
			grant. A Touched event would be the client's physics deciding who
			got paid, which is the one thing docs/03 §6 is a list of reasons
			not to do.
		]]
		local claimed = false
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - position).Magnitude <= CLAIM_RANGE then
				EconomyService.AddFossils(player, ctx.Params.ChunkFossils or 400, "amber rain")
				EconomyService.AddDna(player, ctx.Params.ChunkDna or 2, "amber rain")
				ctx.Score(player, 1)
				claimed = true
				break
			end
		end

		if claimed or position.Y <= GROUND_Y then
			-- Uncollected amber sinks into the ground rather than piling up:
			-- a hub carpeted in unclaimed parts is a performance problem and
			-- an ugly one.
			chunk:Destroy()
			table.remove(ctx.Chunks, index)
		end
	end
end

function AmberRain.Stop(ctx)
	--[[
		The ctx Folder is on the Trove, so every chunk is destroyed with it.
		This only clears the list, so a Stop that ran twice would not walk
		destroyed instances.
	]]
	ctx.Chunks = {}
end

return AmberRain
