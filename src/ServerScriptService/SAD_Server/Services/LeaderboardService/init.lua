--!nonstrict
--[[
	LeaderboardService
	ServerScriptService/SAD_Server/Services/LeaderboardService  (ModuleScript)

	The four global boards, the 60-second read cache, and the Colosseum's data.

	THE ONLY FILE IN THE PROJECT THAT TOUCHES OrderedDataStore. DataService owns
	profiles through ProfileStore and knows nothing about this; this knows
	nothing about profiles beyond `LeaderboardConfig.ValueFor`.

	═══ WRITES ARE THE EXPENSIVE PART, SO THEY ARE THE THROTTLED ONE ═══════════
	docs/13 §Step 22 names the failure directly: "writing every change (budget
	exhaustion)". A player's Fossils change several times a second. Writing that
	would burn the OrderedDataStore budget in seconds and take the profile saves
	down with it.

	So a value is written at most once every 5 minutes per player per board, and
	only when it ACTUALLY CHANGED since the last successful write. A player
	standing still costs nothing at all.
	═══════════════════════════════════════════════════════════════════════════

	═══ THERE IS NO SUCH THING AS A GLOBAL RANK QUERY ══════════════════════════
	docs/08 §3 wants "your rank pinned at the bottom". OrderedDataStore has no
	API that returns a key's rank - `GetSortedAsync` returns pages, and counting
	everyone above you means paging the entire store, which is unbounded and
	would cost more budget than every other read combined.

	So: if you are in the top 100, your real rank is shown. If you are not, your
	VALUE is shown with "outside the top 100" and no number. That is honest.
	Inventing a rank from a sample would be a number that changes when nothing
	about the player did, which is worse than not having one.
	═══════════════════════════════════════════════════════════════════════════

	API:
		LeaderboardService.Get(boardId) -> board?          cached, may be stale
		LeaderboardService.GetAll() -> { [boardId]: board }
		LeaderboardService.GetStatues() -> { {UserId, Name, Value}, ... }
		LeaderboardService.SelfEntry(player, boardId) -> { Value, Rank? }
		LeaderboardService.FlushPlayer(player)             writes now, if dirty
		LeaderboardService.RefreshNow(boardId?)            reads now
		LeaderboardService.BoardsRefreshed  Signal()

	Depends on: LeaderboardConfig, PlayerDataService, Net, Log, Signal.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)

local LeaderboardService = {}

LeaderboardService.BoardsRefreshed = Signal.new()

local PlayerDataService

--- OrderedDataStore handles, one per board. Fetched once at Init: the call is
--- cheap but not free, and a handle is valid for the life of the server.
local stores: { [string]: OrderedDataStore } = {}

--[[
	The cache. One entry per board:
		{ Entries = { {UserId, Name, Value, Rank} }, UpdatedAt = os.clock(), Failed = n }

	`UpdatedAt` is 0 until the first successful read, which is how the client
	tells "loading" from "stale".
]]
local cache: { [string]: any } = {}

--- Last value successfully WRITTEN, per player per board. The throttle's
--- memory: a value equal to this one is not worth a request.
local written: { [Player]: { [string]: number } } = {}
local lastWriteAt: { [Player]: number } = {}

--[[
	userId -> display name, forever. `GetNameFromUserIdAsync` is a web call and
	the top 100 barely changes between refreshes, so re-resolving every minute
	would be a hundred pointless requests. Names do change, but a server's
	lifetime is short enough that a stale one is a smaller problem than the
	request storm.
]]
local nameCache: { [number]: string } = {}

local running = false

-- ── Names ───────────────────────────────────────────────────────────────────

local function resolveName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end

	-- A player already here costs nothing to name, and gives the nicer
	-- DisplayName rather than the account name.
	local present = Players:GetPlayerByUserId(userId)
	if present then
		nameCache[userId] = present.DisplayName
		return present.DisplayName
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		nameCache[userId] = name
		return name
	end

	-- Deleted account, or the request failed. Not cached: a transient failure
	-- should not pin a placeholder for the rest of the server's life.
	return "Player " .. tostring(userId)
end

-- ── Reading ─────────────────────────────────────────────────────────────────

local function refreshBoard(boardId: string): boolean
	local store = stores[boardId]
	if not store then
		return false
	end

	--[[
		`false` is descending: highest first. PageSize is 100, which is both
		docs/08's "top 100" and the maximum a single page may hold, so the
		board is exactly one page and `AdvanceToNextPageAsync` is never needed.
	]]
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, LeaderboardConfig.PageSize)
	end)

	local entry = cache[boardId]
	if not ok then
		entry.Failed += 1
		Log.warn("LeaderboardService", "Read failed for '%s' (%d in a row): %s",
			boardId, entry.Failed, tostring(pages))
		return false
	end

	local page
	local pageOk, pageErr = pcall(function()
		page = pages:GetCurrentPage()
	end)
	if not pageOk then
		entry.Failed += 1
		Log.warn("LeaderboardService", "Page read failed for '%s': %s", boardId, tostring(pageErr))
		return false
	end

	local entries = {}
	for rank, row in ipairs(page) do
		local userId = tonumber(row.key)
		if userId then
			table.insert(entries, {
				UserId = userId,
				Name = resolveName(userId),
				Value = row.value,
				Rank = rank,
			})
		end
	end

	entry.Entries = entries
	entry.UpdatedAt = os.clock()
	entry.Failed = 0
	return true
end

function LeaderboardService.RefreshNow(boardId: string?)
	if boardId then
		refreshBoard(boardId)
	else
		for _, id in LeaderboardConfig.Order do
			refreshBoard(id)
		end
	end
	LeaderboardService.BoardsRefreshed:Fire()
end

-- ── Writing ─────────────────────────────────────────────────────────────────

--[[
	Writes one player's changed values.

	`force` skips the 5-minute throttle - used by PlayerRemoving and
	BindToClose, where the alternative is losing the session's progress from
	the boards entirely. It does NOT skip the changed check: a player who
	leaves without earning anything still costs no requests.
]]
local function writePlayer(player: Player, force: boolean?): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end

	local now = os.clock()
	if not force and (now - (lastWriteAt[player] or 0)) < LeaderboardConfig.WriteIntervalSecs then
		return 0
	end

	local mine = written[player]
	if not mine then
		mine = {}
		written[player] = mine
	end

	local wrote = 0
	for _, boardId in LeaderboardConfig.Order do
		local value = LeaderboardConfig.ValueFor(boardId, data)
		if mine[boardId] ~= value then
			local store = stores[boardId]
			--[[
				SetAsync, not UpdateAsync. The server owns the value outright -
				it is computed from a session-locked profile that no other
				server can be holding - so there is no read-modify-write race
				to guard against, and UpdateAsync would cost a read as well.
			]]
			local ok, err = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if ok then
				mine[boardId] = value
				wrote += 1
			else
				Log.warn("LeaderboardService", "Write failed for %s on '%s': %s",
					player.Name, boardId, tostring(err))
			end
		end
	end

	-- Stamped even when nothing changed, so an idle player is not re-checked
	-- every loop. Stamped after the writes so a slow batch does not shorten
	-- the next interval.
	lastWriteAt[player] = os.clock()
	return wrote
end

function LeaderboardService.FlushPlayer(player: Player): number
	return writePlayer(player, true)
end

-- ── Reading, for everyone else ──────────────────────────────────────────────

local function isStale(entry): boolean
	return entry.UpdatedAt == 0
		or (os.clock() - entry.UpdatedAt) > LeaderboardConfig.StaleAfterSecs
end

function LeaderboardService.Get(boardId: string)
	local entry = cache[boardId]
	if not entry then
		return nil
	end
	return {
		Entries = entry.Entries,
		UpdatedAt = entry.UpdatedAt,
		Stale = isStale(entry),
		Loaded = entry.UpdatedAt > 0,
	}
end

function LeaderboardService.GetAll()
	local all = {}
	for _, id in LeaderboardConfig.Order do
		all[id] = LeaderboardService.Get(id)
	end
	return all
end

--[[
	The player's own line. `Rank` is present only when they are actually in the
	cached top 100 - see the header. Everything else is computed from the
	profile the server holds, so it is current rather than up-to-5-minutes-old
	like the board itself.
]]
function LeaderboardService.SelfEntry(player: Player, boardId: string)
	local data = PlayerDataService.Get(player)
	if not data then
		return nil
	end

	local value = LeaderboardConfig.ValueFor(boardId, data)
	local entry = cache[boardId]
	local rank = nil
	if entry then
		for _, row in entry.Entries do
			if row.UserId == player.UserId then
				rank = row.Rank
				break
			end
		end
	end

	return { Value = value, Rank = rank, Name = player.DisplayName, UserId = player.UserId }
end

--- docs/02 §1.1's three golden statues, from whichever board
--- `LeaderboardConfig.StatueBoard` names.
function LeaderboardService.GetStatues()
	local entry = cache[LeaderboardConfig.StatueBoard]
	local statues = {}
	if not entry then
		return statues
	end
	for rank = 1, LeaderboardConfig.StatueCount do
		local row = entry.Entries[rank]
		if row then
			table.insert(statues, { UserId = row.UserId, Name = row.Name, Value = row.Value, Rank = rank })
		end
	end
	return statues
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function LeaderboardService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")

	for _, boardId in LeaderboardConfig.Order do
		cache[boardId] = { Entries = {}, UpdatedAt = 0, Failed = 0 }

		local entry = LeaderboardConfig.Get(boardId)
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(entry.Store)
		end)
		if ok then
			stores[boardId] = store
		else
			--[[
				Studio without API Services enabled. The boards stay empty and
				every read and write is skipped; nothing else in the game
				changes, which is the same stance ProductConfig takes towards
				an unconfigured asset id.
			]]
			Log.warn("LeaderboardService",
				"No DataStore access for '%s' (%s). Boards will stay empty - "
					.. "enable Studio API Services to test them",
				boardId, tostring(store))
		end
	end
end

function LeaderboardService.Start(app)
	Net.OnInvoke("GetLeaderboards", function(player)
		local payload = { Boards = {}, Self = {}, Order = LeaderboardConfig.Order }
		for _, id in LeaderboardConfig.Order do
			payload.Boards[id] = LeaderboardService.Get(id)
			payload.Self[id] = LeaderboardService.SelfEntry(player, id)
		end
		payload.Statues = LeaderboardService.GetStatues()
		return payload
	end)

	--[[
		A leaving player's session is flushed immediately. Waiting for the
		5-minute tick would mean a short session never reaches the boards at
		all, which is exactly the player who most needs to see their name.
	]]
	Players.PlayerRemoving:Connect(function(player)
		LeaderboardService.FlushPlayer(player)
		written[player] = nil
		lastWriteAt[player] = nil
	end)

	game:BindToClose(function()
		running = false
		if RunService:IsStudio() then
			return
		end
		for _, player in Players:GetPlayers() do
			LeaderboardService.FlushPlayer(player)
		end
	end)

	running = true

	--[[
		Two loops rather than one, because they run at completely different
		periods and a combined loop would have to be the faster of the two.
	]]
	task.spawn(function()
		-- Staggered so a server restart does not have every board read on the
		-- same tick as every other server that restarted with it.
		task.wait(math.random() * LeaderboardConfig.ReadIntervalSecs)
		while running do
			LeaderboardService.RefreshNow()
			--[[
				Re-derived every cycle, so a server that fills up reads more
				often and one that empties out backs off - the budget is a
				function of the player count and so is the schedule.
			]]
			task.wait(LeaderboardConfig.ReadIntervalFor(#Players:GetPlayers()))
		end
	end)

	task.spawn(function()
		while running do
			--[[
				Checked far more often than the interval, and `writePlayer`
				does the throttling. Players join at different times, so one
				5-minute tick for the whole server would make a player wait up
				to 5 minutes past their own interval.
			]]
			task.wait(15)
			for _, player in Players:GetPlayers() do
				writePlayer(player)
			end
		end
	end)

	local check = LeaderboardConfig.BudgetCheck(#Players:GetPlayers())
	Log.info("LeaderboardService",
		"Ready. %d board(s), reads every %.0fs (%.1f/min of %d), writes <= %.1f/min of %d",
		LeaderboardConfig.Count(), check.ReadIntervalSecs,
		check.ReadsPerMin, check.ReadBudget, check.WritesPerMin, check.WriteBudget)
end

return LeaderboardService
