--!nonstrict
--[[
	Patch
	ReplicatedStorage/SAD_Shared/Modules/Patch  (ModuleScript)

	Structural diffing and patch application, shared by the server that produces
	deltas and the client that consumes them.

	It lives here rather than being written twice because the two sides have to
	agree EXACTLY. A producer that emits a numeric key as a string, or a
	consumer that mishandles a removal, desyncs a player's inventory in a way
	that looks like a gameplay bug and is nearly impossible to reproduce. One
	implementation, one set of tests, and the round-trip property - apply the
	diff to the old value and you get the new one - asserted directly.

	A patch is:
		{ Path = { key, ... }, Value = any }    -- set
		{ Path = { key, ... }, Remove = true }  -- delete

	Path keys keep their NATIVE type. Stringifying a numeric key would make the
	consumer write Incubators["1"] where the producer meant Incubators[1].

	Depends on: TableUtil.
]]

local TableUtil = require(script.Parent.TableUtil)

local Patch = {}

--[[
	How deep Diff walks before shipping a subtree wholesale.

	3 gives per-field granularity for every shape in the profile schema:
	Dinos -> uid -> field, and Quests -> Daily -> questId -> field. Deeper costs
	comparisons for no payload saving; shallower resends a whole dinosaur
	because one star changed.
]]
Patch.DefaultDepth = 3

local function emit(patches, path, value)
	if value == nil then
		table.insert(patches, { Path = path, Remove = true })
	else
		table.insert(patches, {
			Path = path,
			Value = if type(value) == "table" then TableUtil.DeepCopy(value) else value,
		})
	end
end

local function diffInto(patches, path, previous, current, depth)
	if previous == current then
		return
	end

	local prevIsTable = type(previous) == "table"
	local currIsTable = type(current) == "table"

	if prevIsTable and currIsTable then
		if depth > 0 then
			for key, value in current do
				local child = table.clone(path)
				table.insert(child, key)
				diffInto(patches, child, previous[key], value, depth - 1)
			end
			for key in previous do
				if current[key] == nil then
					local child = table.clone(path)
					table.insert(child, key)
					emit(patches, child, nil)
				end
			end
			return
		end

		-- Depth exhausted: ship the subtree if anything inside it moved.
		if not TableUtil.DeepEquals(previous, current) then
			emit(patches, path, current)
		end
		return
	end

	emit(patches, path, current)
end

--[[
	Patches that turn `previous` into `current`.

	`basePath` prefixes every emitted path, so a caller diffing one profile key
	passes { "Fossils" } and gets absolute paths back.
]]
function Patch.Diff(previous, current, basePath, depth)
	local patches = {}
	diffInto(patches, basePath or {}, previous, current, depth or Patch.DefaultDepth)
	return patches
end

--- Applies one patch, creating intermediate tables as needed.
function Patch.Apply(root, patch)
	local path = patch.Path
	if type(path) ~= "table" or #path == 0 then
		return false
	end

	local node = root
	for index = 1, #path - 1 do
		local key = path[index]
		local child = node[key]
		if type(child) ~= "table" then
			child = {}
			node[key] = child
		end
		node = child
	end

	local last = path[#path]
	if patch.Remove then
		node[last] = nil
	else
		node[last] = patch.Value
	end
	return true
end

function Patch.ApplyAll(root, patches)
	local applied = 0
	for _, patch in patches do
		if Patch.Apply(root, patch) then
			applied += 1
		end
	end
	return applied
end

--[[
	True when two paths overlap in either direction.

	An observer on {"Dinos"} must hear about {"Dinos","ab12","Stars"}, and one
	on that exact field must hear about a wholesale {"Dinos"} replacement.
]]
function Patch.PathsOverlap(a, b)
	local shorter = math.min(#a, #b)
	for index = 1, shorter do
		if a[index] ~= b[index] then
			return false
		end
	end
	return true
end

--- Reads a value at `path`, or nil if any step is missing.
function Patch.Read(root, path)
	local node = root
	for _, key in path do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

return Patch
