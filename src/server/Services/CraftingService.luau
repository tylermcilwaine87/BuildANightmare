--[[
	CraftingService  (ModuleScript)
	Location: ServerScriptService/Server/Services/CraftingService

	The Crafting Forge (Phase 5). Handles the CraftRequest RemoteFunction:
	  "Craft", partId             spend level-gated Essence + coins + spare parts -> 1 part
	  "Dismantle", partId, count  spare duplicate parts -> Essence (by rarity)
	  "DevGrantMutation"          STUDIO ONLY: a random mutated copy of a part you own

	Rules live in Shared/CraftingDefinitions so the Forge UI shows exactly what is
	enforced here. Every check runs on the AUTHORITATIVE profile; nothing the client sends
	is trusted beyond the part id and count, both validated. Changes are saved right away
	(like boss loot), so a crafted part can't be lost to a crash.

	Returns { Ok, Error?, State = snapshot, Crafted? = { Id, IsNew }, Essence? = gained }
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local CraftingDefinitions = require(Shared:WaitForChild("CraftingDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))

local CraftingService = {}

local random = Random.new()

local MAX_DISMANTLE = 50 -- per request

function CraftingService:Init(services)
	self.Services = services
end

function CraftingService:Start()
	Net.Get("CraftRequest").OnServerInvoke = function(player, action, partId, count)
		if not self.Services.AntiExploitService:Allow(player, "CraftRequest") then
			return { Ok = false, Error = "Slow down a little!" }
		end
		local profile = self.Services.PlayerDataService:Get(player)
		if not profile then
			return { Ok = false, Error = "Your profile is still loading." }
		end
		if self.Services.DuelService:IsInMatch(player) or self.Services.BossService:GetEncounter(player) then
			return { Ok = false, Error = "Finish your fight first." }
		end
		if action == "Craft" then
			return self:Craft(player, profile, partId)
		elseif action == "Dismantle" then
			return self:Dismantle(player, profile, partId, count)
		elseif action == "DevGrantMutation" then
			return self:DevGrantMutation(player, profile)
		end
		return { Ok = false, Error = "Unknown request." }
	end
end

function CraftingService:Finish(player: Player, result)
	self.Services.PlayerDataService:SaveNow(player)
	self.Services.NightmareBuildService:PushState(player)
	result.Ok = true
	result.State = self.Services.PlayerDataService:Snapshot(player)
	return result
end

function CraftingService:Craft(player: Player, profile, partId)
	local ok, reason = CraftingDefinitions.CanCraft(profile, partId)
	if not ok then
		return { Ok = false, Error = reason }
	end
	local recipe = CraftingDefinitions.Get(partId)

	if not CraftingDefinitions.IsFree() then
		profile.Essence -= recipe.Essence
		profile.Coins -= recipe.Coins
		for ingredient, amount in recipe.Ingredients do
			profile.Inventory[ingredient] -= amount
		end
		local analytics = self.Services.GameAnalyticsService
		analytics:Economy(player, "Sink", "Essence", recipe.Essence, "Craft:" .. partId)
		analytics:Economy(player, "Sink", "Coins", recipe.Coins, "Craft:" .. partId)
	end
	self.Services.GameAnalyticsService:Event(player, "PartCrafted", 1, { partId })
	local _, isNew = self.Services.InventoryService:Grant(player, partId, 1)
	self.Services.ChallengeService:Notify(player, "Crafted")

	return self:Finish(player, { Crafted = { Id = partId, IsNew = isNew } })
end

-- DEV ONLY (Studio): a random mutated copy of a random part you own, for testing the
-- Mutation Book / Workshop / visuals without fighting bosses. Refused on live servers.
function CraftingService:DevGrantMutation(player: Player, profile)
	if not RunService:IsStudio() then
		return { Ok = false, Error = "Not available." }
	end
	local owned = {}
	for partId, count in profile.Inventory do
		local def = PartDefinitions.Get(partId)
		if count > 0 and def and def.Equippable then
			table.insert(owned, partId)
		end
	end
	if #owned == 0 then
		return { Ok = false, Error = "You don't own any parts." }
	end
	table.sort(owned) -- deterministic order before the random pick
	local partId = owned[random:NextInteger(1, #owned)]
	local mutationId = MutationDefinitions.Roll(random)
	local _, _, isNewMutation = self.Services.InventoryService:GrantMutated(player, partId, mutationId)
	return self:Finish(player, { Granted = { Id = partId, Mutation = mutationId, MutationNew = isNewMutation } })
end

function CraftingService:Dismantle(player: Player, profile, partId, count)
	local def = type(partId) == "string" and PartDefinitions.Get(partId)
	if not def then
		return { Ok = false, Error = "Unknown part." }
	end
	if type(count) ~= "number" or count % 1 ~= 0 or count < 1 or count > MAX_DISMANTLE then
		return { Ok = false, Error = "Invalid amount." }
	end
	local spare = CraftingDefinitions.SpareCount(profile, partId)
	if spare < count then
		return { Ok = false, Error = spare == 0 and ("No spare %s to dismantle (your last copy and copies in saved builds are kept)."):format(def.DisplayName) or ("You only have %d spare."):format(spare) }
	end

	local gained = (CraftingDefinitions.DismantleValue[def.Rarity] or 0) * count
	profile.Inventory[partId] -= count
	profile.Essence += gained
	self.Services.ChallengeService:Notify(player, "Dismantled", count)
	self.Services.GameAnalyticsService:Economy(player, "Source", "Essence", gained, "Dismantle")

	return self:Finish(player, { Essence = gained })
end

return CraftingService
