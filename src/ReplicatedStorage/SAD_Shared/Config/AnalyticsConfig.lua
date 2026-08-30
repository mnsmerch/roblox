--!nonstrict
--[[
	AnalyticsConfig
	ReplicatedStorage/SAD_Shared/Config/AnalyticsConfig  (ModuleScript)

	docs/14's event catalogue as data: every event name, which Roblox method
	carries it, what it is allowed to attach, and the sampling rate.

	═══ WHY THE CATALOGUE IS DATA ══════════════════════════════════════════════
	Telemetry fails silently. A misspelt event name, a fourth custom field, a
	number where a string belongs - none of it errors, it just never appears on
	the dashboard, and nobody finds out until the day somebody asks what the
	tutorial completion rate is.

	So the names live here, `AnalyticsService.ValidateCoverage` asserts at boot
	that every event docs/14 lists has something that actually fires it, and the
	spec asserts the catalogue against docs/14 line by line. A silent failure
	mode needs a loud check.
	═══════════════════════════════════════════════════════════════════════════

	═══ THREE CUSTOM FIELDS. THREE. ════════════════════════════════════════════
	Roblox's analytics methods take a `customFields` dictionary keyed by
	`Enum.AnalyticsCustomFieldKeys` - and there are exactly three of them
	(CustomField01, 02, 03). A fourth key is not an error; it is dropped.

	docs/14 lists events with more attributes than that (`EggHatched` names six).
	`AnalyticsConfig.Fields` therefore declares, per event, WHICH three survive
	and in what order - a decision made once, here, rather than by whoever wrote
	the call site. The rest are folded into the event's `value`, or dropped
	deliberately, and the spec asserts no event declares more than three.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local AnalyticsConfig = {}

--[[
	Roblox's own limit, and the reason `Fields` exists. Named rather than
	written as `3` at the call sites, so if Roblox ever raises it this file is
	the only edit.
]]
AnalyticsConfig.MaxCustomFields = 3

--[[
	The custom-field keys, as the strings Roblox expects.

	`Enum.AnalyticsCustomFieldKeys.CustomField01.Name` is the documented way to
	build this key. The literal is used instead so this module stays
	dependency-free and testable outside Roblox; `AnalyticsService` asserts the
	two agree at boot, so a Roblox-side rename fails loudly rather than
	producing events with fields nobody can query.
]]
AnalyticsConfig.FieldKeys = { "customField01", "customField02", "customField03" }

--[[
	═══ OUR BUDGET, NOT ROBLOX'S ═══════════════════════════════════════════════
	Roblox rate-limits analytics calls per server. I do not know the current
	published figure and will not invent one - so this is a SELF-IMPOSED cap
	well under any plausible limit, and `AnalyticsService` counts what it drops
	so the real headroom is a measured number rather than a guess.

	Verify against the current Creator Documentation before launch and raise
	this if there is room; the code reads it from here.
	═══════════════════════════════════════════════════════════════════════════
]]
AnalyticsConfig.EventsPerMinute = 400

--- docs/14 §4: "FrameTimeSample and EconomySnapshot are sampled at 10% of
--- players. High-frequency loop events are logged in full - they're the core
--- dataset."
AnalyticsConfig.SampleRate = 0.10
AnalyticsConfig.SnapshotIntervalSecs = 3600
AnalyticsConfig.FrameSampleIntervalSecs = 60

-- ── The onboarding funnel (docs/14 §1) ──────────────────────────────────────

--[[
	Ten steps, in order. docs/14: "Step-to-step drop-off here is the single most
	valuable number in the game."

	`TutorialStarted` is step 1 and `TutorialCompleted` is step 10, but the
	tutorial has TWELVE beats - so this is not a one-to-one mapping of beats to
	funnel steps, and `Beat` says which beat fires each. Beats 1 and 3 are
	reading beats with nothing to measure; beat 12 is the farewell, which is the
	same moment as completion.
]]
local ONBOARDING = {
	{ Step = 1, Name = "TutorialStarted", Beat = 1 },
	{ Step = 2, Name = "TutorialReachedZone", Beat = 2 },
	{ Step = 3, Name = "TutorialEggStolen", Beat = 4 },
	{ Step = 4, Name = "TutorialEscaped", Beat = 5 },
	{ Step = 5, Name = "TutorialEggDeposited", Beat = 6 },
	{ Step = 6, Name = "TutorialHatched", Beat = 8 },
	{ Step = 7, Name = "TutorialDinoPlaced", Beat = 9 },
	{ Step = 8, Name = "TutorialIncomeCollected", Beat = 10 },
	{ Step = 9, Name = "TutorialUpgradeBought", Beat = 11 },
	{ Step = 10, Name = "TutorialCompleted", Beat = 12 },
}
AnalyticsConfig.Onboarding = ONBOARDING

function AnalyticsConfig.OnboardingForBeat(beat: number)
	for _, entry in ONBOARDING do
		if entry.Beat == beat then
			return entry
		end
	end
	return nil
end

-- ── Progression (docs/14 §1) ────────────────────────────────────────────────

AnalyticsConfig.ProgressionPaths = {
	ZoneUnlocked = "ZoneUnlocked",
	RebirthCompleted = "RebirthCompleted",
	IndexMilestone = "IndexMilestone",
	FirstRarity = "FirstRarity",
}

-- ── Economy tags (docs/14 §1) ───────────────────────────────────────────────

--[[
	Every Fossil and DNA flow is tagged with one of these. The list is docs/14's
	verbatim; `AnalyticsService` refuses an untagged flow rather than inventing
	a tag, because an "other" bucket that grows is a bucket nobody can act on.

	`Sink` says which direction the flow is, which is what Roblox's
	`AnalyticsEconomyFlowType` needs and what a source/sink report is built on.
]]
local ECONOMY_TAGS = {
	income_collect = { Sink = false },
	income_offline = { Sink = false },
	quest = { Sink = false },
	daily = { Sink = false },
	event = { Sink = false },
	sell = { Sink = false },
	robux_pack = { Sink = false },
	insurance = { Sink = false },
	upgrade = { Sink = true },
	defence = { Sink = true },
	zone_unlock = { Sink = true },
	reroll = { Sink = true },
	fuse = { Sink = true },
	auction = { Sink = true },
	rebirth_reset = { Sink = true },
}
AnalyticsConfig.EconomyTags = ECONOMY_TAGS

AnalyticsConfig.Currencies = { Fossils = "Fossils", DNA = "DNA" }

function AnalyticsConfig.IsSink(tag: string): boolean?
	local entry = ECONOMY_TAGS[tag]
	if not entry then
		return nil
	end
	return entry.Sink
end

-- ── Custom events (docs/14 §1) ──────────────────────────────────────────────

local custom = {}
local customOrder = {}

--[[
	`fields` is the ordered list of attribute names that survive into the three
	custom-field slots. `sampled` marks the two events docs/14 §4 samples at
	10%; everything else is logged in full.
]]
local function event(name: string, group: string, fields: { string }?, sampled: boolean?)
	assert(custom[name] == nil, "duplicate analytics event: " .. name)
	fields = fields or {}
	assert(#fields <= AnalyticsConfig.MaxCustomFields,
		("'%s' declares %d custom fields; Roblox carries %d and silently drops the rest")
			:format(name, #fields, AnalyticsConfig.MaxCustomFields))
	custom[name] = { Name = name, Group = group, Fields = fields, Sampled = sampled == true }
	table.insert(customOrder, name)
end

-- Core loop
event("EggStolen", "loop", { "rarity", "zone", "guardianArchetype" })
event("EggLost", "loop", { "rarity", "zone", "cause" })
event("ChaseStarted", "loop", { "archetype", "zone" })
event("ChaseEscaped", "loop", { "archetype", "duration" })
event("ChaseCaught", "loop", { "archetype", "duration" })
event("EggDeposited", "loop", { "rarity", "zone" })
event("IncubationStarted", "loop", { "rarity" })
--[[
	docs/14 names six attributes for EggHatched: rarity, species, mutation,
	mutation2, wasPrime, weather. Three survive.

	Rarity and species are the identity of the thing, and mutation is the
	reveal players actually chase. `mutation2` and `wasPrime` are recoverable
	from each other and are rare enough to live in the value; `weather` is
	already on `WeatherStarted` with a timestamp, so it can be joined rather
	than duplicated on every hatch in the game.
]]
event("EggHatched", "loop", { "rarity", "species", "mutation" })
event("DinoPlaced", "loop", { "rarity", "species" })
event("DinoStored", "loop", { "rarity" })
event("DinoSold", "loop", { "rarity", "species" })
event("DinoFused", "loop", { "rarity" })

-- PvP
event("StealAttempted", "pvp", { "targetPower", "myPower" })
event("StealCompleted", "pvp", { "rarity", "targetPower" })
event("StealFailed", "pvp", { "cause" })
event("PlayerRobbed", "pvp", { "rarity" })
event("RaidSurvived", "pvp", {})
event("ShieldActivated", "pvp", { "source" })
event("MercyShieldTriggered", "pvp", {})
event("VaultUsed", "pvp", {})
event("RevengeMarkUsed", "pvp", {})

-- Content engagement
event("ZoneEntered", "content", { "zone" })
event("ServerEventStarted", "content", { "eventId" })
event("ServerEventJoined", "content", { "eventId" })
event("ServerEventReward", "content", { "eventId", "tier" })
event("WeatherStarted", "content", { "weatherId" })
event("QuestCompleted", "content", { "questId", "kind" })
event("DailyClaimed", "content", { "day", "streak" })
event("IndexDiscovered", "content", { "species", "rarity" })

-- Monetization
event("ShopOpened", "money", { "tab" })
event("GamepassPromptShown", "money", { "id" })
event("GamepassPurchased", "money", { "id", "price" })
event("ProductPromptShown", "money", { "id" })
event("ProductPurchased", "money", { "id", "price" })
event("ServerBoostPurchased", "money", { "id", "playersInServer" })
event("ThanksSent", "money", {})

-- Health
event("SessionStart", "health", { "device", "isNew" })
event("SessionEnd", "health", { "reason", "durationSecs" })
event("DataLoadFailed", "health", { "reason" })
event("DataSaveFailed", "health", { "attempts" })
event("SchemaMigrated", "health", { "from", "to" })
event("ExploitFlag", "health", { "kind", "remote" })
event("SuspiciousMovement", "health", { "delta" })
event("ConfigValidationFailed", "health", { "rule" })
event("FrameTimeSample", "health", { "p50", "p10", "deviceClass" }, true)
event("EconomySnapshot", "health", { "rebirths", "zone", "placedCount" }, true)

AnalyticsConfig.Custom = custom
AnalyticsConfig.CustomOrder = customOrder

function AnalyticsConfig.Get(name: string)
	return custom[name]
end

function AnalyticsConfig.CountCustom(): number
	return #customOrder
end

--[[
	Turns an attribute table into the three-slot dictionary Roblox takes.

	Values are stringified because a custom field is a string dimension - a
	number goes in as a string either way, and doing it here means the dashboard
	never shows `1` and `1.0` as two different values of the same field.
]]
function AnalyticsConfig.BuildFields(eventName: string, attributes): { [string]: string }?
	local entry = custom[eventName]
	if not entry or #entry.Fields == 0 or attributes == nil then
		return nil
	end

	local out, count = {}, 0
	for index, field in entry.Fields do
		local value = attributes[field]
		if value ~= nil then
			count += 1
			out[AnalyticsConfig.FieldKeys[index]] = tostring(value)
		end
	end
	if count == 0 then
		return nil
	end
	return out
end

--[[
	Whether this player is in the 10% sample for a sampled event.

	Keyed on the USER ID rather than rolled per event, so a sampled player is
	sampled consistently for their whole life. A per-event roll would give 10%
	of everybody's snapshots, which cannot be joined into a per-player series -
	and a series is the whole point of `EconomySnapshot`.
]]
function AnalyticsConfig.IsSampled(userId: number, eventName: string): boolean
	local entry = custom[eventName]
	if not entry or not entry.Sampled then
		return true
	end
	if type(userId) ~= "number" then
		return false
	end
	return (math.abs(userId) % 1000) < math.floor(AnalyticsConfig.SampleRate * 1000)
end

-- ── docs/12 §4's launch gates ───────────────────────────────────────────────

--[[
	The gates, as data, so the checklist in SETUP.md and the spec cannot drift
	apart. `Offline` marks the ones the spec can actually decide; the rest need
	a playtest or a device, and saying which is which is the honest half.
]]
AnalyticsConfig.LaunchGates = {
	{ Id = "tutorial", Gate = "Tutorial completion", Threshold = ">= 75%", Offline = false },
	{ Id = "crashFree", Gate = "Crash-free sessions", Threshold = ">= 99.5%", Offline = false },
	{ Id = "frameRate", Gate = "Frame rate", Threshold = ">= 45fps p10, 2019 mid Android, 30 players", Offline = false },
	{ Id = "dataLoss", Gate = "Data loss", Threshold = "0 across a 500-session soak", Offline = false },
	{ Id = "exploitSim", Gate = "Exploit sim", Threshold = "DebugExploitClient produces 0 state changes", Offline = false },
	{ Id = "economy", Gate = "Economy", Threshold = "day-1 curve within +/-20% of docs/05 §8", Offline = true },
	{ Id = "saveLoad", Gate = "Save/load", Threshold = "100% round-trip across all migrations", Offline = true },
	{ Id = "mobileUi", Gate = "Mobile UI", Threshold = "every action one-thumbed on 5.5\"", Offline = true },
	{ Id = "moderation", Gate = "Moderation", Threshold = "no unfiltered user text anywhere", Offline = true },
}

do
	for step, entry in ONBOARDING do
		assert(entry.Step == step,
			"the onboarding funnel is out of order at " .. entry.Name)
	end
	assert(#ONBOARDING == 10, "docs/14 §1 lists ten onboarding steps")
	assert(#AnalyticsConfig.FieldKeys == AnalyticsConfig.MaxCustomFields,
		"FieldKeys must have exactly MaxCustomFields entries")
end

return AnalyticsConfig
