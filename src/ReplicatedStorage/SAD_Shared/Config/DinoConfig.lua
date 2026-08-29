--!nonstrict
--[[
	DinoConfig
	ReplicatedStorage/SAD_Shared/Config/DinoConfig  (ModuleScript)

	The species roster. Mirrors docs/01-dinosaurs.md §3, scoped to V1.

	To add a dinosaur: append one `species{...}` row, drop its model into
	SAD_Assets/Dinos, done. No system script changes. ConfigValidator fails the
	boot loudly if the rarity, a zone id, or the model name does not resolve.

	═══ ZONE ASSIGNMENT IS THE AUTHORITATIVE SOURCE ═════════════════════════
	`Zones` on each species is the ONLY place the species-to-zone relationship
	is stored. ZoneConfig does not carry a SpeciesPool - two tables describing
	the same relationship is a guarantee of drift. BuildZoneIndex() derives the
	zone -> rarity -> species lookup at boot instead.
	═════════════════════════════════════════════════════════════════════════

	═══ V1 SCOPE NOTE ═══════════════════════════════════════════════════════
	35 species in V1. docs/01 assigns zones assuming all ten exist. V1 has four, so several
	species are placed earlier than their eventual home - a Legendary has to be
	reachable somewhere or Zone 4's Legendary weight rolls a rarity the game
	cannot hatch. These ranges shift up as zones 5-10 ship. The species that
	move are marked V1_PLACEMENT below.
	═════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local DinoConfig = {}

DinoConfig.Species = {}

local indexCounter = 0

--[[
	Fills the defaults so a row states only what makes that dinosaur different.

	Derived rather than repeated:
	  ModelName     "Dino_" .. Id, unless overridden
	  EggModelName  from the RARITY, not the species. The player does not know
	                what is inside an egg, so eggs look like their tier - which
	                is also what makes the carried-egg aura readable at range.
	  IndexOrder    declaration order, so the collection book reads
	                Common -> Titan without a hand-maintained number.
]]
local function species(entry)
	indexCounter += 1

	entry.VisualScale = entry.VisualScale or 1
	entry.MutationsAllowed = entry.MutationsAllowed or "all"
	entry.IndexOrder = indexCounter
	entry.ModelName = entry.ModelName or ("Dino_" .. entry.Id)
	entry.EggModelName = entry.EggModelName or ("Egg_" .. entry.Rarity)

	-- Animation and sound ids are filled in during the art pass (Step 24).
	-- Placeholders rather than nil so nothing has to nil-check six fields.
	entry.Anims = entry.Anims or {}
	entry.Sfx = entry.Sfx or {}

	assert(DinoConfig.Species[entry.Id] == nil, "duplicate species id: " .. entry.Id)
	DinoConfig.Species[entry.Id] = entry
	return entry
end

local ALL_V1_ZONES = { "plains", "canyon", "swamp", "frozen" }

-- ═══ COMMON (10) ═══════════════════════════════════════════════════════════

species({ Id = "compsognathus", DisplayName = "Compsognathus", Rarity = "common",
	SpeciesFactor = 0.80, Size = "1x1", ChaseArchetype = "skitterer",
	-- Tiny scavengers turn up everywhere, which conveniently makes them the
	-- Common backstop for every zone.
	Zones = ALL_V1_ZONES,
	Description = "Chicken-sized, absolutely fearless." })

species({ Id = "microraptor", DisplayName = "Microraptor", Rarity = "common",
	SpeciesFactor = 0.85, Size = "1x1", ChaseArchetype = "glider",
	Zones = { "plains" },
	Description = "Four wings. Questionable landings." })

species({ Id = "hypsilophodon", DisplayName = "Hypsilophodon", Rarity = "common",
	SpeciesFactor = 0.90, Size = "1x1", ChaseArchetype = "skitterer",
	Zones = { "plains", "swamp" },
	Description = "Fast, twitchy, always looking over its shoulder." })

species({ Id = "coelophysis", DisplayName = "Coelophysis", Rarity = "common",
	SpeciesFactor = 0.95, Size = "1x1", ChaseArchetype = "sprinter",
	Zones = { "plains", "canyon", "swamp" },
	Description = "Hollow bones, hollow conscience." })

species({ Id = "dryosaurus", DisplayName = "Dryosaurus", Rarity = "common",
	SpeciesFactor = 1.00, Size = "1x1", ChaseArchetype = "grazer",
	Zones = { "plains" },
	Description = "Would rather be eating." })

species({ Id = "othnielia", DisplayName = "Othnielia", Rarity = "common",
	SpeciesFactor = 1.00, Size = "1x1", ChaseArchetype = "grazer",
	Zones = { "plains" },
	Description = "Small, springy, deeply unbothered." })

species({ Id = "protoceratops", DisplayName = "Protoceratops", Rarity = "common",
	SpeciesFactor = 1.10, Size = "1x1", ChaseArchetype = "bulldozer",
	Zones = { "plains", "canyon", "frozen" },
	Description = "A frill and a grudge." })

species({ Id = "psittacosaurus", DisplayName = "Psittacosaurus", Rarity = "common",
	SpeciesFactor = 1.15, Size = "1x1", ChaseArchetype = "grazer",
	Zones = { "plains", "canyon", "frozen" },
	Description = "Parrot beak, dinosaur attitude." })

species({ Id = "gallimimus", DisplayName = "Gallimimus", Rarity = "common",
	SpeciesFactor = 1.25, Size = "2x2", ChaseArchetype = "sprinter",
	Zones = { "plains", "canyon" },
	Description = "They're flocking this way." })

species({ Id = "struthiomimus", DisplayName = "Struthiomimus", Rarity = "common",
	SpeciesFactor = 1.30, Size = "2x2", ChaseArchetype = "sprinter",
	Zones = { "plains", "canyon", "frozen" },
	Description = "Ostrich shaped. Ostrich fast." })

-- ═══ UNCOMMON (9) ══════════════════════════════════════════════════════════

species({ Id = "oviraptor", DisplayName = "Oviraptor", Rarity = "uncommon",
	SpeciesFactor = 0.85, Size = "1x1", ChaseArchetype = "skitterer",
	Zones = { "plains", "canyon" },
	Description = "Takes egg theft personally. Professional courtesy is dead." })

species({ Id = "ornithomimus", DisplayName = "Ornithomimus", Rarity = "uncommon",
	SpeciesFactor = 0.90, Size = "2x2", ChaseArchetype = "sprinter",
	Zones = { "canyon" },
	Description = "Built entirely out of legs." })

species({ Id = "dilophosaurus", DisplayName = "Dilophosaurus", Rarity = "uncommon",
	SpeciesFactor = 0.95, Size = "2x2", ChaseArchetype = "spitter",
	Zones = { "canyon", "swamp" },
	Description = "The crest is a warning. So is everything else." })

species({ Id = "maiasaura", DisplayName = "Maiasaura", Rarity = "uncommon",
	SpeciesFactor = 1.00, Size = "2x2", ChaseArchetype = "grazer",
	Zones = { "canyon" },
	Description = "Good mother lizard. Very bad mood." })

species({ Id = "pachycephalosaurus", DisplayName = "Pachycephalosaurus", Rarity = "uncommon",
	SpeciesFactor = 1.05, Size = "2x2", ChaseArchetype = "charger",
	Zones = { "canyon", "swamp", "frozen" },
	Description = "Solves problems with its forehead." })

species({ Id = "corythosaurus", DisplayName = "Corythosaurus", Rarity = "uncommon",
	SpeciesFactor = 1.10, Size = "2x2", ChaseArchetype = "honker",
	Zones = { "canyon", "swamp", "frozen" },
	Description = "The honk carries for miles." })

species({ Id = "iguanodon", DisplayName = "Iguanodon", Rarity = "uncommon",
	SpeciesFactor = 1.15, Size = "2x2", ChaseArchetype = "bulldozer",
	Zones = { "canyon", "swamp", "frozen" },
	Description = "Thumb spikes. Point taken." })

species({ Id = "parasaurolophus", DisplayName = "Parasaurolophus", Rarity = "uncommon",
	SpeciesFactor = 1.20, Size = "2x2", ChaseArchetype = "honker",
	Zones = { "plains", "canyon", "swamp" },
	Description = "The tutorial dinosaur. Never forgot it." })

species({ Id = "deinonychus", DisplayName = "Deinonychus", Rarity = "uncommon",
	SpeciesFactor = 1.30, Size = "2x2", ChaseArchetype = "packhunter",
	Zones = { "swamp" },
	Description = "Never hunts alone. Never." })

-- ═══ RARE (8) ══════════════════════════════════════════════════════════════

species({ Id = "kentrosaurus", DisplayName = "Kentrosaurus", Rarity = "rare",
	SpeciesFactor = 0.85, Size = "2x2", ChaseArchetype = "spiker",
	Zones = { "canyon", "swamp" },
	Description = "Spikes going in every direction at once." })

species({ Id = "plesiosaurus", DisplayName = "Plesiosaurus", Rarity = "rare",
	SpeciesFactor = 0.90, Size = "2x2", ChaseArchetype = "swimmer",
	Zones = { "swamp", "frozen" },
	Description = "Harmless on land. Get on land." })

species({ Id = "pteranodon", DisplayName = "Pteranodon", Rarity = "rare",
	SpeciesFactor = 0.95, Size = "2x2", ChaseArchetype = "divebomber",
	Zones = { "swamp" },
	Description = "Terrain is not a factor for it." })

species({ Id = "stegosaurus", DisplayName = "Stegosaurus", Rarity = "rare",
	SpeciesFactor = 1.05, Size = "3x3", ChaseArchetype = "spiker",
	-- V1_PLACEMENT: also in plains so Zone 1 has a second Rare to chase.
	Zones = { "plains", "swamp" },
	Description = "Brain the size of a walnut. Tail the size of a problem." })

species({ Id = "suchomimus", DisplayName = "Suchomimus", Rarity = "rare",
	SpeciesFactor = 1.10, Size = "3x3", ChaseArchetype = "wader",
	Zones = { "swamp", "frozen" },
	Description = "Crocodile jaws on dinosaur legs." })

species({ Id = "baryonyx", DisplayName = "Baryonyx", Rarity = "rare",
	SpeciesFactor = 1.15, Size = "3x3", ChaseArchetype = "wader",
	Zones = { "swamp", "frozen" },
	Description = "That claw is for fish. Allegedly." })

species({ Id = "ankylosaurus", DisplayName = "Ankylosaurus", Rarity = "rare",
	SpeciesFactor = 1.20, Size = "3x3", ChaseArchetype = "bulldozer",
	Zones = { "swamp", "frozen" },
	Description = "A tank with a club. Redecorates on contact." })

species({ Id = "velociraptor", DisplayName = "Velociraptor", Rarity = "rare",
	SpeciesFactor = 1.30, Size = "2x2", ChaseArchetype = "packhunter",
	-- The signature Rare: available everywhere, so every zone has a chase
	-- worth filming.
	Zones = ALL_V1_ZONES,
	Description = "Clever girl." })

-- ═══ EPIC (3) ══════════════════════════════════════════════════════════════

species({ Id = "carnotaurus", DisplayName = "Carnotaurus", Rarity = "epic",
	SpeciesFactor = 1.05, Size = "3x3", ChaseArchetype = "sprinter",
	Zones = { "canyon", "swamp", "frozen" },
	Description = "Horns, tiny arms, and no brakes." })

species({ Id = "allosaurus", DisplayName = "Allosaurus", Rarity = "epic",
	SpeciesFactor = 1.10, Size = "3x3", ChaseArchetype = "ambusher",
	Zones = { "canyon", "swamp", "frozen" },
	Description = "Already knows where you're going." })

species({ Id = "triceratops", DisplayName = "Triceratops", Rarity = "epic",
	SpeciesFactor = 1.15, Size = "3x3", ChaseArchetype = "charger",
	-- V1_PLACEMENT: also in plains. Zone 1 rolls Epic at 1.8%, so Zone 1 needs
	-- an Epic that can hatch - and a Triceratops on open plains is the most
	-- natural fit in the roster.
	Zones = ALL_V1_ZONES,
	Description = "Three horns. One direction. Yours." })

-- ═══ LEGENDARY (2) ═════════════════════════════════════════════════════════

species({ Id = "spinosaurus", DisplayName = "Spinosaurus", Rarity = "legendary",
	SpeciesFactor = 1.15, Size = "4x4", ChaseArchetype = "wader",
	-- V1_PLACEMENT: eventually Zones 6-7.
	Zones = { "swamp", "frozen" },
	Description = "Sail up. Water is not your escape." })

species({ Id = "trex", DisplayName = "Tyrannosaurus Rex", Rarity = "legendary",
	SpeciesFactor = 1.30, Size = "4x4", ChaseArchetype = "apex",
	-- V1_PLACEMENT: everywhere, because every V1 zone has Legendary weight and
	-- the T-Rex is the one dinosaur every player is already hoping for.
	Zones = ALL_V1_ZONES,
	Description = "The king. Everyone stops what they're doing." })

-- ═══ SECRET (1) ════════════════════════════════════════════════════════════

--[[
	The joke Secret, and the single best clip generator in the game.

	A Compsognathus with a corrupted texture that teleports a few studs at
	random. Its SpeciesFactor of 0.60 makes it the WORST Secret by income -
	which is the joke - but it can drop from any zone including Zone 1, at
	1 in 10,526,316 there. That is a brand-new player's first-egg lottery
	ticket, and the clip of a starter-zone player hitting it spreads further
	than any amount of endgame content.

	Art cost is a retexture of an existing model plus one VFX, which is why it
	earns its slot in a 35-species V1 roster.
]]
species({ Id = "glitchcompy", DisplayName = "Glitch Compsognathus", Rarity = "secret",
	SpeciesFactor = 0.60, Size = "1x1", ChaseArchetype = "glitcher",
	Zones = ALL_V1_ZONES,
	Description = "s̷o̶m̸e̷t̴h̵i̸n̷g̶ ̴i̵s̶ ̸w̷r̴o̵n̸g̷ ̶w̸i̵t̴h̶ ̷t̸h̴i̵s̶ ̷o̴n̵e̸" })

species({ Id = "voidraptor", DisplayName = "Void Raptor", Rarity = "secret",
	SpeciesFactor = 1.00, Size = "3x3", ChaseArchetype = "blinker",
	-- Both Secrets cover every zone, so a Secret roll always has something to
	-- hatch and each is half as likely as the tier itself.
	Zones = ALL_V1_ZONES,
	Description = "It was not in the nest a second ago." })

-- ═══ TITAN (1) ═════════════════════════════════════════════════════════════

species({ Id = "titanrex", DisplayName = "Titan Rex", Rarity = "titan",
	SpeciesFactor = 1.15, Size = "4x4", VisualScale = 3, ChaseArchetype = "titan",
	Zones = ALL_V1_ZONES,
	Description = "The sky goes dark over the park that holds one." })

-- ── Helpers ─────────────────────────────────────────────────────────────────

function DinoConfig.Get(speciesId: string)
	return DinoConfig.Species[speciesId]
end

function DinoConfig.Count(): number
	return indexCounter
end

--- Declaration order, which is Common -> Titan. Used by the Index book.
function DinoConfig.Ordered()
	local list = {}
	for _, entry in DinoConfig.Species do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		return a.IndexOrder < b.IndexOrder
	end)
	return list
end

--[[
	zone -> rarity -> { speciesId }, derived from each species' Zones.

	Built once and cached. This is the lookup NestService uses after rolling a
	rarity: pick the zone's bucket for that tier, then pick uniformly within it.
]]
local zoneIndexCache = nil

function DinoConfig.BuildZoneIndex()
	if zoneIndexCache then
		return zoneIndexCache
	end

	local index = {}
	for _, entry in DinoConfig.Species do
		for _, zoneId in entry.Zones do
			local zone = index[zoneId]
			if not zone then
				zone = {}
				index[zoneId] = zone
			end
			local bucket = zone[entry.Rarity]
			if not bucket then
				bucket = {}
				zone[entry.Rarity] = bucket
			end
			table.insert(bucket, entry.Id)
		end
	end

	-- Sorted so a weighted or seeded pick over a bucket is reproducible.
	for _, zone in index do
		for _, bucket in zone do
			table.sort(bucket)
		end
	end

	zoneIndexCache = index
	return index
end

--- Species of `rarity` obtainable in `zoneId`. Empty when the combination has
--- no coverage, which ConfigValidator rule 6 refuses to let happen at boot.
function DinoConfig.SpeciesFor(zoneId: string, rarity: string): { string }
	local index = DinoConfig.BuildZoneIndex()
	local zone = index[zoneId]
	if not zone then
		return {}
	end
	return zone[rarity] or {}
end

return DinoConfig
