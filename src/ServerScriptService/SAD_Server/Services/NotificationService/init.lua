--!nonstrict
--[[
	NotificationService
	ServerScriptService/SAD_Server/Services/NotificationService  (ModuleScript)

	The one place a notification is created. Twelve call sites across six
	services were each building their own `Notify` payload by hand; from here
	they say what happened and this decides how loudly it is said.

	═══ THE SERVER PICKS THE SEVERITY ══════════════════════════════════════════
	docs/08 §5: "the notification queue is client-side but every entry
	originates from a server event." The client owns how many fit on screen and
	what a player has muted. It never promotes a toast into a takeover, and it
	is never asked to decide what something was worth.
	═══════════════════════════════════════════════════════════════════════════

	API:
		NotificationService.Toast(player, title, subtitle?, opts?)
		NotificationService.Banner(player, text, opts?)
		NotificationService.Takeover(player, info)      -- Title/Subtitle/Headline
		NotificationService.Alert(player, text, opts?)
		NotificationService.Clear(player, tag)
		NotificationService.Send(player, payload)       -- the raw form
		NotificationService.All(payload, exclude?)      -- this server
		NotificationService.Announce(payload)           -- every server

	`opts` accepts Duration, Color, Tag and Sound. Everything else is dropped
	by NotificationConfig.Sanitise before it leaves.

	Depends on: NotificationConfig, Net, Log. BroadcastService is resolved at
	Start, so this service works with cross-server messaging switched off.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local NotificationConfig = require(Shared.Config.NotificationConfig)

local NotificationService = {}

local BroadcastService

--- Counted rather than logged one by one: a flood is interesting, an
--- individual toast is not.
local sent = { toast = 0, banner = 0, takeover = 0, alert = 0 }

-- ── Sending ─────────────────────────────────────────────────────────────────

--[[
	The raw form. Everything else is a shape on top of this.

	Sanitised on the way out even though this side is trusted, so that the
	payload a client receives has the same guarantees whether it came from
	here or across MessagingService - one validation, not two that drift.
]]
function NotificationService.Send(player: Player, payload)
	local clean = NotificationConfig.Sanitise(payload)
	if not clean then
		return
	end

	clean.Duration = NotificationConfig.DurationOf(clean.Kind, payload.Duration)
	sent[clean.Kind] = (sent[clean.Kind] or 0) + 1

	Net.FireClient("Notify", player, clean)
end

--- Everyone on this server. `exclude` skips one player - usually the person
--- the announcement is about, who is getting a better version of it.
function NotificationService.All(payload, exclude: Player?)
	local clean = NotificationConfig.Sanitise(payload)
	if not clean then
		return
	end

	clean.Duration = NotificationConfig.DurationOf(clean.Kind, payload.Duration)
	sent[clean.Kind] = (sent[clean.Kind] or 0) + 1

	if exclude then
		Net.FireAllExcept("Notify", exclude, clean)
	else
		Net.FireAllClients("Notify", clean)
	end
end

--[[
	Every server, this one included.

	Published first and rendered locally from the same payload, so the players
	standing next to the person who hatched it see exactly what a player on
	another server sees. If BroadcastService is unavailable or throttled the
	local half still happens - a Titan hatch that only half the game hears
	about is far better than one nobody does.
]]
function NotificationService.Announce(payload)
	NotificationService.All(payload)

	if BroadcastService then
		BroadcastService.Publish(payload)
	end
end

-- ── Shapes ──────────────────────────────────────────────────────────────────

local function withOpts(payload, opts)
	if type(opts) == "table" then
		payload.Duration = opts.Duration
		payload.Color = opts.Color
		payload.Tag = opts.Tag
		payload.Sound = opts.Sound
	end
	return payload
end

function NotificationService.Toast(player: Player, title: string, subtitle: string?, opts)
	NotificationService.Send(player, withOpts({
		Kind = "toast", Title = title, Subtitle = subtitle,
	}, opts))
end

function NotificationService.Banner(player: Player, text: string, opts)
	NotificationService.Send(player, withOpts({ Kind = "banner", Text = text }, opts))
end

--- The three-line centre panel: what it is, what it means, the big number.
function NotificationService.Takeover(player: Player, info)
	NotificationService.Send(player, withOpts({
		Kind = "takeover",
		Title = info.Title, Subtitle = info.Subtitle, Headline = info.Headline,
	}, info))
end

--[[
	Stays up until something clears it, which is what makes it an alert rather
	than a loud banner. `Tag` is how it is cleared later, so an alert without
	one would be permanent - defaulted rather than left to each caller.
]]
function NotificationService.Alert(player: Player, text: string, opts)
	local payload = withOpts({ Kind = "alert", Text = text }, opts)
	payload.Tag = payload.Tag or "alert"
	NotificationService.Send(player, payload)
end

function NotificationService.Clear(player: Player, tag: string)
	Net.FireClient("Notify", player, { Kind = "clear", Tag = tag })
end

function NotificationService.GetCounts()
	return table.clone(sent)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function NotificationService.Init(_app) end

function NotificationService.Start(app)
	BroadcastService = app.Get("BroadcastService")

	--[[
		Inbound announcements from other servers. They arrive already
		sanitised by BroadcastService; re-sanitising here would be the same
		call twice, so this only decides that a remote announcement is shown
		to everyone locally and to nobody twice.
	]]
	if BroadcastService then
		BroadcastService.Received:Connect(function(payload)
			NotificationService.All(payload)
		end)
	end

	Log.info("NotificationService", "Ready. %d severities, cross-server %s",
		#NotificationConfig.Order, if BroadcastService then "on" else "off")
end

return NotificationService
