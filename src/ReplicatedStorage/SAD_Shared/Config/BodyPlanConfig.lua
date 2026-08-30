--!nonstrict
--[[
	BodyPlanConfig
	ReplicatedStorage/SAD_Shared/Config/BodyPlanConfig  (ModuleScript)

	The silhouette and palette of a placeholder dinosaur, as pure data.

	═══ WHY THIS IS A SEPARATE MODULE ══════════════════════════════════════════
	`AssetBuilder` builds Roblox `Instance`s, so nothing in it can be tested
	offline - and the first Studio run of this project proved that untested
	Instance code is where the bugs live. So the *decisions* live here as plain
	Lua numbers, and AssetBuilder is reduced to a loop that turns each
	descriptor into a Part. `tests/bodyplan_spec.lua` can then assert the things
	that actually go wrong: a limb that does not reach the ground, a body that
	spills outside its tile, a species whose colour is indistinguishable from
	its neighbour.

	This module constructs no Roblox types at all - no Vector3, no Color3, no
	Enum. Sizes and offsets are `{x, y, z}` tables, colours are `{h, s, v}`
	triples. That is what makes it injectable into the offline harness.
	═══════════════════════════════════════════════════════════════════════════

	═══ UNITS ══════════════════════════════════════════════════════════════════
	Everything is in FOOTPRINT UNITS, where 1.0 is the species' footprint in
	studs (span x ParkConfig.TileSize x VisualScale). AssetBuilder multiplies.

	  +Z is forward, towards the head.   +Y is up.   +X is the creature's right.
	  y = 0 is the ground. Every plan must put something on it.

	Working in footprint units is what lets one plan serve a 1x1 Compsognathus
	and a 4x4 Tyrannosaurus: the shape is identical, the scale is not.
	═══════════════════════════════════════════════════════════════════════════

	═══ WHAT REPLACED WHAT ════════════════════════════════════════════════════
	The previous placeholder was a box torso, a box head, a box tail and four
	box legs, tinted from a hash of the species id - seven parts, one shape for
	all 35 species, and a colour with no relationship to anything. It was built
	to prove the pipeline resolved, and it did that.

	Two things changed, both deliberate, both explained rather than silently
	swapped:

	1. `AssetBuilder.hueFor` moved here as `BodyPlanConfig.Jitter`. Same hash,
	   same stable-per-species guarantee; it now returns a small OFFSET applied
	   to the zone's hue rather than an absolute hue, because a free-running
	   hash produced a purple Stegosaurus standing next to an orange one.

	2. Colour is now derived from data the game already has - the species' home
	   zone (ZoneConfig.Color) for the hide, its rarity (RarityConfig.Color) for
	   the accent. Nothing new is hand-authored, so nothing can drift out of
	   step with the zone and rarity tables. A Legendary reads as Legendary from
	   across the park, which the old random tint actively worked against.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing. ZoneConfig and RarityConfig are PASSED IN, the same way
	`ZoneConfig.HeadlineRarities` takes a rarityConfig, so this stays a leaf.
]]

local BodyPlanConfig = {}

--[[
	Bounds every plan is checked against. These are not style preferences, they
	are the reasons a placeholder looks broken in-world:

	  HalfLength   a dinosaur longer than this overlaps the tile behind it
	  HalfWidth    ditto sideways - relaxed only for the two wide plans
	  MaxHeight    taller than this and the name tag sits inside the head
	  GroundEps    the foot must actually touch y = 0, not float or sink

	The old placeholder measured 1.27 footprints nose to tail, so 1.26 is not a
	tightening that would break placement - it is the same envelope, asserted.
]]
BodyPlanConfig.Bounds = {
	HalfLength = 0.63,
	HalfWidth = 0.22,
	WideHalfWidth = 0.56,
	MaxHeight = 1.02,
	GroundEps = 0.012,
}

--[[
	The two plans allowed to exceed `HalfWidth`, because sideways span IS their
	silhouette: a Pteranodon with wings inside its tile is a pigeon, and a
	Plesiosaurus without flippers is a log. Both spill about a stud past their
	tile on a 1x1, which the old placeholder did too - it is stated here rather
	than discovered in-world.
]]
BodyPlanConfig.WidePlans = { flyer = true, longneck = true }

-- ═══ SEGMENT AUTHORING ══════════════════════════════════════════════════════

--[[
	One piece of a dinosaur.

	  shape   "Ellipsoid" or "Block". Nothing else.
	  tint    a key into the palette: Body, Belly, Limb, Accent, Eye, Tooth.
	  rot     degrees about X, Y, Z. Optional.
	  mirror  emit a second copy at -x. Expanded by Segments(), so a spec and
	          AssetBuilder both see the finished list.

	═══ WHY ONLY TWO SHAPES ════════════════════════════════════════════════════
	A `WedgePart`'s slope orientation and a `Cylinder` part's long axis are both
	things I would be guessing at, and a guess here produces 35 models with
	their horns on backwards. An ellipsoid stretched along Z is an unambiguous
	snout; a chain of shrinking ellipsoids is an unambiguous tail. Blocks
	rotated about X are unambiguous plates. That covers every plan below.
	═══════════════════════════════════════════════════════════════════════════
]]
local function seg(name, shape, size, at, tint, rot, mirror)
	return {
		Name = name, Shape = shape,
		Size = size, At = at, Tint = tint,
		Rot = rot, Mirror = mirror,
	}
end

local function ellipsoid(name, size, at, tint, rot) return seg(name, "Ellipsoid", size, at, tint, rot, false) end
local function block(name, size, at, tint, rot) return seg(name, "Block", size, at, tint, rot, false) end
local function pair(name, shape, size, at, tint, rot) return seg(name, shape, size, at, tint, rot, true) end

--[[
	Two eyes, as one mirrored pair, plus the pale ring that makes them read as
	eyes rather than as two dents. Every plan calls this - a placeholder with
	eyes reads as a creature and one without reads as furniture, and that single
	detail does more for "does this look bad" than any amount of body shaping.
]]
local function eyes(x, y, z, size)
	return {
		pair("EyeWhite", "Ellipsoid", { size * 1.55, size * 1.55, size * 1.05 }, { x, y, z }, "Tooth"),
		pair("Eye", "Ellipsoid", { size, size, size }, { x * 1.02, y, z + size * 0.5 }, "Eye"),
	}
end

--- Four pillar legs. `spread` is the x offset, `z` the front/back offset.
local function quadLegs(spread, zFront, zBack, thickness, height)
	local foot = height * 0.16
	return {
		pair("LegFront", "Ellipsoid", { thickness, height, thickness * 1.05 }, { spread, height * 0.5, zFront }, "Limb"),
		pair("LegBack", "Ellipsoid", { thickness * 1.12, height, thickness * 1.15 }, { spread, height * 0.5, zBack }, "Limb"),
		pair("FootFront", "Block", { thickness * 1.1, foot, thickness * 1.35 }, { spread, foot * 0.5, zFront + thickness * 0.12 }, "Limb"),
		pair("FootBack", "Block", { thickness * 1.2, foot, thickness * 1.45 }, { spread, foot * 0.5, zBack + thickness * 0.12 }, "Limb"),
	}
end

--- Two bird legs: thigh, shin, foot. Used by everything bipedal.
local function bipedLegs(spread, thigh, shin, thickness, z)
	local foot = 0.045
	return {
		pair("Thigh", "Ellipsoid", { thickness * 1.25, thigh, thickness * 1.5 }, { spread, foot + shin + thigh * 0.4, z }, "Limb"),
		pair("Shin", "Ellipsoid", { thickness * 0.8, shin, thickness * 0.85 }, { spread, foot + shin * 0.5, z - thickness * 0.15 }, "Limb"),
		pair("Foot", "Block", { thickness * 0.95, foot, thickness * 2.1 }, { spread, foot * 0.5, z + thickness * 0.4 }, "Limb"),
	}
end

--- A tapering tail as a chain of ellipsoids, starting at the hips.
local function tail(startZ, startY, width, dropPerLink, links)
	local out = {}
	local z, y, w = startZ, startY, width
	for index = 1, links do
		local length = w * 1.25
		z -= length * 0.62
		y -= dropPerLink
		table.insert(out, ellipsoid("Tail" .. index, { w, w * 0.94, length }, { 0, y, z }, "Body"))
		w *= 0.68
	end
	return out
end

local function concat(...)
	local out = {}
	for _, list in { ... } do
		for _, item in list do
			table.insert(out, item)
		end
	end
	return out
end

-- ═══ THE PLANS ══════════════════════════════════════════════════════════════

BodyPlanConfig.Plans = {}

local function plan(id, segments)
	assert(BodyPlanConfig.Plans[id] == nil, "duplicate body plan: " .. id)
	BodyPlanConfig.Plans[id] = { Id = id, Segments = segments }
end

--[[
	THEROPOD - the bipedal carnivore. Eleven archetypes default to it, so it is
	the one that has to hold up: deep chest, counterbalancing tail, jaw that
	opens forward of the eyes, and an accent brow ridge that carries the rarity
	colour at the height a player's camera actually looks.
]]
plan("theropod", concat(
	bipedLegs(0.115, 0.24, 0.20, 0.105, -0.03),
	{
		ellipsoid("Torso", { 0.25, 0.28, 0.42 }, { 0, 0.47, 0.03 }, "Body"),
		ellipsoid("Belly", { 0.21, 0.16, 0.34 }, { 0, 0.40, 0.04 }, "Belly"),
		ellipsoid("Neck", { 0.14, 0.15, 0.20 }, { 0, 0.57, 0.23 }, "Body", { -18, 0, 0 }),
		ellipsoid("Head", { 0.155, 0.16, 0.22 }, { 0, 0.645, 0.35 }, "Body"),
		ellipsoid("Snout", { 0.125, 0.10, 0.19 }, { 0, 0.615, 0.44 }, "Body"),
		block("Teeth", { 0.105, 0.022, 0.16 }, { 0, 0.573, 0.45 }, "Tooth"),
		ellipsoid("Jaw", { 0.115, 0.06, 0.17 }, { 0, 0.548, 0.44 }, "Body"),
		block("Brow", { 0.17, 0.032, 0.10 }, { 0, 0.715, 0.345 }, "Accent", { -8, 0, 0 }),
		pair("Arm", "Ellipsoid", { 0.05, 0.05, 0.13 }, { 0.125, 0.45, 0.15 }, "Limb", { 22, 0, 0 }),
	},
	eyes(0.072, 0.678, 0.405, 0.036),
	tail(-0.16, 0.47, 0.20, 0.028, 4)
))

--[[
	ORNITHOPOD - the bipedal herbivore. Same stance, different read: a lighter
	body, no teeth, a beak instead of a jaw, and longer shins, which is what
	separates a Gallimimus from a Velociraptor at a glance.
]]
plan("ornithopod", concat(
	bipedLegs(0.105, 0.22, 0.26, 0.095, -0.02),
	{
		ellipsoid("Torso", { 0.22, 0.24, 0.38 }, { 0, 0.50, 0.04 }, "Body"),
		ellipsoid("Belly", { 0.19, 0.15, 0.30 }, { 0, 0.44, 0.05 }, "Belly"),
		ellipsoid("Neck", { 0.115, 0.13, 0.22 }, { 0, 0.60, 0.24 }, "Body", { -26, 0, 0 }),
		ellipsoid("Head", { 0.125, 0.125, 0.20 }, { 0, 0.695, 0.36 }, "Body"),
		ellipsoid("Beak", { 0.095, 0.075, 0.14 }, { 0, 0.665, 0.45 }, "Accent"),
		pair("Arm", "Ellipsoid", { 0.045, 0.045, 0.15 }, { 0.11, 0.49, 0.16 }, "Limb", { 30, 0, 0 }),
	},
	eyes(0.058, 0.725, 0.415, 0.032),
	tail(-0.14, 0.50, 0.17, 0.030, 4)
))

--[[
	CRESTED - the honkers. The crest IS the silhouette (a Parasaurolophus is a
	tube on a head), so it is long, it is accent-coloured, and it sweeps back
	over the neck where it breaks the outline against the sky.
]]
plan("crested", concat(
	BodyPlanConfig.Plans.ornithopod.Segments,
	{
		ellipsoid("Crest", { 0.055, 0.10, 0.30 }, { 0, 0.79, 0.24 }, "Accent", { 24, 0, 0 }),
		ellipsoid("CrestTip", { 0.05, 0.075, 0.10 }, { 0, 0.855, 0.10 }, "Accent", { 34, 0, 0 }),
	}
))

--[[
	DOMED - the pachycephalosaurs. A thick accent-coloured skull cap with a
	ring of knobs. The dome is what it hits you with, so it is the part the
	player should be able to see coming.
]]
plan("domed", concat(
	BodyPlanConfig.Plans.ornithopod.Segments,
	{
		ellipsoid("Dome", { 0.145, 0.12, 0.185 }, { 0, 0.755, 0.355 }, "Accent"),
		pair("Knob", "Ellipsoid", { 0.035, 0.035, 0.035 }, { 0.062, 0.715, 0.435 }, "Accent"),
		pair("KnobSide", "Ellipsoid", { 0.032, 0.032, 0.032 }, { 0.072, 0.735, 0.30 }, "Accent"),
	}
))

--[[
	QUADRUPED - the heavy four-legged herbivore. Horizontal back, barrel body,
	neck angled down towards a blunt head, because a grazer's head belongs near
	the ground.
]]
plan("quadruped", concat(
	quadLegs(0.135, 0.20, -0.19, 0.10, 0.26),
	{
		ellipsoid("Torso", { 0.30, 0.26, 0.52 }, { 0, 0.375, 0.00 }, "Body"),
		ellipsoid("Belly", { 0.26, 0.15, 0.44 }, { 0, 0.305, 0.01 }, "Belly"),
		ellipsoid("Shoulder", { 0.28, 0.24, 0.20 }, { 0, 0.40, 0.20 }, "Body"),
		ellipsoid("Neck", { 0.15, 0.15, 0.22 }, { 0, 0.435, 0.36 }, "Body", { 16, 0, 0 }),
		ellipsoid("Head", { 0.145, 0.135, 0.21 }, { 0, 0.415, 0.50 }, "Body"),
		ellipsoid("Beak", { 0.105, 0.085, 0.12 }, { 0, 0.395, 0.565 }, "Accent"),
	},
	eyes(0.068, 0.455, 0.545, 0.034),
	tail(-0.22, 0.37, 0.19, 0.026, 4)
))

--[[
	FRILLED - the ceratopsians. Frill first: a broad accent plate standing up
	behind the skull, then a nose horn and two brow horns. Triceratops and
	Protoceratops share this; the horns are small enough on a 1x1 that a
	Protoceratops still reads as the frilly one rather than the stabby one.
]]
plan("frilled", concat(
	quadLegs(0.135, 0.19, -0.19, 0.105, 0.25),
	{
		ellipsoid("Torso", { 0.30, 0.25, 0.46 }, { 0, 0.365, -0.03 }, "Body"),
		ellipsoid("Belly", { 0.26, 0.15, 0.38 }, { 0, 0.30, -0.02 }, "Belly"),
		ellipsoid("Shoulder", { 0.29, 0.25, 0.20 }, { 0, 0.395, 0.17 }, "Body"),
		block("Frill", { 0.36, 0.30, 0.045 }, { 0, 0.505, 0.315 }, "Accent", { 22, 0, 0 }),
		block("FrillEdge", { 0.40, 0.055, 0.05 }, { 0, 0.635, 0.265 }, "Accent", { 22, 0, 0 }),
		ellipsoid("Head", { 0.16, 0.155, 0.24 }, { 0, 0.415, 0.44 }, "Body"),
		ellipsoid("Beak", { 0.085, 0.10, 0.13 }, { 0, 0.385, 0.555 }, "Accent"),
		ellipsoid("HornNose", { 0.045, 0.11, 0.045 }, { 0, 0.475, 0.515 }, "Tooth", { -22, 0, 0 }),
		pair("HornBrow", "Ellipsoid", { 0.05, 0.17, 0.05 }, { 0.078, 0.525, 0.435 }, "Tooth", { -16, 0, 8 }),
	},
	eyes(0.077, 0.445, 0.495, 0.033),
	tail(-0.22, 0.36, 0.16, 0.028, 3)
))

--[[
	PLATED - Stegosaurus and Kentrosaurus. Two staggered rows of accent plates
	along an arched back, and four tail spikes. The arch matters: a flat-backed
	stegosaur reads as a cow with decorations.
]]
local function platesAndSpikes()
	local out = {}
	local rows = { { 0.30, 0.115 }, { 0.16, 0.135 }, { 0.01, 0.135 }, { -0.14, 0.115 }, { -0.27, 0.085 } }
	for index, row in rows do
		local z, height = row[1], row[2]
		local lean = if index % 2 == 0 then 9 else -9
		out[#out + 1] = pair("Plate", "Block", { 0.035, height, height * 1.5 },
			{ 0.045, 0.475 + height * 0.5 + (0.06 - math.abs(z) * 0.12), z }, "Accent", { 0, 0, lean })
	end
	for index = 1, 2 do
		local z = -0.46 - (index - 1) * 0.07
		out[#out + 1] = pair("Spike", "Ellipsoid", { 0.035, 0.035, 0.15 },
			{ 0.05, 0.375 - (index - 1) * 0.02, z }, "Tooth", { 0, 26, 0 })
	end
	return out
end

plan("plated", concat(
	quadLegs(0.14, 0.21, -0.18, 0.095, 0.24),
	{
		ellipsoid("Torso", { 0.28, 0.30, 0.54 }, { 0, 0.38, -0.01 }, "Body"),
		ellipsoid("Belly", { 0.24, 0.16, 0.44 }, { 0, 0.30, 0.00 }, "Belly"),
		ellipsoid("Hip", { 0.29, 0.30, 0.24 }, { 0, 0.40, -0.16 }, "Body"),
		ellipsoid("Neck", { 0.13, 0.13, 0.22 }, { 0, 0.38, 0.36 }, "Body", { 22, 0, 0 }),
		ellipsoid("Head", { 0.115, 0.105, 0.19 }, { 0, 0.325, 0.49 }, "Body"),
		ellipsoid("Beak", { 0.085, 0.07, 0.10 }, { 0, 0.31, 0.565 }, "Accent"),
	},
	eyes(0.055, 0.355, 0.53, 0.028),
	tail(-0.28, 0.375, 0.155, 0.020, 3),
	platesAndSpikes()
))

--[[
	ARMOURED - Ankylosaurus. Low, wide, close to the ground, a mosaic of accent
	scutes across the back and a club on the end of the tail. Width is the tell,
	so the torso is the widest of any plan.
]]
local function scutes()
	local out = {}
	for _, z in { 0.20, 0.06, -0.08, -0.21 } do
		out[#out + 1] = pair("Scute", "Ellipsoid", { 0.075, 0.045, 0.10 }, { 0.10, 0.335, z }, "Accent")
		out[#out + 1] = ellipsoid("ScuteMid", { 0.085, 0.05, 0.10 }, { 0, 0.345, z }, "Accent")
	end
	for _, z in { 0.20, -0.08 } do
		out[#out + 1] = pair("SpikeSide", "Ellipsoid", { 0.13, 0.045, 0.05 }, { 0.15, 0.275, z }, "Tooth", { 0, 0, 22 })
	end
	return out
end

plan("armoured", concat(
	quadLegs(0.155, 0.19, -0.17, 0.10, 0.185),
	{
		ellipsoid("Torso", { 0.38, 0.22, 0.54 }, { 0, 0.275, -0.01 }, "Body"),
		ellipsoid("Belly", { 0.32, 0.13, 0.46 }, { 0, 0.225, 0.00 }, "Belly"),
		ellipsoid("Neck", { 0.16, 0.13, 0.14 }, { 0, 0.275, 0.30 }, "Body"),
		ellipsoid("Head", { 0.175, 0.12, 0.18 }, { 0, 0.265, 0.40 }, "Body"),
		ellipsoid("Beak", { 0.13, 0.075, 0.09 }, { 0, 0.245, 0.475 }, "Accent"),
		ellipsoid("Tail1", { 0.11, 0.10, 0.20 }, { 0, 0.275, -0.35 }, "Body"),
		ellipsoid("Tail2", { 0.08, 0.075, 0.16 }, { 0, 0.275, -0.47 }, "Body"),
		ellipsoid("Club", { 0.155, 0.13, 0.16 }, { 0, 0.28, -0.545 }, "Accent"),
	},
	eyes(0.083, 0.295, 0.445, 0.030),
	scutes()
))

--[[
	SAILBACK - the spinosaurids. A theropod with a long narrow crocodile snout
	and a dorsal sail. The sail is one tall accent block rather than a row of
	spines: at placeholder resolution a solid sail reads correctly from any
	angle and a row of spines reads as a fence.
]]
plan("sailback", concat(
	bipedLegs(0.115, 0.22, 0.19, 0.10, -0.05),
	{
		ellipsoid("Torso", { 0.24, 0.27, 0.44 }, { 0, 0.44, 0.02 }, "Body"),
		ellipsoid("Belly", { 0.20, 0.15, 0.36 }, { 0, 0.375, 0.03 }, "Belly"),
		block("Sail", { 0.04, 0.30, 0.42 }, { 0, 0.71, -0.01 }, "Accent"),
		block("SailEdge", { 0.05, 0.045, 0.44 }, { 0, 0.855, -0.01 }, "Body"),
		ellipsoid("Neck", { 0.125, 0.14, 0.22 }, { 0, 0.545, 0.22 }, "Body", { -14, 0, 0 }),
		ellipsoid("Head", { 0.125, 0.13, 0.20 }, { 0, 0.605, 0.34 }, "Body"),
		ellipsoid("Snout", { 0.09, 0.085, 0.28 }, { 0, 0.575, 0.49 }, "Body"),
		block("Teeth", { 0.075, 0.022, 0.25 }, { 0, 0.545, 0.50 }, "Tooth"),
		pair("Arm", "Ellipsoid", { 0.05, 0.05, 0.16 }, { 0.12, 0.43, 0.15 }, "Limb", { 26, 0, 0 }),
	},
	eyes(0.058, 0.645, 0.395, 0.032),
	tail(-0.17, 0.44, 0.18, 0.024, 4)
))

--[[
	FLYER - Pteranodon and Microraptor. Wings are the whole silhouette, so they
	are long, thin, swept back, and allowed to break the width bound (see
	`WingedPlans`). Legs are short and tucked; the body hangs between the wings.
]]
plan("flyer", {
	ellipsoid("Torso", { 0.17, 0.16, 0.30 }, { 0, 0.44, 0.02 }, "Body"),
	ellipsoid("Belly", { 0.14, 0.10, 0.24 }, { 0, 0.40, 0.03 }, "Belly"),
	pair("WingInner", "Block", { 0.26, 0.028, 0.28 }, { 0.19, 0.475, 0.01 }, "Body", { 0, 14, 12 }),
	pair("WingOuter", "Block", { 0.24, 0.022, 0.19 }, { 0.42, 0.525, -0.07 }, "Accent", { 0, 26, 20 }),
	pair("WingBone", "Ellipsoid", { 0.50, 0.032, 0.045 }, { 0.28, 0.50, 0.10 }, "Limb", { 0, 12, 15 }),
	ellipsoid("Neck", { 0.085, 0.09, 0.14 }, { 0, 0.505, 0.19 }, "Body", { -22, 0, 0 }),
	ellipsoid("Head", { 0.09, 0.095, 0.15 }, { 0, 0.565, 0.28 }, "Body"),
	ellipsoid("Beak", { 0.055, 0.05, 0.26 }, { 0, 0.545, 0.44 }, "Tooth"),
	ellipsoid("Crest", { 0.035, 0.10, 0.17 }, { 0, 0.635, 0.21 }, "Accent", { 26, 0, 0 }),
	pair("EyeWhite", "Ellipsoid", { 0.043, 0.043, 0.03 }, { 0.045, 0.585, 0.325 }, "Tooth"),
	pair("Eye", "Ellipsoid", { 0.028, 0.028, 0.028 }, { 0.046, 0.585, 0.34 }, "Eye"),
	pair("Leg", "Ellipsoid", { 0.04, 0.30, 0.045 }, { 0.06, 0.16, -0.06 }, "Limb"),
	pair("Foot", "Block", { 0.045, 0.035, 0.09 }, { 0.06, 0.0175, -0.04 }, "Limb"),
	ellipsoid("Tail1", { 0.07, 0.065, 0.18 }, { 0, 0.42, -0.19 }, "Body"),
	ellipsoid("Tail2", { 0.045, 0.04, 0.15 }, { 0, 0.41, -0.32 }, "Body"),
	ellipsoid("TailFin", { 0.03, 0.09, 0.10 }, { 0, 0.415, -0.42 }, "Accent"),
})

--[[
	LONGNECK - Plesiosaurus, the one archetype that cannot guard a land nest
	(ChaseConfig: "cannot leave water"). Four flippers instead of legs, a barrel
	body sitting low, and a neck longer than the body. It should look wrong on
	grass, because it IS wrong on grass - that is the joke the chase system
	already tells.
]]
local function neckChain()
	local out = {}
	local z, y, w = 0.16, 0.21, 0.115
	for index = 1, 5 do
		z += 0.068
		y += 0.048
		out[#out + 1] = ellipsoid("Neck" .. index, { w, w, 0.13 }, { 0, y, z }, "Body", { -30, 0, 0 })
		w *= 0.90
	end
	return out
end

plan("longneck", concat(
	{
		ellipsoid("Torso", { 0.32, 0.22, 0.46 }, { 0, 0.11, -0.06 }, "Body"),
		ellipsoid("Belly", { 0.27, 0.13, 0.38 }, { 0, 0.07, -0.05 }, "Belly"),
		pair("FlipperFront", "Block", { 0.26, 0.035, 0.13 }, { 0.21, 0.055, 0.06 }, "Limb", { 0, 18, -10 }),
		pair("FlipperBack", "Block", { 0.22, 0.035, 0.115 }, { 0.19, 0.045, -0.22 }, "Limb", { 0, -14, -10 }),
		ellipsoid("Head", { 0.095, 0.085, 0.17 }, { 0, 0.50, 0.535 }, "Body"),
		block("Teeth", { 0.06, 0.02, 0.13 }, { 0, 0.472, 0.545 }, "Tooth"),
		block("Ridge", { 0.035, 0.05, 0.30 }, { 0, 0.235, -0.10 }, "Accent"),
		ellipsoid("Tail1", { 0.13, 0.11, 0.20 }, { 0, 0.095, -0.36 }, "Body"),
		ellipsoid("Tail2", { 0.08, 0.07, 0.16 }, { 0, 0.085, -0.50 }, "Body"),
	},
	neckChain(),
	eyes(0.045, 0.53, 0.573, 0.026)
))

--[[
	TITAN - one species, and it is the top of the collection, so it gets its own
	plan rather than a scaled theropod. Bulkier everywhere, a crown of accent
	spikes along the skull, and shoulder spikes. VisualScale 3 does the rest.
]]
local function crown()
	local out = {}
	for index = 1, 3 do
		local z = 0.40 - (index - 1) * 0.075
		out[#out + 1] = pair("Crown", "Ellipsoid", { 0.04, 0.09 + index * 0.018, 0.045 },
			{ 0.06, 0.735 + index * 0.012, z }, "Accent", { -14, 0, 14 })
	end
	out[#out + 1] = pair("ShoulderSpike", "Ellipsoid", { 0.05, 0.15, 0.05 }, { 0.115, 0.62, 0.10 }, "Accent", { -20, 0, 18 })
	return out
end

plan("titan", concat(
	bipedLegs(0.13, 0.26, 0.21, 0.125, -0.03),
	{
		ellipsoid("Torso", { 0.30, 0.32, 0.46 }, { 0, 0.50, 0.03 }, "Body"),
		ellipsoid("Belly", { 0.25, 0.18, 0.38 }, { 0, 0.42, 0.04 }, "Belly"),
		ellipsoid("Neck", { 0.17, 0.17, 0.20 }, { 0, 0.60, 0.24 }, "Body", { -16, 0, 0 }),
		ellipsoid("Head", { 0.18, 0.19, 0.25 }, { 0, 0.675, 0.37 }, "Body"),
		ellipsoid("Snout", { 0.145, 0.12, 0.21 }, { 0, 0.645, 0.47 }, "Body"),
		block("Teeth", { 0.125, 0.028, 0.18 }, { 0, 0.596, 0.48 }, "Tooth"),
		ellipsoid("Jaw", { 0.135, 0.07, 0.19 }, { 0, 0.565, 0.47 }, "Body"),
		block("Brow", { 0.20, 0.04, 0.11 }, { 0, 0.755, 0.365 }, "Accent", { -8, 0, 0 }),
		pair("Arm", "Ellipsoid", { 0.055, 0.055, 0.14 }, { 0.145, 0.48, 0.16 }, "Limb", { 22, 0, 0 }),
	},
	eyes(0.083, 0.715, 0.43, 0.040),
	crown(),
	tail(-0.14, 0.50, 0.23, 0.030, 4)
))

-- ═══ WHICH PLAN A SPECIES GETS ══════════════════════════════════════════════

--[[
	Default by chase archetype, because the archetype is already the game's own
	statement about how a species moves, and how a thing moves and how it looks
	are the same question. Every id in `ChaseConfig.Archetypes` must appear -
	`Validate()` fails the boot if one does not.
]]
BodyPlanConfig.ByArchetype = {
	grazer = "ornithopod",
	skitterer = "theropod",
	sprinter = "theropod",
	honker = "crested",
	bulldozer = "quadruped",
	charger = "domed",
	spiker = "plated",
	packhunter = "theropod",
	spitter = "theropod",
	wader = "sailback",
	swimmer = "longneck",
	divebomber = "flyer",
	glider = "flyer",
	ambusher = "theropod",
	slasher = "theropod",
	stomper = "quadruped",
	apex = "theropod",
	blinker = "theropod",
	glitcher = "theropod",
	titan = "titan",
}

--[[
	Where the archetype is right about behaviour and wrong about shape.

	`bulldozer` is the clearest case: it covers Protoceratops (frilled),
	Ankylosaurus (armoured) and Iguanodon (bipedal). They smash through scenery
	the same way and look nothing alike. Eight rows is cheaper than eight
	archetypes nobody asked for.
]]
BodyPlanConfig.BySpecies = {
	protoceratops = "frilled",
	triceratops = "frilled",
	ankylosaurus = "armoured",
	-- Iguanodon walked on all fours as readily as on two, and it is the only
	-- bulldozer left once Protoceratops and Ankylosaurus are pulled out - so it
	-- is what keeps the quadruped plan in the game rather than in the file.
	iguanodon = "quadruped",
	-- Ostrich mimics: beaked, no teeth. The theropod plan gives them a mouth
	-- full of them, which is the one thing they are known for not having.
	gallimimus = "ornithopod",
	struthiomimus = "ornithopod",
	ornithomimus = "ornithopod",
	hypsilophodon = "ornithopod",
}

function BodyPlanConfig.PlanIdFor(entry): string
	return BodyPlanConfig.BySpecies[entry.Id]
		or BodyPlanConfig.ByArchetype[entry.ChaseArchetype]
		or "theropod"
end

--[[
	The finished segment list for a species, with mirrored pairs expanded.

	Returned freshly each call rather than handed out by reference: AssetBuilder
	runs once per boot, and a caller that mutated a shared plan would corrupt
	every later species silently.
]]
function BodyPlanConfig.Segments(entry): { any }
	local planId = BodyPlanConfig.PlanIdFor(entry)
	local source = BodyPlanConfig.Plans[planId]
	assert(source, "BodyPlanConfig: no plan '" .. tostring(planId) .. "'")

	local out = {}
	for _, item in source.Segments do
		local function emit(sign, suffix)
			table.insert(out, {
				Name = item.Name .. suffix,
				Shape = item.Shape,
				Size = { item.Size[1], item.Size[2], item.Size[3] },
				At = { item.At[1] * sign, item.At[2], item.At[3] },
				Tint = item.Tint,
				Rot = if item.Rot then { item.Rot[1], item.Rot[2] * sign, item.Rot[3] * sign } else nil,
			})
		end
		if item.Mirror then
			emit(1, "R")
			emit(-1, "L")
		else
			emit(1, "")
		end
	end
	return out
end

--[[
	How tall the finished model stands, in footprint units.

	Exists because the name tag needs to sit ABOVE the dinosaur, and the only
	other way to know that at runtime is `Model:GetExtentsSize()` - which works,
	but is a measurement taken after the fact rather than a number the specs can
	check. A titan rex is 3x its own footprint; a tag placed at a fixed height
	sits at its ankle.
]]
function BodyPlanConfig.StandHeight(entry): number
	local top = 0
	for _, item in BodyPlanConfig.Segments(entry) do
		top = math.max(top, item.At[2] + item.Size[2] * 0.5)
	end
	return top
end

-- ═══ COLOUR ═════════════════════════════════════════════════════════════════

local function hexToHsv(hex: string): (number, number, number)
	local n = tonumber(hex, 16) or 0
	local r = bit32.rshift(n, 16) % 256 / 255
	local g = bit32.rshift(n, 8) % 256 / 255
	local b = n % 256 / 255

	local maxC = math.max(r, g, b)
	local minC = math.min(r, g, b)
	local delta = maxC - minC

	local h = 0
	if delta > 0 then
		if maxC == r then
			h = ((g - b) / delta) % 6
		elseif maxC == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h /= 6
	end

	return h, (if maxC == 0 then 0 else delta / maxC), maxC
end

BodyPlanConfig.HexToHsv = hexToHsv

--[[
	A stable per-species variation, as three independent numbers in [-1, 1).

	═══ WHY THREE, AND WHY NOT THE OLD HASH ════════════════════════════════════
	Was `AssetBuilder.hueFor`: `hash = (hash * 31 + byte) % 360`, used as an
	ABSOLUTE hue. Two problems, both visible in-world.

	First, a free-running hue ignored the zone, so Frozen Valley could field a
	purple dinosaur next to an orange one. That is fixed by making this an
	OFFSET applied to the zone's own hue.

	Second - and this is the one the spec caught rather than the eye - a single
	weak hash over a narrow range collides. `protoceratops` and `struthiomimus`
	came out 0.0009 apart in hue: the same colour, in the same zone, at the same
	rarity. So there are now three independent streams (different salts, a wider
	modulus, an xor fold) driving hue, saturation and value separately. Two
	species can still land on a near-identical hue; they will not also land on
	the same brightness, and the spec measures the combined distance rather than
	trusting any one channel.

	Stability is unchanged: the same id yields the same three numbers forever,
	so a species keeps its look between sessions and across roster edits. It is
	deliberately NOT keyed on `IndexOrder`, which would repaint half the roster
	every time a species is inserted in the middle of DinoConfig.
	═══════════════════════════════════════════════════════════════════════════
]]
function BodyPlanConfig.Jitter(id: string, salt: number): number
	local hash = 2166136261 + salt * 16777619
	for index = 1, #id do
		hash = bit32.bxor(hash, string.byte(id, index))
		hash = (hash * 16777619) % 4294967296
	end
	hash = bit32.bxor(hash, bit32.rshift(hash, 13))
	return (hash % 100003) / 100003 * 2 - 1
end

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

--[[
	The five tints a plan can ask for, derived from tables the game already has.

	  Body    the species' home zone colour, pulled towards a hide tone
	  Belly   the same hue, pale and desaturated
	  Limb    the same hue, darker - legs read as legs without an outline
	  Accent  the RARITY colour, untouched, on crests/plates/frills/sails
	  Eye     near-black
	  Tooth   bone white, warmed towards the body hue so it does not glow

	═══ THE DARK-RARITY SWAP ═══════════════════════════════════════════════════
	Secret is 1A1A24 - value 0.14. As an accent on a mid-toned hide it is a
	smudge nobody can see, which would make the two rarest-but-one species in
	the game the least distinctive. So when the rarity colour is darker than
	`DarkRaritySwap`, body and accent trade jobs: the hide goes near-black and
	the accent becomes its bright complement. Keyed on the measured value, not
	on a list of species ids, so a future dark rarity gets the same treatment
	without anyone remembering to add it.
	═══════════════════════════════════════════════════════════════════════════
]]
BodyPlanConfig.DarkRaritySwap = 0.30

function BodyPlanConfig.Palette(entry, zoneConfig, rarityConfig)
	local zoneId = entry.Zones and entry.Zones[1]
	local zone = zoneId and zoneConfig.Zones[zoneId]
	local zoneHex = (zone and zone.Color) or "8A8F7A"

	local tier = rarityConfig.Tiers[entry.Rarity]
	assert(tier, "BodyPlanConfig.Palette: unknown rarity '" .. tostring(entry.Rarity) .. "'")

	local zh, zs, zv = hexToHsv(zoneHex)
	local rh, rs, rv = hexToHsv(tier.Color)

	--[[
		Spread wide enough that the closest same-zone same-rarity pair clears
		the "one visible step" bar in tests/bodyplan_spec.lua, and no wider -
		past about this the zone stops reading as a family and the hides just
		look random again, which is the failure this replaced.
	]]
	local jh = BodyPlanConfig.Jitter(entry.Id, 1) * 0.105
	local js = BodyPlanConfig.Jitter(entry.Id, 2) * 0.16
	local jv = BodyPlanConfig.Jitter(entry.Id, 3) * 0.135

	local hue = (zh + jh) % 1
	local bodyS = clamp(zs * 0.88 + js, 0.22, 0.78)
	local bodyV = clamp(zv * 0.70 + jv, 0.24, 0.70)
	local accent = { rh, rs, rv }

	if rv < BodyPlanConfig.DarkRaritySwap then
		hue = (rh + jh) % 1
		bodyS = clamp(rs + 0.25 + js, 0.25, 0.8)
		bodyV = clamp(rv + 0.06 + jv * 0.4, 0.08, 0.24)
		accent = { (rh + 0.5) % 1, 0.85, 1.0 }
	end

	return {
		Body = { hue, bodyS, bodyV },
		Belly = { hue, bodyS * 0.45, clamp(bodyV * 1.62, 0.3, 0.93) },
		Limb = { hue, clamp(bodyS * 1.08, 0, 1), bodyV * 0.74 },
		Accent = accent,
		Eye = { hue, 0.35, 0.07 },
		Tooth = { hue, 0.06, 0.94 },
	}
end

-- ═══ COVERAGE ═══════════════════════════════════════════════════════════════

--[[
	Fails the boot rather than shipping a species shaped like the fallback.

	Every rule here is one that has a visible failure mode in-world: an
	archetype with no plan silently becomes a theropod; a plan whose feet do not
	reach y = 0 hovers; a plan wider than its footprint clips the dinosaur
	beside it. `ConfigValidator` calls this, so the boot log states it.
]]
function BodyPlanConfig.Validate(chaseConfig, dinoConfig): (boolean, { string })
	local problems = {}

	for archetypeId in chaseConfig.Archetypes do
		local planId = BodyPlanConfig.ByArchetype[archetypeId]
		if not planId then
			table.insert(problems, "archetype '" .. archetypeId .. "' has no body plan")
		elseif not BodyPlanConfig.Plans[planId] then
			table.insert(problems, "archetype '" .. archetypeId .. "' maps to unknown plan '" .. planId .. "'")
		end
	end

	for speciesId, planId in BodyPlanConfig.BySpecies do
		if not dinoConfig.Species[speciesId] then
			table.insert(problems, "body plan override for unknown species '" .. speciesId .. "'")
		elseif not BodyPlanConfig.Plans[planId] then
			table.insert(problems, "species '" .. speciesId .. "' maps to unknown plan '" .. planId .. "'")
		end
	end

	local bounds = BodyPlanConfig.Bounds
	for planId, planEntry in BodyPlanConfig.Plans do
		local lowest, highest = math.huge, -math.huge
		local halfWidth = if BodyPlanConfig.WidePlans[planId] then bounds.WideHalfWidth else bounds.HalfWidth
		local hasTorso = false

		for _, item in planEntry.Segments do
			if item.Name == "Torso" then
				hasTorso = true
			end
			local x = math.abs(item.At[1]) + item.Size[1] * 0.5
			local z = math.abs(item.At[3]) + item.Size[3] * 0.5
			lowest = math.min(lowest, item.At[2] - item.Size[2] * 0.5)
			highest = math.max(highest, item.At[2] + item.Size[2] * 0.5)
			if x > halfWidth then
				table.insert(problems, string.format("%s/%s reaches %.3f sideways (max %.3f)", planId, item.Name, x, halfWidth))
			end
			if z > bounds.HalfLength then
				table.insert(problems, string.format("%s/%s reaches %.3f fore-aft (max %.3f)", planId, item.Name, z, bounds.HalfLength))
			end
		end

		if not hasTorso then
			table.insert(problems, planId .. " has no part named Torso - nothing can be the PrimaryPart")
		end
		if math.abs(lowest) > bounds.GroundEps then
			table.insert(problems, string.format("%s rests at y=%.3f, not on the ground", planId, lowest))
		end
		if highest > bounds.MaxHeight then
			table.insert(problems, string.format("%s stands %.3f tall (max %.3f)", planId, highest, bounds.MaxHeight))
		end
	end

	return #problems == 0, problems
end

return BodyPlanConfig
