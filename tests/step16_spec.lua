--[[
	Step 16 specification.

	Notifications and cross-server announcements. The failure modes here are
	quiet ones: a queue that grows instead of dropping, a severity a caller can
	promote itself into, a payload that survives JSON but not rendering, and a
	publish budget that is only discovered by being throttled in production.

	Run with:  ./tests/run.sh
]]

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT NotificationConfig=src/ReplicatedStorage/SAD_Shared/Config/NotificationConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

------------------------------------------------------------------ severities
section("The four severities (docs/08 §5)")

--[[
	The published table, line by line. These durations are read on BOTH sides -
	the server stamps them, the client counts them down - so a drift here is a
	five-second banner that vanishes after three.
]]
local PUBLISHED = {
	{ "toast", 3 }, { "banner", 5 }, { "takeover", 4 },
	{ "alert", NotificationConfig.UntilResolved },
}
for _, row in ipairs(PUBLISHED) do
	local severity = NotificationConfig.Get(row[1])
	ok("severity exists: " .. row[1], severity ~= nil)
	eq(row[1] .. " lasts " .. row[2] .. "s", severity.Duration, row[2])
end
eq("four severities, no more", #NotificationConfig.Order, 4)
eq("every published severity is asserted", #PUBLISHED, #NotificationConfig.Order)

-- Priority must be a strict total order, or "which one wins" has no answer.
local seenPriority = {}
local previous = 0
for _, kind in ipairs(NotificationConfig.Order) do
	local priority = NotificationConfig.Get(kind).Priority
	ok("priority rises with weight: " .. kind, priority > previous)
	ok("priority is unique: " .. kind, seenPriority[priority] == nil)
	seenPriority[priority] = true
	previous = priority
end

ok("a takeover outranks a banner", NotificationConfig.Outranks("takeover", "banner"))
ok("an alert outranks everything", NotificationConfig.Outranks("alert", "takeover"))
ok("a toast outranks nothing", not NotificationConfig.Outranks("toast", "banner"))
ok("a tie does not displace", not NotificationConfig.Outranks("toast", "toast"))

--[[
	docs/08 §5: "a player's own park alerts cannot be muted". Takeovers are
	unmutable too - a Titan hatch is the game's headline event, and a setting
	that hides it is a setting that hides why the game exists.
]]
ok("alerts cannot be muted", NotificationConfig.Get("alert").Mutable == false)
ok("takeovers cannot be muted", NotificationConfig.Get("takeover").Mutable == false)
ok("banners can be", NotificationConfig.Get("banner").Mutable == true)

------------------------------------------------------------------ queueing
section("The queue drops rather than grows")

--[[
	docs/08 §5: "max 1 takeover at a time (others queue, max queue 3, then
	drop)". Dropping is the whole design - a player who has had five Titans
	announced at them wants to keep playing, not watch twenty seconds of
	backlog. The rule is only correct if the queue really refuses.
]]
eq("one takeover on screen at a time", NotificationConfig.Get("takeover").Concurrent, 1)
eq("three more may wait", NotificationConfig.Get("takeover").QueueLimit, 3)

local function pump(limit, arrivals)
	local queue, dropped = {}, 0
	for _ = 1, arrivals do
		if #queue >= limit then
			dropped += 1
		else
			table.insert(queue, true)
		end
	end
	return #queue, dropped
end

local queued, dropped = pump(NotificationConfig.Get("takeover").QueueLimit, 5)
eq("five takeovers: three queue", queued, 3)
eq("...and two are dropped", dropped, 2)

local exact = pump(NotificationConfig.Get("takeover").QueueLimit, 3)
eq("exactly three fit", exact, 3)
eq("...with nothing dropped", select(2, pump(NotificationConfig.Get("takeover").QueueLimit, 3)), 0)

-- Toasts stack rather than queue: three on screen, oldest evicted.
eq("three toasts on screen", NotificationConfig.Get("toast").Concurrent, 3)
ok("toasts allow more concurrent than takeovers",
	NotificationConfig.Get("toast").Concurrent > NotificationConfig.Get("takeover").Concurrent)

-- An alert is singular by construction: there is one bar.
eq("one alert bar", NotificationConfig.Get("alert").Concurrent, 1)
eq("...and no alert queue", NotificationConfig.Get("alert").QueueLimit, 1)

--------------------------------------------------------------- resolution
section("An unknown severity is shown, not dropped")

--[[
	A caller that sends a typo should produce a quiet notification, never a
	silent one and never a loud one. Falling back UP would let any call site
	dim everyone's screen by misspelling a word.
]]
eq("a known kind resolves to itself", NotificationConfig.Resolve("banner"), "banner")
eq("an unknown kind falls back", NotificationConfig.Resolve("shout"), "toast")
eq("nil falls back", NotificationConfig.Resolve(nil), "toast")
eq("the fallback is the quietest severity", NotificationConfig.Fallback, "toast")
eq("...which is priority 1", NotificationConfig.Get(NotificationConfig.Fallback).Priority, 1)

eq("duration follows the resolved severity",
	NotificationConfig.DurationOf("shout"), NotificationConfig.Get("toast").Duration)
eq("an explicit duration wins", NotificationConfig.DurationOf("toast", 9), 9)
eq("a zero duration does not", NotificationConfig.DurationOf("toast", 0),
	NotificationConfig.Get("toast").Duration)

------------------------------------------------------------------ payloads
section("Payload sanitising (docs/13: unvalidated inbound payloads)")

--[[
	The same function runs on both sides: the server before publishing across
	MessagingService, the client before rendering what arrived. One validation
	rather than two that drift.
]]
eq("a non-table is refused", NotificationConfig.Sanitise("hello"), nil)
eq("nil is refused", NotificationConfig.Sanitise(nil), nil)
eq("an empty table is refused", NotificationConfig.Sanitise({}), nil)

local clean = NotificationConfig.Sanitise({ Kind = "banner", Text = "hi", Duration = 4, Loud = true })
ok("a good payload survives", clean ~= nil)
eq("...with its kind", clean.Kind, "banner")
eq("...its strings", clean.Text, "hi")
eq("...its numbers", clean.Duration, 4)
eq("...and its booleans", clean.Loud, true)

--[[
	Nested tables are dropped: a notification is a flat message, and a nested
	one is the shape that makes a 1 KB MessagingService cap surprising.
]]
local nested = NotificationConfig.Sanitise({ Text = "hi", Payload = { a = 1 } })
eq("nested tables are dropped", nested.Payload, nil)
eq("...without taking the rest with them", nested.Text, "hi")

local withFunction = NotificationConfig.Sanitise({ Text = "hi", Fn = print })
eq("functions are dropped", withFunction.Fn, nil)

-- Long strings are truncated rather than dropped: a long display name must
-- not silently lose an announcement the rest of the game promises will arrive.
local long = string.rep("x", 500)
local truncated = NotificationConfig.Sanitise({ Text = long })
eq("long strings are truncated", #truncated.Text, NotificationConfig.MaxStringLength)
ok("...not dropped", truncated.Text ~= nil)

-- Non-string keys, and absurdly long ones, cannot reach a renderer.
local oddKeys = NotificationConfig.Sanitise({ Text = "hi", [1] = "array", [string.rep("k", 64)] = "long" })
eq("numeric keys are dropped", oddKeys[1], nil)
eq("over-long keys are dropped", oddKeys[string.rep("k", 64)], nil)
eq("...and the good key survives", oddKeys.Text, "hi")

--[[
	NaN and infinity both survive JSON encoding badly and render worse - a
	Duration of inf is a notification that never leaves the screen.
]]
local nan = 0 / 0
eq("NaN is dropped", NotificationConfig.Sanitise({ Text = "hi", Duration = nan }).Duration, nil)
eq("infinity is dropped", NotificationConfig.Sanitise({ Text = "hi", Duration = math.huge }).Duration, nil)
eq("negative infinity is dropped",
	NotificationConfig.Sanitise({ Text = "hi", Duration = -math.huge }).Duration, nil)

-- Sanitising is idempotent: running it on both sides must not change anything.
local once = NotificationConfig.Sanitise({ Kind = "banner", Text = "hi", Duration = 4 })
local twice = NotificationConfig.Sanitise(once)
eq("sanitising twice is the same as once (kind)", twice.Kind, once.Kind)
eq("...(text)", twice.Text, once.Text)
eq("...(duration)", twice.Duration, once.Duration)

-- An unknown kind is normalised by Sanitise itself, so nothing downstream has
-- to resolve it a second time.
eq("sanitise normalises the kind", NotificationConfig.Sanitise({ Kind = "shout", Text = "x" }).Kind, "toast")

--------------------------------------------------------------- cross-server
section("MessagingService budget")

--[[
	docs/09 §7.7 fixes this at 6 messages/min with payloads under 800 bytes.
	Roblox's own limit is roughly (150 + 60 x players) per minute per server,
	so the doc's number sits far under the FLOOR of that - an empty server.

	Asserted against the doc rather than against the code, because the point of
	a published budget is that it does not quietly widen.
]]
eq("the budget is docs/09 §7.7's 6 per minute", NotificationConfig.PublishBudget, 6)
eq("...over a 60-second window", NotificationConfig.PublishWindow, 60)
eq("payloads are capped at 800 bytes", NotificationConfig.MaxPayloadBytes, 800)
local ROBLOX_FLOOR_PER_MIN = 150
local perMinute = NotificationConfig.PublishBudget * (60 / NotificationConfig.PublishWindow)
print(string.format("  budget %d per %ds = %.0f/min against a documented floor of %d/min",
	NotificationConfig.PublishBudget, NotificationConfig.PublishWindow,
	perMinute, ROBLOX_FLOOR_PER_MIN))

ok("the budget is under Roblox's floor", perMinute < ROBLOX_FLOOR_PER_MIN)
ok("...with real headroom, not a rounding error", perMinute < ROBLOX_FLOOR_PER_MIN * 0.5)
ok("but enough for everything the game can actually generate", perMinute >= 6)

-- The message cap is 1 KB. The budget for a payload has to leave envelope room.
eq("payloads stay under Roblox's 1 KB cap", NotificationConfig.MaxPayloadBytes < 1024, true)

--[[
	The worst realistic announcement: two maximum-length strings plus the
	envelope. It has to fit, or the loudest moment in the game is the one that
	silently fails to cross servers.
]]
local worst = {
	Kind = "takeover",
	Title = string.rep("W", NotificationConfig.MaxStringLength),
	Subtitle = string.rep("W", NotificationConfig.MaxStringLength),
	Headline = string.rep("W", NotificationConfig.MaxStringLength),
	From = string.rep("f", 36), -- a JobId
	Duration = 6,
}
local encodedSize = 0
for key, value in pairs(worst) do
	encodedSize += #key + 6 -- quotes, colon, comma
	encodedSize += if type(value) == "string" then #value + 2 else 8
end
print(string.format("  worst-case announcement is about %d bytes", encodedSize))
ok("the worst announcement fits the cap", encodedSize < NotificationConfig.MaxPayloadBytes)

-- The topic must be a legal MessagingService topic name (80 chars, non-empty).
ok("the topic is named", #NotificationConfig.Topic > 0)
ok("...and within Roblox's 80-character limit", #NotificationConfig.Topic <= 80)

--------------------------------------------------------- announce coupling
section("What actually gets announced")

--[[
	RarityConfig decides how loud a hatch is. AnnounceKind must name a real
	severity - a typo there is a Titan hatch that renders as a toast - and
	CrossServer must only be set on tiers loud enough to deserve it.
]]
local crossServerTiers = {}
for _, rarityId in ipairs(RarityConfig.Order) do
	local tier = RarityConfig.Tiers[rarityId]
	if tier.AnnounceKind then
		--[[
			"local" is not a severity: it means "tell this player only", which
			the hatch reveal already does. Everything else must resolve to a
			real one.
		]]
		if tier.AnnounceKind ~= "local" then
			ok("announce kind is a real severity: " .. rarityId,
				NotificationConfig.Get(tier.AnnounceKind) ~= nil)
		end
	end
	if tier.CrossServer then
		table.insert(crossServerTiers, rarityId)
		ok("cross-server tiers are announced at all: " .. rarityId, tier.AnnounceKind ~= nil)
		eq("...as a takeover: " .. rarityId, tier.AnnounceKind, "takeover")
	end
end

print("  cross-server: " .. table.concat(crossServerTiers, ", "))
eq("two tiers cross servers", #crossServerTiers, 2)

--[[
	And the budget has to survive them. Secret is 1 in 5.26M in Zone 1 and 1 in
	80k in Zone 4; a full server hatching constantly still cannot approach
	20 announcements a minute, which is what makes the budget a safety net
	rather than a limit anyone meets.
]]
local worstOdds = 80000
local hatchesPerMinutePerServer = 30 * 4 -- 30 players, an egg every 15 seconds
local expectedAnnouncesPerMinute = hatchesPerMinutePerServer / worstOdds
print(string.format("  a full server hatching flat out announces %.4f/min against a budget of %d",
	expectedAnnouncesPerMinute, NotificationConfig.PublishBudget))
ok("the budget is nowhere near binding in normal play",
	expectedAnnouncesPerMinute < NotificationConfig.PublishBudget * 0.01)
print(string.format("  headroom: %.0fx what a full server can generate",
	NotificationConfig.PublishBudget / expectedAnnouncesPerMinute))

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
