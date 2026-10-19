--[[
	ExplorationService  (ModuleScript)
	Location: ServerScriptService/Server/Services/ExplorationService

	Rewards for walking the world (Shared/WorldDefinitions):
	  Relics     hidden along each route (ProximityPrompt "Relic", attribute RelicId).
	             Each can be taken once per player (profile.Relics) for
	             WorldDefinitions.RelicReward, with its lore shown in a toast.
	  Waystones  ProximityPrompt "Waystone", attribute Target:
	               "Hub"      back to the Forge (always allowed)
	               regionId   from the Forge to that boss's gate, once you've beaten
	                          the boss at least once (the shortcut you earn)
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))
local BossDefinitions = require(Shared:WaitForChild("BossDefinitions"))

local ExplorationService = {}

local lastTravel: { [Player]: number } = {}
local TRAVEL_COOLDOWN = 3

function ExplorationService:Init(services)
	self.Services = services
	self.UIState = Net.Get("UIStateUpdate")
end

local function toast(self, player: Player, text: string)
	self.UIState:FireClient(player, "Toast", { Text = text })
end

function ExplorationService:CountRelics(profile): number
	local n = 0
	for id in profile.Relics or {} do
		if WorldDefinitions.RelicById[id] then
			n += 1
		end
	end
	return n
end

function ExplorationService:TakeRelic(player: Player, relicId)
	local relic = type(relicId) == "string" and WorldDefinitions.RelicById[relicId]
	local profile = self.Services.PlayerDataService:Get(player)
	if not relic or not profile then
		return
	end
	profile.Relics = profile.Relics or {}
	if profile.Relics[relicId] then
		toast(self, player, ("You already took the %s."):format(relic.Name))
		return
	end
	profile.Relics[relicId] = true
	local reward = WorldDefinitions.RelicReward
	self.Services.ProgressionService:Award(player, reward)
	self.Services.GameAnalyticsService:Rewards(player, reward, "Relic")
	self.Services.GameAnalyticsService:Event(player, "RelicFound", 1, { relicId })
	toast(self, player, ('RELIC FOUND (%d/%d): %s. "%s"  +%d coins, +%d Essence, +%d XP'):format(self:CountRelics(profile), #WorldDefinitions.Relics, relic.Name, relic.Lore, reward.Coins, reward.Essence, reward.XP))
	self.Services.NightmareBuildService:PushState(player)
end

function ExplorationService:Travel(player: Player, target)
	if type(target) ~= "string" then
		return
	end
	local now = os.clock()
	if lastTravel[player] and now - lastTravel[player] < TRAVEL_COOLDOWN then
		return
	end
	if self.Services.BossService:GetEncounter(player) or self.Services.DuelService:IsInMatch(player) then
		toast(self, player, "Finish your fight first.")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local destination
	if target == "Hub" then
		destination = CFrame.lookAt(Config.World.HubSpawn, Vector3.new(0, Config.World.HubSpawn.Y, 0))
	else
		local region = WorldDefinitions.Regions[target]
		if not region or not region.BossId then
			return
		end
		local profile = self.Services.PlayerDataService:Get(player)
		local record = profile and profile.Bosses and profile.Bosses[region.BossId]
		local beaten = type(record) == "table" and ((tonumber(record.Wins) or 0) > 0 or BossDefinitions.RealWins(record) > 0)
		if Config.Dev.UnlockWaystonesInStudio and RunService:IsStudio() then
			beaten = true
		end
		if not beaten then
			local def = BossDefinitions.Get(region.BossId)
			toast(self, player, ("This waystone wakes once you've beaten %s. Walk the path for now!"):format(def and def.DisplayName or "its boss"))
			return
		end
		destination = WorldDefinitions.GatePlaza(target) * CFrame.new(0, 3, 10)
	end
	lastTravel[player] = now
	character:PivotTo(destination)
	self.Services.NightmareSpawnService:TeleportNightmare(player, destination * CFrame.new(5, 0, 4))
end

function ExplorationService:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name == "Relic" then
			self:TakeRelic(player, prompt:GetAttribute("RelicId"))
		elseif prompt.Name == "Waystone" then
			self:Travel(player, prompt:GetAttribute("Target"))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
	end)
end

return ExplorationService
