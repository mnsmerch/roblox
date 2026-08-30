--[[
	Mutation-visual specification.

	═══ WHY THIS FILE EXISTS ═══════════════════════════════════════════════════
	Mutations were invisible. `ParkService` stamped `Mutation` as an attribute
	and the name tag read "Void Tyrannosaurus", and that was the entire visual -
	a x150 dinosaur at 1 in 2,000,000 rendered identically to a plain one.

	The `Vfx` field has named a particle effect per mutation since Step 3
	("Mut_Golden", "Mut_Void"). The effects folder is empty and nothing has ever
	read the field: registered-but-inert, the same shape as findings 29, 30 and
	56. The names stay for the day the effects are authored; the procedural
	stand-in is what ships now.

	Everything below measures the recipe, which is plain numbers in
	`MutationConfig`. The Instance half is `MutationSkin`, and the handful of
	things that can only be asserted about ITS text are read as source at the
	bottom - the same approach instance_fields_spec.lua uses.
	═══════════════════════════════════════════════════════════════════════════

	Run with:  ./tests/run.sh
]]

-- ── Roblox shims ────────────────────────────────────────────────────────────
Color3 = {
	fromHex = function(hex) return { Hex = hex } end,
	fromHSV = function(h, s, v) return { H = h, S = s, V = v } end,
}

--@SOURCE SkinSource=src/ReplicatedStorage/SAD_Shared/Modules/MutationSkin.lua ParkServiceSource=src/ServerScriptService/SAD_Server/Services/ParkService/init.lua AssetBuilderSource=src/ReplicatedStorage/SAD_Shared/Modules/AssetBuilder.lua@

--@INJECT MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua BodyPlanConfig=src/ReplicatedStorage/SAD_Shared/Config/BodyPlanConfig.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-56s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

local SHIPPED = {}
for id, mutation in MutationConfig.List do
	if id ~= "none" and mutation.InV1 then
		table.insert(SHIPPED, id)
	end
end
table.sort(SHIPPED, function(a, b)
	return MutationConfig.List[a].Rank < MutationConfig.List[b].Rank
end)

-- ═══════════════════════════════════════════════════════════════════════════
section("Every shipped mutation is visible")

eq("eight mutations ship in V1", #SHIPPED, 8)

local valid, problems = MutationConfig.ValidateVisuals()
if not valid then
	for _, problem in problems do print("    " .. problem) end
end
eq("ValidateVisuals reports no problems", #problems, 0)
ok("...and returns true beside an empty list", valid)

print("  mutation     x mult   blend  material      accent        glow")
for _, id in SHIPPED do
	local mutation = MutationConfig.List[id]
	local skin = MutationConfig.SkinFor(id, nil)
	ok(id .. " produces a skin", skin ~= nil)
	if skin then
		print(string.format("  %-12s %6.1f  %5.2f  %-12s  %-12s  %s",
			id, mutation.Multiplier, skin.Blend, skin.Material, skin.AccentMaterial,
			if skin.Glow then "yes" else "-"))
	end
end

eq("an unmutated dinosaur gets no skin at all", MutationConfig.SkinFor(nil, nil), nil)
eq("...and neither does an explicit 'none'", MutationConfig.SkinFor("none", nil), nil)
eq("an unshipped mutation has no visual to apply", MutationConfig.SkinFor("bloodmoon", nil), nil)

-- ═══════════════════════════════════════════════════════════════════════════
section("The glow marks exactly what the game announces")

--[[
	One field, one meaning. If the game stops the room for a hatch, the
	dinosaur it produced should be findable in a park afterwards - and if it
	does not stop the room, it should not be wearing an outline.

	It also bounds the count. Roblox stops rendering Highlights past a few dozen
	adornees; the commonest announced mutation is Diamond at 1 in 250 hatches.
]]
local glowing, announced = {}, {}
for _, id in SHIPPED do
	if MutationConfig.SkinFor(id, nil).Glow then table.insert(glowing, id) end
	if MutationConfig.List[id].AnnounceKind ~= nil then table.insert(announced, id) end
end
table.sort(glowing)
table.sort(announced)
eq("the glowing set is the announced set",
	table.concat(glowing, ","), table.concat(announced, ","))
eq("and it is four of the eight", #glowing, 4)
print("  glowing: " .. table.concat(glowing, ", "))

--[[
	The commonest mutation must NOT glow. Golden is 12% of hatches; a park of
	ten dinosaurs would average more than one, and a whole server of parks would
	blow past the Highlight budget on its own.
]]
ok("Golden - 12% of hatches - does not glow", MutationConfig.SkinFor("golden", nil).Glow == false)

-- ═══════════════════════════════════════════════════════════════════════════
section("Materials are ones that actually exist")

--[[
	Roblox splits materials into part materials and terrain-only materials, and
	naming a terrain one on a Part is a silent no-op rather than an error. This
	allowlist is the seven I am confident are valid on a Part; anything outside
	it has to be added here deliberately, having been checked.
]]
local allowed = {}
for name in MutationConfig.Materials do table.insert(allowed, name) end
table.sort(allowed)
print("  allowed: " .. table.concat(allowed, ", "))
eq("the allowlist is seven materials", #allowed, 7)

for _, id in SHIPPED do
	local skin = MutationConfig.SkinFor(id, nil)
	ok(id .. " body material is on the allowlist", MutationConfig.Materials[skin.Material] == true)
	ok(id .. " accent material is on the allowlist", MutationConfig.Materials[skin.AccentMaterial] == true)
end

-- ═══════════════════════════════════════════════════════════════════════════
section("No two mutations look the same")

local function distance(a, b)
	local ah, as, av = MutationConfig.HexToHsv(a)
	local bh, bs, bv = MutationConfig.HexToHsv(b)
	local dh = math.abs(ah - bh)
	dh = math.min(dh, 1 - dh)
	return math.sqrt((dh * 2.0) ^ 2 + ((as - bs) * 0.6) ^ 2 + ((av - bv) * 1.0) ^ 2)
end

--[[
	Crystal, Frozen and Diamond are all pale blue-white by design - docs/04
	gives them BFE9F5, 8FD9F5 and E8F7FF. Colour alone was never going to
	separate them, which is why the recipe gives them different MATERIALS
	(Glass, Ice, Glass-plus-Neon-plus-glow). So the assertion is that no PAIR
	matches on both.
]]
local sameOnBoth = {}
for i = 1, #SHIPPED do
	for j = i + 1, #SHIPPED do
		local a, b = SHIPPED[i], SHIPPED[j]
		local skinA, skinB = MutationConfig.SkinFor(a, nil), MutationConfig.SkinFor(b, nil)
		local colourGap = distance(skinA.Body, skinB.Body)
		local sameLook = skinA.Material == skinB.Material
			and skinA.AccentMaterial == skinB.AccentMaterial
			and skinA.Glow == skinB.Glow
			and skinA.Rainbow == skinB.Rainbow
		if colourGap < 0.12 and sameLook then
			table.insert(sameOnBoth, a .. " vs " .. b)
		end
	end
end
if #sameOnBoth > 0 then
	for _, pair in sameOnBoth do print("    " .. pair) end
end
eq("no pair matches on both colour and material", #sameOnBoth, 0)

local closest, closestWho = math.huge, "-"
for i = 1, #SHIPPED do
	for j = i + 1, #SHIPPED do
		local gap = distance(MutationConfig.List[SHIPPED[i]].Color, MutationConfig.List[SHIPPED[j]].Color)
		if gap < closest then closest, closestWho = gap, SHIPPED[i] .. " vs " .. SHIPPED[j] end
	end
end
print(string.format("  closest pair by colour alone %.3f (%s) - separated by material", closest, closestWho))

-- ═══════════════════════════════════════════════════════════════════════════
section("A stacked pair shows both mutations")

--[[
	MaxStack is 2, so "Golden Rainbow" exists and DisplayPrefix already names
	both. Averaging the two colours would render every pair as mud; the primary
	takes the hide and the secondary takes the crests and plates instead.
]]
local stacked = MutationConfig.SkinFor("golden", "void")
ok("a stack still produces a skin", stacked ~= nil)
eq("the hide comes from the primary", stacked.Body, MutationConfig.List.golden.Color)
eq("the accent comes from the secondary", stacked.Accent, MutationConfig.List.void.Color)
eq("the material comes from the primary", stacked.Material, MutationConfig.Visuals.golden.Material)
eq("so does the glow", stacked.Glow, MutationConfig.List.golden.AnnounceKind ~= nil)

for _, id in SHIPPED do
	for _, other in SHIPPED do
		if id ~= other then
			local skin = MutationConfig.SkinFor(id, other)
			ok(id .. "+" .. other .. " shows two colours", skin.Body ~= skin.Accent)
		end
	end
end

--[[
	And the single-mutation case where the accent CANNOT be the body colour:
	Void is 140A20, value 0.14. An accent that dark on a hide that dark is a
	silhouette with no shape in it, so it takes the bright complement - the same
	rule, and the same threshold, as BodyPlanConfig's dark-rarity swap.
]]
section("A dark mutation still has a readable shape")

local dark = {}
for _, id in SHIPPED do
	local _, _, value = MutationConfig.HexToHsv(MutationConfig.List[id].Color)
	if value < MutationConfig.DarkVisualSwap then table.insert(dark, id) end
end
eq("exactly one shipped mutation is too dark to carry its own accent", #dark, 1)
eq("and it is void", dark[1], "void")

local voidSkin = MutationConfig.SkinFor("void", nil)
ok("void's accent is not its own colour", voidSkin.Accent ~= MutationConfig.List.void.Color)
local _, _, accentValue = MutationConfig.HexToHsv(voidSkin.Accent)
ok("void's accent is bright", accentValue >= 0.9)
ok("void's accent is Neon, so it reads at range",
	voidSkin.AccentMaterial == "Neon")

eq("the threshold matches the one BodyPlanConfig uses for dark rarities",
	MutationConfig.DarkVisualSwap, BodyPlanConfig.DarkRaritySwap)

--[[
	The two hex/HSV converters must agree, or a computed accent colour is a
	different colour from the one the maths intended.
]]
section("The colour round-trip is lossless enough to trust")

for _, hex in { "FFC94A", "140A20", "8FD9F5", "6B4FD6", "FFFFFF", "000000", "FF6BD6" } do
	local h, s, v = MutationConfig.HexToHsv(hex)
	eq(hex .. " survives a round trip", MutationConfig.HsvToHex(h, s, v), hex)
end

-- ═══════════════════════════════════════════════════════════════════════════
section("The wiring, read as source")

--[[
	None of this can be executed offline - it is Instance code and call sites
	inside a service. Read as text instead, because the alternative is no check
	at all, and "registered but never called" is the failure this project keeps
	finding.
]]
ok("ParkService applies the skin",
	ParkServiceSource:find("MutationSkin.Apply(model, entry.Mutation, entry.Mutation2)", 1, true) ~= nil)
ok("ParkService publishes the second mutation too",
	ParkServiceSource:find('model:SetAttribute("Mutation2", entry.Mutation2)', 1, true) ~= nil)
ok("AssetBuilder stamps the tint role the skin reads",
	AssetBuilderSource:find('part:SetAttribute("Tint", descriptor.Tint)', 1, true) ~= nil)
ok("MutationSkin reads it back",
	SkinSource:find('part:GetAttribute("Tint") == "Accent"', 1, true) ~= nil)

--[[
	The Root part is Transparency 1. A mutation that ADDS transparency would
	make it visible rather than more transparent - a grey cube at every
	dinosaur's feet. Crystal, Diamond and any future glassy mutation all take
	this path.
]]
ok("the invisible Root part is excluded from painting",
	SkinSource:find('part.Name ~= "Root" and part.Transparency < 1', 1, true) ~= nil)
ok("the glow is Occluded, not AlwaysOnTop",
	SkinSource:find("Enum.HighlightDepthMode.Occluded", 1, true) ~= nil)
ok("Apply clears any previous glow before adding one",
	SkinSource:find("MutationSkin.Clear(model)", 1, true) ~= nil)

--[[
	`Color3.toHSV(c)` is the legacy static; `c:ToHSV()` is the current method.
	Both work today and only one is going to keep working.
]]
ok("the current Color3 method is used, not the legacy static",
	SkinSource:find("Color3.toHSV(", 1, true) == nil
		and SkinSource:find(":ToHSV()", 1, true) ~= nil)

--[[
	`Vfx` stays in MutationConfig and stays unread. Asserted so that the day
	somebody wires it up, this line fails and the procedural stand-in gets
	retired deliberately rather than left running underneath it.
]]
local vfxReaders = 0
for _, source in { SkinSource, ParkServiceSource, AssetBuilderSource } do
	if source:find(".Vfx", 1, true) then vfxReaders += 1 end
end
eq("nothing reads Vfx yet - the effects folder is still empty", vfxReaders, 0)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
