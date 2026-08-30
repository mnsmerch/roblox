--!nonstrict
--[[
	BroadcastService
	ServerScriptService/SAD_Server/Services/BroadcastService  (ModuleScript)

	Cross-server announcements over MessagingService. The only file in the
	project that knows MessagingService exists - the same containment DataService
	applies to ProfileStore.

	═══ WHAT CAN GO WRONG HERE ═════════════════════════════════════════════════
	MessagingService is the least reliable thing in the project, so every one of
	its failure modes is handled rather than assumed away:

	  * BOTH CALLS YIELD AND THROW. Publishing from inside a hatch would make a
	    Titan hatch wait on a web request. Every publish goes through a queue
	    drained on its own thread, and both calls are pcall'd.
	  * THE RATE LIMIT IS PER SERVER AND SCALES WITH PLAYER COUNT. Exceeding it
	    does not raise a useful error - it throttles and the message is gone. So
	    the budget is enforced HERE, under the documented floor, where a refusal
	    can be counted.
	  * MESSAGES ARE CAPPED AT 1 KB and must be JSON-serialisable. Payloads are
	    sanitised to flat scalars and truncated before they are handed over.
	  * SUBSCRIBING CAN FAIL AT BOOT. If it does, the game runs with cross-server
	    announcements off rather than not running.
	  * IT IS OFF IN STUDIO unless API services are enabled, and a single Studio
	    session is a single server. Both are reported at boot instead of looking
	    like a bug.
	═══════════════════════════════════════════════════════════════════════════

	API:
		BroadcastService.Publish(payload) -> queued
		BroadcastService.IsAvailable() -> boolean
		BroadcastService.GetStats() -> { Published, Dropped, Received, Failed }
		BroadcastService.Received  Signal(payload)

	Depends on: NotificationConfig, Log, Signal.
	Depended on by: NotificationService.
]]

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local NotificationConfig = require(Shared.Config.NotificationConfig)
local Signal = require(Shared.Modules.Signal)

local BroadcastService = {}

BroadcastService.Received = Signal.new()

local subscribed = false
local connection = nil

local queue = {}
local stats = { Published = 0, Dropped = 0, Received = 0, Failed = 0 }

--- Timestamps of recent publishes, for the token bucket.
local publishTimes = {}

local DRAIN_INTERVAL = 0.5

--[[
	This server's own id, stamped on every message so a server does not render
	its own announcement twice - once locally and once on the way back round.

	JobId is empty in Studio, so a GUID stands in. It only has to be unique
	among the servers currently running.
]]
local SERVER_ID = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

-- ── Budget ──────────────────────────────────────────────────────────────────

local function withinBudget(): boolean
	local now = os.clock()
	local cutoff = now - NotificationConfig.PublishWindow

	local kept = {}
	for _, stamp in publishTimes do
		if stamp > cutoff then
			table.insert(kept, stamp)
		end
	end
	publishTimes = kept

	return #publishTimes < NotificationConfig.PublishBudget
end

-- ── Publishing ──────────────────────────────────────────────────────────────

function BroadcastService.IsAvailable(): boolean
	return subscribed
end

--[[
	Queues a payload for every other server. Returns whether it was queued.

	Never yields: the caller is usually mid-hatch, and a web request in that
	path would be felt. Dropping is deliberate and counted - an announcement
	is a nice-to-have, and the local half has already happened by the time
	this is called.
]]
function BroadcastService.Publish(payload): boolean
	if not subscribed then
		return false
	end

	local clean = NotificationConfig.Sanitise(payload)
	if not clean then
		return false
	end

	if #queue >= NotificationConfig.PublishBudget then
		stats.Dropped += 1
		return false
	end

	clean.From = SERVER_ID
	table.insert(queue, clean)
	return true
end

--[[
	Drains one message per tick.

	One at a time rather than the whole queue, because PublishAsync yields and
	a burst would hold this thread for as long as the network takes. Two per
	second is comfortably inside the budget and fast enough that nobody
	perceives the difference.
]]
local function drain()
	local payload = table.remove(queue, 1)
	if not payload then
		return
	end

	if not withinBudget() then
		stats.Dropped += 1
		Log.warn("BroadcastService", "Publish budget spent (%d/%ds) - dropping",
			NotificationConfig.PublishBudget, NotificationConfig.PublishWindow)
		return
	end

	local encoded
	local ok, err = pcall(function()
		encoded = HttpService:JSONEncode(payload)
	end)
	if not ok or not encoded then
		stats.Failed += 1
		Log.warn("BroadcastService", "Could not encode payload: %s", tostring(err))
		return
	end

	if #encoded > NotificationConfig.MaxPayloadBytes then
		stats.Dropped += 1
		Log.warn("BroadcastService", "Payload %d bytes, over the %d limit - dropping",
			#encoded, NotificationConfig.MaxPayloadBytes)
		return
	end

	table.insert(publishTimes, os.clock())

	local published, publishErr = pcall(function()
		MessagingService:PublishAsync(NotificationConfig.Topic, encoded)
	end)

	if published then
		stats.Published += 1
	else
		stats.Failed += 1
		Log.warn("BroadcastService", "PublishAsync failed: %s", tostring(publishErr))
	end
end

-- ── Receiving ───────────────────────────────────────────────────────────────

--[[
	docs/13 names "unvalidated inbound payloads" as this step's hazard.

	These messages come from our own servers, so this is not a trust boundary
	in the way a RemoteEvent is - but an old server running last week's code,
	or a truncated message, still has to fail as one dropped announcement
	rather than as a broken handler. Everything is decoded inside a pcall and
	sanitised to flat scalars before it goes anywhere near a client.
]]
local function onMessage(message)
	stats.Received += 1

	local raw = if type(message) == "table" then message.Data else message
	if type(raw) ~= "string" then
		return
	end

	local decoded
	local ok = pcall(function()
		decoded = HttpService:JSONDecode(raw)
	end)
	if not ok or type(decoded) ~= "table" then
		stats.Failed += 1
		return
	end

	-- Our own message coming back round. Already rendered locally.
	if decoded.From == SERVER_ID then
		return
	end

	local clean = NotificationConfig.Sanitise(decoded)
	if not clean then
		stats.Failed += 1
		return
	end

	BroadcastService.Received:Fire(clean)
end

function BroadcastService.GetStats()
	return table.clone(stats)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function BroadcastService.Init(_app) end

function BroadcastService.Start(_app)
	--[[
		SubscribeAsync yields and can throw - most often in Studio with API
		services disabled, which is the common case during development. A
		failure here means the game runs without cross-server announcements,
		not that it fails to start.
	]]
	local ok, result = pcall(function()
		return MessagingService:SubscribeAsync(NotificationConfig.Topic, onMessage)
	end)

	if ok then
		connection = result
		subscribed = true
	else
		Log.warn("BroadcastService", "Cross-server announcements are OFF: %s", tostring(result))
		if RunService:IsStudio() then
			Log.warn("BroadcastService",
				"In Studio this usually means API services are disabled (Game Settings > Security)")
		end
		return
	end

	task.spawn(function()
		while true do
			task.wait(DRAIN_INTERVAL)
			local drained, err = pcall(drain)
			if not drained then
				Log.error("BroadcastService", "Drain failed: %s", tostring(err))
			end
		end
	end)

	game:BindToClose(function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end)

	Log.info("BroadcastService", "Subscribed to '%s' as %s. Budget %d/%ds",
		NotificationConfig.Topic, string.sub(SERVER_ID, 1, 8),
		NotificationConfig.PublishBudget, NotificationConfig.PublishWindow)
end

return BroadcastService
