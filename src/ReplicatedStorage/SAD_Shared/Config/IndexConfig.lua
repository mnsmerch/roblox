--!nonstrict
--[[
	IndexConfig
	ReplicatedStorage/SAD_Shared/Config/IndexConfig  (ModuleScript)

	Index milestones and per-rarity completion sets, from docs/05 §7 and
	docs/06 §4.

	═══ THE DENOMINATOR IS EVERY SPECIES THAT EXISTS ═══════════════════════════
	docs/06 §4 defines completion as "discovered species / 60". Sixty is the
	full game; V1 ships 35. So `IndexConfig.Total(dinoConfig)` counts what is
	actually in DinoConfig rather than hardcoding a number, and the milestones
	above that count are simply unreachable until the species ship.

	That direction matters. A hardcoded 60 would make a V1 player's completion
	read 58% when they have found everything there is - which is worse than
	unreachable milestones, because it is wrong rather than merely pending.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing. Takes DinoConfig as an argument where it needs it, the
	same way ZoneConfig.UnlockCheck does.
]]

local IndexConfig = {}

--[[
	docs/05 §7's milestone table. `Id` is what is written into
	`Profile.IndexMilestones`, so renaming one re-grants it - which is why they
	are named after the count rather than numbered.
]]
IndexConfig.Milestones = {
	{ Id = "discover10", Count = 10, LuckNodes = 1, Dna = 50 },
	{ Id = "discover20", Count = 20, LuckNodes = 1, Dna = 150, Egg = "epic" },
	{ Id = "discover30", Count = 30, LuckNodes = 1, Dna = 400, DinoSlots = 1 },
	{ Id = "discover40", Count = 40, LuckNodes = 1, Dna = 1000, Egg = "legendary" },
	{ Id = "discover50", Count = 50, LuckNodes = 1, Dna = 2500, VaultSlots = 1 },
	{ Id = "discover60", Count = 60, LuckNodes = 1, Dna = 10000, Title = "Curator" },
	-- The Curator's Fossilborn Rex is an Ancient species; it arrives in V1.6
	-- with the rest of them.
}

--[[
	docs/05 §7: "Per-rarity completion sets grant a further +2 % Luck each
	(9 sets -> +18 %)." One node is +1 %, so a set is worth two.
]]
IndexConfig.SetLuckNodes = 2

-- ── Helpers ─────────────────────────────────────────────────────────────────

--- How many species exist to be found. Counted, never hardcoded - see above.
function IndexConfig.Total(dinoConfig): number
	local count = 0
	for _ in dinoConfig.Species do
		count += 1
	end
	return count
end

function IndexConfig.Discovered(data): number
	local count = 0
	for _ in data.Index do
		count += 1
	end
	return count
end

--- Completion as a percentage of what exists, not of what is planned.
function IndexConfig.CompletionPercent(data, dinoConfig): number
	local total = IndexConfig.Total(dinoConfig)
	if total <= 0 then
		return 0
	end
	return IndexConfig.Discovered(data) / total * 100
end

--- Milestones reached at `discovered` and not yet claimed.
function IndexConfig.PendingMilestones(data)
	local discovered = IndexConfig.Discovered(data)
	local pending = {}
	for _, milestone in IndexConfig.Milestones do
		if discovered >= milestone.Count and not data.IndexMilestones[milestone.Id] then
			table.insert(pending, milestone)
		end
	end
	return pending
end

--[[
	The rarity sets a player has completed but not been paid for. A set is
	every species of one rarity that exists - so in V1 the Mythic and Ancient
	sets are empty, and an empty set is NOT complete: paying for finding
	nothing would be the same bug as a 60-species denominator, in reverse.
]]
function IndexConfig.PendingSets(data, dinoConfig)
	local byRarity = {}
	for id, species in dinoConfig.Species do
		local bucket = byRarity[species.Rarity]
		if not bucket then
			bucket = { Total = 0, Found = 0 }
			byRarity[species.Rarity] = bucket
		end
		bucket.Total += 1
		if data.Index[id] then
			bucket.Found += 1
		end
	end

	local pending = {}
	for rarity, bucket in byRarity do
		local milestoneId = "set_" .. rarity
		if bucket.Total > 0 and bucket.Found >= bucket.Total
			and not data.IndexMilestones[milestoneId] then
			table.insert(pending, { Id = milestoneId, Rarity = rarity,
				LuckNodes = IndexConfig.SetLuckNodes })
		end
	end

	table.sort(pending, function(a, b)
		return a.Id < b.Id
	end)
	return pending
end

return IndexConfig
