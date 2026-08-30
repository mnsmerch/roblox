--!nonstrict
--[[
	ProductConfig
	ReplicatedStorage/SAD_Shared/Config/ProductConfig  (ModuleScript)

	The 6 gamepasses and 8 developer products V1 ships (docs/12 §MVP), with the
	prices and effects docs/07 publishes.

	═══ NO ASSET IDS ARE INVENTED HERE ═════════════════════════════════════════
	Every `AssetId` below is 0, which means NOT CONFIGURED YET. The Roblox
	experience does not exist (see PROGRESS.md's open question #1), and a
	plausible-looking id would be a purchase prompt that fails silently or,
	worse, one that charges for somebody else's product.

	So: create each pass and product in the live place, paste its id here, and
	nothing else changes. Until then `PurchaseService` refuses to prompt or
	process an unconfigured id and says so at boot, and ConfigValidator rule 10
	warns rather than failing - a game with no store should still be entirely
	playable, because every paid effect exists free at lower magnitude
	(docs/07 §1).
	═══════════════════════════════════════════════════════════════════════════

	═══ OWNERSHIP IS KEYED BY OUR KEY, NOT BY THE ASSET ID ═════════════════════
	`Profile.Gamepasses` is keyed by the string keys below ("vip"), never by the
	numeric id. Two reasons: a DataStore round trip mangles a table with sparse
	numeric keys, and the id itself legitimately differs between a test place
	and the live one - keying on it would invalidate every save the day the
	game is published.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local ProductConfig = {}

--[[
	docs/07 §2: "the combined multiplicative effect of all owned gamepasses on
	income is capped at x2.6, so a full-catalogue buyer is roughly a 2.6x faster
	player, not a 20x one."
]]
ProductConfig.IncomeStackCap = 2.6

--- docs/07 §3: Fossil Packs are worth this many seconds of the BUYER'S income.
--- Never a fixed amount - see the note on the products themselves.
ProductConfig.PackSeconds = { small = 600, medium = 2700, large = 10800 }

local gamepasses = {}
local products = {}

local function pass(entry)
	entry.AssetId = entry.AssetId or 0
	assert(gamepasses[entry.Key] == nil, "duplicate gamepass: " .. entry.Key)
	gamepasses[entry.Key] = entry
	return entry
end

local function product(entry)
	entry.AssetId = entry.AssetId or 0
	assert(products[entry.Key] == nil, "duplicate product: " .. entry.Key)
	products[entry.Key] = entry
	return entry
end

-- ── Gamepasses (docs/07 §2; V1 subset per docs/12) ──────────────────────────

pass({
	Key = "vip", DisplayName = "VIP", Robux = 499, AssetId = 0,
	Blurb = "100% offline income, +1 incubator, +2 dino slots, auto-collect, 25,000 Fossils a day",
	Effects = {
		OfflineRate = 1.0, -- replaces Economy.OfflineRate
		Incubators = 1,
		DinoSlots = 2,
		AutoCollectFromStart = true,
		DailyFossils = 25000,
	},
})

pass({
	Key = "doubleIncome", DisplayName = "Double Income", Robux = 799, AssetId = 0,
	Blurb = "Every dinosaur in your park earns twice as much",
	Effects = { IncomeMultiplier = 2.0 },
})

pass({
	Key = "luckyPlayer", DisplayName = "Lucky Player", Robux = 649, AssetId = 0,
	Blurb = "+35% Luck on every egg you take",
	Effects = { Luck = 0.35 },
})

pass({
	Key = "dinoSlots6", DisplayName = "+6 Dino Slots", Robux = 399, AssetId = 0,
	Blurb = "Six more placement slots in your park",
	Effects = { DinoSlots = 6 },
})

pass({
	Key = "incubators2", DisplayName = "+2 Incubators", Robux = 349, AssetId = 0,
	Blurb = "Hatch two more eggs at once",
	Effects = { Incubators = 2 },
})

pass({
	Key = "fastHatch", DisplayName = "Fast Hatch", Robux = 299, AssetId = 0,
	Blurb = "Eggs hatch 25% faster",
	Effects = { IncubationMultiplier = 0.75 },
})

--[[
	V1.1+, with the prices docs/07 §2 publishes:

		mutationMaster  799  +50% MutLuck
		eggPouch2       249  carry 2 extra eggs
		vaultSlots2     349  2 extra unstealable pedestals
		sprintBoots     299  +20% move speed
		parkTheme       199  cosmetic retexture
		titanNametag    249  cosmetic animated nametag
]]

-- ── Developer products (docs/07 §3; V1 subset per docs/12) ──────────────────

product({
	Key = "luckBoost", DisplayName = "Luck Boost", Robux = 49, AssetId = 0,
	Blurb = "2x Luck for 15 minutes",
	Grant = { Boost = { Id = "luckPotion", Secs = 900 } },
})

product({
	Key = "mutationBoost", DisplayName = "Mutation Boost", Robux = 79, AssetId = 0,
	Blurb = "2x Mutation Luck for 15 minutes",
	Grant = { Boost = { Id = "mutationSerum", Secs = 900 } },
})

product({
	Key = "instantHatch", DisplayName = "Instant Hatch", Robux = 29, AssetId = 0,
	Blurb = "Finish the egg in your first incubator right now",
	Action = "instantHatch",
})

product({
	Key = "instantHatchAll", DisplayName = "Instant Hatch All", Robux = 99, AssetId = 0,
	Blurb = "Finish every egg you have incubating right now",
	Action = "instantHatchAll",
})

--[[
	docs/07 §3: "Fossil Packs are scaled to the buyer's own income, not fixed
	amounts. This is the single most important economy decision in the
	monetization design: it means a pack is never a shortcut past a wall, and
	it never breaks the curve for a rebirth-20 player or trivialises the early
	game for a new one."

	So a pack grants SECONDS of the buyer's current park rate. A player with no
	park gets the floor below instead - otherwise the packs sold to the
	players least able to use them would pay literally nothing.
]]
product({
	Key = "fossilPackSmall", DisplayName = "Fossil Pack - Small", Robux = 49, AssetId = 0,
	Blurb = "10 minutes of your current income",
	Action = "fossilPack", PackSize = "small",
})

product({
	Key = "fossilPackMedium", DisplayName = "Fossil Pack - Medium", Robux = 199, AssetId = 0,
	Blurb = "45 minutes of your current income",
	Action = "fossilPack", PackSize = "medium",
})

product({
	Key = "parkShield", DisplayName = "Park Shield", Robux = 79, AssetId = 0,
	Blurb = "30 minutes of protection. Capped by the 2-hour stack rule",
	Grant = { Shield = 1800 },
})

--[[
	docs/07 §4: server purchases are "the profit centre AND the community glue",
	and rule 6 of docs/07 §1 requires that every one of them benefits everyone
	and credits the buyer by name.
]]
product({
	Key = "serverLuck", DisplayName = "SERVER: 2x Luck", Robux = 199, AssetId = 0,
	Blurb = "Ten minutes of double Luck for everyone on the server",
	ServerWide = true, Action = "serverBoost",
	Grant = { Boost = { Id = "luckPotion", Secs = 600 } },
	Announcement = "%s ACTIVATED 2x SERVER LUCK!",
})

--[[
	V1.1+, with the prices docs/07 §3 publishes:

		fossilPackLarge   799  3 hours of income
		questReroll        25  one extra daily reroll
		eventEgg          149  one egg from the current event's table
		serverMutation    249  SERVER: 2x Mutation, 10 min
		serverFrenzy      249  SERVER: Nest Frenzy, 3 min
		serverWeather     149  SERVER: buyer picks the weather
]]

ProductConfig.Gamepasses = gamepasses
ProductConfig.Products = products

--[[
	═══ THE ORDER THE STORE LISTS THINGS IN ════════════════════════════════════
	Explicit, and here rather than in the controller, for two reasons. A hash
	table has no order at all, so iterating one gives a store whose rows move
	between sessions - a store players cannot learn. And an order that lives in
	the client cannot be checked against the catalogue, so a pass added without
	a listing would simply never appear for sale.

	Both lists are asserted below to be exactly the catalogue, once each.

	VIP leads the passes because it is the broadest. The server boost leads the
	products because docs/07 §4 makes it the one purchase that is supposed to
	make you popular, and burying it under four consumables works against that.
	═══════════════════════════════════════════════════════════════════════════
]]
ProductConfig.PassOrder = {
	"vip", "doubleIncome", "luckyPlayer", "dinoSlots6", "incubators2", "fastHatch",
}

ProductConfig.ProductOrder = {
	"serverLuck",
	"fossilPackSmall", "fossilPackMedium",
	"luckBoost", "mutationBoost",
	"instantHatch", "instantHatchAll",
	"parkShield",
}

do
	local function assertCovers(order, catalogue, label)
		local seen = {}
		for _, key in order do
			assert(catalogue[key], ("ProductConfig.%sOrder lists unknown '%s'"):format(label, key))
			assert(not seen[key], ("ProductConfig.%sOrder lists '%s' twice"):format(label, key))
			seen[key] = true
		end
		for key in catalogue do
			assert(seen[key], ("ProductConfig.%sOrder is missing '%s', so it would never appear in the store")
				:format(label, key))
		end
	end
	assertCovers(ProductConfig.PassOrder, gamepasses, "Pass")
	assertCovers(ProductConfig.ProductOrder, products, "Product")
end

--[[
	docs/07 §4: "Every player gets a one-tap Thanks! button that sends a
	floating heart above the buyer and gives the THANKER 500 Fossils (so people
	actually press it)."

	The reward goes to the thanker, not the buyer, on purpose: paying the buyer
	would turn gratitude into a transaction they profit from twice.
]]
ProductConfig.ThanksReward = 500
ProductConfig.ThanksWindowSecs = 60

-- ── Helpers ─────────────────────────────────────────────────────────────────

function ProductConfig.GetPass(key: string)
	return gamepasses[key]
end

function ProductConfig.GetProduct(key: string)
	return products[key]
end

--- Finds whatever owns `assetId`. Returns (kind, entry) or nil.
function ProductConfig.ByAssetId(assetId: number)
	if type(assetId) ~= "number" or assetId <= 0 then
		return nil, nil
	end
	for _, entry in gamepasses do
		if entry.AssetId == assetId then
			return "gamepass", entry
		end
	end
	for _, entry in products do
		if entry.AssetId == assetId then
			return "product", entry
		end
	end
	return nil, nil
end

--- Whether an entry can actually be sold. See the header.
function ProductConfig.IsConfigured(entry): boolean
	return entry ~= nil and type(entry.AssetId) == "number" and entry.AssetId > 0
end

--- How many of each are still waiting for an id, for the boot log.
function ProductConfig.Unconfigured(): (number, number)
	local passes, prods = 0, 0
	for _, entry in gamepasses do
		if not ProductConfig.IsConfigured(entry) then
			passes += 1
		end
	end
	for _, entry in products do
		if not ProductConfig.IsConfigured(entry) then
			prods += 1
		end
	end
	return passes, prods
end

--[[
	═══ HOW EACH EFFECT COMBINES IS DECLARED, NOT INFERRED ═════════════════════
	This table used to be a guess: "if the default is 1 it must be a multiplier,
	otherwise add". That is right for five of the eight effects and silently
	wrong for OfflineRate, whose default is Economy.OfflineRate (0.60) and whose
	VIP value is 1.0 - the guess ADDED them and paid VIP 160% of park rate while
	they were offline, which is more than they earn while playing.

	So each effect names its own mode. A new effect with no entry here fails the
	assertion at the bottom of this file rather than picking up a default that
	happens to be wrong for it.
	═══════════════════════════════════════════════════════════════════════════

	  "add"       the values sum onto the default      (+2 slots, +0.35 Luck)
	  "multiply"  the values multiply the default      (x2 income, x0.75 hatch)
	  "max"       the best owned value REPLACES the default, and two passes
	              granting the same effect do not stack   (VIP's offline rate)
]]
ProductConfig.EffectModes = {
	OfflineRate = "max",
	Incubators = "add",
	DinoSlots = "add",
	DailyFossils = "add",
	Luck = "add",
	MutLuck = "add",
	IncomeMultiplier = "multiply",
	IncubationMultiplier = "multiply",
}

--[[
	The combined effect of every owned gamepass on one named effect.

	`owned` is the profile's Gamepasses table, keyed by OUR keys. Combination
	follows EffectModes above, and multiplicative income is capped where
	docs/07 §2 caps it.
]]
function ProductConfig.EffectTotal(owned, effectName: string, default: number): number
	local mode = ProductConfig.EffectModes[effectName]
	assert(mode, "ProductConfig.EffectTotal: no mode declared for '" .. tostring(effectName) .. "'")

	local total = default
	for key, has in owned or {} do
		local entry = gamepasses[key]
		local value = has and entry and entry.Effects[effectName]
		if value ~= nil and type(value) == "number" then
			if mode == "multiply" then
				total *= value
			elseif mode == "max" then
				total = math.max(total, value)
			else
				total += value
			end
		end
	end

	if effectName == "IncomeMultiplier" then
		total = math.min(total, ProductConfig.IncomeStackCap)
	end
	return total
end

--[[
	Every numeric effect any pass grants - shipped or listed for V1.1 - must have
	a mode. Runs at require time, so a pass added without one cannot reach a
	live server.
]]
do
	for key, entry in gamepasses do
		for effectName, value in entry.Effects do
			if type(value) == "number" then
				assert(ProductConfig.EffectModes[effectName],
					("ProductConfig: gamepass '%s' grants '%s' with no EffectModes entry")
						:format(key, effectName))
			end
		end
	end
end

function ProductConfig.HasPass(owned, key: string): boolean
	return (owned or {})[key] == true
end

function ProductConfig.CountPasses(): number
	local n = 0
	for _ in gamepasses do
		n += 1
	end
	return n
end

function ProductConfig.CountProducts(): number
	local n = 0
	for _ in products do
		n += 1
	end
	return n
end

return ProductConfig
