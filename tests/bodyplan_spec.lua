--[[
	Body-plan specification.

	═══ WHY THIS FILE EXISTS ═══════════════════════════════════════════════════
	`AssetBuilder` builds Roblox Instances, so it cannot be tested offline - and
	the first two Studio runs of this project were killed by untested Instance
	code. The fix was to move every DECISION about a placeholder's shape and
	colour into `BodyPlanConfig`, which is plain numbers, so the things that
	actually go wrong in-world become assertions here:

	  - a leg that does not reach the ground (the dinosaur hovers)
	  - a body wider than its tile (it clips the dinosaur beside it)
	  - an archetype with no plan (it silently becomes a generic theropod)
	  - two species in one zone that come out the same colour
	  - a rarity whose accent is invisible against the hide it sits on

	None of these throw. Every one of them just looks wrong, which is the
	category of bug that survives a boot log saying "ok".
	═══════════════════════════════════════════════════════════════════════════

	Run with:  ./tests/run.sh
]]

-- ── Roblox shims ────────────────────────────────────────────────────────────
-- ZoneConfig builds Vector3/CFrame values inside its geometry functions. This
-- spec only reads `.Color`, but the module still has to load.
local Vector3MT = {}
Vector3MT.__index = Vector3MT
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT) end
Vector3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3 = { new = v3, zero = v3(0, 0, 0) }
Color3 = { fromHex = function(hex) return { Hex = hex } end, fromHSV = function(h, s, v) return { H = h, S = s, V = v } end }
CFrame = setmetatable({
	new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end,
	Angles = function(x, y, z) return { RX = x, RY = y, RZ = z } end,
	identity = { X = 0, Y = 0, Z = 0 },
}, { __call = function(_, ...) return { ... } end })

--@SOURCE AssetBuilderSource=src/ReplicatedStorage/SAD_Shared/Modules/AssetBuilder.lua ParkServiceSource=src/ServerScriptService/SAD_Server/Services/ParkService/init.lua@

--@INJECT BodyPlanConfig=src/ReplicatedStorage/SAD_Shared/Config/BodyPlanConfig.lua ChaseConfig=src/ReplicatedStorage/SAD_Shared/Config/ChaseConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-56s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-56s got %.4f want %.4f +- %.4f", label, got, want, tol)) end
end
local function section(name) print("\n== " .. name) end

local function speciesList()
	local out = {}
	for _, entry in DinoConfig.Species do
		table.insert(out, entry)
	end
	table.sort(out, function(a, b) return a.IndexOrder < b.IndexOrder end)
	return out
end
local ALL = speciesList()

-- ═══════════════════════════════════════════════════════════════════════════
section("Coverage: every archetype and every override resolves")

local valid, problems = BodyPlanConfig.Validate(ChaseConfig, DinoConfig)
if not valid then
	for _, problem in problems do
		print("    " .. problem)
	end
end
eq("BodyPlanConfig.Validate reports no problems", #problems, 0)
ok("Validate returns true alongside an empty list", valid)

local archetypeCount = 0
for _ in ChaseConfig.Archetypes do archetypeCount += 1 end
local mappedCount = 0
for _ in BodyPlanConfig.ByArchetype do mappedCount += 1 end
eq("every ChaseConfig archetype has a plan", mappedCount, archetypeCount)

--[[
	A plan nobody uses is a plan nobody has ever looked at. If a species stops
	pointing at one, either the plan should go or the mapping is wrong - both
	are worth a failure rather than a shrug.
]]
local usedBy = {}
for _, entry in ALL do
	local planId = BodyPlanConfig.PlanIdFor(entry)
	usedBy[planId] = (usedBy[planId] or 0) + 1
end
for planId in BodyPlanConfig.Plans do
	ok("plan '" .. planId .. "' is used by at least one species", (usedBy[planId] or 0) > 0)
end

print("  species per plan:")
local planIds = {}
for planId in BodyPlanConfig.Plans do table.insert(planIds, planId) end
table.sort(planIds)
for _, planId in planIds do
	print(string.format("    %-11s %d", planId, usedBy[planId] or 0))
end

-- ═══════════════════════════════════════════════════════════════════════════
section("Geometry: every species stands on the ground, inside its tile")

local bounds = BodyPlanConfig.Bounds
local worstLow, worstLowWho = 0, "-"
local worstWide, worstWideWho = 0, "-"
local worstLong, worstLongWho = 0, "-"
local tallest, tallestWho = 0, "-"
local minParts, maxParts = math.huge, 0

for _, entry in ALL do
	local planId = BodyPlanConfig.PlanIdFor(entry)
	local segments = BodyPlanConfig.Segments(entry)
	local halfWidth = if BodyPlanConfig.WidePlans[planId] then bounds.WideHalfWidth else bounds.HalfWidth

	local lowest, highest = math.huge, -math.huge
	local torsoCount, eyeCount = 0, 0
	for _, item in segments do
		lowest = math.min(lowest, item.At[2] - item.Size[2] * 0.5)
		highest = math.max(highest, item.At[2] + item.Size[2] * 0.5)

		local wide = math.abs(item.At[1]) + item.Size[1] * 0.5
		local long = math.abs(item.At[3]) + item.Size[3] * 0.5
		if wide - halfWidth > worstWide then worstWide, worstWideWho = wide - halfWidth, entry.Id .. "/" .. item.Name end
		if long - bounds.HalfLength > worstLong then worstLong, worstLongWho = long - bounds.HalfLength, entry.Id .. "/" .. item.Name end
		if highest > tallest then tallest, tallestWho = highest, entry.Id end

		if item.Name == "Torso" then torsoCount += 1 end
		if item.Name == "EyeR" or item.Name == "EyeL" then eyeCount += 1 end

		ok(entry.Id .. "/" .. item.Name .. " has a positive size",
			item.Size[1] > 0 and item.Size[2] > 0 and item.Size[3] > 0)
	end

	if math.abs(lowest) > math.abs(worstLow) then worstLow, worstLowWho = lowest, entry.Id end
	minParts = math.min(minParts, #segments)
	maxParts = math.max(maxParts, #segments)

	eq(entry.Id .. " has exactly one Torso", torsoCount, 1)
	eq(entry.Id .. " has two eyes", eyeCount, 2)
end

near("the lowest point of any species sits on y=0", worstLow, 0, bounds.GroundEps)
print(string.format("  lowest point %.4f (%s)", worstLow, worstLowWho))
eq("nothing exceeds its sideways bound", worstWide <= 0, true)
print(string.format("  widest overshoot %.4f (%s)", worstWide, worstWideWho))
eq("nothing exceeds its fore-aft bound", worstLong <= 0, true)
print(string.format("  longest overshoot %.4f (%s)", worstLong, worstLongWho))
ok("nothing is taller than the height bound", tallest <= bounds.MaxHeight)
print(string.format("  tallest %.3f footprints (%s)", tallest, tallestWho))

--[[
	Part count is a frame-rate budget, not a style rule. Six plots x roughly a
	dozen dinosaurs each is the worst realistic case, so the ceiling here is
	what keeps that under a few thousand parts.
]]
print(string.format("  parts per dinosaur: %d-%d", minParts, maxParts))
ok("no placeholder is under 12 parts (it would read as a box again)", minParts >= 12)
ok("no placeholder is over 44 parts", maxParts <= 44)

-- ═══════════════════════════════════════════════════════════════════════════
section("Segments() hands out copies, not the shared plan")

local first = BodyPlanConfig.Segments(DinoConfig.Species.trex)
first[1].Size[1] = 999
local second = BodyPlanConfig.Segments(DinoConfig.Species.trex)
ok("mutating a returned segment does not corrupt the plan", second[1].Size[1] ~= 999)

local mirrored = BodyPlanConfig.Segments(DinoConfig.Species.trex)
local rightArm, leftArm
for _, item in mirrored do
	if item.Name == "ArmR" then rightArm = item end
	if item.Name == "ArmL" then leftArm = item end
end
ok("a mirrored pair produces both sides", rightArm ~= nil and leftArm ~= nil)
if rightArm and leftArm then
	near("the mirrored copy is on the opposite side", leftArm.At[1], -rightArm.At[1], 1e-9)
	near("the mirrored copy keeps its height", leftArm.At[2], rightArm.At[2], 1e-9)
	--[[
		Roll and yaw flip with the mirror, pitch does not. An arm that leans
		outwards on the right must lean outwards on the left, not inwards.
	]]
	if rightArm.Rot then
		near("mirrored pitch is unchanged", leftArm.Rot[1], rightArm.Rot[1], 1e-9)
		near("mirrored roll is negated", leftArm.Rot[3], -rightArm.Rot[3], 1e-9)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
section("Palette: derived from the zone and rarity tables, never invented")

local function paletteOf(entry)
	return BodyPlanConfig.Palette(entry, ZoneConfig, RarityConfig)
end

for _, entry in ALL do
	local palette = paletteOf(entry)
	for _, key in { "Body", "Belly", "Limb", "Accent", "Eye", "Tooth" } do
		local hsv = palette[key]
		ok(entry.Id .. " has a " .. key .. " tint", hsv ~= nil)
		if hsv then
			ok(entry.Id .. "." .. key .. " is in range",
				hsv[1] >= 0 and hsv[1] < 1 and hsv[2] >= 0 and hsv[2] <= 1 and hsv[3] >= 0 and hsv[3] <= 1)
		end
	end
	ok(entry.Id .. " belly is lighter than body", palette.Belly[3] > palette.Body[3])
	ok(entry.Id .. " limbs are darker than body", palette.Limb[3] < palette.Body[3])
end

--[[
	The accent carries the rarity, and that is the whole point of it: a
	Legendary should be legible from across the park. Anything but a dark
	rarity must use the rarity colour untouched.
]]
for _, entry in ALL do
	local tier = RarityConfig.Tiers[entry.Rarity]
	local rh, rs, rv = BodyPlanConfig.HexToHsv(tier.Color)
	local palette = paletteOf(entry)
	if rv >= BodyPlanConfig.DarkRaritySwap then
		near(entry.Id .. " accent hue is the rarity hue", palette.Accent[1], rh, 1e-9)
		near(entry.Id .. " accent saturation is the rarity saturation", palette.Accent[2], rs, 1e-9)
		near(entry.Id .. " accent value is the rarity value", palette.Accent[3], rv, 1e-9)
	end
end

-- The dark swap: measured, not listed.
local darkRarities = {}
for _, rarityId in RarityConfig.Order do
	local _, _, value = BodyPlanConfig.HexToHsv(RarityConfig.Tiers[rarityId].Color)
	if value < BodyPlanConfig.DarkRaritySwap then
		table.insert(darkRarities, rarityId)
	end
end
eq("exactly one shipped rarity is dark enough to swap", #darkRarities, 1)
eq("and it is secret", darkRarities[1], "secret")

for _, entry in ALL do
	local palette = paletteOf(entry)
	if entry.Rarity == "secret" then
		ok(entry.Id .. " (secret) has a near-black hide", palette.Body[3] <= 0.24)
		ok(entry.Id .. " (secret) has a bright accent", palette.Accent[3] >= 0.9)
	end
end

--[[
	Contrast is the thing that was actually broken before: an accent nobody can
	pick out of the hide it sits on. Assert the gap rather than trusting it.
]]
local worstContrast, worstContrastWho = math.huge, "-"
for _, entry in ALL do
	local palette = paletteOf(entry)
	local gap = math.abs(palette.Accent[3] - palette.Body[3])
	if gap < worstContrast then worstContrast, worstContrastWho = gap, entry.Id end
end
print(string.format("  smallest accent/body brightness gap %.3f (%s)", worstContrast, worstContrastWho))
ok("every accent is separable from its hide", worstContrast >= 0.15)

-- ═══════════════════════════════════════════════════════════════════════════
section("No two species in a zone come out the same colour")

local byZone = {}
for _, entry in ALL do
	local zoneId = entry.Zones and entry.Zones[1] or "none"
	byZone[zoneId] = byZone[zoneId] or {}
	table.insert(byZone[zoneId], entry)
end

--[[
	Distance across all three channels, not hue alone. Two dinosaurs one shade
	apart in hue but clearly different in brightness are not the bug; two that
	match on every channel are. Hue is weighted up because it is what the eye
	sorts by first, and saturation down because it is what it notices last.
]]
local function tintDistance(a, b)
	local dh = math.abs(a[1] - b[1])
	dh = math.min(dh, 1 - dh)
	return math.sqrt((dh * 2.0) ^ 2 + ((a[2] - b[2]) * 0.6) ^ 2 + ((a[3] - b[3]) * 1.0) ^ 2)
end

local closest, closestWho = math.huge, "-"
for zoneId, members in byZone do
	for i = 1, #members do
		for j = i + 1, #members do
			local a, b = members[i], members[j]
			--[[
				Two species of the same rarity in the same zone are the pair a
				player would actually confuse. Different rarities already differ
				by their accent, so the hide need not separate them alone.
			]]
			if a.Rarity == b.Rarity then
				local gap = tintDistance(paletteOf(a).Body, paletteOf(b).Body)
				if gap < closest then
					closest, closestWho = gap, zoneId .. ": " .. a.Id .. " vs " .. b.Id
				end
			end
		end
	end
end
print(string.format("  closest same-zone same-rarity pair %.4f (%s)", closest, closestWho))
--[[
	═══ THIS NUMBER IS MEASURED, NOT DERIVED ═══════════════════════════════════
	0.044 is where the current roster actually sits (othnielia vs
	psittacosaurus, both Common, both Jurassic Plains). It is not a perceptual
	constant and I am not going to dress it up as one - a hash cannot GUARANTEE
	any separation, so the honest thing is a tripwire at today's floor.

	For scale: the absolute-hash palette this replaced put protoceratops and
	struthiomimus at 0.0018 apart, which is the same colour.

	If a new species trips this, do not widen the jitter to make it pass - that
	just moves every other species to hide one collision. Rename the species id
	(the hash is over the id) or give it an explicit palette override.
	═══════════════════════════════════════════════════════════════════════════
]]
ok("no two same-zone same-rarity hides are hard to tell apart", closest >= 0.044)

-- And across the whole roster, nothing is an exact duplicate of anything.
local exact = 0
for i = 1, #ALL do
	for j = i + 1, #ALL do
		if tintDistance(paletteOf(ALL[i]).Body, paletteOf(ALL[j]).Body) == 0 then
			exact += 1
		end
	end
end
eq("no two species anywhere share an identical hide", exact, 0)

-- ═══════════════════════════════════════════════════════════════════════════
section("The shapes the game already promised")

--[[
	These are not aesthetic opinions - each one is a claim DinoConfig or
	ChaseConfig already makes, checked against the silhouette that ships.
]]
eq("the swimmer that cannot guard is the long-necked one",
	BodyPlanConfig.PlanIdFor(DinoConfig.Species.plesiosaurus), "longneck")
ok("and ChaseConfig agrees it cannot guard", ChaseConfig.Archetypes.swimmer.CanGuard == false)

eq("both fliers get wings",
	BodyPlanConfig.PlanIdFor(DinoConfig.Species.pteranodon) .. "/" .. BodyPlanConfig.PlanIdFor(DinoConfig.Species.microraptor),
	"flyer/flyer")
ok("and ChaseConfig agrees both fly",
	ChaseConfig.Archetypes.divebomber.Flies == true and ChaseConfig.Archetypes.glider.Flies == true)

eq("the titan gets the titan plan", BodyPlanConfig.PlanIdFor(DinoConfig.Species.titanrex), "titan")
eq("both spikers get plates",
	BodyPlanConfig.PlanIdFor(DinoConfig.Species.stegosaurus) .. "/" .. BodyPlanConfig.PlanIdFor(DinoConfig.Species.kentrosaurus),
	"plated/plated")

--[[
	The bulldozer split is the reason species overrides exist at all: one
	archetype, three silhouettes. If these ever collapse back to one plan, the
	override table has been lost.
]]
local bulldozers = {}
for _, entry in ALL do
	if entry.ChaseArchetype == "bulldozer" then
		bulldozers[BodyPlanConfig.PlanIdFor(entry)] = true
	end
end
local distinct = 0
for _ in bulldozers do distinct += 1 end
eq("the three bulldozers keep three different shapes", distinct, 3)

--[[
	Spinosaurids share the sailback plan, and all three are waders. If a fourth
	wader is added with a different silhouette it needs an override, and this
	is where that gets noticed.
]]
for _, id in { "spinosaurus", "suchomimus", "baryonyx" } do
	eq(id .. " is a sailback", BodyPlanConfig.PlanIdFor(DinoConfig.Species[id]), "sailback")
end

-- ═══════════════════════════════════════════════════════════════════════════
section("The pivot sits at the feet, not in the belly")

--[[
	═══ THE BUG THIS SECTION EXISTS FOR ════════════════════════════════════════
	A Model's pivot IS its PrimaryPart's CFrame. The old placeholder made the
	TORSO the PrimaryPart, so every `model:PivotTo(groundCFrame)` in the game
	buried the dinosaur to its belly - about four studs of a nine-stud
	Compsognathus, eight of a 2x2 guardian.

	Nothing threw. Both callers were correct: ParkService places at the tile's
	floor CFrame and WildAIService at ground + 2. The model was lying about
	where its feet were.

	Neither the fix nor the bug can be executed offline, so these read the two
	files as text - the same approach instance_fields_spec.lua uses, for the
	same reason.
	═══════════════════════════════════════════════════════════════════════════
]]
ok("AssetBuilder builds a Root part",
	AssetBuilderSource:find('root.Name = "Root"', 1, true) ~= nil)
ok("Root sits at the model origin",
	AssetBuilderSource:find("root.CFrame = CFrame.new()", 1, true) ~= nil)
ok("Root is the PrimaryPart",
	AssetBuilderSource:find("model.PrimaryPart = root", 1, true) ~= nil)
ok("the Torso is NOT the PrimaryPart any more",
	AssetBuilderSource:find("model.PrimaryPart = torso", 1, true) == nil)
ok("Root is invisible and inert",
	AssetBuilderSource:find("root.Transparency = 1", 1, true) ~= nil
		and AssetBuilderSource:find("root.CanCollide = false", 1, true) ~= nil)

--[[
	And the consequence: with the pivot at the feet, a name tag pinned to it
	needs the model's height, which no longer fits in a constant.
]]
ok("AssetBuilder publishes StandHeight",
	AssetBuilderSource:find('model:SetAttribute("StandHeight"', 1, true) ~= nil)
ok("ParkService reads it for the name tag",
	ParkServiceSource:find('model:GetAttribute("StandHeight")', 1, true) ~= nil)
ok("ParkService no longer pins the tag at a fixed 8 studs",
	ParkServiceSource:find("StudsOffsetWorldSpace = Vector3.new(0, 8, 0)", 1, true) == nil)
ok("the rarity light goes in the Torso, not the Root at the ankles",
	ParkServiceSource:find('light.Parent = model:FindFirstChild("Torso")', 1, true) ~= nil)

local shortest, shortestWho = math.huge, "-"
for _, entry in ALL do
	local height = BodyPlanConfig.StandHeight(entry)
	local top = 0
	for _, item in BodyPlanConfig.Segments(entry) do
		top = math.max(top, item.At[2] + item.Size[2] * 0.5)
	end
	near(entry.Id .. " StandHeight is the top of the model", height, top, 1e-9)
	ok(entry.Id .. " stands taller than nothing", height > 0.3)
	if height < shortest then shortest, shortestWho = height, entry.Id end
end
print(string.format("  shortest plan stands %.3f footprints (%s)", shortest, shortestWho))

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
