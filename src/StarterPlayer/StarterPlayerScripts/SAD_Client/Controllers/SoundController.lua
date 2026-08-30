--!nonstrict
--[[
	SoundController
	.../SAD_Client/Controllers/SoundController  (ModuleScript)

	Every sound the game plays, and the anti-annoyance rules from docs/15 §3
	that stop it from being the reason someone turns the volume off.

	═══ NO ASSET IDS ARE INVENTED HERE ═════════════════════════════════════════
	The sound table below names slots and describes what each one is; it does
	not contain `rbxassetid://` numbers, because there are no assets yet and a
	made-up id is a silent 404 that looks like working code.

	Instead each slot is looked up by NAME in `SAD_Assets/Sounds`. Drop a Sound
	instance called `Hatch` in there and hatching has a sound; until then the
	call is a no-op. That is the same stance AssetBuilder takes for models -
	the game runs complete and silent, and the audio pass is a folder of files
	rather than a code change.
	═══════════════════════════════════════════════════════════════════════════

	docs/15 §3's anti-annoyance rules, each implemented once:
	  * every repeating SFX has a per-player cooldown;
	  * server announcements duck to -12 dB if three fire within 10 seconds;
	  * every category respects its settings slider.

	API:
		SoundController.Play(slot, opts?)          -- opts: Volume, Pitch, Duck
		SoundController.PlayNotification(kind)
		SoundController.SetCategoryVolume(category, volume)
		SoundController.IsAvailable(slot) -> boolean

	Depends on: StateController, GameConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local NotificationConfig = require(Shared.Config.NotificationConfig)

local SoundController = {}

local StateController

--[[
	The slot table. `Category` decides which volume slider applies, `Cooldown`
	is the per-player minimum gap from docs/15 §3, and `Blurb` is the brief for
	whoever makes the file.
]]
SoundController.Slots = {
	-- Notifications, one per severity (NotificationConfig.Severities.Sound).
	toast = { Category = "ui", Cooldown = 0.15, Blurb = "Soft tick" },
	banner = { Category = "ui", Cooldown = 0.4, Blurb = "Short brass swell" },
	takeover = { Category = "announce", Cooldown = 1.0,
		Blurb = "Sub-bass hit + horn, ducks other audio 1.5s (docs/15 §3)" },
	alert = { Category = "announce", Cooldown = 2.0,
		Blurb = "Urgent klaxon, distinct from every other sound in the game" },

	-- The loop.
	EggPickup = { Category = "sfx", Cooldown = 0.1, Blurb = "Shluck + 3-note chime, pitched by rarity" },
	Safe = { Category = "sfx", Cooldown = 0.5, Blurb = "Bright bell + crowd cheer" },
	Caught = { Category = "sfx", Cooldown = 0.5, Blurb = "Comedic bonk + slide whistle. Never a failure sound" },
	EggCrack = { Category = "sfx", Cooldown = 0.2, Blurb = "Three escalating cracks then a burst" },
	Hatch = { Category = "sfx", Cooldown = 0.3, Blurb = "Rarity sting + species roar" },
	Mutation = { Category = "sfx", Cooldown = 0.3, Blurb = "Reverse-cymbal into a per-mutation motif" },
	Collect = { Category = "sfx", Cooldown = 0.08, Blurb = "Coin cascade, pitch rising, capped at 8 chimes" },
	Upgrade = { Category = "ui", Cooldown = 0.2, Blurb = "Mechanical ka-chunk" },
	Rebirth = { Category = "announce", Cooldown = 2.0, Blurb = "Long amber swell" },
	Teleport = { Category = "sfx", Cooldown = 0.3, Blurb = "Short whoosh into a settle" },
}

SoundController.Categories = { "sfx", "ui", "announce", "music", "ambience" }

--[[
	docs/15 §3: "server announcements duck to -12 dB if three fire within 10
	seconds". Expressed as a volume multiplier, because Roblox's Sound.Volume
	is linear rather than in decibels: -12 dB is 10^(-12/20).
]]
local DUCK_VOLUME = 10 ^ (-12 / 20)
local DUCK_THRESHOLD = 3
local DUCK_WINDOW = 10

local lastPlayedAt: { [string]: number } = {}
local announceTimes: { number } = {}
local categoryVolume: { [string]: number } = {}
local soundFolder: Folder? = nil

-- ── Volume ──────────────────────────────────────────────────────────────────

function SoundController.SetCategoryVolume(category: string, volume: number)
	categoryVolume[category] = math.clamp(volume, 0, 1)
end

local function volumeFor(category: string): number
	local base = categoryVolume[category]
	if base ~= nil then
		return base
	end

	--[[
		Settings own the sliders. Read live rather than cached, so a player
		dragging Music to zero hears it stop rather than hearing it stop next
		time something plays.
	]]
	local data = StateController and StateController.Get()
	local settings = data and data.Settings
	if settings then
		if category == "music" and settings.MusicVolume then
			return settings.MusicVolume / 100
		end
		if settings.SfxVolume then
			return settings.SfxVolume / 100
		end
	end
	return 1
end

--[[
	Whether the announcement channel should duck right now: three or more
	announcements inside ten seconds.
]]
local function announceDucking(now: number): boolean
	local cutoff = now - DUCK_WINDOW
	local kept = {}
	for _, stamp in announceTimes do
		if stamp > cutoff then
			table.insert(kept, stamp)
		end
	end
	announceTimes = kept
	return #kept >= DUCK_THRESHOLD
end

-- ── Playing ─────────────────────────────────────────────────────────────────

function SoundController.IsAvailable(slot: string): boolean
	return soundFolder ~= nil and soundFolder:FindFirstChild(slot) ~= nil
end

--[[
	Plays a slot, if an asset for it exists.

	Returns whether anything was played, which is what makes "no assets yet"
	testable rather than invisible.
]]
function SoundController.Play(slot: string, opts): boolean
	local definition = SoundController.Slots[slot]
	if not definition then
		Log.warn("SoundController", "Unknown sound slot '%s'", tostring(slot))
		return false
	end

	local now = os.clock()

	-- docs/15 §3: every repeating SFX has a per-player cooldown.
	if now - (lastPlayedAt[slot] or -math.huge) < definition.Cooldown then
		return false
	end

	local template = soundFolder and soundFolder:FindFirstChild(slot)
	if not template or not template:IsA("Sound") then
		-- No asset for this slot yet. Deliberately silent and deliberately not
		-- a warning: a game with no audio files would log on every action.
		return false
	end

	lastPlayedAt[slot] = now

	local volume = volumeFor(definition.Category)
	if definition.Category == "announce" then
		table.insert(announceTimes, now)
		if announceDucking(now) then
			volume *= DUCK_VOLUME
		end
	end
	if opts and opts.Volume then
		volume *= opts.Volume
	end

	local sound = template:Clone()
	sound.Volume = template.Volume * volume
	if opts and opts.Pitch then
		sound.PlaybackSpeed = opts.Pitch
	end
	sound.Parent = SoundService
	sound:Play()

	--[[
		Cloned per play so overlapping sounds do not cut each other off, and
		destroyed on Ended so the clones do not accumulate. A sound that never
		ends - a loop - would leak, so those are handled by the caller holding
		the instance rather than through here.
	]]
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(30, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)

	return true
end

--- One line for the notification queue, so severities and sounds stay paired.
function SoundController.PlayNotification(kind: string): boolean
	local severity = NotificationConfig.Get(kind)
	return SoundController.Play(severity and severity.Sound or "toast")
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function SoundController.Init(app)
	StateController = app.Get("StateController")
end

function SoundController.Start(_app)
	-- SAD_Assets lives under SAD_Shared, not directly under ReplicatedStorage.
	local assets = Shared:FindFirstChild("SAD_Assets")
	soundFolder = assets and assets:FindFirstChild("Sounds")

	local available = 0
	local total = 0
	for slot in SoundController.Slots do
		total += 1
		if SoundController.IsAvailable(slot) then
			available += 1
		end
	end

	if available == 0 then
		Log.info("SoundController",
			"Ready, silent. Drop Sound instances named after the %d slots into "
				.. "SAD_Shared/SAD_Assets/Sounds to give them audio", total)
	else
		Log.info("SoundController", "Ready. %d of %d slots have audio", available, total)
	end
end

return SoundController
