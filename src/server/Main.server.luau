--[[
	Main  (Script)
	Location: ServerScriptService/Server/Main

	Server bootstrap. Creates remotes, requires every service, then runs
	Init(services) on all of them (wire-up, no yielding) followed by Start() (connect
	events, spawn loops). Services talk to each other through the `services` table, so
	there are no circular requires.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))

Net.Setup()

local ServicesFolder = script.Parent:WaitForChild("Services")

local LOAD_ORDER = {
	"AntiExploitService",
	"WorldBuilder",
	"PlayerDataService",
	"InventoryService",
	"ProgressionService",
	"HitDetectionService",
	"TelegraphService",
	"NavigationService",
	"StatusService",
	"HandlerService",
	"RagdollService",
	"CombatService",
	"MeleeService",
	"AbilityService",
	"UltimateService",
	"NightmareAIService",
	"PossessionService",
	"SyncService",
	"PassiveService",
	"NightmareSpawnService",
	"NightmareBuildService",
	"TutorialService",
	"TrainingService",
	"BossRewardService",
	"BossService",
	"DuelService",
	"CraftingService",
	"ChallengeService",
	"PartyService",
	"LeaderboardService",
	"RankedService",
	"ShowcaseService",
	"ExplorationService",
	"GymService",
	"MonetizationService",
	"GameAnalyticsService",
}

local services = {}
for _, name in LOAD_ORDER do
	services[name] = require(ServicesFolder:WaitForChild(name))
end

for _, name in LOAD_ORDER do
	local service = services[name]
	if service.Init then
		service:Init(services)
	end
end

for _, name in LOAD_ORDER do
	local service = services[name]
	if service.Start then
		-- One failing service is reported loudly but never stops the others starting.
		local ok, err = pcall(service.Start, service)
		if not ok then
			warn(("[BuildANightmare] %s failed to start: %s"):format(name, tostring(err)))
		end
	end
end

-- Studio only: a bridge to the live services so the command bar (its own Lua VM) can
-- drive real systems in tests:
--   game.ServerStorage.DevBridge:Invoke("CombatService", "KnockdownChance", attacker, target)
-- Never created on live servers.
if game:GetService("RunService"):IsStudio() then
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "DevBridge"
	bridge.OnInvoke = function(serviceName: string, method: string, ...)
		local service = services[serviceName]
		return service[method](service, ...)
	end
	bridge.Parent = game:GetService("ServerStorage")
end

print(("[BuildANightmare] Server ready — %s"):format(Config.Version))
