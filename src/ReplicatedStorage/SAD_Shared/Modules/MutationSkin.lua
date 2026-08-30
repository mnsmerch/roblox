--!nonstrict
--[[
	MutationSkin
	ReplicatedStorage/SAD_Shared/Modules/MutationSkin  (ModuleScript)

	Paints a mutation onto a dinosaur model.

	═══ WHAT THIS FIXES ════════════════════════════════════════════════════════
	Mutations were invisible. `ParkService` stamped `Mutation` as an attribute
	and `DisplayNameOf` put "Golden" in the name tag, and that was the whole
	visual: a x150 Void Tyrannosaurus rendered identically to a plain one. The
	`Vfx` field in MutationConfig names a particle effect per mutation, but the
	effects folder is empty and nothing ever read the field.

	So the recipe is procedural, and it lives in `MutationConfig.SkinFor` where
	a spec can measure it. This file is the thin half - it turns a recipe into
	property writes, and makes no decision of its own. Same split as
	BodyPlanConfig / AssetBuilder, for the same reason: Instance code cannot be
	tested outside Roblox, so as little as possible should live in it.
	═══════════════════════════════════════════════════════════════════════════

	  MutationSkin.Apply(model, primary, secondary?)  -> boolean
	  MutationSkin.Clear(model)

	Depends on: MutationConfig.
	Called by: ParkService, when it clones a dinosaur into a park.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local MutationConfig = require(Shared.Config.MutationConfig)

local MutationSkin = {}

MutationSkin.HighlightName = "MutationGlow"

--[[
	Parts that must not be touched.

	`Root` is the invisible pivot part added by AssetBuilder - it is
	Transparency 1, and a mutation that adds transparency would make it
	VISIBLE rather than more transparent, which is the wrong direction and
	would hang a grey cube at every dinosaur's feet.

	Anything else already fully transparent is skipped on the same grounds.
]]
local function paintable(part: BasePart): boolean
	return part.Name ~= "Root" and part.Transparency < 1
end

local function materialOf(name: string): Enum.Material
	return (Enum.Material :: any)[name] or Enum.Material.SmoothPlastic
end

--[[
	Applies `skin` to every part of `model`. Returns false when the dinosaur is
	unmutated, so callers can treat "no mutation" as an ordinary outcome rather
	than as a failure.
]]
function MutationSkin.Apply(model: Model, primary: string?, secondary: string?): boolean
	local skin = MutationConfig.SkinFor(primary, secondary)
	MutationSkin.Clear(model)
	if not skin then
		return false
	end

	local bodyColor = Color3.fromHex(skin.Body)
	local accentColor = Color3.fromHex(skin.Accent)
	local bodyMaterial = materialOf(skin.Material)
	local accentMaterial = materialOf(skin.AccentMaterial)

	--[[
		Rainbow walks the hue wheel across the parts in a stable order rather
		than randomly, so the same species always comes out the same rainbow -
		and so the bands run along the body instead of speckling it. Sorted by
		name because GetDescendants order is not guaranteed to be stable across
		a clone.
	]]
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and paintable(descendant) then
			table.insert(parts, descendant)
		end
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)

	for index, part in parts do
		local isAccent = part:GetAttribute("Tint") == "Accent"
		local target = if isAccent then accentColor else bodyColor

		if skin.Rainbow and not isAccent then
			--[[
				Value is taken from the part's CURRENT colour, so the belly stays
				lighter than the limbs and the model keeps its shading. Only the
				hue is replaced.
			]]
			local _, _, value = part.Color:ToHSV()
			target = Color3.fromHSV((index - 1) / #parts, 0.85, math.max(value, 0.55))
		end

		part.Color = part.Color:Lerp(target, skin.Blend)
		part.Material = if isAccent then accentMaterial else bodyMaterial

		if skin.Transparency > 0 then
			part.Transparency = math.clamp(part.Transparency + skin.Transparency, 0, 0.95)
		end
	end

	--[[
		Only the four announced mutations get an outline. Roblox stops
		rendering Highlights past a few dozen adornees, and the point of the
		outline is that it marks the ones the game already stopped the room for.
	]]
	if skin.Glow then
		local highlight = Instance.new("Highlight")
		highlight.Name = MutationSkin.HighlightName
		highlight.FillColor = bodyColor
		highlight.FillTransparency = 0.75
		highlight.OutlineColor = accentColor
		highlight.OutlineTransparency = 0
		-- Occluded, not AlwaysOnTop: a rare dinosaur is worth finding, not
		-- worth seeing through the wall of the park it is standing in.
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = model
	end

	return true
end

--- Removes anything Apply added. Colours and materials are not restored: a
--- caller re-skinning a model should re-clone it from the template instead.
function MutationSkin.Clear(model: Model)
	local existing = model:FindFirstChild(MutationSkin.HighlightName)
	if existing then
		existing:Destroy()
	end
end

return MutationSkin
