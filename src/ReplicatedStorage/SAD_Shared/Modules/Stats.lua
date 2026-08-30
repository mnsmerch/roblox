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
		DinoSlots = effect(data, "dinoSlots") + RebirthConfig.BonusDinoSlots(rebirths),
		DinoStorage = effect(data, "dinoStorage"),
		Incubators = effect(data, "incubators"),
		IncubationMult = effect(data, "incubatorSpeed"),
		ParkIncomeMult = effect(data, "feedingTrough"),
		BankSecs = effect(data, "bankSize"),

		-- Explorer
		Luck = effect(data, "eggSense")
			+ RebirthConfig.LuckBonus(rebirths)
			+ ((data and data.LuckNodes) or 0) * GameConfig.LuckPerNode,
		MutLuck = math.clamp(
			effect(data, "incubatorGenetics") + RebirthConfig.MutLuckBonus(rebirths),
			0, Stats.MaxMutLuck),
		MoveSpeedMult = effect(data, "runnersLegs") * (1 + RebirthConfig.MoveSpeedBonus(rebirths)),
		CarryPenaltyMult = effect(data, "strongBack"),
		EggCapacity = effect(data, "eggPouch"),

		-- Defence (read by StealService in Step 15)
		StealHoldBonus = effect(data, "fence"),
		TowerCooldown = effect(data, "guardTower"),
		AlertRange = effect(data, "camera"),
	}
end

-- ── Single-field helpers ────────────────────────────────────────────────────
-- Named so a caller reading one stat does not allocate the whole block. Each
-- one is the SAME expression as its line in `Of` - the spec asserts that,
-- because two drifting copies is exactly what this module exists to prevent.

function Stats.DinoSlots(data): number
	return effect(data, "dinoSlots") + RebirthConfig.BonusDinoSlots((data and data.Rebirths) or 0)
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
function Stats.Luck(data): number
	local rebirths = (data and data.Rebirths) or 0
	return effect(data, "eggSense")
		+ RebirthConfig.LuckBonus(rebirths)
		+ ((data and data.LuckNodes) or 0) * GameConfig.LuckPerNode
end

function Stats.MutLuck(data): number
	local rebirths = (data and data.Rebirths) or 0
	return math.clamp(effect(data, "incubatorGenetics") + RebirthConfig.MutLuckBonus(rebirths),
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
