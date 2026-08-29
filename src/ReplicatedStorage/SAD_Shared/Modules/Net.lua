--!nonstrict
--[[
	Net
	ReplicatedStorage/SAD_Shared/Modules/Net  (ModuleScript)

	The single door between client and server. Nothing in this game touches a
	RemoteEvent directly - everything goes through here, which is what makes
	security layers 1 and 2 from docs/09-tech-architecture.md §7.2 enforceable
	in one place instead of 24.

	What it does:
	  * Owns the frozen remote inventory (docs/09 §3). Adding a remote means
	    adding a line here, nowhere else.
	  * CREATES every RemoteEvent/RemoteFunction on the server at boot. You do
	    not hand-build these in Studio.
	  * Rate-limits every client -> server call with a per-player token bucket.
	  * Validates argument arity and types before a handler ever sees them.
	  * Reports violations to a pluggable handler (SecurityService, Step 8).

	Over-limit and malformed calls are DROPPED SILENTLY at the network edge. The
	client is never told - telling an exploiter which guard tripped just helps
	them tune around it.

		-- server
		Net.OnEvent("RequestPickupEgg", function(player, nestId, eggSlot) ... end)
		Net.FireClient("Notify", player, payload)
		-- client
		Net.FireServer("RequestPickupEgg", "plains_04", 2)
		Net.On("Notify", function(payload) ... end)

	Depends on: Log.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Log = require(script.Parent.Log)

local Net = {}

local IS_SERVER = RunService:IsServer()

--- Reject any table argument with more entries than this. Stops a client from
--- shipping a 100k-entry table to burn server CPU inside a handler.
Net.MAX_TABLE_ENTRIES = 64

--- How long the client waits for the server to publish the remote tree.
local CLIENT_WAIT_TIMEOUT = 30

--[[
	═══════════════════════════════════════════════════════════════════════════
	REMOTE INVENTORY - frozen, mirrors docs/09-tech-architecture.md §3.

	dir   "c2s" client -> server (rate limited + validated)
	      "s2c" server -> client (no limiting; the server is trusted)
	rate  sustained calls per second
	burst maximum tokens saved up
	args  positional type specs. "?" suffix = optional.
	      Recognised: string, number, boolean, table, Instance, any
	═══════════════════════════════════════════════════════════════════════════
]]
Net.Events = {
	-- ── Eggs & carrying ────────────────────────────────────────────────────
	RequestPickupEgg = { dir = "c2s", rate = 2, burst = 3, args = { "string", "number" } },
	RequestDropEgg = { dir = "c2s", rate = 2, burst = 3, args = { "string" } },
	RequestDepositEggs = { dir = "c2s", rate = 1, burst = 2, args = {} },

	-- ── Incubation & hatching ──────────────────────────────────────────────
	RequestStartIncubation = { dir = "c2s", rate = 3, burst = 5, args = { "string", "number" } },
	RequestClaimHatch = { dir = "c2s", rate = 3, burst = 5, args = { "number" } },

	-- ── Dinosaurs ──────────────────────────────────────────────────────────
	RequestPlaceDino = { dir = "c2s", rate = 4, burst = 6, args = { "string", "number", "number" } },
	RequestStoreDino = { dir = "c2s", rate = 4, burst = 6, args = { "string" } },
	RequestVaultDino = { dir = "c2s", rate = 2, burst = 3, args = { "string", "number" } },
	RequestSellDinos = { dir = "c2s", rate = 1, burst = 2, args = { "table" } },
	RequestSetDinoFlags = { dir = "c2s", rate = 4, burst = 6, args = { "string", "boolean?", "boolean?" } },
	RequestFuse = { dir = "c2s", rate = 1, burst = 2, args = { "table" } },
	RequestRerollMutation = { dir = "c2s", rate = 1, burst = 2, args = { "string" } },

	-- ── Economy & progression ──────────────────────────────────────────────
	RequestBuyUpgrade = { dir = "c2s", rate = 4, burst = 8, args = { "string", "number" } },
	RequestBuyDefence = { dir = "c2s", rate = 2, burst = 4, args = { "string", "number" } },
	RequestUnlockZone = { dir = "c2s", rate = 1, burst = 2, args = { "string" } },
	RequestTeleport = { dir = "c2s", rate = 1, burst = 2, args = { "string" } },
	RequestRebirth = { dir = "c2s", rate = 0.5, burst = 1, args = {} },
	RequestCollectIncome = { dir = "c2s", rate = 2, burst = 3, args = {} },

	-- ── Player raiding ─────────────────────────────────────────────────────
	RequestStealBegin = { dir = "c2s", rate = 1, burst = 2, args = { "number", "string" } },
	RequestStealCancel = { dir = "c2s", rate = 2, burst = 3, args = {} },
	RequestTagThief = { dir = "c2s", rate = 3, burst = 5, args = { "number" } },

	-- ── Loop content ───────────────────────────────────────────────────────
	RequestClaimDaily = { dir = "c2s", rate = 1, burst = 2, args = {} },
	RequestClaimQuest = { dir = "c2s", rate = 2, burst = 3, args = { "string" } },
	RequestRerollQuest = { dir = "c2s", rate = 1, burst = 2, args = { "string" } },
	RequestUseItem = { dir = "c2s", rate = 2, burst = 4, args = { "string" } },
	RequestEventAction = { dir = "c2s", rate = 3, burst = 6, args = { "string", "string", "any?" } },

	-- ── Meta ───────────────────────────────────────────────────────────────
	RequestSetSetting = { dir = "c2s", rate = 5, burst = 10, args = { "string", "any" } },
	RequestTutorialStep = { dir = "c2s", rate = 3, burst = 5, args = { "number" } },

	-- ── Server -> client ───────────────────────────────────────────────────
	StateFull = { dir = "s2c" },
	StateDelta = { dir = "s2c" },
	Notify = { dir = "s2c" },
	HatchResult = { dir = "s2c" },
	WeatherChanged = { dir = "s2c" },
	EventState = { dir = "s2c" },
	StealAlert = { dir = "s2c" },
	ChaseState = { dir = "s2c" },
	IncomePopup = { dir = "s2c" },
	TutorialState = { dir = "s2c" },
}

--- RemoteFunctions yield and can hang a thread, so they are read-only and
--- idempotent by rule. Every mutating call is a RemoteEvent.
Net.Functions = {
	GetProfileSnapshot = { rate = 1, burst = 2, args = {} },
	GetLeaderboards = { rate = 0.5, burst = 2, args = {} },
	GetParkSnapshot = { rate = 2, burst = 4, args = { "number" } },
	GetIndexData = { rate = 1, burst = 2, args = {} },
}

-- ── Internal state ──────────────────────────────────────────────────────────
local root: Folder? = nil
local eventsFolder: Folder? = nil
local functionsFolder: Folder? = nil

local eventCache: { [string]: RemoteEvent } = {}
local functionCache: { [string]: RemoteFunction } = {}

--- [player] = { [remoteName] = { tokens = n, last = clock } }
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

local violationHandler: ((Player, string, string, string) -> ())? = nil

-- ── Validation ──────────────────────────────────────────────────────────────

local function tableTooLarge(value: any): boolean
	local count = 0
	for _ in value do
		count += 1
		if count > Net.MAX_TABLE_ENTRIES then
			return true
		end
	end
	return false
end

local function argMatches(spec: string, value: any): boolean
	local optional = string.sub(spec, -1) == "?"
	local expected = if optional then string.sub(spec, 1, -2) else spec

	if value == nil then
		return optional
	end
	if expected == "any" then
		return true
	end
	if typeof(value) ~= expected then
		return false
	end
	if expected == "table" and tableTooLarge(value) then
		return false
	end
	return true
end

--- Reports and returns false. Kept as one funnel so every rejection is logged.
local function reject(player: Player, kind: string, remoteName: string, detail: string): boolean
	Log.warn("Net", "%s rejected %s from %s (%s)", kind, remoteName, player.Name, detail)
	if violationHandler then
		task.spawn(violationHandler, player, kind, remoteName, detail)
	end
	return false
end

local function checkArgs(player: Player, remoteName: string, declaration: any, ...): boolean
	local specs = declaration.args
	if not specs then
		return true
	end

	local supplied = select("#", ...)
	if supplied > #specs then
		return reject(player, "Arity", remoteName, string.format("%d args, expected %d", supplied, #specs))
	end

	for index, spec in specs do
		if not argMatches(spec, (select(index, ...))) then
			return reject(
				player,
				"Type",
				remoteName,
				string.format("arg %d expected %s, got %s", index, spec, typeof((select(index, ...))))
			)
		end
	end

	return true
end

--[[
	Token bucket. Refills continuously at `rate` per second up to `burst`, so a
	player who has been idle can fire a short burst but cannot sustain one.
	os.clock() is used rather than os.time() for sub-second resolution.
]]
local function checkRate(player: Player, remoteName: string, declaration: any): boolean
	local rate = declaration.rate
	if not rate then
		return true
	end
	local burst = declaration.burst or rate

	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end

	local bucket = playerBuckets[remoteName]
	local now = os.clock()
	if not bucket then
		bucket = { tokens = burst, last = now }
		playerBuckets[remoteName] = bucket
	end

	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now

	if bucket.tokens < 1 then
		return reject(player, "RateLimit", remoteName, string.format("%.2f/s allowed", rate))
	end

	bucket.tokens -= 1
	return true
end

-- ── Lookup ──────────────────────────────────────────────────────────────────

local function getEvent(name: string): RemoteEvent
	local cached = eventCache[name]
	if cached then
		return cached
	end

	assert(Net.Events[name], "Net: unknown RemoteEvent '" .. name .. "'")
	assert(eventsFolder, "Net: not initialised - call Net.Init() first")

	local remote = (eventsFolder :: Folder):WaitForChild(name, CLIENT_WAIT_TIMEOUT)
	assert(remote, "Net: RemoteEvent '" .. name .. "' never replicated")

	eventCache[name] = remote :: RemoteEvent
	return remote :: RemoteEvent
end

local function getFunction(name: string): RemoteFunction
	local cached = functionCache[name]
	if cached then
		return cached
	end

	assert(Net.Functions[name], "Net: unknown RemoteFunction '" .. name .. "'")
	assert(functionsFolder, "Net: not initialised - call Net.Init() first")

	local remote = (functionsFolder :: Folder):WaitForChild(name, CLIENT_WAIT_TIMEOUT)
	assert(remote, "Net: RemoteFunction '" .. name .. "' never replicated")

	functionCache[name] = remote :: RemoteFunction
	return remote :: RemoteFunction
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

--[[
	Server: builds ReplicatedStorage/SAD_Net with every declared remote.
	Client: waits for that tree to replicate.
	Safe to call once per context; Bootstrap does it before any service loads.
]]
function Net.Init()
	if IS_SERVER then
		-- A leftover tree can survive a Studio stop; start from a clean slate.
		local existing = ReplicatedStorage:FindFirstChild("SAD_Net")
		if existing then
			existing:Destroy()
		end

		local newRoot = Instance.new("Folder")
		newRoot.Name = "SAD_Net"

		local events = Instance.new("Folder")
		events.Name = "Events"
		events.Parent = newRoot

		local functions = Instance.new("Folder")
		functions.Name = "Functions"
		functions.Parent = newRoot

		local eventCount = 0
		for name in Net.Events do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = events
			eventCount += 1
		end

		local functionCount = 0
		for name in Net.Functions do
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = functions
			functionCount += 1
		end

		-- Parent last, so the whole tree replicates as one complete unit.
		newRoot.Parent = ReplicatedStorage

		root = newRoot
		eventsFolder = events
		functionsFolder = functions

		Players.PlayerRemoving:Connect(function(player)
			buckets[player] = nil
		end)

		Log.info("Net", "Published %d events and %d functions", eventCount, functionCount)
	else
		local found = ReplicatedStorage:WaitForChild("SAD_Net", CLIENT_WAIT_TIMEOUT)
		assert(found, "Net: SAD_Net never replicated - is the server Bootstrap running?")

		root = found :: Folder
		eventsFolder = (found :: Folder):WaitForChild("Events", CLIENT_WAIT_TIMEOUT) :: Folder
		functionsFolder = (found :: Folder):WaitForChild("Functions", CLIENT_WAIT_TIMEOUT) :: Folder

		Log.info("Net", "Connected to remote tree")
	end
end

--- SecurityService registers here in Step 8. handler(player, kind, remote, detail)
function Net.SetViolationHandler(handler: (Player, string, string, string) -> ())
	violationHandler = handler
end

-- ── Server API ──────────────────────────────────────────────────────────────

--[[
	Binds a server handler to a c2s event. The handler only ever runs for calls
	that passed the rate limit and the argument schema.
]]
function Net.OnEvent(name: string, handler: (Player, ...any) -> ())
	assert(IS_SERVER, "Net.OnEvent is server-only")

	local declaration = Net.Events[name]
	assert(declaration, "Net: unknown RemoteEvent '" .. name .. "'")
	assert(declaration.dir == "c2s", "Net: '" .. name .. "' is not a client -> server event")

	getEvent(name).OnServerEvent:Connect(function(player, ...)
		if not checkRate(player, name, declaration) then
			return
		end
		if not checkArgs(player, name, declaration, ...) then
			return
		end
		handler(player, ...)
	end)
end

function Net.FireClient(name: string, player: Player, ...)
	assert(IS_SERVER, "Net.FireClient is server-only")

	local declaration = Net.Events[name]
	assert(declaration and declaration.dir == "s2c", "Net: '" .. name .. "' is not a server -> client event")

	getEvent(name):FireClient(player, ...)
end

function Net.FireAllClients(name: string, ...)
	assert(IS_SERVER, "Net.FireAllClients is server-only")

	local declaration = Net.Events[name]
	assert(declaration and declaration.dir == "s2c", "Net: '" .. name .. "' is not a server -> client event")

	getEvent(name):FireAllClients(...)
end

function Net.FireAllExcept(name: string, excluded: Player, ...)
	assert(IS_SERVER, "Net.FireAllExcept is server-only")

	for _, player in Players:GetPlayers() do
		if player ~= excluded then
			Net.FireClient(name, player, ...)
		end
	end
end

--- Binds a RemoteFunction handler. Same guards as OnEvent; blocked calls return nil.
function Net.OnInvoke(name: string, handler: (Player, ...any) -> ...any)
	assert(IS_SERVER, "Net.OnInvoke is server-only")

	local declaration = Net.Functions[name]
	assert(declaration, "Net: unknown RemoteFunction '" .. name .. "'")

	getFunction(name).OnServerInvoke = function(player, ...)
		if not checkRate(player, name, declaration) then
			return nil
		end
		if not checkArgs(player, name, declaration, ...) then
			return nil
		end
		return handler(player, ...)
	end
end

-- ── Client API ──────────────────────────────────────────────────────────────

function Net.FireServer(name: string, ...)
	assert(not IS_SERVER, "Net.FireServer is client-only")

	local declaration = Net.Events[name]
	assert(declaration and declaration.dir == "c2s", "Net: '" .. name .. "' is not a client -> server event")

	getEvent(name):FireServer(...)
end

function Net.On(name: string, handler: (...any) -> ())
	assert(not IS_SERVER, "Net.On is client-only")

	local declaration = Net.Events[name]
	assert(declaration and declaration.dir == "s2c", "Net: '" .. name .. "' is not a server -> client event")

	return getEvent(name).OnClientEvent:Connect(handler)
end

--- Yields. Read-only queries only.
function Net.Invoke(name: string, ...): ...any
	assert(not IS_SERVER, "Net.Invoke is client-only")
	return getFunction(name):InvokeServer(...)
end

return Net
