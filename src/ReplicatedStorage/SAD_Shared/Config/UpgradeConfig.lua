--!nonstrict
--[[
	UpgradeConfig
	ReplicatedStorage/SAD_Shared/Config/UpgradeConfig  (ModuleScript)

	The 11 upgrade tracks and 3 defence tracks shipping in V1. Mirrors
	docs/05-economy.md §5.

	Every cost is cost(n) = BaseCost * Growth^(n-1), rounded to 3 significant
	figures so shop prices read cleanly ("12.3K", never "12,347"). Rounding
	happens HERE and on the server only - a client that computes its own price
	and disagrees with the server produces a purchase that silently fails.

	Effect.Kind is the contract with UpgradeService: each Kind has exactly one
	handler that folds levels into a computed PlayerStats table which every
	other service reads. Adding a track with a new Kind means adding one handler
	in one place.

	Depends on: nothing.
]]

local UpgradeConfig = {}

--- Which shop board a track appears on (docs/06 §5).
UpgradeConfig.Boards = { "park", "explorer", "defence" }

--[[
	Rounds to `digits` significant figures. 1719.4 -> 1720, 27834 -> 27800.
	Costs stay recognisable as they grow instead of turning into noise.
]]
function UpgradeConfig.RoundSignificant(value: number, digits: number?): number
	if value <= 0 then
		return 0
	end
	local places = digits or 3
	local magnitude = math.floor(math.log(value, 10)) - (places - 1)
	local scale = 10 ^ magnitude
	if scale < 1 then
		return math.floor(value + 0.5)
	end
	return math.floor(value / scale + 0.5) * scale
end

local tracks = {}

local function track(entry)
	entry.Currency = entry.Currency or "Fossils"
	entry.Board = entry.Board or "park"
	assert(tracks[entry.Id] == nil, "duplicate upgrade track: " .. entry.Id)
	tracks[entry.Id] = entry
	return entry
end

-- ═══ PARK BOARD ════════════════════════════════════════════════════════════

track({ Id = "dinoSlots", DisplayName = "Dinosaur Slots", Board = "park",
	MaxLevel = 26, BaseCost = 800, Growth = 1.72,
	Effect = { Kind = "dinoSlots", Base = 4, PerLevel = 1 },
	Blurb = "Room for one more dinosaur in the park." })

track({ Id = "incubators", DisplayName = "Incubators", Board = "park",
	MaxLevel = 6, BaseCost = 3500, Growth = 2.55,
	Effect = { Kind = "incubators", Base = 2, PerLevel = 1 },
	Blurb = "Hatch more eggs at the same time." })

track({ Id = "incubatorSpeed", DisplayName = "Incubator Speed", Board = "park",
	MaxLevel = 15, BaseCost = 1200, Growth = 1.61,
	Effect = { Kind = "incubationMult", Base = 1.0, PerLevel = -0.04 },
	Blurb = "Eggs hatch faster." })

track({ Id = "incubatorGenetics", DisplayName = "Incubator Genetics", Board = "park",
	MaxLevel = 15, BaseCost = 6000, Growth = 1.78,
	Effect = { Kind = "mutLuck", Base = 0, PerLevel = 0.0533333 },
	Blurb = "Better odds of a mutation when an egg hatches." })

track({ Id = "feedingTrough", DisplayName = "Feeding Trough", Board = "park",
	MaxLevel = 20, BaseCost = 2000, Growth = 1.66,
	Effect = { Kind = "parkIncomeMult", Base = 1.0, PerLevel = 0.08 },
	Blurb = "Every dinosaur in the park earns more." })

track({ Id = "bankSize", DisplayName = "Bank Size", Board = "park",
	MaxLevel = 10, BaseCost = 3000, Growth = 1.75,
	Effect = { Kind = "bankSecs", Base = 60, PerLevel = 30 },
	Blurb = "Hold more uncollected Fossils before the bank fills." })

track({ Id = "dinoStorage", DisplayName = "Dinosaur Storage", Board = "park",
	MaxLevel = 12, BaseCost = 4500, Growth = 1.80,
	Effect = { Kind = "dinoStorage", Base = 25, PerLevel = 15 },
	Blurb = "Keep more dinosaurs outside the park." })

-- ═══ EXPLORER BOARD ════════════════════════════════════════════════════════

track({ Id = "eggSense", DisplayName = "Egg Sense", Board = "explorer",
	MaxLevel = 15, BaseCost = 4000, Growth = 1.83,
	Effect = { Kind = "luck", Base = 0, PerLevel = 0.05 },
	Blurb = "Better odds of a rare egg." })

track({ Id = "runnersLegs", DisplayName = "Runner's Legs", Board = "explorer",
	MaxLevel = 12, BaseCost = 1500, Growth = 1.90,
	Effect = { Kind = "moveSpeedMult", Base = 1.0, PerLevel = 0.02 },
	Blurb = "Run faster. Everywhere." })

track({ Id = "strongBack", DisplayName = "Strong Back", Board = "explorer",
	MaxLevel = 10, BaseCost = 5000, Growth = 1.95,
	Effect = { Kind = "carryPenaltyMult", Base = 1.0, PerLevel = -0.06 },
	Blurb = "Heavy eggs slow you down less." })

track({ Id = "eggPouch", DisplayName = "Egg Pouch", Board = "explorer",
	MaxLevel = 4, BaseCost = 9000, Growth = 3.40,
	Effect = { Kind = "eggCapacity", Base = 1, PerLevel = 1 },
	Blurb = "Carry another egg at once." })

-- ═══ DEFENCE BOARD ═════════════════════════════════════════════════════════

track({ Id = "fence", DisplayName = "Fence", Board = "defence",
	MaxLevel = 5, BaseCost = 15000, Growth = 2.80,
	Effect = { Kind = "stealHoldBonus", Base = 0, PerLevel = 1.0 },
	Blurb = "Thieves take longer to get away." })

track({ Id = "guardTower", DisplayName = "Guard Tower", Board = "defence",
	MaxLevel = 5, BaseCost = 60000, Growth = 3.10,
	Effect = { Kind = "towerCooldown", Base = 25, PerLevel = -4 },
	Blurb = "Automatically tags a thief carrying your dinosaur." })

track({ Id = "camera", DisplayName = "Security Camera", Board = "defence",
	MaxLevel = 5, BaseCost = 40000, Growth = 2.90,
	Effect = { Kind = "alertRange", Base = 60, PerLevel = 60 },
	Blurb = "See intruders coming from further away." })

--[[
	V1.4 defence tracks, gates preserved from docs/03 §5:
		alarmHorn      3 lv, 120000, 3.60   alerts your friends in-server
		electricFence  3 lv, 400000, 4.20   -10% thief speed per level
]]

UpgradeConfig.Tracks = tracks

-- ── Helpers ─────────────────────────────────────────────────────────────────

function UpgradeConfig.Get(trackId: string)
	return tracks[trackId]
end

--- Cost of buying level `level` (1-indexed). 0 for an invalid level, which
--- callers must treat as "not purchasable" rather than "free".
function UpgradeConfig.CostOf(trackId: string, level: number): number
	local entry = tracks[trackId]
	if not entry or level < 1 or level > entry.MaxLevel then
		return 0
	end
	return UpgradeConfig.RoundSignificant(entry.BaseCost * entry.Growth ^ (level - 1))
end

--- Total to go from `fromLevel` to `toLevel`. Used by Buy Max, which the
--- server evaluates in one transaction.
function UpgradeConfig.CostRange(trackId: string, fromLevel: number, toLevel: number): number
	local total = 0
	for level = fromLevel + 1, toLevel do
		total += UpgradeConfig.CostOf(trackId, level)
	end
	return total
end

--- The track's effect value at `level`. Linear in level by design: every
--- effect in V1 is Base + PerLevel * level, which keeps the shop's
--- "now -> next" preview honest and trivial to render.
function UpgradeConfig.EffectAt(trackId: string, level: number): number
	local entry = tracks[trackId]
	if not entry then
		return 0
	end
	local clamped = math.clamp(level, 0, entry.MaxLevel)
	return entry.Effect.Base + entry.Effect.PerLevel * clamped
end

function UpgradeConfig.MaxEffect(trackId: string): number
	local entry = tracks[trackId]
	if not entry then
		return 0
	end
	return UpgradeConfig.EffectAt(trackId, entry.MaxLevel)
end

function UpgradeConfig.ForBoard(board: string)
	local list = {}
	for _, entry in tracks do
		if entry.Board == board then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	return list
end

function UpgradeConfig.Count(): number
	local count = 0
	for _ in tracks do
		count += 1
	end
	return count
end

return UpgradeConfig
