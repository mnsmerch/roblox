--!nonstrict
--[[
	EventConfig
	ReplicatedStorage/SAD_Shared/Config/EventConfig  (ModuleScript)

	The server events from docs/04 §3: what can fire, how likely, how long, and
	which handler runs it.

	`Handler` is the contract with EventService: the name of a ModuleScript in
	`EventService/Handlers`. ConfigValidator rule 8 - written in Step 3 and
	skipped ever since - asserts every one of them resolves, so an event added
	here without a handler fails at boot rather than firing into nothing.

	V1 ships four (docs/12 §MVP): Meteor Impact, Dinosaur Stampede, Nest
	Frenzy, Amber Rain. The other eight are recorded at the bottom with their
	published weights.

	Depends on: nothing.
]]

local EventConfig = {}

--- docs/04 §3: "Events fire every 12-18 minutes (randomised)".
EventConfig.MinGapSecs = 12 * 60
EventConfig.MaxGapSecs = 18 * 60

--- docs/04 §3: "a 60-second countdown and a map marker".
EventConfig.CountdownSecs = 60

--- docs/04 §3.1: "Countdown notification at 60 s, 30 s, 10 s".
EventConfig.CountdownBeats = { 60, 30, 10 }

--[[
	docs/04 §3: "Weighted selection with a no-repeat-within-3 rule."

	With only four events shipping, three is almost the whole list - so the
	rule is clamped to leave at least two choices, or a fourth event could
	become impossible to schedule.
]]
EventConfig.NoRepeatWithin = 3

--[[
	docs/04 §3.1: "Nobody who participates receives nothing. Minimum
	participation reward is always >= 3 minutes of that player's income."

	Expressed in seconds of their own income, so it scales with the player it
	is protecting rather than becoming worthless by hour four.
]]
EventConfig.MinRewardIncomeSecs = 180

--- docs/04 §3.1: "Every event ends with a contribution scoreboard (top 5)."
EventConfig.ScoreboardSize = 5

--[[
	docs/13 names "events continuing after the last participant leaves" as this
	step's hazard. An event with nobody in the server ends rather than running
	its geometry into an empty world.
]]
EventConfig.EndWhenEmpty = true

local events = {}

local function event(entry)
	assert(events[entry.Id] == nil, "duplicate event: " .. entry.Id)
	events[entry.Id] = entry
	return entry
end

event({
	Id = "meteorImpact", DisplayName = "Meteor Impact", Handler = "MeteorImpact",
	Weight = 160, DurationSecs = 3 * 60, InV1 = true,
	TelegraphSecs = 15,
	Blurb = "A meteor is falling. Get to the crater",
	--[[
		docs/04 §3 also gives the crater "Radioactive weight x20". Radioactive
		is a V1.6 mutation (docs/12), so V1 ships the half that exists: every
		crater egg is GUARANTEED to hatch mutated. The skew arrives with the
		mutation it skews towards.
	]]
	Params = { EggCount = 8, Guaranteed = true, FirstBonusFossils = 2500 },
})

event({
	Id = "stampede", DisplayName = "Dinosaur Stampede", Handler = "Stampede",
	Weight = 160, DurationSecs = 2 * 60, InV1 = true,
	TelegraphSecs = 10,
	Blurb = "Tag a running dinosaur to keep it",
	Params = { HerdSize = 40, TagRange = 14, MaxCaptures = 1 },
})

event({
	Id = "nestFrenzy", DisplayName = "Nest Frenzy", Handler = "NestFrenzy",
	Weight = 150, DurationSecs = 3 * 60, InV1 = true,
	TelegraphSecs = 0,
	Blurb = "Every nest refills in seconds. Guardians are sluggish",
	Params = { RespawnSecs = 3, GuardianSpeedMult = 0.80 },
})

event({
	Id = "amberRain", DisplayName = "Amber Rain", Handler = "AmberRain",
	Weight = 80, DurationSecs = 2 * 60, InV1 = true,
	TelegraphSecs = 10,
	Blurb = "Amber is falling on the hub. Grab it",
	--[[
		docs/04 §3 calls this "the catch-up mechanic", so the reward is a flat
		amount rather than a share of park income: it has to be worth more to
		a player with nothing than to one with everything.
	]]
	Params = { ChunkCount = 60, ChunkFossils = 400, ChunkDna = 2, SpawnRadius = 260 },
})

--[[
	V1.1+, with the weights and durations docs/04 §3 publishes:

		greatMigration  120  4m  one zone's nests upgraded a full rarity tier
		titanEgg         90  5m  a colossal egg in the Arena, charged by holding
		volcano          90  4m  Zone 5 erupts; Volcanic eggs spawn everywhere
		bossDino         80  5m  a 4x Apex with a shared Exhaustion bar
		timePortal       60  4m  a pocket arena of 20 nests, no zone gating
		skyFall          55  3m  flying dinosaurs drop eggs on parachutes
		fossilAuction    40  3m  a hidden-rarity egg auctioned for Fossils
		blackoutRaid     30  3m  OPT-IN ONLY. Shields drop, steal rewards x3

	docs/04 §3 is explicit that Blackout Raid must be opt-in: "a forced
	server-wide shield drop is the fastest way to make a 9-year-old quit".
	Whoever builds it should read that paragraph first.
]]

EventConfig.Events = events

EventConfig.Order = { "meteorImpact", "stampede", "nestFrenzy", "amberRain" }

-- ── Helpers ─────────────────────────────────────────────────────────────────

function EventConfig.Get(eventId: string?)
	if not eventId then
		return nil
	end
	return events[eventId]
end

function EventConfig.RollableWeights(exclude: { [string]: boolean }?): { [string]: number }
	local pool = {}
	for id, entry in events do
		if entry.InV1 and not (exclude and exclude[id]) then
			pool[id] = entry.Weight
		end
	end
	return pool
end

function EventConfig.Count(): number
	local count = 0
	for _, entry in events do
		if entry.InV1 then
			count += 1
		end
	end
	return count
end

--[[
	How many recent events to exclude from the next roll.

	Clamped so at least two remain selectable. With four events a strict
	no-repeat-within-3 leaves exactly one choice, which is not a weighted roll
	any more - it is a fixed rotation.
]]
function EventConfig.ExclusionDepth(): number
	return math.min(EventConfig.NoRepeatWithin, math.max(0, EventConfig.Count() - 2))
end

function EventConfig.Param(eventId: string, key: string, default: any): any
	local entry = events[eventId]
	if not entry or not entry.Params then
		return default
	end
	local value = entry.Params[key]
	if value == nil then
		return default
	end
	return value
end

return EventConfig
