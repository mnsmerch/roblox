--!nonstrict
--[[
	RewardGrant
	.../Services/QuestService/RewardGrant  (ModuleScript)

	One function that pays out a reward table, used by quests, dailies and
	Index milestones.

	═══ WHY ONE GRANT FUNCTION ═════════════════════════════════════════════════
	Three systems hand out overlapping rewards: Fossils, DNA, eggs, boosts,
	shields, luck nodes, slots, titles. Written three times, the rebirth scaling
	gets applied in two of them, the third quietly pays a flat rate forever, and
	nothing throws.

	So a reward is DATA - a table of optional fields declared in DailyConfig,
	QuestConfig or IndexConfig - and this is the only code that reads it.
	Adding a reward kind is one branch here and a field there.
	═══════════════════════════════════════════════════════════════════════════

	Rewards are additive and idempotent-by-caller: this function does not know
	whether something has already been claimed, because that check belongs with
	the thing being claimed and must happen BEFORE the grant (docs/13 §Step 19's
	double-claim hazard).

	Depends on: EconomyService, PlayerDataService, StealService,
	            NotificationService, DailyConfig, QuestConfig, RarityConfig.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DailyConfig = require(Shared.Config.DailyConfig)
local Format = require(Shared.Modules.Format)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Modules.Log)
local QuestConfig = require(Shared.Config.QuestConfig)
local RarityConfig = require(Shared.Config.RarityConfig)

local RewardGrant = {}

local EconomyService, PlayerDataService, StealService, NotificationService

--[[
	Builds a one-line summary as it grants, so the notification says exactly
	what arrived rather than a generic "reward claimed".
]]
local function describe(parts)
	return if #parts > 0 then table.concat(parts, "  ·  ") else "Claimed"
end

--[[
	Pays out `reward`. Returns the summary line.

	Every field is optional and every one is independent, so a reward table with
	no recognised fields grants nothing and says so rather than erroring - which
	is what a typo in a config should do.
]]
function RewardGrant.Give(player: Player, reward, reason: string): string
	local data = PlayerDataService.Get(player)
	if not data or type(reward) ~= "table" then
		return ""
	end

	local rebirths = data.Rebirths or 0
	local parts = {}

	--[[
		docs/05 §7: all Fossil values scale with `(1 + 0.9 x rebirths)`. DNA
		does not - it is the depth currency and deliberately does not inflate
		(docs/05 §1). Doing this in one place is the whole reason this file
		exists.
	]]
	if reward.Fossils and reward.Fossils > 0 then
		local amount = QuestConfig.ScaleFossils(reward.Fossils, rebirths)
		EconomyService.AddFossils(player, amount, reason)
		table.insert(parts, "+" .. Format.Number(amount) .. " Fossils")
	end

	if reward.Dna and reward.Dna > 0 then
		EconomyService.AddDna(player, reward.Dna, reason)
		table.insert(parts, "+" .. Format.Number(reward.Dna) .. " DNA")
	end

	--[[
		An egg reward goes straight into storage as a real egg, not into Items
		as a token to be redeemed later. A "Rare Egg" that needs a second
		screen to become an egg is a reward the player has to work out.
	]]
	if reward.Egg then
		local tier = RarityConfig.Tiers[reward.Egg]
		if tier then
			local stored = 0
			for _ in data.Eggs do
				stored += 1
			end

			if stored >= GameConfig.EggStorageCap then
				--[[
					Refused rather than dropped: the player keeps the Fossils
					and is told why the egg did not arrive, instead of silently
					losing it to a full bag.
				]]
				table.insert(parts, "egg storage full")
			else
				local uid = string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 8)
				PlayerDataService.UpdateKeys(player, { "Eggs" }, function(profile)
					profile.Eggs[uid] = {
						Rarity = reward.Egg,
						Origin = "reward",
						AcquiredAt = os.time(),
					}
				end, reason)
				table.insert(parts, "1 " .. tier.DisplayName .. " Egg")
			end
		end
	end

	--[[
		Boosts are stored as an EXPIRY, not a duration, so a player who logs off
		mid-potion does not come back with the clock reset. Extending an active
		boost adds to what is left rather than replacing it.
	]]
	if reward.Boost and reward.Boost.Id then
		local definition = DailyConfig.GetBoost(reward.Boost.Id)
		if definition then
			local secs = reward.Boost.Secs or 600
			local now = os.time()
			PlayerDataService.UpdateKeys(player, { "Boosts" }, function(profile)
				local existing = profile.Boosts[reward.Boost.Id] or 0
				profile.Boosts[reward.Boost.Id] = math.max(existing, now) + secs
			end, reason)
			table.insert(parts, definition.DisplayName .. " " .. Format.Time(secs))
		end
	end

	if reward.Shield and reward.Shield > 0 and StealService then
		StealService.GrantShield(player, reward.Shield, reason)
		table.insert(parts, "Shield " .. Format.Time(reward.Shield))
	end

	--[[
		The permanent grants. Each is a plain counter on the profile that Stats
		already reads, so a granted slot is a slot the moment it is written -
		there is no second system to remember to tell.
	]]
	if reward.LuckNodes and reward.LuckNodes > 0 then
		PlayerDataService.UpdateKeys(player, { "LuckNodes" }, function(profile)
			profile.LuckNodes += reward.LuckNodes
		end, reason)
		table.insert(parts, string.format("+%d%% permanent Luck",
			math.floor(reward.LuckNodes * GameConfig.LuckPerNode * 100 + 0.5)))
	end

	if reward.DinoSlots and reward.DinoSlots > 0 then
		PlayerDataService.UpdateKeys(player, { "BonusDinoSlots" }, function(profile)
			profile.BonusDinoSlots += reward.DinoSlots
		end, reason)
		table.insert(parts, "+" .. reward.DinoSlots .. " Dino Slot")
	end

	if reward.VaultSlots and reward.VaultSlots > 0 then
		PlayerDataService.UpdateKeys(player, { "BonusVaultSlots" }, function(profile)
			profile.BonusVaultSlots += reward.VaultSlots
		end, reason)
		table.insert(parts, "+" .. reward.VaultSlots .. " Vault Slot")
	end

	if reward.Title then
		PlayerDataService.UpdateKeys(player, { "Titles" }, function(profile)
			profile.Titles[reward.Title] = true
		end, reason)
		table.insert(parts, "Title: " .. reward.Title)
	end

	if reward.Item and reward.Item.Id then
		PlayerDataService.UpdateKeys(player, { "Items" }, function(profile)
			profile.Items[reward.Item.Id] = (profile.Items[reward.Item.Id] or 0)
				+ (reward.Item.Count or 1)
		end, reason)
		table.insert(parts, (reward.Item.Count or 1) .. "x " .. reward.Item.Id)
	end

	local summary = describe(parts)
	Log.info("RewardGrant", "%s: %s (%s)", player.Name, summary, reason)
	return summary
end

function RewardGrant.Init(app)
	EconomyService = app.Get("EconomyService")
	PlayerDataService = app.Get("PlayerDataService")
	NotificationService = app.Get("NotificationService")

	--[[
		Guarded, because a shield reward is a nice-to-have and StealService
		loading after this one must not make a daily chest unclaimable.
	]]
	local ok, service = pcall(app.Get, "StealService")
	StealService = if ok then service else nil
end

return RewardGrant
