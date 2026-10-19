--[[
	AbilityService  (ModuleScript)
	Location: ServerScriptService/Server/Services/AbilityService

	Executes Nightmare special abilities (definitions in Shared/AbilityDefinitions).

	Flow:
	  client presses Q/E -> CombatAction("Ability", slot) -> :Request()
	    -> checks the Nightmare exists, has an ability in that slot, cooldown is ready
	    -> queues it on the AI brain; the AI walks into range (up to 3s) and calls
	       :Execute(). Abilities with no target fire straight ahead.
	Cooldowns are tracked on the SERVER. The ready-time is mirrored to the client
	through attributes "Ability1ReadyAt"/"Ability2ReadyAt" (Workspace:GetServerTimeNow()).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local StatusDefinitions = require(Shared:WaitForChild("StatusDefinitions"))
local Util = require(Shared:WaitForChild("Util"))

local AbilityService = {}

function AbilityService:Init(services)
	self.Services = services
end

-- How close the Nightmare needs to be (centre to centre, minus target radius) to cast.
function AbilityService:GetCastRange(brain, def): number
	local half = brain.hitboxSize.Z / 2
	if def.Type == "Melee" then
		return half + def.Range - 0.5
	elseif def.Type == "AoE" then
		return def.Offset + def.Radius * 0.7
	elseif def.Type == "Dash" then
		return half + def.Distance * 0.9
	elseif def.Type == "Pull" then
		return def.Range
	end
	return math.huge -- Shield
end

function AbilityService:IsReady(brain, slot: number): boolean
	return os.clock() >= (brain.abilityReadyAt[slot] or 0)
end

function AbilityService:Request(player: Player, slot: number)
	local ai = self.Services.NightmareAIService
	local brain = ai:GetBrain(player)
	if not brain or brain.humanoid.Health <= 0 or self.Services.DuelService:IsFrozen(player) then
		return
	end
	local def = AbilityDefinitions.Get(brain.abilities[slot])
	if not def or not self:IsReady(brain, slot) then
		return
	end
	brain.queuedAbility = { Slot = slot, Expires = os.clock() + Config.Nightmare.AbilityQueueTimeout }
end

local function damageTargets(self, brain, targets, def, knockback)
	local combat = self.Services.CombatService
	for _, target in targets do
		combat:ApplyDamage({
			Attacker = brain.model,
			Target = target,
			BaseDamage = def.Damage,
			AttackPower = brain.stats.AttackPower,
			Knockback = knockback or 0,
			Stagger = def.Stagger or 15,
			Status = def.Element and StatusDefinitions.ByElement[def.Element] or nil,
			Source = "Ability:" .. def.DisplayName,
		})
	end
end

local function ignoreList(brain)
	local ignore = { brain.model }
	if brain.owner.Character then
		table.insert(ignore, brain.owner.Character)
	end
	return ignore
end

local function stillValid(brain, castToken: number): boolean
	return brain.castToken == castToken and brain.model.Parent ~= nil and brain.humanoid.Health > 0
end

function AbilityService:Execute(brain, slot: number, target: Model?)
	local def = AbilityDefinitions.Get(brain.abilities[slot])
	if not def then
		return
	end
	local now = os.clock()
	brain.queuedAbility = nil
	brain.abilityReadyAt[slot] = now + def.Cooldown
	brain.model:SetAttribute(("Ability%dReadyAt"):format(slot), Workspace:GetServerTimeNow() + def.Cooldown)
	brain.castToken = (brain.castToken or 0) + 1
	local castToken = brain.castToken

	local ai = self.Services.NightmareAIService
	local telegraphs = self.Services.TelegraphService
	local hitDetection = self.Services.HitDetectionService
	local windup, total = def.Windup, def.Windup + def.Recovery

	brain.busyUntil = now + total
	brain.cancelableAt = now + windup + 0.05 -- the next queued ability may only cut the RECOVERY
	local possessed = brain.possessedBy ~= nil
	if not possessed then
		ai:Stop(brain)
	end
	self.Services.UltimateService:AddEnergy(brain, Config.Ultimate.PerAbilityUse)
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	if targetRoot and not possessed then
		ai:Face(brain, targetRoot.Position)
		-- Snap to face the target so the ability goes where the player expects.
		local direction = Util.FlatUnit(targetRoot.Position - brain.root.Position)
		if direction then
			brain.root.CFrame = CFrame.lookAt(brain.root.Position, brain.root.Position + direction)
		end
	end
	ai:PlayAction(brain, "Ability_" .. def.Type, windup, total)
	self.Services.TutorialService:Notify(brain.owner, "AbilityUsed")
	self.Services.ChallengeService:Notify(brain.owner, "AbilityUsed")

	local root = brain.root
	local hitbox = brain.hitboxSize

	if def.Type == "Melee" then
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			local cframe = root.CFrame * CFrame.new(0, 0, -(hitbox.Z / 2 + def.Range / 2))
			damageTargets(self, brain, hitDetection:QueryBox(cframe, Vector3.new(def.Width, hitbox.Y + 2, def.Range), ignoreList(brain), root.Position), def, 15)
		end)
	elseif def.Type == "AoE" then
		local ground = root.Position - Vector3.new(0, hitbox.Y / 2 + brain.humanoid.HipHeight, 0)
		local center = ground + Util.Flat(root.CFrame.LookVector) * def.Offset
		telegraphs:Circle(center, def.Radius, windup, "Friendly")
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			telegraphs:Impact(center, def.Radius, "Friendly")
			local hits = {}
			for _, model in hitDetection:QueryRadius(center + Vector3.new(0, 3, 0), def.Radius + 3, ignoreList(brain), root.Position) do
				local r = model:FindFirstChild("HumanoidRootPart")
				if r and Util.FlatDistance(r.Position, center) <= def.Radius + math.max(r.Size.X, r.Size.Z) / 2 then
					table.insert(hits, model)
				end
			end
			damageTargets(self, brain, hits, def, 20)
		end)
	elseif def.Type == "Dash" then
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			local look = Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
			local start = root.Position
			-- Path hit box covering the whole dash.
			local mid = start + look * (def.Distance / 2)
			local pathCF = CFrame.lookAt(mid, mid + look)
			damageTargets(self, brain, hitDetection:QueryBox(pathCF, Vector3.new(def.Width, hitbox.Y + 2, def.Distance + hitbox.Z), ignoreList(brain)), def, 10)

			local attachment = root:FindFirstChild("FacingAttachment")
			if attachment then
				local velocity = Instance.new("LinearVelocity")
				velocity.Attachment0 = attachment
				velocity.MaxForce = 1e6
				velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
				velocity.RelativeTo = Enum.ActuatorRelativeTo.World
				velocity.VectorVelocity = look * (def.Distance / 0.2)
				velocity.Parent = root
				task.delay(0.2, function()
					velocity:Destroy()
				end)
			end
		end)
	elseif def.Type == "Pull" then
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			local tRoot = target and target:FindFirstChild("HumanoidRootPart")
			if not tRoot or Util.FlatDistance(tRoot.Position, root.Position) > def.Range + 3 then
				return
			end
			if not tRoot.Anchored and not target:GetAttribute("KnockbackImmune") then
				local toward = Util.FlatUnit(root.Position - tRoot.Position)
				local distance = Util.FlatDistance(root.Position, tRoot.Position) - (hitbox.Z / 2 + 3)
				if toward and distance > 0 then
					tRoot:ApplyImpulse((toward * math.min(distance * 4, 90) + Vector3.new(0, 12, 0)) * tRoot.AssemblyMass)
				end
			end
			damageTargets(self, brain, { target }, def, 0)
		end)
	elseif def.Type == "Shield" then
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			brain.model:SetAttribute("Shield", def.Amount)
			brain.model:SetAttribute("ShieldMax", def.Amount)
			Net.FireNearby(self.Services.TelegraphService.WorldFX, brain.root.Position, Config.Performance.EffectRadius, "Shield", { Target = brain.model, Duration = def.Duration })
			task.delay(def.Duration, function()
				if brain.model.Parent then
					brain.model:SetAttribute("Shield", 0)
				end
			end)
		end)
	end
end

return AbilityService
