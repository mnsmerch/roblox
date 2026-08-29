--!nonstrict
--[[
	StateController
	StarterPlayerScripts/SAD_Client/Controllers/StateController  (ModuleScript)

	The client's mirror of its own profile slice, and the thing every other
	controller reads from. Nothing else on the client should hold game state.

	It is a MIRROR. Writing to it does not change anything on the server - it
	just makes this client draw a lie until the next patch corrects it. To
	change something, fire the matching Request remote and let the delta come
	back.

	API:
		StateController.Get()                  -> the mirror table (read only)
		StateController.GetPath({"Settings","MusicVolume"})  -> value?
		StateController.IsReady()              -> boolean
		StateController.Ready                  Signal()
		StateController.Changed                Signal(paths)
		StateController.Observe(path, fn)      -> { Disconnect }

	Observe is the one most UI wants. It fires immediately with the current
	value if state has arrived, then again on every change at or under that
	path, so a HUD element is written once and never polls:

		StateController.Observe({ "Fossils" }, function(value)
			label.Text = Format.Number(value or 0)
		end)

	Depends on: Net, Patch, Log, Signal.
	Depended on by: every UI controller from Step 5 onward.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Patch = require(Shared.Modules.Patch)
local Signal = require(Shared.Modules.Signal)

local StateController = {}

StateController.Ready = Signal.new()
StateController.Changed = Signal.new()

local state = {}
local isReady = false

--- Patches that arrived before the first snapshot. Applying them to an empty
--- table would build a half-real mirror out of partial paths.
local pendingPatches = {}
local MAX_PENDING = 40

local observers = {}

-- ── Path helpers ────────────────────────────────────────────────────────────
--
-- Reading, applying and path matching all come from SAD_Shared/Modules/Patch,
-- the same module the server diffs with, so producer and consumer cannot
-- disagree about what a patch means.

local readPath = Patch.Read
local applyPatch = Patch.Apply
local pathsOverlap = Patch.PathsOverlap

local function notify(changedPaths)
	for _, observer in observers do
		if not observer.Connected then
			continue
		end
		for _, changed in changedPaths do
			if pathsOverlap(observer.Path, changed) then
				task.spawn(observer.Callback, readPath(state, observer.Path))
				break
			end
		end
	end

	StateController.Changed:Fire(changedPaths)
end

-- ── Public API ──────────────────────────────────────────────────────────────

function StateController.Get()
	return state
end

function StateController.GetPath(path)
	return readPath(state, path)
end

function StateController.IsReady(): boolean
	return isReady
end

--[[
	Calls `callback(value)` now (if state has arrived) and on every later
	change at or under `path`. Returns a handle with :Disconnect().
]]
function StateController.Observe(path, callback)
	assert(type(path) == "table" and #path > 0, "Observe needs a non-empty path")
	assert(type(callback) == "function", "Observe needs a callback")

	local observer = {
		Path = table.clone(path),
		Callback = callback,
		Connected = true,
	}
	observer.Disconnect = function()
		observer.Connected = false
		for index, entry in observers do
			if entry == observer then
				table.remove(observers, index)
				break
			end
		end
	end

	table.insert(observers, observer)

	if isReady then
		task.spawn(callback, readPath(state, observer.Path))
	end

	return observer
end

--- Asks the server for a fresh snapshot. Yields. Used when the mirror looks
--- wrong - deltas ahead of the snapshot, or a UI that opened mid-load.
function StateController.Resync()
	local ok, snapshot = pcall(Net.Invoke, "GetProfileSnapshot")
	if not ok or type(snapshot) ~= "table" then
		Log.warn("StateController", "Resync failed")
		return false
	end

	state = snapshot
	isReady = true
	pendingPatches = {}

	local everything = {}
	for key in state do
		table.insert(everything, { key })
	end
	notify(everything)

	Log.info("StateController", "Resynced")
	return true
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function StateController.Init(app)
	Net.On("StateFull", function(snapshot)
		if type(snapshot) ~= "table" then
			return
		end

		state = snapshot
		pendingPatches = {}

		local firstTime = not isReady
		isReady = true

		local everything = {}
		for key in state do
			table.insert(everything, { key })
		end
		notify(everything)

		if firstTime then
			StateController.Ready:Fire()
			Log.info("StateController", "State ready")
		else
			Log.debug("StateController", "Full state refreshed")
		end
	end)

	Net.On("StateDelta", function(patches)
		if type(patches) ~= "table" then
			return
		end

		if not isReady then
			-- Applying patches to an empty mirror produces a plausible-looking
			-- but wrong state, so hold them until the snapshot lands.
			for _, patch in patches do
				table.insert(pendingPatches, patch)
			end
			if #pendingPatches > MAX_PENDING then
				Log.warn("StateController", "%d patches queued with no snapshot - resyncing", #pendingPatches)
				pendingPatches = {}
				task.spawn(StateController.Resync)
			end
			return
		end

		local changedPaths = {}
		for _, patch in patches do
			applyPatch(state, patch)
			table.insert(changedPaths, patch.Path)
		end
		notify(changedPaths)
	end)
end

function StateController.Start(app)
	--[[
		The server sends StateFull as part of loading a profile, which normally
		lands before this runs. If it does not - a slow DataStore, a rejoin
		racing the load - ask once rather than sitting at an empty HUD.
	]]
	task.spawn(function()
		task.wait(5)
		if not isReady then
			Log.warn("StateController", "No state after 5s - requesting a snapshot")
			StateController.Resync()
		end
	end)
end

return StateController
