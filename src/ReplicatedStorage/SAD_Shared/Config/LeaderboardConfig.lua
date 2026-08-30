--!nonstrict
--[[
	LeaderboardConfig
	ReplicatedStorage/SAD_Shared/Config/LeaderboardConfig  (ModuleScript)

	The boards, what each one measures, and the budget arithmetic that decides
	how often they may be written and read.

	═══ V1 SHIPS 4 OF THE 8 BOARDS ═════════════════════════════════════════════
	docs/02 §1.1 puts "8 leaderboards + 3 golden statues" in the Colosseum and
	docs/08 §3 gives the menu 8 tabs. docs/12's V1 list is four: Richest,
	Highest Income, Most Eggs Stolen, Highest Rebirth. The other four are here
	as a commented block with the store names docs/10 §4 already reserved, so
	adding one is an entry rather than an archaeology exercise - and the
	Colosseum builds a pillar per SHIPPED board, so it does not grow four empty
	ones.
	═══════════════════════════════════════════════════════════════════════════

	═══ ValueOf IS PURE AND SHARED ═════════════════════════════════════════════
	Both sides need the same number: the server writes it to the OrderedDataStore
	and the client pins "you" at the bottom of the tab. A client that computed
	its own value differently would show a player a number that disagrees with
	the board they are standing in front of.

	The value is never TRUSTED from the client - it is only DISPLAYED there. The
	server writes what it computes from the profile it owns.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local LeaderboardConfig = {}

--[[
	═══ THE INTEGER CEILING ════════════════════════════════════════════════════
	An OrderedDataStore value is a 64-bit signed integer. A rebirth-15 player's
	Fossils passes 2^53 - where a Lua number stops being able to represent
	consecutive integers - long before it passes 2^63, so the clamp below is
	well under both and the arithmetic that produces it stays exact.

	docs/13 §Step 22 names 9e18 as the guard. 9e18 is under 2^63 (~9.22e18) but
	is NOT exactly representable, and it is above 2^53, so a value near it would
	be silently rounded before the store ever saw it. 2^53 is the largest
	ceiling where every integer below it survives the trip intact, so that is
	the one used - and a park worth 9 quadrillion Fossils is far past anything
	docs/05's curve reaches.
	═══════════════════════════════════════════════════════════════════════════
]]
LeaderboardConfig.MaxValue = 2 ^ 53 -- 9,007,199,254,740,992

--[[
	═══ BUDGETS ════════════════════════════════════════════════════════════════
	Roblox's published per-minute request budgets, as of writing:

		OrderedDataStore SetAsync    60 + 10 x players
		GetSortedAsync                5 +  2 x players

	VERIFY THESE against the current DataStore limits documentation before
	launch - Roblox has changed them before, and every number below is derived
	from them rather than restated, so correcting them here corrects the whole
	schedule. `LeaderboardConfig.BudgetCheck` computes the actual usage at a
	given player count so the margin is a measured number rather than a hope.
	═══════════════════════════════════════════════════════════════════════════
]]
LeaderboardConfig.WriteBudgetBase = 60
LeaderboardConfig.WriteBudgetPerPlayer = 10
LeaderboardConfig.ReadBudgetBase = 5
LeaderboardConfig.ReadBudgetPerPlayer = 2

--- docs/10 §4: "written at most once every 5 minutes per player".
LeaderboardConfig.WriteIntervalSecs = 300

--- docs/10 §4: "reads the top 100 of each board every 60 s and caches".
--- A FLOOR, not a fixed period - see ReadIntervalFor below.
LeaderboardConfig.ReadIntervalSecs = 60

--[[
	How much of the read budget the refresh loop is allowed to occupy. Not
	100 %: the budget is a token bucket, and a loop that spends every token
	leaves nothing for a burst - an admin command, a statue refresh, whatever
	V1.4 adds next.
]]
LeaderboardConfig.ReadBudgetShare = 0.75

--[[
	═══ THE READ INTERVAL HAS TO KNOW HOW MANY BOARDS THERE ARE ════════════════
	Reads are per-SERVER, not per-player, so the read budget is smallest exactly
	where the load is constant: a one-player server has a GetSortedAsync budget
	of 5 + 2 = 7/min. V1's four boards at 60 s cost 4/min and fit. The full
	eight boards docs/02 and docs/08 describe would cost 8/min and DO NOT -
	they would exhaust the budget of a nearly empty server and start failing.

	So the period is derived rather than fixed: never faster than docs/10's
	60 s, and stretched when the board count would not fit. V1 is unaffected
	(the floor wins), and the eight-board build-out slows to ~92 s on its own
	instead of silently throttling.
	═══════════════════════════════════════════════════════════════════════════
]]
function LeaderboardConfig.ReadIntervalFor(players: number): number
	local boardCount = #LeaderboardConfig.Order
	local budget = (LeaderboardConfig.ReadBudgetBase
		+ LeaderboardConfig.ReadBudgetPerPlayer * math.max(players, 1))
		* LeaderboardConfig.ReadBudgetShare

	-- Seconds needed to spread `boardCount` reads over the affordable rate.
	local needed = boardCount / budget * 60
	return math.max(LeaderboardConfig.ReadIntervalSecs, needed)
end

--- docs/08 §3: "top 100 each". Also the OrderedDataStore page-size maximum,
--- so a board is exactly one page and never needs `:AdvanceToNextPageAsync`.
LeaderboardConfig.PageSize = 100

--- docs/02 §1.1: "3 golden statues of the server's top players".
LeaderboardConfig.StatueCount = 3

--[[
	Which board the statues depict. Richest, because it is the one docs/00's
	status engine is built around - a park skyline you can see from the plaza
	and a name in gold are the same brag.
]]
LeaderboardConfig.StatueBoard = "richest"

--[[
	How stale a cached board may be before the client is told so. Twice the
	read interval: one missed refresh is ordinary, two means DataStore is
	struggling and a player staring at frozen numbers deserves to know.
]]
LeaderboardConfig.StaleAfterSecs = LeaderboardConfig.ReadIntervalSecs * 2

-- ── The boards ──────────────────────────────────────────────────────────────

local boards = {}
local order = {}

local function board(entry)
	assert(boards[entry.Id] == nil, "duplicate board: " .. entry.Id)
	assert(type(entry.ValueOf) == "function", "board has no ValueOf: " .. entry.Id)
	boards[entry.Id] = entry
	table.insert(order, entry.Id)
	return entry
end

board({
	Id = "richest",
	DisplayName = "RICHEST",
	Blurb = "Fossils on hand",
	Store = "SAD_LB_Fossils",
	Format = "number",
	ValueOf = function(data)
		return (data and data.Fossils) or 0
	end,
})

board({
	Id = "income",
	DisplayName = "HIGHEST INCOME",
	Blurb = "Best park income per second",
	Store = "SAD_LB_Income",
	Format = "rate",
	--[[
		PEAK, not current. docs/10's column is `PeakIncomePerSec` and the
		distinction matters: a player who sells their park to fund a rebirth
		should not drop off the board for the ten minutes it takes to rebuild.
		A board that punishes the thing the game most wants you to do is a
		board working against the design.
	]]
	ValueOf = function(data)
		return (data and data.Stats and data.Stats.PeakIncomePerSec) or 0
	end,
})

board({
	Id = "eggsStolen",
	DisplayName = "MOST EGGS STOLEN",
	Blurb = "Eggs carried home from a nest",
	Store = "SAD_LB_EggsStolen",
	Format = "count",
	ValueOf = function(data)
		return (data and data.Stats and data.Stats.EggsStolen) or 0
	end,
})

board({
	Id = "rebirths",
	DisplayName = "HIGHEST REBIRTH",
	Blurb = "Times the park has been reset",
	Store = "SAD_LB_Rebirths",
	Format = "count",
	ValueOf = function(data)
		return (data and data.Rebirths) or 0
	end,
})

--[[
	V1.4's four, with the store names docs/10 §4 reserves:

		index         SAD_LB_Index         #data.Index
		dinosStolen   SAD_LB_DinosStolen   Stats.DinosStolenFromOthers
		parkValue     SAD_LB_ParkValue     Economy.ParkValue(data)
		rarest        SAD_LB_Rarest        rarity rank x 1e6 + income

	`rarest` is the only one that needs thought: its value is a composite so
	that ties on rarity break by income rather than by whoever wrote last.
]]

LeaderboardConfig.Boards = boards
LeaderboardConfig.Order = order

-- ── Helpers ─────────────────────────────────────────────────────────────────

function LeaderboardConfig.Get(boardId: string)
	return boards[boardId]
end

--- Reads `LeaderboardConfig.Order`, not the local list it was built from, so
--- that `Count` and `ReadIntervalFor` can never disagree about how many boards
--- there are - which is exactly what a spec simulating the eight-board
--- build-out will do to them.
function LeaderboardConfig.Count(): number
	return #LeaderboardConfig.Order
end

--[[
	The value the store actually receives: a non-negative integer inside the
	ceiling. Floored rather than rounded, so a displayed 1,234 is never a
	stored 1,235.
]]
function LeaderboardConfig.StoreValue(raw: number): number
	if type(raw) ~= "number" or raw ~= raw then -- NaN
		return 0
	end
	if raw == math.huge then
		return LeaderboardConfig.MaxValue
	end
	return math.clamp(math.floor(raw), 0, LeaderboardConfig.MaxValue)
end

--- The value for one board, already clamped. The one call site both the
--- writer and the spec use, so the clamp cannot be forgotten at one of them.
function LeaderboardConfig.ValueFor(boardId: string, data): number
	local entry = boards[boardId]
	if not entry then
		return 0
	end
	return LeaderboardConfig.StoreValue(entry.ValueOf(data))
end

--[[
	Requests per minute at a given player count, against the budget for that
	same count. Returns a table so a spec (and the boot log) can assert the
	margin rather than assume it.

	Writes: every player, every board, once per WriteIntervalSecs - the worst
	case where every value changed. Reads: every board once per
	ReadIntervalSecs, and NOT per player, because the cache is server-wide.
]]
function LeaderboardConfig.BudgetCheck(players: number)
	local boardCount = #order

	local writesPerMin = players * boardCount * (60 / LeaderboardConfig.WriteIntervalSecs)
	local readsPerMin = boardCount * (60 / LeaderboardConfig.ReadIntervalFor(players))

	local writeBudget = LeaderboardConfig.WriteBudgetBase
		+ LeaderboardConfig.WriteBudgetPerPlayer * players
	local readBudget = LeaderboardConfig.ReadBudgetBase
		+ LeaderboardConfig.ReadBudgetPerPlayer * players

	return {
		Players = players,
		WritesPerMin = writesPerMin,
		WriteBudget = writeBudget,
		WriteHeadroom = writeBudget / math.max(writesPerMin, 1e-9),
		ReadIntervalSecs = LeaderboardConfig.ReadIntervalFor(players),
		ReadsPerMin = readsPerMin,
		ReadBudget = readBudget,
		ReadHeadroom = readBudget / math.max(readsPerMin, 1e-9),
		Fits = writesPerMin <= writeBudget and readsPerMin <= readBudget,
	}
end

--[[
	Every shipped board must be writable and readable at every player count the
	game supports, INCLUDING one. The read budget is the binding constraint at
	low player counts precisely because reads are per-server rather than
	per-player, so an empty server is the case worth checking - and the one
	nobody thinks to test.
]]
do
	for _, players in { 1, 2, 10, 30, 50 } do
		local check = LeaderboardConfig.BudgetCheck(players)
		assert(check.Fits, ("LeaderboardConfig: %d board(s) do not fit the budget at %d player(s) "
			.. "- %.1f writes/min against %d, %.1f reads/min against %d")
			:format(#order, players, check.WritesPerMin, check.WriteBudget,
				check.ReadsPerMin, check.ReadBudget))
	end

	assert(boards[LeaderboardConfig.StatueBoard],
		"LeaderboardConfig.StatueBoard names a board that does not ship: "
			.. tostring(LeaderboardConfig.StatueBoard))

	local seenStores = {}
	for _, id in order do
		local store = boards[id].Store
		assert(not seenStores[store], "two boards share a store: " .. store)
		seenStores[store] = true
	end
end

return LeaderboardConfig
