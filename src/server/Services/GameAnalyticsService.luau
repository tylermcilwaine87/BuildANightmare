--[[
	GameAnalyticsService  (ModuleScript)
	Location: ServerScriptService/Server/Services/GameAnalyticsService

	ANALYTICS (Phase 7): a thin, safe wrapper around Roblox's AnalyticsService.
	Results appear on the Creator Dashboard → your experience → Analytics
	(Onboarding, Economy, Custom events) once real players play the PUBLISHED game.

	Every call is wrapped in pcall: analytics can never break gameplay.

	  Onboarding funnel  1 Joined (new player) · 2 Created a Nightmare · 3 Trained ·
	                     4 Commanded · 5 First Scrapling · 6 First boss · 7 Equipped reward
	                     (tutorial complete). Roblox counts each step once per player.
	  Economy            Coins / Essence / ArenaTokens: Sources (rewards) and Sinks (crafting).
	  Custom events      BossWin, BossFail, DuelEnd, MutationFound, PartCrafted,
	                     ChallengeComplete, LevelUp (see the call sites).
]]

local AnalyticsService = game:GetService("AnalyticsService")

local GameAnalyticsService = {}

-- The tutorial's steps, in order, as onboarding funnel steps 2..7 (step 1 = joined).
GameAnalyticsService.TutorialSteps = {
	Assemble = { 2, "Created a Nightmare" },
	Train = { 3, "Trained" },
	Command = { 4, "Commanded the Nightmare" },
	Defeat = { 5, "First Scrapling defeated" },
	Boss = { 6, "First boss defeated" },
	Equip = { 7, "Equipped a reward (tutorial complete)" },
}

function GameAnalyticsService:Init(services)
	self.Services = services
end

-- { a, b, c } -> Roblox's custom field table (up to 3 values, shown as breakdowns).
local function fields(values)
	if not values then
		return nil
	end
	local result = {}
	local keys = { Enum.AnalyticsCustomFieldKeys.CustomField01, Enum.AnalyticsCustomFieldKeys.CustomField02, Enum.AnalyticsCustomFieldKeys.CustomField03 }
	for i, value in values do
		if keys[i] and value ~= nil then
			result[keys[i].Name] = tostring(value)
		end
	end
	return result
end

local function safe(label: string, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[Analytics] %s failed: %s"):format(label, tostring(err)))
	end
end

function GameAnalyticsService:Onboarding(player: Player, step: number, name: string)
	if player.UserId <= 0 then
		return -- Studio test players
	end
	safe("onboarding", AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, step, name)
end

-- Called by TutorialService when a step is finished.
function GameAnalyticsService:TutorialStepDone(player: Player, stepId: string)
	local entry = self.TutorialSteps[stepId]
	if entry then
		self:Onboarding(player, entry[1], entry[2])
	end
end

-- flow: "Source" (earned) or "Sink" (spent). reason: e.g. "BossVictory", "Crafting".
function GameAnalyticsService:Economy(player: Player, flow: string, currency: string, amount: number, reason: string)
	if player.UserId <= 0 or amount <= 0 then
		return
	end
	local profile = self.Services.PlayerDataService:Get(player)
	local balance = profile and profile[currency] or 0
	safe("economy", AnalyticsService.LogEconomyEvent, AnalyticsService, player, Enum.AnalyticsEconomyFlowType[flow], currency, amount, balance, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, reason)
end

-- Logs every currency in a rewards table ({ Coins, Essence, ArenaTokens, XP }).
function GameAnalyticsService:Rewards(player: Player, rewards, reason: string)
	for _, currency in { "Coins", "Essence", "ArenaTokens" } do
		self:Economy(player, "Source", currency, rewards[currency] or 0, reason)
	end
end

-- name: event name; value: optional number; values: up to 3 breakdown values.
function GameAnalyticsService:Event(player: Player, name: string, value: number?, values)
	if player.UserId <= 0 then
		return
	end
	safe("event " .. name, AnalyticsService.LogCustomEvent, AnalyticsService, player, name, value or 1, fields(values))
end

function GameAnalyticsService:Start()
	-- Onboarding step 1: a brand-new player joined (their tutorial hasn't started).
	local Players = game:GetService("Players")
	local function onPlayer(player: Player)
		task.spawn(function()
			local profile = self.Services.PlayerDataService:WaitFor(player, 30)
			if profile and not profile.Tutorial.Done and profile.Tutorial.Step == 1 then
				self:Onboarding(player, 1, "Joined")
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return GameAnalyticsService
