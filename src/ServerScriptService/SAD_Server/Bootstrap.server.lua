--[[
	Bootstrap
	ServerScriptService/SAD_Server/Bootstrap  (Script)

	The ONLY Script on the server. Everything else is a ModuleScript, which
	means load order is explicit here rather than emergent, and a circular
	dependency surfaces as an error on this line instead of a mystery later.

	Boot sequence:
	  1. Wait for shared modules to replicate.
	  2. Net.Init() - publishes ReplicatedStorage/SAD_Net so clients can connect.
	  3. Require every service in SERVICE_ORDER that actually exists on disk.
	  4. Init(app) on all of them.
	  5. Start(app) on all of them.

	Services not yet built are SKIPPED, not errors. That is what lets us add one
	service per build step without touching this file - the order list is the
	full V1 roster from docs/09-tech-architecture.md §2, and entries light up as
	they are created.

	Service contract:
		local MyService = {}
		function MyService.Init(app) end   -- wire up state; do not call others
		function MyService.Start(app) end  -- others exist now; safe to use them
		return MyService

	`app` is injected rather than having services require each other, because
	StealService needs ParkService and ParkService needs StealService, and a
	direct require in both directions deadlocks.

	Depends on: Log, Net, GameConfig. Depended on by: every service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = Shared:WaitForChild("Config")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Log = require(Modules:WaitForChild("Log"))
local Net = require(Modules:WaitForChild("Net"))

--[[
	Full V1 service roster in dependency order (docs/09 §2).
	Do not reorder casually - SecurityService must exist before anything that
	validates input, and DataService before anything that reads a profile.
]]
local SERVICE_ORDER = {
	"SecurityService", -- Step 8
	"DataService", -- Step 2
	"PlayerDataService", -- Step 2
	"EconomyService", -- Step 12
	"AnalyticsService", -- Step 24
	"NotificationService", -- Step 16
	"BroadcastService", -- Step 16
	"ParkService", -- Step 6
	"DinosaurService", -- Step 11
	"MutationService", -- Step 11
	"IncubationService", -- Step 11
	"NestService", -- Step 7
	"WildAIService", -- Step 9
	"EggService", -- Step 8
	"StealService", -- Step 15
	"UpgradeService", -- Step 13
	"RebirthService", -- Step 20
	"IndexService", -- Step 19
	"QuestService", -- Step 19
	"DailyService", -- Step 19
	"WeatherService", -- Step 17
	"EventService", -- Step 18
	"PurchaseService", -- Step 21
	"LeaderboardService", -- Step 22
}

local servicesFolder = script.Parent:WaitForChild("Services")

local registry: { [string]: any } = {}
local loadedOrder: { string } = {}

--- Injected into every Init/Start. See Types.App.
local app
app = {
	IsServer = true,
	Log = Log,
	Net = Net,
	Config = Shared.Config,
	Get = function(name: string): any
		local service = registry[name]
		if not service then
			error(
				string.format(
					"Service '%s' is not loaded. It may not be built yet, or it is missing from SERVICE_ORDER.",
					name
				),
				2
			)
		end
		return service
	end,
}

--[[
	Runs `fn`, and on failure either aborts the boot (StrictBoot, the Studio
	default) or logs loudly and continues. Continuing matters in production: one
	broken service should degrade the experience, not take it offline.
]]
local function guarded(phase: string, name: string, fn: () -> ()): boolean
	local ok, err = pcall(fn)
	if ok then
		return true
	end

	Log.error("Boot", "%s failed for %s: %s", phase, name, tostring(err))
	if GameConfig.StrictBoot then
		error(string.format("[SAD] Boot aborted: %s failed for %s\n%s", phase, name, tostring(err)), 0)
	end
	return false
end

local startedAt = os.clock()

Log.banner(string.format("%s v%s starting", GameConfig.GameName, GameConfig.Version))

-- Phase 0: publish the remote tree before any service tries to bind to it.
Net.Init()

-- Phase 1: require
local skipped: { string } = {}
for _, name in SERVICE_ORDER do
	local moduleScript = servicesFolder:FindFirstChild(name)
	if not moduleScript then
		table.insert(skipped, name)
		continue
	end

	guarded("Require", name, function()
		local service = require(moduleScript)
		assert(type(service) == "table", name .. " must return a table")
		registry[name] = service
		table.insert(loadedOrder, name)
	end)
end

if #skipped > 0 then
	Log.debug("Boot", "Not built yet (%d): %s", #skipped, table.concat(skipped, ", "))
end

-- Phase 2: Init - set up internal state only, do not reach for other services.
for _, name in loadedOrder do
	local service = registry[name]
	if type(service.Init) == "function" then
		guarded("Init", name, function()
			service.Init(app)
		end)
	end
end

-- Phase 3: Start - every service now exists, so cross-service calls are safe.
for _, name in loadedOrder do
	local service = registry[name]
	if type(service.Start) == "function" then
		guarded("Start", name, function()
			service.Start(app)
		end)
	end
end

Log.info("Boot", "Loaded %d service(s): %s", #loadedOrder, table.concat(loadedOrder, ", "))
Log.banner(string.format("Server boot complete (%.0f ms)", (os.clock() - startedAt) * 1000))
