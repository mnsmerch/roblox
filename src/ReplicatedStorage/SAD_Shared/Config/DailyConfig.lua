--!nonstrict
--[[
	DailyConfig
	ReplicatedStorage/SAD_Shared/Config/DailyConfig  (ModuleScript)

	The 7-day chest and the streak table from docs/05 §7.

	═══ REWARDS SCALE WITH THE PLAYER ══════════════════════════════════════════
	docs/05 §7: "Fossil rewards scale with player power (R = rebirth count) so
	they stay relevant: dailyFossils = base x (1 + 0.9 x R)."

	Without it, day 7's 500,000 Fossils is a fortune on day one and a rounding
	error by rebirth 4 - and a daily reward nobody bothers collecting is a
	retention feature that has quietly stopped working.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local DailyConfig = {}

--- docs/05 §7's scaling term.
DailyConfig.RebirthScale = 0.9

--- The cycle resets on a missed day; the streak bonus does not (docs/05 §7).
DailyConfig.CycleLength = 7

--[[
	Rewards are declared, not granted. Each is a plain table that DailyService
	hands to one grant function, so "what does day 5 give" is answerable by
	reading this file and nothing else.

	Fields, all optional:
		Fossils  scaled by (1 + 0.9 x rebirths)
		Dna      flat - DNA is the depth currency and does not inflate (docs/05 §1)
		Egg      a rarity id, granted straight into storage
		Boost    { Id, Secs }
		Shield   seconds of park shield
		Item     { Id, Count }
]]
DailyConfig.Days = {
	{ Day = 1, Fossils = 2500 },
	{ Day = 2, Fossils = 6000, Boost = { Id = "luckPotion", Secs = 900 } },
	{ Day = 3, Fossils = 15000, Dna = 25 },
	{ Day = 4, Fossils = 40000, Boost = { Id = "mutationSerum", Secs = 600 } },
	{ Day = 5, Fossils = 100000, Egg = "rare", Shield = 600 },
	{ Day = 6, Fossils = 250000, Dna = 75, Item = { Id = "instantHatch", Count = 1 } },
	{ Day = 7, Fossils = 500000, Dna = 150, Egg = "epic",
		Boost = { Id = "luckPotion", Secs = 1800 } },
}

--[[
	Streak milestones (docs/05 §7). The two content rewards - a Compsognathus
	skin at 60 and a Mythic Triceratops at 100 - need art and a Mythic species,
	neither of which V1 has, so those days grant their title and DNA and the
	content arrives with the content.
]]
DailyConfig.StreakRewards = {
	{ Days = 7, Title = "Regular", Dna = 100 },
	{ Days = 14, Title = "Devoted", Dna = 300 },
	{ Days = 30, Title = "Keeper", Dna = 800, VaultSlots = 1 },
	{ Days = 60, Title = "Amberling", Dna = 2000 }, -- + skin, V1.2
	{ Days = 100, Title = "Fossilkeeper", Dna = 6000 }, -- + Mythic Trike, V1.3
}

--- Boost definitions, so a granted boost is a real effect rather than a key.
--- Read by Stats; `Kind` names which stat it adds to.
DailyConfig.Boosts = {
	luckPotion = { Id = "luckPotion", DisplayName = "Luck Potion", Kind = "luck", Amount = 1.0 },
	mutationSerum = { Id = "mutationSerum", DisplayName = "Mutation Serum",
		Kind = "mutLuck", Amount = 1.5 },
}

-- ── Helpers ─────────────────────────────────────────────────────────────────

--- docs/05 §7: `base x (1 + 0.9 x R)`. Applied to Fossils only.
function DailyConfig.ScaleFossils(base: number, rebirths: number): number
	return math.floor(base * (1 + DailyConfig.RebirthScale * (rebirths or 0)))
end

--[[
	The reward for a given position in the cycle. 1-indexed and wrapping, so a
	player on day 9 of a streak is on cycle day 2 - the chest repeats, the
	streak does not.
]]
function DailyConfig.RewardFor(dayIndex: number)
	if dayIndex < 1 then
		return nil
	end
	local position = ((dayIndex - 1) % DailyConfig.CycleLength) + 1
	return DailyConfig.Days[position]
end

--- The streak reward crossed by reaching exactly `streak` days, if any.
function DailyConfig.StreakRewardAt(streak: number)
	for _, reward in DailyConfig.StreakRewards do
		if reward.Days == streak then
			return reward
		end
	end
	return nil
end

function DailyConfig.GetBoost(boostId: string)
	return DailyConfig.Boosts[boostId]
end

return DailyConfig
