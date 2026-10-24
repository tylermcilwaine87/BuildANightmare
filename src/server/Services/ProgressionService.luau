--[[
	ProgressionService  (ModuleScript)
	Location: ServerScriptService/Server/Services/ProgressionService

	XP, levels and currencies (Nightmare Coins, Nightmare Essence).
	Level-gated unlocks arrive in Phase 5; XP and currency are earned from Phase 2.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local ProgressionService = {}

function ProgressionService:Init(services)
	self.Services = services
	self.UIState = Net.Get("UIStateUpdate")
end

-- rewards = { XP = n, Coins = n, Essence = n } EARNED in play (the SHOP's perks multiply
-- coins and XP here: 2x Coins, VIP, Premium; bought coins never come through here).
-- Returns a summary for the reward screen (with the multiplied amounts).
function ProgressionService:Award(player: Player, rewards)
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile then
		return nil
	end
	local shop = self.Services.MonetizationService
	local coins = math.floor((rewards.Coins or 0) * (shop and shop:CoinMultiplier(player) or 1) + 0.5)
	local xp = math.floor((rewards.XP or 0) * (shop and shop:XPMultiplier(player) or 1) + 0.5)
	rewards = table.clone(rewards)
	rewards.Coins, rewards.XP = coins, xp
	local levelBefore = profile.Level
	profile.Coins += rewards.Coins or 0
	profile.Essence += rewards.Essence or 0
	profile.ArenaTokens += rewards.ArenaTokens or 0
	profile.XP += rewards.XP or 0

	local maxLevel = Config.Progression.MaxLevel
	while profile.Level < maxLevel and profile.XP >= Config.Progression.XPForLevel(profile.Level) do
		profile.XP -= Config.Progression.XPForLevel(profile.Level)
		profile.Level += 1
	end
	if profile.Level >= maxLevel then
		profile.XP = 0
	end

	if profile.Level > levelBefore then
		self.UIState:FireClient(player, "LevelUp", { Level = profile.Level })
		self.Services.GameAnalyticsService:Event(player, "LevelUp", profile.Level)
	end

	return {
		XP = rewards.XP or 0,
		Coins = rewards.Coins or 0,
		Essence = rewards.Essence or 0,
		ArenaTokens = rewards.ArenaTokens or 0,
		LevelBefore = levelBefore,
		LevelAfter = profile.Level,
	}
end

return ProgressionService
