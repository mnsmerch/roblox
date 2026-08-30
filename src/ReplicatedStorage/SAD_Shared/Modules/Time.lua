--!nonstrict
--[[
	Time
	ReplicatedStorage/SAD_Shared/Modules/Time  (ModuleScript)

	When does "today" end.

	═══ EVERYTHING HERE IS UTC ═════════════════════════════════════════════════
	docs/13 §Step 19 names timezone handling as this step's hazard, and the
	failure it produces is specific: a player in Auckland and a player in Los
	Angeles disagreeing about whether their streak survived. There is exactly
	one day boundary in this game and it is 00:00 UTC.

	`os.time()` is already UTC seconds since the epoch on every Roblox server,
	so the whole of this module is integer division. No `os.date`, no locale,
	no daylight saving - none of which would be the same on two machines.
	═══════════════════════════════════════════════════════════════════════════

	Shared, because the client draws the countdown to the next chest and the
	server decides whether it may be claimed. Two implementations of "which day
	is it" is a UI that says READY over a button that refuses.

	Depends on: nothing.
]]

local Time = {}

Time.SecondsPerDay = 86400
Time.SecondsPerWeek = 604800

--[[
	The Unix epoch, 1970-01-01, was a THURSDAY. Weekly resets land on Monday
	(docs/05 §7), so the index is shifted by three days to move the boundary
	off Thursday and onto Monday 1970-01-05 00:00 UTC, which is second 345600.

	345600 + 259200 = 604800 = exactly one week, so that Monday is a boundary
	and so is every Monday after it. The spec checks real dates rather than
	trusting the arithmetic.
]]
Time.MondayOffset = 259200

--- Which UTC day `now` falls in. Days are contiguous integers, so "is this a
--- new day" is `DayIndex(now) > stored`, never a date comparison.
function Time.DayIndex(now: number): number
	return math.floor(now / Time.SecondsPerDay)
end

--- Which Monday-aligned UTC week `now` falls in.
function Time.WeekIndex(now: number): number
	return math.floor((now + Time.MondayOffset) / Time.SecondsPerWeek)
end

--- Seconds until the next UTC midnight. What the daily chest counts down.
function Time.SecondsUntilNextDay(now: number): number
	return Time.SecondsPerDay - (now % Time.SecondsPerDay)
end

--- Seconds until the next Monday 00:00 UTC.
function Time.SecondsUntilNextWeek(now: number): number
	return Time.SecondsPerWeek - ((now + Time.MondayOffset) % Time.SecondsPerWeek)
end

--[[
	Whether a streak survives.

	Claiming on consecutive days continues it; skipping a day breaks it;
	claiming twice in one day is neither. Returns "continue", "break" or
	"same" so the caller never has to re-derive the comparison - the three
	cases are the whole of the rule and each one is named.
]]
function Time.StreakState(lastClaimDay: number, today: number): string
	if lastClaimDay <= 0 then
		return "continue" -- a first claim is a streak of one
	end
	if today == lastClaimDay then
		return "same"
	end
	if today == lastClaimDay + 1 then
		return "continue"
	end
	return "break"
end

return Time
