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

-- ── Ring geometry ───────────────────────────────────────────────────────────

--[[
	Ten slots are reserved even though V1 fills four, so zones 5-10 drop into
	their eventual positions without moving anything a player has learned.
	Landmarks and routes stay put across updates.

	Slot 1 sits on +X and they run anticlockwise in zone order, so a player
	physically walks further around the ring as they progress (docs/02 §1).
]]
ZoneConfig.SlotCount = 10
ZoneConfig.ZoneSize = 350

--[[
	Derived clearance, not a chosen number. Parks occupy 573 +/- 60, so their
	outer edge is 633; a zone's inner edge is RingRadius - ZoneSize/2. At 950
	that leaves a 142-stud walk between the park ring and the nearest zone,
	which is the "zone entrances are close" feel from the FTUE.
]]
ZoneConfig.RingRadius = 950

ZoneConfig.HubRadius = 520
ZoneConfig.GroundThickness = 4
ZoneConfig.GateHeight = 150 -- docs/02 §1.2: visible from across the map
ZoneConfig.RoadWidth = 40

export type Zone = {
	Id: string,
	DisplayName: string,
	Order: number,
	Color: string,
	RingSlot: number,
	Unlock: { Fossils: number, Rebirths: number, IndexPercent: number, OwnRarity: string? },
	NestCount: number,
	EggsPerNest: number,
	RespawnSecs: number,
	GuardiansPerNest: { min: number, max: number },
	LuckBonus: number,
	GuardianSpeedBonus: number,
	Hazards: { string },
	WorldModel: string,
	Tagline: string,
}

ZoneConfig.Zones = {
	plains = {
		Id = "plains", RingSlot = 1, DisplayName = "Jurassic Plains", Order = 1, Color = "7ED957",
		Unlock = { Fossils = 0, Rebirths = 0, IndexPercent = 0, OwnRarity = nil },
		NestCount = 14, EggsPerNest = 3, RespawnSecs = 45,
		GuardiansPerNest = { min = 1, max = 1 },
		LuckBonus = 0.00,
		-- starter zone: guardians are outrun by anyone who keeps running
		GuardianSpeedBonus = 0.00,
		Hazards = {},
		WorldModel = "Zone01",
		Tagline = "Wide, green, forgiving. Everyone starts here.",
	},
	canyon = {
		Id = "canyon", RingSlot = 2, DisplayName = "Rocky Canyon", Order = 2, Color = "C98A4B",
		Unlock = { Fossils = 5000, Rebirths = 0, IndexPercent = 0, OwnRarity = nil },
		NestCount = 12, EggsPerNest = 3, RespawnSecs = 55,
		GuardiansPerNest = { min = 1, max = 1 },
		LuckBonus = 0.02,
		GuardianSpeedBonus = 0.04,
		Hazards = { "falling_rocks", "ledges" },
		WorldModel = "Zone02",
		Tagline = "Narrow ledges. Falling rocks knock the egg loose.",
	},
	swamp = {
		Id = "swamp", RingSlot = 3, DisplayName = "Swamp Lands", Order = 3, Color = "4C7A5A",
		Unlock = { Fossils = 45000, Rebirths = 0, IndexPercent = 0, OwnRarity = nil },
		NestCount = 12, EggsPerNest = 2, RespawnSecs = 70,
		GuardiansPerNest = { min = 1, max = 2 },
		LuckBonus = 0.04,
		GuardianSpeedBonus = 0.08,
		Hazards = { "mud", "water" },
		WorldModel = "Zone03",
		Tagline = "Mud slows you 35%. The bridges are the safe route.",
	},
	frozen = {
		Id = "frozen", RingSlot = 4, DisplayName = "Frozen Valley", Order = 4, Color = "8FD9F5",
		Unlock = { Fossils = 400000, Rebirths = 0, IndexPercent = 0, OwnRarity = nil },
		NestCount = 10, EggsPerNest = 2, RespawnSecs = 85,
		GuardiansPerNest = { min = 1, max = 2 },
		LuckBonus = 0.06,
		-- V1 end game: a sprinter here genuinely runs you down
		GuardianSpeedBonus = 0.12,
		Hazards = { "ice", "blizzard_pockets" },
		WorldModel = "Zone04",
		Tagline = "Ice means momentum. Blizzard pockets mean you cannot see.",
	},

	--[[
		V1.1+ zones, with their gates from docs/02 §2.1 preserved:

		slot 5   volcano   3,500,000     R1              V1.1
		slot 6   jungle    28,000,000    R2              V1.4
		slot 7   ruins     220,000,000   R4  index 25%   V1.4
		slot 8   wasteland 1,800,000,000 R6  index 40%   V1.6
		slot 9   sky       15e9          R9  index 55%  own a Mythic   V2.0
		slot 10  titan     140e9         R13 index 70%  own an Ancient V2.0
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

--[[
	Zone origin on the ring. Local +Z faces the hub, matching plots exactly.

	CFrame.LookVector is the CFrame's local -Z, so the LookVector aims OUTWARD
	for +Z to point at the hub - the same trap that had every park gate facing
	backwards before it was caught.
]]
function ZoneConfig.OriginOf(zoneId: string): CFrame?
	local zone = (ZoneConfig.Zones :: any)[zoneId]
	if not zone then
		return nil
	end

	local angle = (zone.RingSlot - 1) / ZoneConfig.SlotCount * math.pi * 2
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local position = outward * ZoneConfig.RingRadius

	return CFrame.lookAt(position, position + outward, Vector3.yAxis)
end

--[[
	Nest positions inside a zone, in zone-local space.

	A sunflower (golden-angle) spiral: deterministic, so a nest is in the same
	place every session and players learn the map, and evenly spread without the
	clustering that random scatter produces. No seeds, no tuning, no two nests
	on top of each other.
]]
function ZoneConfig.NestOffsets(zoneId: string): { Vector3 }
	local zone = (ZoneConfig.Zones :: any)[zoneId]
	if not zone then
		return {}
	end

	local count = zone.NestCount
	local usable = ZoneConfig.ZoneSize * 0.40 -- keep clear of the walls
	local goldenAngle = math.pi * (3 - math.sqrt(5))

	local offsets = {}
	for index = 1, count do
		local radius = usable * math.sqrt((index - 0.5) / count)
		local theta = index * goldenAngle
		table.insert(offsets, Vector3.new(math.cos(theta) * radius, 0, math.sin(theta) * radius))
	end
	return offsets
end

--- Smallest gap between any two nests in a zone. Asserted by the spec so a
--- NestCount change cannot quietly stack two nests on each other.
function ZoneConfig.MinNestSeparation(zoneId: string): number
	local offsets = ZoneConfig.NestOffsets(zoneId)
	local smallest = math.huge

	for i = 1, #offsets do
		for j = i + 1, #offsets do
			local delta = offsets[i] - offsets[j]
			local distance = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
			if distance < smallest then
				smallest = distance
			end
		end
	end
	return smallest
end

--- The three rarest tiers a zone can actually roll, for its nest sign. This is
--- the "1 IN 100,000,000" line players screenshot.
function ZoneConfig.HeadlineRarities(zoneId: string, rarityConfig, limit: number?): { string }
	local weights = rarityConfig.ZoneWeights[zoneId]
	if not weights then
		return {}
	end

	local reachable = {}
	for _, rarityId in rarityConfig.Order do
		if (weights[rarityId] or 0) > 0 then
			table.insert(reachable, rarityId)
		end
	end

	local headline = {}
	for index = #reachable, math.max(1, #reachable - (limit or 3) + 1), -1 do
		table.insert(headline, reachable[index])
	end
	return headline
end

--[[
	Whether a profile meets a zone's unlock gate, and what is still missing.

	Returns (ok, reason, requirements) where `requirements` is a list of
	{ Label, Met } - the shop-style breakdown the client renders so a locked
	zone says WHICH gate is short, not just that it is locked.

	Takes its configs as arguments for the same reason HeadlineRarities does:
	this module is dependency-free by design and every config loads it. Shared
	rather than server-only so the zone wheel greys the right entries with the
	real reason - the server re-checks all of it before charging anything.

	docs/02 §2.1. `Fossils` is the only gate that is SPENT; the rest are
	thresholds a player must have reached and keeps afterwards.
]]
function ZoneConfig.UnlockCheck(zoneId: string, data, dinoConfig, rarityConfig)
	local zone = (ZoneConfig.Zones :: any)[zoneId]
	if not zone then
		return false, "no such zone", {}
	end
	if not data then
		return false, "profile not loaded", {}
	end
	if data.ZonesUnlocked and data.ZonesUnlocked[zoneId] then
		return false, "already unlocked", {}
	end

	local gate = zone.Unlock
	local requirements = {}
	local firstMissing = nil

	local function need(met: boolean, label: string, shortfall: string)
		table.insert(requirements, { Label = label, Met = met })
		if not met and not firstMissing then
			firstMissing = shortfall
		end
	end

	need((data.Fossils or 0) >= gate.Fossils,
		string.format("%d Fossils", gate.Fossils), "not enough Fossils")

	if gate.Rebirths > 0 then
		need((data.Rebirths or 0) >= gate.Rebirths,
			string.format("Rebirth %d", gate.Rebirths), "rebirth too low")
	end

	if gate.IndexPercent > 0 then
		--[[
			Index percentage is over every species that EXISTS, not every
			species shipped - otherwise the gate loosens every time content is
			added, and a player who met it once could stop meeting it.
		]]
		local discovered, total = 0, 0
		for _, species in dinoConfig.Species do
			total += 1
			if data.Index and data.Index[species.Id] then
				discovered += 1
			end
		end
		local percent = if total > 0 then discovered / total * 100 else 0
		need(percent >= gate.IndexPercent,
			string.format("Index %d%%", gate.IndexPercent), "index too low")
	end

	if gate.OwnRarity then
		local wanted = rarityConfig.Tiers[gate.OwnRarity]
		local has = false
		if wanted and data.Dinos then
			for _, entry in data.Dinos do
				local tier = rarityConfig.Tiers[entry.Rarity]
				if tier and tier.Rank >= wanted.Rank then
					has = true
					break
				end
			end
		end
		need(has, string.format("own a %s", gate.OwnRarity), "missing a " .. gate.OwnRarity)
	end

	return firstMissing == nil, firstMissing, requirements
end

function ZoneConfig.GetColor(zoneId: string): Color3
	local zone = (ZoneConfig.Zones :: any)[zoneId]
	return Color3.fromHex(if zone then zone.Color else "FFFFFF")
end

return ZoneConfig
