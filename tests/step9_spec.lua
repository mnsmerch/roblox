--[[
	Step 9 specification.

	Chase archetypes, and the fairness properties the design rests on.

	The bug this class of system produces is not a crash - it is a chase that is
	impossible to escape, or one that never threatens anybody. Both render as
	"the game is bad" rather than as an error, so the escape maths is asserted
	directly.

	Run with:  ./tests/run.sh
]]

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
CFrame = { lookAt = function(from, to) return { Position = from, LookAt = to } end,
	new = function(x, y, z) return { Position = v3(x, y, z) } end }

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua ChaseConfig=src/ReplicatedStorage/SAD_Shared/Config/ChaseConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-50s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-50s got %.3f want ~%.3f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

------------------------------------------------------------------ table
section("Archetype table")

local count = 0
for id, archetype in pairs(ChaseConfig.Archetypes) do
	count = count + 1
	eq("id matches key: " .. id, archetype.Id, id)
	ok("speed ratio is sane: " .. id, archetype.SpeedRatio > 0.5 and archetype.SpeedRatio < 1.5)
	ok("turn rate is positive: " .. id, archetype.TurnRate > 0)
	ok("reach is sane: " .. id, archetype.Reach >= 4 and archetype.Reach <= 20)
	ok("gives up eventually: " .. id, archetype.GiveUpSecs >= 20 and archetype.GiveUpSecs <= 60)
	ok("has a note: " .. id, type(archetype.Note) == "string" and #archetype.Note > 0)
	ok("CanGuard is explicit: " .. id, type(archetype.CanGuard) == "boolean")

	-- An ability with a cooldown must say how long it lasts, or it fires once
	-- and never expires.
	if archetype.Ability and archetype.AbilityCooldown then
		ok("timed ability has a duration or is instant: " .. id,
			archetype.AbilityDuration ~= nil or archetype.Ability == "blink" or archetype.Ability == "glitch")
	end
	if archetype.AbilityMultiplier and archetype.AbilityMultiplier > 1 then
		ok("a speed ability has a duration: " .. id, archetype.AbilityDuration ~= nil)
	end
end
print(string.format("  %d archetypes defined", count))
ok("enough archetypes for the V1 roster", count >= 18)

eq("an unknown archetype falls back", ChaseConfig.Get("nonsense").Id, ChaseConfig.Default.Id)
eq("nil falls back", ChaseConfig.Get(nil).Id, ChaseConfig.Default.Id)
ok("the fallback can guard", ChaseConfig.Default.CanGuard)

section("Every V1 species has a chase archetype")

for id, species in pairs(DinoConfig.Species) do
	ok("archetype exists: " .. id, ChaseConfig.Archetypes[species.ChaseArchetype] ~= nil)
end

------------------------------------------------------------------ guardians
section("Guardian eligibility")

--[[
	The bug this prevents: a Plesiosaurus guarding a land nest.

	Its archetype cannot leave water, and the blockout has none, so it would
	stand motionless beside the nest forever. That is not a chase, it is a
	statue - and nothing throws.
]]
ok("swimmers cannot guard", ChaseConfig.CanGuard("swimmer") == false)
ok("sprinters can guard", ChaseConfig.CanGuard("sprinter") == true)
ok("an unknown archetype cannot guard", ChaseConfig.CanGuard("nonsense") == false)
ok("nil cannot guard", ChaseConfig.CanGuard(nil) == false)

-- Every zone must still have guardians AFTER the filter.
for _, zoneId in ipairs(ZoneConfig.Order) do
	local eligible = {}
	for _, rarityId in ipairs({ "common", "uncommon", "rare" }) do
		for _, speciesId in ipairs(DinoConfig.SpeciesFor(zoneId, rarityId)) do
			local species = DinoConfig.Get(speciesId)
			if ChaseConfig.CanGuard(species.ChaseArchetype) then
				table.insert(eligible, speciesId)
			end
		end
	end
	ok(string.format("%s has eligible guardians (%d)", zoneId, #eligible), #eligible >= 3)

	-- And several different ones, or every nest in a zone looks identical.
	local archetypes = {}
	for _, speciesId in ipairs(eligible) do
		archetypes[DinoConfig.Get(speciesId).ChaseArchetype] = true
	end
	local variety = 0
	for _ in pairs(archetypes) do variety = variety + 1 end
	ok(string.format("%s has varied guardian behaviour (%d archetypes)", zoneId, variety), variety >= 3)
end

------------------------------------------------------------------ fairness
section("Speed is relative to the thief")

local BASE = GameConfig.BaseWalkSpeed

-- A faster player is chased faster. This is what keeps a chase a chase at
-- every point on the progression curve without retuning anything.
near("a 20 studs/s thief is chased at ratio x 20",
	ChaseConfig.SpeedFor("sprinter", 20), 20 * ChaseConfig.Archetypes.sprinter.SpeedRatio, 0.001)
ok("a faster thief is chased faster",
	ChaseConfig.SpeedFor("sprinter", 30) > ChaseConfig.SpeedFor("sprinter", 20))

--[[
	THE ESCAPE GUARANTEE.

	Guardian speed is sampled from the thief's ENCUMBERED speed at aggro and
	never re-sampled. So dropping a heavy egg makes the thief faster while the
	guardian stays where it was - dropping always works, from Rare upward.

	Without this, a player carrying something heavy through a bad chase has no
	move available to them, and the answer to "what do I do" is "nothing".
]]
print(string.format("  %-11s %8s %10s %12s %s", "rarity", "carried", "fastest", "if dropped", "escapes?"))
for _, rarityId in ipairs(RarityConfig.Order) do
	local penalty = RarityConfig.Tiers[rarityId].CarryPenalty
	local encumbered = BASE * (1 - penalty)

	local fastest, fastestId = 0, nil
	for id, archetype in pairs(ChaseConfig.Archetypes) do
		if archetype.CanGuard then
			local speed = ChaseConfig.SpeedFor(id, encumbered)
			if speed > fastest then fastest, fastestId = speed, id end
		end
	end

	local escapes = BASE > fastest
	print(string.format("  %-11s %8.1f %10.1f %12.1f %s", rarityId, encumbered, fastest, BASE,
		escapes and "yes" or "no (common eggs are weightless)"))

	if penalty > 0 then
		ok("dropping a " .. rarityId .. " egg outruns every guardian", escapes)
	end
end

-- Carrying nothing, the fastest guardian is only slightly faster than you -
-- so an unencumbered player is threatened but not doomed.
local fastestRatio = 0
for id, archetype in pairs(ChaseConfig.Archetypes) do
	if archetype.CanGuard then
		fastestRatio = math.max(fastestRatio, archetype.SpeedRatio)
	end
end
ok(string.format("the fastest guardian is only just faster than you (x%.2f)", fastestRatio),
	fastestRatio > 1.0 and fastestRatio < 1.1)

------------------------------------------------------------------ chases
section("Simulated chase durations")

--[[
	Straight-line pursuit, including abilities and the zone bonus.

	The thief flees at constant speed; the guardian accelerates over
	AccelerationSecs, uses its ability on cooldown, and starts one head start
	behind. Returns seconds to close, or nil if it never does.

	Abilities are modelled because they are the actual threat. A Charger at a
	base ratio of 0.95 spends a third of every cycle at 1.71, which averages out
	well above the thief - the ratio alone says nothing about whether it catches
	you.

	A straight line is the WORST case for the thief: no corners, no shortcuts,
	no dropping the egg. If a chase is survivable here it is survivable in game.
]]
local HEAD_START = 18
local function timeToCatch(archetypeId, thiefSpeed, zoneBonus)
	local archetype = ChaseConfig.Get(archetypeId)
	local guardianSpeed = ChaseConfig.SpeedFor(archetypeId, thiefSpeed, zoneBonus)

	local gap = HEAD_START
	local dt, elapsed = 1 / 20, 0
	-- Seeded to 0, matching the service: the first ability fires one cooldown in.
	local lastAbilityAt, windupUntil, abilityUntil = 0, 0, 0
	local thiefSlowUntil, thiefSlowMult = 0, 1

	while elapsed < archetype.GiveUpSecs do
		if archetype.Ability and archetype.AbilityCooldown
			and elapsed - lastAbilityAt >= archetype.AbilityCooldown then
			local windup = archetype.AbilityWindupSecs or 0
			lastAbilityAt = elapsed
			windupUntil = elapsed + windup
			abilityUntil = windupUntil + (archetype.AbilityDuration or 0)
			if archetype.AbilityMultiplier and archetype.AbilityMultiplier < 1 then
				-- A slow does not speed the guardian up, it slows the thief.
				thiefSlowUntil = abilityUntil
				thiefSlowMult = archetype.AbilityMultiplier
			end
		end

		local speed = guardianSpeed * math.min(elapsed / ChaseConfig.AccelerationSecs, 1)
		if elapsed < windupUntil then
			speed = speed * ChaseConfig.WindupSpeedMultiplier
		elseif elapsed < abilityUntil and archetype.AbilityMultiplier and archetype.AbilityMultiplier > 1 then
			speed = speed * archetype.AbilityMultiplier
		end
		if gap > ChaseConfig.RubberBandDistance then
			speed = speed * ChaseConfig.RubberBandMultiplier
		end

		local slowed = elapsed >= windupUntil and elapsed < thiefSlowUntil
		local fleeing = thiefSpeed * (if slowed then thiefSlowMult else 1)

		gap = gap + (fleeing - speed) * dt
		elapsed = elapsed + dt
		if gap <= archetype.Reach then
			return elapsed
		end
	end
	return nil
end

local GUARDIAN_ARCHETYPES = { "grazer", "skitterer", "sprinter", "honker", "bulldozer",
	"charger", "spiker", "packhunter", "spitter", "wader", "divebomber", "glider", "ambusher" }

print(string.format("  %-12s %6s %8s %12s %12s", "archetype", "ratio", "reach", "Zone 1", "Zone 4"))
local zone1Catchers, zone1Escapers, zone4Catchers = 0, 0, 0

for _, id in ipairs(GUARDIAN_ARCHETYPES) do
	local archetype = ChaseConfig.Archetypes[id]
	local plains = timeToCatch(id, BASE, ZoneConfig.Zones.plains.GuardianSpeedBonus)
	local frozen = timeToCatch(id, BASE, ZoneConfig.Zones.frozen.GuardianSpeedBonus)

	print(string.format("  %-12s %6.2f %8d %12s %12s", id, archetype.SpeedRatio, archetype.Reach,
		plains and string.format("%.1fs", plains) or "escapes",
		frozen and string.format("%.1fs", frozen) or "escapes"))

	if plains then
		zone1Catchers = zone1Catchers + 1
		-- A catch inside a few seconds is not a chase, it is a tax.
		ok("Zone 1 catch is slow enough to be a chase: " .. id, plains >= 5)
	else
		zone1Escapers = zone1Escapers + 1
	end

	if frozen then
		zone4Catchers = zone4Catchers + 1
		ok("Zone 4 catch is slow enough to be a chase: " .. id, frozen >= 4)
	end

	-- The zone bonus must never make a chase easier.
	if plains and frozen then
		ok("Zone 4 is not slower to catch than Zone 1: " .. id, frozen <= plains + 0.001)
	end
end

--[[
	The progression the risk skulls promise.

	Zone 1 must be forgiving - most guardians outrun-able, so a new player's
	first chase is a thrill they win. Zone 4 must genuinely threaten a player
	who only knows how to hold W.
]]
print(string.format("  Zone 1: %d of %d catch a fleeing thief | Zone 4: %d of %d",
	zone1Catchers, #GUARDIAN_ARCHETYPES, zone4Catchers, #GUARDIAN_ARCHETYPES))

ok("Zone 1 is forgiving", zone1Escapers >= 5)
ok("Zone 1 still has something that catches you", zone1Catchers >= 1)
ok("Zone 4 is meaningfully harder", zone4Catchers > zone1Catchers)
ok("Zone 4 threatens roughly half the roster", zone4Catchers >= 5)

-- Ability users are the threat in the starter zone, which is the design: you
-- lose to a Charger's charge, not to being out-jogged.
ok("the starter zone's threat comes from abilities",
	timeToCatch("charger", BASE, 0) ~= nil or timeToCatch("spitter", BASE, 0) ~= nil)
eq("a plain jogger cannot catch you in Zone 1", timeToCatch("grazer", BASE, 0), nil)

-- The zone bonus must scale monotonically with zone order.
local previousBonus = -1
for _, zoneId in ipairs(ZoneConfig.Order) do
	local bonus = ZoneConfig.Zones[zoneId].GuardianSpeedBonus
	ok("guardian bonus rises with zone: " .. zoneId, bonus > previousBonus)
	previousBonus = bonus
end
eq("the starter zone has no bonus", ZoneConfig.Zones.plains.GuardianSpeedBonus, 0)
ok("the bonus never makes a guardian absurd",
	ZoneConfig.Zones.frozen.GuardianSpeedBonus <= 0.20)

section("Chase geometry")

ok("a guardian can chase across its own zone",
	ChaseConfig.MaxChaseDistance > ZoneConfig.ZoneSize * 0.5)
ok("a guardian cannot chase across the map",
	ChaseConfig.MaxChaseDistance < ZoneConfig.RingRadius * 0.5)
ok("the leash outlives the acceleration ramp",
	ChaseConfig.MaxChaseDistance / BASE > ChaseConfig.AccelerationSecs)

-- Every give-up time must sit inside the global timeout, or the global one is
-- dead code that nobody will notice is dead.
for id, archetype in pairs(ChaseConfig.Archetypes) do
	ok("give-up is inside the global timeout: " .. id,
		archetype.GiveUpSecs <= GameConfig.ChaseTimeoutSecs)
end

-- Sprinting out of a zone must be a real escape route.
local secondsToLeaveZone = (ZoneConfig.ZoneSize * 0.5) / BASE
ok(string.format("crossing a zone (%.0fs) is quicker than the leash", secondsToLeaveZone),
	secondsToLeaveZone < ChaseConfig.MaxChaseDistance / BASE)
ok("the out-of-zone grace is short enough to feel like escaping",
	ChaseConfig.OutOfZoneGraceSecs <= 10)

section("Being caught is a setback, not a punishment")

ok("winded slows you but does not stop you",
	ChaseConfig.WindedSpeedMult > 0.5 and ChaseConfig.WindedSpeedMult < 1)
ok("the trip is brief", ChaseConfig.TripRagdollSecs <= 2)
ok("winded wears off quickly", ChaseConfig.WindedSecs <= 10)
ok("the guardian loses interest after catching you", ChaseConfig.PostCatchLingerSecs <= 5)

-- Recovering fully must be faster than the egg you dropped returns to its
-- nest, or being caught means losing it outright rather than racing for it.
ok("you recover before the dropped egg vanishes",
	ChaseConfig.TripRagdollSecs + 1 < GameConfig.LooseEggLifetimeSecs)

section("Performance envelope")

eq("decisions run at 6 Hz", ChaseConfig.DecisionHz, 6)
ok("the guardian cap is bounded", ChaseConfig.MaxActiveGuardians > 0 and ChaseConfig.MaxActiveGuardians <= 30)
ok("the cap allows most of a full server to be chasing at once",
	ChaseConfig.MaxActiveGuardians >= 20)

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
