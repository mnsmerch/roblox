--[[
	Step 5 specification.

	The mobile-first constraint from docs/08 §4 - every touch target at least
	64 real pixels - made executable. It is asserted across a matrix of real
	device viewports rather than by resizing a Studio window and squinting.

	Theme is pure data plus pure functions, so it needs no Roblox shims beyond
	Color3 and Enum, which the tokens build at load.

	Run with:  ./tests/run.sh
]]

-- ── Roblox shims ────────────────────────────────────────────────────────────
-- Theme constructs Color3, UDim and Enum values at load. Stand-ins are enough:
-- the spec asserts on numbers, not on rendering.

Color3 = {
	fromHex = function(hex) return { Hex = hex, __type = "Color3" } end,
	fromRGB = function(r, g, b) return { R = r, G = g, B = b, __type = "Color3" } end,
}
UDim = { new = function(scale, offset) return { Scale = scale, Offset = offset } end }
Enum = setmetatable({}, {
	__index = function(_, group)
		return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
	end,
})

--@INJECT Theme=src/StarterPlayer/StarterPlayerScripts/SAD_Client/UI/Theme.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-46s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

------------------------------------------------------------------ tokens
section("Theme tokens")

ok("touch minimum is 64px", Theme.Size.MinTouchTarget == 64)
ok("bottom button clears the minimum at scale 1",
	Theme.Size.BottomButtonHeight >= Theme.Size.MinTouchTarget)
ok("bottom bar is taller than its buttons",
	Theme.Size.BottomBarHeight > Theme.Size.BottomButtonHeight)

-- Layers must be strictly ordered, or a takeover renders behind a menu.
local layerOrder = { "Hud", "Screen", "Prompt", "Notification", "Takeover" }
local previous = 0
for _, name in ipairs(layerOrder) do
	ok("layer defined: " .. name, Theme.Layer[name] ~= nil)
	ok("layer above the one below: " .. name, Theme.Layer[name] > previous)
	previous = Theme.Layer[name]
end

-- Type scale must ascend, or "Small" is bigger than "Body" somewhere.
local sizeOrder = { "Tiny", "Small", "Body", "Label", "Heading", "Display", "Huge" }
previous = 0
for _, name in ipairs(sizeOrder) do
	ok("text size ascends: " .. name, Theme.TextSize[name] > previous)
	previous = Theme.TextSize[name]
end

local spaceOrder = { "XS", "S", "M", "L", "XL", "XXL" }
previous = 0
for _, name in ipairs(spaceOrder) do
	ok("spacing ascends: " .. name, Theme.Space[name] > previous)
	previous = Theme.Space[name]
end

ok("scale range is sane", Theme.ScaleRange.Min > 0 and Theme.ScaleRange.Max > Theme.ScaleRange.Min)
ok("breakpoints ascend", Theme.Breakpoint.CompactMaxWidth < Theme.Breakpoint.MediumMaxWidth)
ok("rail collapses inside the compact band",
	Theme.Breakpoint.RailCollapseWidth <= Theme.Breakpoint.CompactMaxWidth)

------------------------------------------------------------------ scaling
section("Touch targets across real viewports")

--[[
	Every one of these must produce a bottom-bar button of at least 64 real
	pixels. If a change to the scale maths ever breaks that, it breaks here
	instead of on a player's phone.
]]
local DEVICES = {
	{ Name = "iPhone SE landscape", X = 667, Y = 375 },
	{ Name = "iPhone 14 landscape", X = 844, Y = 390 },
	{ Name = "Pixel 7 landscape", X = 915, Y = 412 },
	{ Name = "small Android landscape", X = 640, Y = 360 },
	{ Name = "iPad landscape", X = 1180, Y = 820 },
	{ Name = "iPad portrait", X = 820, Y = 1180 },
	{ Name = "Surface / small laptop", X = 1366, Y = 768 },
	{ Name = "720p window", X = 1280, Y = 720 },
	{ Name = "1080p", X = 1920, Y = 1080 },
	{ Name = "1440p", X = 2560, Y = 1440 },
	{ Name = "4K", X = 3840, Y = 2160 },
	{ Name = "tiny window", X = 480, Y = 270 },
}

print(string.format("  %-26s %6s %6s %7s %8s %9s %s",
	"viewport", "px", "scale", "button", "logical", "layout", "rail"))

for _, device in ipairs(DEVICES) do
	local scale = Theme.ScaleFor(device.X, device.Y, 100, false)
	local buttonPx = Theme.Size.BottomButtonHeight * scale
	local logical = device.X / scale
	local breakpoint = Theme.BreakpointFor(logical)
	local collapsed = Theme.ShouldCollapseRail(logical)

	print(string.format("  %-26s %4dx%-4d %6.3f %7.1f %8.0f %9s %s",
		device.Name, device.X, device.Y, scale, buttonPx, logical, breakpoint,
		collapsed and "collapsed" or "shown"))

	ok("touch target >= 64px: " .. device.Name, buttonPx >= Theme.Size.MinTouchTarget - 0.001)
	ok("top bar fits: " .. device.Name, Theme.Size.TopBarHeight * scale < device.Y * 0.2)
	ok("bottom bar under a third of height: " .. device.Name,
		Theme.Size.BottomBarHeight * scale < device.Y * 0.34)
	ok("breakpoint is known: " .. device.Name,
		breakpoint == "compact" or breakpoint == "medium" or breakpoint == "wide")
end

section("Scale behaviour")

-- The floor is derived from the touch target, not picked by hand.
local floor = Theme.Size.MinTouchTarget / Theme.Size.BottomButtonHeight
eq("a tiny viewport lands exactly on the floor",
	math.floor(Theme.ScaleFor(320, 180, 100, false) * 10000 + 0.5),
	math.floor(math.max(floor, Theme.ScaleRange.Min) * 10000 + 0.5))

ok("a huge viewport is capped", Theme.ScaleFor(7680, 4320, 100, false) <= Theme.ScaleRange.Max)
ok("scale rises with viewport", Theme.ScaleFor(1920, 1080, 100, false) > Theme.ScaleFor(1280, 720, 100, false))

-- The accessibility slider from docs/06 §8.
local base = Theme.ScaleFor(1920, 1080, 100, false)
ok("80% setting shrinks", Theme.ScaleFor(1920, 1080, 80, false) < base)
ok("130% setting grows", Theme.ScaleFor(1920, 1080, 130, false) > base)
eq("100% is the identity", Theme.ScaleFor(1920, 1080, 100, false), base)
eq("nil percent means 100", Theme.ScaleFor(1920, 1080, nil, false), base)

-- Even at the smallest accessibility setting on the smallest phone, the button
-- must stay usable. 80% of 64 is 51px, which is the documented floor for a
-- player who has deliberately chosen smaller UI.
local worst = Theme.ScaleFor(640, 360, 80, false) * Theme.Size.BottomButtonHeight
ok(string.format("worst case with 80%% UI scale is still usable (%.1fpx)", worst), worst >= 50)

ok("console scales up", Theme.ScaleFor(1920, 1080, 100, true) > Theme.ScaleFor(1920, 1080, 100, false))
eq("console boost is exactly the documented factor",
	math.floor(Theme.ScaleFor(1920, 1080, 100, true) / Theme.ScaleFor(1920, 1080, 100, false) * 1000 + 0.5),
	math.floor(Theme.ConsoleScaleBoost * 1000 + 0.5))

section("Breakpoints")

eq("narrow is compact", Theme.BreakpointFor(700), "compact")
eq("just under the compact edge", Theme.BreakpointFor(Theme.Breakpoint.CompactMaxWidth - 1), "compact")
eq("at the compact edge is medium", Theme.BreakpointFor(Theme.Breakpoint.CompactMaxWidth), "medium")
eq("just under the medium edge", Theme.BreakpointFor(Theme.Breakpoint.MediumMaxWidth - 1), "medium")
eq("at the medium edge is wide", Theme.BreakpointFor(Theme.Breakpoint.MediumMaxWidth), "wide")
eq("very wide", Theme.BreakpointFor(3000), "wide")

ok("rails collapse when narrow", Theme.ShouldCollapseRail(400))
ok("rails stay when wide", not Theme.ShouldCollapseRail(1400))

-- Two viewports with the same room must get the same layout - that is what
-- responsive means, and it is why breakpoints read logical width rather than
-- sniffing the device.
local tabletScale = Theme.ScaleFor(1180, 820, 100, false)
local desktopScale = Theme.ScaleFor(1280, 720, 100, false)
eq("equal logical width means equal layout",
	Theme.BreakpointFor(1180 / tabletScale) == Theme.BreakpointFor(1280 / desktopScale), true)

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
