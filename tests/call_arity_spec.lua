--[[
	Call-arity specification.

	═══ WHY THIS FILE EXISTS ═══════════════════════════════════════════════════
	Opening the Index panel threw on the third Studio run:

	    Format:154: attempt to compare nil <= number

	`Format.Odds(weight, total)` had been called with one argument. `total` was
	nil, the `weight >= total` compare blew up, and the collection book - one of
	the game's four main panels - never opened.

	Nothing could have caught it. Luau's analyser resolves a `require` across
	files to `any`, so it never sees the arity. The specs never execute a
	controller's render path. And it is a one-character mistake in a call
	spanning three lines.

	So this reads EVERY .lua file in src as text, extracts the declared
	parameter list of the pure shared modules, and counts the arguments at each
	call site. Crude - a bracket-depth scan and a regex - and crude beats a
	panel that does not open.

	It deliberately covers only the SHARED modules: they are pure, their
	signatures are stable, and they are what gets called from everywhere. A
	service's own internal helpers change shape too often to be worth pinning.
	═══════════════════════════════════════════════════════════════════════════

	Run with:  ./tests/run.sh
]]

--@TREE Sources=src@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-56s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

--[[
	Comments first, and for the same reason instance_fields_spec strips them:
	a scanner that trips over the documentation of the bug it exists to find is
	a scanner somebody switches off.

	Long-bracket comments of any level, then line comments. Strings are NOT
	stripped - a call inside a string would be a false positive, and there are
	none in this codebase; if one appears, it is one line to allowlist.
]]
local function stripComments(text: string): string
	local out = text:gsub("%-%-%[(=*)%[.-%]%1%]", "")
	out = out:gsub("%-%-[^\n]*", "")
	return out
end

local CLEAN = {}
local fileCount = 0
for path, text in Sources do
	CLEAN[path] = stripComments(text)
	fileCount += 1
end
print(string.format("  %d source file(s) read", fileCount))
ok("the whole tree was injected", fileCount > 80)

-- ═══════════════════════════════════════════════════════════════════════════
section("Declared signatures of the shared modules")

--[[
	The modules worth pinning: pure, stable, and called from everywhere. A
	service's private helpers are deliberately out of scope.
]]
local MODULES = { "Format", "Economy", "Stats", "Patch", "Time", "RNG", "TableUtil" }

--[[
	A parameter is OPTIONAL when its type ends in `?`. Untyped parameters are
	counted as optional too, and that is not laziness - `Patch.Diff(previous,
	current, basePath, depth)` has no annotations and defaults its last two
	with `or`, so treating an untyped tail as required would report a false
	positive on a correct call. False negatives here cost nothing; false
	positives get the check switched off.
]]
local signatures = {}
local declared = 0

for _, moduleName in MODULES do
	local path = "src/ReplicatedStorage/SAD_Shared/Modules/" .. moduleName .. ".lua"
	local text = CLEAN[path]
	ok(moduleName .. " was found in the tree", text ~= nil)
	if not text then
		continue
	end

	for name, params in text:gmatch("function%s+" .. moduleName .. "%.([%w_]+)%s*%(([^)]*)%)") do
		local required, total = 0, 0
		local anyUntyped = false
		for param in params:gmatch("[^,]+") do
			param = param:match("^%s*(.-)%s*$")
			if param ~= "" then
				total += 1
				local typed = param:find(":", 1, true) ~= nil
				if not typed then
					anyUntyped = true
				end
				if typed and not param:match("%?%s*$") then
					required += 1
				end
			end
		end
		signatures[moduleName .. "." .. name] = {
			Required = if anyUntyped then 0 else required,
			Total = total,
			Untyped = anyUntyped,
		}
		declared += 1
	end
end

print(string.format("  %d function(s) across %d module(s)", declared, #MODULES))
ok("enough signatures were found to be worth checking", declared >= 40)

-- The one that broke, pinned by name so a signature change is noticed here.
local odds = signatures["Format.Odds"]
ok("Format.Odds was found", odds ~= nil)
if odds then
	eq("Format.Odds takes two arguments", odds.Total, 2)
	eq("...and both are required", odds.Required, 2)
end

-- ═══════════════════════════════════════════════════════════════════════════
section("Every call site passes an argument count the function accepts")

--[[
	Counts arguments between the matching brackets, tracking depth so a nested
	call's commas are not counted, and skipping string literals so a comma
	inside one is not either.

	Returns nil when the brackets do not close within the file, which happens
	only if the strip above ate something it should not have - a nil result is
	skipped rather than guessed at.
]]
local function countArgs(text: string, openIndex: number): number?
	local depth, count, seen = 0, 0, false
	local index = openIndex
	local inString, quote = false, ""

	while index <= #text do
		local char = text:sub(index, index)

		if inString then
			if char == "\\" then
				index += 2
				continue
			end
			if char == quote then
				inString = false
			end
		elseif char == '"' or char == "'" then
			inString, quote = true, char
		elseif char == "(" or char == "[" or char == "{" then
			depth += 1
		elseif char == ")" or char == "]" or char == "}" then
			depth -= 1
			if depth == 0 then
				return if seen then count + 1 else 0
			end
		elseif char == "," and depth == 1 then
			count += 1
		end

		if depth == 1 and char ~= "(" and not char:match("%s") then
			seen = true
		end
		index += 1
	end
	return nil
end

local problems = {}
local checked = 0

for path, text in CLEAN do
	for key, signature in signatures do
		local moduleName, functionName = key:match("^([%w_]+)%.([%w_]+)$")

		-- A module never counts its own definitions as calls.
		if path:find("/Modules/" .. moduleName .. ".lua", 1, true) then
			continue
		end

		local pattern = "%f[%w_]" .. moduleName .. "%." .. functionName .. "%s*%("
		local from = 1
		while true do
			local start, stop = text:find(pattern, from)
			if not start then
				break
			end
			from = stop

			local count = countArgs(text, stop)
			if count then
				checked += 1
				if count < signature.Required or count > signature.Total then
					local line = 1
					for _ in text:sub(1, start):gmatch("\n") do
						line += 1
					end
					table.insert(problems, string.format("%s:%d  %s takes %d-%d, called with %d",
						path, line, key, signature.Required, signature.Total, count))
				end
			end
		end
	end
end

if #problems > 0 then
	table.sort(problems)
	for _, problem in problems do
		print("    " .. problem)
	end
	print("  Each of these throws the first time that line runs.")
end

print(string.format("  %d call site(s) checked", checked))
ok("enough call sites were found for this to mean anything", checked >= 100)
eq("no call site passes the wrong number of arguments", #problems, 0)

--[[
	And the scanner must be able to fail, or it is a green light with nothing
	behind it. Two calls it has to catch and one it must not.
]]
section("The scanner catches what it claims to")

local FIXTURE = [[
	local a = Format.Odds(weights[rarity] or 0)
	local b = Format.Odds(w, total)
	local c = Format.Odds(w, total, extra)
	local d = Format.Comma(math.floor(total / weight + 0.5))
	local e = Format.Odds(f(x, y), g(z))
]]

local counts = {}
local from = 1
while true do
	local start, stop = FIXTURE:find("%f[%w_]Format%.Odds%s*%(", from)
	if not start then break end
	from = stop
	table.insert(counts, countArgs(FIXTURE, stop))
end

eq("four Format.Odds calls in the fixture", #counts, 4)
eq("the one-argument call is seen as one", counts[1], 1)
eq("the correct call is seen as two", counts[2], 2)
eq("the over-long call is seen as three", counts[3], 3)
eq("nested calls do not leak their commas", counts[4], 2)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
