--[[
	Wiring specification: nothing is fired into the void.

	═══ WHY THIS FILE EXISTS ═══════════════════════════════════════════════════
	Holding E on a nest egg did nothing. `NestBuilder` put a ProximityPrompt on
	every egg, `NestService` fired `PickupRequested` when one was triggered, and
	NOTHING LISTENED. Meanwhile `EggService` handled a `RequestPickupEgg` remote
	that no client ever sent. Two halves of the game's core loop, neither joined
	to the other, through every one of the twenty-four build steps.

	It is the same failure as rule 11 in Step 17 (registered, never defined) and
	the same as findings 29, 30, 56 and 131: something that LOOKS like wiring
	and is decoration. It is the most common bug in this project by a distance,
	and it is invisible to every other check - a dead Signal is valid Luau, it
	compiles, and the boot log says "Ready".

	So this walks the whole source tree and asserts, for every Signal and every
	entry in the frozen `Net` inventory, that both ends exist. Anything that is
	deliberately one-ended is named in an allowlist WITH ITS REASON, so the
	difference between "an extension point nobody needed yet" and "the bug that
	made the game unplayable" is written down instead of assumed.
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

local function stripComments(text: string): string
	local out = text:gsub("%-%-%[(=*)%[.-%]%1%]", "")
	return (out:gsub("%-%-[^\n]*", ""))
end

local CLEAN, SERVER, CLIENT = {}, {}, {}
local blob = {}
for path, text in Sources do
	local clean = stripComments(text)
	CLEAN[path] = clean
	table.insert(blob, clean)
	if path:find("/ServerScriptService/", 1, true) then
		SERVER[path] = clean
	elseif path:find("/StarterPlayer/", 1, true) and not path:find("DebugExploit", 1, true) then
		--[[
			DebugExploitClient is excluded deliberately. It fires every c2s
			remote in the inventory by design, so counting it as a sender would
			make every remote look wired and this check would pass forever.
		]]
		CLIENT[path] = clean
	end
end
local ALL = table.concat(blob, "\n")

local function anyMatch(group, pattern): boolean
	for _, text in group do
		if text:find(pattern) then
			return true
		end
	end
	return false
end

-- ═══════════════════════════════════════════════════════════════════════════
section("Every Signal has a listener, or a written reason not to")

--[[
	Signals nothing listens to ON PURPOSE, each with why.

	Observability hooks are legitimate: a Signal fired beside work that already
	happened, so a future system can hang off it without the firing service
	knowing. What is NOT legitimate is a Signal that is the ONLY link in a
	chain - which is exactly what PickupRequested was.

	The test is asymmetric on purpose. Adding an unlistened Signal fails until
	it is justified here; connecting one that is listed also fails, so the list
	cannot rot into a graveyard of things that quietly got wired up.
]]
local DELIBERATELY_UNHEARD = {
	["InputController.DeviceChanged"] = "touch and gamepad UI swapping is not built; the device is read directly where it matters",
	["LeaderboardService.BoardsRefreshed"] = "LeaderboardController polls its own cache; this is for a future push",
	["NestService.EggClaimed"] = "observability - the claim itself is done before it fires",
	["NestService.NestRefilled"] = "observability - the egg is already back",
	["ParkService.ParkExited"] = "ParkEntered is the one that banks eggs; leaving costs nothing",
	["StateController.Ready"] = "controllers read StateController.Get() directly; nothing waits on a first frame",
	["UIController.ScreenChanged"] = "panels manage their own open state",
	["WildAIService.ThiefCaught"] = "observability - DropAll, the stat and the ChaseState packet all run inline before it",
	["ZoneService.ShrineFound"] = "observability - the unlock is written before it fires",
	["ZoneService.Teleported"] = "observability - the teleport has already happened",
}

local declared, unheard = 0, {}
for path, text in CLEAN do
	for owner, name in text:gmatch("\n([%w_]+)%.([%w_]+)%s*=%s*Signal%.new%(%)") do
		declared += 1
		local key = owner .. "." .. name
		local listened = ALL:find("%f[%w_]" .. name .. "%s*:%s*Connect")
			or ALL:find("%f[%w_]" .. name .. "%s*:%s*Once")
			or ALL:find("%f[%w_]" .. name .. "%s*:%s*Wait")
			--[[
				`Trove:Connect(Service.Signal, fn)` is the other subscribe form
				in this codebase - EventService's handlers use it - and it does
				not look like `:Connect` on the signal at all.
			]]
			or ALL:find("Connect%(%s*[%w_]+%." .. name .. "%s*,")
		if not listened then
			table.insert(unheard, key)
		end
	end
end

print(string.format("  %d Signal(s) declared across the tree", declared))
ok("enough Signals were found for this to mean anything", declared >= 40)

table.sort(unheard)
local unexplained = {}
for _, key in unheard do
	if not DELIBERATELY_UNHEARD[key] then
		table.insert(unexplained, key)
	end
end
if #unexplained > 0 then
	print("  Signals fired into the void:")
	for _, key in unexplained do
		print("    " .. key)
	end
	print("  Each of these is a system that runs and tells nothing.")
end
eq("no Signal is fired into the void", #unexplained, 0)

--[[
	And the other direction: an allowlist entry that HAS become connected is
	stale, and a stale allowlist is how the next PickupRequested hides.
]]
local stale = {}
local unheardSet = {}
for _, key in unheard do
	unheardSet[key] = true
end
for key in DELIBERATELY_UNHEARD do
	if not unheardSet[key] then
		table.insert(stale, key)
	end
end
table.sort(stale)
for _, key in stale do
	print("    " .. key .. " is listed as unheard but something listens now")
end
eq("the allowlist has no stale entries", #stale, 0)

--[[
	The two this file was written for. Pinned by name so a future refactor that
	drops either connection fails here rather than in a Play session.
]]
section("The two that were broken")

ok("something listens to NestService.PickupRequested",
	ALL:find("NestService.PickupRequested:Connect", 1, true) ~= nil)
ok("...and it is EggService.TryPickup",
	anyMatch(SERVER, "PickupRequested:Connect.-TryPickup"))
ok("something listens to EggService.RareGrab",
	ALL:find("EggService.RareGrab:Connect", 1, true) ~= nil)

-- ═══════════════════════════════════════════════════════════════════════════
section("Every remote in the frozen inventory has both ends")

--[[
	The `Net` inventory declares direction per event. A c2s event with no
	server handler is a request that vanishes; an s2c event with no client
	handler is an announcement nobody hears.

	Only the HANDLER side is checked, and that is a deliberate limit rather
	than an oversight. Handlers are always registered with a literal name -
	`Net.OnEvent("X", ...)` and `Net.On("X", ...)` - so their absence is a
	fact. The SENDING side is often config-driven (`Net.FireServer(remote,
	...)` where `remote` came from UpgradeConfig), so "nobody sends this" can
	only ever be a guess, and a check that guesses is a check that gets turned
	off.
]]
local netSource = CLEAN["src/ReplicatedStorage/SAD_Shared/Modules/Net.lua"]
ok("Net.lua was found in the tree", netSource ~= nil)

local UNHANDLED_ON_PURPOSE = {
	--[[
		Reserved in the frozen inventory for features past V1. The inventory is
		frozen precisely so these names cannot drift, so they are declared long
		before they are built.
	]]
	RequestFuse = "fusion is V1.2",
	RequestRerollMutation = "mutation reroll is V1.2",
	RequestSellDinos = "bulk sell is V1.1",
	RequestSetDinoFlags = "per-dinosaur flags are V1.1",
	RequestUseItem = "the item system is V1.3",
	IncomePopup = "ParkController generates income floaters entirely client-side from replicated state - thirty remotes a second was the alternative",
}

local events, gaps = 0, {}
for name, direction in netSource:gmatch("([%w_]+)%s*=%s*{%s*dir%s*=%s*\"(%w+)\"") do
	if direction ~= "c2s" and direction ~= "s2c" then
		continue
	end
	events += 1

	local handled
	if direction == "c2s" then
		handled = anyMatch(SERVER, "OnEvent%(%s*\"" .. name .. "\"")
			or anyMatch(SERVER, "OnInvoke%(%s*\"" .. name .. "\"")
	else
		handled = anyMatch(CLIENT, "Net%.On%(%s*\"" .. name .. "\"")
	end

	if not handled and not UNHANDLED_ON_PURPOSE[name] then
		table.insert(gaps, string.format("%s (%s) has no handler", name, direction))
	end
end

print(string.format("  %d event(s) in the inventory", events))
ok("the whole inventory was parsed", events >= 35)

table.sort(gaps)
for _, gap in gaps do
	print("    " .. gap)
end
eq("every remote that should be handled is handled", #gaps, 0)

--[[
	`EventState` is the one this section caught. Four world events fire every
	twelve to eighteen minutes and the client had no handler at all, so a
	Meteor Impact ran its full duration with the player told nothing.
]]
ok("the client handles EventState",
	anyMatch(CLIENT, "Net%.On%(%s*\"EventState\""))
ok("...and it drives the banner slot that was reserved for it",
	anyMatch(CLIENT, "BannerPriority.Event"))

--[[
	Which made a latent flaw in the shared banner reachable: it used to hide
	outright when its holder released it, so an event ending would blank a
	weather line that was still true.
]]
ok("the banner keeps a text per priority rather than one holder",
	anyMatch(CLIENT, "bannerTexts%["))
ok("...and the single-holder version is gone",
	not anyMatch(CLIENT, "bannerHolder%s*="))

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
