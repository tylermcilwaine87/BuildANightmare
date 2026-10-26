--[[
	NightmareSpawnService  (ModuleScript)
	Location: ServerScriptService/Server/Services/NightmareSpawnService

	Creates the player's ACTIVE Nightmare in the world from their saved build data,
	using the shared NightmareAssembler, and wires it to the AI.

	  * Auto-summons when the Handler spawns (players can recall/summon with H).
	  * Rebuilds instantly when the active build is saved or switched.
	  * On defeat: plays out, then reforms after Config.Nightmare.RespawnDelay seconds.
	  * Despawns on Handler death / leaving. Pending respawns are cancelled with tokens,
	    so a Nightmare can never be duplicated by rapid re-summoning.

	The server owns the Nightmare's physics (SetNetworkOwner(nil)) so clients cannot
	teleport or speed-hack it.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local NightmareAssembler = require(Shared:WaitForChild("NightmareAssembler"))
local BuildValidator = require(Shared:WaitForChild("BuildValidator"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local PassiveDefinitions = require(Shared:WaitForChild("PassiveDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))
local LevelUnlocks = require(Shared:WaitForChild("LevelUnlocks"))

local NightmareSpawnService = {}

local active: { [Player]: Model } = {}
local summoned: { [Player]: boolean } = {}
local tokens: { [Player]: number } = {}
local buildOverride: { [Player]: number } = {} -- duels: fight with a chosen saved build without changing the active one
local devBuild: { [Player]: any } = {} -- Studio tests: a build table to spawn, never saved

local function bumpToken(player: Player): number
	local token = (tokens[player] or 0) + 1
	tokens[player] = token
	return token
end

function NightmareSpawnService:Init(services)
	self.Services = services
	self.UIState = Net.Get("UIStateUpdate")
end

function NightmareSpawnService:Start()
	local function onPlayerAdded(player: Player)
		summoned[player] = true
		player.CharacterAdded:Connect(function(character)
			self:OnCharacterAdded(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			self:Despawn(player)
		end)
		if player.Character then
			task.spawn(self.OnCharacterAdded, self, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:Despawn(player)
		summoned[player] = nil
		tokens[player] = nil
		buildOverride[player] = nil
	end)
end

function NightmareSpawnService:OnCharacterAdded(player: Player, character: Model)
	-- Handlers walk through their own (and everyone's) Nightmares instead of shoving them.
	local function setGroup(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Characters"
		end
	end
	for _, d in character:GetDescendants() do
		setGroup(d)
	end
	character.DescendantAdded:Connect(setGroup)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.MaxHealth = Config.Handler.MaxHealth
		humanoid.Health = humanoid.MaxHealth
		humanoid.Died:Connect(function()
			self:Despawn(player)
		end)
	end

	if not self.Services.PlayerDataService:WaitFor(player) then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.5) -- let the character settle on the ground first
	-- New players create their first Nightmare in the tutorial before it appears.
	if not self.Services.TutorialService:AllowsAutoSummon(player) then
		summoned[player] = false
		self.UIState:FireClient(player, "Summon", { Summoned = false })
		return
	end
	if summoned[player] and player.Character == character then
		self:Spawn(player)
	end
end

-- Moves the active Nightmare (if any) next to a world position, e.g. on arena entry.
function NightmareSpawnService:TeleportNightmare(player: Player, cframe: CFrame)
	local model = active[player]
	if model and model.Parent then
		model:PivotTo(cframe + Vector3.new(0, 3, 0))
	end
end

function NightmareSpawnService:GetNightmare(player: Player): Model?
	return active[player]
end

function NightmareSpawnService:IsSummoned(player: Player): boolean
	return summoned[player] == true
end

function NightmareSpawnService:SetSummoned(player: Player, value: boolean)
	summoned[player] = value
	if value then
		self:Spawn(player)
	else
		self:Despawn(player)
	end
	self.UIState:FireClient(player, "Summon", { Summoned = value })
end

-- Rebuild the active Nightmare (after saving / switching builds) if it is summoned.
function NightmareSpawnService:Refresh(player: Player)
	if summoned[player] then
		self:Spawn(player)
	end
end

-- Duels: (re)spawn right now, optionally with a specific saved build.
function NightmareSpawnService:ForceSpawn(player: Player, buildIndex: number?)
	summoned[player] = true
	buildOverride[player] = buildIndex
	return self:Spawn(player)
end

function NightmareSpawnService:ClearOverride(player: Player)
	buildOverride[player] = nil
	devBuild[player] = nil
end

-- Studio only: spawn a test body from a build table ({ Parts = {...} }, e.g. four legs and no
-- arms) without touching the saved builds. ClearOverride + Refresh puts yours back.
function NightmareSpawnService:DevSpawn(player: Player, build)
	if not game:GetService("RunService"):IsStudio() or type(build) ~= "table" then
		return nil
	end
	devBuild[player] = build
	summoned[player] = true
	return self:Spawn(player)
end

function NightmareSpawnService:Despawn(player: Player)
	bumpToken(player)
	local model = active[player]
	active[player] = nil
	if model then
		self.Services.NightmareAIService:Unregister(model)
		model:Destroy()
	end
end

function NightmareSpawnService:Spawn(player: Player): Model?
	self:Despawn(player)

	local profile = self.Services.PlayerDataService:Get(player)
	local character = player.Character
	local handlerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local handlerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not profile or not handlerRoot or not handlerHumanoid or handlerHumanoid.Health <= 0 then
		return nil
	end

	local build = devBuild[player] or profile.Builds[buildOverride[player] or profile.ActiveBuild] or profile.Builds[profile.ActiveBuild]
	-- Safety net: if a saved build became illegal (e.g. after a balance patch), fall back
	-- to a starter build instead of spawning something the rules don't allow.
	-- (a Studio DevSpawn test body may use parts this profile doesn't own)
	if not devBuild[player] and not BuildValidator.Validate(build, profile.Inventory, LevelUnlocks.PvEBudget(profile.Level), profile.Mutations) then
		build = BuildValidator.Sanitize(Config.StarterBuilds[1])
		build.Name = profile.Builds[profile.ActiveBuild].Name
	end
	local ok, model, info = pcall(NightmareAssembler.Build, build, { Name = ("Nightmare_%d"):format(player.UserId) })
	if not ok then
		warn(("[NightmareSpawn] Failed to assemble %s's Nightmare: %s"):format(player.Name, tostring(model)))
		return nil
	end
	local stats = info.Stats
	info.Abilities = AbilityDefinitions.ForBuild(build, PartDefinitions)
	info.UltimateId = AbilityDefinitions.UltimateForBuild(build, PartDefinitions)
	-- On-hit status passives from equipped parts (e.g. Venomous Spider Legs) and from
	-- mutations (e.g. an Infernal part may burn).
	info.OnHit = {}
	for slot, partId in build.Parts do
		local def = PartDefinitions.Get(partId)
		if def and def.OnHit then
			table.insert(info.OnHit, def.OnHit)
		end
		local mutation = MutationDefinitions.Get(MutationDefinitions.ForSlot(build, slot))
		if mutation and mutation.OnHit then
			table.insert(info.OnHit, mutation.OnHit)
		end
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- R15 so HipHeight drives standing height
	humanoid.HipHeight = info.HipHeight
	humanoid.MaxHealth = stats.MaxHealth
	humanoid.Health = stats.MaxHealth
	humanoid.WalkSpeed = stats.MoveSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated } do
		humanoid:SetStateEnabled(state, false)
	end

	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	model:SetAttribute("NightmareName", build.Name)
	model:SetAttribute("DisplayName", build.Name)
	model:SetAttribute("Archetype", info.Archetype)
	model:SetAttribute("BuildSlot", profile.ActiveBuild)
	model:SetAttribute("Defence", stats.Defence)
	model:SetAttribute("AttackPower", stats.AttackPower)
	model:SetAttribute("AttackSpeed", stats.AttackSpeed)
	model:SetAttribute("MoveSpeed", stats.MoveSpeed)
	model:SetAttribute("Reach", stats.Reach)
	model:SetAttribute("PowerCost", stats.PowerCost)
	model:SetAttribute("ActionSeq", 0)
	model:SetAttribute("DevBuild", devBuild[player] and true or nil) -- (Studio test body: earns no mastery)
	-- (the combat brain: which combos this body can do) an arm's animation set (e.g. a
	-- Tentacle) and the mutations it carries (a mutated part unlocks the Frenzy)
	for _, slot in { "RightArm", "LeftArm" } do
		local def = build.Parts[slot] and PartDefinitions.Get(build.Parts[slot])
		model:SetAttribute(slot .. "Set", def and def.AnimationSet or nil)
	end
	local mutations = {}
	for slot in build.Parts do
		local id = MutationDefinitions.ForSlot(build, slot)
		if id and MutationDefinitions.Get(id) then
			table.insert(mutations, id)
		end
	end
	model:SetAttribute("Mutations", #mutations > 0 and table.concat(mutations, ",") or nil)
	model:SetAttribute("Command", "Follow")
	-- always-on part passives (PassiveDefinitions): "Splinters,Sprint"
	model:SetAttribute("Passives", table.concat(PassiveDefinitions.ForBuild(build, PartDefinitions), ","))
	model:SetAttribute("Shield", 0)
	model:SetAttribute("StaggerPower", stats.StaggerPower)
	model:SetAttribute("StaggerResist", stats.StaggerResist)
	model:SetAttribute("StaggerMax", Config.Stagger.Max.Nightmare)
	model:SetAttribute("Stagger", 0)
	model:SetAttribute("UltimateId", info.UltimateId or "")
	model:SetAttribute("UltimateEnergy", 0)
	for slot = 1, 2 do
		model:SetAttribute(("Ability%dId"):format(slot), info.Abilities[slot] or "")
		model:SetAttribute(("Ability%dReadyAt"):format(slot), 0)
		-- which body slot the ability comes from (Head, RightArm, LeftArm, Tail...): the
		-- animator uses it so the right limb performs it (a left-arm claw slashes left)
		local source = ""
		for _, partSlot in { "Head", "Core", "RightArm", "LeftArm", "Back", "Tail" } do
			local def = PartDefinitions.Get(build.Parts[partSlot])
			if def and info.Abilities[slot] and def.AbilityId == info.Abilities[slot] then
				source = partSlot
				break
			end
		end
		model:SetAttribute(("Ability%dSource"):format(slot), source)
	end

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Nightmares"
		end
	end
	CollectionService:AddTag(model, "Nightmare")

	-- Place beside the Handler with the feet on the Handler's ground level.
	local groundY = handlerRoot.Position.Y - (handlerHumanoid.HipHeight + handlerRoot.Size.Y / 2)
	local spawnPos = (handlerRoot.CFrame * CFrame.new(Config.Nightmare.FollowOffset)).Position
	spawnPos = Vector3.new(spawnPos.X, groundY + info.HipHeight + info.HitboxSize.Y / 2 + 0.5, spawnPos.Z)
	local look = handlerRoot.CFrame.LookVector
	model:PivotTo(CFrame.lookAt(spawnPos, spawnPos + Vector3.new(look.X, 0, look.Z)))

	model.Parent = Workspace:FindFirstChild("Nightmares") or Workspace
	pcall(function()
		model.PrimaryPart:SetNetworkOwner(nil)
	end)

	active[player] = model
	self.Services.NightmareAIService:Register(model, player, stats, info)

	humanoid.Died:Connect(function()
		self:OnDefeated(player, model)
	end)

	return model
end

function NightmareSpawnService:OnDefeated(player: Player, model: Model)
	model:SetAttribute("Defeated", true)
	self.Services.NightmareAIService:Unregister(model)
	if active[player] ~= model then
		return
	end
	active[player] = nil
	local token = bumpToken(player)

	task.delay(1.5, function()
		if model.Parent then
			model:Destroy()
		end
	end)

	-- In a duel, a defeated Nightmare loses the round; DuelService handles respawning.
	local duel = self.Services.DuelService
	if duel:IsInMatch(player) then
		duel:OnNightmareDefeated(player)
		return
	end

	local delaySeconds = Config.Nightmare.RespawnDelay
	self.UIState:FireClient(player, "NightmareDefeated", { RespawnIn = delaySeconds })
	task.delay(delaySeconds, function()
		if tokens[player] == token and summoned[player] and player.Parent then
			self:Spawn(player)
		end
	end)
end

return NightmareSpawnService
