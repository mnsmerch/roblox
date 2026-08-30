--!nonstrict
--[[
	DataService
	ServerScriptService/SAD_Server/Services/DataService  (ModuleScript)
	  ├── ProfileTemplate  (ModuleScript)
	  └── Migrations       (ModuleScript)

	Persistence and session locking. THE ONLY FILE IN THE PROJECT THAT KNOWS
	ProfileStore EXISTS - every other service goes through PlayerDataService.
	If we ever swap persistence, this file changes and nothing else does.

	What it guarantees:
	  * One session per player across all servers (ProfileStore's session lock).
	    This is what prevents the classic duplication exploit: join two servers,
	    move an item in one, and let the other's save overwrite it.
	  * A loaded profile is migrated and reconciled BEFORE any service sees it.
	  * A profile from a newer schema than this server understands is never
	    written to. It is refused and the player is told to rejoin later.
	  * Autosave on a jittered interval, plus explicit saves at the moments
	    docs/09 §5 calls out, plus a clean shutdown on BindToClose.

	Save order on load: migrate (reshape), then reconcile (fill defaults).
	Reshaping first means a migration can rely on the old shape being intact.

	Public API:
		DataService.StartSessionAsync(player) -> Session?   yields
		DataService.EndSession(player)
		DataService.SaveNow(player, reason)
		DataService.GetSession(player) -> Session?
		DataService.BeforeSave       Signal(player, data, reason)
		DataService.SaveStalled      Signal(player, secondsSinceLastSave)

	A Session is a thin wrapper:
		session.Data      the profile table (Types.Profile)
		session.Player
		session:Save(reason)
		session:End()
		session:IsActive() -> boolean

	Depends on: Log, Signal, TableUtil, GameConfig, ProfileTemplate, Migrations,
	            and the third-party ProfileStore module.
	Depended on by: PlayerDataService (and nothing else, by design).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Modules.Log)
local Signal = require(Shared.Modules.Signal)
local TableUtil = require(Shared.Modules.TableUtil)

local ProfileTemplate = require(script.ProfileTemplate)
local Migrations = require(script.Migrations)

--[[
	ProfileStore is a third-party module (MadStudioRoblox/ProfileStore) that we
	add to the place by hand - it is not a Roblox API. Fail with instructions
	rather than a bare "attempt to call nil" if it is missing.
]]
local profileStoreModule = script.Parent.Parent:FindFirstChild("ProfileStore")
assert(
	profileStoreModule,
	"[SAD] ProfileStore is not installed.\n"
		.. "Put the ProfileStore ModuleScript at ServerScriptService/SAD_Server/ProfileStore.\n"
		.. "See SETUP.md for where to get it."
)
local ProfileStore = require(profileStoreModule)

local DataService = {}

DataService.BeforeSave = Signal.new()
DataService.SaveStalled = Signal.new()

local store = nil
local sessions: { [Player]: any } = {}
local lastSaveClock: { [Player]: number } = {}
local app = nil

-- ── Session wrapper ─────────────────────────────────────────────────────────

local Session = {}
Session.__index = Session

function Session.new(player: Player, profile)
	return setmetatable({
		Player = player,
		Data = profile.Data,
		_profile = profile,
		_active = true,
	}, Session)
end

function Session:IsActive(): boolean
	return self._active == true
end

--[[
	Forces an immediate write. Called at the moments where losing the last few
	minutes would be unacceptable: a rebirth, a Robux purchase, a Legendary+
	hatch, a completed steal.
]]
function Session:Save(reason: string?)
	if not self._active then
		return
	end

	DataService.BeforeSave:Fire(self.Player, self.Data, reason or "Manual")

	local ok, err = pcall(function()
		self._profile:Save()
	end)

	if ok then
		lastSaveClock[self.Player] = os.clock()
		Log.debug("DataService", "Saved %s (%s)", self.Player.Name, reason or "Manual")
	else
		Log.error("DataService", "Save failed for %s (%s): %s", self.Player.Name, reason or "Manual", tostring(err))
	end
end

function Session:End()
	if not self._active then
		return
	end
	self._active = false

	DataService.BeforeSave:Fire(self.Player, self.Data, "SessionEnd")

	local ok, err = pcall(function()
		self._profile:EndSession()
	end)
	if not ok then
		Log.error("DataService", "EndSession failed for %s: %s", self.Player.Name, tostring(err))
	end
end

-- ── Loading ─────────────────────────────────────────────────────────────────

--[[
	Migrate, then reconcile, then apply to the live table IN PLACE.

	In place matters: ProfileStore saves whatever profile.Data points at, and
	replacing that reference could leave it saving the pre-migration table.

	Returns an error string if the profile must not be loaded.
]]
local function prepareData(player: Player, profile): string?
	local data = profile.Data

	local migrated, steps, err = Migrations.Apply(data)
	if err then
		return err
	end
	if steps > 0 then
		Log.info("DataService", "Migrated %s through %d version(s) to v%d", player.Name, steps, migrated.SchemaVersion)
	end

	-- Reconcile fills any key the current template has and this profile lacks.
	-- Our own TableUtil.Reconcile is used rather than ProfileStore's, so that
	-- reconcile semantics are covered by tests/run.sh and stay identical if the
	-- persistence layer is ever swapped out.
	local reconciled = TableUtil.Reconcile(migrated, ProfileTemplate)

	Migrations.WriteInPlace(data, reconciled)
	return nil
end

--[[
	Starts a locked session for `player`. YIELDS.

	Returns nil when the profile could not be loaded or must not be written to.
	The caller is responsible for telling the player - see PlayerDataService.
]]
function DataService.StartSessionAsync(player: Player): any?
	if sessions[player] then
		return sessions[player]
	end

	local key = "Player_" .. player.UserId

	local ok, profile = pcall(function()
		return store:StartSessionAsync(key, {
			-- ProfileStore stops waiting for the lock if the player has left.
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
	end)

	if not ok then
		Log.error("DataService", "StartSessionAsync threw for %s: %s", player.Name, tostring(profile))
		return nil
	end

	if not profile then
		Log.warn("DataService", "Could not acquire a session lock for %s", player.Name)
		return nil
	end

	-- The player may have left while we were yielding on the DataStore.
	if player.Parent ~= Players then
		profile:EndSession()
		return nil
	end

	profile:AddUserId(player.UserId) -- GDPR: associates the key with the user

	local prepareError = prepareData(player, profile)
	if prepareError then
		Log.error("DataService", "Refusing to load %s: %s", player.Name, prepareError)
		-- Ending without touching Data re-saves exactly what was read, so a
		-- newer profile is never overwritten by an older server.
		profile:EndSession()
		return nil
	end

	local session = Session.new(player, profile)

	--[[
		Fires when the lock is lost - normally our own EndSession, but also when
		another server steals the session (the player joined elsewhere). In that
		case this server's copy is stale and must stop writing immediately.
	]]
	profile.OnSessionEnd:Connect(function()
		session._active = false
		sessions[player] = nil
		lastSaveClock[player] = nil

		if player.Parent == Players then
			Log.warn("DataService", "Session ended remotely for %s - kicking to protect data", player.Name)
			player:Kick("Your data was opened in another server. Please rejoin.")
		end
	end)

	sessions[player] = session
	lastSaveClock[player] = os.clock()

	Log.info("DataService", "Session started for %s (schema v%d)", player.Name, session.Data.SchemaVersion)
	return session
end

function DataService.GetSession(player: Player): any?
	return sessions[player]
end

function DataService.EndSession(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	lastSaveClock[player] = nil
	session:End()
	Log.info("DataService", "Session ended for %s", player.Name)
end

function DataService.SaveNow(player: Player, reason: string?)
	local session = sessions[player]
	if session then
		session:Save(reason)
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function DataService.Init(injected)
	app = injected

	--[[
		Invariant: the template's SchemaVersion and the migration chain must
		agree. Bumping GameConfig.SchemaVersion without adding the matching
		migration would make every existing profile fail Migrations.Apply with
		"no migration registered" - i.e. nobody can log in. Catching that here
		costs one comparison and turns a launch-day outage into a boot error.
	]]
	local chainError = Migrations.Validate()
	assert(not chainError, "[SAD] " .. tostring(chainError))

	assert(
		ProfileTemplate.SchemaVersion == Migrations.CurrentVersion(),
		string.format(
			"[SAD] Schema mismatch: template is v%d but the migration chain ends at v%d. "
				.. "Add a migration to DataService/Migrations, or revert GameConfig.SchemaVersion.",
			ProfileTemplate.SchemaVersion,
			Migrations.CurrentVersion()
		)
	)

	local storeName = GameConfig.DataStoreName
	store = ProfileStore.New(storeName, ProfileTemplate)

	--[[
		Studio without API access cannot reach DataStores at all. ProfileStore
		exposes a .Mock store that behaves identically in memory, which keeps
		Studio usable - but mock data is DISCARDED when you stop the session, so
		this must never be reachable in a published place.
	]]
	if RunService:IsStudio() and GameConfig.UseMockDataInStudio then
		store = store.Mock
		Log.warn("DataService", "USING MOCK STORE - data will NOT persist. GameConfig.UseMockDataInStudio")
	end

	Log.info("DataService", "Store '%s' ready, schema v%d", storeName, Migrations.CurrentVersion())
end

function DataService.Start(injected)
	--[[
		Autosave. ProfileStore autosaves on its own schedule too; this is our
		documented interval on top of it (docs/09 §5). The per-player jitter
		spreads writes across the window instead of stacking 24 saves into one
		frame every three minutes.
	]]
	task.spawn(function()
		while true do
			task.wait(1)

			local now = os.clock()
			for player, session in sessions do
				if not session:IsActive() then
					continue
				end

				local last = lastSaveClock[player] or now
				local elapsed = now - last

				-- Jitter is derived from UserId so a player's slot is stable
				-- across the session rather than drifting every cycle.
				local jitter = (player.UserId % GameConfig.AutosaveJitterSecs)
				if elapsed >= GameConfig.AutosaveIntervalSecs + jitter then
					session:Save("Autosave")
				elseif elapsed >= GameConfig.SaveStalledWarningSecs then
					-- ProfileStore retries internally, so we cannot see one
					-- failed write. What we CAN see is that nothing has
					-- succeeded for a long time, which is the signal that
					-- matters. Step 16 turns this into a player-facing banner.
					Log.warn("DataService", "No successful save for %s in %ds", player.Name, math.floor(elapsed))
					DataService.SaveStalled:Fire(player, elapsed)
					lastSaveClock[player] = now -- avoid warning every second
				end
			end
		end
	end)

	--[[
		Shutdown. ProfileStore handles game close itself, but ending sessions
		explicitly and waiting means we control the ordering and can log what
		actually got out.
	]]
	game:BindToClose(function()
		Log.banner("Shutdown - flushing sessions")

		local deadline = os.clock() + GameConfig.BindToCloseTimeoutSecs

		for player in sessions do
			task.spawn(DataService.EndSession, player)
		end

		while next(sessions) ~= nil and os.clock() < deadline do
			task.wait(0.1)
		end

		local remaining = 0
		for _ in sessions do
			remaining += 1
		end
		if remaining > 0 then
			Log.error("DataService", "%d session(s) did not flush before the shutdown deadline", remaining)
		else
			Log.info("DataService", "All sessions flushed")
		end
	end)
end

--[[
	Exposed so RebirthService can assert its three classification lists cover
	the schema. Read-only by convention: DataService is still the only thing
	that writes through it.
]]
DataService.Template = ProfileTemplate

return DataService
