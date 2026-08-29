--!nonstrict
--[[
	NestBuilder
	.../Services/NestService/NestBuilder  (ModuleScript)

	Builds one nest at a tagged anchor: the bowl, its eggs, and the sign that
	tells a player what they are about to risk.

	The sign is the whole point of the approach beat in docs/03 §1.1. A player
	reads the guardian, the risk, and the odds, and THEN decides. Without it a
	nest is a button; with it, stealing is a choice - which is what makes the
	chase feel earned rather than random.

	Eggs in a nest are deliberately GENERIC. Rarity is not rolled until pickup
	(docs/03 §1.1), so a nest egg that looked Legendary would be a lie, and one
	that looked Common would spoil the reveal.

	Depends on: DinoConfig, RarityConfig, ZoneConfig, Format, RNG.
	Owned by: NestService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Format = require(Shared.Modules.Format)
local RNG = require(Shared.Modules.RNG)

local NestBuilder = {}

NestBuilder.BowlRadius = 9
NestBuilder.EggSpacing = 4.5
NestBuilder.PromptHoldSecs = 0.6 -- docs/03 §1.1

--[[
	Which species guards this nest.

	Drawn from the zone's COMMON, UNCOMMON and RARE species only. A Titan Rex
	standing over a Zone 1 nest would be absurd, and more practically it would
	misprice the risk: the sign is a promise about how hard the escape will be,
	and the guardian is not related to what the egg turns out to be.

	Seeded from the nest's identity, so a nest keeps its guardian across
	sessions and players learn which nests are worth the trip.
]]
function NestBuilder.PickGuardian(zoneId: string, nestIndex: number): string?
	local candidates = {}
	for _, rarityId in { "common", "uncommon", "rare" } do
		for _, speciesId in DinoConfig.SpeciesFor(zoneId, rarityId) do
			table.insert(candidates, speciesId)
		end
	end
	if #candidates == 0 then
		return nil
	end

	table.sort(candidates)

	-- Deterministic per nest: same zone and index always give the same guardian.
	local seed = nestIndex * 7919
	for index = 1, #zoneId do
		seed += string.byte(zoneId, index) * index
	end
	return candidates[(seed % #candidates) + 1]
end

--[[
	Risk, 1 to 5, shown as skulls.

	Zone order sets the floor, and a Rare guardian adds one - so Zone 1 reads
	1 or 2 and Zone 4 reads 4 or 5. Deliberately coarse: a player glancing at a
	sign mid-run needs a number they can feel, not a formula.
]]
function NestBuilder.RiskOf(zoneId: string, guardianSpeciesId: string?): number
	local zone = ZoneConfig.Zones[zoneId]
	local risk = zone and zone.Order or 1

	local guardian = guardianSpeciesId and DinoConfig.Get(guardianSpeciesId)
	if guardian and RarityConfig.RankOf(guardian.Rarity) >= 3 then
		risk += 1
	end

	return math.clamp(risk, 1, 5)
end

local function makeSignText(zoneId: string, nestIndex: number, guardianSpeciesId: string?): (string, string, string)
	local zone = ZoneConfig.Zones[zoneId]
	local guardian = guardianSpeciesId and DinoConfig.Get(guardianSpeciesId)
	local risk = NestBuilder.RiskOf(zoneId, guardianSpeciesId)

	local header = string.format("%s  ·  NEST %d", string.upper(zone.DisplayName), nestIndex)
	local guardianLine = string.format("Guardian: %s        Risk: %s",
		guardian and guardian.DisplayName or "Unknown",
		string.rep("💀", risk))

	-- The three rarest tiers this zone can actually roll, with exact odds.
	-- "1 IN 100,000,000" on a starter-zone sign is the hook: it says the
	-- lottery ticket is real without pretending it is likely.
	local weights = RarityConfig.ZoneWeights[zoneId]
	local lines = {}
	for _, rarityId in ZoneConfig.HeadlineRarities(zoneId, RarityConfig, 3) do
		local tier = RarityConfig.Tiers[rarityId]
		table.insert(lines, string.format("%-10s %s",
			string.upper(tier.DisplayName),
			Format.Odds(weights[rarityId], RarityConfig.WeightTotal)))
	end

	return header, guardianLine, table.concat(lines, "\n")
end

local function buildSign(model: Model, cframe: CFrame, zoneId: string, nestIndex: number, guardianSpeciesId: string?)
	local post = Instance.new("Part")
	post.Name = "SignPost"
	post.Size = Vector3.new(1.2, 10, 1.2)
	post.CFrame = cframe * CFrame.new(0, 5, -NestBuilder.BowlRadius - 3)
	post.Color = Color3.fromHex("4A3F2A")
	post.Anchored = true
	post.CanCollide = false
	post.CastShadow = false
	post.Material = Enum.Material.WoodPlanks
	post.Parent = model

	local header, guardianLine, oddsBlock = makeSignText(zoneId, nestIndex, guardianSpeciesId)

	local gui = Instance.new("BillboardGui")
	gui.Name = "NestSign"
	gui.Size = UDim2.fromScale(22, 13)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
	gui.MaxDistance = 220
	gui.Adornee = post

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromHex("1F1A12")
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex(ZoneConfig.Zones[zoneId].Color)
	stroke.Thickness = 2
	stroke.Parent = panel

	local function label(name, text, sizeScale, positionScale, font, colour, scaled)
		local instance = Instance.new("TextLabel")
		instance.Name = name
		instance.Size = UDim2.fromScale(0.92, sizeScale)
		instance.Position = UDim2.fromScale(0.04, positionScale)
		instance.BackgroundTransparency = 1
		instance.Font = font
		instance.TextColor3 = colour
		instance.Text = text
		instance.TextScaled = scaled ~= false
		instance.TextXAlignment = Enum.TextXAlignment.Left
		instance.Parent = panel
		return instance
	end

	label("Header", header, 0.2, 0.04, Enum.Font.FredokaOne, Color3.fromHex("FFB020"))
	label("Guardian", guardianLine, 0.18, 0.26, Enum.Font.GothamMedium, Color3.fromHex("F5F0E4"))

	local odds = label("Odds", oddsBlock, 0.44, 0.48, Enum.Font.Code, Color3.fromHex("A89C86"), false)
	odds.TextSize = 14
	odds.TextYAlignment = Enum.TextYAlignment.Top
end

--[[
	Creates one egg with its prompt. Shared by the initial build and by respawn,
	so a respawned egg is byte-for-byte the same thing as an original - two
	construction paths is two sets of attributes to forget to set.
]]
local function createEgg(eggTemplate: Model, anchorCFrame: CFrame, offset: Vector3,
	nestId: string, slot: number, zoneId: string)
	local egg = eggTemplate:Clone()
	egg.Name = "Egg" .. slot
	egg:PivotTo(anchorCFrame * CFrame.new(offset))

	for _, descendant in egg:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	local shell = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Steal Egg"
	prompt.ObjectText = ZoneConfig.Zones[zoneId].DisplayName
	prompt.HoldDuration = NestBuilder.PromptHoldSecs
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = shell

	egg:SetAttribute("NestId", nestId)
	egg:SetAttribute("SlotIndex", slot)

	return egg, prompt
end

--[[
	Builds the nest at `anchor`. Returns the Model and its egg parts.

	`eggTemplate` is the generic Egg_Wild model from SAD_Assets.
]]
function NestBuilder.Build(anchor: BasePart, zoneId: string, nestIndex: number, eggTemplate: Model)
	local zone = ZoneConfig.Zones[zoneId]
	local cframe = anchor.CFrame

	local model = Instance.new("Model")
	model.Name = string.format("Nest_%s_%02d", zoneId, nestIndex)

	local bowl = Instance.new("Part")
	bowl.Name = "Bowl"
	bowl.Shape = Enum.PartType.Cylinder
	bowl.Size = Vector3.new(2.5, NestBuilder.BowlRadius * 2, NestBuilder.BowlRadius * 2)
	bowl.CFrame = cframe * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	bowl.Color = Color3.fromHex("5A4B34")
	bowl.Anchored = true
	bowl.CanCollide = false
	bowl.CastShadow = false
	bowl.Material = Enum.Material.Ground
	bowl.Parent = model
	model.PrimaryPart = bowl

	local guardianSpeciesId = NestBuilder.PickGuardian(zoneId, nestIndex)
	buildSign(model, cframe, zoneId, nestIndex, guardianSpeciesId)

	local eggs = Instance.new("Folder")
	eggs.Name = "Eggs"
	local slots = {}

	local count = zone.EggsPerNest
	for slot = 1, count do
		local angle = (slot - 1) / count * math.pi * 2
		local offset = if count == 1
			then Vector3.new(0, 2.6, 0)
			else Vector3.new(math.cos(angle) * NestBuilder.EggSpacing, 2.6, math.sin(angle) * NestBuilder.EggSpacing)

		local egg, prompt = createEgg(eggTemplate, cframe, offset, model.Name, slot, zoneId)
		egg.Parent = eggs

		slots[slot] = { Model = egg, Prompt = prompt, Offset = offset }
	end
	eggs.Parent = model

	model:SetAttribute("ZoneId", zoneId)
	model:SetAttribute("NestIndex", nestIndex)
	model:SetAttribute("GuardianSpeciesId", guardianSpeciesId)
	model:SetAttribute("Risk", NestBuilder.RiskOf(zoneId, guardianSpeciesId))
	-- Stored rather than recovered from the bowl's geometry. The bowl is a
	-- rotated cylinder, and un-rotating it to find the anchor again is the kind
	-- of arithmetic that silently drifts the first time the bowl changes shape.
	model:SetAttribute("AnchorCFrame", cframe)

	return model, slots, guardianSpeciesId
end

--- Rebuilds a single egg into an emptied slot, on respawn.
function NestBuilder.RespawnEgg(nestModel: Model, slot: number, offset: Vector3, eggTemplate: Model, zoneId: string)
	local eggs = nestModel:FindFirstChild("Eggs")
	if not eggs then
		return nil, nil
	end

	local anchorCFrame = nestModel.PrimaryPart.CFrame
		* CFrame.Angles(0, 0, math.rad(-90))
		* CFrame.new(0, -1.2, 0)

	local egg = eggTemplate:Clone()
	egg.Name = "Egg" .. slot
	egg:PivotTo(anchorCFrame * CFrame.new(offset))
	for _, descendant in egg:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	local shell = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Steal Egg"
	prompt.ObjectText = ZoneConfig.Zones[zoneId].DisplayName
	prompt.HoldDuration = NestBuilder.PromptHoldSecs
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = shell

	egg:SetAttribute("NestId", nestModel.Name)
	egg:SetAttribute("SlotIndex", slot)
	egg.Parent = eggs

	return egg, prompt
end

return NestBuilder
