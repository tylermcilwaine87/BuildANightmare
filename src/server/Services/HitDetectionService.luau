--[[
	HitDetectionService  (ModuleScript)
	Location: ServerScriptService/Server/Services/HitDetectionService

	Server-side spatial hit queries. Returns the combatant MODELS (anything with a
	Humanoid) whose queryable parts overlap a box. Nightmare visual parts have
	CanQuery = false, so only their fixed hitbox root can ever be hit.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HitDetectionService = {}

-- Only solid world geometry blocks sight; creatures and effects never do.
-- Cached and rebuilt at most every Config.Performance.FilterRefresh seconds.
local cachedSight: RaycastParams? = nil
local cachedAt = 0
local function sightParams(): RaycastParams
	if cachedSight and os.clock() - cachedAt < Config.Performance.FilterRefresh then
		return cachedSight
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, name in { "Nightmares", "Enemies", "ClientEffects" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	cachedSight, cachedAt = params, os.clock()
	return params
end

-- True if nothing solid (walls, pillars) sits between the two points.
function HitDetectionService:HasLineOfSight(from: Vector3, to: Vector3, target: Instance?): boolean
	local hit = Workspace:Raycast(from, to - from, sightParams())
	return hit == nil or (target ~= nil and hit.Instance:IsDescendantOf(target))
end

-- Drops models hidden behind walls from `origin` (so melee can't hit through pillars).
function HitDetectionService:FilterVisible(models: { Model }, origin: Vector3?): { Model }
	if not origin or #models == 0 then
		return models
	end
	local params = sightParams()
	local visible = {}
	for _, model in models do
		local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		local hit = root and Workspace:Raycast(origin, root.Position - origin, params)
		-- Hitting the target's own body (e.g. a boss's armour) still counts as visible.
		if not hit or hit.Instance:IsDescendantOf(model) then
			table.insert(visible, model)
		end
	end
	return visible
end

function HitDetectionService:GetCombatantModel(part: BasePart): Model?
	local node = part.Parent
	while node and node ~= Workspace do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- `origin` (optional): the attacker's position; targets behind walls from there are dropped.
function HitDetectionService:QueryBox(cframe: CFrame, size: Vector3, ignore: { Instance }, origin: Vector3?): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = false

	if Config.Dev.DebugHitboxes then
		local box = Instance.new("Part")
		box.Anchored = true
		box.CanCollide = false
		box.CanQuery = false
		box.CanTouch = false
		box.Transparency = 0.7
		box.Color = Color3.fromRGB(255, 0, 0)
		box.Size = size
		box.CFrame = cframe
		box.Parent = Workspace
		Debris:AddItem(box, 0.25)
	end

	return self:FilterVisible(self:CollectModels(Workspace:GetPartBoundsInBox(cframe, size, params)), origin)
end

-- Sphere query; `ignore` and `origin` as above. Used for slams, shockwaves and AoE abilities.
function HitDetectionService:QueryRadius(position: Vector3, radius: number, ignore: { Instance }, origin: Vector3?): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = false

	if Config.Dev.DebugHitboxes then
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.Transparency = 0.8
		ball.Color = Color3.fromRGB(255, 0, 0)
		ball.Size = Vector3.one * radius * 2
		ball.Position = position
		ball.Parent = Workspace
		Debris:AddItem(ball, 0.25)
	end

	return self:FilterVisible(self:CollectModels(Workspace:GetPartBoundsInRadius(position, radius, params)), origin)
end

function HitDetectionService:CollectModels(parts: { BasePart }): { Model }
	local seen = {}
	local results = {}
	for _, part in parts do
		local model = self:GetCombatantModel(part)
		if model and not seen[model] then
			seen[model] = true
			table.insert(results, model)
		end
	end
	return results
end

return HitDetectionService
