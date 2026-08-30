--[[
	Step 20 specification.

	Rebirth. docs/13 §Step 20: "the reset must be one atomic profile write. A
	half-applied rebirth is the worst bug in the game."

	The half-applied rebirth this measures is not a torn write - it is a
	profile field nobody classified. `Preserved` was written at Step 3 and the
	schema has grown eleven fields since; every one defaulted to RESET by not
	being mentioned, and four of those would have made a rebirth a way to clear
	an anti-abuse cooldown.

	Run with:  ./tests/run.sh
]]

local Vector3MT = {}
Vector3MT.__index = Vector3MT
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT) end
Vector3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3 = { new = v3, zero = v3(0, 0, 0), yAxis = v3(0, 1, 0) }
local CFrameMT = {}
CFrameMT.__index = CFrameMT
CFrameMT.__mul = function(a, _b) return a end
CFrame = {
	new = function(x, y, z) return setmetatable({ P = v3(x, y, z) }, CFrameMT) end,
	lookAt = function(from) return setmetatable({ P = from }, CFrameMT) end,
	Angles = function() return setmetatable({ P = v3(0, 0, 0) }, CFrameMT) end,
}
Color3 = { fromHex = function(h) return { Hex = h } end }
typeof = type

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua DailyConfig=src/ReplicatedStorage/SAD_Shared/Config/DailyConfig.lua ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

for name, mod in pairs({ GameConfig = GameConfig, RarityConfig = RarityConfig, DinoConfig = DinoConfig,
	ZoneConfig = ZoneConfig, UpgradeConfig = UpgradeConfig, RebirthConfig = RebirthConfig,
	MutationConfig = MutationConfig, DailyConfig = DailyConfig, ParkConfig = ParkConfig }) do
	_shared.Config[name] = mod
end

--@INJECT Stats=src/ReplicatedStorage/SAD_Shared/Modules/Stats.lua@
_shared.Modules.Stats = Stats

--@INJECT Economy=src/ReplicatedStorage/SAD_Shared/Modules/Economy.lua ProfileTemplate=src/ServerScriptService/SAD_Server/Services/DataService/ProfileTemplate.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %.4f want ~%.4f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

------------------------------------------------------------------ coverage
section("Every profile field is classified exactly once")

--[[
	The finding this step exists around. Three lists, and the template must be
	their exact union - no key in two, no key in none.
]]
eq("the three lists cover the template", RebirthConfig.Validate(ProfileTemplate), nil)

local templateKeys, preserved, reset, partial = 0, 0, 0, 0
for _ in pairs(ProfileTemplate) do templateKeys += 1 end
for _ in pairs(RebirthConfig.Preserved) do preserved += 1 end
for _ in pairs(RebirthConfig.Reset) do reset += 1 end
for _ in pairs(RebirthConfig.Partial) do partial += 1 end

print(string.format("  %d fields = %d preserved + %d reset + %d partial",
	templateKeys, preserved, reset, partial))
eq("the counts add up", preserved + reset + partial, templateKeys)

--[[
	And the check has to be capable of failing, in each of its three ways.
	A coverage assertion nobody has watched fail is not a coverage assertion.
]]
local probe = {}
for key, value in pairs(ProfileTemplate) do probe[key] = value end

probe.SomethingNew = 0
local unclassified = RebirthConfig.Validate(probe)
ok("an unclassified field is caught", unclassified ~= nil)
ok("...and named", unclassified and string.find(unclassified, "SomethingNew") ~= nil)
probe.SomethingNew = nil

RebirthConfig.Reset.Index = "wrong"
local twice = RebirthConfig.Validate(probe)
ok("a field classified twice is caught", twice ~= nil)
ok("...and named", twice and string.find(twice, "Index") ~= nil)
RebirthConfig.Reset.Index = nil

RebirthConfig.Preserved.Imaginary = "not a field"
local ghost = RebirthConfig.Validate(probe)
ok("a classification for a field that does not exist is caught", ghost ~= nil)
RebirthConfig.Preserved.Imaginary = nil

eq("and it passes again once repaired", RebirthConfig.Validate(ProfileTemplate), nil)

--------------------------------------------------------------- what survives
section("What survives (docs/05 §6)")

--[[
	docs/05 §6's "what never resets" list, by name.
]]
for _, key in ipairs({ "Index", "IndexMilestones", "DNA", "Quests", "Daily",
	"Gamepasses", "Stats", "Settings", "Tutorial", "LuckNodes", "Items" }) do
	ok("preserved: " .. key, RebirthConfig.Preserved[key] ~= nil)
end

--[[
	The four anti-abuse fields. Resetting any of them makes a rebirth a way to
	clear a cooldown that exists to stop a player being farmed - the most
	consequential of the eleven that were unclassified.
]]
for _, key in ipairs({ "StealCooldowns", "RevengeMarks", "RobbedAt", "GlobalStealAt" }) do
	ok("a rebirth cannot clear: " .. key, RebirthConfig.Preserved[key] ~= nil)
end

--[[
	The permanent grants. Index milestones never reset (above), so the slots
	they hand out must not either - otherwise "permanent" is only true until
	the next rebirth.
]]
for _, key in ipairs({ "BonusDinoSlots", "BonusVaultSlots", "Titles" }) do
	ok("permanent grants stay permanent: " .. key, RebirthConfig.Preserved[key] ~= nil)
end

ok("map knowledge survives, like the Index", RebirthConfig.Preserved.Shrines ~= nil)
ok("an active boost is not confiscated", RebirthConfig.Preserved.Boosts ~= nil)

-- Every classification carries a reason rather than a bare `true`.
local reasonless = 0
for _, list in ipairs({ RebirthConfig.Preserved, RebirthConfig.Reset, RebirthConfig.Partial }) do
	for key, reason in pairs(list) do
		if type(reason) ~= "string" or #reason < 8 then reasonless += 1 end
	end
end
eq("every classification says why", reasonless, 0)

section("What resets")

for _, key in ipairs({ "Fossils", "Upgrades", "Defences", "Eggs", "Incubators",
	"BankedFossils", "BankedAt", "BankedRate" }) do
	ok("reset: " .. key, RebirthConfig.Reset[key] ~= nil)
end
eq("dinosaurs are partial, not reset", RebirthConfig.Reset.Dinos, nil)
ok("...and are classified as partial", RebirthConfig.Partial.Dinos ~= nil)

--[[
	docs/05 §6 says "all Fossil-purchased upgrade levels" reset, and the
	defence board is Fossil-purchased. Step 13's whole 180-second measurement
	depends on this being true, so it is asserted here too rather than only
	there.
]]
ok("both upgrade tables reset",
	RebirthConfig.Reset.Upgrades ~= nil and RebirthConfig.Reset.Defences ~= nil)

------------------------------------------------------------------ the cost
section("The cost curve (docs/05 §6)")

local PUBLISHED = { { 1, 250000 }, { 2, 1300000 }, { 3, 6760000 }, { 5, 183000000 } }
for _, row in ipairs(PUBLISHED) do
	eq(string.format("rebirth %d costs %s", row[1], Format.Number(row[2])),
		RebirthConfig.CostOf(row[1]), row[2])
end
eq("before the first is free", RebirthConfig.CostOf(0), 0)

-- Whole numbers, always: a price is read and compared against a balance.
local fractional = 0
for n = 1, 25 do
	local cost = RebirthConfig.CostOf(n)
	if cost ~= math.floor(cost) then fractional += 1 end
end
eq("every rebirth cost is a whole number", fractional, 0)

-- And the dinosaur requirement, which stops a rebirth on a bare plot.
eq("rebirth 1 needs 3 dinosaurs", RebirthConfig.DinosaursRequired(1), 3)
eq("rebirth 10 needs 12", RebirthConfig.DinosaursRequired(10), 12)

------------------------------------------------------------------ the gains
section("What you gain (docs/05 §6)")

local GAINS = {
	{ "income at R1", RebirthConfig.IncomeMultiplier(1), 1.15 },
	{ "income at R10", RebirthConfig.IncomeMultiplier(10), 2.5 },
	{ "luck at R5", RebirthConfig.LuckBonus(5), 0.25 },
	{ "luck caps at R15", RebirthConfig.LuckBonus(15), 0.75 },
	{ "luck stays capped at R40", RebirthConfig.LuckBonus(40), 0.75 },
	{ "mutluck caps at R15", RebirthConfig.MutLuckBonus(15), 0.45 },
	{ "move speed caps at R20", RebirthConfig.MoveSpeedBonus(20), 0.40 },
}
for _, row in ipairs(GAINS) do
	near(row[1], row[2], row[3], 0.0001)
end

eq("offline cap starts at 4 hours", RebirthConfig.OfflineCapSecs(0) / 3600, 4)
eq("and caps at 12", RebirthConfig.OfflineCapSecs(20) / 3600, 12)
eq("dino slots: +1 every two rebirths", RebirthConfig.BonusDinoSlots(6), 3)
eq("...capped at 10", RebirthConfig.BonusDinoSlots(99), 10)

local VAULT = { { 0, 1 }, { 3, 2 }, { 7, 3 }, { 12, 4 }, { 20, 5 }, { 99, 5 } }
for _, row in ipairs(VAULT) do
	eq(string.format("vault slots at R%d", row[1]), RebirthConfig.VaultSlots(row[1]), row[2])
end

--[[
	Every capped grant must actually reach its cap before the cap changes
	meaning - a cap reached at R500 is not a cap, it is a limit nobody meets.
]]
eq("luck reaches its cap by R15", RebirthConfig.LuckBonus(15), RebirthConfig.LuckBonus(16))
eq("move speed by R20", RebirthConfig.MoveSpeedBonus(20), RebirthConfig.MoveSpeedBonus(21))
eq("dino slots by R20", RebirthConfig.BonusDinoSlots(20), RebirthConfig.BonusDinoSlots(21))

-------------------------------------------------------------------- the cache
section("The Rebirth Cache (docs/05 §6)")

--[[
	"One guaranteed egg of the highest rarity you have ever hatched, minus one
	tier (min Rare)." Read from Stats.RarestRarity, which is Preserved - so
	the cache scales with a career rather than with the run just deleted.
]]
local function cacheFor(rarest)
	return RebirthConfig.CacheRarity({ Stats = { RarestRarity = rarest } }, RarityConfig)
end

--[[
	docs/05 §6's RULE and its EXAMPLE disagree, and the example is the one that
	is wrong. "Minus one tier" from Mythic is Legendary; the example says
	"rebirth 8 hands a Mythic player an Epic egg", which is minus TWO.

	The rule wins: it is the mechanism, the example is prose illustrating it,
	and `CacheTiersBelowBest = 1` has implemented the rule since Step 3.
	docs/05 §6's example is corrected rather than the config changed - but the
	generosity question is a real design call, and flipping
	`CacheTiersBelowBest` to 2 is the whole change if the example's reading is
	preferred. Written up in PROGRESS.md.
]]
eq("one tier below is the rule", RebirthConfig.CacheTiersBelowBest, 1)
eq("a Mythic career caches a Legendary", cacheFor("mythic"), "legendary")
eq("a Legendary career caches an Epic", cacheFor("legendary"), "epic")
eq("an Epic career caches a Rare", cacheFor("epic"), "rare")
eq("a Rare career caches a Rare, the floor", cacheFor("rare"), "rare")
eq("a Common career still caches a Rare", cacheFor("common"), "rare")
eq("a Titan career caches a Secret", cacheFor("titan"), "secret")

-- And the two-tier reading, so switching to it is a one-value change with a
-- test that already describes what it would do.
local function cacheAt(rarest, steps)
	local target = RarityConfig.TierBelow(rarest, steps)
	if RarityConfig.RankOf(target) < RarityConfig.RankOf(RebirthConfig.CacheMinRarity) then
		target = RebirthConfig.CacheMinRarity
	end
	return target
end
eq("at two tiers below, a Mythic career would cache an Epic", cacheAt("mythic", 2), "epic")

--[[
	The floor is the anti-repetition rule's whole point: docs/05 §6 says "you
	never restart from literally nothing". A cache below Rare would be nothing.
]]
for _, rarity in ipairs(RarityConfig.Order) do
	ok("never caches below Rare: " .. rarity,
		RarityConfig.RankOf(cacheFor(rarity)) >= RarityConfig.RankOf("rare"))
end

--------------------------------------------------------------- zones
section("Which zones survive")

--[[
	The real implementation, not a copy. RebirthConfig owns this so the confirm
	screen and the transaction cannot disagree, which also means the spec is
	testing the thing that runs.
]]
local function zonesAfter(unlocked, rebirths)
	return RebirthConfig.ZonesAfter(unlocked, rebirths, ZoneConfig)
end

local everything = {}
for _, zoneId in ZoneConfig.Order do everything[zoneId] = true end

local kept, lost = zonesAfter(everything, 1)
ok("the free zone always survives", kept.plains == true)

local lostCost = 0
local lostNames = {}
for zoneId in pairs(lost) do
	lostCost += ZoneConfig.Get(zoneId).Unlock.Fossils
	table.insert(lostNames, zoneId)
end
table.sort(lostNames)
print(string.format("  a V1 rebirth re-locks %s, worth %s Fossils",
	table.concat(lostNames, ", "), Format.Number(lostCost)))

--[[
	No V1 zone is rebirth-gated - Zone 5 is the first, and it is V1.1 - so a V1
	rebirth returns the player to the free zone and the other three are
	re-bought. Worth measuring against the rebirth cost it sits beside:
	450,000 of re-buying on top of a 250,000 rebirth is nearly three times the
	published price of the transaction.

	That is the design's own rule and it is recorded, not changed. It stops
	mattering the moment Zone 5 ships, because from then on the floor rises
	with the rebirth count.
]]
eq("V1 re-locks three zones", #lostNames, 3)
eq("...worth 450,000 Fossils", lostCost, 450000)
ok("which is more than the rebirth itself costs", lostCost > RebirthConfig.CostOf(1))
print(string.format("  rebirth 1 costs %s, so the true cost is %s",
	Format.Number(RebirthConfig.CostOf(1)),
	Format.Number(RebirthConfig.CostOf(1) + lostCost)))

--[[
	And the rule relaxes with content. An injected rebirth-gated Zone 5 must
	become the floor, so a player at that rebirth count keeps everything below
	it.
]]
ZoneConfig.Zones.volcano = {
	Id = "volcano", RingSlot = 5, DisplayName = "Volcanic Crater", Order = 5, Color = "FF6B35",
	Unlock = { Fossils = 3500000, Rebirths = 1, IndexPercent = 0, OwnRarity = nil },
	NestCount = 10, EggsPerNest = 2, RespawnSecs = 90, GuardiansPerNest = { min = 1, max = 2 },
	LuckBonus = 0.08, GuardianSpeedBonus = 0.14, Hazards = {}, WorldModel = "Zone05",
	Tagline = "-",
}
table.insert(ZoneConfig.Order, "volcano")

local withZone5 = {}
for _, zoneId in ZoneConfig.Order do withZone5[zoneId] = true end
local kept5, lost5 = zonesAfter(withZone5, 1)
local lost5Count = 0
for _ in pairs(lost5) do lost5Count += 1 end

ok("a rebirth-gated zone becomes the floor", kept5.volcano == true)
ok("...and everything below it survives",
	kept5.canyon and kept5.swamp and kept5.frozen)
eq("...so nothing is re-locked at all", lost5Count, 0)

table.remove(ZoneConfig.Order)
ZoneConfig.Zones.volcano = nil

------------------------------------------------------------- vault survival
section("Vaulted dinosaurs survive")

local dinosAfter = RebirthConfig.DinosAfter

local park = { Rebirths = 12, BonusVaultSlots = 0, Dinos = {
	v1 = { SpeciesId = "trex", Rarity = "titan", Vault = 1, Stars = 5 },
	v2 = { SpeciesId = "trex", Rarity = "mythic", Vault = 2 },
	v3 = { SpeciesId = "trex", Rarity = "legendary", Vault = 3 },
	v4 = { SpeciesId = "trex", Rarity = "epic", Vault = 4 },
	loose1 = { SpeciesId = "trex", Rarity = "legendary", Placed = true },
	loose2 = { SpeciesId = "trex", Rarity = "common", Placed = false },
} }

local survivors = dinosAfter(park)
local survivorCount = 0
for _ in pairs(survivors) do survivorCount += 1 end

eq("four vaulted at R12 (4 slots) all survive", survivorCount, 4)
ok("the Titan survives", survivors.v1 ~= nil)
ok("...with its stars", survivors.v1 and survivors.v1.Stars == 5)
ok("a placed Legendary does not", survivors.loose1 == nil)
ok("nor a stored Common", survivors.loose2 == nil)

--[[
	More vaulted than slots is not reachable today, because slots only ever go
	up - but which four of five survive must still be deterministic rather than
	whatever `pairs` returned. "Cannot happen" is how eleven fields ended up
	unclassified.
]]
local overfull = { Rebirths = 0, BonusVaultSlots = 0, Dinos = {} }
for slot = 1, 5 do
	overfull.Dinos["v" .. slot] = { SpeciesId = "trex", Rarity = "epic", Vault = slot }
end
local trimmed = dinosAfter(overfull)
local trimmedCount = 0
for _ in pairs(trimmed) do trimmedCount += 1 end
eq("one vault slot keeps one", trimmedCount, 1)
ok("...the lowest pedestal, deterministically", trimmed.v1 ~= nil)

-- Bonus vault slots from Index milestones and streaks count too.
overfull.BonusVaultSlots = 2
local withBonus = 0
for _ in pairs(dinosAfter(overfull)) do withBonus += 1 end
eq("a granted vault slot really holds a dinosaur", withBonus, 3)

----------------------------------------------------------- is it worth it
section("Is a rebirth worth doing?")

--[[
	A rebirth deletes a park and returns +15 % income. That trade is only good
	because the run rebuilds faster than the last one - so the question the
	design answers is how long it takes to get back to where you were.

	Measured against docs/05 §8's own curve: the multiplier at R1 is 1.15, and
	the 3-hour row is where docs/05 §8 puts Rebirth 1.
]]
local function timeToRebuild(rebirths)
	--[[
		Rebuilding is the same curve, run at the new multiplier. Reaching the
		same income takes as long as the curve needs to cover the ratio - a
		x3.5-per-hour curve covers 1.15 in about eight minutes.
	]]
	local growthPerHour = 3.5
	return math.log(RebirthConfig.IncomeMultiplier(rebirths)) / math.log(growthPerHour) * 3600
end

print(string.format("  R1 multiplier x%.2f rebuilds in about %s",
	RebirthConfig.IncomeMultiplier(1), Format.Time(timeToRebuild(1))))
print(string.format("  R10 multiplier x%.2f is worth about %s of the curve",
	RebirthConfig.IncomeMultiplier(10), Format.Time(timeToRebuild(10))))

ok("the first rebirth pays for itself inside an hour", timeToRebuild(1) < 3600)
ok("...and the tenth is still a real step", RebirthConfig.IncomeMultiplier(10) > 2)

--[[
	And the multiplier must be genuinely additive rather than compounding: at
	R20 an additive +15 % is x4, while compounding would be x16 - which is the
	difference between a curve and a cliff.
]]
near("R20 is x4.0, additive", RebirthConfig.IncomeMultiplier(20), 4.0, 0.0001)
ok("...not x16, which compounding would give",
	RebirthConfig.IncomeMultiplier(20) < 1.15 ^ 20)

----------------------------------------------------------------- preview
section("The preview a player reads before deleting their park")

--[[
	docs/13 §Step 20 asks for a keep/lose/gain preview. It is the same function
	the transaction uses, so what the screen promises and what the reset does
	cannot drift - "you keep 4 vaulted dinosaurs" is the one line a player
	reads before pressing the button.
]]
local candidate = {
	Rebirths = 12,
	BonusVaultSlots = 0,
	Fossils = 50000000,
	DNA = 4200,
	LuckNodes = 6,
	Dinos = park.Dinos,
	Eggs = { e1 = { Rarity = "epic" }, e2 = { Rarity = "rare" } },
	Index = { trex = {}, stego = {}, raptor = {} },
	ZonesUnlocked = everything,
	Stats = { RarestRarity = "mythic" },
}

local preview = RebirthConfig.Preview(candidate, ZoneConfig, RarityConfig)

eq("previews the NEXT rebirth", preview.Rebirth, 13)
eq("...at its cost", preview.Cost, RebirthConfig.CostOf(13))
eq("...needing 15 dinosaurs", preview.DinosRequired, 15)

eq("keeps four vaulted", preview.Keeps.Vaulted, 4)
eq("keeps the DNA", preview.Keeps.Dna, 4200)
eq("keeps the Index", preview.Keeps.IndexEntries, 3)
eq("keeps the luck nodes", preview.Keeps.LuckNodes, 6)

eq("loses the Fossils", preview.Loses.Fossils, 50000000)
eq("loses two un-vaulted dinosaurs", preview.Loses.Dinos, 2)
eq("loses two eggs", preview.Loses.Eggs, 2)
eq("loses three zones", preview.Loses.Zones, 3)
eq("...worth 450K to re-buy", preview.Loses.ZoneCost, 450000)

near("gains the R13 multiplier", preview.Gains.IncomeMultiplier,
	RebirthConfig.IncomeMultiplier(13), 0.0001)
eq("gains a Legendary cache from a Mythic career", preview.Gains.CacheRarity, "legendary")
eq("names the tier reached", preview.Gains.NameTag, RebirthConfig.NameTagFor(13).DisplayName)

--[[
	The counts must reconcile: everything owned is either kept or lost, and
	nothing is both. A preview that loses more dinosaurs than the player has is
	how a confirm screen becomes a lie.
]]
local owned = 0
for _ in pairs(candidate.Dinos) do owned += 1 end
eq("kept plus lost is everything owned", preview.Keeps.Vaulted + preview.Loses.Dinos, owned)

local zonesOwned = 0
for _ in pairs(candidate.ZonesUnlocked) do zonesOwned += 1 end
eq("kept plus lost is every zone", preview.Keeps.Zones + preview.Loses.Zones, zonesOwned)

--[[
	And a vaulted dinosaur beyond the slot count counts as LOST, not kept -
	the preview has to be honest about the one case where vaulting is not
	enough.
]]
local overVaulted = {
	Rebirths = 0, BonusVaultSlots = 0, Fossils = 0, DNA = 0, LuckNodes = 0,
	Dinos = {}, Eggs = {}, Index = {}, ZonesUnlocked = { plains = true },
	Stats = { RarestRarity = "common" },
}
for slot = 1, 5 do
	overVaulted.Dinos["v" .. slot] = { SpeciesId = "trex", Rarity = "epic", Vault = slot }
end
local tight = RebirthConfig.Preview(overVaulted, ZoneConfig, RarityConfig)
eq("one slot keeps one", tight.Keeps.Vaulted, 1)
eq("...and the preview admits the other four are lost", tight.Loses.Dinos, 4)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
