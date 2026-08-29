--!nonstrict
--[[
	Widgets
	StarterPlayerScripts/SAD_Client/UI/Widgets  (ModuleScript)

	Reusable UI pieces. Anything that appears more than once lives here so the
	HUD, the shop and the index cannot drift into three different button styles.

	Two things worth knowing:

	* Buttons scale down on press and back on release. That 60 ms of movement is
	  the difference between a button that feels responsive on a phone and one
	  players tap twice because they were not sure it registered.

	* Number labels LERP toward their target through a single shared
	  RenderStepped loop, not one connection per label. A HUD with six counters
	  should cost one connection, and a big Fossil payout should read as a
	  payout rather than a value substitution.

	Depends on: Theme, Create, Format.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Format = require(Shared.Modules.Format)

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)

local Widgets = {}

-- ── Animated numbers ────────────────────────────────────────────────────────

local spinners = {}
local spinnerCount = 0
local spinnerConnection = nil

local function stepSpinners(deltaTime: number)
	local alpha = math.min(deltaTime / Theme.NumberSpinSecs, 1)

	for label, spinner in spinners do
		if not label.Parent then
			spinners[label] = nil
			spinnerCount -= 1
			continue
		end

		local difference = spinner.Target - spinner.Current
		if math.abs(difference) < 0.5 then
			spinner.Current = spinner.Target
			label.Text = spinner.Format(spinner.Target)
			spinners[label] = nil
			spinnerCount -= 1
		else
			spinner.Current += difference * alpha
			label.Text = spinner.Format(spinner.Current)
		end
	end

	-- One connection for the whole HUD, and none while nothing is moving.
	if spinnerCount <= 0 and spinnerConnection then
		spinnerConnection:Disconnect()
		spinnerConnection = nil
	end
end

--[[
	Moves `label` toward `value` over NumberSpinSecs.

	`immediate` snaps instead, which is what the first value after a state
	snapshot wants - counting up from zero on join is a lie about what just
	happened.
]]
function Widgets.SetNumber(label: TextLabel, value: number, formatter, immediate: boolean?)
	local format = formatter or Format.Number

	if immediate then
		spinners[label] = nil
		label.Text = format(value)
		return
	end

	local existing = spinners[label]
	if existing then
		existing.Target = value
		existing.Format = format
	else
		spinners[label] = {
			Current = tonumber(string.match(label.Text or "", "%-?%d+%.?%d*")) or value,
			Target = value,
			Format = format,
		}
		spinnerCount += 1
	end

	if not spinnerConnection then
		spinnerConnection = RunService.RenderStepped:Connect(stepSpinners)
	end
end

--- Brief colour pulse. Used when a counter jumps by a lot.
function Widgets.Flash(guiObject: GuiObject, color: Color3)
	local original = guiObject.TextColor3 or Theme.Color.Text
	guiObject.TextColor3 = color
	TweenService:Create(
		guiObject,
		TweenInfo.new(Theme.Duration.Slow, Theme.Easing.Out, Enum.EasingDirection.Out),
		{ TextColor3 = original }
	):Play()
end

-- ── Building blocks ─────────────────────────────────────────────────────────

--- A rounded surface with an outline. The base of every panel in the game.
function Widgets.Panel(props)
	local children = props.Children or {}
	table.insert(children, 1, Create("UICorner", { CornerRadius = props.Radius or Theme.Radius.Medium }))
	table.insert(children, 2, Create("UIStroke", {
		Color = props.StrokeColor or Theme.Color.Outline,
		Thickness = Theme.Size.StrokeThickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Transparency = props.StrokeTransparency or 0,
	}))

	return Create("Frame", {
		Name = props.Name or "Panel",
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = props.Color or Theme.Color.Surface,
		BackgroundTransparency = props.Transparency or 0.08,
		BorderSizePixel = 0,
		Visible = props.Visible ~= false,
		ZIndex = props.ZIndex or Theme.Layer.Hud,
		LayoutOrder = props.LayoutOrder,
		Children = children,
		Parent = props.Parent,
	})
end

local function attachPressFeedback(button: GuiButton)
	local restore = TweenInfo.new(Theme.Duration.Fast, Theme.Easing.Bounce, Enum.EasingDirection.Out)
	local press = TweenInfo.new(Theme.Duration.Instant, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local scale = Create("UIScale", { Scale = 1, Parent = button })

	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, press, { Scale = 0.94 }):Play()
	end)
	local function release()
		TweenService:Create(scale, restore, { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

--[[
	The five bottom-bar buttons: icon over label, with an optional badge.

	Returns the button plus handles to the pieces the HUD updates, so callers
	never have to FindFirstChild into a widget's internals.
]]
function Widgets.BottomButton(props)
	local badge = Create("TextLabel", {
		Name = "Badge",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -6, 0, 4),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Color.Danger,
		BorderSizePixel = 0,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.Text,
		Text = "0",
		Visible = false,
		ZIndex = (props.ZIndex or Theme.Layer.Hud) + 2,
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Pill }) },
	})

	local icon = Create("TextLabel", {
		Name = "Icon",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 8),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = props.IconColor or Theme.Color.Accent,
		Text = props.Icon or "",
		ZIndex = (props.ZIndex or Theme.Layer.Hud) + 1,
	})

	local label = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -22),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Text,
		Text = props.Label or "",
		ZIndex = (props.ZIndex or Theme.Layer.Hud) + 1,
	})

	local button = Create("TextButton", {
		Name = props.Name or "BottomButton",
		Size = props.Size or UDim2.new(0.2, -Theme.Space.S, 1, 0),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex or Theme.Layer.Hud,
		Children = {
			Create("UICorner", { CornerRadius = Theme.Radius.Large }),
			Create("UIStroke", {
				Color = Theme.Color.Outline,
				Thickness = Theme.Size.StrokeThickness,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			icon,
			label,
			badge,
		},
		Parent = props.Parent,
	})

	attachPressFeedback(button)
	if props.OnActivated then
		button.Activated:Connect(props.OnActivated)
	end

	return {
		Instance = button,
		Icon = icon,
		Label = label,
		Badge = badge,
		SetBadge = function(count: number)
			badge.Visible = count > 0
			badge.Text = if count > 99 then "99+" else tostring(count)
		end,
	}
end

--- Small square icon button for the side rails.
function Widgets.RailButton(props)
	local button = Create("TextButton", {
		Name = props.Name or "RailButton",
		Size = UDim2.fromOffset(Theme.Size.RailButton, Theme.Size.RailButton),
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Label,
		TextColor3 = props.IconColor or Theme.Color.Text,
		Text = props.Icon or "",
		AutoButtonColor = false,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex or Theme.Layer.Hud,
		Children = {
			Create("UICorner", { CornerRadius = Theme.Radius.Medium }),
			Create("UIStroke", {
				Color = Theme.Color.Outline,
				Thickness = Theme.Size.StrokeThickness,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		},
		Parent = props.Parent,
	})

	attachPressFeedback(button)
	if props.OnActivated then
		button.Activated:Connect(props.OnActivated)
	end
	return button
end

--[[
	A currency or status chip: coloured icon, then a value.

	Returns the frame and its value label, because the HUD updates the label
	dozens of times a minute and should not be searching for it each time.
]]
function Widgets.Chip(props)
	local icon = Create("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.fromOffset(Theme.Space.S, 5),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Label,
		TextColor3 = props.IconColor or Theme.Color.Accent,
		Text = props.Icon or "",
		ZIndex = (props.ZIndex or Theme.Layer.Hud) + 1,
	})

	local value = Create("TextLabel", {
		Name = "Value",
		Size = UDim2.new(1, -36, 1, 0),
		Position = UDim2.fromOffset(34, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = props.Text or "0",
		ZIndex = (props.ZIndex or Theme.Layer.Hud) + 1,
	})

	local frame = Widgets.Panel({
		Name = props.Name or "Chip",
		Size = UDim2.fromOffset(props.Width or 110, Theme.Size.ChipHeight),
		Color = Theme.Color.Surface,
		Transparency = 0.1,
		Radius = Theme.Radius.Pill,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible ~= false,
		ZIndex = props.ZIndex,
		Children = { icon, value },
		Parent = props.Parent,
	})

	return { Instance = frame, Icon = icon, Value = value }
end

--[[
	The contextual action prompt: a wide button with a fill ring for holds.

	Step 8 drives this for egg pickup, Step 15 for raiding. It exists now, empty
	and hidden, so those steps add behaviour rather than layout.
]]
function Widgets.ActionPrompt(props)
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.Color.Accent,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = (props.ZIndex or Theme.Layer.Prompt),
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Large }) },
	})

	local label = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		Text = "",
		ZIndex = (props.ZIndex or Theme.Layer.Prompt) + 1,
	})

	local frame = Widgets.Panel({
		Name = "ActionPrompt",
		Size = UDim2.new(0, 320, 0, Theme.Size.ActionPromptHeight),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Color = Theme.Color.SurfaceRaised,
		Transparency = 0.05,
		Radius = Theme.Radius.Large,
		StrokeColor = Theme.Color.Accent,
		Visible = false,
		ZIndex = props.ZIndex or Theme.Layer.Prompt,
		Children = { fill, label },
		Parent = props.Parent,
	})

	return {
		Instance = frame,
		Label = label,
		Fill = fill,
		Set = function(text: string?, progress: number?)
			if text then
				frame.Visible = true
				label.Text = text
			else
				frame.Visible = false
			end
			fill.Size = UDim2.new(math.clamp(progress or 0, 0, 1), 0, 1, 0)
		end,
	}
end

--- Horizontal or vertical list layout with consistent spacing.
function Widgets.Layout(direction: string, padding: number?, alignment: Enum.HorizontalAlignment?)
	return Create("UIListLayout", {
		FillDirection = if direction == "vertical"
			then Enum.FillDirection.Vertical
			else Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, padding or Theme.Space.S),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = alignment or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
end

return Widgets
