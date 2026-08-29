--!nonstrict
--[[
	PlayerDataService
	ServerScriptService/SAD_Server/Services/PlayerDataService  (ModuleScript)
	  └── Replication  (ModuleScript)

	The profile access layer every other service uses. Owns the player lifecycle
	(join -> load -> play -> leave) and holds loaded profiles in memory.

	This is the boundary that keeps ProfileStore out of the rest of the codebase.
	No service outside DataService should ever import a persistence library.

	Public API:
		PlayerDataService.Get(player)            -> data?   nil until loaded
		PlayerDataService.GetAsync(player)       -> data?   yields for the load
		PlayerDataService.IsLoaded(player)       -> boolean
		PlayerDataService.Update(player, fn, reason?)            -> boolean
		PlayerDataService.UpdateKeys(player, keys, fn, reason?)  -> boolean
		PlayerDataService.Save(player, reason)
		PlayerDataService.GetAll()               -> {[Player]: data}
		PlayerDataService.SendFullState(player)

		PlayerDataService.ProfileLoaded     Signal(player, data)
		PlayerDataService.ProfileUnloading  Signal(player, data)
		PlayerDataService.Changed           Signal(player, reason, keys?)

	READS use Get. WRITES use Update or UpdateKeys:

		-- touches one field, so say so: the diff walks one subtree
		PlayerDataService.UpdateKeys(player, { "Fossils" }, function(data)
			data.Fossils += 100
		end, "income")

		-- unsure what changed? Update marks everything dirty. Costs one wider
		-- diff, never a desynced client.
		PlayerDataService.Update(player, function(data) ... end, "rebirth")

	A write that bypasses both is a write the client never hears about. That is
	the only reason these exist - server code is trusted, so this is about
	replication, not safety.

	Depends on: DataService, Replication, Log, Net, Signal, GameConfig.
	Depended on by: essentially every later service.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)

local Replication = require(script.Replication)

local PlayerDataService = {}

PlayerDataService.ProfileLoaded = Signal.new()
PlayerDataService.ProfileUnloading = Signal.new()
PlayerDataService.Changed = Signal.new()

local DataService = nil
local app = nil

--- [player] = profile data table
local loaded: { [Player]: any } = {}

--- [player] = os.clock() when this session's playtime was last flushed
local playtimeMark: { [Player]: number } = {}

--- Players whose load is still in flight, so GetAsync can wait on them.
local loading: { [Player]: boolean } = {}

-- ── Access ──────────────────────────────────────────────────────────────────

function PlayerDataService.Get(player: Player): any?
	return loaded[player]
end

function PlayerDataService.IsLoaded(player: Player): boolean
	return loaded[player] ~= nil
end

function PlayerDataService.GetAll(): { [Player]: any }
	return loaded
end

--[[
	Waits for a player's profile. Returns nil if they leave or the load fails,
	so every caller must handle nil - a player CAN leave mid-load and services
	that assume otherwise will throw on the one unlucky join.
]]
function PlayerDataService.GetAsync(player: Player, timeoutSecs: number?): any?
	local deadline = os.clock() + (timeoutSecs or 30)

	while os.clock() < deadline do
		local data = loaded[player]
		if data then
			return data
		end
		if not loading[player] and player.Parent ~= Players then
			return nil
		end
		if not loading[player] and not loaded[player] then
			-- Load finished and produced nothing.
			return nil
		end
		task.wait(0.1)
	end

	Log.warn("PlayerDataService", "GetAsync timed out for %s", player.Name)
	return nil
end

--[[
	Mutates a profile and announces it. Returns false when the profile is not
	loaded, which is a normal race (a remote can arrive before the load
	finishes), not an error - callers should check it and drop the request.
]]
function PlayerDataService.Update(player: Player, mutator: (any) -> (), reason: string?): boolean
	return PlayerDataService.UpdateKeys(player, nil, mutator, reason)
end

--[[
	As Update, but declares which top-level profile keys changed so replication
	only diffs those subtrees. `keys` nil means "everything".

	Declaring keys is an optimisation, never a correctness requirement - getting
	it wrong costs a wider diff, and omitting it entirely is the safe default.
]]
function PlayerDataService.UpdateKeys(
	player: Player,
	keys: { string }?,
	mutator: (any) -> (),
	reason: string?
): boolean
	local data = loaded[player]
	if not data then
		return false
	end

	local ok, err = pcall(mutator, data)
	if not ok then
		Log.error("PlayerDataService", "Update mutator errored for %s (%s): %s", player.Name, reason or "?", tostring(err))
		return false
	end

	Replication.MarkDirty(player, keys)
	PlayerDataService.Changed:Fire(player, reason or "update", keys)
	return true
end

--- Re-sends the whole replicated slice. RebirthService uses this after a reset,
--- where a patch list would be larger than a snapshot anyway.
function PlayerDataService.SendFullState(player: Player)
	local data = loaded[player]
	if data then
		Replication.SendFull(player, data)
	end
end

function PlayerDataService.Save(player: Player, reason: string?)
	DataService.SaveNow(player, reason)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

--- Rolls wall-clock time since the last flush into Stats.PlaytimeSecs.
--- New Player Protection (docs/06 §7) is measured in playtime, not join time,
--- so this has to be accurate rather than derived from FirstJoinAt.
local function flushPlaytime(player: Player, data: any)
	local mark = playtimeMark[player]
	if not mark then
		return
	end
	local now = os.clock()
	data.Stats.PlaytimeSecs += (now - mark)
	playtimeMark[player] = now
end

local function onPlayerAdded(player: Player)
	loading[player] = true

	local session = DataService.StartSessionAsync(player)

	loading[player] = nil

	if not session then
		if player.Parent == Players then
			Log.error("PlayerDataService", "No session for %s - kicking", player.Name)
			player:Kick("We could not load your dinosaurs. Please rejoin in a moment.")
		end
		return
	end

	-- The player may have left during the DataStore round trip.
	if player.Parent ~= Players then
		DataService.EndSession(player)
		return
	end

	local data = session.Data
	local now = os.time()

	local isNewPlayer = data.FirstJoinAt == 0
	if isNewPlayer then
		data.FirstJoinAt = now
		Log.info("PlayerDataService", "%s is a NEW player", player.Name)
	end

	data.Stats.Joins += 1
	playtimeMark[player] = os.clock()

	loaded[player] = data

	-- Before ProfileLoaded fires, so a listener that immediately writes has a
	-- snapshot to diff against rather than being dropped.
	Replication.SendFull(player, data)

	Log.info(
		"PlayerDataService",
		"Loaded %s | Fossils %d | Rebirths %d | Playtime %ds | New: %s",
		player.Name,
		data.Fossils,
		data.Rebirths,
		math.floor(data.Stats.PlaytimeSecs),
		tostring(isNewPlayer)
	)

	PlayerDataService.ProfileLoaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local data = loaded[player]

	if data then
		-- Fire BEFORE unloading so services can still read the profile while
		-- writing their final state into it.
		PlayerDataService.ProfileUnloading:Fire(player, data)
	end

	loaded[player] = nil
	loading[player] = nil
	playtimeMark[player] = nil
	Replication.Clear(player)

	DataService.EndSession(player)
end

--[[
	Applies one client-requested setting after validating it against
	GameConfig.SettingsSchema.

	Settings are the one profile field a client may write, so this is the first
	place the input rules from docs/09 §7.2 apply for real: the key must be
	known, the type must match, numbers are CLAMPED rather than rejected, and
	string values must be one of the allowed options. A bad value is dropped
	silently - the client is not told which guard tripped.
]]
local function applySetting(player: Player, key: string, value: any): boolean
	local schema = GameConfig.SettingsSchema[key]
	if not schema then
		return false
	end
	if typeof(value) ~= schema.Type then
		return false
	end

	if schema.Type == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return false
		end
		value = math.clamp(value, schema.Min, schema.Max)
	elseif schema.Type == "string" then
		local allowed = false
		for _, option in schema.OneOf do
			if value == option then
				allowed = true
				break
			end
		end
		if not allowed then
			return false
		end
	end

	return PlayerDataService.UpdateKeys(player, { "Settings" }, function(data)
		data.Settings[key] = value
	end, "setting")
end

function PlayerDataService.Init(injected)
	app = injected
	DataService = app.Get("DataService")

	Replication.Init(injected)

	-- Stamp bookkeeping onto every save, whatever triggered it. Doing this on
	-- the signal rather than at each call site means no save path can forget.
	DataService.BeforeSave:Connect(function(player: Player, data: any)
		flushPlaytime(player, data)
		data.LastSeen = os.time()
	end)
end

function PlayerDataService.Start(injected)
	Replication.Start(injected)

	Net.OnEvent("RequestSetSetting", function(player: Player, key: string, value: any)
		applySetting(player, key, value)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- In Studio and on a fast server start, PlayerAdded can fire before this
	-- service reaches Start. Catch anyone already here.
	for _, player in Players:GetPlayers() do
		if not loaded[player] and not loading[player] then
			task.spawn(onPlayerAdded, player)
		end
	end
end

return PlayerDataService
