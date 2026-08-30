--!strict
--[[
	ChaseConfig
	ReplicatedStorage/SAD_Shared/Config/ChaseConfig  (ModuleScript)

	How each guardian archetype chases. Mirrors docs/03-stealing.md §3.

	Every archetype is DATA, not a separate implementation. They differ in five
	numbers and at most one ability, so WildAIService runs one pursuit loop and
	reads its parameters from here. Adding a nineteenth archetype is a row.

	═══ SPEED IS RELATIVE, NOT ABSOLUTE ════════════════════════════════════════
	SpeedRatio multiplies the THIEF'S speed, sampled at the moment of aggro
	(docs/03 §2). A player with maxed Runner's Legs is not chased by the same
	sluggish dinosaur a new player is, and a new player carrying a Titan egg is
	not instantly caught by one. The chase stays a chase at every point on the
	progression curve, without a single balance number needing to change.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local ChaseConfig = {}

-- ── Global tuning ───────────────────────────────────────────────────────────

--- Guardians lumber into a run over this long, which is what gives the thief a
--- guaranteed head start and reads as comedy rather than as unfairness.
ChaseConfig.AccelerationSecs = 2.0

--[[
	Speed during an ability's wind-up.

	A charge that begins instantly is not dodgeable, it is a tax - docs/03 §3
	says "winds up 1 s, then charges. Dodge sideways", and the wind-up IS the
	dodge window. Slowing the guardian while it telegraphs costs it ground,
	which is what stops a Charger closing an 18-stud head start in three
	seconds.
]]
ChaseConfig.WindupSpeedMultiplier = 0.30

--- A guardian further behind than this gets a temporary boost, so it stays on
--- screen. Tension without actually being faster.
ChaseConfig.RubberBandDistance = 120
ChaseConfig.RubberBandMultiplier = 1.15
ChaseConfig.RubberBandSecs = 3.0

--- After catching someone, a guardian loses interest and walks home.
ChaseConfig.PostCatchLingerSecs = 3.0

--- Being caught: a comedy beat, not a punishment (docs/03 §1.3).
ChaseConfig.TripRagdollSecs = 1.5
ChaseConfig.WindedSecs = 6.0
ChaseConfig.WindedSpeedMult = 0.75

--- Leaving the zone for longer than this ends the chase.
ChaseConfig.OutOfZoneGraceSecs = 8

--- Never chase further than this from the nest.
ChaseConfig.MaxChaseDistance = 250

--- Decisions run at this rate; movement integrates every frame from the last
--- decision, so the AI is cheap without looking like it updates six times a
--- second.
ChaseConfig.DecisionHz = 6

--[[
	Hard ceiling on concurrent chases (docs/09 §6).

	At the cap, a new steal RECYCLES the longest-running chase rather than
	spawning a cosmetic guardian that cannot catch anyone. A fake chase is a lie
	the player eventually notices; letting the player who has already been
	running for 40 seconds get away is a gift, bounds cost identically, and
	means every steal gets a real guardian.
]]
ChaseConfig.MaxActiveGuardians = 20

export type Archetype = {
	Id: string,
	SpeedRatio: number,
	TurnRate: number, -- radians/sec; low means bad cornering
	Reach: number, -- studs at which it catches you
	GiveUpSecs: number,
	CanGuard: boolean,
	Ability: string?,
	AbilityCooldown: number?,
	AbilityDuration: number?,
	AbilityMultiplier: number?,
	AbilityWindupSecs: number?,
	Flies: boolean?,
	Note: string,
}

--[[
	CanGuard = false means the archetype is never chosen to guard a nest.

	Swimmers are the reason this exists: a Plesiosaurus that cannot leave water
	would stand motionless beside a nest in a world with no water in it. That is
	not a chase, it is a bug that renders as a statue.
]]
ChaseConfig.Archetypes = {
	grazer = { Id = "grazer", SpeedRatio = 0.88, TurnRate = 2.2, Reach = 7, GiveUpSecs = 25,
		CanGuard = true, Note = "Gives up early. Stops to eat a bush mid-chase." },

	skitterer = { Id = "skitterer", SpeedRatio = 1.02, TurnRate = 5.0, Reach = 5, GiveUpSecs = 40,
		CanGuard = true, Note = "Tiny, fast, harmless-looking. Zigzags." },

	sprinter = { Id = "sprinter", SpeedRatio = 1.04, TurnRate = 1.4, Reach = 7, GiveUpSecs = 40,
		CanGuard = true, Note = "Straight-line speed, terrible cornering. Beat it with turns." },

	honker = { Id = "honker", SpeedRatio = 0.92, TurnRate = 2.4, Reach = 8, GiveUpSecs = 35,
		CanGuard = true, Ability = "slow", AbilityCooldown = 6, AbilityDuration = 2,
		AbilityMultiplier = 0.85, Note = "Every 6s a honk that slows you." },

	bulldozer = { Id = "bulldozer", SpeedRatio = 0.90, TurnRate = 1.8, Reach = 9, GiveUpSecs = 40,
		CanGuard = true, Note = "Smashes through scenery, opening shortcuts by accident." },

	charger = { Id = "charger", SpeciesNote = nil, SpeedRatio = 0.95, TurnRate = 1.6, Reach = 9, GiveUpSecs = 40,
		CanGuard = true, Ability = "charge", AbilityCooldown = 7, AbilityDuration = 2.5,
		AbilityMultiplier = 1.8, AbilityWindupSecs = 1.0,
		Note = "Winds up, then a straight-line charge. Dodge sideways." },

	spiker = { Id = "spiker", SpeedRatio = 0.90, TurnRate = 2.0, Reach = 12, GiveUpSecs = 35,
		CanGuard = true, Note = "Long tail sweep. Knocks the egg loose from further out." },

	packhunter = { Id = "packhunter", SpeedRatio = 1.00, TurnRate = 3.2, Reach = 7, GiveUpSecs = 45,
		CanGuard = true, Ability = "pack", Note = "Two or three units. One cuts you off." },

	spitter = { Id = "spitter", SpeedRatio = 0.94, TurnRate = 2.6, Reach = 7, GiveUpSecs = 40,
		CanGuard = true, Ability = "slow", AbilityCooldown = 4, AbilityDuration = 2,
		AbilityMultiplier = 0.70, Note = "Ranged goo. A hit slows you badly." },

	wader = { Id = "wader", SpeedRatio = 0.96, TurnRate = 2.0, Reach = 9, GiveUpSecs = 40,
		CanGuard = true, Note = "Faster in water, slower on land. Stay dry." },

	swimmer = { Id = "swimmer", SpeedRatio = 1.06, TurnRate = 3.0, Reach = 8, GiveUpSecs = 30,
		CanGuard = false, Note = "Cannot leave water, so it cannot guard a land nest." },

	divebomber = { Id = "divebomber", SpeedRatio = 1.02, TurnRate = 2.8, Reach = 8, GiveUpSecs = 40,
		CanGuard = true, Flies = true, Ability = "swoop", AbilityCooldown = 5, AbilityDuration = 1.2,
		AbilityMultiplier = 1.5, AbilityWindupSecs = 0.5, Note = "Ignores terrain. Swoops on a tell." },

	glider = { Id = "glider", SpeedRatio = 1.00, TurnRate = 3.4, Reach = 5, GiveUpSecs = 30,
		CanGuard = true, Flies = true, Note = "Low, erratic, and very hard to take seriously." },

	ambusher = { Id = "ambusher", SpeedRatio = 0.98, TurnRate = 2.2, Reach = 9, GiveUpSecs = 40,
		CanGuard = true, Ability = "predict", Note = "Aims where you are going, not where you are." },

	slasher = { Id = "slasher", SpeedRatio = 0.97, TurnRate = 1.9, Reach = 14, GiveUpSecs = 40,
		CanGuard = false, Note = "Enormous reach. Out-distance it, do not out-turn it." },

	stomper = { Id = "stomper", SpeedRatio = 0.86, TurnRate = 1.2, Reach = 11, GiveUpSecs = 35,
		CanGuard = false, Note = "Slow, but every footfall shoves you." },

	apex = { Id = "apex", SpeedRatio = 0.94, TurnRate = 1.7, Reach = 10, GiveUpSecs = 45,
		CanGuard = false, Ability = "burst", AbilityCooldown = 8, AbilityDuration = 3,
		AbilityMultiplier = 1.35, AbilityWindupSecs = 0.6,
		Note = "The classic T-Rex burst. Sprint on its cooldown." },

	blinker = { Id = "blinker", SpeedRatio = 1.05, TurnRate = 3.0, Reach = 8, GiveUpSecs = 45,
		CanGuard = false, Ability = "blink", AbilityCooldown = 6, Note = "Teleports directly behind you." },

	glitcher = { Id = "glitcher", SpeedRatio = 0.99, TurnRate = 3.0, Reach = 6, GiveUpSecs = 40,
		CanGuard = false, Ability = "glitch", AbilityCooldown = 2, Note = "Teleports a few studs at random." },

	titan = { Id = "titan", SpeedRatio = 0.82, TurnRate = 1.0, Reach = 16, GiveUpSecs = 45,
		CanGuard = false, Ability = "roar", AbilityCooldown = 7, AbilityDuration = 1.2,
		AbilityMultiplier = 0.0, AbilityWindupSecs = 0.8,
		Note = "Enormous and slow. Its roar stops you where you stand." },
}

--- Fallback so an archetype id nobody implemented still produces a chase.
ChaseConfig.Default = ChaseConfig.Archetypes.sprinter

function ChaseConfig.Get(archetypeId: string?): Archetype
	if not archetypeId then
		return ChaseConfig.Default
	end
	return (ChaseConfig.Archetypes :: any)[archetypeId] or ChaseConfig.Default
end

function ChaseConfig.CanGuard(archetypeId: string?): boolean
	if not archetypeId then
		return false
	end
	local archetype = (ChaseConfig.Archetypes :: any)[archetypeId]
	return archetype ~= nil and archetype.CanGuard == true
end

--[[
	Guardian speed, given the thief's speed at the moment of aggro and the
	zone's guardian bonus.

	The zone bonus is what makes a Risk 4 sign mean something. Without it every
	archetype's ratio sits at or below about 1.04, and a two-second acceleration
	ramp costs more ground than 1.04 recovers in forty seconds - so a thief who
	simply holds W is uncatchable in Frozen Valley exactly as they are in
	Jurassic Plains, and the skulls on the sign are decoration.

	docs/02 wants zone difficulty to come from hazards (mud pools, ice) as well.
	Those need real geometry and are not in the blockout, so today the whole
	difficulty curve rests on this number. See PROGRESS.md.
]]
function ChaseConfig.SpeedFor(archetypeId: string?, thiefSpeed: number, zoneBonus: number?): number
	return thiefSpeed * (ChaseConfig.Get(archetypeId).SpeedRatio + (zoneBonus or 0))
end

return ChaseConfig
