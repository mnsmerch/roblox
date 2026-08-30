--!nonstrict
--[[
	RebirthController
	.../SAD_Client/Controllers/RebirthController  (ModuleScript)

	The confirm screen: what you keep, what you lose, what you gain.

	═══ THE NUMBERS COME FROM THE SAME FUNCTION THE SERVER USES ════════════════
	`RebirthConfig.Preview` is pure and shared, so the line that says "you keep
	4 vaulted dinosaurs" is produced by the same code that will decide which
	four survive. A preview computed separately is a contract the game might
	not honour - and this is the one screen where a player is asked to delete
	their park on the strength of what it says.
	═══════════════════════════════════════════════════════════════════════════

	The button sends nothing but the intent. Every requirement is re-checked on
	the server, and the screen greys the button only so a player is not invited
	to press something that will be refused.

	Depends on: StateController, UIController, InputController, Theme, Create,
	            Widgets, RebirthConfig, ZoneConfig, RarityConfig, Economy,
	            Format, Net.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Economy = require(Shared.Modules.Economy)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local RarityConfig = require(Shared.Config.RarityConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local RebirthController = {}

local StateController, UIController, InputController

local screen, columns, confirm, heading = nil, {}, nil, nil
local observers = {}

--[[
	Three columns, because that is the decision: what survives, what does not,
	and what it buys. A single list would let the losses hide among the gains,
	which is not a screen anyone should design deliberately.
]]
local COLUMNS = {
	{ Id = "keeps", Title = "YOU KEEP", Color = Theme.Color.Success },
	{ Id = "loses", Title = "YOU LOSE", Color = Theme.Color.Danger },
	{ Id = "gains", Title = "YOU GAIN", Color = Theme.Color.Rebirth },
}

local function buildColumn(parent, index, entry)
	local title = Create("TextLabel", {
		Name = "Heading",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = entry.Color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = entry.Title,
	})

	local body = Create("TextLabel", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -30),
		Position = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = false,
		Text = "",
	})

	local panel = Widgets.Panel({
		Name = entry.Id,
		Size = UDim2.new(1 / #COLUMNS, -Theme.Space.M, 1, 0),
		Position = UDim2.new((index - 1) / #COLUMNS, Theme.Space.S, 0, 0),
		Color = Theme.Color.Surface,
		Children = {
			Create("UIPadding", {
				PaddingLeft = UDim.new(0, Theme.Space.L),
				PaddingTop = UDim.new(0, Theme.Space.M),
				PaddingRight = UDim.new(0, Theme.Space.M),
			}),
			title, body,
		},
		Parent = parent,
	})

	return { Panel = panel, Body = body }
end

local function lines(list)
	return table.concat(list, "\n")
end

local function refresh()
	local data = StateController.Get()
	if not data or not screen then
		return
	end

	local preview = RebirthConfig.Preview(data, ZoneConfig, RarityConfig)
	local rate = Economy.ParkIncomeRate(data)

	heading.Text = string.format("REBIRTH %d  ·  %s FOSSILS",
		preview.Rebirth, Format.Number(preview.Cost))

	columns.keeps.Body.Text = lines({
		string.format("%d vaulted dinosaur%s", preview.Keeps.Vaulted,
			if preview.Keeps.Vaulted == 1 then "" else "s"),
		string.format("%s DNA", Format.Number(preview.Keeps.Dna)),
		string.format("%d Index entries", preview.Keeps.IndexEntries),
		string.format("%d permanent Luck node%s", preview.Keeps.LuckNodes,
			if preview.Keeps.LuckNodes == 1 then "" else "s"),
		string.format("%d zone%s", preview.Keeps.Zones,
			if preview.Keeps.Zones == 1 then "" else "s"),
		"Quests, dailies and your streak",
		"Every upgrade you have bought with DNA",
	})

	columns.loses.Body.Text = lines({
		string.format("%s Fossils", Format.Number(preview.Loses.Fossils)),
		string.format("%d dinosaur%s", preview.Loses.Dinos,
			if preview.Loses.Dinos == 1 then "" else "s"),
		string.format("%d egg%s", preview.Loses.Eggs,
			if preview.Loses.Eggs == 1 then "" else "s"),
		string.format("%s Fossils/sec of income", Format.Number(rate)),
		"Every Fossil upgrade and defence",
		--[[
			Named with its price, because re-buying the zones is a real second
			cost and a player deserves to see it before agreeing rather than
			after.
		]]
		if preview.Loses.Zones > 0
			then string.format("%d zone%s (%s to re-buy)", preview.Loses.Zones,
				if preview.Loses.Zones == 1 then "" else "s",
				Format.Number(preview.Loses.ZoneCost))
			else "No zones",
	})

	local gains = preview.Gains
	columns.gains.Body.Text = lines({
		string.format("x%.2f income, permanently", gains.IncomeMultiplier),
		string.format("+%d%% Luck", math.floor(gains.Luck * 100 + 0.5)),
		string.format("+%d%% Mutation Luck", math.floor(gains.MutLuck * 100 + 0.5)),
		string.format("+%d%% move speed", math.floor(gains.MoveSpeed * 100 + 0.5)),
		string.format("%d hour offline cap", math.floor(gains.OfflineCapHours)),
		string.format("%d dino slots, %d vault slots", gains.DinoSlots, gains.VaultSlots),
		string.format("%s name tag", gains.NameTag),
		if gains.CacheRarity
			then string.format("1 %s egg to start with",
				RarityConfig.Tiers[gains.CacheRarity].DisplayName)
			else "",
	})

	--[[
		The button greys when a requirement is short, and says WHICH. It is
		still only a hint: every one of these is re-checked on the server,
		which is the thing that actually decides.
	]]
	local owned = 0
	for _ in data.Dinos do
		owned += 1
	end

	local short = nil
	if (data.Fossils or 0) < preview.Cost then
		short = "NEED " .. Format.Number(preview.Cost - data.Fossils) .. " MORE"
	elseif owned < preview.DinosRequired then
		short = string.format("NEED %d MORE DINOSAURS", preview.DinosRequired - owned)
	end

	confirm.Text = short or ("REBIRTH " .. preview.Rebirth)
	confirm.BackgroundColor3 = if short then Theme.Color.SurfaceRaised else Theme.Color.Rebirth
	confirm.TextColor3 = if short then Theme.Color.TextDim else Theme.Color.Text
end

local function build()
	local layer = UIController.Layer("screen")

	heading = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Space.XXL, 0, 30),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.L),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Color.Rebirth,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "REBIRTH",
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
		Events = { MouseButton1Click = function() UIController.Close("Rebirth") end },
	})

	local body = Create("Frame", {
		Name = "Columns",
		Size = UDim2.new(1, -Theme.Space.XL, 1, -140),
		Position = UDim2.fromOffset(Theme.Space.L, 56),
		BackgroundTransparency = 1,
	})

	confirm = Create("TextButton", {
		Name = "Confirm",
		Size = UDim2.new(0, 320, 0, Theme.Size.MinTouchTarget),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.XL),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Theme.Color.Rebirth,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		Text = "REBIRTH",
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Medium }) },
		Events = {
			MouseButton1Click = function()
				--[[
					Sends the intent and closes. The server re-checks every
					requirement; the screen is closed either way, because
					leaving it open over a park that may no longer exist is
					worse than closing one that was refused - the refusal
					arrives as a toast.
				]]
				Net.FireServer("RequestRebirth")
				UIController.Close("Rebirth")
			end,
		},
	})

	screen = Widgets.Panel({
		Name = "RebirthScreen",
		Size = UDim2.fromScale(0.9, 0.8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0.02,
		Radius = Theme.Radius.Large,
		StrokeColor = Theme.Color.Rebirth,
		ZIndex = Theme.Layer.Screen,
		Visible = false,
		Children = { heading, close, body, confirm },
		Parent = layer,
	})

	for index, entry in COLUMNS do
		columns[entry.Id] = buildColumn(body, index, entry)
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function RebirthController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
	InputController = app.Get("InputController")
end

function RebirthController.Start(_app)
	build()

	UIController.Register("Rebirth", {
		Open = function()
			refresh()
			screen.Visible = true
		end,
		Close = function()
			screen.Visible = false
		end,
	})

	InputController.Action:Connect(function(action, state)
		if action == "ToggleRebirth" and state == "Begin" then
			UIController.Toggle("Rebirth")
		end
	end)

	--[[
		Redrawn on anything the preview reads. Fossils are in the list because
		the button's enabled state is mostly a function of them, and they move
		constantly while the park earns.
	]]
	for _, path in { { "Fossils" }, { "Dinos" }, { "Rebirths" }, { "ZonesUnlocked" } } do
		table.insert(observers, StateController.Observe(path, function()
			if screen and screen.Visible then
				refresh()
			end
		end))
	end

	Log.info("RebirthController", "Ready. Rebirth 1 costs %s",
		Format.Number(RebirthConfig.CostOf(1)))
end

return RebirthController
