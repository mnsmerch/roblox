--!nonstrict
--[[
	SecurityService
	ServerScriptService/SAD_Server/Services/SecurityService  (ModuleScript)

	Validation layers 1, 3 and 5 from docs/09 §7.2: rate-limit enforcement,
	movement plausibility, and the server-side distance checks every interaction
	goes through. (Layer 2, argument shape, lives in Net; layer 4, state
	machines, lives in whichever service owns the state.)

	The core assumption: a Roblox character's physics are simulated on its
	OWNER'S CLIENT. The server sees the position the client reports. That is not
	a flaw to route around, it is the reason this file exists - every position a
	client reports is checked against how fast it could plausibly have got
	there.

	Responses are graded, and none of them is a kick:

		flag          logged and counted
		carry void    an implausible move invalidates any carry in progress
		correction    sustained flagging snaps the character back

	Kicking is deliberately absent. Mobile players on poor connections generate
	false positives, and disconnecting a child over network jitter is not an
	acceptable trade for catching a speed exploit. An exploiter who is snapped
	back every second is not playing either.

	API:
		SecurityService.CheckDistance(player, position, range?) -> ok, reason?
		SecurityService.SetMaxSpeed(player, speed)
		SecurityService.GetMaxSpeed(player) -> number
		SecurityService.Exempt(player, seconds)      -- teleports, launchers
		SecurityService.IsExempt(player) -> boolean
		SecurityService.Flag(player, kind, detail)
		SecurityService.GetFlagCount(player) -> number

		SecurityService.Flagged     Signal(player, kind, detail, count)
		SecurityService.CarryVoided Signal(player, reason)

	Depends on: GameConfig, Net, Log, Signal.
	Depended on by: EggService, StealService, and every future remote handler.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)

local SecurityService = {}

SecurityService.Flagged = Signal.new()
SecurityService.CarryVoided = Signal.new()

--- [player] = { { Kind, Detail, At } } within the flag window
local flags: { [Player]: { any } } = {}

--- [player] = last plausible position, and when it was sampled
local lastValid: { [Player]: { Position: Vector3, At: number } } = {}

--- [player] = the top speed this player is currently ALLOWED, set by whichever
--- service last changed it (carrying, upgrades, boosts).
local maxSpeed: { [Player]: number } = {}

--- [player] = os.clock() until which movement checks are suspended
local exemptUntil: { [Player]: number } = {}

-- ── Speed budget ────────────────────────────────────────────────────────────

--[[
	The speed this player should currently be capable of.

	EggService lowers it while carrying; UpgradeService raises it in Step 13.
	Movement plausibility is measured against THIS, so a client that edits its
	own WalkSpeed is measured against what the server intended rather than
	against whatever it claims.
]]
function SecurityService.SetMaxSpeed(player: Player, speed: number)
	maxSpeed[player] = speed
end

function SecurityService.GetMaxSpeed(player: Player): number
	return maxSpeed[player] or GameConfig.BaseWalkSpeed
end

-- ── Exemptions ──────────────────────────────────────────────────────────────

--[[
	Suspends movement checks. Teleports, launch pads, event portals and lava
	geysers all move a player faster than they could run, legitimately.

	Anything that moves a character without the character running MUST call
	this, or it will flag every player who uses it.
]]
function SecurityService.Exempt(player: Player, seconds: number)
	exemptUntil[player] = math.max(exemptUntil[player] or 0, os.clock() + seconds)
	lastValid[player] = nil
end

function SecurityService.IsExempt(player: Player): boolean
	return (exemptUntil[player] or 0) > os.clock()
end

-- ── Flagging ────────────────────────────────────────────────────────────────

function SecurityService.GetFlagCount(player: Player): number
	local record = flags[player]
	if not record then
		return 0
	end

	local cutoff = os.clock() - GameConfig.MovementFlagWindowSecs
	local count = 0
	for _, entry in record do
		if entry.At >= cutoff then
			count += 1
		end
	end
	return count
end

function SecurityService.Flag(player: Player, kind: string, detail: string)
	local record = flags[player]
	if not record then
		record = {}
		flags[player] = record
	end

	local now = os.clock()
	table.insert(record, { Kind = kind, Detail = detail, At = now })

	-- Drop anything outside the window so the list cannot grow forever.
	local cutoff = now - GameConfig.MovementFlagWindowSecs
	local kept = {}
	for _, entry in record do
		if entry.At >= cutoff then
			table.insert(kept, entry)
		end
	end
	flags[player] = kept

	local count = #kept
	Log.warn("SecurityService", "%s flagged: %s (%s) [%d in %ds]",
		player.Name, kind, detail, count, GameConfig.MovementFlagWindowSecs)

	SecurityService.Flagged:Fire(player, kind, detail, count)
end

-- ── Distance ────────────────────────────────────────────────────────────────

--[[
	Layer 5. Is this player close enough to interact with something at
	`position`?

	Every interaction in the game goes through here rather than trusting a
	ProximityPrompt, which enforces its range on the client - the one place an
	exploiter can simply delete the check.

	The default range is generous by roughly one prompt radius, so an honest
	player on a laggy connection is not punished for latency.
]]
function SecurityService.CheckDistance(player: Player, position: Vector3, range: number?): (boolean, string?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "no character"
	end

	local allowed = range or GameConfig.InteractRangeStuds
	local distance = (root.Position - position).Magnitude
	if distance > allowed then
		return false, string.format("%.0f studs away, limit %.0f", distance, allowed)
	end

	return true, nil
end

-- ── Movement plausibility ───────────────────────────────────────────────────

local function sampleMovement()
	local now = os.clock()

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			lastValid[player] = nil
			continue
		end

		local position = root.Position

		if SecurityService.IsExempt(player) then
			lastValid[player] = { Position = position, At = now }
			continue
		end

		local previous = lastValid[player]
		if not previous then
			lastValid[player] = { Position = position, At = now }
			continue
		end

		local elapsed = now - previous.At
		if elapsed <= 0 then
			continue
		end

		--[[
			Horizontal distance only. Falling is fast, legal, and entirely
			normal in a game about running away from things - measuring the
			vertical component would flag every player who steps off a ledge.
		]]
		local delta = position - previous.Position
		local horizontal = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
		local impliedSpeed = horizontal / elapsed

		local budget = SecurityService.GetMaxSpeed(player) * GameConfig.SpeedToleranceMultiplier

		if impliedSpeed > budget then
			SecurityService.Flag(player, "SuspiciousMovement",
				string.format("%.0f studs/s, budget %.0f", impliedSpeed, budget))

			-- An implausible move invalidates anything being carried, which is
			-- the actual exploit this defends: teleport to a nest, grab, and
			-- teleport home (docs/03 §6).
			SecurityService.CarryVoided:Fire(player, "implausible movement")

			if GameConfig.MovementCorrectionEnabled
				and SecurityService.GetFlagCount(player) >= GameConfig.MovementFlagsBeforeCorrection then
				root.CFrame = CFrame.new(previous.Position)
				Log.warn("SecurityService", "Corrected %s back to their last valid position", player.Name)
			end

			-- Do NOT advance the baseline: the next sample is compared against
			-- the last position we actually believed.
			continue
		end

		lastValid[player] = { Position = position, At = now }
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function SecurityService.Init(app)
	--[[
		Net drops over-limit and malformed calls at the network edge on its own;
		this is where those drops become a player-level record, so a client
		spraying one remote is visible rather than merely ignored.
	]]
	Net.SetViolationHandler(function(player: Player, kind: string, remoteName: string, detail: string)
		SecurityService.Flag(player, kind, string.format("%s: %s", remoteName, detail))
	end)
end

function SecurityService.Start(app)
	Players.PlayerRemoving:Connect(function(player)
		flags[player] = nil
		lastValid[player] = nil
		maxSpeed[player] = nil
		exemptUntil[player] = nil
	end)

	-- A fresh character has no movement history, and spawning is a teleport.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			lastValid[player] = nil
			SecurityService.Exempt(player, 3)
		end)
	end)

	local interval = 1 / GameConfig.SecuritySampleHz
	task.spawn(function()
		while true do
			task.wait(interval)
			local ok, err = pcall(sampleMovement)
			if not ok then
				Log.error("SecurityService", "Movement sampling failed: %s", tostring(err))
			end
		end
	end)

	Log.info("SecurityService", "Movement plausibility at %d Hz, tolerance %.1fx, correction %s",
		GameConfig.SecuritySampleHz,
		GameConfig.SpeedToleranceMultiplier,
		GameConfig.MovementCorrectionEnabled and "on" or "off")
end

return SecurityService
