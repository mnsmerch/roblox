--!nonstrict
--[[
	WeatherController
	.../SAD_Client/Controllers/WeatherController  (ModuleScript)

	The sky. Everything weather does that only changes how the world looks.

	═══ WHY THIS IS ON THE CLIENT ══════════════════════════════════════════════
	docs/13 §Step 17 asks for it - "the effects are server truth, only the
	visuals are local" - and names "Lighting changes not reverting" as this
	step's hazard.

	Both point the same way. Lighting driven from the server and left wrong is
	wrong for every player until the server restarts; the same mistake made
	here corrects itself the moment anyone rejoins. It also lets the
	LowGraphics setting suppress fog for the player who asked for that, which a
	server-wide Lighting change cannot do.

	Nothing here decides anything. The weather id arrives from the server and
	this draws it.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: StateController, HUDController, SoundController,
	            WeatherConfig, Net, Format.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local WeatherConfig = require(Shared.Config.WeatherConfig)

local WeatherController = {}

local StateController, HUDController, SoundController

local current = "clear"
local endsAt = 0

--[[
	Lighting as it was at boot. Captured once, before anything is touched, and
	restored whenever the weather is Clear.

	Captured rather than hardcoded so that whatever the place is configured
	with is what Clear looks like - a hardcoded "default" is a second source of
	truth that silently overwrites the artist's settings the first time it
	rains.
]]
local baseline = nil

--[[
	The per-weather look. Only properties that appear here are ever written, so
	restoring is "put these back", not "guess what Clear was".
]]
local LOOKS = {
	clear = {},
	rainstorm = {
		Ambient = Color3.fromRGB(70, 78, 90),
		OutdoorAmbient = Color3.fromRGB(95, 105, 120),
		Brightness = 1.4,
		FogEnd = 900,
		FogColor = Color3.fromRGB(120, 130, 145),
	},
	thunderstorm = {
		Ambient = Color3.fromRGB(55, 55, 80),
		OutdoorAmbient = Color3.fromRGB(75, 75, 105),
		Brightness = 1.1,
		FogEnd = 700,
		FogColor = Color3.fromRGB(95, 95, 125),
	},
	blizzard = {
		Ambient = Color3.fromRGB(140, 155, 170),
		OutdoorAmbient = Color3.fromRGB(190, 205, 220),
		Brightness = 2.2,
		-- The number that actually matters, and the one WeatherConfig owns:
		-- fog is the blizzard's mechanic, not just its colour.
		FogColor = Color3.fromRGB(225, 238, 250),
	},
}

local TRANSITION = 3

-- ── Lighting ────────────────────────────────────────────────────────────────

local function capture()
	baseline = {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		FogColor = Lighting.FogColor,
	}
end

--[[
	Whether this player has asked for the cheap version. Fog and heavy ambient
	shifts are the expensive, disorienting parts, so LowGraphics keeps the
	colour grade and drops the fog.
]]
local function lowGraphics(): boolean
	local data = StateController.Get()
	return data ~= nil and data.Settings ~= nil and data.Settings.LowGraphics == true
end

local function applyLook(weatherId: string)
	if not baseline then
		return
	end

	local look = LOOKS[weatherId] or {}
	local target = {}

	-- Start from the captured baseline, so anything this weather does not
	-- mention goes back to how the place was authored.
	for key, value in baseline do
		target[key] = value
	end
	for key, value in look do
		target[key] = value
	end

	--[[
		FogEnd is the blizzard's actual mechanic, so it comes from
		WeatherConfig rather than from the look table - the number a designer
		tunes and the number the spec asserts are then the same number.
	]]
	local fogEnd = WeatherConfig.EffectOf(weatherId, "FogEnd", nil)
	if fogEnd then
		target.FogEnd = fogEnd
		target.FogStart = math.max(0, fogEnd * 0.15)
	end

	if lowGraphics() then
		target.FogEnd = baseline.FogEnd
		target.FogStart = baseline.FogStart
	end

	TweenService:Create(Lighting, TweenInfo.new(TRANSITION, Enum.EasingStyle.Sine), target):Play()
end

-- ── Handling ────────────────────────────────────────────────────────────────

function WeatherController.OnWeatherChanged(info)
	if type(info) ~= "table" or type(info.Weather) ~= "string" then
		return
	end

	local entry = WeatherConfig.Get(info.Weather)
	if not entry then
		return
	end

	current = info.Weather
	endsAt = info.EndsAt or 0

	applyLook(current)

	if current == "clear" then
		HUDController.SetEventBanner(nil, HUDController.BannerPriority.Weather)
	else
		HUDController.SetEventBanner(string.upper(entry.DisplayName),
			HUDController.BannerPriority.Weather)
		SoundController.Play("banner")
	end

	Log.debug("WeatherController", "%s until %s", entry.DisplayName, tostring(endsAt))
end

function WeatherController.Current(): string
	return current
end

--- Seconds left, for the HUD. Clamped at zero rather than going negative
--- while the next roll is in flight.
function WeatherController.Remaining(): number
	return math.max(0, endsAt - os.time())
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function WeatherController.Init(app)
	StateController = app.Get("StateController")
	HUDController = app.Get("HUDController")
	SoundController = app.Get("SoundController")
end

function WeatherController.Start(_app)
	-- Before anything is written to Lighting, so Clear is what the place was
	-- authored as rather than what the first weather left behind.
	capture()

	Net.On("WeatherChanged", WeatherController.OnWeatherChanged)

	--[[
		Re-apply when LowGraphics changes, so turning it on during a blizzard
		clears the fog immediately instead of at the next weather.
	]]
	StateController.Observe({ "Settings", "LowGraphics" }, function()
		applyLook(current)
	end)

	--[[
		The banner counts down. 1 Hz: it is a minutes-scale readout and a
		per-frame update would be the same text sixty times a second.
	]]
	task.spawn(function()
		while true do
			task.wait(1)
			if current ~= "clear" then
				local entry = WeatherConfig.Get(current)
				HUDController.SetEventBanner(string.format("%s  ·  %s",
					string.upper(entry.DisplayName), Format.Time(WeatherController.Remaining())),
					HUDController.BannerPriority.Weather)
			end
		end
	end)

	Log.info("WeatherController", "Ready. Lighting is local; %d looks", #WeatherConfig.Order)
end

return WeatherController
