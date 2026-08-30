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

	The SHAPE and COLOUR of a placeholder are not decided here - they live in
	`BodyPlanConfig` as plain numbers, so they can be tested offline. This file
	is the thin part: it turns each descriptor into a Part, and nothing in it
	makes a judgement about how a dinosaur should look.

	That split is deliberate. Instance code cannot be tested outside Roblox, and
	the first two Studio runs of this project died in Instance code that 5,000
	offline assertions had passed straight over. So the rule is: decisions in a
	config module the specs can reach, Instances in a loop with no decisions.

	When real art arrives (Step 24): drop the models into SAD_Assets/Dinos and
	SAD_Assets/Eggs with the same names and set BuildPlaceholders to false in
	GameConfig. Nothing else changes - that is the point of deriving ModelName
	from the species id.

	Depends on: BodyPlanConfig, DinoConfig, RarityConfig, ParkConfig, ZoneConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local BodyPlanConfig = require(Shared.Config.BodyPlanConfig)
local DinoConfig = require(Shared.Config.DinoConfig)
local ParkConfig = require(Shared.Config.ParkConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Log = require(Shared.Modules.Log)

local AssetBuilder = {}

--[[
	One segment of a body plan, in world units.

	`Ellipsoid` is a Block part wearing a `SpecialMesh` set to Sphere, which
	fills the part's bounding box - so a 4 x 2 x 6 part becomes a 4 x 2 x 6
	ellipsoid. That is the only way to get a non-uniform rounded shape out of a
	primitive without an asset, and it is why BodyPlanConfig needs no wedges or
	cylinders (whose orientation conventions I would be guessing at).
]]
local function buildSegment(descriptor, footprint: number, palette, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = descriptor.Name
	part.Size = Vector3.new(
		descriptor.Size[1] * footprint,
		descriptor.Size[2] * footprint,
		descriptor.Size[3] * footprint)

	local offset = CFrame.new(
		descriptor.At[1] * footprint,
		descriptor.At[2] * footprint,
		descriptor.At[3] * footprint)
	if descriptor.Rot then
		offset *= CFrame.Angles(
			math.rad(descriptor.Rot[1]),
			math.rad(descriptor.Rot[2]),
			math.rad(descriptor.Rot[3]))
	end
	part.CFrame = offset

	local hsv = palette[descriptor.Tint]
	assert(hsv, "AssetBuilder: body plan asked for tint '" .. tostring(descriptor.Tint) .. "'")
	part.Color = Color3.fromHSV(hsv[1], hsv[2], hsv[3])

	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if descriptor.Shape == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end

	part.Parent = parent
	return part
end

--[[
	A placeholder dinosaur, built at its real footprint so placement, collision
	and the enclosure grid can all be tested with correct proportions.

	Footprint drives everything; VisualScale multiplies it, which is what makes
	a Titan read as a Titan (3x) without a separate model. Every number in the
	plan is a fraction of that footprint, so one plan serves a 1x1 Compsognathus
	and a 4x4 Tyrannosaurus unchanged.
]]
function AssetBuilder.BuildDino(entry): Model
	local span = tonumber(string.sub(entry.Size, 1, 1)) or 1
	local footprint = span * ParkConfig.TileSize * entry.VisualScale

	local palette = BodyPlanConfig.Palette(entry, ZoneConfig, RarityConfig)
	local segments = BodyPlanConfig.Segments(entry)

	local model = Instance.new("Model")
	model.Name = entry.ModelName

	--[[
		═══ WHY THERE IS A ROOT PART ═══════════════════════════════════════════
		A Model's pivot IS its PrimaryPart's CFrame. The previous placeholder
		made the TORSO the PrimaryPart, and the torso sits roughly 0.45
		footprints off the ground - so every `model:PivotTo(groundCFrame)` in
		the game buried the dinosaur up to its belly. On a 1x1 that is four
		studs of a nine-stud model underground; on a 2x2 guardian, eight.

		Both callers were right and the model was wrong: ParkService places at
		the tile's floor CFrame (`GridCenterOffset` has Y = 0, and the plot's
		base slab tops out at Y = 0), and WildAIService places at ground + 2.

		So the pivot is now an empty part at the model's own origin, which is
		where the feet are. Nothing outside this file changed to make placement
		correct - the model started reporting where its feet were.
		═══════════════════════════════════════════════════════════════════════
	]]
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local torso: BasePart? = nil
	for _, descriptor in segments do
		local part = buildSegment(descriptor, footprint, palette, model)
		if descriptor.Name == "Torso" then
			torso = part
		end
	end

	--[[
		Not a soft failure. The rarity light is parented to the Torso so it
		glows from inside the body rather than from the ankles; a plan without
		one would lose it silently. BodyPlanConfig.Validate() asserts every plan
		has a Torso, so reaching here means the two files have drifted apart.
	]]
	assert(torso, "AssetBuilder: body plan for '" .. entry.Id .. "' produced no Torso")

	model:SetAttribute("SpeciesId", entry.Id)
	model:SetAttribute("BodyPlan", BodyPlanConfig.PlanIdFor(entry))
	--[[
		In studs, so a caller placing a name tag above the head does not have to
		know anything about footprints. Read by ParkService.
	]]
	model:SetAttribute("StandHeight", BodyPlanConfig.StandHeight(entry) * footprint)
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
