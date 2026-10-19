--[[
	UltimateService  (ModuleScript)
	Location: ServerScriptService/Server/Services/UltimateService

	ULTIMATE ENERGY (0-100, attribute "UltimateEnergy" on the Nightmare) builds from
	damage the Nightmare deals and takes and from ability use. G fires the build's
	Ultimate (AbilityDefinitions.Ultimates; chosen by Core or a signature Back part).

	Rules (spec section 11): never spammable (needs a full bar, which resets), always a
	visible telegraphed STARTUP, damage goes through the normal pipeline (defence, guard,
	dodge i-frames all apply), and Config.Ultimate.PvPDamageCapFraction caps it in PvP
	(Phase 4). Works whether or not the Nightmare is possessed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local StatusDefinitions = require(Shared:WaitForChild("StatusDefinitions"))

local UltimateService = {}

local U = Config.Ultimate

function UltimateService:Init(services)
	self.Services = services
end

function UltimateService:AddEnergy(brain, amount: number)
	if not brain or amount <= 0 or brain.ultimateFiring then
		return
	end
	brain.ultimateEnergy = math.min(U.EnergyMax, (brain.ultimateEnergy or 0) + amount)
	brain.model:SetAttribute("UltimateEnergy", math.floor(brain.ultimateEnergy))
end

-- The Ultimate CANCELS a basic combo / heavy / ability in progress (it's the big
-- moment, so it should feel instant). If the Nightmare is staggered or already mid-
-- Ultimate, the press is buffered for up to 2 seconds instead of being ignored.
function UltimateService:Request(player: Player)
	local ai = self.Services.NightmareAIService
	local brain = ai:GetBrain(player)
	if not brain or brain.humanoid.Health <= 0 or brain.ultimateQueued or self.Services.DuelService:IsFrozen(player) then
		return
	end
	local def = AbilityDefinitions.GetUltimate(brain.model:GetAttribute("UltimateId"))
	if not def or (brain.ultimateEnergy or 0) < U.EnergyMax then
		return
	end

	local status = self.Services.StatusService
	local function blocked()
		return brain.ultimateFiring or status:IsStaggered(brain.model)
	end

	if blocked() then
		brain.ultimateQueued = true
		task.spawn(function()
			local deadline = os.clock() + 2
			while blocked() and os.clock() < deadline and brain.model.Parent do
				task.wait(0.1)
			end
			brain.ultimateQueued = false
			if not blocked() and brain.model.Parent and brain.humanoid.Health > 0 and (brain.ultimateEnergy or 0) >= U.EnergyMax then
				self:Fire(brain, def)
			end
		end)
		return
	end
	self:Fire(brain, def)
end

function UltimateService:Fire(brain, def)
	brain.ultimateEnergy = 0
	brain.model:SetAttribute("UltimateEnergy", 0)
	brain.queuedAbility = nil
	self:Execute(brain, def) -- Execute bumps castToken, cancelling any pending combo/heavy hit
	self.Services.ChallengeService:Notify(brain.owner, "UltimateUsed")
end

------------------------------------------------------------------------------------------
-- Execution
------------------------------------------------------------------------------------------
local function enemiesNear(position: Vector3, radius: number): { Model }
	local list = {}
	for _, enemy in game:GetService("CollectionService"):GetTagged("Enemy") do
		local root = enemy:FindFirstChild("HumanoidRootPart")
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and Util.FlatDistance(root.Position, position) <= radius then
			table.insert(list, enemy)
		end
	end
	return list
end

function UltimateService:Damage(brain, def, targets)
	local combat = self.Services.CombatService
	for _, target in targets do
		combat:ApplyDamage({
			Attacker = brain.model,
			Target = target,
			BaseDamage = def.Damage,
			AttackPower = brain.stats.AttackPower,
			Knockback = 25,
			Stagger = def.Stagger,
			Status = def.Element and StatusDefinitions.ByElement[def.Element] or nil,
			CastKey = brain.ultimateCastKey, -- PvP cap: max 45% of a target's HP per Ultimate
			Source = "Ultimate:" .. def.DisplayName,
		})
	end
end

function UltimateService:DamageCircle(brain, def, center: Vector3, radius: number)
	local hits = {}
	for _, enemy in enemiesNear(center, radius + 6) do
		local root = enemy.HumanoidRootPart
		if Util.FlatDistance(root.Position, center) <= radius + math.max(root.Size.X, root.Size.Z) / 2 then
			table.insert(hits, enemy)
		end
	end
	self:Damage(brain, def, hits)
end

function UltimateService:Execute(brain, def)
	local ai = self.Services.NightmareAIService
	local telegraphs = self.Services.TelegraphService
	local root = brain.root
	local hitbox = brain.hitboxSize
	local now = os.clock()

	local extra = 1
	if def.Type == "Nova" then
		extra = def.Pulses * def.Interval
	elseif def.Type == "Beam" then
		extra = def.Ticks * def.Interval
	end
	brain.ultimateFiring = true
	brain.ultimateCastKey = game:GetService("HttpService"):GenerateGUID(false)
	brain.castToken = (brain.castToken or 0) + 1
	local castToken = brain.castToken
	brain.busyUntil = now + def.Startup + extra
	if not brain.possessedBy then
		ai:Stop(brain)
	end
	ai:PlayAction(brain, "Ultimate", def.Startup, def.Startup + extra)
	Net.FireNearby(telegraphs.WorldFX, root.Position, Config.Performance.EffectRadius, "UltimateBanner", { Name = def.DisplayName, Model = brain.model, Position = root.Position })

	local function alive()
		return brain.castToken == castToken and brain.model.Parent ~= nil and brain.humanoid.Health > 0
	end
	local function ground()
		return root.Position - Vector3.new(0, hitbox.Y / 2 + brain.humanoid.HipHeight, 0)
	end

	task.spawn(function()
		if def.Type == "Nova" then
			telegraphs:Circle(ground(), def.Radius, def.Startup, "Friendly")
			task.wait(def.Startup)
			for _ = 1, def.Pulses do
				if not alive() then
					break
				end
				local center = ground()
				telegraphs:Impact(center, def.Radius, "Friendly")
				self:DamageCircle(brain, def, center, def.Radius)
				task.wait(def.Interval)
			end
		elseif def.Type == "Barrage" then
			local origin = ground()
			local targets = enemiesNear(origin, def.Area)
			local points = {}
			local random = Random.new()
			for i = 1, def.Count do
				local base
				if #targets > 0 then
					base = targets[(i - 1) % #targets + 1].HumanoidRootPart.Position
					base = Vector3.new(base.X, origin.Y, base.Z)
				else
					base = origin + Util.Flat(root.CFrame.LookVector) * random:NextNumber(6, def.Area * 0.6)
				end
				local point = base + Vector3.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3))
				local delay = def.Startup + (i - 1) * 0.12
				table.insert(points, { Position = point, Delay = delay })
				telegraphs:Circle(point, def.Radius, delay, "Friendly")
			end
			local skyFrom = root.Position + Vector3.new(0, 25, 0)
			for _, entry in points do
				task.delay(math.max(entry.Delay - 0.45, 0), function()
					if alive() then
						telegraphs:Projectile(skyFrom, entry.Position, 0.45)
					end
				end)
				task.delay(entry.Delay, function()
					if alive() then
						telegraphs:Impact(entry.Position, def.Radius, "Friendly")
						self:DamageCircle(brain, def, entry.Position, def.Radius)
					end
				end)
			end
			task.wait(def.Startup + def.Count * 0.12)
		elseif def.Type == "Beam" then
			local look = Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
			local start = ground()
			local centre = start + look * (hitbox.Z / 2 + def.Length / 2)
			local beamCF = CFrame.lookAt(centre, centre + look)
			telegraphs:Box(beamCF, Vector3.new(def.Width, 1, def.Length), def.Startup, "Friendly")
			task.wait(def.Startup)
			for _ = 1, def.Ticks do
				if not alive() then
					break
				end
				telegraphs:Impact(centre, def.Width, "Friendly")
				local hits = self.Services.HitDetectionService:QueryBox(beamCF * CFrame.new(0, 4, 0), Vector3.new(def.Width, 10, def.Length), { brain.model })
				self:Damage(brain, def, hits)
				task.wait(def.Interval)
			end
		elseif def.Type == "Collapse" then
			local center = ground() + Util.Flat(root.CFrame.LookVector) * def.Offset
			telegraphs:Circle(center, def.PullRadius, def.Startup, "Pull")
			telegraphs:Circle(center, def.Radius, def.Startup + 0.5, "Friendly")
			task.wait(def.Startup)
			if alive() then
				for _, enemy in enemiesNear(center, def.PullRadius) do
					local enemyRoot = enemy.HumanoidRootPart
					if not enemyRoot.Anchored and not enemy:GetAttribute("KnockbackImmune") then
						local toward = Util.FlatUnit(center - enemyRoot.Position)
						if toward then
							enemyRoot:ApplyImpulse((toward * 50 + Vector3.new(0, 10, 0)) * enemyRoot.AssemblyMass)
						end
					end
				end
				task.wait(0.5)
				if alive() then
					telegraphs:Impact(center, def.Radius, "Friendly")
					self:DamageCircle(brain, def, center, def.Radius)
				end
			end
		end
		brain.ultimateFiring = false
	end)
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function UltimateService:Start()
	local ai = self.Services.NightmareAIService
	self.Services.CombatService:OnDamaged(function(target, attacker, amount)
		if amount <= 0 then
			return
		end
		local dealerBrain = attacker and ai:GetBrainByModel(attacker)
		if dealerBrain then
			self:AddEnergy(dealerBrain, amount * U.PerDamageDealt)
		end
		local victimBrain = ai:GetBrainByModel(target)
		if victimBrain then
			self:AddEnergy(victimBrain, amount * U.PerDamageTaken)
		end
	end)
end

return UltimateService
