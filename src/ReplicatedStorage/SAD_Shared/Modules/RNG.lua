--!strict
--[[
	RNG
	ReplicatedStorage/SAD_Shared/Modules/RNG  (ModuleScript)

	Weighted selection and the luck maths from docs/01-dinosaurs.md §1.2.

	Every roll that matters (rarity at pickup, species and mutation at hatch)
	runs on the SERVER through this module. It lives in SAD_Shared only so the
	client can display accurate odds in the UI - the client never rolls.

	Determinism: dictionary iteration order in Lua is unspecified, which would
	make weighted picks unreproducible. WeightedPick therefore iterates a sorted
	key list, cached per weight table. Same weights + same seed = same result,
	which is what makes the odds testable.

	Depends on: nothing.
]]

local RNG = {}

--- Sorted-key cache, keyed weakly so frozen config tables can still be collected.
local sortedKeyCache: any = setmetatable({}, { __mode = "k" })

--- A fresh generator. Services each hold their own, seeded at boot.
function RNG.new(seed: number?): Random
	if seed then
		return Random.new(seed)
	end
	return Random.new()
end

--- Deterministic key order for a weight table. Cached after the first call.
function RNG.SortedKeys(weights: { [string]: number }): { string }
	local cached = sortedKeyCache[weights]
	if cached then
		return cached
	end

	local keys = {}
	for key in weights do
		table.insert(keys, key)
	end
	table.sort(keys)

	sortedKeyCache[weights] = keys
	return keys
end

--[[
	Picks one key with probability proportional to its weight.
	Pass `order` (e.g. RarityConfig.Order) to skip the sort and control ordering.
	Returns nil only when every weight is zero.
]]
function RNG.WeightedPick(
	weights: { [string]: number },
	rng: Random,
	order: { string }?
): string?
	local keys = order or RNG.SortedKeys(weights)

	local total = 0
	for _, key in keys do
		local weight = weights[key]
		if weight and weight > 0 then
			total += weight
		end
	end

	if total <= 0 then
		return nil
	end

	local roll = rng:NextNumber() * total
	local accumulated = 0
	for _, key in keys do
		local weight = weights[key]
		if weight and weight > 0 then
			accumulated += weight
			if roll < accumulated then
				return key
			end
		end
	end

	-- Only reachable through float accumulation error at the very top of the range.
	for index = #keys, 1, -1 do
		local key = keys[index]
		local weight = weights[key]
		if weight and weight > 0 then
			return key
		end
	end
	return nil
end

--[[
	Applies a luck stat to a weight table.

		scaled[k] = base[k] * (1 + luck * power[k])

	Negative powers drain a tier (Common/Uncommon shrink as luck rises); Secret
	and Titan carry deliberately lower powers than Mythic so luck cannot buy the
	tail. See docs/01-dinosaurs.md §1.2.

	Returns a NEW table - the config is never mutated.
]]
function RNG.ApplyLuck(
	weights: { [string]: number },
	powers: { [string]: number },
	luck: number
): { [string]: number }
	local out = {}
	for key, weight in weights do
		local power = powers[key] or 0
		out[key] = math.max(weight * (1 + luck * power), 0)
	end
	return out
end

--- Multiplies specific weights, e.g. weather boosting a mutation. New table.
function RNG.ApplyModifiers(
	weights: { [string]: number },
	modifiers: { [string]: number },
	cap: number?
): { [string]: number }
	local out = table.clone(weights)
	for key, multiplier in modifiers do
		if out[key] then
			local applied = if cap then math.min(multiplier, cap) else multiplier
			out[key] = out[key] * applied
		end
	end
	return out
end

--- True with probability 1/oneIn. Used for flat gates like the Prime roll.
function RNG.Chance(oneIn: number, rng: Random): boolean
	if oneIn <= 1 then
		return true
	end
	return rng:NextInteger(1, math.floor(oneIn)) == 1
end

--- Fisher-Yates, in place.
function RNG.Shuffle<T>(list: { T }, rng: Random): { T }
	for index = #list, 2, -1 do
		local swap = rng:NextInteger(1, index)
		list[index], list[swap] = list[swap], list[index]
	end
	return list
end

--- Uniform pick from an array.
function RNG.Pick<T>(list: { T }, rng: Random): T?
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

--[[
	Normalised probability of one key, for UI display.
	The client calls this to show odds; it never calls WeightedPick.
]]
function RNG.ProbabilityOf(weights: { [string]: number }, key: string): number
	local total = 0
	for _, weight in weights do
		if weight > 0 then
			total += weight
		end
	end
	if total <= 0 then
		return 0
	end
	return (weights[key] or 0) / total
end

return RNG
