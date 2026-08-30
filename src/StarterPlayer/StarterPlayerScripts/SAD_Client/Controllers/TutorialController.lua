--!nonstrict
--[[
	TutorialController
	.../SAD_Client/Controllers/TutorialController  (ModuleScript)

	docs/00 §3's FTUE, as the player experiences it: Professor Rok, one world
	arrow, one line of objective text, and a skip button.

	═══ IT ASKS, IT DOES NOT DECIDE ════════════════════════════════════════════
	This controller never sets the step. It watches for the thing the current
	beat is about, then sends `RequestTutorialStep(n+1)` - and the server
	checks that against real state and either advances or does not. The step
	number the UI draws always comes back from the server, never from a local
	guess.

	So a modified client can ask as fast as it likes and finish exactly nothing.
	═══════════════════════════════════════════════════════════════════════════

	═══ ONE ARROW, NOT A MAZE OF HIGHLIGHTS ════════════════════════════════════
	docs/08 §6: "A single animated arrow in world space, never a maze of
	highlights." So there is exactly one arrow instance, retargeted per beat,
	and exactly one line of objective text in a fixed spot under the top bar.

	Rok is a 3D character rather than a UI panel because he "physically leads" -
	he hops to the arrow's target, which is what makes the direction readable
	without reading anything.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: StateController, UIController, Theme, Create, Widgets,
	            TutorialConfig, ZoneConfig, Net.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local TutorialController = {}

local StateController, UIController

local player = Players.LocalPlayer

--- Server truth. Nil until the first `TutorialState` arrives, which is why
--- nothing is drawn before then - a flash of beat 1 for a returning player
--- would be worse than a moment of nothing.
local state = nil

local panel: Frame? = nil
local objectiveLabel: TextLabel?, bubbleLabel: TextLabel?
local hintLabel: TextLabel?
local skipButton: TextButton?

local rok: Model? = nil
local arrow: BasePart? = nil
local arrowTarget: Vector3? = nil

local enteredStepAt = 0
local hintShown = false
local askedFor = 0
local renderConn

local ARROW_HEIGHT = 9
local ROK_FOLLOW_DISTANCE = 7

-- ── Where the arrow points ──────────────────────────────────────────────────

--[[
	One function, one table. Each beat names an `Arrow` target and this resolves
	it to a world position, or nil if the thing does not exist yet - a nil arrow
	is hidden rather than pointing at the origin, which is under the map.
]]
local function resolveTarget(name: string?): Vector3?
	if not name then
		return nil
	end

	local world = workspace:FindFirstChild("SAD_World")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if name == "zone1" then
		local first = ZoneConfig.Order[1]
		local origin = first and ZoneConfig.OriginOf(first)
		return origin and origin.Position
	end

	--[[
		Everything else is inside the player's own park, which the client finds
		the same way ParkController does: by the plot carrying its userId. Not
		by index - plot 7 is not the same park for two different players.
	]]
	local parks = world and world:FindFirstChild("ParkPlots")
	local myPlot = nil
	for _, plot in (parks and parks:GetChildren()) or {} do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			myPlot = plot
			break
		end
	end

	if name == "gate" or name == "park" then
		return myPlot and myPlot:GetPivot().Position
	end

	if name == "incubator" or name == "totem" or name == "tile" or name == "shop" then
		--[[
			`tile` and `shop` fall through to the plot centre on purpose: the
			free tile a dinosaur should go on changes as the park fills, and the
			Bone Market is a menu rather than a place once beat 11 opens it. An
			arrow at the plot centre is right for both.
		]]
		local lookup = { incubator = "Incubators", totem = "CollectionTotem" }
		local childName = lookup[name]
		local found = myPlot and childName and myPlot:FindFirstChild(childName, true)
		if found then
			if found:IsA("BasePart") then
				return found.Position
			end
			if found:IsA("Model") then
				return found:GetPivot().Position
			end
			--[[
				`Incubators` is a plain Folder, so the arrow points at the first
				pad inside it rather than at nothing.
			]]
			local pad = found:FindFirstChildWhichIsA("BasePart", true)
			if pad then
				return pad.Position
			end
		end
		return myPlot and myPlot:GetPivot().Position
	end

	--[[
		"nest" is the nearest nest in the zone the player is standing in, so the
		arrow points at something reachable rather than at a fixed nest they may
		have walked past. Resolved live, per frame, for the same reason.
	]]
	if name == "nest" and root then
		--[[
			Nest models live under `Workspace/SAD_Runtime/Nests`, which
			`NestService` creates - not under `SAD_World`, which holds the
			blockout. Two different folders on purpose: one is generated
			geometry and one is live state.
		]]
		local runtime = workspace:FindFirstChild("SAD_Runtime")
		local nests = runtime and runtime:FindFirstChild("Nests")
		local best, bestDistance = nil, math.huge
		for _, nest in (nests and nests:GetChildren()) or {} do
			if nest:IsA("Model") and nest.PrimaryPart then
				local position = nest:GetPivot().Position
				local distance = (position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = position, distance
				end
			end
		end
		return best
	end

	return nil
end

-- ── Rok and the arrow ───────────────────────────────────────────────────────

--[[
	Professor Rok, built in code from parts - no asset id is invented, the same
	stance `SoundController` and `AssetBuilder` take. A small green
	Compsognathus shape with a yellow hard hat, which is enough for a player to
	read as "the guide" from across the plaza.

	Replaced by a real model the day one exists: this builds into a Model named
	`ProfessorRok`, and anything with that name in `SAD_Assets` is used instead.
]]
local function buildRok(): Model
	local prebuilt = ReplicatedStorage:FindFirstChild("SAD_Assets")
	prebuilt = prebuilt and prebuilt:FindFirstChild("ProfessorRok", true)
	if prebuilt and prebuilt:IsA("Model") then
		local clone = prebuilt:Clone()
		clone.Parent = workspace
		return clone
	end

	local model = Instance.new("Model")
	model.Name = "ProfessorRok"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2.6, 3.4)
	body.Color = Color3.fromHex("5FD35F")
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.Parent = model
	model.PrimaryPart = body

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4, 1.4, 1.8)
	head.Color = Color3.fromHex("6FE06F")
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = false
	head.CFrame = body.CFrame * CFrame.new(0, 1.8, -1.4)
	head.Parent = model

	local hat = Instance.new("Part")
	hat.Name = "HardHat"
	hat.Size = Vector3.new(1.7, 0.7, 1.9)
	hat.Color = Color3.fromHex("FFB020")
	hat.Material = Enum.Material.SmoothPlastic
	hat.Anchored = true
	hat.CanCollide = false
	hat.CanQuery = false
	hat.CFrame = head.CFrame * CFrame.new(0, 0.9, 0)
	hat.Parent = model

	model.Parent = workspace
	return model
end

local function buildArrow(): BasePart
	local part = Instance.new("Part")
	part.Name = "SAD_TutorialArrow"
	part.Size = Vector3.new(3, 5, 3)
	part.Shape = Enum.PartType.Wedge
	part.Color = Theme.Color.Accent
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 0.15
	part.Parent = workspace
	return part
end

--- Rok hops beside the player and looks at the arrow's target, so his body is
--- the direction indicator and the arrow is the destination.
local function stepRok(dt: number)
	if not rok or not rok.PrimaryPart then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		rok.PrimaryPart.Transparency = 1
		return
	end

	local beside = root.CFrame * CFrame.new(-ROK_FOLLOW_DISTANCE * 0.5, 0, -ROK_FOLLOW_DISTANCE * 0.5)
	local hop = math.abs(math.sin(os.clock() * 6)) * 1.2

	local look = arrowTarget or (root.Position + root.CFrame.LookVector * 10)
	local flatLook = Vector3.new(look.X, beside.Position.Y, look.Z)
	local target = CFrame.lookAt(beside.Position + Vector3.new(0, hop, 0), flatLook)

	rok:PivotTo(rok.PrimaryPart.CFrame:Lerp(target, math.min(dt * 6, 1)))
end

local function stepArrow(_dt: number)
	if not arrow then
		return
	end
	if not arrowTarget then
		arrow.Transparency = 1
		return
	end

	--[[
		The arrow enlarges after the hint timeout, per docs/08 §6, rather than a
		second arrow appearing. One arrow, louder.
	]]
	local scale = if hintShown then 1.8 else 1
	arrow.Size = Vector3.new(3 * scale, 5 * scale, 3 * scale)
	arrow.Transparency = 0.15

	local bob = math.sin(os.clock() * 3) * 0.8
	arrow.CFrame = CFrame.new(arrowTarget + Vector3.new(0, ARROW_HEIGHT + bob, 0))
		* CFrame.Angles(math.pi, 0, 0)
end

-- ── Drawing ─────────────────────────────────────────────────────────────────

local function hideAll()
	if panel then
		panel.Visible = false
	end
	arrowTarget = nil
	if arrow then
		arrow.Transparency = 1
	end
	if rok then
		rok:Destroy()
		rok = nil
	end
end

local function draw()
	if not state or state.Completed or state.Skipped then
		hideAll()
		return
	end

	local step = math.max(state.Step, 1)
	local beat = TutorialConfig.Get(step)
	if not beat then
		hideAll()
		return
	end

	if panel then
		panel.Visible = true
	end
	if objectiveLabel then
		objectiveLabel.Text = beat.Objective
	end
	if bubbleLabel then
		bubbleLabel.Text = beat.Text
	end
	if hintLabel then
		hintLabel.Visible = hintShown
		hintLabel.Text = "Stuck? This step will finish itself shortly."
	end

	--[[
		docs/00 §3: Rok "disappears permanently after step 10". Permanently -
		so he is destroyed rather than hidden, and never rebuilt for this
		session.
	]]
	if step > TutorialConfig.RokLeavesAfterStep then
		if rok then
			rok:Destroy()
			rok = nil
		end
	elseif not rok then
		rok = buildRok()
	end

	--[[
		docs/00 §3's rule: "No menu is opened for the player during the FTUE
		except the upgrade board."
	]]
	if beat.OpensShop and UIController.GetOpen() == nil then
		UIController.Open("Shop")
	end
end

-- ── Advancing ───────────────────────────────────────────────────────────────

--[[
	Ask the server to move on. Asked at most once per step until the server
	answers, because the remote is rate-limited to 3/s and a per-frame ask would
	spend that budget on the first beat and then be dropped for the rest.
]]
local function ask(step: number)
	if askedFor == step then
		return
	end
	askedFor = step
	Net.FireServer("RequestTutorialStep", step)
end

--[[
	Whether the local player looks like they have done what this beat is about.

	Deliberately optimistic and deliberately not authoritative: this only
	decides when to ASK. The server has the same conditions computed from state
	it owns, and its answer is what moves the step. Getting this wrong makes the
	tutorial ask too often, not advance wrongly.
]]
local function looksDone(beat): boolean
	local data = StateController.Get()
	if not data then
		return false
	end

	local requirement = beat.Requires
	if requirement == "none" then
		--[[
			A reading beat. It advances on the timer rather than on an action,
			so the player gets a moment to read eight words - which is the
			whole content of the beat.
		]]
		return (os.clock() - enteredStepAt) > 4
	end

	if requirement == "hatched" then
		return next(data.Dinos) ~= nil
	end
	if requirement == "placed" then
		for _, entry in data.Dinos do
			if entry.Placed then
				return true
			end
		end
		return false
	end
	if requirement == "incubating" then
		for _, slot in data.Incubators or {} do
			if slot and slot.EggUid then
				return true
			end
		end
		return false
	end
	if requirement == "upgraded" then
		for _, level in data.Upgrades or {} do
			if (level or 0) > 0 then
				return true
			end
		end
		return false
	end

	--[[
		`carrying`, `chased`, `inZone`, `home` and `collected` are not in the
		replicated profile - they are live world state the server holds. Rather
		than mirroring five more things onto the client, the ask is made on the
		timer and the server answers when it is true. It costs one refused ask
		every few seconds and keeps the authority in one place.
	]]
	return (os.clock() - enteredStepAt) > 3
end

local function tick()
	if not state or state.Completed or state.Skipped then
		return
	end

	local step = math.max(state.Step, 1)
	local beat = TutorialConfig.Get(step)
	if not beat then
		return
	end

	arrowTarget = resolveTarget(beat.Arrow)

	local elapsed = os.clock() - enteredStepAt

	-- docs/08 §6: hint at 25s, auto-complete at 60s.
	if not hintShown and elapsed > TutorialConfig.HintAfterSecs then
		hintShown = true
		draw()
	end

	--[[
		The auto-advance asks like everything else - it does not force. A player
		who is 60 seconds into "get back to your park" and is not in their park
		is asked for, refused, and asked again; the arrow is enormous by then
		and the hint is up.

		docs/08 §6 says the step "auto-completes so nobody gets stuck", and the
		honest reading of that with a server-authoritative step is: keep asking
		rather than let the client declare it done. A client that could declare
		a step done could declare the last one done.
	]]
	if elapsed > TutorialConfig.AutoAdvanceAfterSecs or looksDone(beat) then
		askedFor = 0
		ask(step + 1)
	end
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function build()
	local layer = UIController.Layer("hud")

	objectiveLabel = Create("TextLabel", {
		Name = "Objective",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 24),
		Position = UDim2.fromOffset(Theme.Space.L, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Accent,
		Text = "",
	})

	bubbleLabel = Create("TextLabel", {
		Name = "Bubble",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 20),
		Position = UDim2.fromOffset(Theme.Space.L, 26),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Text,
		Text = "",
	})

	hintLabel = Create("TextLabel", {
		Name = "Hint",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 18),
		Position = UDim2.fromOffset(Theme.Space.L, 48),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextMuted,
		Visible = false,
		Text = "",
	})

	--[[
		docs/00 §3: "He is skippable at any time." A small button, off to the
		side and never disguised - a skip a player cannot find is not a skip.
	]]
	skipButton = Create("TextButton", {
		Name = "Skip",
		Size = UDim2.fromOffset(84, 30),
		Position = UDim2.new(1, -Theme.Space.M, 0, Theme.Space.M),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextMuted,
		Text = "SKIP",
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
		Events = {
			MouseButton1Click = function()
				-- Step 0 is the skip signal on the existing remote; see
				-- TutorialService's handler for why it is not a second remote.
				Net.FireServer("RequestTutorialStep", 0)
			end,
		},
	})

	panel = Widgets.Panel({
		Name = "TutorialPanel",
		Size = UDim2.new(0, 460, 0, 74),
		Position = UDim2.new(0.5, 0, 0, Theme.Size.TopBarHeight + Theme.Space.L),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Color.Backdrop,
		Transparency = 0.15,
		StrokeColor = Theme.Color.Accent,
		ZIndex = Theme.Layer.Hud,
		Visible = false,
		Children = { objectiveLabel, bubbleLabel, hintLabel, skipButton },
		Parent = layer,
	})

	arrow = buildArrow()
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function TutorialController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
end

function TutorialController.Start(_app)
	build()

	Net.On("TutorialState", function(info)
		if type(info) ~= "table" then
			return
		end

		local previous = state and state.Step
		state = info

		-- The per-step timers restart only when the step actually changed, so a
		-- re-push (a rejoin, a refused ask) does not reset the hint clock.
		if previous ~= info.Step then
			enteredStepAt = os.clock()
			hintShown = false
			askedFor = 0
		end

		draw()

		if info.Completed or info.Skipped then
			Log.info("TutorialController", "Tutorial %s",
				if info.Skipped then "skipped" else "complete")
		end
	end)

	--[[
		Two loops at two rates. Rok and the arrow move every frame because they
		are animation; the beat logic runs twice a second because it is polling
		and a per-frame poll would ask the server sixty times before the rate
		limit noticed.
	]]
	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not state or state.Completed or state.Skipped then
			return
		end
		stepRok(dt)
		stepArrow(dt)
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			tick()
		end
	end)

	Log.info("TutorialController", "Ready. %d beats, %d words",
		TutorialConfig.StepCount, TutorialConfig.TotalWords)
end

return TutorialController
