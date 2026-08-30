--!nonstrict
--[[
	Stats
	ReplicatedStorage/SAD_Shared/Modules/Stats  (ModuleScript)

	Every derived player number in one place: what the upgrade tracks, the
	rebirth grants and the base constants add up to.

	docs/13 §Step 13 calls for a "PlayerStats aggregation", and docs/11 §5 says
	each `Effect.Kind` is read into it. Before this module, eleven call sites
	across six files each did their own version of

	    UpgradeConfig.EffectAt(track, data.Upgrades[track] or 0)

	and the ones that also had a rebirth grant or a cap folded it in locally.
	That is eleven places to forget the cap the twelfth time, and the failure is
	silent - a stat that is simply wrong, in one system only.

	Everything here is PURE: profile in, numbers out. That matters twice over.
	The server reads it for every gameplay decision, and the shop reads it on
	the CLIENT to draw "now -> next", which has to be the number the player
	actually gets or the shop is lying.

	═══ ADDING A STAT ══════════════════════════════════════════════════════════
	One entry in `Stats.Of` and one line in the Kind table below. If a track's
	Effect.Kind has no case here, `Stats.AssertComplete()` fails at boot rather
	than the stat silently reading as its base value forever.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: GameConfig, UpgradeConfig, RebirthConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local GameConfig = require(Shared.Config.GameConfig)
local DailyConfig = require(Shared.Config.DailyConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)

local Stats = {}

--[[
	Which stat field each Effect.Kind lands in. Purely documentation for
	humans and a completeness check for `AssertComplete` - the actual folding
	happens in `Of`, because several stats combine a track with a rebirth
	grant or a cap and a generic loop could not express that.
]]
Stats.KindToField = {
	dinoSlots = "DinoSlots",
	dinoStorage = "DinoStorage",
	incubators = "Incubators",
	incubationMult = "IncubationMult",
	mutLuck = "MutLuck",
	parkIncomeMult = "ParkIncomeMult",
	bankSecs = "BankSecs",
	luck = "Luck",
	moveSpeedMult = "MoveSpeedMult",
	carryPenaltyMult = "CarryPenaltyMult",
	eggCapacity = "EggCapacity",
	stealHoldBonus = "StealHoldBonus",
	towerCooldown = "TowerCooldown",
	alertRange = "AlertRange",
}

--[[
	docs/04 §2 caps MutLuck at 4.0 and that is the whole story, so it lives
	here. Luck is different: docs/01 §2 caps it at 5.0 AFTER the zone bonus is
	added, and the zone is not part of the profile. So Luck below is the
	player-derived part only, uncapped, and `EggService.LuckFrom` applies the
	one documented clamp once the zone is known. Capping twice would silently
	nerf a player standing in a high-luck zone.
]]
Stats.MaxMutLuck = 4.0

--[[
	`UpgradeConfig.LevelIn` and not `data.Upgrades[trackId]`, because docs/10 §1
	puts the three defence tracks in `data.Defences` instead. Reading the wrong
	table returns 0 and nothing throws, so a bought Fence would simply never
	apply - which is the exact shape of bug this module exists to remove.
]]
local function effect(data, trackId: string): number
	return UpgradeConfig.EffectAt(trackId, UpgradeConfig.LevelIn(data, trackId))
end

--[[
	The total from every ACTIVE boost of one kind (docs/05 §7's Luck Potion and
	Mutation Serum).

	`data.Boosts[id]` is an expiry timestamp, so an expired boost contributes
	nothing without needing to be cleaned up first - which matters, because the
	client computes stats too and cannot write to the profile. Sweeping expired
	entries is bookkeeping, done on save; correctness does not depend on it.

	`now` is injectable so the spec can watch one expire rather than waiting.
]]
local function boostTotal(data, kind: string, now: number?): number
	local boosts = data and data.Boosts
	if not boosts then
		return 0
	end

	local at = now or os.time()
	local total = 0
	for boostId, expiry in boosts do
		if expiry > at then
			local definition = DailyConfig.GetBoost(boostId)
			if definition and definition.Kind == kind then
				total += definition.Amount
			end
		end
	end
	return total
end

Stats.BoostTotal = boostTotal

--[[
	The whole derived stat block for a profile.

	Allocates a table per call, which is fine everywhere it is used today
	(purchases, hatches, pickups - never a per-frame path). Callers on a hot
	path should read the single field they need through the helpers below
	instead, which is what the existing service APIs do.
]]
function Stats.Of(data)
	local rebirths = (data and data.Rebirths) or 0

	return {
		-- Park
		DinoSlots = effect(data, "dinoSlots") + RebirthConfig.BonusDinoSlots(rebirths)
			+ ((data and data.BonusDinoSlots) or 0),
		DinoStorage = effect(data, "dinoStorage"),
		Incubators = effect(data, "incubators"),
		IncubationMult = effect(data, "incubatorSpeed"),
		ParkIncomeMult = effect(data, "feedingTrough"),
		BankSecs = effect(data, "bankSize"),

		-- Explorer
		Luck = Stats.Luck(data),
		MutLuck = Stats.MutLuck(data),
		MoveSpeedMult = effect(data, "runnersLegs") * (1 + RebirthConfig.MoveSpeedBonus(rebirths)),
		CarryPenaltyMult = effect(data, "strongBack"),
		EggCapacity = effect(data, "eggPouch"),

		-- Defence
		StealHoldBonus = effect(data, "fence"),
		TowerCooldown = effect(data, "guardTower"),
		AlertRange = effect(data, "camera"),

		--[[
			Not a track: the aggregate docs/03 §5 defines as
			"sum of all defence levels / 4, capped at 5", which docs/03 §4.2
			feeds into the raid hold time. Derived here so the three tracks
			above and the number they add up to cannot disagree.
		]]
		SecurityLevel = Stats.SecurityLevel(data),
		RaidHoldSecs = Stats.RaidHoldSecs(data),
	}
end

-- ── Single-field helpers ────────────────────────────────────────────────────
-- Named so a caller reading one stat does not allocate the whole block. Each
-- one is the SAME expression as its line in `Of` - the spec asserts that,
-- because two drifting copies is exactly what this module exists to prevent.

function Stats.DinoSlots(data): number
	return effect(data, "dinoSlots")
		+ RebirthConfig.BonusDinoSlots((data and data.Rebirths) or 0)
		+ ((data and data.BonusDinoSlots) or 0)
end

function Stats.DinoStorage(data): number
	return effect(data, "dinoStorage")
end

function Stats.Incubators(data): number
	return effect(data, "incubators")
end

function Stats.IncubationMult(data): number
	return effect(data, "incubatorSpeed")
end

function Stats.ParkIncomeMult(data): number
	return effect(data, "feedingTrough")
end

function Stats.BankSecs(data): number
	return effect(data, "bankSize")
end

--- The player-derived part of luck. Uncapped on purpose - see the note above
--- Stats.MaxMutLuck. `EggService.LuckFrom` adds the zone bonus and clamps to 5.0.
function Stats.Luck(data, now: number?): number
	local rebirths = (data and data.Rebirths) or 0
	return effect(data, "eggSense")
		+ RebirthConfig.LuckBonus(rebirths)
		+ ((data and data.LuckNodes) or 0) * GameConfig.LuckPerNode
		+ boostTotal(data, "luck", now)
end

function Stats.MutLuck(data, now: number?): number
	local rebirths = (data and data.Rebirths) or 0
	return math.clamp(
		effect(data, "incubatorGenetics")
			+ RebirthConfig.MutLuckBonus(rebirths)
			+ boostTotal(data, "mutLuck", now),
		0, Stats.MaxMutLuck)
end

function Stats.MoveSpeedMult(data): number
	return effect(data, "runnersLegs") * (1 + RebirthConfig.MoveSpeedBonus((data and data.Rebirths) or 0))
end

function Stats.CarryPenaltyMult(data): number
	return effect(data, "strongBack")
end

function Stats.EggCapacity(data): number
	return effect(data, "eggPouch")
end

function Stats.StealHoldBonus(data): number
	return effect(data, "fence")
end

function Stats.TowerCooldown(data): number
	return effect(data, "guardTower")
end

function Stats.AlertRange(data): number
	return effect(data, "camera")
end

--[[
	docs/03 §5: "SecurityLevel = sum of all defence levels / 4, capped at 5".

	Summed from the DEFENCE BOARD rather than from a hardcoded list of three
	track ids, so the V1.4 pass that adds Alarm Horn and Electric Fence raises
	it without touching this function - which is also why V1's ceiling is 3.75
	rather than 5, with only fifteen defence levels in the game to sum.
]]
function Stats.SecurityLevel(data): number
	local total = 0
	for _, entry in UpgradeConfig.ForBoard("defence") do
		total += UpgradeConfig.LevelIn(data, entry.Id)
	end
	return math.min(total / 4, 5)
end

--- Seconds a raider must hold to lift a dinosaur from this park (docs/03 §4.2).
function Stats.RaidHoldSecs(data): number
	return GameConfig.RaidHoldBase + Stats.SecurityLevel(data) * GameConfig.RaidHoldPerSecurity
end

--[[
	Every track's Effect.Kind must map to a field, and every field must exist
	in a freshly computed block. Called by ConfigValidator at boot: a track
	added without a handler here would otherwise ship as an upgrade the player
	can buy that does nothing at all, and nothing throws.
]]
function Stats.AssertComplete(): (boolean, string?)
	local sample = Stats.Of(nil)

	for trackId, entry in UpgradeConfig.Tracks do
		local field = Stats.KindToField[entry.Effect.Kind]
		if not field then
			return false, string.format("upgrade track '%s' has Effect.Kind '%s' with no field in Stats.KindToField",
				trackId, tostring(entry.Effect.Kind))
		end
		if sample[field] == nil then
			return false, string.format("Effect.Kind '%s' maps to field '%s', which Stats.Of does not produce",
				entry.Effect.Kind, field)
		end
	end

	for kind, field in Stats.KindToField do
		if sample[field] == nil then
			return false, string.format("Stats.KindToField lists '%s' -> '%s', which Stats.Of does not produce",
				kind, field)
		end
	end

	return true
end

return Stats
