--!nonstrict
--[[
	WeatherConfig
	ReplicatedStorage/SAD_Shared/Config/WeatherConfig  (ModuleScript)

	The weather table from docs/04 §2: what can happen, how likely it is, how
	long it lasts, and what it does that is not a mutation weight.

	═══ MUTATION WEIGHTS ARE NOT HERE ══════════════════════════════════════════
	`MutationConfig.WeatherModifiers` owns those, and stays the only place they
	live. Deviation #5 removed `ZoneConfig.SpeciesPool` for exactly this reason:
	two tables describing one relationship drift apart the first time someone
	edits in a hurry, and the drift is silent.

	ConfigValidator rule 11 asserts the two tables name the same weathers, so a
	weather added to one and forgotten in the other fails at boot.
	═══════════════════════════════════════════════════════════════════════════

	V1 ships four. The other seven from docs/04 §2 are recorded at the bottom
	with their published weights so V1.1 is a paste rather than a redesign.

	Depends on: nothing.
]]

local WeatherConfig = {}

--- docs/04 §2: "Rolls every 8 minutes".
WeatherConfig.RollInterval = 8 * 60

--- The countdown before a new weather lands (docs/04 §2).
WeatherConfig.CountdownSecs = 20

--[[
	docs/04 §2: exotic weather is followed by a forced Clear gap of at least
	three minutes. Without it two exotics can run back to back and "special"
	stops meaning anything.
]]
WeatherConfig.MinClearGapSecs = 3 * 60

local weathers = {}

local function weather(entry)
	entry.Effects = entry.Effects or {}
	assert(weathers[entry.Id] == nil, "duplicate weather: " .. entry.Id)
	weathers[entry.Id] = entry
	return entry
end

--[[
	`Effects` are the non-mutation consequences. Each key is read by exactly
	one system, named in the comment beside it, so "what does Rainstorm do"
	has one answer and one place to change it.
]]

weather({
	Id = "clear", DisplayName = "Clear", Weight = 4500, DurationSecs = 0,
	Color = "9FD6FF", InV1 = true,
	Blurb = "Baseline",
	Effects = {},
})

weather({
	Id = "rainstorm", DisplayName = "Rainstorm", Weight = 1400, DurationSecs = 6 * 60,
	Color = "5A7A9A", InV1 = true,
	Blurb = "The ground turns to soup, but the nests refill faster",
	Effects = {
		GroundSpeedMult = 0.90, -- EggService speed modifier, every player
		NestRespawnMult = 0.75, -- NestService: 25% faster
	},
})

weather({
	Id = "thunderstorm", DisplayName = "Thunderstorm", Weight = 900, DurationSecs = 5 * 60,
	Color = "8A7ACC", InV1 = true,
	Blurb = "Electric mutations, and lightning that knocks eggs loose",
	Effects = {
		-- WeatherService: chance per carrying player per LightningInterval.
		LightningChance = 0.10,
		LightningInterval = 12,
	},
})

weather({
	Id = "blizzard", DisplayName = "Blizzard", Weight = 650, DurationSecs = 5 * 60,
	Color = "D8ECFF", InV1 = true,
	Blurb = "Frozen mutations. You cannot see, and the Valley is worse",
	Effects = {
		FogEnd = 260, -- WeatherController: local Lighting only
		--[[
			docs/04 §2's "Frozen Valley x2". Doubles the weather's own mutation
			modifier inside that zone - so Frozen goes 25 -> 50, which the x40
			cap then trims to 40. That interaction is the cap earning its keep
			rather than being decoration.
		]]
		ZoneBoost = { frozen = 2 },
	},
})

--[[
	V1.1+, with the weights and durations docs/04 §2 publishes. Adding one is
	this block plus an entry in MutationConfig.WeatherModifiers:

		heatwave        700  6m   +20% Fossil income; guardians -8% speed
		meteorshower    550  5m   +40% rare-egg weight server-wide (luck +0.9)
		volcanicash     500  6m   Volcanic x25; ash slows everyone incl. guardians
		radiationstorm  350  5m   Radioactive x30, Toxic x15; Wasteland nests +1 tier
		aurora          250  7m   Celestial x20, Lunar x12
		bloodmoon       130  6m   Blood Moon x40, Shadow x20; guardians +10%; steals x1.5
		solareclipse     70  4m   Secret rarity x8, Solar x30. Full server announcement
]]

WeatherConfig.Weathers = weathers

WeatherConfig.Order = { "clear", "rainstorm", "thunderstorm", "blizzard" }

-- ── Helpers ─────────────────────────────────────────────────────────────────

function WeatherConfig.Get(weatherId: string?)
	if not weatherId then
		return weathers.clear
	end
	return weathers[weatherId]
end

--- The weight table the roll picks from. V1-only, so an unshipped weather
--- cannot be rolled by having been left in the table.
function WeatherConfig.RollableWeights(): { [string]: number }
	local pool = {}
	for id, entry in weathers do
		if entry.InV1 then
			pool[id] = entry.Weight
		end
	end
	return pool
end

--- The share of rolls that land on Clear, as a fraction. docs/04 §2 wants
--- roughly 45%: "special needs to feel special".
function WeatherConfig.ClearShare(): number
	local total, clear = 0, 0
	for id, weight in WeatherConfig.RollableWeights() do
		total += weight
		if id == "clear" then
			clear = weight
		end
	end
	return if total > 0 then clear / total else 0
end

function WeatherConfig.EffectOf(weatherId: string?, key: string, default: any): any
	local entry = WeatherConfig.Get(weatherId)
	if not entry then
		return default
	end
	local value = entry.Effects[key]
	if value == nil then
		return default
	end
	return value
end

--[[
	The extra multiplier this weather applies to its own mutation modifiers
	inside `zoneId`. 1 when there is none, so callers multiply unconditionally.
]]
function WeatherConfig.ZoneBoost(weatherId: string?, zoneId: string?): number
	if not zoneId then
		return 1
	end
	local boosts = WeatherConfig.EffectOf(weatherId, "ZoneBoost", nil)
	return (boosts and boosts[zoneId]) or 1
end

--- How long a weather lasts. Clear has no duration of its own: it runs until
--- the next roll, which is what makes it the resting state.
function WeatherConfig.DurationOf(weatherId: string?): number
	local entry = WeatherConfig.Get(weatherId)
	if not entry or entry.DurationSecs <= 0 then
		return WeatherConfig.RollInterval
	end
	return entry.DurationSecs
end

function WeatherConfig.Count(): number
	local count = 0
	for _, entry in weathers do
		if entry.InV1 then
			count += 1
		end
	end
	return count
end

return WeatherConfig
