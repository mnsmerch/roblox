--!nonstrict
--[[
	AnimationController
	.../SAD_Client/Controllers/AnimationController  (ModuleScript)

	Everything in the world that should look alive. The last entry in the
	client roster to be built, and the reason it was last is worth stating
	before the code.

	═══ THE MODELS IN THIS GAME CANNOT PLAY ANIMATIONS ═════════════════════════
	`WildAIService`'s header: guardians "are ANCHORED and moved by CFrame rather
	than driven by Humanoids. The placeholder models have no rig."

	A Roblox `Animation` needs an `Animator`; an `Animator` needs a `Humanoid`
	or an `AnimationController` instance; both need joints. `AssetBuilder`
	welds a head onto a block. There are no joints, so there is nothing to
	animate, and no amount of asset work changes that until the models are
	replaced.

	So this controller has two paths and picks between them by asking the model
	rather than by reading a flag:

	  RIGGED   → look the clip up by name in `SAD_Assets/Animations`, load it
	             on the model's own `Animator`, play it. Real animation.
	  NOT      → apply a small local CFrame offset on top of the server-driven
	             pivot: a breath, a stride bob, a crouch before a charge.

	The second is what actually runs today. It is a stand-in and it is written
	as one - every number in `AnimationConfig.Motions` is deliberately small,
	because a stand-in that draws attention to itself is worse than stillness.
	═══════════════════════════════════════════════════════════════════════════

	═══ IT IS LOCAL, AND THAT IS THE POINT ════════════════════════════════════
	Every offset here is applied on the client only. The server's pivot is the
	truth; this moves the *rendering* of it by a fraction of a stud.

	Same call `WeatherController` made about Lighting: a visual that fails
	locally has broken one player's screen, and one driven from the server and
	left wrong is wrong for everybody until a restart. It also means the
	animation budget is spent per device - the phone does less work than the
	desktop beside it, for free.
	═══════════════════════════════════════════════════════════════════════════

	API:
		AnimationController.Play(model, clipName, opts?) -> track?
		AnimationController.Stop(model, clipName?)
		AnimationController.SetState(model, clipName)     -- a held pose or loop
		AnimationController.Register(model, archetypeId?, gaitDriven?)
		AnimationController.Forget(model)
		AnimationController.IsAvailable(clipName) -> boolean
		AnimationController.Report() -> { Tracked, Animated, Rigged, Procedural }

	Depends on: StateController, AnimationConfig, ChaseConfig, DinoConfig,
	            GameConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local AnimationConfig = require(Shared.Config.AnimationConfig)
local DinoConfig = require(Shared.Config.DinoConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Modules.Log)

local AnimationController = {}

local StateController

local player = Players.LocalPlayer

--[[
	One entry per model being animated:
		{ Model, Archetype, BasePivot, LastPosition, Speed, State,
		  HoldClip, HoldUntil, Animator, Tracks }

	Keyed by the Model instance, so a destroyed model's entry goes with it -
	`Forget` is called from `AncestryChanged` rather than by a sweep.
]]
local tracked: { [Model]: any } = {}
local trackedCount = 0

--- Round-robin cursor, so the budget cuts a different set of models each frame
--- rather than always starving the same tail of the table.
local cursor = nil

local assetFolder = nil
local missingWarned: { [string]: boolean } = {}

local counters = { Rigged = 0, Procedural = 0, Animated = 0 }

-- ── Assets ──────────────────────────────────────────────────────────────────

--[[
	`SAD_Assets/Animations/<clip>`. Absent until somebody makes them, exactly
	like `SoundController`'s sounds - and absent is a no-op, never an error.
]]
local function findClip(clipName: string): Animation?
	if not assetFolder then
		return nil
	end
	local found = assetFolder:FindFirstChild(clipName)
	if found and found:IsA("Animation") then
		return found
	end
	return nil
end

function AnimationController.IsAvailable(clipName: string): boolean
	return findClip(clipName) ~= nil
end

--[[
	A model's `Animator`, or nil if it has no rig.

	Asked of the model rather than assumed, because both answers are legitimate
	in this game at the same time: a rigged Titan and a placeholder Compy can be
	on screen together, and each should get the best motion it can support.
]]
local function animatorOf(model: Model): Animator?
	local host = model:FindFirstChildOfClass("Humanoid")
		or model:FindFirstChildOfClass("AnimationController")
	if not host then
		return nil
	end

	local existing = host:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end

	local animator = Instance.new("Animator")
	animator.Parent = host
	return animator
end

-- ── Registration ────────────────────────────────────────────────────────────

--[[
	Opts a model in. Called from the folder watchers below, and callable
	directly for anything that appears another way.

	The offset is applied on top of the model's CURRENT pivot every frame rather
	than accumulated onto a stored base, so a moving model's animation follows
	the server rather than fighting it, and there is no state to drift.

	`gaitDriven` is false for the player's own character, and that distinction
	matters more than it looks.

	Roblox's default `Animate` script already plays walk and run on a player
	character. Deriving a gait here and playing our own `Walk` on top of it
	would be two animations fighting for the same joints the day a `Walk` asset
	lands - so the character is registered for the EVENT clips docs/15 §2 lists
	for it (Carry Egg, Trip, Steal Hold) and nothing else.

	Everything out of the watched folders is gait-driven: nothing else is
	animating them, because nothing else can.
]]
function AnimationController.Register(model: Model, archetypeId: string?, gaitDriven: boolean?)
	if tracked[model] or not model:IsA("Model") then
		return
	end

	--[[
		The archetype decides the CHARACTER of the motion (a Bulldozer lumbers,
		a Skitterer scurries). Read from the model's own `SpeciesId` attribute,
		which `WildAIService` already stamps, so nothing new has to be sent.
	]]
	local archetype = archetypeId
	if not archetype then
		local speciesId = model:GetAttribute("SpeciesId")
		local species = speciesId and DinoConfig.Get(speciesId)
		archetype = species and species.ChaseArchetype or nil
	end

	local animator = animatorOf(model)
	local entry = {
		Model = model,
		Archetype = archetype,
		Animator = animator,
		Tracks = {},
		Speed = 0,
		State = "Idle",
		LastPosition = nil,
		HoldClip = nil,
		HoldUntil = 0,
		LastAbilityAt = nil,
		GaitDriven = gaitDriven ~= false,
		Phase = math.random() * math.pi * 2, -- so twenty guardians do not bob in lockstep
	}

	tracked[model] = entry
	trackedCount += 1
	if animator then
		counters.Rigged += 1
	else
		counters.Procedural += 1
	end

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			AnimationController.Forget(model)
		end
	end)
end

function AnimationController.Forget(model: Model)
	local entry = tracked[model]
	if not entry then
		return
	end
	for _, track in entry.Tracks do
		pcall(function()
			track:Stop(0.1)
		end)
	end
	if entry.Animator then
		counters.Rigged -= 1
	else
		counters.Procedural -= 1
	end
	tracked[model] = nil
	trackedCount -= 1
	if cursor == model then
		cursor = nil
	end
end

-- ── Playing ─────────────────────────────────────────────────────────────────

--[[
	Plays a clip on a model.

	Returns the `AnimationTrack` when a real animation ran, and nil when the
	procedural stand-in did - so a caller can tell the difference if it needs
	to, and almost none of them do.
]]
function AnimationController.Play(model: Model, clipName: string, opts)
	local entry = tracked[model]
	if not entry then
		AnimationController.Register(model)
		entry = tracked[model]
		if not entry then
			return nil
		end
	end

	local clip = AnimationConfig.Clips[clipName]
	if not clip then
		--[[
			Refused rather than guessed. A clip that is not in the catalogue is
			one nobody declared a fallback for, and a typo would otherwise be a
			silent no-op forever.
		]]
		if not missingWarned[clipName] then
			missingWarned[clipName] = true
			Log.warn("AnimationController", "'%s' is not in AnimationConfig; ignoring", clipName)
		end
		return nil
	end

	local asset = findClip(clipName)
	if asset and entry.Animator then
		local track = entry.Tracks[clipName]
		if not track then
			local ok, loaded = pcall(function()
				return entry.Animator:LoadAnimation(asset)
			end)
			if ok then
				track = loaded
				--[[
					A gait loops under Movement so the character controller can
					blend it; a one-shot plays over the top as an Action, or a
					Trip would be drowned out by the walk it interrupts.
				]]
				track.Priority = if clip.Looped
					then Enum.AnimationPriority.Movement
					else Enum.AnimationPriority.Action
				track.Looped = clip.Looped == true
				entry.Tracks[clipName] = track
			end
		end
		if track then
			track:Play((opts and opts.FadeSecs) or 0.15, 1, (opts and opts.Speed) or 1)
			return track
		end
	end

	--[[
		No asset, or no rig. Hold the procedural stand-in for this clip's
		duration; a clip with no stand-in simply does nothing, which is the
		honest outcome and better than a wrong motion.
	]]
	if clip.Procedural then
		local motion = AnimationConfig.Motions[clip.Procedural]
		--[[
			`opts.Secs` overrides the motion's own duration, which is how the
			wind-up crouch runs for exactly as long as the wind-up it belongs
			to rather than for a fixed time that may outlast it.
		]]
		local secs = (opts and opts.Secs) or motion.Secs
		entry.HoldClip = clip.Procedural
		entry.HoldUntil = if secs then os.clock() + secs else math.huge
	end
	return nil
end

function AnimationController.Stop(model: Model, clipName: string?)
	local entry = tracked[model]
	if not entry then
		return
	end
	if clipName then
		local track = entry.Tracks[clipName]
		if track then
			pcall(function()
				track:Stop(0.15)
			end)
		end
		if entry.HoldClip == (AnimationConfig.Clips[clipName] or {}).Procedural then
			entry.HoldClip = nil
			entry.HoldUntil = 0
		end
		return
	end
	for _, track in entry.Tracks do
		pcall(function()
			track:Stop(0.15)
		end)
	end
	entry.HoldClip = nil
	entry.HoldUntil = 0
end

--- A held pose or loop that persists until something replaces it - the
--- de-aggro huff, a park dinosaur sleeping.
function AnimationController.SetState(model: Model, clipName: string)
	return AnimationController.Play(model, clipName)
end

-- ── The frame ───────────────────────────────────────────────────────────────

local function lowGraphics(): boolean
	local data = StateController and StateController.Get()
	return data ~= nil and data.Settings ~= nil and data.Settings.LowGraphics == true
end

local function cullDistance(): number
	local base = AnimationConfig.CullDistance
	return if lowGraphics() then base * AnimationConfig.LowGraphicsScale else base
end

local function budget(): number
	local base = AnimationConfig.MaxAnimatedPerFrame
    return math.max(1, math.floor(
		if lowGraphics() then base * AnimationConfig.LowGraphicsScale else base))
end

--[[
	One model's frame.

	Measures how far it moved since last time to derive its state, then applies
	the offset for whichever motion is current. A model with a real rig gets its
	state pushed to the animator instead and no CFrame offset at all - the two
	paths never both move the same model.
]]
local function stepModel(entry, dt: number, cameraPosition: Vector3, maxDistance: number): boolean
	local model = entry.Model
	if not model.PrimaryPart then
		return false
	end

	local pivot = model:GetPivot()
	local position = pivot.Position

	if (position - cameraPosition).Magnitude > maxDistance then
		--[[
			Out of range. `LastPosition` is still updated, so a model that
			comes back into range does not report a single enormous frame of
			movement and snap into a run.
		]]
		entry.LastPosition = position
		return false
	end

	if entry.LastPosition and dt > 0 then
		local moved = (position - entry.LastPosition).Magnitude
		--[[
			Smoothed, because the server steers at 6 Hz and the raw
			frame-to-frame delta flickers between walk and run on the boundary.
			A dinosaur that switches gait four times a second reads as broken.
		]]
		entry.Speed = entry.Speed + (moved / dt - entry.Speed) * math.min(dt * 6, 1)
	end
	entry.LastPosition = position

	-- A held clip outranks the movement state until it expires.
	local now = os.clock()
	if entry.HoldClip and now > entry.HoldUntil then
		entry.HoldClip = nil
	end

	--[[
		docs/03 §1.2's wind-up tell. `WildAIService` stamps `AbilityAt`,
		`WindupSecs` and `Ability` on the model when a wind-up starts;
		attributes replicate on their own, so this costs no remote.

		Read here rather than pushed, and compared in os.time() seconds because
		os.clock() is per-machine and a deadline from the server would be
		meaningless on this one.
	]]
	local abilityAt = model:GetAttribute("AbilityAt")
	if abilityAt and abilityAt ~= entry.LastAbilityAt then
		entry.LastAbilityAt = abilityAt
		local windup = model:GetAttribute("WindupSecs") or 0
		if windup > 0 then
			-- Held for exactly the wind-up, so the tell ends as the ability
			-- begins rather than overlapping it.
			AnimationController.Play(model, AnimationConfig.WindupClip, { Secs = windup })
			--[[
				The ability itself follows the wind-up rather than replacing it,
				so the crouch reads as leading into the charge instead of being
				interrupted by it.
			]]
			task.delay(windup, function()
				if tracked[model] then
					local clip = AnimationConfig.AbilityClip[model:GetAttribute("Ability")]
					if clip then
						AnimationController.Play(model, clip)
					end
				end
			end)
		else
			local clip = AnimationConfig.AbilityClip[model:GetAttribute("Ability")]
			if clip then
				AnimationController.Play(model, clip)
			end
		end
	end

	local state = entry.State
	if entry.GaitDriven then
		state = AnimationConfig.StateFor(entry.Speed, GameConfig.BaseWalkSpeed)
		if entry.State ~= state then
			entry.State = state
			if entry.Animator then
				AnimationController.Play(model, state)
			end
		end
	end

	--[[
		Rigged models stop here: the animator moves the joints and an added
		CFrame offset would double the motion.
	]]
	if entry.Animator then
		return true
	end

	--[[
		A model that is not gait-driven only ever shows a held clip: the player
		character has no procedural motion of its own here, and applying one
		would fight Roblox's character controller.
	]]
	local motionName = entry.HoldClip
	if not motionName and entry.GaitDriven then
		motionName = AnimationConfig.Clips[state] and AnimationConfig.Clips[state].Procedural
	end
	local motion = motionName and AnimationConfig.Motions[motionName]
	if not motion then
		return false
	end

	local style = AnimationConfig.StyleFor(entry.Archetype)

	--[[
		Stride scales with actual speed, which is the whole difference between
		a walk and a run when both use one motion: the same bob, harder.
	]]
	local intensity = 1
	if motionName == "stride" then
		intensity = math.clamp(entry.Speed / GameConfig.BaseWalkSpeed, 0.3, 1.6)
	end

	local hz = motion.Hz * style.HzScale
	local phase = entry.Phase + now * hz * math.pi * 2
	local wave = if hz > 0 then math.sin(phase) else 1

	local lift = motion.Height * style.HeightScale * intensity * wave
	local pitch = motion.Pitch * style.LeanScale * intensity
	local roll = motion.Roll * style.LeanScale * intensity * wave

	--[[
		Applied on top of the server pivot every frame rather than accumulated,
		so a dropped frame or a teleport cannot leave a model permanently
		leaning. There is no state to drift.
	]]
	model:PivotTo(pivot * CFrame.new(0, lift, 0) * CFrame.Angles(pitch, 0, roll))
	return true
end

local function stepAll(dt: number)
	local camera = Workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position or Vector3.zero
	local maxDistance = cullDistance()
	local remaining = budget()

	counters.Animated = 0

	--[[
		Round-robin from wherever the last frame stopped. With a flat `pairs`
		loop the same models would always be inside the budget and the same
		tail always frozen; this way the cut moves.
	]]
	local started = false
	for model, entry in tracked do
		if cursor == nil or started or model == cursor then
			started = true
			if remaining <= 0 then
				cursor = model
				return
			end
			if stepModel(entry, dt, cameraPosition, maxDistance) then
				counters.Animated += 1
				remaining -= 1
			end
		end
	end

	-- Reached the end of the table; begin again next frame.
	cursor = nil
end

-- ── Watching the world ──────────────────────────────────────────────────────

--[[
	Models arrive in three folders `NestService` creates. Watched rather than
	polled, and each is optional: a folder that does not exist yet simply has
	nothing in it, which is what a partially-built world looks like.
]]
local WATCHED = { "Guardians", "ParkDinos", "CarriedEggs" }

local function watch(folder: Instance)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			AnimationController.Register(child)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			AnimationController.Register(child)
		end
	end)
end

function AnimationController.Report()
	return {
		Tracked = trackedCount,
		Animated = counters.Animated,
		Rigged = counters.Rigged,
		Procedural = counters.Procedural,
	}
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function AnimationController.Init(app)
	StateController = app.Get("StateController")
end

function AnimationController.Start(_app)
	local assets = ReplicatedStorage:FindFirstChild("SAD_Assets")
	assetFolder = assets and assets:FindFirstChild(AnimationConfig.AssetFolder)

	task.spawn(function()
		--[[
			`SAD_Runtime` is created by the server on boot, so the client can
			arrive before it. Waited for rather than assumed, and each folder is
			watched the moment it appears.
		]]
		local runtime = Workspace:WaitForChild("SAD_Runtime", 30)
		if not runtime then
			Log.warn("AnimationController", "SAD_Runtime never appeared; nothing to animate")
			return
		end
		for _, name in WATCHED do
			local folder = runtime:FindFirstChild(name)
			if folder then
				watch(folder)
			else
				task.spawn(function()
					local late = runtime:WaitForChild(name, 30)
					if late then
						watch(late)
					end
				end)
			end
		end
	end)

	RunService.RenderStepped:Connect(stepAll)

	--[[
		`Play` is the whole public surface, so the events that should trigger a
		one-shot are wired by the controllers that already own them - this
		subscribes to nothing. The one exception is the player's own character,
		which has a real rig and is therefore the one thing here that can play
		a real clip the day the assets land.
	]]
	local function bindCharacter(character: Model)
		if character then
			-- Not gait-driven: see Register's header.
			AnimationController.Register(character, nil, false)
		end
	end
	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	local available = 0
	for _, name in AnimationConfig.ClipOrder do
		if AnimationController.IsAvailable(name) then
			available += 1
		end
	end

	if available == 0 then
		Log.info("AnimationController",
			"Ready. 0 of %d clips have assets, so everything runs on procedural "
				.. "motion - drop Animation instances in SAD_Assets/%s to change that",
			#AnimationConfig.ClipOrder, AnimationConfig.AssetFolder)
	else
		Log.info("AnimationController", "Ready. %d of %d clips have assets",
			available, #AnimationConfig.ClipOrder)
	end
end

return AnimationController
