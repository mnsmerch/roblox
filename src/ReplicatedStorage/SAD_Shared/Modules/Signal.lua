--!nonstrict
--[[
	Signal
	ReplicatedStorage/SAD_Shared/Modules/Signal  (ModuleScript)

	Lightweight event object for server-internal and client-internal messaging.
	Deliberately NOT a replacement for RemoteEvents - this never crosses the
	network. Services use it to broadcast "an egg hatched" without every other
	service having to require them directly.

		local hatched = Signal.new()
		hatched:Connect(function(player, dino) ... end)
		hatched:Fire(player, dino)

	Handlers run in their own thread (task.spawn), so one erroring listener can
	never block the others or the firing code.

	Stored as a singly linked list: connect is O(1), fire is O(n) with no table
	allocation per fire. Disconnect during a Fire is safe - the next node is
	captured before each handler runs.

	--!nonstrict because the metatable OOP pattern fights the strict checker for
	no practical benefit. See docs/09-tech-architecture.md.

	Depends on: nothing.
]]

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, fn)
	return setmetatable({
		Connected = true,
		_signal = signal,
		_fn = fn,
		_next = nil,
	}, Connection)
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false

	local signal = self._signal
	if signal then
		if signal._head == self then
			signal._head = self._next
		else
			local prev = signal._head
			while prev and prev._next ~= self do
				prev = prev._next
			end
			if prev then
				prev._next = self._next
			end
		end
	end

	self._signal = nil
	self._fn = nil
	self._next = nil
end

Connection.Destroy = Connection.Disconnect

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _head = nil }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect expects a function")
	local connection = Connection.new(self, fn)
	connection._next = self._head
	self._head = connection
	return connection
end

--- Fires once, then disconnects itself before the handler runs.
function Signal:Once(fn)
	assert(type(fn) == "function", "Signal:Once expects a function")
	local connection
	connection = self:Connect(function(...)
		if connection.Connected then
			connection:Disconnect()
		end
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	local node = self._head
	while node do
		-- Capture next BEFORE dispatch: the handler may disconnect itself.
		local nextNode = node._next
		if node.Connected then
			task.spawn(node._fn, ...)
		end
		node = nextNode
	end
end

--- Yields the calling thread until the next Fire, returning its arguments.
function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	local node = self._head
	while node do
		local nextNode = node._next
		node.Connected = false
		node._signal = nil
		node._fn = nil
		node._next = nil
		node = nextNode
	end
	self._head = nil
end

Signal.Destroy = Signal.DisconnectAll

return Signal
