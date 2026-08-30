--!nonstrict
--[[
	QuestController
	.../SAD_Client/Controllers/QuestController  (ModuleScript)

	Two screens: the quest board and the daily chest. Both are lists of things
	to claim, so they share a row widget and a redraw path.

	Everything shown is derived from the replicated profile - progress, whether
	a quest is claimable, which chest day is next, how long until the next one.
	Nothing is remembered between redraws, so a quest claimed on another device
	or a day that turned while the screen was open lands the same way: the
	profile changed, the rows redraw.

	The client computes the day boundary with the same shared `Time` module the
	server claims against, which is the point of that module being shared: a UI
	saying READY over a button that refuses is worse than no UI.

	Depends on: StateController, UIController, InputController, Theme, Create,
	            Widgets, QuestConfig, DailyConfig, Time, Format, Net.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DailyConfig = require(Shared.Config.DailyConfig)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local QuestConfig = require(Shared.Config.QuestConfig)
local Time = require(Shared.Modules.Time)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local QuestController = {}

local StateController, UIController, InputController

local questScreen, dailyScreen = nil, nil
local questList, dailyList = nil, nil
local observers = {}

local ROW_HEIGHT = 76

-- ── Rows ────────────────────────────────────────────────────────────────────

--[[
	One row: a title, a progress bar, and a button that is either the reward or
	the reason it cannot be pressed. Returns handles so a redraw never has to
	FindFirstChild into its own widget.
]]
local function buildRow(parent, order)
	local title = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -180, 0, 22),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.M),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})

	local detail = Create("TextLabel", {
		Name = "Detail",
		Size = UDim2.new(1, -180, 0, 18),
		Position = UDim2.fromOffset(Theme.Space.L, 36),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	local track = Create("Frame", {
		Name = "Track",
		Size = UDim2.new(1, -180 - Theme.Space.XL, 0, 6),
		Position = UDim2.fromOffset(Theme.Space.L, 58),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Pill }) },
	})

	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Color.Accent,
		BorderSizePixel = 0,
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Pill }) },
		Parent = track,
	})

	local button = Create("TextButton", {
		Name = "Claim",
		Size = UDim2.fromOffset(148, Theme.Size.MinTouchTarget - 16),
		Position = UDim2.new(1, -Theme.Space.M, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextDim,
		Text = "",
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
	})

	local panel = Widgets.Panel({
		Name = "Row",
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = order,
		Color = Theme.Color.Surface,
		Children = { title, detail, track, button },
		Parent = parent,
	})

	return { Panel = panel, Title = title, Detail = detail, Fill = fill, Button = button }
end

local questRows = {}
local dailyRows = {}

local function setButton(button, text, enabled)
	button.Text = text
	button.BackgroundColor3 = if enabled then Theme.Color.Accent else Theme.Color.SurfaceRaised
	button.TextColor3 = if enabled then Theme.Color.TextOnAccent else Theme.Color.TextDim
end

--[[
	Summarises a reward table the same way RewardGrant pays it out - Fossils
	scaled by rebirths, DNA not. Two different numbers in the UI and the wallet
	is the drift this mirrors the server's formula to avoid.
]]
local function rewardText(reward, rebirths)
	local parts = {}
	if reward.Fossils then
		table.insert(parts, Format.Number(QuestConfig.ScaleFossils(reward.Fossils, rebirths)) .. " F")
	end
	if reward.Dna then
		table.insert(parts, reward.Dna .. " DNA")
	end
	if reward.Egg then
		table.insert(parts, "1 Egg")
	end
	if reward.Boost then
		table.insert(parts, "Boost")
	end
	if reward.Shield then
		table.insert(parts, "Shield")
	end
	if reward.LuckNodes then
		table.insert(parts, "+Luck")
	end
	return table.concat(parts, " + ")
end

-- ── Quests ──────────────────────────────────────────────────────────────────

local function refreshQuests()
	local data = StateController.Get()
	if not data or not questList then
		return
	end

	local order = 0
	local wanted = {}

	for _, kind in { "daily", "weekly" } do
		local set = if kind == "weekly" then data.Quests.Weekly else data.Quests.Daily
		local ids = {}
		for id in set do
			table.insert(ids, id)
		end
		table.sort(ids)

		for _, questId in ids do
			local quest = QuestConfig.Get(kind, questId)
			if not quest then
				continue
			end

			order += 1
			wanted[questId] = true

			local row = questRows[questId]
			if not row then
				row = buildRow(questList, order)
				questRows[questId] = row
			end
			row.Panel.LayoutOrder = order

			local state = set[questId]
			local progress = math.min(state.Progress or 0, quest.Target)
			local complete = progress >= quest.Target

			row.Title.Text = quest.Text
			row.Detail.Text = string.format("%s  ·  %s  ·  %s",
				if kind == "weekly" then "WEEKLY" else "DAILY",
				string.format("%s / %s", Format.Number(progress), Format.Number(quest.Target)),
				rewardText(quest, data.Rebirths or 0))
			row.Fill.Size = UDim2.fromScale(progress / quest.Target, 1)
			row.Fill.BackgroundColor3 = if complete then Theme.Color.Success else Theme.Color.Accent

			if state.Claimed then
				setButton(row.Button, "CLAIMED", false)
			elseif complete then
				setButton(row.Button, "CLAIM", true)
			else
				setButton(row.Button, "IN PROGRESS", false)
			end

			-- Rebound each redraw, so the closure always names the current id.
			row.Button.MouseButton1Click:Connect(function()
				if complete and not state.Claimed then
					Net.FireServer("RequestClaimQuest", questId)
				end
			end)
		end
	end

	for questId, row in questRows do
		if not wanted[questId] then
			row.Panel:Destroy()
			questRows[questId] = nil
		end
	end
end

-- ── Daily ───────────────────────────────────────────────────────────────────

--[[
	Which cycle day the next claim pays. The same derivation DailyService uses,
	from the same shared `Time` module, so the screen and the server cannot
	disagree about whether a streak survived.
]]
local function nextDayIndex(data, now)
	local state = Time.StreakState(data.Daily.LastClaimDay or 0, Time.DayIndex(now))
	if state == "break" then
		return 1
	end
	if state == "same" then
		return math.max(1, data.Daily.DayIndex or 1)
	end
	return (data.Daily.DayIndex or 0) + 1
end

local function refreshDaily()
	local data = StateController.Get()
	if not data or not dailyList then
		return
	end

	local now = os.time()
	local today = Time.DayIndex(now)
	local claimedToday = (data.Daily.LastClaimDay or 0) == today
	local nextDay = nextDayIndex(data, now)

	for day = 1, DailyConfig.CycleLength do
		local row = dailyRows[day]
		if not row then
			row = buildRow(dailyList, day)
			dailyRows[day] = row
		end

		local reward = DailyConfig.RewardFor(day)
		row.Title.Text = "DAY " .. day
		row.Detail.Text = rewardText(reward, data.Rebirths or 0)

		--[[
			Days before the next one are shown as done, the next one as
			available or waiting, and the rest as locked. Derived from
			`nextDay` alone rather than from a second list of claimed days.
		]]
		local isNext = day == nextDay
		row.Fill.Size = UDim2.fromScale(if day < nextDay then 1 elseif isNext then 0.5 else 0, 1)
		row.Fill.BackgroundColor3 = if day < nextDay then Theme.Color.Success else Theme.Color.Accent

		if isNext and not claimedToday then
			setButton(row.Button, "CLAIM", true)
		elseif isNext then
			setButton(row.Button, Format.Time(Time.SecondsUntilNextDay(now)), false)
		elseif day < nextDay then
			setButton(row.Button, "DONE", false)
		else
			setButton(row.Button, "LOCKED", false)
		end

		row.Button.MouseButton1Click:Connect(function()
			if isNext and not claimedToday then
				Net.FireServer("RequestClaimDaily")
			end
		end)
	end

	local header = dailyScreen and dailyScreen:FindFirstChild("Title")
	if header then
		header.Text = string.format("DAILY CHEST  ·  %d DAY STREAK", data.Daily.Streak or 0)
	end
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function buildScreen(name: string, title: string)
	local layer = UIController.Layer("screen")

	local heading = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Space.XXL, 0, 30),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.L),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
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
		Events = { MouseButton1Click = function() UIController.Close(name) end },
	})

	local list = Create("ScrollingFrame", {
		Name = "Rows",
		Size = UDim2.new(1, -Theme.Space.XL, 1, -70),
		Position = UDim2.fromOffset(Theme.Space.L, 60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Outline,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Children = { Widgets.Layout("vertical", Theme.Space.S, Enum.HorizontalAlignment.Left) },
	})

	local screen = Widgets.Panel({
		Name = name .. "Screen",
		Size = UDim2.fromScale(0.82, 0.84),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0.02,
		Radius = Theme.Radius.Large,
		ZIndex = Theme.Layer.Screen,
		Visible = false,
		Children = { heading, close, list },
		Parent = layer,
	})

	return screen, list
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function QuestController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
	InputController = app.Get("InputController")
end

function QuestController.Start(_app)
	questScreen, questList = buildScreen("Quests", "QUESTS")
	dailyScreen, dailyList = buildScreen("Daily", "DAILY CHEST")

	UIController.Register("Quests", {
		Open = function()
			refreshQuests()
			questScreen.Visible = true
		end,
		Close = function()
			questScreen.Visible = false
		end,
	})

	UIController.Register("Daily", {
		Open = function()
			refreshDaily()
			dailyScreen.Visible = true
		end,
		Close = function()
			dailyScreen.Visible = false
		end,
	})

	InputController.Action:Connect(function(action, state)
		if state ~= "Begin" then
			return
		end
		if action == "ToggleQuests" then
			UIController.Toggle("Quests")
		elseif action == "ToggleDaily" then
			UIController.Toggle("Daily")
		end
	end)

	for _, path in { { "Quests" }, { "Daily" }, { "Rebirths" } } do
		table.insert(observers, StateController.Observe(path, function()
			if questScreen and questScreen.Visible then
				refreshQuests()
			end
			if dailyScreen and dailyScreen.Visible then
				refreshDaily()
			end
		end))
	end

	--[[
		The daily screen carries a countdown to the next chest, so it ticks
		while open. 1 Hz - it is a hours-scale readout and a per-frame update
		would be the same string sixty times a second.
	]]
	task.spawn(function()
		while true do
			task.wait(1)
			if dailyScreen and dailyScreen.Visible then
				refreshDaily()
			end
		end
	end)

	Log.info("QuestController", "Ready. %d daily, %d weekly in the pools",
		QuestConfig.Count("daily"), QuestConfig.Count("weekly"))
end

return QuestController
