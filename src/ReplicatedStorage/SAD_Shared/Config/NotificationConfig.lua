--!nonstrict
--[[
	NotificationConfig
	ReplicatedStorage/SAD_Shared/Config/NotificationConfig  (ModuleScript)

	The four severities from docs/08 §5, their durations, and the queueing
	rules. Shared because the server decides which severity a thing is and the
	client decides how long it stays - and those two have to be the same table
	or a five-second banner ends after three.

	═══ SEVERITY IS A SERVER DECISION ══════════════════════════════════════════
	The client never promotes a toast to a takeover. Every entry in the queue
	originates from a server event (docs/08 §5), and the severity travels with
	it. What the client owns is the QUEUE: how many can be on screen, what
	happens when a fifth takeover arrives, and what a player has muted.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local NotificationConfig = {}

--[[
	docs/08 §5, in order of weight. `Priority` decides what wins when two
	arrive together; `Concurrent` is how many may be visible at once.

	`Mutable` marks the severities a player is allowed to turn off in Settings.
	Alerts are not mutable: docs/08 §5 says "a player's own park alerts cannot
	be muted", and a raid you cannot see is a raid you cannot answer.
]]
NotificationConfig.Severities = {
	toast = {
		Id = "toast", Priority = 1, Duration = 3, Concurrent = 3, QueueLimit = 8,
		Sound = "toast", Mutable = true,
		Blurb = "Small, top-right, slides in",
	},
	banner = {
		Id = "banner", Priority = 2, Duration = 5, Concurrent = 1, QueueLimit = 4,
		Sound = "banner", Mutable = true,
		Blurb = "Full-width, top, colour-coded, with SFX",
	},
	takeover = {
		Id = "takeover", Priority = 3, Duration = 4, Concurrent = 1, QueueLimit = 3,
		Sound = "takeover", Mutable = false,
		Blurb = "Centre-screen, dims the world, camera flourish",
	},
	alert = {
		Id = "alert", Priority = 4, Duration = 0, Concurrent = 1, QueueLimit = 1,
		Sound = "alert", Mutable = false,
		Blurb = "Red pulsing bar, until resolved",
	},
}

NotificationConfig.Order = { "toast", "banner", "takeover", "alert" }

--- The severity used when a caller sends something unrecognised. Deliberately
--- the quietest: a mistake should never be the thing that dims the screen.
NotificationConfig.Fallback = "toast"

--[[
	A duration of 0 means "until resolved" - the alert bar stays up until
	something clears it. Named so nobody reads a 0 as "do not show it".
]]
NotificationConfig.UntilResolved = 0

-- ── Cross-server ────────────────────────────────────────────────────────────

--- MessagingService topic. One topic, with a Kind inside, because subscribing
--- costs quota per topic and V1 has one kind of announcement to make.
NotificationConfig.Topic = "SAD_Announce"

--[[
	docs/09 §7.7 fixes this at 6 messages/min, and that is deliberately far
	under Roblox's own floor of roughly 150/min for an empty server (the real
	limit is 150 + 60 x players).

	The headroom is not caution for its own sake - it is measured. Only Secret
	and Titan hatches cross servers, and at 1 in 80,000 in the hardest V1 zone
	a full server hatching flat out produces about 0.0015 announcements per
	minute. Six is four thousand times what the game can generate.

	Exceeding the real limit does not throw usefully; it throttles, and the
	message is simply lost. So the bucket is here, refusing locally, where the
	refusal can be logged and counted.
]]
NotificationConfig.PublishBudget = 6 -- messages
NotificationConfig.PublishWindow = 60 -- seconds

--[[
	MessagingService caps a message at 1 KB. Strings are truncated to this
	before publishing so a long display name cannot silently drop an
	announcement that everything else about the game says will arrive.
]]
NotificationConfig.MaxStringLength = 120
NotificationConfig.MaxPayloadBytes = 800 -- docs/09 §7.7; under 1 KB with envelope room

-- ── Helpers ─────────────────────────────────────────────────────────────────

function NotificationConfig.Get(kind: string)
	return NotificationConfig.Severities[kind]
end

--- The severity a payload should actually be rendered at. Unknown kinds fall
--- back rather than being dropped: a notification nobody sees is worse than
--- one shown too quietly.
function NotificationConfig.Resolve(kind: string?): string
	if kind and NotificationConfig.Severities[kind] then
		return kind
	end
	return NotificationConfig.Fallback
end

function NotificationConfig.DurationOf(kind: string, override: number?): number
	local severity = NotificationConfig.Severities[NotificationConfig.Resolve(kind)]
	if override and override > 0 then
		return override
	end
	return severity.Duration
end

--- Whether `a` should displace `b` on screen. Ties keep what is already there:
--- a notification that is swapped mid-read may as well not have been sent.
function NotificationConfig.Outranks(a: string, b: string): boolean
	local left = NotificationConfig.Severities[NotificationConfig.Resolve(a)]
	local right = NotificationConfig.Severities[NotificationConfig.Resolve(b)]
	return left.Priority > right.Priority
end

--[[
	Trims every string in a payload and refuses anything that is not a plain
	scalar. Used on BOTH sides: the server before publishing across servers,
	the client before rendering what arrived.

	This is also docs/09 §7.7's "allow-list of message kinds": `Kind` is forced
	through `Resolve`, so an unrecognised one becomes a toast rather than
	reaching a renderer that has no case for it.

	docs/13 names "unvalidated inbound payloads" as this step's hazard. The
	messages come from our own servers, but a malformed one still has to fail
	as a dropped notification rather than as a broken queue.
]]
function NotificationConfig.Sanitise(payload: any): any?
	if type(payload) ~= "table" then
		return nil
	end

	local clean = {}
	for key, value in payload do
		if type(key) ~= "string" or #key > 32 then
			continue
		end

		local valueType = type(value)
		if valueType == "string" then
			clean[key] = string.sub(value, 1, NotificationConfig.MaxStringLength)
		elseif valueType == "number" then
			-- NaN and infinity both survive JSON badly and render worse.
			if value == value and value ~= math.huge and value ~= -math.huge then
				clean[key] = value
			end
		elseif valueType == "boolean" then
			clean[key] = value
		end
		-- Tables and functions are dropped: a notification is a flat message.
	end

	if next(clean) == nil then
		return nil
	end

	clean.Kind = NotificationConfig.Resolve(clean.Kind)
	return clean
end

return NotificationConfig
