--!strict
--[[
	ZoneConfig
	ReplicatedStorage/SAD_Shared/Config/ZoneConfig  (ModuleScript)

	The four V1 zones. Mirrors docs/02-zones-and-map.md.

	Note there is NO SpeciesPool here. docs/11 originally specified one on both
	this table and DinoConfig; two tables describing the same relationship drift
	apart the first time someone adds a dinosaur in a hurry. DinoConfig.Zones is
	authoritative and DinoConfig.BuildZoneIndex() derives the pools.

	Nest positions are not here either - they are parts tagged SAD_NestAnchor in
	the world model, read via CollectionService at boot (Step 7). A builder can
	move a nest in Studio without touching code. NestCount below is the EXPECTED
	count, which ConfigValidator compares against reality once the world exists.

	Depends on: nothing.
]]

local ZoneConfig = {}

ZoneConfig.Order = { "plains", "canyon", "swamp", "frozen" }

export type Zone = {
	Id: string,
	DisplayName: string,
	Order: number,
	Color: string,
	Unlock: { Fossils: number, Rebirths: number, IndexPercent: number, OwnRarity: string? },
	NestCount: number,
	EggsPerNest: number,
	RespawnSecs: number,
	GuardiansPerNest: { min: number, max: number },
	LuckBonus: number,
	Hazards: { string },
	WorldModel: string,
	Tagline: string,
}

ZoneConfig.Zones = {
	plains = {
		Id = "plains", DisplayName = "Jurassic Plains", Order = 1, Color = "7ED957",
		Unlock = { Fossils = 0, Rebirths = 0, IndexPercent = 0, OwnRarity = nil },
		NestCount = 14, EggsPerNest = 3, RespawnSecs = 45,
		GuardiansPerNest = { min = 1, max = 1 },
		LuckBonus = 0.00,
		Hazards = {},
		WorldModel = "Zone01",
		Tagline = "Wide, green, forgiving. Everyone starts here.",
	},
	canyon = {
		Id = "canyon", DisplayName = "Rocky Canyon", Order = 2, Color = "C98A4B",
		Unlock = { Fossils = 5000, Rebirths = 0, IndexPercent = 0, OwnRarity = nil },
		NestCount = 12, EggsPerNest = 3, RespawnSecs = 55,
		GuardiansPerNest = { min = 1, max = 1 },
		LuckBonus = 0.02,
		Hazards = { "falling_rocks", "ledges" },
		WorldModel = "Zone02",
		Tagline = "Narrow ledges. Falling rocks knock the egg loose.",
	},
	swamp = {
		Id = "swamp", DisplayName = "Swamp Lands", Order = 3, Color = "4C7A5A",
		Unlock = { Fossils = 45000, Rebirths = 0, IndexPercent = 0, OwnRarity = nil },
		NestCount = 12, EggsPerNest = 2, RespawnSecs = 70,
		GuardiansPerNest = { min = 1, max = 2 },
		LuckBonus = 0.04,
		Hazards = { "mud", "water" },
		WorldModel = "Zone03",
		Tagline = "Mud slows you 35%. The bridges are the safe route.",
	},
	frozen = {
		Id = "frozen", DisplayName = "Frozen Valley", Order = 4, Color = "8FD9F5",
		Unlock = { Fossils = 400000, Rebirths = 0, IndexPercent = 0, OwnRarity = nil },
		NestCount = 10, EggsPerNest = 2, RespawnSecs = 85,
		GuardiansPerNest = { min = 1, max = 2 },
		LuckBonus = 0.06,
		Hazards = { "ice", "blizzard_pockets" },
		WorldModel = "Zone04",
		Tagline = "Ice means momentum. Blizzard pockets mean you cannot see.",
	},

	--[[
		V1.1+ zones, with their gates from docs/02 §2.1 preserved:

		volcano   3,500,000     R1              V1.1
		jungle    28,000,000    R2              V1.4
		ruins     220,000,000   R4  index 25%   V1.4
		wasteland 1,800,000,000 R6  index 40%   V1.6
		sky       15e9          R9  index 55%  own a Mythic   V2.0
		titan     140e9         R13 index 70%  own an Ancient V2.0
	]]
}

-- ── Helpers ─────────────────────────────────────────────────────────────────

function ZoneConfig.Get(zoneId: string): Zone?
	return (ZoneConfig.Zones :: any)[zoneId]
end

function ZoneConfig.Count(): number
	return #ZoneConfig.Order
end

--- The zone a player should be pushed toward next, or nil when all V1 zones
--- are open. Used by the HUD's "next goal" chip.
function ZoneConfig.NextLocked(unlocked: { [string]: boolean }): Zone?
	for _, zoneId in ZoneConfig.Order do
		if not unlocked[zoneId] then
			return (ZoneConfig.Zones :: any)[zoneId]
		end
	end
	return nil
end

function ZoneConfig.GetColor(zoneId: string): Color3
	local zone = (ZoneConfig.Zones :: any)[zoneId]
	return Color3.fromHex(if zone then zone.Color else "FFFFFF")
end

return ZoneConfig
