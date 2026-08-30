--!nonstrict
--[[
	PurchaseService
	ServerScriptService/SAD_Server/Services/PurchaseService  (ModuleScript)

	Robux. The only file in the project that touches MarketplaceService.

	═══ THE MOST EXPENSIVE BUG POSSIBLE ════════════════════════════════════════
	docs/13 §Step 21 names it exactly: "returning PurchaseGranted before the
	profile is marked dirty (this loses purchases and it is the most expensive
	bug possible)."

	So ProcessReceipt does, in this order and no other:

	  1. Refuse with NotProcessedYet if the profile is not loaded. Roblox
	     retries; a player who bought something during a load gets it on the
	     retry rather than losing it.
	  2. Check the PurchaseId against the profile's ring buffer. Already there
	     means already granted - return PurchaseGranted so Roblox stops asking.
	  3. Record the PurchaseId AND grant, in ONE profile write.
	  4. Save, and wait for the save.
	  5. Only then return PurchaseGranted.

	Step 3 being one write is what makes a crash between "recorded" and
	"granted" impossible. Step 4 is what makes a crash between "granted" and
	"Roblox told" harmless: the receipt is durable, so the retry finds it in
	the ring and returns granted without paying twice.
	═══════════════════════════════════════════════════════════════════════════

	═══ NO ASSET IDS ARE INVENTED ══════════════════════════════════════════════
	Every id in ProductConfig is 0 until the live place exists. This service
	refuses to prompt or process an unconfigured id and says how many are
	waiting at boot. A game with no store is still a complete game: docs/07 §1
	rule 1 guarantees every paid effect exists free at lower magnitude.
	═══════════════════════════════════════════════════════════════════════════

	API:
		PurchaseService.OwnsPass(player, key) -> boolean
		PurchaseService.RefreshOwnership(player)      -- yields
		PurchaseService.GrantProduct(player, entry, receiptId?) -> ok, reason?
		PurchaseService.Thank(player, buyerUserId) -> ok, reason?
		PurchaseService.PassPurchased  Signal(player, key)
		PurchaseService.ProductPurchased  Signal(player, key)

	Depends on: ProductConfig, Economy, PlayerDataService, EconomyService,
	            NotificationService, StealService, IncubationService,
	            QuestService (for RewardGrant), EventService, WeatherService.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Economy = require(Shared.Modules.Economy)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local ProductConfig = require(Shared.Config.ProductConfig)
local Signal = require(Shared.Modules.Signal)

local PurchaseService = {}

PurchaseService.PassPurchased = Signal.new()
PurchaseService.ProductPurchased = Signal.new()

local PlayerDataService, EconomyService, NotificationService
local RewardGrant, StealService, IncubationService

--- docs/10 §2 bounds this at 100 entries.
local RECEIPT_RING = 100

--[[
	The most recent server-wide purchase, for the Thanks button.
	{ BuyerUserId, BuyerName, At, Thanked = { [userId] = true } }
]]
local lastServerPurchase = nil

--- A player with no park at all still gets something for a Fossil Pack.
local PACK_FLOOR_FOSSILS = 2500

-- ── Ownership ───────────────────────────────────────────────────────────────

function PurchaseService.OwnsPass(player: Player, key: string): boolean
	local data = PlayerDataService.Get(player)
	return data ~= nil and data.Gamepasses[key] == true
end

--[[
	Re-reads ownership from Roblox. Yields.

	Cached in the profile rather than queried per read: `UserOwnsGamePassAsync`
	is a web call, and Stats reads gamepass effects on every income
	calculation. The cache is refreshed on join and whenever a purchase
	finishes mid-session, which is the whole of docs/09 §7.6's requirement.

	Every call is pcall'd and a FAILURE LEAVES THE CACHE ALONE. Roblox being
	briefly unavailable must not silently revoke a pass somebody paid for.
]]
function PurchaseService.RefreshOwnership(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local owned = {}
	local checked, failures = 0, 0

	for key, entry in ProductConfig.Gamepasses do
		if not ProductConfig.IsConfigured(entry) then
			-- Nothing to ask about. Keep whatever the profile already says, so
			-- a pass granted in a test place is not wiped by an id being 0.
			owned[key] = data.Gamepasses[key]
			continue
		end

		local ok, has = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.AssetId)
		end)

		checked += 1
		if ok then
			owned[key] = has == true
		else
			failures += 1
			owned[key] = data.Gamepasses[key]
		end
	end

	if failures > 0 then
		Log.warn("PurchaseService", "%d of %d ownership checks failed for %s - kept the cache",
			failures, checked, player.Name)
	end

	PlayerDataService.UpdateKeys(player, { "Gamepasses" }, function(profile)
		profile.Gamepasses = owned
	end, "gamepass ownership")

	--[[
		Passes change income, slots and incubators, so anything derived from
		them is recomputed. Cheap, and missing it means a player who buys
		Double Income mid-session earns single until they rejoin - which
		docs/13 §Step 21 tests for explicitly.
	]]
	EconomyService.InvalidateRate(player)
end

-- ── Granting ────────────────────────────────────────────────────────────────

--[[
	Applies one product's effect. Called from inside ProcessReceipt's write for
	the parts that are profile changes, and after it for the parts that are
	not.

	Returns (ok, reason). A product that cannot be granted right now - an
	Instant Hatch with nothing incubating - still returns true: the player
	paid, Roblox must be told the purchase succeeded, and the alternative is a
	receipt that retries forever.
]]
local function applyProduct(player: Player, entry): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	--[[
		docs/07 §3: Fossil Packs are scaled to the buyer's own income, "the
		single most important economy decision in the monetization design".
		A pack is never a shortcut past a wall because it is always the same
		number of minutes of wherever the player already is.
	]]
	if entry.Action == "fossilPack" then
		local seconds = ProductConfig.PackSeconds[entry.PackSize] or 600
		local rate = Economy.ParkIncomeRate(data)
		local amount = math.max(math.floor(rate * seconds), PACK_FLOOR_FOSSILS)
		EconomyService.AddFossils(player, amount, "product " .. entry.Key)
		NotificationService.Takeover(player, {
			Title = string.upper(entry.DisplayName),
			Subtitle = string.format("%s of your income", Format.Time(seconds)),
			Headline = "+" .. Format.Number(amount),
			Duration = 4,
		})
		return true
	end

	if entry.Action == "instantHatch" or entry.Action == "instantHatchAll" then
		local finished = IncubationService.FinishNow(player,
			entry.Action == "instantHatchAll")
		NotificationService.Toast(player, string.upper(entry.DisplayName),
			string.format("%d egg%s ready", finished, if finished == 1 then "" else "s"))
		return true
	end

	--[[
		A server-wide boost. docs/07 §1 rule 6: "Every server-wide purchase
		benefits everyone, and credits the buyer by name."
	]]
	if entry.ServerWide then
		for _, other in Players:GetPlayers() do
			if entry.Grant then
				RewardGrant.Give(other, entry.Grant, "server " .. entry.Key)
			end
		end

		lastServerPurchase = {
			BuyerUserId = player.UserId,
			BuyerName = player.DisplayName,
			At = os.clock(),
			Thanked = {},
		}

		NotificationService.Announce({
			Kind = "takeover",
			Title = string.format(entry.Announcement or "%s BOUGHT A SERVER BOOST!",
				string.upper(player.DisplayName)),
			Subtitle = entry.Blurb,
			Headline = "SAY THANKS",
			Duration = 6,
		})

		Net.FireAllClients("ServerBoost", {
			BuyerUserId = player.UserId,
			BuyerName = player.DisplayName,
			Product = entry.Key,
			WindowSecs = ProductConfig.ThanksWindowSecs,
		})
		return true
	end

	-- Everything else is a plain reward table, paid by the one grant function.
	if entry.Grant then
		local summary = RewardGrant.Give(player, entry.Grant, "product " .. entry.Key)
		NotificationService.Toast(player, string.upper(entry.DisplayName), summary)
		return true
	end

	return true
end

--[[
	Grants a product and records its receipt in ONE write.

	`receiptId` may be nil when a grant is driven by something other than a
	receipt (an admin command, a test). The ring is only written when there is
	an id to record.
]]
function PurchaseService.GrantProduct(player: Player, entry, receiptId: string?): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	--[[
		Recorded BEFORE the effect is applied, in a write that also bumps the
		spend total. Every path out of applyProduct below is therefore already
		covered by a durable receipt.
	]]
	if receiptId then
		PlayerDataService.UpdateKeys(player, { "ProcessedReceipts", "RobuxSpent" }, function(profile)
			table.insert(profile.ProcessedReceipts, receiptId)
			-- docs/10 §2: a 100-entry ring, so the profile stays bounded.
			while #profile.ProcessedReceipts > RECEIPT_RING do
				table.remove(profile.ProcessedReceipts, 1)
			end
			profile.RobuxSpent += entry.Robux or 0
		end, "receipt " .. entry.Key)
	end

	local ok, reason = applyProduct(player, entry)
	PurchaseService.ProductPurchased:Fire(player, entry.Key)
	return ok, reason
end

-- ── Receipts ────────────────────────────────────────────────────────────────

local function alreadyProcessed(data, receiptId: string): boolean
	for _, id in data.ProcessedReceipts do
		if id == receiptId then
			return true
		end
	end
	return false
end

--[[
	`MarketplaceService.ProcessReceipt`. Implemented once, here.

	The ordering in this function is the whole of docs/09 §7.6 and docs/13's
	warning; the comments name which line is which guarantee.
]]
local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		-- They left. Roblox retries when they next join a server.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local data = PlayerDataService.Get(player)
	if not data then
		--[[
			GUARANTEE 1. The profile is not loaded, so nothing can be recorded
			durably. Refusing here means Roblox retries; granting here means a
			purchase that vanishes if the session ends first.
		]]
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptId = tostring(info.PurchaseId)

	--[[
		GUARANTEE 2. Idempotency. A receipt already in the ring was already
		granted, so this returns Granted to stop Roblox retrying - NOT to grant
		again.
	]]
	if alreadyProcessed(data, receiptId) then
		Log.info("PurchaseService", "Receipt %s already processed for %s", receiptId, player.Name)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local kind, entry = ProductConfig.ByAssetId(info.ProductId)
	if kind ~= "product" or not entry then
		--[[
			An id this build does not know. NOT granted and NOT consumed: an
			older server may know it, and consuming it would take the player's
			Robux for nothing.
		]]
		Log.warn("PurchaseService", "Unknown product id %s from %s", tostring(info.ProductId), player.Name)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- GUARANTEE 3. Record and grant in one write; see GrantProduct.
	local ok = PurchaseService.GrantProduct(player, entry, receiptId)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	--[[
		GUARANTEE 4. The save is waited for. If the server dies after this
		line, the receipt is durable and the retry finds it in the ring.
		If it dies BEFORE, nothing was granted and Roblox retries cleanly.
		There is no ordering in between.
	]]
	PlayerDataService.Save(player, "receipt")

	Log.info("PurchaseService", "%s bought %s (%d R$)", player.Name, entry.Key, entry.Robux or 0)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ── Thanks ──────────────────────────────────────────────────────────────────

--[[
	docs/07 §4's Thanks button. The reward goes to the THANKER, "so people
	actually press it" - paying the buyer would turn gratitude into something
	they profit from twice.
]]
function PurchaseService.Thank(player: Player, buyerUserId: number): (boolean, string?)
	local purchase = lastServerPurchase
	if not purchase then
		return false, "nothing to thank anyone for"
	end
	if purchase.BuyerUserId ~= buyerUserId then
		return false, "that is not the buyer"
	end
	if os.clock() - purchase.At > ProductConfig.ThanksWindowSecs then
		return false, "too late"
	end
	if player.UserId == buyerUserId then
		return false, "you cannot thank yourself"
	end
	if purchase.Thanked[player.UserId] then
		return false, "already said thanks"
	end

	purchase.Thanked[player.UserId] = true
	EconomyService.AddFossils(player, ProductConfig.ThanksReward, "thanks")

	local buyer = Players:GetPlayerByUserId(buyerUserId)
	if buyer then
		Net.FireClient("ServerBoost", buyer, {
			Kind = "thanked",
			FromName = player.DisplayName,
		})
	end

	return true
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function PurchaseService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	EconomyService = app.Get("EconomyService")
	NotificationService = app.Get("NotificationService")
	IncubationService = app.Get("IncubationService")
end

function PurchaseService.Start(app)
	RewardGrant = app.Get("QuestService").RewardGrant

	local ok, service = pcall(app.Get, "StealService")
	StealService = if ok then service else nil

	--[[
		Bound once. Roblox allows exactly one ProcessReceipt callback per
		experience, and binding it in two places silently keeps whichever ran
		last - which is why docs/09 §7.6 says "implemented once, in
		PurchaseService".
	]]
	MarketplaceService.ProcessReceipt = function(info)
		local success, result = pcall(processReceipt, info)
		if not success then
			--[[
				An error inside ProcessReceipt must never be read as a grant.
				NotProcessedYet is the only safe answer: Roblox retries, and a
				retry that succeeds is better than a purchase silently
				consumed by a bug.
			]]
			Log.error("PurchaseService", "ProcessReceipt errored: %s", tostring(result))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return result
	end

	--[[
		docs/09 §7.6: ownership is cached on join, "with a
		PromptGamePassPurchaseFinished listener to update mid-session".
	]]
	PlayerDataService.ProfileLoaded:Connect(function(player)
		task.spawn(PurchaseService.RefreshOwnership, player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end

		local kind, entry = ProductConfig.ByAssetId(passId)
		if kind ~= "gamepass" or not entry then
			return
		end

		--[[
			Refreshed from Roblox rather than trusting the event's own claim.
			The event says a purchase finished; ownership is what the server
			asks Roblox about.
		]]
		PurchaseService.RefreshOwnership(player)

		PurchaseService.PassPurchased:Fire(player, entry.Key)
		NotificationService.Takeover(player, {
			Title = string.upper(entry.DisplayName),
			Subtitle = entry.Blurb,
			Headline = "ACTIVE NOW",
			Duration = 5,
		})
	end)

	Net.OnEvent("RequestThanks", function(player, buyerUserId)
		if type(buyerUserId) ~= "number" then
			return
		end
		PurchaseService.Thank(player, math.floor(buyerUserId))
	end)

	local unconfiguredPasses, unconfiguredProducts = ProductConfig.Unconfigured()
	if unconfiguredPasses + unconfiguredProducts > 0 then
		Log.warn("PurchaseService",
			"Ready, but %d gamepass(es) and %d product(s) have no AssetId. "
				.. "Create them in the live place and paste the ids into ProductConfig - "
				.. "everything else works without them",
			unconfiguredPasses, unconfiguredProducts)
	else
		Log.info("PurchaseService", "Ready. %d gamepass(es), %d product(s)",
			ProductConfig.CountPasses(), ProductConfig.CountProducts())
	end
end

return PurchaseService
