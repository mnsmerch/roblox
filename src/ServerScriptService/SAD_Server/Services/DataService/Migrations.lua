--!nonstrict
--[[
	Migrations
	ServerScriptService/SAD_Server/Services/DataService/Migrations  (ModuleScript)

	Ordered schema upgrades. Migrations[n] transforms a profile at SchemaVersion
	n into one at SchemaVersion n+1, so a profile saved months ago walks the
	whole chain on load and arrives current.

	Rules (docs/10-data-schema.md §3):
	  * PURE. Take a table, return a NEW table. Never mutate the argument, never
	    read os.time() or any service. This is what makes them fixture-testable,
	    and every migration ships with a test.
	  * ADDITIVE. Add and transform; never delete a player's dinosaurs. If a
	    migration can destroy content, it is the wrong migration.
	  * ORDERED and CONTIGUOUS. Migrations[1] takes v1 to v2 with no gaps.
	  * SET SchemaVersion. Each migration stamps its own output version.

	Adding a field with a sensible default does NOT need a migration - put it in
	ProfileTemplate and Reconcile fills it in. Migrations are for RESHAPING:
	renaming a key, splitting one field into two, changing units.

	Currently empty: we are at SchemaVersion 1 and nothing has shipped, so there
	is nothing to migrate from. The machinery and its tests exist now so that the
	first real migration is a five-line change rather than a design problem.

	Depends on: TableUtil. Depended on by: DataService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local TableUtil = require(Shared.Modules.TableUtil)

local Migrations = {}

--[[
	The chain. Index n migrates version n -> n+1.

	Worked example of the shape a real one takes - keep this comment when the
	first migration lands, it is the template:

		-- v1 -> v2: Boosts moved from {[id]=true} to {[id]=expiryTimestamp}
		Migrations.Chain[1] = function(data)
			local out = TableUtil.DeepCopy(data)
			local converted = {}
			for boostId, value in out.Boosts do
				converted[boostId] = if type(value) == "number" then value else 0
			end
			out.Boosts = converted
			out.SchemaVersion = 2
			return out
		end
]]
Migrations.Chain = {}

--[[
	Length of the chain counted from 1 upward, stopping at the first gap.

	Deliberately NOT `#Migrations.Chain`. The length operator is undefined on a
	table with a hole, so a chain of {[1]=f, [3]=f} - what you get by adding
	migration 3 and forgetting 2 - could report either 1 or 3 depending on the
	VM's internal array sizing. Walking explicitly is unambiguous, and
	Validate() below turns the gap into a loud boot error.
]]
function Migrations.ContiguousLength(): number
	local length = 0
	while Migrations.Chain[length + 1] ~= nil do
		length += 1
	end
	return length
end

--- The version a profile is at once the whole chain has run.
function Migrations.CurrentVersion(): number
	return Migrations.ContiguousLength() + 1
end

--[[
	Structural check on the chain itself, run by DataService at boot.
	Returns an error string, or nil when the chain is well formed.

	A migration stranded past a gap would never run, so a profile would load
	claiming an old version while the code assumed the new shape. That is a
	silent, server-wide data corruption, so it fails the boot instead.
]]
function Migrations.Validate(): string?
	local contiguous = Migrations.ContiguousLength()

	for key, value in Migrations.Chain do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return string.format("Migrations.Chain has a non-integer index %s", tostring(key))
		end
		if key > contiguous then
			return string.format(
				"Migrations.Chain[%d] sits past a gap (the chain runs 1..%d). "
					.. "Every version between must have a migration.",
				key,
				contiguous
			)
		end
		if type(value) ~= "function" then
			return string.format("Migrations.Chain[%d] is a %s, expected a function", key, typeof(value))
		end
	end

	return nil
end

--[[
	Walks `data` from its own SchemaVersion up to CurrentVersion().

	Returns (migratedData, stepsApplied, err):
	  * err is a string when the profile cannot be migrated. The caller must NOT
	    load a profile that returns an error - see DataService, which ends the
	    session without saving rather than risk clobbering it.

	A profile from the FUTURE (SchemaVersion above ours, i.e. a server rollback)
	is refused here rather than silently downgraded. Overwriting a player's newer
	save with older code is the one unrecoverable data bug, so it is refused at
	the earliest possible point.
]]
function Migrations.Apply(data): (any, number, string?)
	local target = Migrations.CurrentVersion()
	local version = data.SchemaVersion

	if type(version) ~= "number" then
		return data, 0, string.format("SchemaVersion is %s, expected a number", typeof(version))
	end

	if version > target then
		return data, 0, string.format("profile is version %d but this server only understands %d", version, target)
	end

	if version < 1 then
		return data, 0, string.format("SchemaVersion %d is below the first known version", version)
	end

	local current = data
	local applied = 0

	while current.SchemaVersion < target do
		local from = current.SchemaVersion
		local migrate = Migrations.Chain[from]

		if not migrate then
			return current, applied, string.format("no migration registered for version %d", from)
		end

		local ok, result = pcall(migrate, current)
		if not ok then
			return current, applied, string.format("migration %d -> %d errored: %s", from, from + 1, tostring(result))
		end

		-- A migration that fails to advance the version would loop forever.
		if type(result) ~= "table" or result.SchemaVersion ~= from + 1 then
			return current, applied, string.format(
				"migration %d -> %d returned SchemaVersion %s",
				from,
				from + 1,
				tostring(type(result) == "table" and result.SchemaVersion or "not a table")
			)
		end

		current = result
		applied += 1
	end

	return current, applied, nil
end

--[[
	Copies `source` into `target` IN PLACE, so the table's identity survives.

	This exists because ProfileStore holds a reference to profile.Data and saves
	whatever that reference points at. Replacing it with a migrated copy could
	leave ProfileStore saving the pre-migration table. Migrations stay pure and
	testable; this function is how their result gets applied safely.

	Keys absent from `source` are removed from `target`, so a migration that
	drops a field actually drops it.
]]
function Migrations.WriteInPlace(target, source)
	for key in target do
		if source[key] == nil then
			target[key] = nil
		end
	end
	for key, value in source do
		target[key] = if type(value) == "table" then TableUtil.DeepCopy(value) else value
	end
	return target
end

return Migrations
