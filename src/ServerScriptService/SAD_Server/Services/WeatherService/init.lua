--!nonstrict
--[[
	WeatherService
	ServerScriptService/SAD_Server/Services/WeatherService  (ModuleScript)

	One weather is always active, it is the same for everyone, and the server
	decides it (docs/04 §2).

	═══ EFFECTS ARE SERVER TRUTH; VISUALS ARE LOCAL ════════════════════════════
	docs/13 §Step 17 names this exactly. Everything that changes an outcome -
	mutation weights, walk speed, nest respawn, lightning - happens here. The
	sky, the fog and the particles are applied by WeatherController on each
	client from the replicated weather id.

	That split is not only about trust. Lighting driven from the server and not
	reverted is broken for every player until the server restarts; the same
	mistake made locally corrects itself on rejoin. docs/13 names "Lighting
	changes not reverting" as this step's hazard, and putting Lighting on the
	client is what bounds it.
	═══════════════════════════════════════════════════════════════════════════

	API:
		WeatherService.Current() -> weatherId
		WeatherService.EndsAt() -> os.time()
		WeatherService.Set(weatherId, durationSecs?)   -- admin/test entry point
		WeatherService.Roll() -> weatherId             -- picks the next one
		WeatherService.EffectOf(key, default) -> value
		WeatherService.Changed  Signal(weatherId, endsAt)

	Depends on: WeatherConfig, MutationConfig, RNG, Net, NotificationService,
	            MutationService, EggService, PlayerDataService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local RNG = require(Shared.Modules.RNG)
local Signal = require(Shared.Modules.Signal)
local WeatherConfig = require(Shared.Config.WeatherConfig)

local WeatherService = {}

WeatherService.Changed = Signal.new()

local MutationService, EggService, NotificationService

local current = "clear"
local endsAt = 0
local lastExoticEndedAt = -math.huge

local rng = Random.new()

--- The speed modifier key. Named once so setting and clearing cannot drift.
local SPEED_KEY = "weather"

-- ── State ───────────────────────────────────────────────────────────────────

function WeatherService.Current(): string
	return current
end

function WeatherService.EndsAt(): number
	return endsAt
end

function WeatherService.EffectOf(key: string, default: any): any
	return WeatherConfig.EffectOf(current, key, default)
end

-- ── Effects ─────────────────────────────────────────────────────────────────

--[[
	Applies the ground-speed effect to one player.

	Routed through EggService's modifier stack rather than setting WalkSpeed,
	so a player who is rain-slowed AND carrying a Titan egg is slowed by both -
	and so SecurityService still measures them against the speed the server
	actually intended (docs/03 §6).
]]
local function applySpeed(player: Player)
	local multiplier = WeatherService.EffectOf("GroundSpeedMult", 1)
	if multiplier >= 1 then
		EggService.ClearSpeedModifier(player, SPEED_KEY)
	else
		EggService.SetSpeedModifier(player, SPEED_KEY, multiplier)
	end
end

local function applySpeedToAll()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(applySpeed, player)
		if not ok then
			Log.error("WeatherService", "Speed apply failed for %s: %s", player.Name, tostring(err))
		end
	end
end

--[[
	Thunderstorm: "random lightning knocks eggs loose" (docs/04 §2).

	Only ever affects a player who is CARRYING something - being struck while
	empty-handed would be a punishment with nothing to learn from. The chance
	is per player per interval, so a full server does not multiply into one
	strike a second.
]]
local function tickLightning()
	local chance = WeatherService.EffectOf("LightningChance", 0)
	if chance <= 0 then
		return
	end

	for _, player in Players:GetPlayers() do
		if EggService.GetCarryCount(player) > 0 and rng:NextNumber() < chance then
			EggService.DropAll(player, "lightning")
			NotificationService.Banner(player, "LIGHTNING! YOU DROPPED EVERYTHING",
				{ Duration = 3 })
		end
	end
end

-- ── Rolling ─────────────────────────────────────────────────────────────────

--[[
	Picks the next weather.

	docs/04 §2 forces a Clear gap of at least three minutes after an exotic, so
	an exotic rolled inside that window is turned into Clear rather than
	re-rolled - re-rolling would quietly reshape the weight table by making
	rare weathers likelier to survive the filter.
]]
function WeatherService.Roll(): string
	local now = os.clock()
	local picked = RNG.WeightedPick(WeatherConfig.RollableWeights(), rng) or "clear"

	if picked ~= "clear" and now - lastExoticEndedAt < WeatherConfig.MinClearGapSecs then
		return "clear"
	end

	return picked
end

--[[
	Makes `weatherId` current. The single place weather changes, so every
	consequence is applied in one order every time.
]]
function WeatherService.Set(weatherId: string, durationSecs: number?)
	local entry = WeatherConfig.Get(weatherId)
	if not entry then
		Log.warn("WeatherService", "Unknown weather '%s' - staying on %s", tostring(weatherId), current)
		return
	end

	if current ~= "clear" and entry.Id == "clear" then
		lastExoticEndedAt = os.clock()
	end

	current = entry.Id
	endsAt = os.time() + (durationSecs or WeatherConfig.DurationOf(entry.Id))

	-- MutationService owns the roll; it only needs to be told what is outside.
	MutationService.SetWeather(current)

	applySpeedToAll()

	Net.FireAllClients("WeatherChanged", {
		Weather = current,
		EndsAt = endsAt,
		DisplayName = entry.DisplayName,
		Blurb = entry.Blurb,
	})

	WeatherService.Changed:Fire(current, endsAt)

	Log.info("WeatherService", "%s for %s", entry.DisplayName,
		Format.Time(endsAt - os.time()))
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function WeatherService.Init(app)
	MutationService = app.Get("MutationService")
	EggService = app.Get("EggService")
	NotificationService = app.Get("NotificationService")
end

function WeatherService.Start(_app)
	--[[
		A joining player is told what the weather already is. Without this the
		sky is whatever Lighting shipped with until the next roll, which for
		Clear-heavy weather is most of a session.
	]]
	Players.PlayerAdded:Connect(function(player)
		local entry = WeatherConfig.Get(current)
		Net.FireClient("WeatherChanged", player, {
			Weather = current,
			EndsAt = endsAt,
			DisplayName = entry.DisplayName,
			Blurb = entry.Blurb,
		})
		applySpeed(player)
	end)

	--[[
		The roll loop. One weather is always active, so this sets Clear
		immediately rather than starting with nothing and waiting eight
		minutes for the first roll.
	]]
	WeatherService.Set("clear")

	task.spawn(function()
		while true do
			local remaining = math.max(1, endsAt - os.time())

			--[[
				The 20-second countdown from docs/04 §2. Announced before the
				change, not after - the point of a countdown is that people can
				move before it lands.
			]]
			if remaining > WeatherConfig.CountdownSecs then
				task.wait(remaining - WeatherConfig.CountdownSecs)

				local nextWeather = WeatherService.Roll()
				if nextWeather ~= current then
					local entry = WeatherConfig.Get(nextWeather)
					NotificationService.All({
						Kind = "banner",
						Text = string.format("%s IN %ds", string.upper(entry.DisplayName),
							WeatherConfig.CountdownSecs),
						Duration = 4,
					})
				end

				task.wait(WeatherConfig.CountdownSecs)
				WeatherService.Set(nextWeather)
			else
				task.wait(remaining)
				WeatherService.Set(WeatherService.Roll())
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(WeatherConfig.EffectOf(current, "LightningInterval", 12))
			local ok, err = pcall(tickLightning)
			if not ok then
				Log.error("WeatherService", "Lightning tick failed: %s", tostring(err))
			end
		end
	end)

	Log.info("WeatherService", "Ready. %d weathers, rolling every %s, Clear %.0f%% of the time",
		WeatherConfig.Count(), Format.Time(WeatherConfig.RollInterval),
		WeatherConfig.ClearShare() * 100)
end

return WeatherService
