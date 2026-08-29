--!nonstrict
--[[
	Trove
	ReplicatedStorage/SAD_Shared/Modules/Trove  (ModuleScript)

	Cleanup bookkeeping. Anything with a lifetime - a guardian's connections, a
	park's parts, a chase's tween - goes into a Trove, and one :Clean() releases
	all of it in reverse order.

	This exists because the single most common source of memory leaks and ghost
	behaviour in a game like this is a connection that outlives the thing it was
	watching. Guardians in particular are spawned and destroyed constantly.

		local trove = Trove.new()
		trove:Add(model)                       -- :Destroy()
		trove:Connect(hum.Died, onDied)        -- :Disconnect()
		trove:Add(function() print("bye") end) -- called
		trove:Clean()

	Handles: Instance, RBXScriptConnection, thread, function, and any table
	exposing Destroy or Disconnect (which includes our own Signal).

	Depends on: nothing.
]]

local Trove = {}
Trove.__index = Trove

local CALL = "\0call" -- sentinel: the object is a function to invoke
local THREAD = "\0thread" -- sentinel: the object is a thread to cancel

local function resolveMethod(object, explicit)
	if explicit ~= nil then
		return explicit
	end

	local kind = typeof(object)
	if kind == "function" then
		return CALL
	elseif kind == "thread" then
		return THREAD
	elseif kind == "RBXScriptConnection" then
		return "Disconnect"
	elseif kind == "Instance" then
		return "Destroy"
	elseif kind == "table" then
		if typeof(object.Destroy) == "function" then
			return "Destroy"
		elseif typeof(object.Disconnect) == "function" then
			return "Disconnect"
		end
	end

	return nil
end

local function cleanupOne(entry)
	local object, method = entry[1], entry[2]
	if method == CALL then
		object()
	elseif method == THREAD then
		-- Cancelling an already-finished thread throws; that is not an error here.
		pcall(task.cancel, object)
	else
		object[method](object)
	end
end

function Trove.new()
	return setmetatable({ _objects = {} }, Trove)
end

--- Tracks an object. Returns it, so you can wrap creation inline.
function Trove:Add(object, cleanupMethod)
	local method = resolveMethod(object, cleanupMethod)
	assert(
		method ~= nil,
		"Trove:Add - no cleanup method for a " .. typeof(object) .. "; pass one explicitly"
	)
	table.insert(self._objects, { object, method })
	return object
end

--- Convenience for the most common case.
function Trove:Connect(signal, handler)
	return self:Add(signal:Connect(handler))
end

--- A child Trove, cleaned when this one is.
function Trove:Extend()
	return self:Add(Trove.new())
end

--- Cleans and forgets one tracked object. Returns whether it was found.
function Trove:Remove(object)
	for index, entry in self._objects do
		if entry[1] == object then
			table.remove(self._objects, index)
			cleanupOne(entry)
			return true
		end
	end
	return false
end

--- Cleans everything, newest first. The Trove stays usable afterwards.
function Trove:Clean()
	local objects = self._objects
	self._objects = {}
	for index = #objects, 1, -1 do
		cleanupOne(objects[index])
	end
end

Trove.Destroy = Trove.Clean

return Trove
