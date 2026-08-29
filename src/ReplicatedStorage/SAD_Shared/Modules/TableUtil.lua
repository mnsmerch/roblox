--!nonstrict
--[[
	TableUtil
	ReplicatedStorage/SAD_Shared/Modules/TableUtil  (ModuleScript)

	Table helpers. The important one is Reconcile, which DataService uses to fill
	a loaded profile with any keys the current schema template has but the saved
	data doesn't. That is how new fields ship without a migration for every
	single addition.

	--!nonstrict because a properly generic DeepCopy signature costs more in
	casts than it returns in safety.

	Depends on: nothing.
]]

local TableUtil = {}

--- Recursive copy. Keys are copied by value (ours are always strings/numbers).
function TableUtil.DeepCopy(source)
	if type(source) ~= "table" then
		return source
	end
	local copy = table.clone(source)
	for key, value in copy do
		if type(value) == "table" then
			copy[key] = TableUtil.DeepCopy(value)
		end
	end
	return copy
end

--[[
	Returns a copy of `target` with any keys missing from it filled in from
	`template`. Recurses into nested tables that exist on BOTH sides.

	Deliberate behaviour: a template value of {} adds an empty table and never
	recurses, so player-owned dictionaries (Dinos, Eggs, Index) are left alone.
	Reconcile never deletes a key the player has.
]]
function TableUtil.Reconcile(target, template)
	local result = TableUtil.DeepCopy(target)

	for key, templateValue in template do
		local current = result[key]
		if current == nil then
			result[key] = if type(templateValue) == "table"
				then TableUtil.DeepCopy(templateValue)
				else templateValue
		elseif type(templateValue) == "table" and type(current) == "table" then
			result[key] = TableUtil.Reconcile(current, templateValue)
		end
	end

	return result
end

--- Shallow merge of `extra` over a copy of `base`.
function TableUtil.Merge(base, extra)
	local result = table.clone(base)
	for key, value in extra do
		result[key] = value
	end
	return result
end

--- Entry count for dictionaries (#t only works on arrays).
function TableUtil.Count(source)
	local count = 0
	for _ in source do
		count += 1
	end
	return count
end

--- Cheaper than Count() == 0 for large tables.
function TableUtil.IsEmpty(source)
	return next(source) == nil
end

function TableUtil.Keys(source)
	local keys = {}
	for key in source do
		table.insert(keys, key)
	end
	return keys
end

--- Deterministic key order. Used anywhere randomness must be reproducible.
function TableUtil.SortedKeys(source)
	local keys = TableUtil.Keys(source)
	table.sort(keys)
	return keys
end

--- Recursively freezes. Applied to every config at boot so no service can
--- accidentally mutate shared content data at runtime.
function TableUtil.DeepFreeze(source)
	for _, value in source do
		if type(value) == "table" and not table.isfrozen(value) then
			TableUtil.DeepFreeze(value)
		end
	end
	if not table.isfrozen(source) then
		table.freeze(source)
	end
	return source
end

--- True when both tables have identical contents, compared recursively.
function TableUtil.DeepEquals(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not TableUtil.DeepEquals(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

return TableUtil
