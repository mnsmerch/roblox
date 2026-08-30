--[[
	Step 12 specification.

	Placement and money. Two failure modes here that nothing throws for:
	footprints that overlap (dinosaurs standing inside each other) and a bank
	that pays the same seconds twice.

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
Vector3 = { new = v3, zero = v3(0, 0, 0) }
Color3 = { fromHex = function(h) return { Hex = h } end }

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

for name, mod in pairs({ GameConfig = GameConfig, RarityConfig = RarityConfig, MutationConfig = MutationConfig,
	DinoConfig = DinoConfig, ParkConfig = ParkConfig, UpgradeConfig = UpgradeConfig, RebirthConfig = RebirthConfig }) do
	_shared.Config[name] = mod
end

--@INJECT Stats=src/ReplicatedStorage/SAD_Shared/Modules/Stats.lua@
_shared.Modules.Stats = Stats

--@INJECT Economy=src/ReplicatedStorage/SAD_Shared/Modules/Economy.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-50s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-50s got %.4f want ~%.4f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

local function profile(overrides)
	local data = { Upgrades = {}, Rebirths = 0, Dinos = {}, LastSeen = 0,
		BankedFossils = 0, BankedAt = 0, Fossils = 0 }
	for k, v in pairs(overrides or {}) do data[k] = v end
	return data
end

local function dino(speciesId, rarity, extra)
	local entry = { SpeciesId = speciesId, Rarity = rarity, Stars = 1, Placed = true }
	for k, v in pairs(extra or {}) do entry[k] = v end
	return entry
end

------------------------------------------------------------------ rate
section("Park income rate")

eq("an empty park earns nothing", Economy.ParkIncomeRate(profile()), 0)

local onePark = profile({ Dinos = { a = dino("trex", "legendary") } })
near("one dinosaur earns its own income",
	Economy.ParkIncomeRate(onePark), Economy.IncomeOf(onePark.Dinos.a, onePark), 0.001)

--[[
	STORED DINOSAURS EARN NOTHING.

	This is what makes placement slots the core sink of the whole economy
	(docs/05 §2). A hundred dinosaurs in a bag are worth exactly zero until
	there is somewhere to put them, which is why Dino Slots is the track players
	buy first and keep buying.
]]
local stored = profile({ Dinos = {
	a = dino("trex", "legendary", { Placed = true }),
	b = dino("trex", "legendary", { Placed = false }),
} })
near("storing one halves the park's output",
	Economy.ParkIncomeRate(stored), Economy.IncomeOf(stored.Dinos.a, stored), 0.001)

-- Vaulted dinosaurs still earn: the vault is protection, not a penalty.
local vaulted = profile({ Dinos = { a = dino("trex", "legendary", { Placed = false, Vault = 1 }) } })
ok("vaulted dinosaurs still earn", Economy.ParkIncomeRate(vaulted) > 0)

-- Rate scales with the park.
local rates = {}
for count = 1, 5 do
	local data = profile()
	for index = 1, count do
		data.Dinos["d" .. index] = dino("trex", "legendary")
	end
	rates[count] = Economy.ParkIncomeRate(data)
end
for count = 2, 5 do
	near("rate is linear in placed dinosaurs: " .. count, rates[count], rates[1] * count, 0.01)
end

------------------------------------------------------------------ bank
section("The lazy bank")

eq("bank seconds at level 0", Economy.BankSeconds(profile()), 60)
eq("bank seconds at max", Economy.BankSeconds(profile({ Upgrades = { bankSize = 10 } })), 360)

local park = profile({ Dinos = { a = dino("trex", "legendary") } })
local rate = Economy.ParkIncomeRate(park)
park.BankedAt = 1000
-- Opening a banking interval means stamping the rate it accrues at. This is
-- what EconomyService.SettleBank does on every rate change; a fixture that
-- skips it banks nothing, which is the correct behaviour and is asserted below.
park.BankedRate = rate

-- Accrual is exactly rate x elapsed until the cap.
for _, elapsed in ipairs({ 0, 1, 10, 30, 59 }) do
	local banked = Economy.BankedNow(park, 1000 + elapsed, rate)
	near(string.format("accrues %ds of income", elapsed), banked, rate * elapsed, 0.001)
end

-- And then stops. The cap is what brings a player home.
local capped = Economy.BankedNow(park, 1000 + 600, rate)
near("the bank fills and stops", capped, rate * 60, 0.001)
near("the cap is rate x bank seconds", capped, Economy.BankCap(park, rate), 0.001)

local bigger = profile({ Dinos = park.Dinos, Upgrades = { bankSize = 10 },
	BankedAt = 1000, BankedRate = rate })
ok("upgrading the bank holds more",
	Economy.BankedNow(bigger, 1000 + 600, rate) > capped)

-- An empty park cannot bank anything, however long it waits.
eq("an empty park banks nothing", Economy.BankedNow(profile({ BankedAt = 0 }), 99999), 0)

section("Collecting twice cannot pay twice")

--[[
	docs/13 names double collection as the bug to watch for in this step.

	Collect resets BankedFossils to 0 and BankedAt to now in the same write, so
	a second call in the same second finds zero stored and zero elapsed.
]]
local wallet = profile({ Dinos = park.Dinos, BankedAt = 1000, BankedRate = rate })
local firstTake = Economy.BankedNow(wallet, 1060, rate)
ok("the first collection is worth something", firstTake > 0)

wallet.BankedFossils = 0
wallet.BankedAt = 1060
local secondTake = Economy.BankedNow(wallet, 1060, rate)
eq("an immediate second collection is worth nothing", secondTake, 0)

local laterTake = Economy.BankedNow(wallet, 1070, rate)
near("but ten seconds later is worth ten seconds", laterTake, rate * 10, 0.001)

------------------------------------------------------------------ offline
section("Offline earnings")

local away = profile({ Dinos = park.Dinos, LastSeen = 1000 })

eq("a player who has never played earns nothing offline",
	Economy.OfflineEarnings(profile({ Dinos = park.Dinos, LastSeen = 0 }), 99999, rate), 0)

local hourEarned, hourSecs = Economy.OfflineEarnings(away, 1000 + 3600, rate)
eq("an hour away counts an hour", hourSecs, 3600)
near("at 60% of the active rate", hourEarned, rate * 3600 * 0.60, 0.01)

-- The cap, and how rebirths extend it.
local _, cappedSecs = Economy.OfflineEarnings(away, 1000 + 86400, rate)
eq("capped at 4 hours with no rebirths", cappedSecs, 4 * 3600)

local veteran = profile({ Dinos = park.Dinos, LastSeen = 1000, Rebirths = 5 })
local _, veteranSecs = Economy.OfflineEarnings(veteran, 1000 + 86400, rate)
eq("rebirths extend it by an hour each", veteranSecs, 9 * 3600)

local maxed = profile({ Dinos = park.Dinos, LastSeen = 1000, Rebirths = 50 })
local _, maxedSecs = Economy.OfflineEarnings(maxed, 1000 + 999999, rate)
eq("and cap at 12 hours", maxedSecs, 12 * 3600)

--[[
	Offline must be worth noticeably less than playing, or there is no reason to
	log in - but enough that a player who can only manage twenty minutes a day
	still feels progress. 60% of rate, capped, does both.
]]
local activeHour = rate * 3600
ok("an hour offline is worth less than an hour playing", hourEarned < activeHour)
ok("but is still worth coming back for", hourEarned > activeHour * 0.5)

-- Offline is NOT limited by the bank: everyone returning to the same sixty
-- seconds regardless of how long they were gone is the opposite of a hook.
ok("offline ignores the bank cap", hourEarned > Economy.BankCap(away, rate))

------------------------------------------------------------------ footprints
section("Footprints do not overlap")

--[[
	The other silent failure in this step: two dinosaurs occupying the same
	tiles renders as them standing inside each other.

	This fills a grid greedily with every footprint size and asserts no tile is
	ever claimed twice.
]]
local function fillGrid(sizes)
	local occupied, placed = {}, {}

	for _, size in ipairs(sizes) do
		local anchorX, anchorZ = nil, nil
		for tileZ = 1, ParkConfig.GridTiles do
			for tileX = 1, ParkConfig.GridTiles do
				local tiles = ParkConfig.FootprintTiles(tileX, tileZ, size)
				if tiles then
					local clear = true
					for _, tile in ipairs(tiles) do
						if occupied[tile[1] .. "," .. tile[2]] then clear = false break end
					end
					if clear then anchorX, anchorZ = tileX, tileZ break end
				end
			end
			if anchorX then break end
		end

		if anchorX then
			local tiles = ParkConfig.FootprintTiles(anchorX, anchorZ, size)
			for _, tile in ipairs(tiles) do
				local key = tile[1] .. "," .. tile[2]
				if occupied[key] then
					failed = failed + 1
					print("  FAIL tile " .. key .. " claimed twice by " .. size)
				end
				occupied[key] = size
			end
			table.insert(placed, { Size = size, X = anchorX, Z = anchorZ })
		end
	end

	return placed, occupied
end

local mixed = {}
for _ = 1, 4 do
	table.insert(mixed, "4x4"); table.insert(mixed, "3x3")
	table.insert(mixed, "2x2"); table.insert(mixed, "1x1")
end
local placed, occupied = fillGrid(mixed)

local usedTiles = 0
for _ in pairs(occupied) do usedTiles = usedTiles + 1 end
print(string.format("  packed %d dinosaurs into %d of %d tiles",
	#placed, usedTiles, ParkConfig.GridTiles ^ 2))

ok("the grid holds a mixed park", #placed >= 6)
ok("no tile is over-claimed", usedTiles <= ParkConfig.GridTiles ^ 2)

-- A grid of 1x1s must hold exactly its tile count and no more.
local singles = {}
for _ = 1, ParkConfig.GridTiles ^ 2 + 10 do table.insert(singles, "1x1") end
local allSingles = fillGrid(singles)
eq("a grid of singles holds exactly its tiles", #allSingles, ParkConfig.GridTiles ^ 2)

-- Four 4x4s exactly fill an 8x8 and a fifth does not fit.
local fourBigs = fillGrid({ "4x4", "4x4", "4x4", "4x4", "4x4" })
eq("four 4x4s fill the grid", #fourBigs, 4)

section("Placement slots")

eq("a new player has 4 slots", Economy.SlotCap(profile()), 4)
eq("maxed Dino Slots gives 30", Economy.SlotCap(profile({ Upgrades = { dinoSlots = 26 } })), 30)
eq("rebirths add slots", Economy.SlotCap(profile({ Rebirths = 10 })), 4 + 5)
eq("both together",
	Economy.SlotCap(profile({ Upgrades = { dinoSlots = 26 }, Rebirths = 20 })), 30 + 10)

-- Slots must never exceed what the grid can physically hold as 1x1s.
ok("the grid can hold every slot a player can buy",
	Economy.SlotCap(profile({ Upgrades = { dinoSlots = 26 }, Rebirths = 99 })) <= ParkConfig.GridTiles ^ 2)

------------------------------------------------------------------ curve
section("The day-one economy curve")

--[[
	docs/05 §8 publishes a progression: about 6 Fossils/sec at five minutes,
	45 at twenty, 380 at an hour. Those assume a mix of what a player would
	actually have caught, so this checks the SHAPE rather than exact values -
	that a plausible early park lands in the right order of magnitude.
]]
local function parkOf(counts)
	local data = profile()
	local index = 0
	for rarity, count in pairs(counts) do
		for _ = 1, count do
			index += 1
			data.Dinos["d" .. index] = dino("compsognathus", rarity)
		end
	end
	return data
end

local fiveMinutes = Economy.ParkIncomeRate(parkOf({ common = 3 }))
local twentyMinutes = Economy.ParkIncomeRate(parkOf({ common = 4, uncommon = 2 }))
local oneHour = Economy.ParkIncomeRate(parkOf({ common = 4, uncommon = 4, rare = 2 }))

print(string.format("  3 commons:                 %6.1f F/s   (docs/05: ~6 at 5 min)", fiveMinutes))
print(string.format("  4 common + 2 uncommon:     %6.1f F/s   (docs/05: ~45 at 20 min)", twentyMinutes))
print(string.format("  + 2 rare:                  %6.1f F/s   (docs/05: ~380 at 1 hour)", oneHour))

ok("a starter park earns single digits", fiveMinutes > 1 and fiveMinutes < 20)
ok("income grows several-fold with each tier reached", twentyMinutes > fiveMinutes * 1.5)
ok("and again", oneHour > twentyMinutes * 1.5)

--[[
	The three parks above are a FLOOR: every dinosaur in them is a
	Compsognathus (SpeciesFactor 0.80) and the mix leans common, so they land
	under docs/05 §8's published rows. That is expected and is not the check.

	The check that matters is that each published row is REACHABLE - that some
	park a player could plausibly hold at that timestamp produces the number
	the document prints. If it is not reachable, the economy document is
	promising a curve the formula cannot deliver, and every downstream cost in
	docs/05 is built on it.

	`dryosaurus` is a Common with SpeciesFactor exactly 1.00, which is what
	makes the arithmetic below legible: the rate is BaseIncome x count.
]]
local function parkOfSpecies(speciesId, counts, overrides)
	local data = profile(overrides)
	local index = 0
	for rarity, count in pairs(counts) do
		for _ = 1, count do
			index += 1
			data.Dinos["d" .. index] = dino(speciesId, rarity)
		end
	end
	return data
end

eq("dryosaurus is the unit species (factor 1.00)", DinoConfig.Get("dryosaurus").SpeciesFactor, 1.00)

-- Row 1: 5 min, 3 placed, 6 F/s. Three Commons at factor 1.00 gives exactly 6.
near("docs/05 row '5 min': 3 commons reach 6 F/s",
	Economy.ParkIncomeRate(parkOfSpecies("dryosaurus", { common = 3 })), 6, 0.001)

-- Row 2: 20 min, 6 placed, 45 F/s. Six Uncommons give 48 - the row is reachable
-- with a little room to spare, which is the right direction to be wrong in.
local row2 = Economy.ParkIncomeRate(parkOfSpecies("dryosaurus", { uncommon = 6 }))
near("docs/05 row '20 min': 6 uncommons reach 45 F/s", row2, 45, 45 * 0.10)

--[[
	Row 3: 1 h, 10 placed, 380 F/s. Ten Rares alone give 300 - the row is NOT
	reachable on placement count alone. It becomes reachable at Feeding Trough
	L3 (x1.24), which costs ~10.8K against the row's own 95K total earned. So
	docs/05 §8 assumes the player has been spending, which is consistent with
	its own "First upgrade" milestone at 5 minutes. Pinned here so that changing
	the Feeding Trough track fails loudly rather than quietly invalidating the
	published curve.
]]
local tenRares = Economy.ParkIncomeRate(parkOfSpecies("dryosaurus", { rare = 10 }))
near("ten rares alone fall short of the 1 h row", tenRares, 300, 0.001)
ok("...which is why the row needs upgrades, not just dinosaurs", tenRares < 380)

near("feeding trough L3 is x1.24", UpgradeConfig.EffectAt("feedingTrough", 3), 1.24, 0.0001)

local row3 = Economy.ParkIncomeRate(
	parkOfSpecies("dryosaurus", { rare = 10 }, { Upgrades = { feedingTrough = 3 } }))
print(string.format("  10 rares + trough L3:      %6.1f F/s   (docs/05: ~380 at 1 hour)", row3))
near("docs/05 row '1 h': 10 rares + trough L3 reach 380 F/s", row3, 380, 380 * 0.05)

--[[
	And the growth rate the document promises in prose: "roughly x3.5 income
	per hour in the first 6 hours". Row 2 -> row 3 is 40 minutes, so the
	published rows must at least clear that.
]]
ok("the published rows grow at least as fast as the prose claims",
	row3 / row2 >= 3.5)

-- Rebirth and the income upgrade must both matter, or neither gets bought.
local upgraded = parkOf({ common = 4, uncommon = 4, rare = 2 })
upgraded.Upgrades.feedingTrough = 20
ok("maxed Feeding Trough is worth 2.6x", Economy.ParkIncomeRate(upgraded) > oneHour * 2.5)

local reborn = parkOf({ common = 4, uncommon = 4, rare = 2 })
reborn.Rebirths = 10
near("ten rebirths are worth 2.5x", Economy.ParkIncomeRate(reborn), oneHour * 2.5, oneHour * 0.05)

section("Clamping")

eq("NaN clamps to zero", Economy.ClampFossils(0 / 0), 0)
eq("negatives clamp to zero", Economy.ClampFossils(-100), 0)
eq("the ceiling holds", Economy.ClampFossils(1e40), Economy.MaxFossils)
eq("normal values pass through", Economy.ClampFossils(12345), 12345)

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
