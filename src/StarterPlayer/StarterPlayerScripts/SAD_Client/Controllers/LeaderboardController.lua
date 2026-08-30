--!nonstrict
--[[
	LeaderboardController
	.../SAD_Client/Controllers/LeaderboardController  (ModuleScript)

	Two surfaces onto the same cached data:

	  1. The Leaderboards screen - one tab per board, top 100, your own line
	     pinned at the bottom (docs/08 §3).
	  2. The Colosseum - the pillars the world builder put up, and the three
	     golden statues (docs/02 §1.1).

	═══ ONE FETCH FEEDS BOTH ═══════════════════════════════════════════════════
	`GetLeaderboards` is rate-limited to one call every two seconds and the
	server's own cache only changes once a minute, so fetching per surface
	would be two round trips for one answer. The controller holds the last
	payload and both surfaces render from it.
	═══════════════════════════════════════════════════════════════════════════

	═══ "OUTSIDE THE TOP 100" IS THE HONEST ANSWER ═════════════════════════════
	OrderedDataStore has no rank query. The server sends a real rank when the
	player is in the cached page and no rank when they are not, and this draws
	exactly that: their value, and the words rather than a made-up number. See
	LeaderboardService's header for why a sampled rank would be worse.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: StateController, UIController, InputController, HUDController,
	            Theme, Create, Widgets, LeaderboardConfig, Format, Net.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Format = require(Shared.Modules.Format)
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local LeaderboardController = {}

--- Fires with each successful payload. The Colosseum surfaces redraw from it,
--- so the screen and the world never disagree about what the cache holds.
LeaderboardController.Fetched = Signal.new()

local UIController, InputController

local player = Players.LocalPlayer

local root: Frame? = nil
local list: ScrollingFrame? = nil
local selfLine: Frame? = nil
local statusLabel: TextLabel? = nil
local tabButtons: { [string]: TextButton } = {}
local activeBoard = LeaderboardConfig.Order[1]

--- The last payload from the server. Nil until the first fetch returns.
local payload = nil
local fetching = false
local lastFetchAt = 0

--- Rows are pooled: 100 of them, reused across tabs. Rebuilding a hundred
--- frames on every tab change is the kind of thing that drops frames on a
--- phone for no benefit at all.
local rowPool: { any } = {}

--[[
	How long a locally held payload may be reused before the screen re-fetches.
	Shorter than the server's own refresh would just re-read the same cache;
	`GetLeaderboards` is rate-limited to 0.5/s and this stays well inside it.
]]
local REFETCH_SECS = 20
local ROW_HEIGHT = 34

-- ── Formatting ──────────────────────────────────────────────────────────────

local function formatValue(boardId: string, value: number): string
	local entry = LeaderboardConfig.Get(boardId)
	local kind = entry and entry.Format
	if kind == "rate" then
		return Format.Number(value) .. "/s"
	elseif kind == "count" then
		return Format.Comma(value)
	end
	return Format.Number(value)
end

--- Gold, silver, bronze, then the ordinary text colour.
local function rankColor(rank: number): Color3
	if rank == 1 then
		return Theme.Color.Accent
	elseif rank == 2 then
		return Color3.fromHex("C9CBD1")
	elseif rank == 3 then
		return Color3.fromHex("CD7F32")
	end
	return Theme.Color.TextMuted
end

-- ── Fetching ────────────────────────────────────────────────────────────────

local function render()
	if not root or not list then
		return
	end

	local boards = payload and payload.Boards
	local board = boards and boards[activeBoard]
	local entries = (board and board.Entries) or {}

	if statusLabel then
		if not payload then
			statusLabel.Text = "LOADING…"
			statusLabel.TextColor3 = Theme.Color.TextDim
		elseif not board or not board.Loaded then
			--[[
				Not an error. A server whose first refresh has not landed, or
				one running in Studio without API Services, has genuinely empty
				boards - saying so beats an empty list that looks broken.
			]]
			statusLabel.Text = "NO DATA YET"
			statusLabel.TextColor3 = Theme.Color.TextDim
		elseif board.Stale then
			statusLabel.Text = "LAST UPDATE FAILED — SHOWING OLDER DATA"
			statusLabel.TextColor3 = Theme.Color.Warning
		else
			local entry = LeaderboardConfig.Get(activeBoard)
			statusLabel.Text = (entry and entry.Blurb or ""):upper()
			statusLabel.TextColor3 = Theme.Color.TextDim
		end
	end

	for index, row in rowPool do
		local data = entries[index]
		if not data then
			row.Frame.Visible = false
		else
			row.Frame.Visible = true
			row.Rank.Text = "#" .. data.Rank
			row.Rank.TextColor3 = rankColor(data.Rank)
			row.Name.Text = data.Name
			-- Your own line is highlighted in the list as well as pinned, so
			-- scrolling past yourself is not a surprise.
			row.Name.TextColor3 = if data.UserId == player.UserId
				then Theme.Color.Accent
				else Theme.Color.Text
			row.Value.Text = formatValue(activeBoard, data.Value)
		end
	end

	-- The pinned line.
	local mine = payload and payload.Self and payload.Self[activeBoard]
	if selfLine then
		local rankLabel = selfLine:FindFirstChild("Rank") :: TextLabel?
		local nameLabel = selfLine:FindFirstChild("Name") :: TextLabel?
		local valueLabel = selfLine:FindFirstChild("Value") :: TextLabel?
		if mine and rankLabel and nameLabel and valueLabel then
			rankLabel.Text = if mine.Rank then "#" .. mine.Rank else "—"
			rankLabel.TextColor3 = if mine.Rank then rankColor(mine.Rank) else Theme.Color.TextDim
			nameLabel.Text = if mine.Rank then "YOU" else "YOU  ·  OUTSIDE THE TOP 100"
			valueLabel.Text = formatValue(activeBoard, mine.Value)
			selfLine.Visible = true
		else
			selfLine.Visible = false
		end
	end
end

--[[
	One in-flight fetch at a time. Without the guard, switching tabs three times
	while the network is slow sends three invocations, and the server's rate
	limit drops two of them - so the screen would sometimes just never fill in.
]]
local function fetch(force: boolean?)
	if fetching then
		return
	end
	if not force and payload and (os.clock() - lastFetchAt) < REFETCH_SECS then
		return
	end

	fetching = true
	task.spawn(function()
		local ok, result = pcall(function()
			return Net.Invoke("GetLeaderboards")
		end)
		fetching = false

		if ok and type(result) == "table" then
			payload = result
			lastFetchAt = os.clock()
			render()
			LeaderboardController.Fetched:Fire(result)
		else
			Log.warn("LeaderboardController", "Fetch failed: %s", tostring(result))
			render()
		end
	end)
end

function LeaderboardController.GetPayload()
	return payload
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function buildRow(index: number, parent: Instance)
	local rank = Create("TextLabel", {
		Name = "Rank",
		Size = UDim2.fromOffset(56, ROW_HEIGHT),
		Position = UDim2.fromOffset(Theme.Space.M, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	local name = Create("TextLabel", {
		Name = "Name",
		Size = UDim2.new(1, -240, 1, 0),
		Position = UDim2.fromOffset(70, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})

	local value = Create("TextLabel", {
		Name = "Value",
		Size = UDim2.fromOffset(160, ROW_HEIGHT),
		Position = UDim2.new(1, -Theme.Space.M, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})

	local frame = Create("Frame", {
		Name = "Row" .. index,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		-- Alternating bands, so a hundred rows are readable without a divider
		-- per row.
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = if index % 2 == 0 then 1 else 0.6,
		BorderSizePixel = 0,
		LayoutOrder = index,
		Visible = false,
		Children = { rank, name, value },
		Parent = parent,
	})

	return { Frame = frame, Rank = rank, Name = name, Value = value }
end

local function showBoard(boardId: string)
	activeBoard = boardId
	for id, button in tabButtons do
		local on = id == boardId
		button.BackgroundColor3 = if on then Theme.Color.Accent else Theme.Color.SurfaceRaised
		button.TextColor3 = if on then Theme.Color.TextOnAccent else Theme.Color.TextMuted
	end
	if list then
		list.CanvasPosition = Vector2.zero
	end
	render()
end

local function build()
	local layer = UIController.Layer("screen")

	local title = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 30),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.L),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "LEADERBOARDS",
	})

	statusLabel = Create("TextLabel", {
		Name = "Status",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 18),
		Position = UDim2.fromOffset(Theme.Space.L, 104),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "LOADING…",
	})

	local close = Create("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(Theme.Size.MinTouchTarget, 40),
		Position = UDim2.new(1, -Theme.Space.L, 0, Theme.Space.M),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		Text = "✕",
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
		Events = { MouseButton1Click = function() UIController.Close("Leaderboards") end },
	})

	local tabs = Create("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 40),
		Position = UDim2.fromOffset(Theme.Space.L, 56),
		BackgroundTransparency = 1,
		Children = { Widgets.Layout("horizontal", Theme.Space.S, Enum.HorizontalAlignment.Left) },
	})

	for _, boardId in LeaderboardConfig.Order do
		local entry = LeaderboardConfig.Get(boardId)
		tabButtons[boardId] = Create("TextButton", {
			Name = boardId,
			--[[
				Sized from the board count so four tabs fill the row and eight
				still fit. Derived rather than a fixed width for the same
				reason the Colosseum's arc is: V1.4 adds four boards and
				nothing here should need editing.
			]]
			Size = UDim2.new(1 / LeaderboardConfig.Count(), -Theme.Space.S, 1, 0),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Color.TextMuted,
			Text = entry.DisplayName,
			Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
			Events = { MouseButton1Click = function() showBoard(boardId) end },
			Parent = tabs,
		})
	end

	list = Create("ScrollingFrame", {
		Name = "Rows",
		Size = UDim2.new(1, -Theme.Space.XL, 1, -186),
		Position = UDim2.fromOffset(Theme.Space.L, 128),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Outline,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Children = { Widgets.Layout("vertical", 0, Enum.HorizontalAlignment.Left) },
	})

	--[[
		Your own line, pinned below the list rather than inside it. docs/08 §3
		asks for exactly this: a player who is 4,000th should not have to scroll
		to find out what they have.
	]]
	selfLine = Widgets.Panel({
		Name = "SelfLine",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 44),
		Position = UDim2.new(0, Theme.Space.L, 1, -Theme.Space.L),
		AnchorPoint = Vector2.new(0, 1),
		Color = Theme.Color.SurfaceRaised,
		Transparency = 0,
		StrokeColor = Theme.Color.Accent,
		Visible = false,
		Children = {
			Create("TextLabel", {
				Name = "Rank",
				Size = UDim2.fromOffset(56, 44),
				Position = UDim2.fromOffset(Theme.Space.M, 0),
				BackgroundTransparency = 1,
				Font = Theme.Font.Bold,
				TextSize = Theme.TextSize.Small,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "—",
			}),
			Create("TextLabel", {
				Name = "Name",
				Size = UDim2.new(1, -240, 1, 0),
				Position = UDim2.fromOffset(70, 0),
				BackgroundTransparency = 1,
				Font = Theme.Font.Bold,
				TextSize = Theme.TextSize.Small,
				TextColor3 = Theme.Color.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "YOU",
			}),
			Create("TextLabel", {
				Name = "Value",
				Size = UDim2.fromOffset(160, 44),
				Position = UDim2.new(1, -Theme.Space.M, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Font.Display,
				TextSize = Theme.TextSize.Small,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = "0",
			}),
		},
	})

	root = Widgets.Panel({
		Name = "LeaderboardScreen",
		Size = UDim2.fromScale(0.92, 0.86),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0.02,
		Radius = Theme.Radius.Large,
		ZIndex = Theme.Layer.Screen,
		Visible = false,
		Children = { title, close, tabs, statusLabel, list, selfLine },
		Parent = layer,
	})

	for index = 1, LeaderboardConfig.PageSize do
		rowPool[index] = buildRow(index, list)
	end

	showBoard(activeBoard)
end

-- ── The Colosseum ───────────────────────────────────────────────────────────

local worldBoards: { [string]: any } = {}
local worldStatues: { [number]: any } = {}

--[[
	A SurfaceGui on each pillar. Built on the client so a player whose board
	fails to draw has broken their own screen rather than everyone's world -
	the same call WeatherController made about Lighting.
]]
local function attachBoardSurface(pillar: BasePart, boardId: string)
	local entry = LeaderboardConfig.Get(boardId)
	if not entry then
		return
	end

	local surface = Instance.new("SurfaceGui")
	surface.Name = "SAD_Board"
	surface.Face = Enum.NormalId.Back -- the face aimed at the plaza
	surface.SizingDefinition = Enum.SurfaceGuiSizingDefinition.PixelsPerStud
	surface.PixelsPerStud = 24
	surface.AlwaysOnTop = false
	surface.MaxDistance = 220
	surface.LightInfluence = 0
	surface.Adornee = pillar
	surface.Parent = pillar

	local heading = Create("TextLabel", {
		Name = "Heading",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = 34,
		TextColor3 = Theme.Color.Accent,
		Text = entry.DisplayName,
		Parent = surface,
	})

	local rowsFrame = Create("Frame", {
		Name = "Rows",
		Size = UDim2.new(1, -20, 1, -54),
		Position = UDim2.fromOffset(10, 50),
		BackgroundTransparency = 1,
		Children = { Widgets.Layout("vertical", 2, Enum.HorizontalAlignment.Left) },
		Parent = surface,
	})

	local labels = {}
	--[[
		Ten rows, not a hundred. A pillar is read at a distance while walking
		past; the screen is where the full list lives.
	]]
	for index = 1, 10 do
		labels[index] = Create("TextLabel", {
			Name = "Row" .. index,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Font = Theme.Font.Body,
			TextSize = 22,
			TextColor3 = Theme.Color.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = index,
			Text = "",
			Parent = rowsFrame,
		})
	end

	worldBoards[boardId] = { Surface = surface, Labels = labels, Heading = heading }
end

local function attachStatueSurface(plinth: BasePart, rank: number)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "SAD_Statue"
	surface.Face = Enum.NormalId.Back
	surface.SizingDefinition = Enum.SurfaceGuiSizingDefinition.PixelsPerStud
	surface.PixelsPerStud = 24
	surface.MaxDistance = 220
	surface.LightInfluence = 0
	surface.Adornee = plinth
	surface.Parent = plinth

	--[[
		The avatar's headshot, fetched with `Players:GetUserThumbnailAsync`.
		It yields and can fail, so it is fetched off the render path and the
		plinth reads fine without it - a gold block with a name on it is
		already the brag.
	]]
	local portrait = Create("ImageLabel", {
		Name = "Portrait",
		Size = UDim2.new(1, -20, 1, -70),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Theme.Color.Backdrop,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Image = "",
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
		Parent = surface,
	})

	local nameLabel = Create("TextLabel", {
		Name = "Name",
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.new(0, 10, 1, -56),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = 24,
		TextColor3 = Theme.Color.Accent,
		Text = "",
		Parent = surface,
	})

	local valueLabel = Create("TextLabel", {
		Name = "Value",
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0, 10, 1, -26),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = 20,
		TextColor3 = Theme.Color.TextMuted,
		Text = "",
		Parent = surface,
	})

	worldStatues[rank] = {
		Surface = surface, Portrait = portrait, Name = nameLabel, Value = valueLabel,
		ShowingUserId = nil,
	}
end

local function renderWorld()
	if not payload then
		return
	end

	for boardId, world in worldBoards do
		local board = payload.Boards and payload.Boards[boardId]
		local entries = (board and board.Entries) or {}
		for index, label in world.Labels do
			local row = entries[index]
			if row then
				label.Text = string.format("%d. %s   %s",
					row.Rank, row.Name, formatValue(boardId, row.Value))
				label.TextColor3 = rankColor(row.Rank)
			else
				label.Text = ""
			end
		end
		if #entries == 0 then
			world.Labels[1].Text = "NO DATA YET"
			world.Labels[1].TextColor3 = Theme.Color.TextDim
		end
	end

	local statues = payload.Statues or {}
	for rank, world in worldStatues do
		local row = statues[rank]
		if not row then
			world.Name.Text = "VACANT"
			world.Value.Text = ""
			world.Portrait.Image = ""
			world.ShowingUserId = nil
		else
			world.Name.Text = row.Name
			world.Value.Text = formatValue(LeaderboardConfig.StatueBoard, row.Value)

			-- Only re-fetched when the occupant actually changes: the call is
			-- a web request and the top three move rarely.
			if world.ShowingUserId ~= row.UserId then
				world.ShowingUserId = row.UserId
				task.spawn(function()
					local ok, content = pcall(function()
						return Players:GetUserThumbnailAsync(row.UserId,
							Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
					end)
					-- Guarded: the occupant may have changed while this yielded.
					if ok and world.ShowingUserId == row.UserId then
						world.Portrait.Image = content
					end
				end)
			end
		end
	end
end

local function bindWorld()
	local hub = workspace:FindFirstChild("SAD_World")
	hub = hub and hub:FindFirstChild("Hub")
	local colosseum = hub and hub:FindFirstChild("Colosseum")
	if not colosseum then
		return false
	end

	for _, child in colosseum:GetChildren() do
		if child:IsA("BasePart") then
			local boardId = child:GetAttribute("LeaderboardBoard")
			if boardId and not worldBoards[boardId] then
				attachBoardSurface(child, boardId)
			end
			local statueRank = child:GetAttribute("LeaderboardStatue")
			if statueRank and not worldStatues[statueRank] then
				attachStatueSurface(child, statueRank)
			end
		end
	end
	return true
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function LeaderboardController.Init(app)
	UIController = app.Get("UIController")
	InputController = app.Get("InputController")
end

function LeaderboardController.Start(_app)
	build()

	UIController.Register("Leaderboards", {
		Open = function()
			if root then
				root.Visible = true
			end
			render()
			fetch()
		end,
		Close = function()
			if root then
				root.Visible = false
			end
		end,
	})

	InputController.Action:Connect(function(action, state)
		if action == "ToggleLeaderboards" and state == "Begin" then
			UIController.Toggle("Leaderboards")
		end
	end)

	LeaderboardController.Fetched:Connect(renderWorld)

	--[[
		The Colosseum is server-built and streams in, so binding is retried
		rather than assumed. Once bound it refreshes on the same cadence the
		server's cache turns over - the pillars are read while walking past,
		not stared at, so there is no reason to poll faster than the data
		actually changes.
	]]
	task.spawn(function()
		while not bindWorld() do
			task.wait(2)
		end
		while true do
			fetch(true)
			task.wait(LeaderboardConfig.ReadIntervalSecs)
		end
	end)

	Log.info("LeaderboardController", "Ready. %d board(s), %d statue(s)",
		LeaderboardConfig.Count(), LeaderboardConfig.StatueCount)
end

return LeaderboardController
