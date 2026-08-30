--[[
	Step 22 specification.

	Leaderboards. docs/13 names two hazards: "writing every change (budget
	exhaustion)" and "values above the OrderedDataStore 64-bit integer range".

	Both are arithmetic, so both can be measured rather than hoped for. The
	spec computes the actual request rate at every player count the game
	supports, drives the clamp with the values that break it, and simulates the
	throttle against a player whose Fossils change every second for an hour.

	The third thing measured here is the one that cannot be fixed with code:
	OrderedDataStore has no rank query, so the spec pins down exactly what a
	player outside the top 100 is shown.

	Run with:  ./tests/run.sh
]]

Color3 = { fromHex = function(h) return { Hex = h } end }
typeof = type

-- ParkConfig does real vector arithmetic at load, and the Colosseum's clearance
-- is measured against its ring radius.
local Vector3MT = {}
Vector3MT.__index = Vector3MT
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT) end
Vector3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3 = { new = v3, zero = v3(0, 0, 0) }

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua DailyConfig=src/ReplicatedStorage/SAD_Shared/Config/DailyConfig.lua ProductConfig=src/ReplicatedStorage/SAD_Shared/Config/ProductConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua LeaderboardConfig=src/ReplicatedStorage/SAD_Shared/Config/LeaderboardConfig.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

for name, mod in pairs({ GameConfig = GameConfig, RarityConfig = RarityConfig,
	MutationConfig = MutationConfig, DinoConfig = DinoConfig, UpgradeConfig = UpgradeConfig,
	RebirthConfig = RebirthConfig, DailyConfig = DailyConfig, ProductConfig = ProductConfig,
	ZoneConfig = ZoneConfig,
	ParkConfig = ParkConfig, LeaderboardConfig = LeaderboardConfig }) do
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
		Stats = { RarestRarity = "common", EggsStolen = 0, PeakIncomePerSec = 0 } }
	for k, v in pairs(overrides or {}) do data[k] = v end
	return data
end

--------------------------------------------------------------- the catalogue
section("The boards docs/12 puts in V1")

eq("four boards ship", LeaderboardConfig.Count(), 4)

--[[
	docs/12's V1 list, by name: Richest, Highest Income, Most Eggs Stolen,
	Highest Rebirth. Asserted by id so a rename has to be deliberate.
]]
for _, id in ipairs({ "richest", "income", "eggsStolen", "rebirths" }) do
	ok("ships: " .. id, LeaderboardConfig.Get(id) ~= nil)
end

--[[
	docs/02 §1.1 and docs/08 §3 both describe EIGHT boards. V1 ships four, and
	that difference is deliberate rather than forgotten - the same shape as the
	Index's 60-species denominator and docs/07's twelve-pass catalogue.
]]
print(string.format("  V1 ships %d boards; docs/02 §1.1 and docs/08 §3 describe 8",
	LeaderboardConfig.Count()))

-- Every board must have the pieces the service and the UI both read.
for _, id in ipairs(LeaderboardConfig.Order) do
	local entry = LeaderboardConfig.Get(id)
	ok(id .. " has a store name", type(entry.Store) == "string" and #entry.Store > 0)
	ok(id .. " names a SAD_LB_ store", entry.Store:sub(1, 7) == "SAD_LB_")
	ok(id .. " has a display name", type(entry.DisplayName) == "string")
	ok(id .. " has a blurb", type(entry.Blurb) == "string")
	ok(id .. " has a ValueOf", type(entry.ValueOf) == "function")
	ok(id .. " has a format", entry.Format ~= nil)
end

--[[
	docs/10 §4 reserves the store names. A board writing to a store the schema
	does not list is a board whose data nobody can find later.
]]
local RESERVED = {
	richest = "SAD_LB_Fossils",
	income = "SAD_LB_Income",
	eggsStolen = "SAD_LB_EggsStolen",
	rebirths = "SAD_LB_Rebirths",
}
for id, store in pairs(RESERVED) do
	eq("docs/10 §4's store for " .. id, LeaderboardConfig.Get(id).Store, store)
end

-- Two boards sharing a store would silently overwrite each other.
local seenStores = {}
for _, id in ipairs(LeaderboardConfig.Order) do
	local store = LeaderboardConfig.Get(id).Store
	ok("store is unique: " .. store, seenStores[store] == nil)
	seenStores[store] = true
end

ok("the statue board is one that ships",
	LeaderboardConfig.Get(LeaderboardConfig.StatueBoard) ~= nil)
eq("three statues, per docs/02 §1.1", LeaderboardConfig.StatueCount, 3)

--------------------------------------------------------------- what it reads
section("Each board measures what docs/10's column says it does")

local rich = profile({ Fossils = 1234567 })
eq("richest reads Fossils", LeaderboardConfig.ValueFor("richest", rich), 1234567)

local earner = profile({ Stats = { PeakIncomePerSec = 480, EggsStolen = 0 } })
eq("income reads PeakIncomePerSec", LeaderboardConfig.ValueFor("income", earner), 480)

--[[
	PEAK, not current, and this is the assertion that matters: a player who
	sells their whole park to fund a rebirth must not drop off the board. Their
	current rate is zero and their peak is not.
]]
local sold = profile({ Dinos = {}, Stats = { PeakIncomePerSec = 480, EggsStolen = 0 } })
eq("...so an emptied park keeps its place", LeaderboardConfig.ValueFor("income", sold), 480)
eq("...even though it currently earns nothing", Economy.ParkIncomeRate(sold), 0)

local thief = profile({ Stats = { EggsStolen = 91, PeakIncomePerSec = 0 } })
eq("eggsStolen reads Stats.EggsStolen", LeaderboardConfig.ValueFor("eggsStolen", thief), 91)

eq("rebirths reads Rebirths", LeaderboardConfig.ValueFor("rebirths", profile({ Rebirths = 7 })), 7)

-- A fresh profile is zero everywhere and never nil: a nil would be written to
-- the store as a delete, quietly removing the player from the board.
for _, id in ipairs(LeaderboardConfig.Order) do
	eq("a fresh profile is 0 on " .. id, LeaderboardConfig.ValueFor(id, profile()), 0)
end

-- And a nil profile must not throw. The write loop can race a leaving player.
for _, id in ipairs(LeaderboardConfig.Order) do
	local okCall, value = pcall(LeaderboardConfig.ValueFor, id, nil)
	ok("no profile is survivable on " .. id, okCall and value == 0)
end

--------------------------------------------------------------- the clamp
section("The integer ceiling (docs/13's second hazard)")

--[[
	docs/13 says "store math.min(value, 9e18)". 9e18 is under 2^63 but is NOT
	exactly representable as a double, and is far above 2^53 where consecutive
	integers stop being distinguishable - so a value near it would already have
	been rounded before the store ever saw it. 2^53 is the largest ceiling
	where every integer below survives intact.
]]
eq("the ceiling is 2^53", LeaderboardConfig.MaxValue, 2 ^ 53)
ok("...which is under the int64 limit docs/13 cites", LeaderboardConfig.MaxValue < 9.22e18)
ok("...and every integer below it is exact",
	LeaderboardConfig.MaxValue - 1 ~= LeaderboardConfig.MaxValue)

eq("an ordinary value passes through", LeaderboardConfig.StoreValue(1234), 1234)
eq("a fraction floors, never rounds up", LeaderboardConfig.StoreValue(1234.9), 1234)
eq("a huge value clamps", LeaderboardConfig.StoreValue(1e30), LeaderboardConfig.MaxValue)
eq("infinity clamps", LeaderboardConfig.StoreValue(math.huge), LeaderboardConfig.MaxValue)
eq("negative infinity floors at zero", LeaderboardConfig.StoreValue(-math.huge), 0)
eq("NaN is zero, not an error", LeaderboardConfig.StoreValue(0 / 0), 0)
eq("a negative is zero", LeaderboardConfig.StoreValue(-5), 0)
eq("a non-number is zero", LeaderboardConfig.StoreValue("nope"), 0)
eq("nil is zero", LeaderboardConfig.StoreValue(nil), 0)

eq("the economy uses the same ceiling", Economy.MaxFossils, LeaderboardConfig.MaxValue)

--[[
	═══ THE REBIRTH CURVE OUTGROWS THE NUMBER SYSTEM AT 16 ═════════════════════
	The ceiling ought to be past anything the game can reach. It is not, and
	that is worth knowing rather than asserting away: docs/05 §6's cost curve is
	250,000 x 5.2^n, and 5.2^n passes 2^53 between rebirth 15 and 16.

	This is not the leaderboard's problem to solve. Above 2^53 a Lua double
	cannot represent consecutive integers at all, so a balance up there stops
	counting: earning a Fossil changes nothing and the player watches a frozen
	number. The board pinning everyone at the ceiling is the visible symptom of
	an economy that has already stopped working.

	So the spec measures where the curve crosses, asserts the ceiling covers
	every rebirth below it, and records the crossing. Recorded in PROGRESS.md
	as finding 39.
	═══════════════════════════════════════════════════════════════════════════
]]
local crossing
for n = 1, 30 do
	if RebirthConfig.CostOf(n) > LeaderboardConfig.MaxValue then
		crossing = n
		break
	end
end
print(string.format("  the rebirth curve passes the ceiling at rebirth %d (%.3g vs %.3g)",
	crossing, RebirthConfig.CostOf(crossing), LeaderboardConfig.MaxValue))

eq("the curve first exceeds the ceiling at rebirth 16", crossing, 16)
ok("...so every rebirth up to 15 is representable exactly",
	RebirthConfig.CostOf(15) < LeaderboardConfig.MaxValue)
ok("...and rebirth 20 is past int64 entirely, not just past this ceiling",
	RebirthConfig.CostOf(20) > 9.22e18)

-- Whatever happens up there, the clamp must saturate rather than corrupt.
eq("a balance past the ceiling stores as the ceiling",
	LeaderboardConfig.StoreValue(RebirthConfig.CostOf(20)), LeaderboardConfig.MaxValue)
eq("...and the economy clamps it the same way",
	Economy.ClampFossils(RebirthConfig.CostOf(20)), LeaderboardConfig.MaxValue)

--------------------------------------------------------------- the budget
section("Request budgets (docs/13's first hazard)")

eq("writes are throttled to 5 minutes, per docs/10 §4",
	LeaderboardConfig.WriteIntervalSecs, 300)
eq("reads floor at 60 seconds, per docs/10 §4", LeaderboardConfig.ReadIntervalSecs, 60)
eq("a page is 100, per docs/08 §3", LeaderboardConfig.PageSize, 100)

print("  players   writes/min  budget   reads/min  budget   interval")
for _, players in ipairs({ 1, 2, 10, 30, 50 }) do
	local check = LeaderboardConfig.BudgetCheck(players)
	print(string.format("  %7d   %10.1f  %6d   %9.2f  %6d   %6.1fs",
		players, check.WritesPerMin, check.WriteBudget,
		check.ReadsPerMin, check.ReadBudget, check.ReadIntervalSecs))
	ok(string.format("fits at %d players", players), check.Fits)
end

-- docs/13's own test case.
local thirty = LeaderboardConfig.BudgetCheck(30)
ok("at 30 players writes use under a tenth of the budget",
	thirty.WritesPerMin < thirty.WriteBudget * 0.1)

--[[
	═══ THE BINDING CONSTRAINT IS AN EMPTY SERVER, NOT A FULL ONE ══════════════
	Writes scale with players and so does the write budget, so a full server is
	never the problem. READS do not scale with players - the cache is
	server-wide - while the read budget does. So the tightest case is one
	player, and it is the one nobody tests.
]]
local alone = LeaderboardConfig.BudgetCheck(1)
local full = LeaderboardConfig.BudgetCheck(50)
ok("read headroom is tightest on a nearly empty server",
	alone.ReadHeadroom < full.ReadHeadroom)
ok("...and still fits at one player", alone.Fits)

--[[
	And the eight-board build-out docs/02 describes would NOT fit at 60 s on a
	one-player server: 8 reads/min against a budget of 5 + 2 = 7. The interval
	is derived from the board count for exactly this reason, so the build-out
	slows itself down instead of silently failing.
]]
do
	local naive = 8 * (60 / 60) -- eight boards, fixed 60 s
	local budgetAtOne = LeaderboardConfig.ReadBudgetBase + LeaderboardConfig.ReadBudgetPerPlayer
	ok("eight boards at a fixed 60s would exceed a one-player read budget",
		naive > budgetAtOne)

	--[[
		Simulated by lengthening Order IN PLACE and then removing what was
		added. Reassigning the field would leave `Count` reading a different
		list from `ReadIntervalFor` - which is exactly the bug this spec found
		in the config's first draft, where `Count` closed over a local.
	]]
	local before = #LeaderboardConfig.Order
	for index = 1, 4 do table.insert(LeaderboardConfig.Order, "future" .. index) end
	eq("the simulated catalogue is eight", LeaderboardConfig.Count(), 8)

	local stretched = LeaderboardConfig.ReadIntervalFor(1)
	print(string.format("  with the full 8 boards a one-player server reads every %.0fs", stretched))
	ok("...so the derived interval stretches past 60s", stretched > 60)
	ok("...far enough to fit the budget",
		8 * (60 / stretched) <= budgetAtOne * LeaderboardConfig.ReadBudgetShare + 1e-9)

	for _ = 1, 4 do table.remove(LeaderboardConfig.Order) end
	eq("the catalogue is restored", #LeaderboardConfig.Order, before)
	eq("...and Count agrees with it", LeaderboardConfig.Count(), before)
	eq("...and V1 keeps docs/10's 60 seconds", LeaderboardConfig.ReadIntervalFor(1), 60)
end

--------------------------------------------------------------- the throttle
section("A player earning constantly still costs 4 writes an hour")

--[[
	The hazard, simulated. A player's Fossils change every second for an hour.
	A naive implementation writes 3,600 times per board - 14,400 requests -
	against a 70/min budget on a one-player server. The throttle plus the
	changed check has to bring that to one write per board per 5 minutes.
]]
local WRITE_INTERVAL = LeaderboardConfig.WriteIntervalSecs
local boardCount = LeaderboardConfig.Count()

local function simulate(seconds: number, changeEvery: number)
	local lastWriteAt = -math.huge
	local written = {}
	local requests = 0

	for t = 1, seconds do
		local data = profile({
			Fossils = math.floor(t / changeEvery) * 100,
			Rebirths = 0,
			Stats = { EggsStolen = 0, PeakIncomePerSec = 0 },
		})
		if (t - lastWriteAt) >= WRITE_INTERVAL then
			for _, id in ipairs(LeaderboardConfig.Order) do
				local value = LeaderboardConfig.ValueFor(id, data)
				if written[id] ~= value then
					written[id] = value
					requests += 1
				end
			end
			lastWriteAt = t
		end
	end
	return requests
end

local busy = simulate(3600, 1)
local idle = simulate(3600, math.huge)

print(string.format("  an hour of constant earning: %d requests (naive would be %d)",
	busy, 3600 * boardCount))
print(string.format("  an hour of standing still:   %d requests", idle))

--[[
	Twelve ticks in an hour. The first writes all four boards (nothing is
	stored yet); the eleven after it write only `richest`, because Fossils are
	the only value that moved. 4 + 11 = 15.

	That the first tick costs four and the rest cost one is the changed check
	earning its place - a throttle alone would spend four every tick forever.
]]
local ticks = 3600 / WRITE_INTERVAL
eq("twelve throttled ticks in an hour", ticks, 12)
eq("the first writes every board, the rest write only what moved",
	busy, boardCount + (ticks - 1))
-- 14,400 naive requests against 15. Stated as a measured ratio rather than a
-- round number, because the round number was wrong the first time.
print(string.format("  that is %.0fx fewer requests", 3600 * boardCount / busy))
ok("...which is over 900x fewer than writing every change",
	busy * 900 < 3600 * boardCount)

--[[
	And an idle player costs ONE round of writes - the first, which establishes
	the stored value - then nothing at all. That is the changed check doing the
	work the throttle cannot: a throttle alone would still write every 5
	minutes forever.
]]
eq("an idle player writes once and then never again", idle, boardCount)

-- The whole server's worst case against the budget it actually has.
do
	local perPlayerPerMin = boardCount * (60 / WRITE_INTERVAL)
	for _, players in ipairs({ 1, 10, 30, 50 }) do
		local used = perPlayerPerMin * players
		local budget = LeaderboardConfig.WriteBudgetBase
			+ LeaderboardConfig.WriteBudgetPerPlayer * players
		ok(string.format("worst-case writes fit at %d players", players), used <= budget)
	end
end

--------------------------------------------------------------- the rank
section("There is no rank query, and the UI must say so")

--[[
	The one thing in this step that cannot be solved with better code.
	`OrderedDataStore` returns pages; it has no "what rank is this key" call,
	and counting everyone above a player means paging the entire store.

	So the contract is: a real rank when the player is in the cached page, and
	no rank at all when they are not. Modelled here as the function the service
	and the controller both depend on.
]]
local function selfEntry(cachedEntries, userId, value)
	local rank = nil
	for _, row in ipairs(cachedEntries) do
		if row.UserId == userId then
			rank = row.Rank
			break
		end
	end
	return { Value = value, Rank = rank }
end

local page = {}
for index = 1, LeaderboardConfig.PageSize do
	table.insert(page, { UserId = 1000 + index, Value = 100000 - index, Rank = index })
end

local inPage = selfEntry(page, 1042, 99958)
eq("a player in the page gets their real rank", inPage.Rank, 42)

local outside = selfEntry(page, 99999, 12)
eq("a player outside it gets no rank at all", outside.Rank, nil)
eq("...but always gets their value", outside.Value, 12)

--[[
	The rank must come from the page, not be recomputed from the value - two
	players on the same value would otherwise both claim the same rank and the
	list would show two #7s.
]]
local tied = {}
for index = 1, 5 do
	table.insert(tied, { UserId = 2000 + index, Value = 500, Rank = index })
end
local first = selfEntry(tied, 2001, 500)
local last = selfEntry(tied, 2005, 500)
eq("ties keep their page order, first", first.Rank, 1)
eq("ties keep their page order, last", last.Rank, 5)

--------------------------------------------------------------- the Colosseum
section("The Colosseum fits in the plaza")

--[[
	Geometry, because a pillar overlapping the Bone Market or poking through a
	park is the kind of thing nobody notices until a player walks into it. The
	numbers come from WorldBuilder; the constraints come from ZoneConfig and
	ParkConfig.
]]
local COLOSSEUM_RADIUS = 160
local STATUE_RADIUS = 130
local BONE_MARKET_RADIUS = 60

local plotInnerEdge = ParkConfig.RingRadius() - ParkConfig.PlotSize * 0.5
print(string.format("  plaza reaches %d; the park ring's inner edge is %.0f",
	ZoneConfig.HubRadius, plotInnerEdge))

ok("the pillars are inside the plaza", COLOSSEUM_RADIUS + 20 < ZoneConfig.HubRadius)
ok("the pillars are inside the park ring", COLOSSEUM_RADIUS + 20 < plotInnerEdge)
ok("the statues are inside the pillars", STATUE_RADIUS < COLOSSEUM_RADIUS)
ok("both clear the Bone Market", STATUE_RADIUS - BONE_MARKET_RADIUS > 60)

--[[
	The pillars sit on an arc whose spacing is derived from the board count, so
	V1.4's four extra boards space themselves rather than stacking on top of
	the existing four. Checked at both counts.
]]
local function pillarPositions(count: number)
	local ARC, RADIUS = 70, COLOSSEUM_RADIUS
	local gaps = math.max(count - 1, 1)
	local out = {}
	for index = 1, count do
		local spread = if count == 1 then 0 else (index - 1) / gaps - 0.5
		local angle = math.rad(spread * ARC + 180)
		table.insert(out, { X = math.cos(angle) * RADIUS, Z = math.sin(angle) * RADIUS })
	end
	return out
end

for _, count in ipairs({ 1, 4, 8 }) do
	local positions = pillarPositions(count)
	local closest = math.huge
	for i = 1, #positions do
		for j = i + 1, #positions do
			local dx = positions[i].X - positions[j].X
			local dz = positions[i].Z - positions[j].Z
			closest = math.min(closest, math.sqrt(dx * dx + dz * dz))
		end
	end
	if count > 1 then
		print(string.format("  %d pillars: closest pair %.1f studs apart", count, closest))
		-- A pillar is 20 wide, so anything above that cannot overlap.
		ok(string.format("%d pillars do not overlap", count), closest > 20)
	else
		ok("a single pillar is placeable", #positions == 1)
	end
end

--------------------------------------------------------------- the freshness
section("Stale data says so rather than lying quietly")

eq("stale after two missed refreshes",
	LeaderboardConfig.StaleAfterSecs, LeaderboardConfig.ReadIntervalSecs * 2)

local function staleness(updatedAt, now)
	if updatedAt == 0 then
		return "loading"
	elseif (now - updatedAt) > LeaderboardConfig.StaleAfterSecs then
		return "stale"
	end
	return "fresh"
end

eq("before the first read it is loading, not stale", staleness(0, 10000), "loading")
eq("one missed refresh is still fresh", staleness(10000, 10000 + 90), "fresh")
eq("two missed refreshes is stale", staleness(10000, 10000 + 130), "stale")

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
