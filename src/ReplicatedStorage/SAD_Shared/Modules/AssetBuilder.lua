--!nonstrict
--[[
	AssetBuilder
	ReplicatedStorage/SAD_Shared/Modules/AssetBuilder  (ModuleScript)

	Generates placeholder egg and dinosaur models into SAD_Assets at boot, one
	per entry in DinoConfig and RarityConfig.

	This exists so the content pipeline is verifiable BEFORE any art exists.
	With it, ConfigValidator rule 7 (every model a species references must
	resolve) becomes a real check rather than a permanently skipped one, and
	Steps 11 and 12 have something to hatch and place.

	Placeholders are deliberately crude - a body, a head, four legs, sized from
	the species footprint and tinted from a hash of its id. They are not trying
	to look good. They are trying to be present, correctly named, correctly
	scaled, and easy to delete.

	When real art arrives (Step 24): drop the models into SAD_Assets/Dinos and
	SAD_Assets/Eggs with the same names and set BuildPlaceholders to false in
	GameConfig. Nothing else changes - that is the point of deriving ModelName
	from the species id.

	Depends on: DinoConfig, RarityConfig, ParkConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local ParkConfig = require(Shared.Config.ParkConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local Log = require(Shared.Modules.Log)

local AssetBuilder = {}

--- Stable pseudo-colour from a species id, so a placeholder keeps the same
--- look between sessions and two species are rarely the same shade.
local function hueFor(id: string): number
	local hash = 0
	for index = 1, #id do
		hash = (hash * 31 + string.byte(id, index)) % 360
	end
	return hash / 360
end

local function block(name: string, size: Vector3, offset: Vector3, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(offset)
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[
	A placeholder dinosaur, built at its real footprint so placement, collision
	and the enclosure grid can all be tested with correct proportions.

	Footprint drives width and depth; VisualScale multiplies everything, which
	is what makes a Titan read as a Titan (3x) without a separate model.
]]
function AssetBuilder.BuildDino(entry): Model
	local span = tonumber(string.sub(entry.Size, 1, 1)) or 1
	local footprint = span * ParkConfig.TileSize * entry.VisualScale

	-- Leave a margin so a 4x4 does not touch its neighbours' tiles.
	local width = footprint * 0.7
	local height = footprint * 0.55
	local legHeight = footprint * 0.28

	local hue = hueFor(entry.Id)
	local body = Color3.fromHSV(hue, 0.55, 0.75)
	local accent = Color3.fromHSV((hue + 0.08) % 1, 0.6, 0.55)

	local model = Instance.new("Model")
	model.Name = entry.ModelName

	local torso = block("Torso",
		Vector3.new(width * 0.6, height * 0.5, width),
		Vector3.new(0, legHeight + height * 0.25, 0), body, model)

	block("Head",
		Vector3.new(width * 0.4, height * 0.35, width * 0.45),
		Vector3.new(0, legHeight + height * 0.55, width * 0.6), accent, model)

	block("Tail",
		Vector3.new(width * 0.25, height * 0.2, width * 0.7),
		Vector3.new(0, legHeight + height * 0.3, -width * 0.7), accent, model)

	for _, side in { -1, 1 } do
		for _, front in { -1, 1 } do
			block("Leg",
				Vector3.new(width * 0.16, legHeight, width * 0.16),
				Vector3.new(side * width * 0.2, legHeight * 0.5, front * width * 0.28), accent, model)
		end
	end

	model.PrimaryPart = torso
	model:SetAttribute("SpeciesId", entry.Id)
	model:SetAttribute("Placeholder", true)
	return model
end

--- An egg. `rarityId` nil builds the generic wild egg that sits in a nest -
--- rarity is not rolled until pickup, so a nest egg must not hint at one.
function AssetBuilder.BuildEgg(rarityId: string?): Model
	local color = if rarityId
		then Color3.fromHex(RarityConfig.Tiers[rarityId].Color)
		else Color3.fromHex("E4DCC8")

	local model = Instance.new("Model")
	model.Name = if rarityId then "Egg_" .. rarityId else "Egg_Wild"

	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(3, 4, 3) -- squashed into an egg by the mesh below
	shell.Color = color
	shell.Anchored = true
	shell.CanCollide = false
	shell.CastShadow = false
	shell.Material = Enum.Material.SmoothPlastic
	shell.TopSurface = Enum.SurfaceType.Smooth
	shell.BottomSurface = Enum.SurfaceType.Smooth
	shell.Parent = model

	-- SpecialMesh scales a ball into an egg without needing an asset.
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(0.8, 1.1, 0.8)
	mesh.Parent = shell

	model.PrimaryPart = shell
	model:SetAttribute("RarityId", rarityId)
	model:SetAttribute("Placeholder", true)
	return model
end

--[[
	Populates SAD_Assets. Returns counts for the boot log.

	Only builds what is MISSING, so a real model dropped into the folder is
	never overwritten by a placeholder. That makes the art handover incremental:
	replace one species at a time and the rest keep working.
]]
function AssetBuilder.Build(): (number, number, number)
	local assets = Shared:FindFirstChild("SAD_Assets")
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "SAD_Assets"
		assets.Parent = Shared
	end

	local function folder(name: string): Folder
		local existing = assets:FindFirstChild(name)
		if existing then
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = name
		created.Parent = assets
		return created
	end

	local dinos = folder("Dinos")
	local eggs = folder("Eggs")
	folder("Effects")
	folder("UI")
	--[[
		Empty on purpose. SoundController looks its slots up by name in here,
		so dropping a Sound named `Hatch` in gives hatching a sound with no
		code change - and no asset id is invented anywhere to stand in for
		one that does not exist yet (docs/15 §3).
	]]
	folder("Sounds")

	local builtDinos, builtEggs, kept = 0, 0, 0

	for _, entry in DinoConfig.Species do
		if dinos:FindFirstChild(entry.ModelName) then
			kept += 1
		else
			AssetBuilder.BuildDino(entry).Parent = dinos
			builtDinos += 1
		end
	end

	if not eggs:FindFirstChild("Egg_Wild") then
		AssetBuilder.BuildEgg(nil).Parent = eggs
		builtEggs += 1
	else
		kept += 1
	end

	for _, rarityId in RarityConfig.Order do
		local name = "Egg_" .. rarityId
		if eggs:FindFirstChild(name) then
			kept += 1
		else
			AssetBuilder.BuildEgg(rarityId).Parent = eggs
			builtEggs += 1
		end
	end

	Log.info("AssetBuilder", "Placeholders: %d dino(s), %d egg(s) built, %d real asset(s) kept",
		builtDinos, builtEggs, kept)

	return builtDinos, builtEggs, kept
end

--- Maps SAD_Assets into the shape ConfigValidator rule 7 expects.
function AssetBuilder.Manifest()
	local assets = Shared:FindFirstChild("SAD_Assets")
	if not assets then
		return nil
	end

	local manifest = { Dinos = {}, Eggs = {} }
	for _, child in (assets:FindFirstChild("Dinos") or assets):GetChildren() do
		manifest.Dinos[child.Name] = true
	end
	for _, child in (assets:FindFirstChild("Eggs") or assets):GetChildren() do
		manifest.Eggs[child.Name] = true
	end
	return manifest
end

return AssetBuilder
