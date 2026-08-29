--!strict
--[[
	Theme
	StarterPlayerScripts/SAD_Client/UI/Theme  (ModuleScript)

	Design tokens. Every colour, size, font and duration the UI uses comes from
	here, so a restyle is one file and the interface stays coherent while six
	more steps bolt things onto it.

	Palette logic: chrome is deliberately DESATURATED - warm dark browns and
	bone - because rarity colours are the game's information channel. A Titan's
	gold has to read instantly against the UI, and it cannot if the UI is also
	shouting. Rarity colours live in RarityConfig and are never duplicated here.

	Sizes are DESIGN pixels at scale 1. UIController applies a single UIScale to
	the whole tree, so a number here is a real proportion, not a guess.

	Depends on: nothing (RarityConfig is read through helpers, lazily).
]]

local Theme = {}

-- ── Colour ──────────────────────────────────────────────────────────────────

Theme.Color = {
	-- Surfaces, darkest to lightest
	Backdrop = Color3.fromHex("120F0A"),
	Surface = Color3.fromHex("1F1A12"),
	SurfaceRaised = Color3.fromHex("2C2418"),
	SurfaceHover = Color3.fromHex("3A3020"),

	-- Text
	Text = Color3.fromHex("F5F0E4"),
	TextMuted = Color3.fromHex("A89C86"),
	TextDim = Color3.fromHex("6E6353"),
	TextOnAccent = Color3.fromHex("241C0C"),

	-- Brand
	Accent = Color3.fromHex("FFB020"), -- amber: Fossils, primary actions
	AccentDark = Color3.fromHex("C48010"),
	Dna = Color3.fromHex("5FD35F"), -- green: DNA
	Rebirth = Color3.fromHex("9B5DE5"), -- purple: rebirth badge
	Shield = Color3.fromHex("3FA9F5"), -- blue: protection

	-- State
	Danger = Color3.fromHex("FF4B3E"),
	Success = Color3.fromHex("5FD35F"),
	Warning = Color3.fromHex("FFC94A"),

	Outline = Color3.fromHex("463A26"),
	Shadow = Color3.fromHex("000000"),
}

-- ── Type ────────────────────────────────────────────────────────────────────
-- Enum.Font rather than FontFace: fully supported, no asset loading, and these
-- three cover everything the HUD needs.

Theme.Font = {
	Display = Enum.Font.FredokaOne, -- big numbers, button labels
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
}

Theme.TextSize = {
	Tiny = 12,
	Small = 14,
	Body = 16,
	Label = 18,
	Heading = 22,
	Display = 28,
	Huge = 40,
}

-- ── Metrics ─────────────────────────────────────────────────────────────────

Theme.Space = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32 }

Theme.Radius = {
	Small = UDim.new(0, 8),
	Medium = UDim.new(0, 12),
	Large = UDim.new(0, 18),
	Pill = UDim.new(1, 0),
}

Theme.Size = {
	TopBarHeight = 44,
	--- The floor from docs/08 §4. ScaleFor guarantees it structurally.
	MinTouchTarget = 64,
	BottomBarHeight = 88,
	BottomButtonHeight = 76,
	RailButton = 48,
	ChipHeight = 34,
	ActionPromptHeight = 64,
	StrokeThickness = 2,
}

-- ── Layers ──────────────────────────────────────────────────────────────────
-- Named so later steps never guess a ZIndex.

Theme.Layer = {
	Hud = 10,
	Screen = 20,
	Prompt = 30,
	Notification = 40,
	Takeover = 50,
}

-- ── Motion ──────────────────────────────────────────────────────────────────

Theme.Duration = {
	Instant = 0.08,
	Fast = 0.15,
	Normal = 0.25,
	Slow = 0.4,
}

Theme.Easing = {
	Out = Enum.EasingStyle.Quart,
	Bounce = Enum.EasingStyle.Back,
}

--- Currency counters lerp toward their target rather than snapping, so a big
--- collection reads as a payout rather than a number substitution.
Theme.NumberSpinSecs = 0.45

-- ── Layout rules ────────────────────────────────────────────────────────────

--[[
	Breakpoints are named for available ROOM, not device class.

	An iPhone in landscape and a small desktop window can end up with the same
	logical width, and when they do they should get the same layout - that is
	what responsive means. Naming these "phone" and "tablet" would invite
	device-sniffing, which is how UI ends up wrong on the one configuration
	nobody tested.

	Measured in LOGICAL pixels (viewport / scale).
]]
Theme.Breakpoint = {
	CompactMaxWidth = 900,
	MediumMaxWidth = 1350,
	--- Below this the left rail folds behind one button (docs/08 §4).
	RailCollapseWidth = 850,
}

--- Design reference. Every size in this file is a pixel at this resolution.
Theme.DesignWidth = 1280
Theme.DesignHeight = 720

Theme.ScaleRange = { Min = 0.80, Max = 1.40 }

--- Console needs a safe-area inset; TVs overscan.
Theme.ConsoleInsetScale = 0.05
Theme.ConsoleScaleBoost = 1.25

--[[
	The single UIScale applied to the whole tree.

	The lower clamp is derived from MinTouchTarget rather than picked: at any
	scale at or above MinTouchTarget / BottomButtonHeight, a bottom-bar button
	is at least 64 real pixels tall. Enforcing it here makes the mobile-first
	constraint structural - it holds on every viewport, including ones nobody
	thought to test - instead of depending on a device check being right.

	Consequence: on a very small viewport the UI is deliberately LARGER relative
	to the screen. That is correct. There is less to show and every target still
	has to be thumb-sized.
]]
function Theme.ScaleFor(viewportX: number, viewportY: number, userScalePercent: number?, isTenFoot: boolean?): number
	local ratio = math.min(viewportX / Theme.DesignWidth, viewportY / Theme.DesignHeight)

	local touchFloor = Theme.Size.MinTouchTarget / Theme.Size.BottomButtonHeight
	local minimum = math.max(Theme.ScaleRange.Min, touchFloor)

	local scale = math.clamp(ratio, minimum, Theme.ScaleRange.Max)

	-- Consoles are viewed from across a room.
	if isTenFoot then
		scale *= Theme.ConsoleScaleBoost
	end

	return scale * ((userScalePercent or 100) / 100)
end

function Theme.BreakpointFor(logicalWidth: number): string
	if logicalWidth < Theme.Breakpoint.CompactMaxWidth then
		return "compact"
	elseif logicalWidth < Theme.Breakpoint.MediumMaxWidth then
		return "medium"
	end
	return "wide"
end

--- The left rail folds away when there is no room beside gameplay for it.
function Theme.ShouldCollapseRail(logicalWidth: number): boolean
	return logicalWidth < Theme.Breakpoint.RailCollapseWidth
end

return Theme
