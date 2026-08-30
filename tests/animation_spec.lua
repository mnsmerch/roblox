--[[
	Animation specification.

	The animation pass is blocked on assets that do not exist, so what this
	checks is the part that is not: the catalogue against docs/15 §2, the
	fallback wiring that decides what happens when a clip is missing, and the
	state machine that turns observed motion into a gait.

	The single most important assertion here is the coverage one — every clip
	that names a procedural stand-in must name one that exists. A clip pointing
	at a motion nobody wrote is a dinosaur that silently stops moving, and
	"silently" is the whole reason this file exists.

	Run with:  ./tests/run.sh
]]

Color3 = { fromHex = function(h) return { Hex = h } end }
typeof = type

--@INJECT AnimationConfig=src/ReplicatedStorage/SAD_Shared/Config/AnimationConfig.lua ChaseConfig=src/ReplicatedStorage/SAD_Shared/Config/ChaseConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %.4f want ~%.4f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

--------------------------------------------------------------- the catalogue
section("docs/15 §2's clip catalogue")

--[[
	docs/15 §2, group by group. Written out rather than counted, because the
	failure to guard against is a MISSING clip and a count would pass while the
	catalogue held the wrong thirty.
]]
local DOCS15 = {
	core = { "Idle", "Walk", "Run", "Roar", "Eat", "Sleep" },
	archetype = { "ChargeWindup", "Charge", "TailSweep", "DiveSwoop", "Burrow",
		"Spit", "Honk", "Stomp", "PackCall", "TitanRoar" },
	player = { "CarryEgg", "CarryDino", "Trip", "WindedStagger", "StealHold",
		"PlaceDino", "CollectIncome" },
	sequence = { "EggWobble", "EggCrack", "MutationBloom", "TitanHatch",
		"RebirthSweep", "GuardianDeAggro" },
}

local expected = 0
for group, names in pairs(DOCS15) do
	for _, name in ipairs(names) do
		expected += 1
		local entry = AnimationConfig.Clips[name]
		ok("docs/15 names it and the catalogue holds it: " .. name, entry ~= nil)
		if entry then
			eq("...in the right group: " .. name, entry.Group, group)
		end
	end
end
eq("the catalogue is exactly docs/15's list", #AnimationConfig.ClipOrder, expected)
print(string.format("  %d clips: 6 core, 10 archetype, 7 player, 6 sequence", expected))

-- Nothing extra: a clip nobody asked for is one nobody will animate.
do
	local named = {}
	for _, names in pairs(DOCS15) do
		for _, name in ipairs(names) do named[name] = true end
	end
	for _, name in ipairs(AnimationConfig.ClipOrder) do
		ok("nothing in the catalogue docs/15 does not name: " .. name, named[name] == true)
	end
end

--[[
	docs/15 §2's priority order: "Idle/Walk/Run for all species → Carry Egg →
	Trip → Roar → Egg crack → everything else. The first four carry 90% of the
	game's readability."

	Asserted as an ORDERING rather than as exact numbers, so the list can be
	re-tuned without the spec becoming a copy of it.
]]
local function priority(name)
	return AnimationConfig.Clips[name].Priority
end
ok("Idle comes before Walk", priority("Idle") < priority("Walk"))
ok("Walk before Run", priority("Walk") < priority("Run"))
ok("Run before Carry Egg", priority("Run") < priority("CarryEgg"))
ok("Carry Egg before Trip", priority("CarryEgg") < priority("Trip"))
ok("Trip before Roar", priority("Trip") < priority("Roar"))
ok("Roar before Egg crack", priority("Roar") < priority("EggCrack"))

for _, name in ipairs({ "Idle", "Walk", "Run", "CarryEgg" }) do
	ok("in docs/15's first four: " .. name, priority(name) <= 4)
end

-- Looping clips loop and one-shots do not; a looped Trip would never end.
for _, name in ipairs({ "Idle", "Walk", "Run", "Eat", "Sleep", "CarryEgg", "EggWobble" }) do
	ok("loops: " .. name, AnimationConfig.Clips[name].Looped == true)
end
for _, name in ipairs({ "Roar", "Trip", "Charge", "EggCrack", "TitanHatch" }) do
	ok("does not loop: " .. name, AnimationConfig.Clips[name].Looped == false)
end

---------------------------------------------------------------- the fallback
section("Every stand-in a clip names actually exists")

--[[
	═══ THE ASSERTION THIS FILE IS FOR ═════════════════════════════════════════
	A clip whose `Procedural` names a motion nobody wrote is a dinosaur that
	stops moving, with no error anywhere. `AnimationConfig` asserts this at
	require time; it is asserted again here so the failure names the clip.
	═══════════════════════════════════════════════════════════════════════════
]]
local withStandIn, without = 0, 0
for _, name in ipairs(AnimationConfig.ClipOrder) do
	local entry = AnimationConfig.Clips[name]
	if entry.Procedural then
		withStandIn += 1
		ok(name .. "'s stand-in exists: " .. entry.Procedural,
			AnimationConfig.Motions[entry.Procedural] ~= nil)
	else
		without += 1
	end
end
print(string.format("  %d clips have a procedural stand-in, %d deliberately do not",
	withStandIn, without))

--[[
	The four gait clips MUST have one, because they are what runs on every
	guardian in the game today. The player clips deliberately do not: a comedic
	waddle cannot be faked with a CFrame offset without fighting Roblox's own
	character animation, which would look worse than the walk it replaced.
]]
for _, name in ipairs({ "Idle", "Walk", "Run" }) do
	ok("the gait has a stand-in: " .. name, AnimationConfig.Clips[name].Procedural ~= nil)
end
for _, name in ipairs({ "CarryEgg", "CarryDino", "Trip", "PlaceDino" }) do
	eq("no faked player motion: " .. name, AnimationConfig.Clips[name].Procedural, nil)
end

-- Every motion is bounded. A stand-in that draws attention to itself is worse
-- than stillness, and these numbers are the difference.
for name, motion in pairs(AnimationConfig.Motions) do
	ok("subtle lift: " .. name, math.abs(motion.Height) <= 2.5)
	ok("subtle pitch: " .. name, math.abs(motion.Pitch) <= 0.4)
	ok("subtle roll: " .. name, math.abs(motion.Roll) <= 0.4)
	ok("plausible rate: " .. name, motion.Hz >= 0 and motion.Hz <= 12)
	if motion.Secs then
		ok("a one-shot ends: " .. name, motion.Secs > 0 and motion.Secs <= 3)
	end
end

-- Every motion is reachable from some clip; an unreferenced one is dead code.
do
	local referenced = {}
	for _, name in ipairs(AnimationConfig.ClipOrder) do
		local procedural = AnimationConfig.Clips[name].Procedural
		if procedural then referenced[procedural] = true end
	end
	for name in pairs(AnimationConfig.Motions) do
		ok("something plays motion '" .. name .. "'", referenced[name] == true)
	end
end

--------------------------------------------------------------- the archetypes
section("Every archetype has a character, and none of them is silly")

--[[
	One motion, twenty characters. Anything unlisted falls back to `Default`,
	deliberately, so a new archetype looks plausible immediately rather than
	invisible until somebody remembers to tune it.
]]
local styled, defaulted = 0, 0
for archetypeId in pairs(ChaseConfig.Archetypes) do
	local style = AnimationConfig.StyleFor(archetypeId)
	ok("has a style: " .. archetypeId, style ~= nil)
	if AnimationConfig.ArchetypeStyle[archetypeId] then
		styled += 1
	else
		defaulted += 1
	end
	ok("plausible rate scale: " .. archetypeId, style.HzScale > 0 and style.HzScale <= 4)
	ok("plausible lift scale: " .. archetypeId, style.HeightScale > 0 and style.HeightScale <= 3)
	ok("plausible lean scale: " .. archetypeId, style.LeanScale > 0 and style.LeanScale <= 2)
end
print(string.format("  %d of %d archetypes tuned, %d on the default",
	styled, styled + defaulted, defaulted))
eq("every shipped archetype is tuned", defaulted, 0)

-- An unknown archetype must not throw; it is the case a V1.4 species produces.
eq("an unknown archetype gets the default",
	AnimationConfig.StyleFor("notAnArchetype"), AnimationConfig.ArchetypeStyle.Default)
eq("so does no archetype at all",
	AnimationConfig.StyleFor(nil), AnimationConfig.ArchetypeStyle.Default)

--[[
	The character has to actually differentiate, or twenty styles is twenty
	copies of one. Measured as the spread across the shipped set.
]]
do
	local slowest, fastest = math.huge, 0
	local smallest, biggest = math.huge, 0
	for _, style in pairs(AnimationConfig.ArchetypeStyle) do
		slowest = math.min(slowest, style.HzScale)
		fastest = math.max(fastest, style.HzScale)
		smallest = math.min(smallest, style.HeightScale)
		biggest = math.max(biggest, style.HeightScale)
	end
	print(string.format("  bob rate spans x%.2f to x%.2f; lift spans x%.2f to x%.2f",
		slowest, fastest, smallest, biggest))
	ok("the fastest archetype bobs at least 4x the slowest", fastest / slowest >= 4)
	ok("the biggest lifts at least 4x the smallest", biggest / smallest >= 4)
end

--[[
	The Titan is the specific case worth pinning: making the biggest thing in
	the game bob fastest would read as comic rather than as threatening.
]]
do
	local titan = AnimationConfig.ArchetypeStyle.titan
	local skitterer = AnimationConfig.ArchetypeStyle.skitterer
	ok("a Titan moves slower than a Skitterer", titan.HzScale < skitterer.HzScale)
	ok("...and hugely more", titan.HeightScale > skitterer.HeightScale * 3)
end

--[[
	And every V1 species must reach a tuned style, since the archetype is read
	off the species. A species whose archetype is missing from ChaseConfig would
	animate as Default and nobody would notice.
]]
do
	local missing = 0
	for speciesId, species in pairs(DinoConfig.Species) do
		local archetype = species.ChaseArchetype
		if archetype and not AnimationConfig.ArchetypeStyle[archetype] then
			missing += 1
			ok("species reaches a tuned style: " .. speciesId, false)
		end
	end
	eq("every species' archetype is tuned", missing, 0)
end

------------------------------------------------------------------ the gait
section("Gait is derived from observed motion, not sent")

--[[
	═══ WHY DERIVED ════════════════════════════════════════════════════════════
	A guardian's position is already replicated. A "now I'm running" packet
	would be sending information the client can already see - and a derived
	state cannot desync: if the model is moving, it is running, by definition.

	The thresholds are FRACTIONS of base walk speed rather than absolute
	numbers, so they follow the game's speed instead of quietly stopping
	meaning anything the day walk speed changes.
	═══════════════════════════════════════════════════════════════════════════
]]
local base = GameConfig.BaseWalkSpeed
eq("standing still is Idle", AnimationConfig.StateFor(0, base), "Idle")
eq("a twitch is still Idle", AnimationConfig.StateFor(base * 0.05, base), "Idle")
eq("a stroll is Walk", AnimationConfig.StateFor(base * 0.3, base), "Walk")
eq("full pace is Run", AnimationConfig.StateFor(base * 1.0, base), "Run")
eq("faster than a player is still Run", AnimationConfig.StateFor(base * 3, base), "Run")

-- The boundaries themselves, both sides.
eq("just below the walk threshold", AnimationConfig.StateFor(
	base * (AnimationConfig.IdleBelowFraction - 0.001), base), "Idle")
eq("just above it", AnimationConfig.StateFor(
	base * (AnimationConfig.IdleBelowFraction + 0.001), base), "Walk")
eq("just below the run threshold", AnimationConfig.StateFor(
	base * (AnimationConfig.RunAboveFraction - 0.001), base), "Walk")
eq("just above it", AnimationConfig.StateFor(
	base * (AnimationConfig.RunAboveFraction + 0.001), base), "Run")

-- Walk must be reachable at all, which it is not if the thresholds cross.
ok("Walk is a reachable state",
	AnimationConfig.IdleBelowFraction < AnimationConfig.RunAboveFraction)

-- A zero base speed must not divide by zero.
eq("no base speed is Idle, not a crash", AnimationConfig.StateFor(5, 0), "Idle")

--[[
	Every guardian archetype, at the speed it actually chases at, must land in
	Run - or the fastest thing in the game plays a walk cycle while it catches
	you. Driven through the real speed function.
]]
do
	local thiefSpeed = base
	local notRunning = {}
	for archetypeId in pairs(ChaseConfig.Archetypes) do
		local speed = ChaseConfig.SpeedFor(archetypeId, thiefSpeed, 0)
		local state = AnimationConfig.StateFor(speed, base)
		if state ~= "Run" then
			table.insert(notRunning, archetypeId)
		end
	end
	if #notRunning > 0 then
		table.sort(notRunning)
		print("  archetypes that do not read as running: " .. table.concat(notRunning, ", "))
	end
	eq("every archetype at chase speed reads as running", #notRunning, 0)
end

--[[
	And a guardian capped by the tutorial's unlosable-chase rule must STILL read
	as running. It is slower than the player, but it is not strolling, and a
	beat-5 dinosaur playing an idle animation would undercut the one moment the
	whole FTUE is built around.
]]
do
	local capped = base * 0.82 -- TutorialConfig.ChaseSpeedFraction
	eq("the tutorial guardian still runs", AnimationConfig.StateFor(capped, base), "Run")
end

--------------------------------------------------------------- the tell
section("docs/03 §1.2's wind-up tell, which used to be speed only")

--[[
	═══ WHY THIS EXISTS AT ALL ═════════════════════════════════════════════════
	docs/03 §1.2 calls the wind-up "the tell the player reacts to". Until now it
	was a speed change and nothing else - a tell you feel a second late rather
	than one you see.

	`WildAIService` now stamps `Ability`, `WindupSecs` and `AbilityAt` on the
	guardian model as ATTRIBUTES, which replicate on their own: no remote, no
	entry in `Net`, and a client that ignores them is exactly as correct as one
	that reads them.
	═══════════════════════════════════════════════════════════════════════════
]]
ok("there is one wind-up clip, so the tell is learned once",
	AnimationConfig.Clips[AnimationConfig.WindupClip] ~= nil)
eq("...and it crouches", AnimationConfig.Clips[AnimationConfig.WindupClip].Procedural, "crouch")

--[[
	Every ability any shipped archetype has must map to a clip, or the wind-up
	leads into nothing and the player learns half a tell.
]]
do
	local unmapped = {}
	for archetypeId, archetype in pairs(ChaseConfig.Archetypes) do
		if archetype.Ability then
			local clip = AnimationConfig.AbilityClip[archetype.Ability]
			if not clip then
				table.insert(unmapped, archetypeId .. ":" .. archetype.Ability)
			else
				ok("the ability maps to a real clip: " .. archetype.Ability,
					AnimationConfig.Clips[clip] ~= nil)
			end
		end
	end
	if #unmapped > 0 then
		table.sort(unmapped)
		print("  abilities with no clip: " .. table.concat(unmapped, ", "))
	end
	eq("every shipped ability has a clip", #unmapped, 0)
end

-- And every mapped clip exists, so a V1.4 ability cannot point at a typo.
for ability, clipName in pairs(AnimationConfig.AbilityClip) do
	ok("'" .. ability .. "' maps to a catalogued clip", AnimationConfig.Clips[clipName] ~= nil)
end

--[[
	The crouch must be VISIBLE within the wind-up it accompanies, or the tell
	finishes after the thing it was warning about. Checked against the shortest
	wind-up any archetype actually uses.
]]
do
	local shortest = math.huge
	for _, archetype in pairs(ChaseConfig.Archetypes) do
		if archetype.AbilityWindupSecs and archetype.AbilityWindupSecs > 0 then
			shortest = math.min(shortest, archetype.AbilityWindupSecs)
		end
	end
	if shortest < math.huge then
		local crouch = AnimationConfig.Motions.crouch
		print(string.format("  the shortest wind-up is %.1fs; the crouch runs %.1fs at %.0f Hz",
			shortest, crouch.Secs, crouch.Hz))
		ok("the crouch fits inside the shortest wind-up", crouch.Secs <= shortest + 0.01)
		ok("...and shudders visibly while it does", crouch.Hz >= 4)
		ok("...downward, which reads as gathering", crouch.Height < 0)
	end
end

------------------------------------------------------------------- the budget
section("The budget, which is the only thing here that can cost frames")

ok("a per-frame cap exists", AnimationConfig.MaxAnimatedPerFrame > 0)

--[[
	`ChaseConfig.MaxActiveGuardians` guardians can exist at once, and a park
	holds dozens more dinosaurs. The cap has to cover at least every guardian,
	or a full chase is animating a subset of the thing the player is looking at.
]]
print(string.format("  %d models per frame against up to %d guardians",
	AnimationConfig.MaxAnimatedPerFrame, ChaseConfig.MaxActiveGuardians))
ok("the budget covers every possible guardian",
	AnimationConfig.MaxAnimatedPerFrame >= ChaseConfig.MaxActiveGuardians)

ok("Low Graphics actually cuts it",
	AnimationConfig.LowGraphicsScale > 0 and AnimationConfig.LowGraphicsScale < 1)

do
	local cut = math.max(1, math.floor(
		AnimationConfig.MaxAnimatedPerFrame * AnimationConfig.LowGraphicsScale))
	print(string.format("  Low Graphics: %d per frame, culled at %.0f studs instead of %d",
		cut, AnimationConfig.CullDistance * AnimationConfig.LowGraphicsScale,
		AnimationConfig.CullDistance))
	ok("...but never to nothing", cut >= 1)
end

--[[
	Animation culls closer than VFX, because a bob is subtler than a particle
	and stops being visible sooner. Both must be well inside the chase's own
	leash, or a guardian chasing you would be frozen while visible.
]]
ok("animation culls closer than VFX",
	AnimationConfig.CullDistance < GameConfig.VfxCullDistance)
ok("but not so close a guardian on your heels is frozen",
	AnimationConfig.CullDistance > ChaseConfig.Archetypes.spiker.Reach * 4)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
