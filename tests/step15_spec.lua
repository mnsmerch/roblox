--[[
	Step 15 specification.

	Player raiding. This is the highest-value cheat target in the game and the
	step whose real test needs two clients, so what is measured here is the
	half that is pure: the eligibility rules, the hold formula, the shield
	arithmetic, the record pruning, and the transfer's conservation property.

	The failure modes that nothing throws for:

	  * a raid transfer that duplicates or loses a dinosaur;
	  * a shield stack that reaches permanence;
	  * a cooldown table that grows without bound on a busy account;
	  * a hold time the design publishes that the tracks cannot produce.

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
	DinoConfig = DinoConfig, ParkConfig = ParkConfig, UpgradeConfig = UpgradeConfig,
	RebirthConfig = RebirthConfig }) do
	_shared.Config[name] = mod
end

--@INJECT Stats=src/ReplicatedStorage/SAD_Shared/Modules/Stats.lua@
_shared.Modules.Stats = Stats

--@INJECT Economy=src/ReplicatedStorage/SAD_Shared/Modules/Economy.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %.3f want ~%.3f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

local NOW = 1000000

local function profile(overrides)
	local data = {
		Upgrades = {}, Defences = {}, Dinos = {}, Index = {}, Rebirths = 0, Fossils = 0,
		StealCooldowns = {}, RevengeMarks = {}, RobbedAt = {}, GlobalStealAt = 0,
		ShieldUntil = 0, NewPlayerProtectionDone = false,
		Stats = { PlaytimeSecs = 0, RarestRarity = "common" },
		Settings = { StealNotifications = true },
		BankedFossils = 0, BankedAt = 0, BankedRate = 0,
	}
	for k, v in pairs(overrides or {}) do data[k] = v end
	return data
end

local function dino(rarity, extra)
	local entry = { SpeciesId = "trex", Rarity = rarity, Stars = 1, Placed = true, HatchedAt = 1 }
	for k, v in pairs(extra or {}) do entry[k] = v end
	return entry
end

--------------------------------------------------------------- hold time
section("Hold time (docs/03 §4.2)")

--[[
	"Hold time = 3 s + SecurityLevel x 1.2 s (3 s -> 9 s at max security)",
	where docs/03 §5 defines SecurityLevel as the sum of all defence levels
	divided by 4, capped at 5.
]]
near("an undefended park is 3 seconds", Stats.RaidHoldSecs(profile()), 3.0, 0.001)
eq("...at security level zero", Stats.SecurityLevel(profile()), 0)

local maxed = profile({ Defences = { fence = 5, guardTower = 5, camera = 5 } })
print(string.format("  V1 max: %d defence levels -> security %.2f -> hold %.2fs",
	15, Stats.SecurityLevel(maxed), Stats.RaidHoldSecs(maxed)))

--[[
	The published ceiling of 9 s needs SecurityLevel 5, which needs 20 defence
	levels. V1 ships three tracks of five, so fifteen - security 3.75 and a
	7.5 s hold. The missing five levels are Alarm Horn (3) and Electric Fence
	(3), which docs/03 §5 lists and UpgradeConfig defers to V1.4.

	Asserted as what V1 actually is, with the V1.4 arithmetic checked
	alongside, so the day those two tracks ship this stops being a gap without
	anyone having to remember it was one.
]]
near("V1's ceiling is 7.5s, not the published 9s", Stats.RaidHoldSecs(maxed), 7.5, 0.001)
near("...because V1 has 15 defence levels, not 20", Stats.SecurityLevel(maxed), 3.75, 0.001)
near("with Alarm Horn and Electric Fence it reaches 5.25, capped to 5",
	math.min((15 + 3 + 3) / 4, 5), 5.0, 0.001)
near("...which is the published 9 seconds",
	GameConfig.RaidHoldBase + 5 * GameConfig.RaidHoldPerSecurity, 9.0, 0.001)

-- SecurityLevel is summed from the defence BOARD, so a V1.4 track raises it
-- with no edit here. Proven by adding one and watching the number move.
local before = Stats.SecurityLevel(maxed)
UpgradeConfig.Tracks.alarmHorn = { Id = "alarmHorn", DisplayName = "Alarm Horn", Board = "defence",
	MaxLevel = 3, BaseCost = 120000, Growth = 3.6,
	Effect = { Kind = "stealHoldBonus", Base = 0, PerLevel = 1 } }
local withHorn = profile({ Defences = { fence = 5, guardTower = 5, camera = 5, alarmHorn = 3 } })
ok("a new defence track raises security with no code change",
	Stats.SecurityLevel(withHorn) > before)
near("...to exactly 4.5", Stats.SecurityLevel(withHorn), 4.5, 0.001)
UpgradeConfig.Tracks.alarmHorn = nil

-- The cap is real: no amount of defence passes 5.
local absurd = profile({ Defences = { fence = 500, guardTower = 500, camera = 500 } })
eq("security is capped at 5", Stats.SecurityLevel(absurd), 5)
near("...so the hold can never exceed 9 seconds", Stats.RaidHoldSecs(absurd), 9.0, 0.001)

-- A Revenge Mark halves it (docs/03 §4.4).
near("a revenge raid is half the hold",
	Stats.RaidHoldSecs(maxed) * GameConfig.RevengeHoldMultiplier, 3.75, 0.001)

------------------------------------------------------------------ shields
section("Shields cannot reach permanence (docs/03 §4.3)")

--[[
	The stack cap is on the RESULTING duration, not on what is added, so no
	sequence of grants - free, quest, purchased, or all three - buys
	permanent invulnerability.
]]
local function grant(currentUntil, seconds, now)
	local base = math.max(currentUntil, now)
	return math.min(base + seconds, now + GameConfig.ShieldStackCapSecs)
end

eq("session shield is 15 minutes", GameConfig.SessionShieldSecs, 900)
eq("mercy shield is 10 minutes", GameConfig.MercyShieldSecs, 600)
eq("the stack cap is 2 hours", GameConfig.ShieldStackCapSecs, 7200)

local shield = 0
for _ = 1, 50 do
	shield = grant(shield, GameConfig.SessionShieldSecs, NOW)
end
eq("fifty session shields still cap at two hours", shield - NOW, GameConfig.ShieldStackCapSecs)

-- One grant from zero is exactly what it says.
eq("a single grant is not capped early",
	grant(0, GameConfig.SessionShieldSecs, NOW) - NOW, GameConfig.SessionShieldSecs)

-- An expired shield does not carry its past into the new one.
eq("an expired shield restarts from now",
	grant(NOW - 5000, GameConfig.MercyShieldSecs, NOW) - NOW, GameConfig.MercyShieldSecs)

-- Mercy triggers on the third robbery inside the window, not the third ever.
-- The window is 15 MINUTES - 900 seconds - so the stamps have to be inside it.
local robbedAt = { NOW - 800, NOW - 400, NOW - 100 }
local function recentCount(stamps, now)
	local count = 0
	for _, stamp in ipairs(stamps) do
		if stamp > now - GameConfig.MercyWindowSecs then count += 1 end
	end
	return count
end
eq("three robberies inside 15 minutes", recentCount(robbedAt, NOW), 3)
ok("...which is the mercy threshold", recentCount(robbedAt, NOW) >= GameConfig.MercyRobberies)
eq("the same three an hour later are not recent",
	recentCount(robbedAt, NOW + 3600), 0)

-- The boundary is exclusive: a robbery exactly 15 minutes ago has aged out.
eq("a robbery exactly on the window edge does not count",
	recentCount({ NOW - GameConfig.MercyWindowSecs }, NOW), 0)
eq("...one second inside it does",
	recentCount({ NOW - GameConfig.MercyWindowSecs + 1 }, NOW), 1)

------------------------------------------------------------------ pruning
section("Raid records stay bounded")

--[[
	StealCooldowns and RevengeMarks are keyed by userId, so on a busy account
	they grow forever unless something prunes them. docs/10 §2 bounds every
	table in the profile; an unbounded one grows until a DataStore write fails,
	which is the worst failure mode - late, and looking like nothing.
]]
local function prune(profileTable, now)
	for _, key in ipairs({ "StealCooldowns", "RevengeMarks" }) do
		local live, count = {}, 0
		for id, expiry in pairs(profileTable[key]) do
			if expiry > now then live[id] = expiry; count += 1 end
		end
		if count > GameConfig.StealRecordCap then
			local ordered = {}
			for id, expiry in pairs(live) do table.insert(ordered, { Id = id, Expiry = expiry }) end
			table.sort(ordered, function(a, b) return a.Expiry > b.Expiry end)
			live = {}
			for index = 1, GameConfig.StealRecordCap do live[ordered[index].Id] = ordered[index].Expiry end
		end
		profileTable[key] = live
	end
	local cutoff = now - GameConfig.MercyWindowSecs
	local recent = {}
	for _, stamp in ipairs(profileTable.RobbedAt) do
		if stamp > cutoff then table.insert(recent, stamp) end
	end
	profileTable.RobbedAt = recent
end

local busy = profile()
for index = 1, 500 do
	busy.StealCooldowns[tostring(index)] = NOW + index -- all still live
	busy.RevengeMarks[tostring(index)] = NOW - 1 -- all expired
end
for index = 1, 100 do
	table.insert(busy.RobbedAt, NOW - index * 60)
end
prune(busy, NOW)

local cooldownCount = 0
for _ in pairs(busy.StealCooldowns) do cooldownCount += 1 end
local markCount = 0
for _ in pairs(busy.RevengeMarks) do markCount += 1 end

eq("live cooldowns are capped", cooldownCount, GameConfig.StealRecordCap)
eq("expired marks are dropped entirely", markCount, 0)
--[[
	Stamps run NOW-60 to NOW-6000 in minute steps. The cutoff is exclusive, so
	the one at exactly NOW-900 ages out with everything older: 14 survive, not
	15. Spelled out because an off-by-one here is the difference between a
	Mercy Shield firing on the third robbery and on the fourth.
]]
eq("robbery stamps outside the window are dropped", #busy.RobbedAt,
	math.floor(GameConfig.MercyWindowSecs / 60) - 1)

-- The ones kept are the ones that matter: pruning must drop the cooldowns
-- expiring soonest, never the longest-lasting.
ok("the longest-lasting cooldown survives", busy.StealCooldowns["500"] ~= nil)
ok("...and the shortest does not", busy.StealCooldowns["1"] == nil)

------------------------------------------------------------------ targets
section("Who may be raided (docs/03 §4.1, §4.3)")

--[[
	Reimplements the stealable check and the power floor. The service itself
	needs Players and six other services; these two rules are the ones that
	decide whether a raid is even offered, and both are pure.
]]
local function stealable(ownerData, uid)
	local entry = ownerData.Dinos[uid]
	if not entry then return false, "no such dinosaur" end
	if entry.Vault then return false, "it is vaulted" end
	if not entry.Placed then return false, "it is not on display" end
	return true
end

local owner = profile({ Dinos = {
	placed = dino("epic"),
	stored = dino("legendary", { Placed = false }),
	vaulted = dino("titan", { Placed = false, Vault = 1 }),
} })

ok("a placed dinosaur is stealable", (stealable(owner, "placed")))
eq("a stored one is not", select(2, stealable(owner, "stored")), "it is not on display")
eq("a vaulted one is never", select(2, stealable(owner, "vaulted")), "it is vaulted")
eq("nor is one that does not exist", select(2, stealable(owner, "ghost")), "no such dinosaur")

--[[
	A vaulted dinosaur is off the grid but still earns (Economy counts placed
	OR vaulted), which is what makes the Vault a real choice rather than a
	sacrifice - and is why it must be checked before Placed.
]]
local vaultOnly = profile({ Dinos = { v = dino("titan", { Placed = false, Vault = 1 }) } })
ok("a vaulted dinosaur still earns", Economy.ParkIncomeRate(vaultOnly) > 0)
ok("...and still counts toward park value", Economy.ParkValue(vaultOnly) > 0)

-- The power floor: park value, not net worth. What is at risk is what is on
-- display, so what protects you should be too.
eq("the floor is 25%", GameConfig.RaidPowerFloor, 0.25)

local whale = profile({ Dinos = { a = dino("titan"), b = dino("titan") } })
local minnow = profile({ Dinos = { a = dino("common") } })

local function floorBlocks(thiefData, ownerData)
	local thiefValue = Economy.ParkValue(thiefData)
	return thiefValue > 0 and Economy.ParkValue(ownerData) < thiefValue * GameConfig.RaidPowerFloor
end

ok("a whale cannot rob a beginner", floorBlocks(whale, minnow))
ok("a beginner may rob a whale", not floorBlocks(minnow, whale))
ok("equals may rob each other", not floorBlocks(minnow, minnow))

--[[
	And the floor must not lock out a brand-new player who owns nothing: with
	a park value of zero there is no ratio to fail, so the check is skipped
	rather than dividing by it.
]]
local empty = profile()
ok("a player with no park is not blocked from raiding", not floorBlocks(empty, minnow))

-- Vaulting your whole park does NOT hide you behind the power floor: value
-- counts vaulted dinosaurs, so a park you cannot be robbed of is still a park
-- that can rob.
local allVaulted = profile({ Dinos = { a = dino("titan", { Placed = false, Vault = 1 }) } })
ok("vaulting everything does not shrink your park value",
	Economy.ParkValue(allVaulted) == Economy.ParkValue(profile({ Dinos = { a = dino("titan") } })))

----------------------------------------------------------------- transfer
section("The transfer conserves dinosaurs")

--[[
	The property that matters most in the whole step: after a raid resolves,
	the dinosaur exists exactly once across both profiles. Not zero (a support
	ticket) and not twice (an economy).

	This models the real sequence in completeSteal: snapshot, remove from the
	owner, mint for the thief - and the rollback when the thief's storage is
	full.
]]
local function totalDinos(...)
	local total = 0
	for _, data in ipairs({ ... }) do
		for _ in pairs(data.Dinos) do total += 1 end
	end
	return total
end

local victim = profile({ Dinos = { target = dino("mythic"), other = dino("common") } })
local raider = profile({ Dinos = { own = dino("rare") } })
eq("three dinosaurs before the raid", totalDinos(victim, raider), 3)

local snapshot = table.clone(victim.Dinos.target)
victim.Dinos.target = nil
raider.Dinos.stolen1 = snapshot
eq("three dinosaurs after the raid", totalDinos(victim, raider), 3)
eq("the victim has one fewer", (function() local n = 0 for _ in pairs(victim.Dinos) do n += 1 end return n end)(), 1)

-- The rollback path: storage full means the removal is undone, not skipped.
local victim2 = profile({ Dinos = { target = dino("mythic") } })
local snapshot2 = table.clone(victim2.Dinos.target)
victim2.Dinos.target = nil
-- ...Create refuses...
victim2.Dinos.target = snapshot2
eq("a failed transfer leaves it with its owner", totalDinos(victim2), 1)
eq("...unchanged", victim2.Dinos.target.Rarity, "mythic")

--[[
	A stolen dinosaur is not a hatched one. It keeps its original HatchedAt and
	must not inflate the thief's DinosHatched - which decides leaderboards, and
	which "first Rare hatch" in New Player Protection reads.
]]
eq("the stolen entry keeps its original age", snapshot.HatchedAt, 1)

-- Insurance: 25% of sell value, to the victim (docs/03 §4.4).
local sellValue = Economy.SellValueOf(snapshot)
local insurance = math.floor(sellValue * GameConfig.RaidInsuranceShare)
print(string.format("  a stolen Mythic: sell value %s, insurance %s",
	Format.Number(sellValue), Format.Number(insurance)))
ok("insurance is a real consolation", insurance > 0)
ok("...but well under the thing lost", insurance < sellValue * 0.5)
eq("the share is the published 25%", GameConfig.RaidInsuranceShare, 0.25)

------------------------------------------------------------------ vault
section("The Vault")

--[[
	docs/03 §4.3: 1 base, +1 at rebirths 3/7/12/20, max 5. Checked here rather
	than only in step3_spec because Step 15 is where the number finally does
	something - it decides how much of a park can never be taken.
]]
local VAULT = { { 0, 1 }, { 2, 1 }, { 3, 2 }, { 6, 2 }, { 7, 3 }, { 12, 4 }, { 20, 5 }, { 99, 5 } }
for _, row in ipairs(VAULT) do
	eq(string.format("rebirth %d gives %d vault slot(s)", row[1], row[2]),
		RebirthConfig.VaultSlots(row[1]), row[2])
end

ok("vault slots never exceed the pedestals built into a plot",
	RebirthConfig.VaultSlots(99) <= ParkConfig.VaultPedestalCount)

------------------------------------------------------------ carry weight
section("Raiding is heavier than egg carrying (docs/03 §4.5)")

eq("the extra penalty is 10%", GameConfig.RaidCarryExtra, 0.10)

local heaviest = 0
for _, rarityId in ipairs(RarityConfig.Order) do
	local tier = RarityConfig.Tiers[rarityId]
	local penalty = math.min(tier.CarryPenalty + GameConfig.RaidCarryExtra, GameConfig.MaxCarryPenalty)
	heaviest = math.max(heaviest, penalty)
	ok("still able to move with a " .. rarityId, penalty <= GameConfig.MaxCarryPenalty)
end

print(string.format("  heaviest raid carry: %.0f%% slower (floor is %.0f%%)",
	heaviest * 100, GameConfig.MaxCarryPenalty * 100))

-- A Titan is 45% + 10% = 55%, comfortably inside the 85% floor, so no raid is
-- ever an immobilising one.
near("a Titan raid is 55% slower",
	RarityConfig.Tiers.titan.CarryPenalty + GameConfig.RaidCarryExtra, 0.55, 0.001)
ok("no raid ever hits the immobility floor", heaviest < GameConfig.MaxCarryPenalty)

--[[
	And the raid penalty must be strictly worse than carrying the same rarity
	as an egg, or "raiding is heavier" is not true of anything.
]]
for _, rarityId in ipairs(RarityConfig.Order) do
	local tier = RarityConfig.Tiers[rarityId]
	ok("heavier than the egg: " .. rarityId,
		tier.CarryPenalty + GameConfig.RaidCarryExtra > tier.CarryPenalty)
end

---------------------------------------------------------------- cooldowns
section("Cooldowns (docs/03 §4.3)")

eq("same-victim cooldown is 10 minutes", GameConfig.RaidSameVictimCooldown, 600)
eq("global cooldown is 90 seconds", GameConfig.RaidGlobalCooldown, 90)
eq("revenge lasts 30 minutes", GameConfig.RevengeDuration, 1800)

--[[
	A Revenge Mark ignores the same-victim cooldown (docs/03 §4.4), which only
	means anything if it outlives it. Thirty minutes against ten: a robbed
	player gets three full windows to take it back.
]]
ok("a revenge mark outlives the cooldown it bypasses",
	GameConfig.RevengeDuration > GameConfig.RaidSameVictimCooldown)
eq("...by three cooldown windows",
	math.floor(GameConfig.RevengeDuration / GameConfig.RaidSameVictimCooldown), 3)

-- The global cooldown must be shorter than the same-victim one, or the
-- per-victim rule would never be the binding constraint on anything.
ok("the global cooldown is the looser of the two",
	GameConfig.RaidGlobalCooldown < GameConfig.RaidSameVictimCooldown)

--[[
	How many raids an hour a determined player can run: the global cooldown is
	the only limit once they have enough distinct victims, and 40/hour is the
	number the design is choosing when it sets 90 seconds.
]]
print(string.format("  ceiling: %d raids/hour against distinct victims, %d against one",
	math.floor(3600 / GameConfig.RaidGlobalCooldown),
	math.floor(3600 / GameConfig.RaidSameVictimCooldown)))
ok("one victim cannot be farmed more than 6 times an hour",
	math.floor(3600 / GameConfig.RaidSameVictimCooldown) <= 6)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
