--[[
	TutorialService  (ModuleScript)
	Location: ServerScriptService/Server/Services/TutorialService

	Server-side first-time player experience (steps in Shared/TutorialDefinitions).
	Other services call :Notify(player, event, data) when something happens; this
	service decides when a step is complete. Progress is saved in profile.Tutorial,
	so a player who leaves mid-tutorial resumes where they were.

	Hooks:
	  * New players' Nightmares don't appear until they press CREATE (AllowsAutoSummon)
	  * The Boss Portal offers the forgiving Tutorial Titan during the "Boss" step
	  * Remote TutorialAction "Skip" ends the tutorial at any time
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local TutorialDefinitions = require(Shared:WaitForChild("TutorialDefinitions"))

local TutorialService = {}

local STEPS = TutorialDefinitions.Steps

function TutorialService:Init(services)
	self.Services = services
	self.UIState = Net.Get("UIStateUpdate")
end

function TutorialService:Start()
	Net.Get("TutorialAction").OnServerEvent:Connect(function(player, action)
		if not self.Services.AntiExploitService:Allow(player, "TutorialAction") then
			return
		end
		if action == "Skip" then
			self:Finish(player, false)
		end
	end)

	-- Kill credit for "Defeat a Scrapling".
	self.Services.CombatService:OnDefeated(function(target, killer)
		if CollectionService:HasTag(target, "Enemy") and not CollectionService:HasTag(target, "Boss") then
			local owner = self.Services.CombatService:GetOwnerPlayer(killer)
			if owner then
				self:Notify(owner, "EnemyDefeated")
			end
		end
	end)
end

local function getState(self, player: Player)
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile or profile.Tutorial.Done then
		return nil, profile
	end
	return profile.Tutorial, profile
end

function TutorialService:CurrentStepId(player: Player): string?
	local tutorial = getState(self, player)
	if not tutorial then
		return nil
	end
	local step = STEPS[tutorial.Step]
	return step and step.Id or nil
end

function TutorialService:IsDone(player: Player): boolean
	local profile = self.Services.PlayerDataService:Get(player)
	return profile ~= nil and profile.Tutorial.Done == true
end

function TutorialService:AllowsAutoSummon(player: Player): boolean
	return self:CurrentStepId(player) ~= "Assemble"
end

-- Which boss mode the portal offers: "Tutorial", "Normal", or nil + reason.
function TutorialService:BossModeFor(player: Player): (string?, string?)
	local stepId = self:CurrentStepId(player)
	if not stepId then
		return "Normal", nil
	end
	if stepId == "Boss" then
		return "Tutorial", nil
	end
	local stepIndex = TutorialDefinitions.IndexOf(stepId)
	if stepIndex < TutorialDefinitions.IndexOf("Boss") then
		return nil, "Finish your training first (or skip the tutorial)."
	end
	return "Normal", nil
end

function TutorialService:Push(player: Player, toast: string?)
	self.Services.NightmareBuildService:PushState(player)
	if toast then
		self.UIState:FireClient(player, "Toast", { Text = toast })
	end
end

function TutorialService:Advance(player: Player)
	local tutorial = getState(self, player)
	if not tutorial then
		return
	end
	local finishedId = STEPS[tutorial.Step] and STEPS[tutorial.Step].Id
	tutorial.Step += 1
	tutorial.Flags = {}
	if finishedId then
		self.Services.GameAnalyticsService:TutorialStepDone(player, finishedId) -- onboarding funnel
	end

	if finishedId == "Assemble" then
		-- Minute 1-2: the creature comes alive.
		self.Services.NightmareSpawnService:SetSummoned(player, true)
		self.UIState:FireClient(player, "Toast", { Text = "IT'S ALIVE!" })
	end

	if tutorial.Step > #STEPS then
		self:Finish(player, true)
		return
	end
	self:Push(player, nil)
end

function TutorialService:Finish(player: Player, completed: boolean)
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile or profile.Tutorial.Done then
		return
	end
	profile.Tutorial.Done = true
	profile.Tutorial.Step = #STEPS + 1
	if completed then
		self.Services.ProgressionService:Award(player, Config.Progression.Rewards.TutorialComplete)
		self.Services.GameAnalyticsService:Rewards(player, Config.Progression.Rewards.TutorialComplete, "TutorialComplete")
	end
	if not self.Services.NightmareSpawnService:IsSummoned(player) then
		self.Services.NightmareSpawnService:SetSummoned(player, true)
	end
	self.Services.PlayerDataService:SaveNow(player)
	self:Push(player, completed and "Tutorial complete! The Forge is yours. (+100 coins)" or "Tutorial skipped.")
end

function TutorialService:Notify(player: Player, event: string, data)
	local tutorial = getState(self, player)
	if not tutorial then
		return
	end
	local step = STEPS[tutorial.Step]
	if not step then
		return
	end

	if event == "TutorialBossWon" and data then
		tutorial.RewardPart = data.PartId
	end

	-- The final step completes only when the reward part is on the ACTIVE build.
	if step.Id == "Equip" and event == "BuildSaved" then
		local profile = self.Services.PlayerDataService:Get(player)
		if data and data.Slot == profile.ActiveBuild and tutorial.RewardPart then
			for _, id in data.Build.Parts do
				if id == tutorial.RewardPart then
					self:Advance(player)
					return
				end
			end
		end
		return
	end

	if not table.find(step.Needs, event) then
		return
	end
	tutorial.Flags = tutorial.Flags or {}
	if tutorial.Flags[event] then
		return
	end
	tutorial.Flags[event] = true
	for _, need in step.Needs do
		if not tutorial.Flags[need] then
			self:Push(player, nil) -- show partial progress
			return
		end
	end
	self:Advance(player)
end

return TutorialService
