--!nonstrict
--[[
	TutorialConfig
	ReplicatedStorage/SAD_Shared/Config/TutorialConfig  (ModuleScript)

	docs/00 §3's twelve beats, and the four places the tutorial is allowed to
	bend the real game.

	═══ IT DRIVES THE REAL SYSTEMS, IT DOES NOT REPLACE THEM ═══════════════════
	docs/13 §Step 23 names the failure: "the tutorial fighting the real systems
	(it must DRIVE them, never bypass them)."

	So there is no tutorial sandbox, no second pickup path and no fake hatch.
	The four things docs/00 promises to bend are PURE FUNCTIONS OF THE PROFILE,
	consulted by the real service at the point it already computes that number:

		ForcedRarity(data)      EggService.RollRarity    beat 4 is always Common
		ForcedHatchSecs(data)   IncubationService        beat 8 is always 10s
		ChaseSpeedCap(data)     WildAIService            beat 5 cannot be lost
		TopUpFor(data, cost)    TutorialService          beat 11 is affordable

	Each returns nil for everybody who is not mid-tutorial, so the real path is
	the only path and the tutorial is a modifier on it rather than a fork.
	═══════════════════════════════════════════════════════════════════════════

	═══ THE SERVER OWNS THE STEP NUMBER ════════════════════════════════════════
	`Profile.Tutorial.Step` is server state. The client asks to advance and the
	server checks the ask against what the player has actually done - a client
	that could set its own step could claim step 12 and collect the completion
	grant without playing.

	`Beats[n].Requires` is that check, and it is data rather than a switch
	statement so the spec can drive every beat's condition directly.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local TutorialConfig = {}

--- docs/08 §6: "Every FTUE step has a 25-second timeout after which the arrow
--- enlarges and a hint appears; after 60 s the step auto-completes so nobody
--- gets stuck."
TutorialConfig.HintAfterSecs = 25
TutorialConfig.AutoAdvanceAfterSecs = 60

--- docs/00 §3's target: "2m 30s to 'I get it'".
TutorialConfig.TargetSecs = 150

--- Beat 4 is Reveal #1 and it is always the same reveal, so the player learns
--- what a rarity flash MEANS before the odds start mattering.
TutorialConfig.ForcedFirstRarity = "common"

--- Beat 8: "hatches in a forced 10 seconds with full crack VFX".
--- Named `HatchSecs` rather than `ForcedHatchSecs` because the latter is the
--- FUNCTION below, and a constant quietly overwritten by a function of the same
--- name is the kind of thing that works until somebody reads it.
TutorialConfig.HatchSecs = 10

--[[
	Beat 5: "The first chase is unlosable. The guardian's speed is capped below
	the player's. The player must FEEL the chase, not fail it."

	A fraction of the thief's own speed rather than a fixed number, so it stays
	unlosable whatever the player is carrying and whatever Runner's Legs they
	somehow already have.
]]
TutorialConfig.ChaseSpeedFraction = 0.82

--[[
	Which upgrade beat 11 highlights. docs/00: "Upgrade board pre-highlighted,
	first upgrade costs exactly what you now have."

	Dinosaur Slots because it is the cheapest track in the game and because
	"room for one more dinosaur" is the sentence that makes the sink obvious.
]]
TutorialConfig.FirstUpgradeId = "dinoSlots"

--[[
	docs/00's beat 10 shows "+120 Fossils!" from the first collect, and beat 11
	says the first upgrade "costs exactly what you now have". Those cannot both
	be literally true - the cheapest track is 800 - so beat 10 tops the player
	up to the price rather than the design quietly not working. See the
	deviation note in PROGRESS.md.

	A top-up, not a grant: a player who took their time and earned 700 gets 100,
	and one who already has 800 gets nothing. "Exactly what you now have" stays
	true either way.
]]
TutorialConfig.TopUpToUpgrade = true

--- Skipping still pays out, per docs/00: "If a player skips, they still receive
--- the tutorial egg in their inventory."
TutorialConfig.SkipGrantsEgg = true

-- ── The beats ───────────────────────────────────────────────────────────────

local beats = {}

--[[
	`Requires` is the server's check, named rather than written as a function so
	the same string can be evaluated on either side and asserted in a spec:

		"none"        advance on the client's ask alone (pure reading beats)
		"inZone"      the player is standing in a zone, not the hub
		"carrying"    the player is carrying at least one egg
		"chased"      a chase has started for this player
		"home"        the player is inside their own park
		"incubating"  at least one incubator slot is occupied
		"hatched"     the player owns at least one dinosaur
		"placed"      at least one dinosaur is placed on a tile
		"collected"   the player has collected banked income at least once
		"upgraded"    the player owns at least one upgrade level
]]
local function beat(entry)
	entry.Step = #beats + 1
	--[[
		docs/00 §3: Rok "speaks in <= 8-word speech bubbles", and total forced
		reading is "under 60 words". Asserted per beat here and in total below,
		because a tutorial's word count is the one thing that always grows.
	]]
	local words = select(2, entry.Text:gsub("%S+", ""))
	assert(words <= 8, ("beat text is %d words, docs/00 §3 allows 8: %s"):format(words, entry.Text))
	table.insert(beats, entry)
	return entry
end

beat({ Id = "park", Text = "This is YOUR park!", Objective = "Look around your park",
	Requires = "none", Teaches = "Ownership", Arrow = "gate" })

beat({ Id = "leave", Text = "Follow me!", Objective = "Head out to Jurassic Plains",
	Requires = "inZone", Teaches = "The world is close", Arrow = "zone1" })

beat({ Id = "findEgg", Text = "See that egg? TAKE IT.", Objective = "Find the glowing nest",
	Requires = "none", Teaches = "The verb", Arrow = "nest" })

beat({ Id = "takeEgg", Text = "Grab it!", Objective = "Hold E on the egg",
	Requires = "carrying", Teaches = "Reveal #1", Arrow = "nest" })

beat({ Id = "run", Text = "RUN!!!", Objective = "Get away from the guardian",
	Requires = "chased", Teaches = "The pillar", Arrow = "park", Takeover = true })

beat({ Id = "safe", Text = "SAFE!", Objective = "Get back inside your park",
	Requires = "home", Teaches = "Safe zone rule", Arrow = "park" })

beat({ Id = "incubate", Text = "Eggs hatch in here.", Objective = "Stand on an incubator pad",
	Requires = "incubating", Teaches = "Incubation", Arrow = "incubator" })

beat({ Id = "hatch", Text = "Here it comes!", Objective = "Wait for the egg to hatch",
	Requires = "hatched", Teaches = "Reveals #2 and #3", Arrow = "incubator" })

beat({ Id = "place", Text = "Put him in the park!", Objective = "Place your dinosaur",
	Requires = "placed", Teaches = "Placement", Arrow = "tile" })

beat({ Id = "collect", Text = "Tap the pile!", Objective = "Collect your Fossils",
	Requires = "collected", Teaches = "Income", Arrow = "totem" })

beat({ Id = "upgrade", Text = "Buy this!", Objective = "Buy your first upgrade",
	Requires = "upgraded", Teaches = "The sink", Arrow = "shop", OpensShop = true })

beat({ Id = "farewell", Text = "Go get a BIG one!", Objective = "You're on your own",
	Requires = "none", Teaches = "Release", Arrow = nil })

TutorialConfig.Beats = beats
TutorialConfig.StepCount = #beats

--[[
	docs/00 §3: "He is skippable at any time and disappears permanently after
	step 10." Rok leaves before the upgrade board because beat 11 opens the one
	menu the FTUE is allowed to open, and a character hopping in front of it is
	in the way.
]]
TutorialConfig.RokLeavesAfterStep = 10

-- ── Helpers ─────────────────────────────────────────────────────────────────

function TutorialConfig.Get(step: number)
	return beats[step]
end

--- Whether this profile is mid-tutorial: started or not, but not finished and
--- not skipped. Everything below keys off this.
function TutorialConfig.IsActive(data): boolean
	local state = data and data.Tutorial
	if not state then
		return false
	end
	return not state.Completed and state.SkippedAt == nil
end

function TutorialConfig.StepOf(data): number
	local state = data and data.Tutorial
	return (state and state.Step) or 0
end

--[[
	The four bends. Each returns nil when it does not apply, so a caller writes

		local forced = TutorialConfig.ForcedRarity(data)
		local rarity = forced or EggService.RollRarityIn(...)

	and the real roll is what runs for everybody else.
]]

--- Beat 4's Common. Applies while the player has not yet taken their first egg,
--- which is steps 1-4: after that they are rolling for real.
function TutorialConfig.ForcedRarity(data): string?
	if not TutorialConfig.IsActive(data) then
		return nil
	end
	if TutorialConfig.StepOf(data) > 4 then
		return nil
	end
	return TutorialConfig.ForcedFirstRarity
end

--- Beat 8's ten seconds. Applies up to and including the hatch beat.
function TutorialConfig.ForcedHatchSecs(data): number?
	if not TutorialConfig.IsActive(data) then
		return nil
	end
	if TutorialConfig.StepOf(data) > 8 then
		return nil
	end
	return TutorialConfig.HatchSecs
end

--[[
	Beat 5's unlosable chase, as a speed CAP rather than a speed.

	Returns the fastest the guardian may move given the thief's own speed, or
	nil once the tutorial chase is behind them. Capped rather than set, so a
	guardian that was already slower stays slower - the cap can only ever make
	the chase easier, never harder.
]]
function TutorialConfig.ChaseSpeedCap(data, thiefSpeed: number): number?
	if not TutorialConfig.IsActive(data) then
		return nil
	end
	if TutorialConfig.StepOf(data) > 6 then
		return nil
	end
	return thiefSpeed * TutorialConfig.ChaseSpeedFraction
end

--[[
	Beat 11's top-up. Returns how many Fossils to add so the highlighted upgrade
	is exactly affordable, or 0.

	Only ever positive: a player who is already rich enough is not topped up,
	and nobody is ever taken DOWN to the price.
]]
function TutorialConfig.TopUpFor(data, cost: number): number
	if not TutorialConfig.TopUpToUpgrade or not TutorialConfig.IsActive(data) then
		return 0
	end
	if TutorialConfig.StepOf(data) < 10 then
		return 0
	end
	return math.max(0, cost - ((data and data.Fossils) or 0))
end

--[[
	Whether a step may advance, given what the player has actually done.

	`facts` is a table the server fills from real state - carrying, chased,
	home, and so on. The client never supplies it, which is the whole point:
	`RequestTutorialStep` carries a step number and nothing else, and the number
	is checked against this.
]]
function TutorialConfig.CanAdvance(data, toStep: number, facts): (boolean, string?)
	local state = data and data.Tutorial
	if not state then
		return false, "no tutorial state"
	end
	if state.Completed then
		return false, "already finished"
	end
	if state.SkippedAt ~= nil then
		return false, "skipped"
	end

	-- Exactly one forward. Not "at least": a client that could jump would skip
	-- straight to the completion grant.
	if toStep ~= state.Step + 1 then
		return false, "not the next step"
	end
	if toStep > TutorialConfig.StepCount then
		return false, "past the end"
	end

	--[[
		The condition belongs to the step being LEFT, not the one being
		entered: advancing from beat 4 means the egg has been taken.
	]]
	local leaving = beats[state.Step]
	local requirement = leaving and leaving.Requires or "none"
	if requirement == "none" then
		return true, nil
	end
	if not facts or facts[requirement] ~= true then
		return false, "requirement not met: " .. requirement
	end
	return true, nil
end

--[[
	Every requirement a beat names must be one the server actually reports, or
	that beat can never be advanced past and the tutorial deadlocks at it - the
	same coverage discipline the replication allowlist and RebirthConfig's three
	lists use. `TutorialService.ValidateFacts` calls this at boot with the keys
	it knows how to compute.
]]
function TutorialConfig.ValidateRequirements(known: { [string]: boolean }): (boolean, string?)
	for _, entry in beats do
		local requirement = entry.Requires
		if requirement ~= "none" and not known[requirement] then
			return false, string.format(
				"beat %d (%s) requires '%s', which nothing computes - the tutorial would "
					.. "deadlock there", entry.Step, entry.Id, requirement)
		end
	end
	return true, nil
end

do
	assert(#beats == 12, "docs/00 §3 describes twelve beats, found " .. #beats)
	assert(TutorialConfig.RokLeavesAfterStep < #beats,
		"Rok must leave before the last beat, or docs/00's farewell has nobody in it")

	local seen = {}
	for _, entry in beats do
		assert(not seen[entry.Id], "duplicate beat id: " .. entry.Id)
		seen[entry.Id] = true
	end

	assert(TutorialConfig.HintAfterSecs < TutorialConfig.AutoAdvanceAfterSecs,
		"the hint has to arrive before the auto-advance, or it never shows at all")

	-- docs/00 §3: "Total forced reading: under 60 words."
	local total = 0
	for _, entry in beats do
		total += select(2, entry.Text:gsub("%S+", ""))
	end
	TutorialConfig.TotalWords = total
	assert(total < 60, ("the FTUE reads %d words; docs/00 §3 allows under 60"):format(total))
end

return TutorialConfig
