--!nonstrict
--[[
	Replication
	.../Services/PlayerDataService/Replication  (ModuleScript)

	Mirrors a slice of each player's profile onto their own client, and only
	their own client.

	Two properties matter more than efficiency here:

	1. THE SLICE IS AN ALLOWLIST. Fields are withheld by default and must be
	   named to be replicated. A denylist leaks every field someone adds later
	   and forgets about - the failure mode is silent and the consequence is a
	   receipt id or an anti-cheat counter sitting in a client's memory for an
	   exploiter to read. Init() asserts that every profile key appears in
	   exactly one of REPLICATED or WITHHELD, so adding a field to the schema
	   forces a deliberate decision about it.

	2. THE CLIENT IS A MIRROR, NEVER A SOURCE. Nothing here reads client state.
	   Deltas flow one way. The client's copy is for drawing.

	How it works: changes mark top-level keys dirty; a 5 Hz loop diffs only
	those subtrees against the last-sent snapshot and ships the differences as
	patches. Currency flushes immediately, because a Fossil counter that lags a
	fifth of a second feels broken.

	Depends on: Net, Log, Signal, TableUtil, GameConfig, ProfileTemplate.
	Owned by: PlayerDataService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Patch = require(Shared.Modules.Patch)
local TableUtil = require(Shared.Modules.TableUtil)

local Replication = {}

--[[
	Sent to the owning client. Everything else is withheld.
	Adding a key here is a security decision - make it deliberately.
]]
local REPLICATED = {
	Fossils = true,
	DNA = true,
	Rebirths = true,
	ZonesUnlocked = true,
	Shrines = true,
	Upgrades = true,
	Defences = true,
	LuckNodes = true,
	BonusDinoSlots = true,
	BonusVaultSlots = true,
	Titles = true,
	Dinos = true,
	Eggs = true,
	Incubators = true,
	Index = true,
	IndexMilestones = true,
	Boosts = true,
	Items = true,
	ShieldUntil = true,
	ShieldBankSecs = true,
	Daily = true,
	Quests = true,
	Tutorial = true,
	Gamepasses = true,
	Settings = true,
	Stats = true,
	BankedFossils = true,
	BankedAt = true,
	NewPlayerProtectionDone = true,
}

--[[
	Deliberately NOT sent, with the reason. Init() asserts this list plus
	REPLICATED covers the whole schema, so a new field cannot slip through
	either way.
]]
local WITHHELD = {
	SchemaVersion = "server bookkeeping; the client has no use for it",
	ProcessedReceipts = "Robux receipt ids - never leaves the server",
	RobuxSpent = "spend history; nothing on the client should render it",
	LastSeen = "used only to compute offline income, server-side",
	FirstJoinAt = "account age drives protection rules; server-side only",
	StealCooldowns = "who you may raid is decided server-side; the prompt says why",
	RevengeMarks = "same - the halved hold time is applied where it is checked",
	RobbedAt = "raid history feeding the Mercy Shield; the shield itself replicates",
	GlobalStealAt = "the 90-second raid cooldown; enforced where it is read",
	BankedRate = "the rate the current banking interval accrues at; the client "
		.. "renders the LIVE rate, which it derives from its own dinosaurs",
}

--- Flushed the moment they change rather than on the next tick.
local IMMEDIATE = { Fossils = true, DNA = true }

--- Past this many patches in one flush, a full snapshot is cheaper to build,
--- cheaper to send and far cheaper to reason about than a giant patch list.
local MAX_PATCHES = 60

--- Floor between immediate flushes, so a burst of income collection cannot
--- turn into a remote call per frame.
local IMMEDIATE_MIN_INTERVAL = 0.05

--[[
	Resolved once in Init rather than inside the flush loop.

	Requiring the parent at module load would be a circular require - it loads
	us. By Init the parent has fully returned, so the reference is safe to hold,
	and hoisting it keeps require() out of a 5 Hz path.
]]
local Owner = nil

local snapshots: { [Player]: any } = {}
local dirty: { [Player]: any } = {}
local ready: { [Player]: boolean } = {}
local lastImmediate: { [Player]: number } = {}

local ALL = "\0all"

-- ── Diffing ─────────────────────────────────────────────────────────────────
--
-- Diff and apply live in SAD_Shared/Modules/Patch, shared with the client that
-- consumes these deltas. See that module for why.

-- ── Snapshots ───────────────────────────────────────────────────────────────

local function buildSlice(data)
	local slice = {}
	for key in REPLICATED do
		local value = data[key]
		slice[key] = if type(value) == "table" then TableUtil.DeepCopy(value) else value
	end
	return slice
end

--- Full state. Also the recovery path whenever a delta would be too large or
--- the client asks to resync.
function Replication.SendFull(player: Player, data)
	if not data then
		return
	end

	local slice = buildSlice(data)
	snapshots[player] = slice
	dirty[player] = nil
	ready[player] = true

	Net.FireClient("StateFull", player, buildSlice(data))
	Log.debug("Replication", "Sent full state to %s", player.Name)
end

-- ── Dirty tracking ──────────────────────────────────────────────────────────

--[[
	Marks top-level keys as changed. `keys` nil means "everything", which is the
	safe default: a caller that forgets to declare what it touched costs one
	wider diff, not a desynced client.
]]
function Replication.MarkDirty(player: Player, keys: { string }?)
	if not ready[player] then
		return
	end

	local current = dirty[player]
	if current == ALL then
		return
	end

	if not keys then
		dirty[player] = ALL
		return
	end

	if not current then
		current = {}
		dirty[player] = current
	end

	local immediate = false
	for _, key in keys do
		if REPLICATED[key] then
			current[key] = true
			if IMMEDIATE[key] then
				immediate = true
			end
		end
	end

	if immediate then
		local now = os.clock()
		if now - (lastImmediate[player] or 0) >= IMMEDIATE_MIN_INTERVAL then
			lastImmediate[player] = now
			Replication.Flush(player)
		end
	end
end

-- ── Flushing ────────────────────────────────────────────────────────────────

function Replication.Flush(player: Player)
	local pending = dirty[player]
	if not pending then
		return
	end

	local data = Owner.Get(player)
	local snapshot = snapshots[player]

	if not data or not snapshot then
		dirty[player] = nil
		return
	end

	dirty[player] = nil

	local keys = {}
	if pending == ALL then
		for key in REPLICATED do
			table.insert(keys, key)
		end
	else
		for key in pending do
			table.insert(keys, key)
		end
	end

	local patches = {}
	for _, key in keys do
		for _, patch in Patch.Diff(snapshot[key], data[key], { key }) do
			table.insert(patches, patch)
		end
	end

	if #patches == 0 then
		return
	end

	if #patches > MAX_PATCHES then
		Log.debug("Replication", "%d patches for %s - sending full state instead", #patches, player.Name)
		Replication.SendFull(player, data)
		return
	end

	-- Only advance the snapshot for what was actually diffed, so an untouched
	-- key stays comparable against the last state the client really received.
	for _, key in keys do
		local value = data[key]
		snapshot[key] = if type(value) == "table" then TableUtil.DeepCopy(value) else value
	end

	Net.FireClient("StateDelta", player, patches)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function Replication.Clear(player: Player)
	snapshots[player] = nil
	dirty[player] = nil
	ready[player] = nil
	lastImmediate[player] = nil
end

function Replication.Init(app)
	Owner = require(script.Parent)

	local ProfileTemplate = require(script.Parent.Parent.DataService.ProfileTemplate)

	--[[
		The security boundary, asserted at boot. Every profile key must be
		explicitly replicated or explicitly withheld. Adding a field to the
		schema without deciding fails the server here rather than quietly
		shipping it to clients, or quietly failing to.
	]]
	local undeclared = {}
	for key in ProfileTemplate do
		if not REPLICATED[key] and not WITHHELD[key] then
			table.insert(undeclared, key)
		end
	end
	if #undeclared > 0 then
		table.sort(undeclared)
		error(string.format(
			"[SAD] Replication: profile field(s) %s are neither replicated nor withheld. "
				.. "Add each to REPLICATED or WITHHELD in Replication.lua - this is a security decision.",
			table.concat(undeclared, ", ")
		), 0)
	end

	local stale = {}
	for key in REPLICATED do
		if ProfileTemplate[key] == nil then
			table.insert(stale, key)
		end
	end
	for key in WITHHELD do
		if ProfileTemplate[key] == nil then
			table.insert(stale, key)
		end
	end
	if #stale > 0 then
		table.sort(stale)
		error(string.format(
			"[SAD] Replication declares field(s) %s that are not in the profile schema.",
			table.concat(stale, ", ")
		), 0)
	end

	Log.info("Replication", "%d field(s) replicated, %d withheld",
		TableUtil.Count(REPLICATED), TableUtil.Count(WITHHELD))
end

function Replication.Start(app)
	--[[
		Resync path. Read-only and idempotent, so it is safe as a
		RemoteFunction. A client whose mirror is behind - a dropped packet, a
		delta that arrived before the snapshot - can always ask for the truth.
	]]
	Net.OnInvoke("GetProfileSnapshot", function(player: Player)
		local data = Owner.Get(player)
		if not data then
			return nil
		end
		return buildSlice(data)
	end)

	Players.PlayerRemoving:Connect(Replication.Clear)

	local interval = 1 / GameConfig.StateFlushHz
	task.spawn(function()
		while true do
			task.wait(interval)
			for player in dirty do
				local ok, err = pcall(Replication.Flush, player)
				if not ok then
					Log.error("Replication", "Flush failed for %s: %s", player.Name, tostring(err))
					dirty[player] = nil
				end
			end
		end
	end)

	Log.info("Replication", "Flushing at %d Hz", GameConfig.StateFlushHz)
end

--- Exposed for tests and for the Step 24 exploit sweep.
Replication._REPLICATED = REPLICATED
Replication._WITHHELD = WITHHELD

return Replication
