--[[
	Step 21 specification.

	Purchases. docs/13 names the hazard precisely: "returning PurchaseGranted
	before the profile is marked dirty (this loses purchases and it is the most
	expensive bug possible)."

	So the centre of this spec is an ORDERING, modelled as a state machine and
	crashed at every step to prove that no crash can either lose a purchase or
	grant one twice. Around it sit docs/07's ethics rules, which are the only
	part of the monetization design that can be measured rather than asserted
	by a person reading it.

	Run with:  ./tests/run.sh
]]

Color3 = { fromHex = function(h) return { Hex = h } end }
typeof = type

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua DailyConfig=src/ReplicatedStorage/SAD_Shared/Config/DailyConfig.lua ProductConfig=src/ReplicatedStorage/SAD_Shared/Config/ProductConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua ConfigValidator=src/ReplicatedStorage/SAD_Shared/Config/ConfigValidator.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

for name, mod in pairs({ GameConfig = GameConfig, RarityConfig = RarityConfig,
	MutationConfig = MutationConfig, DinoConfig = DinoConfig, UpgradeConfig = UpgradeConfig,
	RebirthConfig = RebirthConfig, DailyConfig = DailyConfig, ProductConfig = ProductConfig,
	ZoneConfig = ZoneConfig }) do
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
	else failed = failed + 1; print(string.format("  FAIL %-52s got %.4f want ~%.4f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

local function profile(overrides)
	local data = { Upgrades = {}, Defences = {}, Dinos = {}, Eggs = {}, Index = {},
		Gamepasses = {}, Boosts = {}, Items = {}, Rebirths = 0, Fossils = 0, DNA = 0,
		LuckNodes = 0, BonusDinoSlots = 0, BonusVaultSlots = 0, ProcessedReceipts = {},
		RobuxSpent = 0, LastSeen = 0, BankedFossils = 0, BankedAt = 0, BankedRate = 0,
		Stats = { RarestRarity = "common" } }
	for k, v in pairs(overrides or {}) do data[k] = v end
	return data
end

------------------------------------------------------------------ the ordering
section("A receipt cannot be lost or granted twice (docs/13's hazard)")

--[[
	The real ProcessReceipt in four steps. Modelled here so the ordering can be
	crashed at every point - which is the only way to test a guarantee that is
	entirely about what happens when the server dies.

	  1. profile not loaded -> NotProcessedYet
	  2. receipt in the ring -> PurchaseGranted, WITHOUT granting again
	  3. record and grant in ONE write
	  4. save, then return PurchaseGranted
]]
local GRANTED, RETRY = "PurchaseGranted", "NotProcessedYet"

--- `crashAt` aborts after that numbered step, as a server dying would.
local function processReceipt(world, receiptId, crashAt)
	local data = world.Profile
	if not data then
		return RETRY
	end
	if crashAt == 1 then return nil end

	for _, id in ipairs(data.ProcessedReceipts) do
		if id == receiptId then
			return GRANTED
		end
	end
	if crashAt == 2 then return nil end

	-- One write: the receipt and the grant land together or not at all.
	table.insert(data.ProcessedReceipts, receiptId)
	world.Fossils += 1000
	if crashAt == 3 then return nil end

	world.Saved = deepCopyReceipts(data.ProcessedReceipts)
	if crashAt == 4 then return nil end

	return GRANTED
end

function deepCopyReceipts(list)
	local copy = {}
	for index, value in ipairs(list) do copy[index] = value end
	return copy
end

local function newWorld()
	return { Profile = profile(), Fossils = 0, Saved = nil }
end

-- The happy path.
local world = newWorld()
eq("a clean receipt is granted", processReceipt(world, "r1"), GRANTED)
eq("...and paid once", world.Fossils, 1000)

-- Roblox retrying an already-granted receipt.
eq("a retry is granted again", processReceipt(world, "r1"), GRANTED)
eq("...but not paid again", world.Fossils, 1000)
for _ = 1, 20 do processReceipt(world, "r1") end
eq("twenty retries change nothing", world.Fossils, 1000)

--[[
	No profile means no durable record, so granting would be a purchase that
	vanishes when the session ends. Roblox retries instead.
]]
local unloaded = { Profile = nil, Fossils = 0 }
eq("an unloaded profile retries", processReceipt(unloaded, "r2"), RETRY)
eq("...and pays nothing", unloaded.Fossils, 0)

--[[
	Crashing at every step. The property that matters at each: either nothing
	was granted (so the retry grants cleanly) or the receipt is durable (so the
	retry is refused).
]]
for step = 1, 4 do
	local crashed = newWorld()
	processReceipt(crashed, "r3", step)

	local recorded = #crashed.Profile.ProcessedReceipts > 0
	local paid = crashed.Fossils > 0

	-- The invariant: never paid without being recorded.
	ok(string.format("crash after step %d: never paid unrecorded", step),
		not paid or recorded)

	-- And the retry lands exactly once either way.
	processReceipt(crashed, "r3")
	eq(string.format("crash after step %d: paid exactly once after the retry", step),
		crashed.Fossils, 1000)
end

--[[
	The reverse ordering, for contrast: grant first, record after. Crashing
	between them pays twice - which is the bug docs/13 is warning about, and it
	is only visible if the two orderings are compared.
]]
local function wrongOrder(world, receiptId, crashAfterGrant)
	local data = world.Profile
	for _, id in ipairs(data.ProcessedReceipts) do
		if id == receiptId then return GRANTED end
	end
	world.Fossils += 1000
	if crashAfterGrant then return nil end
	table.insert(data.ProcessedReceipts, receiptId)
	return GRANTED
end

local wrong = newWorld()
wrongOrder(wrong, "r4", true) -- crashed between grant and record
wrongOrder(wrong, "r4") -- Roblox retries
eq("granting before recording pays twice", wrong.Fossils, 2000)
ok("...which is why the order is the guarantee", wrong.Fossils ~= 1000)

--[[
	docs/10 §2 bounds ProcessedReceipts at 100. An unbounded ring grows until a
	DataStore write fails, which is the worst failure mode - late, and looking
	like nothing.
]]
local RING = 100
local ringed = profile()
for index = 1, 250 do
	table.insert(ringed.ProcessedReceipts, "r" .. index)
	while #ringed.ProcessedReceipts > RING do
		table.remove(ringed.ProcessedReceipts, 1)
	end
end
eq("the ring stays at 100", #ringed.ProcessedReceipts, RING)
eq("...keeping the most recent", ringed.ProcessedReceipts[RING], "r250")
eq("...and dropping the oldest", ringed.ProcessedReceipts[1], "r151")

------------------------------------------------------------------ catalogue
section("The catalogue (docs/07 §2-3, docs/12's V1 scope)")

eq("V1 ships 6 gamepasses", ProductConfig.CountPasses(), 6)
eq("V1 ships 8 developer products", ProductConfig.CountProducts(), 8)

local PASSES = {
	{ "vip", 499 }, { "doubleIncome", 799 }, { "luckyPlayer", 649 },
	{ "dinoSlots6", 399 }, { "incubators2", 349 }, { "fastHatch", 299 },
}
for _, row in ipairs(PASSES) do
	local entry = ProductConfig.GetPass(row[1])
	ok("gamepass exists: " .. row[1], entry ~= nil)
	eq(row[1] .. " costs " .. row[2] .. " R$", entry.Robux, row[2])
end
eq("every published pass is asserted", #PASSES, ProductConfig.CountPasses())

--[[
	docs/07 §2: "Deliberately no bundle above 799 - large single prices are how
	children's games get bad press." And docs/07 §5's ladder: impulse at 25-99,
	considered at 149-299, committed at 399-799 and capped there.
]]
local dearest = 0
for _, entry in pairs(ProductConfig.Gamepasses) do dearest = math.max(dearest, entry.Robux) end
for _, entry in pairs(ProductConfig.Products) do dearest = math.max(dearest, entry.Robux) end
eq("nothing costs more than 799 R$", dearest, 799)

local impulse, total = 0, 0
for _, entry in pairs(ProductConfig.Products) do
	total += 1
	if entry.Robux <= 99 then impulse += 1 end
end
print(string.format("  %d of %d products are impulse-priced (<= 99 R$)", impulse, total))
ok("most products sit in the impulse tier", impulse > total / 2)

------------------------------------------------------------------ no ids
section("No asset ids are invented")

--[[
	The Roblox experience does not exist yet (PROGRESS.md's open question #1).
	A plausible-looking id is a purchase prompt that fails silently or, worse,
	one that charges for somebody else's product.
]]
local configured, unconfigured = 0, 0
for _, group in ipairs({ ProductConfig.Gamepasses, ProductConfig.Products }) do
	for _, entry in pairs(group) do
		if ProductConfig.IsConfigured(entry) then configured += 1 else unconfigured += 1 end
	end
end
print(string.format("  %d configured, %d awaiting an id from the live place",
	configured, unconfigured))

eq("nothing is sellable yet", configured, 0)
eq("...and everything is declared", unconfigured, 14)

eq("an unconfigured entry is refused", ProductConfig.IsConfigured({ AssetId = 0 }), false)
eq("a real id is accepted", ProductConfig.IsConfigured({ AssetId = 123456 }), true)
eq("a negative id is refused", ProductConfig.IsConfigured({ AssetId = -1 }), false)
eq("looking up id 0 finds nothing", (ProductConfig.ByAssetId(0)), nil)

--[[
	And the validator must WARN rather than fail. A game with no store has to
	boot and be entirely playable, because docs/07 §1 rule 1 guarantees every
	paid effect exists free at lower magnitude.
]]
local report = ConfigValidator.Run({
	Rarity = RarityConfig, Mutation = MutationConfig, Dino = DinoConfig,
	Zone = ZoneConfig, Upgrade = UpgradeConfig, Product = ProductConfig,
})
eq("an unconfigured catalogue does not fail the boot", #report.errors, 0)
ok("...but it does warn", #report.warnings > 0)

-- A duplicate id, on the other hand, is a real error: it charges for the
-- wrong thing.
ProductConfig.Gamepasses.vip.AssetId = 111
ProductConfig.Gamepasses.doubleIncome.AssetId = 111
local clashing = ConfigValidator.Run({
	Rarity = RarityConfig, Mutation = MutationConfig, Dino = DinoConfig,
	Zone = ZoneConfig, Upgrade = UpgradeConfig, Product = ProductConfig,
})
ok("a duplicate asset id fails the boot", #clashing.errors > 0)

-- And a configured id resolves both ways.
ProductConfig.Gamepasses.doubleIncome.AssetId = 222
local kind, found = ProductConfig.ByAssetId(222)
eq("a configured id resolves to its kind", kind, "gamepass")
eq("...and its entry", found and found.Key, "doubleIncome")

ProductConfig.Gamepasses.vip.AssetId = 0
ProductConfig.Gamepasses.doubleIncome.AssetId = 0

-------------------------------------------------------------- ethics rules
section("docs/07 §1's ethics rules, where they can be measured")

--[[
	Rule 1: "No gamepass gates progression. Every paid effect exists free at
	lower magnitude, or is convenience only."

	Measurable: every numeric gamepass effect must correspond to something a
	free player can also raise.
]]
local FREE_EQUIVALENT = {
	IncomeMultiplier = "the Feeding Trough upgrade track",
	Luck = "the Egg Sense track, rebirths and Luck Nodes",
	MutLuck = "the Incubator Genetics track and rebirths",
	DinoSlots = "the Dino Slots track and rebirths",
	Incubators = "the Incubators track",
	IncubationMultiplier = "the Incubator Speed track",
	OfflineRate = "no free equivalent - but it is a rate on income already earned",
	AutoCollectFromStart = "free at rebirth 2",
	DailyFossils = "the daily chest",
}
for key, entry in pairs(ProductConfig.Gamepasses) do
	for effectName in pairs(entry.Effects) do
		ok(string.format("%s's %s has a free path", key, effectName),
			FREE_EQUIVALENT[effectName] ~= nil)
	end
end

--[[
	Rule 2: "No paid invulnerability. Shields are capped at 2 hours stacked
	regardless of spend."

	The Park Shield product is 30 minutes, and StealService's stack cap is what
	stops four of them buying two hours and a bit.
]]
local shield = ProductConfig.GetProduct("parkShield")
eq("the shield product is 30 minutes", shield.Grant.Shield, 1800)
eq("the stack cap is 2 hours", GameConfig.ShieldStackCapSecs, 7200)
ok("four shields reach the cap on paper", shield.Grant.Shield * 4 >= GameConfig.ShieldStackCapSecs)

local stacked, now = 0, 1000000
for _ = 1, 10 do
	stacked = math.min(math.max(stacked, now) + shield.Grant.Shield, now + GameConfig.ShieldStackCapSecs)
end
eq("...but ten of them still cannot", stacked - now, GameConfig.ShieldStackCapSecs)

--[[
	Rule 4: "No paid-only rarity. There is no dinosaur obtainable ONLY with
	Robux."

	Measurable: no product may grant a species or a rarity that is not also
	reachable from a nest.
]]
local paidRarities = 0
for _, entry in pairs(ProductConfig.Products) do
	local granted = entry.Grant and entry.Grant.Egg
	if granted then
		paidRarities += 1
		local reachable = false
		for _, zoneId in ipairs(ZoneConfig.Order) do
			local weights = RarityConfig.WeightsForZone(zoneId)
			if weights and (weights[granted] or 0) > 0 then reachable = true end
		end
		ok("a paid egg's rarity is reachable free: " .. granted, reachable)
	end
	ok("no product grants a specific species: " .. entry.Key,
		entry.Grant == nil or entry.Grant.SpeciesId == nil)
end

------------------------------------------------------- the stacking cap
section("The x2.6 income cap (docs/07 §2)")

eq("the cap is x2.6", ProductConfig.IncomeStackCap, 2.6)

local none = profile()
local doubled = profile({ Gamepasses = { doubleIncome = true } })
near("no passes is x1", ProductConfig.EffectTotal(none.Gamepasses, "IncomeMultiplier", 1), 1, 0.0001)
near("Double Income is x2", ProductConfig.EffectTotal(doubled.Gamepasses, "IncomeMultiplier", 1), 2, 0.0001)

--[[
	Every pass at once - and this is where the published number and the shipped
	catalogue part company, in exactly the way the x40 mutation cap and the 9s
	raid hold did.

	docs/07 §2 promises a full-catalogue buyer is "roughly a 2.6x faster player,
	not a 20x one", and it says that of the FULL twelve-pass catalogue. V1 ships
	six, and exactly one of them - Double Income - touches IncomeMultiplier at
	all. So the direct channel multiplies to precisely 2.0 and math.min never
	binds: the cap is correct, shipped, and currently unreached.

	Asserting 2.6 here would have been asserting the doc instead of the game, so
	this measures both: what V1 reaches now, and that the cap does its job the
	moment a second income pass exists.
]]
local everything = profile()
for key in pairs(ProductConfig.Gamepasses) do everything.Gamepasses[key] = true end
near("V1's whole catalogue reaches x2.0, not the cap",
	ProductConfig.EffectTotal(everything.Gamepasses, "IncomeMultiplier", 1), 2.0, 0.0001)
ok("...because Double Income is V1's only income pass", (function()
	local n = 0
	for _, entry in pairs(ProductConfig.Gamepasses) do
		if entry.Effects.IncomeMultiplier then n += 1 end
	end
	return n == 1
end)())

-- The cap binds the moment a second one ships. Simulated on a copy of the
-- catalogue so the shipped table is untouched.
do
	local restore = ProductConfig.Gamepasses.parkTheme
	ProductConfig.Gamepasses.parkTheme = { Key = "parkTheme", Effects = { IncomeMultiplier = 1.5 } }
	local capped = ProductConfig.EffectTotal(
		{ doubleIncome = true, parkTheme = true }, "IncomeMultiplier", 1)
	near("a second income pass would give x3.0 uncapped, so the cap trims to x2.6",
		capped, 2.6, 0.0001)
	ProductConfig.Gamepasses.parkTheme = restore
end

--[[
	And what V1 reaches must reach the actual income, not just the helper. A cap
	that nothing reads is the decorative failure this project keeps removing.
]]
local dino = { SpeciesId = "trex", Rarity = "epic", Stars = 1, Placed = true }
local plain = profile({ Dinos = { a = dino } })
local paid = profile({ Dinos = { a = dino } })
for key in pairs(ProductConfig.Gamepasses) do paid.Gamepasses[key] = true end

local plainRate = Economy.ParkIncomeRate(plain)
local paidRate = Economy.ParkIncomeRate(paid)
print(string.format("  the same Epic earns %.1f free and %.1f with every pass (x%.2f)",
	plainRate, paidRate, paidRate / plainRate))
near("a full-catalogue buyer earns 2.0x per dinosaur, not 20x", paidRate / plainRate, 2.0, 0.01)

--[[
	Per DINOSAUR is not the whole story, and docs/07 §2's "2.6x faster player"
	is the honest frame for it: the passes also buy +8 slots, so a buyer fields
	more dinosaurs as well as better-paid ones. That channel has no cap, so it
	is measured rather than assumed - across progression, because the ratio is
	not constant.

	It is worst on a brand-new account (4 free slots vs 12) and converges on the
	published number as the free player buys the slot track they can already
	afford. That shape is the right one for the ethics rules: the paid advantage
	is largest where the free path has barely started and smallest where players
	actually live.
]]
do
	local maxSlots = UpgradeConfig.Get("dinoSlots").MaxLevel
	print("  overall multiple, income x slots, by the free player's slot track:")
	local worst
	for _, level in ipairs({ 0, 5, 12, maxSlots }) do
		local free = profile({ Upgrades = { dinoSlots = level } })
		local buyer = profile({ Upgrades = { dinoSlots = level } })
		for key in pairs(ProductConfig.Gamepasses) do buyer.Gamepasses[key] = true end

		local freeSlots, paidSlots = Stats.DinoSlots(free), Stats.DinoSlots(buyer)
		local whole = (paidRate / plainRate) * (paidSlots / freeSlots)
		worst = worst or whole
		print(string.format("    slot level %2d: %2d slots vs %2d  ->  x%.2f",
			level, freeSlots, paidSlots, whole))
	end

	local capped = profile({ Upgrades = { dinoSlots = maxSlots } })
	local cappedBuyer = profile({ Upgrades = { dinoSlots = maxSlots } })
	for key in pairs(ProductConfig.Gamepasses) do cappedBuyer.Gamepasses[key] = true end
	local settled = (paidRate / plainRate)
		* (Stats.DinoSlots(cappedBuyer) / Stats.DinoSlots(capped))

	ok("at the slot track's end a full-catalogue buyer is under x2.6, as docs/07 §2 says",
		settled <= ProductConfig.IncomeStackCap)
	ok("...but on a fresh account the uncapped slot channel exceeds it",
		worst > ProductConfig.IncomeStackCap)
end

-- Additive effects add rather than multiply, and are not capped by the income rule.
eq("slots from two passes add",
	ProductConfig.EffectTotal({ vip = true, dinoSlots6 = true }, "DinoSlots", 0), 8)
eq("incubators likewise",
	ProductConfig.EffectTotal({ vip = true, incubators2 = true }, "Incubators", 0), 3)

--[[
	And they must reach Stats, or the pass is a refund. Checked against the
	same functions the game reads on every placement and every hatch.
]]
local vip = profile({ Gamepasses = { vip = true, dinoSlots6 = true } })
eq("Stats sees the slots", Stats.DinoSlots(vip), Stats.DinoSlots(profile()) + 8)
eq("Stats sees the incubators", Stats.Incubators(vip), Stats.Incubators(profile()) + 1)
near("Lucky Player reaches Luck",
	Stats.Luck(profile({ Gamepasses = { luckyPlayer = true } })) - Stats.Luck(profile()),
	0.35, 0.0001)
near("Fast Hatch reaches the incubation multiplier",
	Stats.IncubationMult(profile({ Gamepasses = { fastHatch = true } })),
	Stats.IncubationMult(profile()) * 0.75, 0.0001)

--------------------------------------------------------------- fossil packs
section("Fossil Packs scale with the buyer (docs/07 §3)")

--[[
	"Fossil Packs are scaled to the buyer's own income, not fixed amounts. This
	is the single most important economy decision in the monetization design."

	The property that makes that true: the same pack is worth the same NUMBER
	OF MINUTES to everyone, so it is never a shortcut past a wall.
]]
eq("small is 10 minutes", ProductConfig.PackSeconds.small, 600)
eq("medium is 45 minutes", ProductConfig.PackSeconds.medium, 2700)

local FLOOR = 2500
local function packValue(data, size)
	return math.max(math.floor(Economy.ParkIncomeRate(data) * ProductConfig.PackSeconds[size]), FLOOR)
end

local beginner = profile({ Dinos = { a = { SpeciesId = "compsognathus", Rarity = "common", Stars = 1, Placed = true } } })
local veteran = profile({ Rebirths = 10, Dinos = {} })
for index = 1, 20 do
	veteran.Dinos["d" .. index] = { SpeciesId = "trex", Rarity = "legendary", Stars = 3, Placed = true }
end

local beginnerPack = packValue(beginner, "medium")
local veteranPack = packValue(veteran, "medium")
print(string.format("  a Medium pack is %s to a beginner and %s to a rebirth-10 veteran",
	Format.Number(beginnerPack), Format.Number(veteranPack)))

ok("the veteran's pack is far larger", veteranPack > beginnerPack * 100)
near("...but both are 45 minutes of their own income",
	veteranPack / Economy.ParkIncomeRate(veteran), 2700, 1)

--[[
	A player with no park at all is exactly who a pack is least useful to, so
	the floor is what stops it paying literally nothing.
]]
eq("a player with no park gets the floor", packValue(profile(), "small"), FLOOR)
ok("...which is a real amount", FLOOR > 0)

--------------------------------------------------------------- server-wide
section("Server purchases benefit everyone (docs/07 §1 rule 6, §4)")

local serverProducts = {}
for key, entry in pairs(ProductConfig.Products) do
	if entry.ServerWide then table.insert(serverProducts, key) end
end
table.sort(serverProducts)
eq("V1 ships one server product", #serverProducts, 1)
eq("...and it is the 2x Luck one", serverProducts[1], "serverLuck")

local server = ProductConfig.GetProduct("serverLuck")
ok("it credits the buyer by name", server.Announcement ~= nil
	and string.find(server.Announcement, "%%s") ~= nil)
ok("it grants something", server.Grant ~= nil)

--[[
	docs/07 §4: the Thanks reward goes to the THANKER, "so people actually
	press it". Paying the buyer would turn gratitude into something they profit
	from twice.
]]
eq("thanks pays 500 Fossils", ProductConfig.ThanksReward, 500)
ok("...within a bounded window", ProductConfig.ThanksWindowSecs > 0
	and ProductConfig.ThanksWindowSecs <= 300)

--[[
	And it must be worth pressing without being worth farming: 500 Fossils is
	generous at minute five and negligible by hour two, which is the right
	shape for a social nudge.
]]
local minuteFive = 6 -- docs/05 §8's 5-minute row
print(string.format("  a Thanks is %.0f seconds of a new player's income and %.2f of an hour-2 player's",
	ProductConfig.ThanksReward / minuteFive, ProductConfig.ThanksReward / 2100))
ok("worth pressing early", ProductConfig.ThanksReward / minuteFive > 30)
ok("not worth farming later", ProductConfig.ThanksReward / 2100 < 1)

--------------------------------------------------------------- VIP offline
section("VIP's offline rate reaches the offline calculation")

eq("the default offline rate is 60%", Economy.OfflineRate, 0.60)
near("a normal player earns 60%", Economy.OfflineRateFor(profile()), 0.60, 0.0001)
near("VIP earns 100%", Economy.OfflineRateFor(profile({ Gamepasses = { vip = true } })), 1.0, 0.0001)

local away = profile({ Dinos = { a = dino }, LastSeen = 1000 })
local vipAway = profile({ Dinos = { a = dino }, LastSeen = 1000, Gamepasses = { vip = true } })
local plainEarned = Economy.OfflineEarnings(away, 1000 + 3600)
local vipEarned = Economy.OfflineEarnings(vipAway, 1000 + 3600)
near("an hour away pays VIP exactly 1/0.6 as much", vipEarned / plainEarned, 1 / 0.6, 0.001)

------------------------------------------------------- the store's listing
section("Every purchasable thing is actually listed for sale")

--[[
	The store's order lives in ProductConfig rather than in the controller for
	the same reason the replication allowlist and RebirthConfig's three lists
	do: an order the client owns cannot be checked against the catalogue, and a
	pass added without a listing would simply never appear for sale - the
	registered-but-inert failure this project keeps removing.
]]
local function coverage(order, catalogue, label)
	local seen = {}
	for _, key in ipairs(order) do
		ok(label .. " lists a real key: " .. key, catalogue[key] ~= nil)
		ok(label .. " lists " .. key .. " once", seen[key] == nil)
		seen[key] = true
	end
	for key in pairs(catalogue) do
		ok(label .. " covers " .. key, seen[key] == true)
	end
end
coverage(ProductConfig.PassOrder, ProductConfig.Gamepasses, "PassOrder")
coverage(ProductConfig.ProductOrder, ProductConfig.Products, "ProductOrder")

eq("PassOrder is the whole catalogue", #ProductConfig.PassOrder, ProductConfig.CountPasses())
eq("ProductOrder is the whole catalogue", #ProductConfig.ProductOrder, ProductConfig.CountProducts())
eq("VIP leads the passes", ProductConfig.PassOrder[1], "vip")
ok("the server boost leads the products, per docs/07 §4",
	ProductConfig.GetProduct(ProductConfig.ProductOrder[1]).ServerWide == true)

--[[
	docs/07 §1 rule 7's panel needs somewhere to record that it has been shown,
	or it becomes a nag. It rides in Settings, so it must be in both the schema
	and the template - the drift `step2_spec` checks for generally.
]]
ok("SeenStoreNotice is in the settings schema",
	GameConfig.SettingsSchema.SeenStoreNotice ~= nil)
eq("...as a boolean", GameConfig.SettingsSchema.SeenStoreNotice.Type, "boolean")

--[[
	Every effect any pass grants must have a declared combination mode. This is
	finding 36's guard, asserted here as well as at require time so the failure
	names the effect rather than a stack trace at boot.
]]
for key, entry in pairs(ProductConfig.Gamepasses) do
	for effectName, value in pairs(entry.Effects) do
		if type(value) == "number" then
			ok(string.format("%s's %s declares a mode", key, effectName),
				ProductConfig.EffectModes[effectName] ~= nil)
		end
	end
end

eq("OfflineRate replaces rather than adds", ProductConfig.EffectModes.OfflineRate, "max")
near("...so two offline-rate passes would not stack past 100%",
	ProductConfig.EffectTotal({ vip = true }, "OfflineRate", Economy.OfflineRate), 1.0, 0.0001)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
