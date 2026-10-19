--[[
	BossRewardService  (ModuleScript)
	Location: ServerScriptService/Server/Services/BossRewardService

	Rolls and grants boss loot. Called ONLY by BossService, once per completed encounter
	(the encounter's Rewarded flag guarantees "exactly once"). Players can't influence
	it: no client input is read here.

	  1. Roll a rarity with Config.Loot.Odds[mode].
	  2. LEGENDARY PITY: eligible victories without a Legendary are counted per player.
	     The 25th eligible victory in a row is a guaranteed Legendary; the counter resets
	     whenever a Legendary drops. Tutorial victories are not eligible.
	     Leaving or disconnecting mid-fight never touches the counter: it only changes
	     here, at victory, in the same profile write as the item itself.
	  3. Pick a random part of that rarity from the boss's own LootPool (falls back to
	     a lower rarity if the pool has none).
	  3b. The part may roll a MUTATION (Config.Mutations.Chance per difficulty; never on
	     Tutorial drops) and is recorded in the Mutation Book.
	  4. Grant part + XP/coins/essence, record boss stats, save immediately.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BossDefinitions = require(Shared:WaitForChild("BossDefinitions"))
local RarityDefinitions = require(Shared:WaitForChild("RarityDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))

local BossRewardService = {}

local random = Random.new()

function BossRewardService:Init(services)
	self.Services = services
end

local function rollRarity(odds): string
	local total = 0
	for _, rarity in RarityDefinitions.Order do
		total += odds[rarity] or 0
	end
	local roll = random:NextNumber(0, total)
	for _, rarity in RarityDefinitions.Order do
		roll -= odds[rarity] or 0
		if roll <= 0 then
			return rarity
		end
	end
	return "Uncommon"
end

local function pickFromPool(pool, rarity: string): (string?, string)
	local rank = RarityDefinitions.Info[rarity].Rank
	for r = rank, 1, -1 do
		local name = RarityDefinitions.Order[r]
		local list = pool[name]
		if list and #list > 0 then
			return list[random:NextInteger(1, #list)], name
		end
	end
	return nil, rarity
end

--[[
	Returns the reward summary sent to the client:
	{ BossId, Mode, Time, BestTime, Parts = { {Id, Rarity, IsNew, Pity} }, Progress = {...},
	  Pity = { Count, Threshold } }
]]
function BossRewardService:GrantVictory(player: Player, bossId: string, mode: string, fightTime: number)
	local profile = self.Services.PlayerDataService:Get(player)
	local boss = BossDefinitions.Get(bossId)
	if not profile or not boss then
		return nil
	end

	local rarity
	local pityTriggered = false
	if mode == "Tutorial" then
		rarity = Config.Loot.TutorialGuaranteedRarity
	else
		profile.Pity.Legendary += 1
		if profile.Pity.Legendary >= Config.Loot.LegendaryPity then
			rarity = "Legendary"
			pityTriggered = true
		else
			rarity = rollRarity(Config.Loot.Odds[mode] or Config.Loot.Odds.Normal)
		end
	end

	local partId, finalRarity = pickFromPool(boss.LootPool, rarity)
	local parts = {}
	if partId then
		-- Mutation roll (never on tutorial drops).
		local chance = Config.Mutations.Chance[mode] or 0
		if RunService:IsStudio() and Config.Dev.StudioMutationChance and mode ~= "Tutorial" then
			chance = Config.Dev.StudioMutationChance
		end
		local mutationId = random:NextNumber() < chance and MutationDefinitions.Roll(random) or nil
		if mutationId then
			local _, isNew, isNewMutation = self.Services.InventoryService:GrantMutated(player, partId, mutationId)
			table.insert(parts, { Id = partId, Rarity = finalRarity, IsNew = isNew, Pity = pityTriggered, Mutation = mutationId, MutationNew = isNewMutation })
		else
			local _, isNew = self.Services.InventoryService:Grant(player, partId, 1)
			table.insert(parts, { Id = partId, Rarity = finalRarity, IsNew = isNew, Pity = pityTriggered })
		end
		if mode ~= "Tutorial" and finalRarity == "Legendary" then
			profile.Pity.Legendary = 0
		end
	end

	-- Boss stats: total wins, plus wins and best time per difficulty (Modes[mode]).
	-- Normal wins unlock Hard; Hard wins unlock Nightmare.
	local record = profile.Bosses[bossId] or { Wins = 0 }
	record.Wins += 1
	local rounded = math.floor(fightTime + 0.5)
	local modeBest = nil
	if mode ~= "Tutorial" then
		record.Modes = record.Modes or {}
		local modeRecord = record.Modes[mode] or { Wins = 0 }
		modeRecord.Wins += 1
		if not modeRecord.BestTime or rounded < modeRecord.BestTime then
			modeRecord.BestTime = rounded
		end
		record.Modes[mode] = modeRecord
		modeBest = modeRecord.BestTime
		if mode == "Normal" then
			record.BestTime = modeRecord.BestTime -- legacy field (Normal best)
		end
	end
	profile.Bosses[bossId] = record
	profile.Stats.BossWins += 1

	local rewardTable = mode == "Tutorial" and Config.Progression.Rewards.TutorialBossVictory or Config.Progression.Rewards.BossVictory
	local difficulty = Config.Difficulties[mode]
	if difficulty and difficulty.RewardMultiplier ~= 1 then
		local scaled = {}
		for key, amount in rewardTable do
			scaled[key] = math.floor(amount * difficulty.RewardMultiplier + 0.5)
		end
		rewardTable = scaled
	end
	local progress = self.Services.ProgressionService:Award(player, rewardTable)
	self.Services.GameAnalyticsService:Rewards(player, rewardTable, mode == "Tutorial" and "TutorialBoss" or ("Boss:" .. bossId))

	self.Services.PlayerDataService:SaveNow(player)
	self.Services.NightmareBuildService:PushState(player)

	return {
		BossId = bossId,
		BossName = boss.DisplayName,
		Mode = mode,
		Time = rounded,
		BestTime = modeBest,
		Parts = parts,
		Progress = progress,
		Pity = { Count = profile.Pity.Legendary, Threshold = Config.Loot.LegendaryPity },
	}
end

return BossRewardService
