--[[
	Step 7 specification.

	Zone ring geometry, deterministic nest placement, and the nest sign content.

	The bugs this catches are the ones that do not throw: zones overlapping the
	park ring, two nests placed on top of each other, or a sign quoting odds
	that do not match the weight table a player will actually be rolled against.

	Run with:  ./tests/run.sh
]]

-- ── Roblox shims ────────────────────────────────────────────────────────────
local Vector3MT = {}
Vector3MT.__index = Vector3MT
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT) end
Vector3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3 = { new = v3, zero = v3(0, 0, 0), yAxis = v3(0, 1, 0) }
Color3 = { fromHex = function(hex) return { Hex = hex } end }

-- ZoneConfig.OriginOf builds a CFrame; the spec asserts on the ring maths it
-- derives, not on the rotation, so a position-carrying stand-in is enough.
CFrame = {
	lookAt = function(from, to) return { Position = from, LookAt = to } end,
	new = function(x, y, z) return { Position = v3(x, y, z) } end,
}

--@INJECT ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-48s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

------------------------------------------------------------------ ring
section("Zone ring")

local zoneHalf = ZoneConfig.ZoneSize * 0.5
local parkOuter = ParkConfig.RingRadius() + ParkConfig.PlotSize * 0.5
local zoneInner = ZoneConfig.RingRadius - zoneHalf

print(string.format("  hub radius %d | park ring %.0f..%.0f | zone ring inner edge %.0f",
	ZoneConfig.HubRadius, ParkConfig.RingRadius() - ParkConfig.PlotSize * 0.5, parkOuter, zoneInner))

ok("zones sit outside the park ring", zoneInner > parkOuter)
ok("there is a walk between parks and zones", zoneInner - parkOuter > 50)
ok("the hub plaza reaches the park ring",
	ZoneConfig.HubRadius >= ParkConfig.RingRadius() - ParkConfig.PlotSize * 0.5 - 10)
ok("the hub does not swallow the park ring",
	ZoneConfig.HubRadius < ParkConfig.RingRadius())

-- Ten slots are reserved so zones 5-10 land in their final positions.
eq("ten ring slots reserved", ZoneConfig.SlotCount, 10)
local slotsSeen = {}
for _, zoneId in ipairs(ZoneConfig.Order) do
	local zone = ZoneConfig.Zones[zoneId]
	ok("zone has a ring slot: " .. zoneId, zone.RingSlot ~= nil)
	ok("ring slot is in range: " .. zoneId, zone.RingSlot >= 1 and zone.RingSlot <= ZoneConfig.SlotCount)
	ok("ring slot is unique: " .. zoneId, not slotsSeen[zone.RingSlot])
	slotsSeen[zone.RingSlot] = true
	eq("slot matches zone order: " .. zoneId, zone.RingSlot, zone.Order)
end

-- Neighbouring slots must not overlap, at the full ten-zone build-out.
local step = math.pi * 2 / ZoneConfig.SlotCount
local chord = 2 * ZoneConfig.RingRadius * math.sin(step * 0.5)
local required = zoneHalf + zoneHalf * (math.cos(step) + math.sin(step))
print(string.format("  neighbouring zones: chord %.0f, minimum separation %.0f (margin %.0f)",
	chord, required, chord - required))
ok("all ten zone slots fit without overlapping", chord > required)

-- Zone origins land on the ring at the right angle.
for _, zoneId in ipairs(ZoneConfig.Order) do
	local origin = ZoneConfig.OriginOf(zoneId)
	ok("origin exists: " .. zoneId, origin ~= nil)
	local p = origin.Position
	local distance = math.sqrt(p.X * p.X + p.Z * p.Z)
	ok("origin is on the ring: " .. zoneId, math.abs(distance - ZoneConfig.RingRadius) < 0.01)
end
eq("an unknown zone has no origin", ZoneConfig.OriginOf("atlantis"), nil)

-- Zone 1 sits on +X, and the ring runs anticlockwise in zone order.
local plains = ZoneConfig.OriginOf("plains").Position
ok("zone 1 is on +X", plains.X > 0 and math.abs(plains.Z) < 0.01)

------------------------------------------------------------------ nests
section("Nest placement")

print(string.format("  %-8s %6s %10s %12s", "zone", "nests", "min gap", "furthest"))
for _, zoneId in ipairs(ZoneConfig.Order) do
	local zone = ZoneConfig.Zones[zoneId]
	local offsets = ZoneConfig.NestOffsets(zoneId)

	eq("nest count matches config: " .. zoneId, #offsets, zone.NestCount)

	local gap = ZoneConfig.MinNestSeparation(zoneId)
	local furthest = 0
	for _, offset in ipairs(offsets) do
		local distance = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
		if distance > furthest then furthest = distance end
	end

	print(string.format("  %-8s %6d %10.1f %12.1f", zoneId, #offsets, gap, furthest))

	-- Nest bowls are 18 studs across, and a sign post sits 3 studs behind one.
	ok("nests do not overlap: " .. zoneId, gap > 26)
	ok("every nest is inside the zone: " .. zoneId, furthest + 12 < zoneHalf)
end

-- Deterministic: same input, same layout, every session.
local firstRun = ZoneConfig.NestOffsets("plains")
local secondRun = ZoneConfig.NestOffsets("plains")
local identical = true
for index, offset in ipairs(firstRun) do
	if math.abs(offset.X - secondRun[index].X) > 1e-9 or math.abs(offset.Z - secondRun[index].Z) > 1e-9 then
		identical = false
	end
end
ok("nest placement is deterministic", identical)

-- Raising NestCount must not silently stack nests.
local zone = ZoneConfig.Zones.plains
local originalCount = zone.NestCount
zone.NestCount = 24
ok("24 nests still do not overlap", ZoneConfig.MinNestSeparation("plains") > 26)
zone.NestCount = originalCount
eq("nest count restored", zone.NestCount, 14)

------------------------------------------------------------------ signs
section("Nest sign content")

--[[
	The sign quotes exact odds. If it ever disagrees with the weight table the
	player is actually rolled against, the game is lying to them about the one
	number they screenshot.
]]
for _, zoneId in ipairs(ZoneConfig.Order) do
	local headline = ZoneConfig.HeadlineRarities(zoneId, RarityConfig, 3)
	local weights = RarityConfig.ZoneWeights[zoneId]

	eq("three headline rarities: " .. zoneId, #headline, 3)

	local lines = {}
	for _, rarityId in ipairs(headline) do
		ok(string.format("%s headline '%s' is reachable", zoneId, rarityId), (weights[rarityId] or 0) > 0)
		table.insert(lines, string.format("%s %s",
			string.upper(RarityConfig.Tiers[rarityId].DisplayName),
			Format.Odds(weights[rarityId], RarityConfig.WeightTotal)))
	end

	-- Rarest first, which is what makes the top line the hook.
	local previousRank = math.huge
	for _, rarityId in ipairs(headline) do
		local rank = RarityConfig.RankOf(rarityId)
		ok("headline runs rarest first: " .. zoneId, rank < previousRank)
		previousRank = rank
	end

	print(string.format("  %-8s %s", zoneId, table.concat(lines, "  |  ")))
end

-- The starter zone's Titan line is the specific hook from docs/02 §2.3.
eq("Zone 1 headline leads with Titan", ZoneConfig.HeadlineRarities("plains", RarityConfig, 3)[1], "titan")
eq("Zone 1 Titan odds",
	Format.Odds(RarityConfig.ZoneWeights.plains.titan, RarityConfig.WeightTotal),
	"1 IN 100,000,000")
eq("Zone 4 Titan odds",
	Format.Odds(RarityConfig.ZoneWeights.frozen.titan, RarityConfig.WeightTotal),
	"1 IN 2,000,000")

------------------------------------------------------------------ guardians
section("Guardian selection")

--[[
	Reimplements NestBuilder.PickGuardian's rule. That module cannot load
	outside Roblox, but the property that matters is testable here: every nest
	in every zone must resolve a guardian, and it must never be something absurd
	like a Titan standing over a starter nest.
]]
local function pickGuardian(zoneId, nestIndex)
	local candidates = {}
	for _, rarityId in ipairs({ "common", "uncommon", "rare" }) do
		for _, speciesId in ipairs(DinoConfig.SpeciesFor(zoneId, rarityId)) do
			table.insert(candidates, speciesId)
		end
	end
	if #candidates == 0 then return nil end
	table.sort(candidates)

	local seed = nestIndex * 7919
	for index = 1, #zoneId do
		seed = seed + string.byte(zoneId, index) * index
	end
	return candidates[(seed % #candidates) + 1]
end

for _, zoneId in ipairs(ZoneConfig.Order) do
	local zone = ZoneConfig.Zones[zoneId]
	local used = {}

	for nestIndex = 1, zone.NestCount do
		local speciesId = pickGuardian(zoneId, nestIndex)
		ok(string.format("%s nest %d has a guardian", zoneId, nestIndex), speciesId ~= nil)

		local species = speciesId and DinoConfig.Get(speciesId)
		ok(string.format("%s nest %d guardian exists", zoneId, nestIndex), species ~= nil)

		if species then
			-- Never a Legendary, Secret or Titan looming over a nest.
			ok(string.format("%s nest %d guardian is Rare or below", zoneId, nestIndex),
				RarityConfig.RankOf(species.Rarity) <= 3)

			-- And it must actually live in this zone.
			local livesHere = false
			for _, zid in ipairs(species.Zones) do
				if zid == zoneId then livesHere = true end
			end
			ok(string.format("%s nest %d guardian lives here", zoneId, nestIndex), livesHere)

			used[speciesId] = true
		end
	end

	-- Deterministic, so nests keep their guardians between sessions.
	eq(string.format("%s guardians are stable", zoneId), pickGuardian(zoneId, 1), pickGuardian(zoneId, 1))

	local variety = 0
	for _ in pairs(used) do variety = variety + 1 end
	ok(string.format("%s uses several guardian species (%d)", zoneId, variety), variety >= 2)
end

------------------------------------------------------------------ risk
section("Risk ratings")

local function riskOf(zoneId, speciesId)
	local risk = ZoneConfig.Zones[zoneId].Order
	local species = speciesId and DinoConfig.Get(speciesId)
	if species and RarityConfig.RankOf(species.Rarity) >= 3 then
		risk = risk + 1
	end
	return math.clamp(risk, 1, 5)
end

eq("Zone 1 with a common guardian is risk 1", riskOf("plains", "compsognathus"), 1)
eq("Zone 1 with a rare guardian is risk 2", riskOf("plains", "velociraptor"), 2)
eq("Zone 4 with a common guardian is risk 4", riskOf("frozen", "compsognathus"), 4)
eq("Zone 4 with a rare guardian is risk 5", riskOf("frozen", "velociraptor"), 5)

for _, zoneId in ipairs(ZoneConfig.Order) do
	local zone = ZoneConfig.Zones[zoneId]
	for nestIndex = 1, zone.NestCount do
		local risk = riskOf(zoneId, pickGuardian(zoneId, nestIndex))
		ok(string.format("%s nest %d risk is 1-5", zoneId, nestIndex), risk >= 1 and risk <= 5)
	end
end

------------------------------------------------------------------ zones
section("Zone parameters")

local totalNests, totalEggs = 0, 0
for _, zoneId in ipairs(ZoneConfig.Order) do
	local zone = ZoneConfig.Zones[zoneId]
	totalNests = totalNests + zone.NestCount
	totalEggs = totalEggs + zone.NestCount * zone.EggsPerNest

	ok("nest count is sane: " .. zoneId, zone.NestCount >= 6 and zone.NestCount <= 14)
	ok("eggs per nest is sane: " .. zoneId, zone.EggsPerNest >= 1 and zone.EggsPerNest <= 3)
	ok("has a world model name: " .. zoneId, zone.WorldModel ~= nil)
	ok("has a tagline: " .. zoneId, #zone.Tagline > 0)
end

print(string.format("  %d nests, %d eggs across %d zones", totalNests, totalEggs, ZoneConfig.Count()))
ok("enough nests for a full server", totalNests >= ParkConfig.PlotCount)
ok("enough eggs that a server cannot strip the map", totalEggs >= ParkConfig.PlotCount * 3)

-- Later zones are scarcer and slower, so progression means fewer, better eggs.
local previousRespawn, previousNests = 0, math.huge
for _, zoneId in ipairs(ZoneConfig.Order) do
	local zone = ZoneConfig.Zones[zoneId]
	ok("respawn slows through zones: " .. zoneId, zone.RespawnSecs > previousRespawn)
	ok("nests thin out through zones: " .. zoneId, zone.NestCount <= previousNests)
	previousRespawn, previousNests = zone.RespawnSecs, zone.NestCount
end

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
