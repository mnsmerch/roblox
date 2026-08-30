--!nonstrict
--[[
	IndexService
	ServerScriptService/SAD_Server/Services/IndexService  (ModuleScript)

	The Dinosaur Index: what you have found, and what finding it is worth.

	DinosaurService already writes the Index entry when a dinosaur is created
	(Step 11) - count, best star, mutations seen. This service owns what that
	means: whether it was a first discovery, which milestones it crossed, and
	the completion percentage the HUD shows.

	═══ THE DENOMINATOR IS WHAT EXISTS ═════════════════════════════════════════
	docs/06 §4 defines completion as "discovered / 60". Sixty is the finished
	game; V1 ships 35. IndexConfig counts DinoConfig rather than hardcoding a
	number, so a V1 player who has found everything reads 100 % - and the
	milestones above 35 are simply unreachable until the species ship.

	Unreachable is the right failure. A hardcoded 60 would show 58 % to a
	player who has found every dinosaur in the game, which is not pending, it
	is wrong.
	═══════════════════════════════════════════════════════════════════════════

	API:
		IndexService.Completion(data) -> percent
		IndexService.CheckMilestones(player) -> granted
		IndexService.SpeciesDiscovered  Signal(player, speciesId, entry)

	Depends on: IndexConfig, DinoConfig, PlayerDataService, DinosaurService,
	            NotificationService, QuestService (for RewardGrant).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local IndexConfig = require(Shared.Config.IndexConfig)
local Log = require(Shared.Modules.Log)

local IndexService = {}

local Signal = require(Shared.Modules.Signal)

IndexService.SpeciesDiscovered = Signal.new()

local PlayerDataService, NotificationService, RewardGrant

function IndexService.Completion(data): number
	return IndexConfig.CompletionPercent(data, DinoConfig)
end

function IndexService.Discovered(data): number
	return IndexConfig.Discovered(data)
end

function IndexService.Total(): number
	return IndexConfig.Total(DinoConfig)
end

--[[
	Grants every milestone and rarity set the player has reached and not been
	paid for.

	Marked claimed BEFORE granting, in the same shape as quests and dailies:
	two calls racing both read the same unclaimed set, and only the first write
	survives to reach the grant.

	Called on discovery AND on load, so a milestone that was crossed while the
	code that grants it did not yet exist is paid the next time they log in.
]]
function IndexService.CheckMilestones(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data or not RewardGrant then
		return 0
	end

	local pending = IndexConfig.PendingMilestones(data)
	for _, set in IndexConfig.PendingSets(data, DinoConfig) do
		table.insert(pending, set)
	end

	if #pending == 0 then
		return 0
	end

	PlayerDataService.UpdateKeys(player, { "IndexMilestones" }, function(profile)
		for _, milestone in pending do
			profile.IndexMilestones[milestone.Id] = true
		end
	end, "index milestone")

	for _, milestone in pending do
		local summary = RewardGrant.Give(player, milestone, "index " .. milestone.Id)
		NotificationService.Takeover(player, {
			Title = "INDEX MILESTONE",
			Subtitle = if milestone.Rarity
				then string.format("Every %s species found", milestone.Rarity)
				else string.format("%d species discovered", milestone.Count),
			Headline = summary,
			Duration = 5,
		})
	end

	Log.info("IndexService", "%s crossed %d milestone(s)", player.Name, #pending)
	return #pending
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function IndexService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	NotificationService = app.Get("NotificationService")
end

function IndexService.Start(app)
	--[[
		Resolved in Start, not Init: QuestService owns RewardGrant and sets it
		up in its own Init, which runs after this service's.
	]]
	RewardGrant = app.Get("QuestService").RewardGrant

	local DinosaurService = app.Get("DinosaurService")

	--[[
		DinosaurService writes the Index entry as part of creating a dinosaur,
		so by the time this fires the entry exists. A first discovery is one
		with a Count of exactly 1 - read from the profile rather than tracked
		separately, because two counters describing one thing is the drift this
		project keeps removing.
	]]
	DinosaurService.DinoCreated:Connect(function(player, _uid, entry)
		local data = PlayerDataService.Get(player)
		if not data then
			return
		end

		local indexEntry = data.Index[entry.SpeciesId]
		if not indexEntry or indexEntry.Count ~= 1 then
			return
		end

		local species = DinoConfig.Get(entry.SpeciesId)
		NotificationService.Takeover(player, {
			Title = "NEW SPECIES",
			Subtitle = species and species.DisplayName or entry.SpeciesId,
			Headline = string.format("%d / %d", IndexService.Discovered(data), IndexService.Total()),
			Duration = 4,
		})

		IndexService.SpeciesDiscovered:Fire(player, entry.SpeciesId, indexEntry)
		IndexService.CheckMilestones(player)
	end)

	--[[
		Checked on load as well. A player who crossed a milestone before this
		service shipped - or during a session that failed to save - is paid the
		next time they arrive rather than never.
	]]
	PlayerDataService.ProfileLoaded:Connect(function(player)
		task.defer(IndexService.CheckMilestones, player)
	end)

	Log.info("IndexService", "Ready. %d species to discover, %d milestone(s)",
		IndexService.Total(), #IndexConfig.Milestones)
end

return IndexService
