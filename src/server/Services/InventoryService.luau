--[[
	InventoryService  (ModuleScript)
	Location: ServerScriptService/Server/Services/InventoryService

	Server-only access to owned parts. Nothing on the client can grant parts; only
	server code (BossRewardService after a verified victory) calls :Grant().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PartDefinitions"))
local MutationDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MutationDefinitions"))

local InventoryService = {}

function InventoryService:Init(services)
	self.Services = services
end

function InventoryService:GetCount(player: Player, partId: string): number
	local profile = self.Services.PlayerDataService:Get(player)
	return profile and (profile.Inventory[partId] or 0) or 0
end

function InventoryService:GetInventory(player: Player)
	local profile = self.Services.PlayerDataService:Get(player)
	return profile and profile.Inventory or nil
end

-- Returns (granted: boolean, isNewDiscovery: boolean). Server code only.
-- Does NOT push state or save; the caller batches that (see BossRewardService).
function InventoryService:Grant(player: Player, partId: string, amount: number?): (boolean, boolean)
	local profile = self.Services.PlayerDataService:Get(player)
	local def = PartDefinitions.Get(partId)
	amount = amount or 1
	if not profile or not def or amount < 1 or amount % 1 ~= 0 then
		return false, false
	end
	local isNew = not profile.Discovered[partId]
	profile.Inventory[partId] = (profile.Inventory[partId] or 0) + amount
	profile.Discovered[partId] = true
	return true, isNew
end

-- Grants ONE mutated copy (the part itself + its mutation) and records it in the
-- Mutation Book. Returns (granted, isNewPart, isNewMutation). Server code only.
function InventoryService:GrantMutated(player: Player, partId: string, mutationId: string): (boolean, boolean, boolean)
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile or not MutationDefinitions.Get(mutationId) then
		return false, false, false
	end
	local granted, isNewPart = self:Grant(player, partId, 1)
	if not granted then
		return false, false, false
	end
	profile.Mutations[partId] = profile.Mutations[partId] or {}
	profile.Mutations[partId][mutationId] = (profile.Mutations[partId][mutationId] or 0) + 1

	local entry = profile.MutationBook[mutationId]
	local isNewMutation = entry == nil
	entry = entry or { Found = 0, Parts = {} }
	entry.Found += 1
	entry.Parts[partId] = true
	profile.MutationBook[mutationId] = entry
	self.Services.GameAnalyticsService:Event(player, "MutationFound", 1, { mutationId, partId, isNewMutation and "New" or "Repeat" })
	return true, isNewPart, isNewMutation
end

return InventoryService
