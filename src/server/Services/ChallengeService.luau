--[[
	ChallengeService  (ModuleScript)
	Location: ServerScriptService/Server/Services/ChallengeService

	Daily / weekly challenges (definitions + rotation in Shared/ChallengeDefinitions).
	  * Other services call :Notify(player, event, amount?, data?) when something happens.
	  * Each player's profile.Challenges[period] = { Key, List = { { Id, Progress, Done } } }
	    is refreshed when the period key changes (new day / week), so nobody keeps
	    yesterday's challenges.
	  * A finished challenge pays its period's rewards ONCE (Done flag set before paying)
	    and saves right away.
	  * Progress updates go to the client as a small UIStateUpdate("Challenges", table)
	    message instead of a full profile snapshot (abilities fire often).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ChallengeDefinitions = require(Shared:WaitForChild("ChallengeDefinitions"))

local ChallengeService = {}

function ChallengeService:Init(services)
	self.Services = services
	self.UIState = Net.Get("UIStateUpdate")
end

-- Makes sure the profile holds the CURRENT day's and week's challenges.
-- Returns true if anything was rolled over.
function ChallengeService:Refresh(profile): boolean
	local changed = false
	local now = os.time()
	for period in ChallengeDefinitions.Periods do
		local key = ChallengeDefinitions.PeriodInfo(period, now)
		local current = profile.Challenges[period]
		if type(current) ~= "table" or current.Key ~= key or type(current.List) ~= "table" then
			local list = {}
			for _, id in ChallengeDefinitions.Pick(period, key) do
				table.insert(list, { Id = id, Progress = 0, Done = false })
			end
			profile.Challenges[period] = { Key = key, List = list }
			changed = true
		end
	end
	return changed
end

function ChallengeService:Push(player: Player, profile)
	self.UIState:FireClient(player, "Challenges", profile.Challenges)
end

function ChallengeService:Notify(player: Player?, event: string, amount: number?, data)
	local profile = player and self.Services.PlayerDataService:Get(player)
	if not profile then
		return
	end
	local changed = self:Refresh(profile)
	local completed = {}
	for period in ChallengeDefinitions.Periods do
		for _, entry in profile.Challenges[period].List do
			local def = ChallengeDefinitions.Get(entry.Id)
			if def and not entry.Done and def.Event == event and (not def.Match or def.Match(data)) then
				entry.Progress = math.min(def.Target, entry.Progress + (amount or 1))
				changed = true
				if entry.Progress >= def.Target then
					entry.Done = true -- set BEFORE paying: rewards can never be paid twice
					table.insert(completed, def)
				end
			end
		end
	end

	for _, def in completed do
		local rewards = ChallengeDefinitions.Periods[def.Period].Rewards
		self.Services.ProgressionService:Award(player, rewards)
		self.Services.GameAnalyticsService:Rewards(player, rewards, "Challenge")
		self.Services.GameAnalyticsService:Event(player, "ChallengeComplete", 1, { def.Id, def.Period })
		self.UIState:FireClient(player, "Toast", {
			Text = ("%s CHALLENGE COMPLETE: %s  (+%d coins, +%d Essence, +%d XP)"):format(string.upper(def.Period), def.Text, rewards.Coins, rewards.Essence, rewards.XP),
		})
	end
	if #completed > 0 then
		self.Services.PlayerDataService:SaveNow(player)
		self.Services.NightmareBuildService:PushState(player) -- coins / Essence / level changed
	elseif changed then
		self:Push(player, profile)
	end
end

function ChallengeService:Start()
	-- Scrapling kills (TrainingService tags them EnemyType = "Scrapling").
	self.Services.CombatService:OnDefeated(function(target, killer)
		if CollectionService:HasTag(target, "Enemy") and target:GetAttribute("EnemyType") == "Scrapling" then
			self:Notify(self.Services.CombatService:GetOwnerPlayer(killer), "EnemyDefeated")
		end
	end)

	-- New day / week while playing: roll over and tell the client.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local profile = self.Services.PlayerDataService:Get(player)
				if profile and self:Refresh(profile) then
					self:Push(player, profile)
				end
			end
		end
	end)

	-- On join: make sure the challenges are current before the client asks for state.
	local function onPlayer(player: Player)
		task.spawn(function()
			local profile = self.Services.PlayerDataService:WaitFor(player, 30)
			if profile and self:Refresh(profile) then
				self:Push(player, profile)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return ChallengeService
