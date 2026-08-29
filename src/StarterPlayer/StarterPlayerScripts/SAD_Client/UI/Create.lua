--!nonstrict
--[[
	Create
	StarterPlayerScripts/SAD_Client/UI/Create  (ModuleScript)

	A declarative wrapper over Instance.new, so UI reads as a tree instead of
	forty lines of property assignment and manual parenting.

		local bar = Create("Frame", {
			Name = "TopBar",
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = Theme.Color.Surface,
			Children = {
				Create("UICorner", { CornerRadius = Theme.Radius.Medium }),
				Create("TextLabel", { Text = "Fossils" }),
			},
			Events = { Activated = function() ... end },
		})

	Parent is assigned LAST, after every property and child. Parenting first
	makes Roblox re-render on each subsequent property change, which is the
	standard way UI construction quietly becomes a frame hitch.

	Depends on: nothing.
]]

local function Create(className: string, props: { [string]: any }?)
	local instance = Instance.new(className)
	local properties = props or {}

	local children = properties.Children
	local events = properties.Events
	local parent = properties.Parent

	for key, value in properties do
		if key ~= "Children" and key ~= "Events" and key ~= "Parent" then
			instance[key] = value
		end
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	if events then
		for signalName, handler in events do
			instance[signalName]:Connect(handler)
		end
	end

	-- Last, always.
	if parent then
		instance.Parent = parent
	end

	return instance
end

return Create
