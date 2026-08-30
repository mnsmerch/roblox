--!nonstrict
--[[
	DailyService
	ServerScriptService/SAD_Server/Services/DailyService  (ModuleScript)

	The 7-day chest and the streak behind it (docs/05 §7).

	═══ THREE OUTCOMES, NAMED ══════════════════════════════════════════════════
	Claiming is not "did a day pass". It is three cases, and conflating any two
	of them is how streaks get lost:

	  * SAME day  - already claimed, refuse. Not a break.
	  * NEXT day  - the streak continues and the cycle advances.
	  * ANY LATER day - the streak breaks and the cycle restarts at day 1.

	`Time.StreakState` returns exactly those three, so this file never compares
	timestamps and never subtracts dates.
	═══════════════════════════════════════════════════════════════════════════

	The cycle resets on a missed day; the STREAK RECORD does not (docs/05 §7),
	which is why BestStreak is separate and never decreases.

	API:
		DailyService.Available(data, now?) -> ok, reason?
		DailyService.NextDayIndex(data, now?) -> 1..7
		DailyService.Claim(player) -> ok, reason?
		DailyService.Claimed  Signal(player, dayIndex, streak, summary)

	Depends on: DailyConfig, Time, PlayerDataService, NotificationService,
	            RewardGrant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DailyConfig = require(Shared.Config.DailyConfig)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local Time = require(Shared.Modules.Time)

local DailyService = {}

DailyService.Claimed = Signal.new()

local PlayerDataService, NotificationService, RewardGrant

-- ── State ───────────────────────────────────────────────────────────────────

function DailyService.Available(data, now: number?): (boolean, string?)
	local today = Time.DayIndex(now or os.time())
	local state = Time.StreakState(data.Daily.LastClaimDay or 0, today)
	if state == "same" then
		return false, "come back tomorrow"
	end
	return true
end

--[[
	Which position in the 7-day cycle the next claim pays out.

	Derived rather than stored so it can never disagree with the streak: a
	broken streak restarts at day 1 because the cycle position is a function of
	the streak, not a second counter kept alongside it.
]]
function DailyService.NextDayIndex(data, now: number?): number
	local today = Time.DayIndex(now or os.time())
	local state = Time.StreakState(data.Daily.LastClaimDay or 0, today)

	if state == "break" then
		return 1
	end
	if state == "same" then
		return math.max(1, data.Daily.DayIndex or 1)
	end
	return (data.Daily.DayIndex or 0) + 1
end

-- ── Claiming ────────────────────────────────────────────────────────────────

function DailyService.Claim(player: Player, now: number?): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local at = now or os.time()
	local today = Time.DayIndex(at)

	local available, reason = DailyService.Available(data, at)
	if not available then
		return false, reason
	end

	local state = Time.StreakState(data.Daily.LastClaimDay or 0, today)
	local dayIndex = DailyService.NextDayIndex(data, at)
	local streak = if state == "break" then 1 else (data.Daily.Streak or 0) + 1

	--[[
		The claim is RECORDED before anything is granted. docs/13 names
		double-claim as this step's hazard, and this ordering is the defence:
		two calls racing both see the same LastClaimDay, but the second finds
		"same" the moment the first write lands.
	]]
	PlayerDataService.UpdateKeys(player, { "Daily" }, function(profile)
		profile.Daily.LastClaimDay = today
		profile.Daily.DayIndex = dayIndex
		profile.Daily.Streak = streak
		profile.Daily.BestStreak = math.max(profile.Daily.BestStreak or 0, streak)
	end, "daily claim")

	local reward = DailyConfig.RewardFor(dayIndex)
	local summary = if reward then RewardGrant.Give(player, reward, "daily day " .. dayIndex) else ""

	--[[
		Streak milestones are separate from the chest and survive a broken
		cycle, because the streak is what they reward. Granted on the exact day
		they are crossed - a player who reaches 30 gets it once, and reaching
		30 again after a break is a genuinely new 30.
	]]
	local milestone = DailyConfig.StreakRewardAt(streak)
	if milestone then
		local extra = RewardGrant.Give(player, milestone, "streak " .. streak)
		summary = summary .. "  ·  " .. extra
	end

	NotificationService.Takeover(player, {
		Title = string.format("DAY %d", dayIndex),
		Subtitle = summary,
		Headline = string.format("%d DAY STREAK", streak),
		Duration = 5,
	})

	DailyService.Claimed:Fire(player, dayIndex, streak, summary)
	Log.info("DailyService", "%s claimed day %d, streak %d", player.Name, dayIndex, streak)
	return true
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function DailyService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	NotificationService = app.Get("NotificationService")
	-- QuestService owns it and exposes it; see its header.
	RewardGrant = app.Get("QuestService").RewardGrant
end

function DailyService.Start(_app)
	Net.OnEvent("RequestClaimDaily", function(player)
		local ok, reason = DailyService.Claim(player)
		if not ok and reason then
			NotificationService.Toast(player, "DAILY", reason)
		end
	end)

	--[[
		A player with a chest waiting is told once, a few seconds after joining
		- late enough not to collide with the offline-earnings panel, early
		enough that they have not walked away.
	]]
	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		task.delay(8, function()
			if not player.Parent then
				return
			end
			local current = PlayerDataService.Get(player)
			if current and DailyService.Available(current) then
				NotificationService.Toast(player, "DAILY CHEST",
					string.format("Day %d is waiting", DailyService.NextDayIndex(current)))
			end
		end)
	end)

	Log.info("DailyService", "Ready. %d-day cycle, %d streak milestone(s)",
		DailyConfig.CycleLength, #DailyConfig.StreakRewards)
end

return DailyService
