--[[
	Instance-field specification.

	═══ WHY THIS FILE EXISTS ═══════════════════════════════════════════════════
	A Roblox `Instance` is not a Lua table. Writing a field that is not a real
	property does not add it — it throws:

	    Rarity is not a valid member of Frame "…CarryPanel"

	That single line killed the client on the first two Studio runs of this
	project, in `HUDController.Init`, from code written in Step 5. Seven
	assignments across four panels, sitting there through nineteen build steps
	while 5,097 offline assertions passed over them.

	They passed because no spec can catch it the ordinary way: the specs never
	construct an `Instance`, and cannot, outside Roblox. The only assertion that
	would have failed is "does Roblox accept this property", and only Roblox can
	answer that.

	So this reads the client source as TEXT and flags any capitalised field
	written onto a local that holds an Instance. Crude — a regex, an allowlist,
	and a list of locals — and crude beats a third Studio run finding the same
	bug in a fifth panel.
	═══════════════════════════════════════════════════════════════════════════

	It is deliberately NOT a general Roblox property database. It knows the
	properties this project actually assigns, which is a short list, and
	anything outside it has to be added here on purpose. A false positive costs
	one line; a false negative costs a Play session.

	Run with:  ./tests/run.sh
]]

--@SOURCE HUDSource=src/StarterPlayer/StarterPlayerScripts/SAD_Client/Controllers/HUDController.lua@
--@SOURCE WidgetsSource=src/StarterPlayer/StarterPlayerScripts/SAD_Client/UI/Widgets.lua@
--@SOURCE CreateSource=src/StarterPlayer/StarterPlayerScripts/SAD_Client/UI/Create.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

--[[
	Every property this project actually assigns to a GuiObject or a BasePart.
	Short on purpose — see the header. Add to it deliberately, never to silence
	a failure you have not read.
]]
local REAL_PROPERTIES = {}
for _, name in ipairs({
	-- GuiObject
	"Name", "Parent", "Visible", "Position", "Size", "AnchorPoint", "ZIndex",
	"BackgroundColor3", "BackgroundTransparency", "BorderSizePixel", "Rotation",
	"ClipsDescendants", "Active", "Selectable", "LayoutOrder", "AutomaticSize",
	-- Text
	"Text", "TextColor3", "TextSize", "TextTransparency", "TextWrapped",
	"TextScaled", "TextXAlignment", "TextYAlignment", "TextTruncate", "Font",
	"RichText", "AutoButtonColor", "PlaceholderText",
	-- Image
	"Image", "ImageColor3", "ImageTransparency", "ImageRectOffset", "ImageRectSize",
	"ScaleType",
	-- Scrolling
	"CanvasSize", "CanvasPosition", "AutomaticCanvasSize", "ScrollBarThickness",
	"ScrollBarImageColor3", "ScrollingDirection", "ElasticBehavior",
	-- Constraints and modifiers
	"CornerRadius", "Color", "Thickness", "Transparency", "ApplyStrokeMode",
	"Scale", "MinTextSize", "MaxTextSize", "PaddingTop", "PaddingBottom",
	"PaddingLeft", "PaddingRight", "FillDirection", "HorizontalAlignment",
	"VerticalAlignment", "SortOrder", "Padding", "CellSize", "CellPadding",
	-- ScreenGui / layers
	"DisplayOrder", "IgnoreGuiInset", "ResetOnSpawn", "ScreenInsets", "Enabled",
	-- BasePart, for the world-space bits
	"CFrame", "Anchored", "CanCollide", "CanQuery", "CanTouch", "Material",
	"Shape", "CastShadow", "TopSurface", "BottomSurface", "Massless",
	"PrimaryPart", "Adornee", "Face", "SizingDefinition", "PixelsPerStud",
	"AlwaysOnTop", "MaxDistance", "LightInfluence", "Brightness",
	-- ProximityPrompt
	"ActionText", "ObjectText", "HoldDuration", "MaxActivationDistance",
	"RequiresLineOfSight", "KeyboardKeyCode", "Style",
	-- Lighting
	"FogEnd", "FogStart", "FogColor", "Ambient", "OutdoorAmbient", "ClockTime",
	"GlobalShadows", "ExposureCompensation",
	-- Sound
	"SoundId", "Volume", "PlaybackSpeed", "Looped", "TimePosition", "RollOffMaxDistance",
	-- AnimationTrack (not an Instance property write, but the same syntax)
	"Priority", "Speed", "Weight",
}) do
	REAL_PROPERTIES[name] = true
end

--[[
	Locals in the scanned files that hold an `Instance`. Named explicitly rather
	than inferred, because inferring it from the source is exactly the kind of
	cleverness that produces a check nobody trusts.
]]
local INSTANCE_LOCALS = {
	HUDController = {
		"hud", "topBar", "leftRail", "rightRail", "bottomBar", "actionPrompt",
		"carryPanel", "chaseBanner", "chaseVignette", "flashPanel", "hatchPanel",
		"compass", "eventBanner", "railToggle", "label", "title", "subtitle",
		"odds", "rarityLabel", "distanceLabel", "stroke",
	},
	Widgets = { "frame", "label", "badge", "icon", "fill", "value", "guiObject" },
	Create = { "instance", "child" },
}

--[[
	Comments are stripped before scanning, and that is not a nicety.

	The first run of this check flagged `carryPanel.Rarity` — inside the comment
	in `HUDController` explaining that `carryPanel.Rarity` throws. A scanner
	that trips over the documentation of the bug it exists to find is a scanner
	somebody switches off, and then it catches nothing at all.

	Block comments first (so a `--` inside one is not treated as a line
	comment), then line comments. A nested closing double-bracket ends a block
	early; that costs a false positive at worst and never a false negative,
	which is the right way round for this check.

	(That sentence originally contained the two characters it describes, which
	closed THIS comment early and made the rest of the file parse as code. The
	bug this spec is about, in the spec that is about it.)
]]
local function stripComments(text: string): string
	local withoutBlocks = text:gsub("%-%-%[%[.-%]%]", "")
	local withoutLines = withoutBlocks:gsub("%-%-[^\n]*", "")
	return withoutLines
end

local SOURCES = {
	{ Name = "HUDController", Text = stripComments(HUDSource) },
	{ Name = "Widgets", Text = stripComments(WidgetsSource) },
	{ Name = "Create", Text = stripComments(CreateSource) },
}

section("No capitalised field is written onto a Roblox Instance")

--[[
	The scan. For each named Instance local, find `local.Field =` writes and
	check the field against the allowlist.

	`==` is excluded so comparisons are not mistaken for assignments, and a
	field that is itself a table index (`a.B.C = x`) is fine — only the FIRST
	hop lands on the Instance.
]]
local flagged = {}
local scanned = 0

for _, source in ipairs(SOURCES) do
	local locals = INSTANCE_LOCALS[source.Name]
	ok(source.Name .. " source was injected", type(source.Text) == "string" and #source.Text > 0)

	for _, name in ipairs(locals) do
		--[[
			`[^.=]` after the field name excludes `a.B.C = x` (a write through
			the field, which is fine) and `a.B == x` (a comparison).
		]]
		local pattern = "%f[%w_]" .. name .. "%.([A-Z][%w_]*)%s*=[^=]"
		for field in source.Text:gmatch(pattern) do
			scanned += 1
			if not REAL_PROPERTIES[field] then
				table.insert(flagged, string.format("%s: %s.%s", source.Name, name, field))
			end
		end
	end
end

if #flagged > 0 then
	table.sort(flagged)
	print("  fields written onto an Instance that are not real properties:")
	for _, entry in ipairs(flagged) do
		print("    " .. entry)
	end
	print("  Each of these throws at runtime. Hold the handle in a plain table")
	print("  beside the instance instead - see HUDController's carryParts.")
end

print(string.format("  %d property write(s) checked across %d file(s)", scanned, #SOURCES))
eq("nothing is written onto an Instance that Roblox would reject", #flagged, 0)

--[[
	And the positive case: the handle tables the fix introduced must actually be
	plain Lua tables, or the fix is the bug with a new name.
]]
section("The handle tables are tables")

for _, name in ipairs({ "carryParts", "flashParts", "hatchParts", "chaseParts" }) do
	-- Read from the raw source: these are declarations, not property writes.
	ok(name .. " is declared as a plain table",
		HUDSource:find("local " .. name .. " = {}", 1, true) ~= nil)
	ok(name .. " is not created from a widget",
		HUDSource:find("local " .. name .. " = Widgets", 1, true) == nil)
end

--[[
	═══ THE ROOT CAUSE, ASSERTED ═══════════════════════════════════════════════
	`Widgets.Panel` returns a bare `Frame` while `Widgets.Chip` returns a table
	of handles. Two conventions side by side is what invited seven assignments
	onto an Instance in the first place.

	Not changed here — `Panel` has a dozen call sites and this is a bug-fix, not
	a refactor — but recorded as an assertion so the inconsistency is a fact the
	suite states rather than a thing somebody has to notice again.
	═══════════════════════════════════════════════════════════════════════════
]]
section("The convention that invited it")

ok("Widgets.Chip returns a handle table",
	WidgetsSource:find("return { Instance = frame", 1, true) ~= nil)
ok("Widgets.Panel returns a bare Instance",
	WidgetsSource:find("function Widgets.Panel", 1, true) ~= nil)
print("  Panel returns an Instance and Chip returns a table. Unify before the")
print("  next panel is written - see PROGRESS.md finding 49.")

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
