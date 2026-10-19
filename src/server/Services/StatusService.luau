--[[
	StatusService  (ModuleScript)
	Location: ServerScriptService/Server/Services/StatusService

	Server-authoritative STAGGER and STATUS EFFECTS for every combatant.

	STAGGER (Nightmares, enemies, bosses; Handlers use guard-break instead)
	  * Heavy attacks, combo finishers and abilities add stagger, scaled by the
	    attacker's StaggerPower and the target's StaggerResist (a Nightmare's Defence adds
	    to that: armour steadies it; 70% is the most that can ever be ignored).
	  * When the meter fills, the target is Staggered (stunned) for a short time and the
	    meter resets. For a few seconds afterwards stagger builds at 25%, so endless stun
	    loops are impossible.
	  * Meters drain after a short delay without new stagger.
	  Attributes: Stagger, StaggerMax, StaggeredUntil (Workspace:GetServerTimeNow()).

	STATUS EFFECTS (definitions in Shared/StatusDefinitions)
	  Burn / Poison (damage over time, Poison stacks to 5), Shock (burst + chain),
	  Chill (slow, never freeze), Weaken (deals less damage).
	  Attributes: Statuses ("Burn,Poison:3"), SpeedMultiplier.

	Every movement controller multiplies its speed by :SpeedMultiplier(model), and
	CombatService multiplies outgoing damage by :OutgoingMultiplier(attacker).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local StatusDefinitions = require(Shared:WaitForChild("StatusDefinitions"))

local StatusService = {}

local S = Config.Stagger
local records = {} -- [Model] = { stagger, lastStagger, staggeredUntil, resistUntil, statuses = { [id] = {stacks, expires, nextTick, source} } }

local function getRecord(model: Model)
	local record = records[model]
	if not record then
		record = { stagger = 0, lastStagger = 0, staggeredUntil = 0, resistUntil = 0, statuses = {} }
		records[model] = record
		model.Destroying:Connect(function()
			records[model] = nil
		end)
	end
	return record
end

local function isHandler(model: Model): boolean
	return Players:GetPlayerFromCharacter(model) ~= nil
end

local function staggerKind(model: Model): string
	if CollectionService:HasTag(model, "Boss") then
		return "Boss"
	elseif CollectionService:HasTag(model, "Enemy") then
		return "Enemy"
	end
	return "Nightmare"
end

function StatusService:Init(services)
	self.Services = services
	self.Feedback = Net.Get("CombatFeedback")
end

------------------------------------------------------------------------------------------
-- Stagger
------------------------------------------------------------------------------------------
function StatusService:GetStaggerMax(model: Model): number
	local max = model:GetAttribute("StaggerMax")
	if max then
		return max
	end
	return S.Max[staggerKind(model)] or 100
end

function StatusService:IsStaggered(model: Model?): boolean
	local record = model and records[model]
	return record ~= nil and os.clock() < record.staggeredUntil
end

function StatusService:AddStagger(target: Model, amount: number, attacker: Model?)
	if amount <= 0 or isHandler(target) or not target.Parent then
		return
	end
	local record = getRecord(target)
	local now = os.clock()
	if now < record.staggeredUntil then
		return -- already stunned: no extending it
	end
	local power = (attacker and attacker:GetAttribute("StaggerPower")) or 100
	local resist = target:GetAttribute("StaggerResist") or 0
	-- a Nightmare's armour (Defence) steadies it too: up to +30% more stagger ignored, so
	-- another player's armoured Nightmare is much harder to stun than a Scrapling
	if CollectionService:HasTag(target, "Nightmare") then
		resist += math.clamp(target:GetAttribute("Defence") or 0, 0, 60) * 0.5
	end
	amount = amount * (power / 100) * (1 - math.clamp(resist, 0, 70) / 100)
	if now < record.resistUntil then
		amount *= S.ResistanceMultiplier
	end

	record.stagger += amount
	record.lastStagger = now
	local max = self:GetStaggerMax(target)

	if record.stagger >= max then
		local duration = S.Duration[staggerKind(target)] or 1.2
		record.stagger = 0
		record.staggeredUntil = now + duration
		record.resistUntil = now + duration + S.ResistanceTime
		target:SetAttribute("StaggeredUntil", Workspace:GetServerTimeNow() + duration)
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		local root = target:FindFirstChild("HumanoidRootPart")
		if humanoid and root then
			humanoid:MoveTo(root.Position)
		end
		local position = target:GetPivot().Position
		Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "Staggered", { Target = target, Position = position, Duration = duration })
	end
	target:SetAttribute("Stagger", math.floor(record.stagger))
	target:SetAttribute("StaggerMax", max)
end

------------------------------------------------------------------------------------------
-- Status effects
------------------------------------------------------------------------------------------
local function publish(model: Model, record)
	local parts = {}
	local slow = 0
	for _, id in StatusDefinitions.Order do
		local status = record.statuses[id]
		if status then
			table.insert(parts, status.stacks > 1 and (id .. ":" .. status.stacks) or id)
			local def = StatusDefinitions.ById[id]
			if def.Slow then
				slow = math.max(slow, def.Slow)
			end
		end
	end
	model:SetAttribute("Statuses", table.concat(parts, ","))
	model:SetAttribute("SpeedMultiplier", 1 - slow)
end

function StatusService:SpeedMultiplier(model: Model?): number
	return (model and model:GetAttribute("SpeedMultiplier")) or 1
end

function StatusService:OutgoingMultiplier(model: Model?): number
	local record = model and records[model]
	if record and record.statuses.Weaken then
		return StatusDefinitions.ById.Weaken.OutgoingMultiplier
	end
	return 1
end

-- statusId from StatusDefinitions; attacker gets credit for damage ticks.
function StatusService:Apply(target: Model, statusId: string, attacker: Model?)
	local def = StatusDefinitions.Get(statusId)
	if not def or not target.Parent then
		return
	end
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if statusId == "Shock" then
		-- Instant burst + chain to one nearby enemy of the same side.
		self:DealStatusDamage(target, attacker, def.BurstDamage, "Shock")
		local root = target:FindFirstChild("HumanoidRootPart")
		if root then
			local sameSide = CollectionService:HasTag(target, "Enemy")
			for _, other in CollectionService:GetTagged(sameSide and "Enemy" or "Nightmare") do
				local otherRoot = other:FindFirstChild("HumanoidRootPart")
				if other ~= target and otherRoot and Util.FlatDistance(otherRoot.Position, root.Position) <= def.ChainRadius then
					self:DealStatusDamage(other, attacker, def.BurstDamage * def.ChainFraction, "Shock")
					Net.FireNearby(self.Feedback, root.Position, Config.Performance.EffectRadius, "Chain", { From = root.Position, To = otherRoot.Position })
					break
				end
			end
		end
	end

	local record = getRecord(target)
	local now = os.clock()
	local status = record.statuses[statusId]
	if status then
		status.stacks = math.min(def.MaxStacks, status.stacks + 1)
		status.expires = now + def.Duration
		status.source = attacker
	else
		record.statuses[statusId] = { stacks = 1, expires = now + def.Duration, nextTick = now + (def.TickInterval or 1), source = attacker }
	end
	publish(target, record)
	local position = target:GetPivot().Position
	Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "Status", { Target = target, Status = statusId, Position = position })
end

function StatusService:DealStatusDamage(target: Model, attacker: Model?, amount: number, statusId: string)
	if not attacker or not attacker.Parent then
		-- Source gone (e.g. despawned): still tick, attributed to nobody.
		attacker = nil
	end
	self.Services.CombatService:ApplyDamage({
		Attacker = attacker or target, -- CanDamage() rejects self-damage, so handle below
		Target = target,
		BaseDamage = amount,
		AttackPower = 100,
		IgnoreDefence = true,
		Unblockable = true,
		NoStatus = true,
		AllowSourceless = attacker == nil,
		Source = "Status:" .. statusId,
	})
end

function StatusService:Clear(model: Model)
	records[model] = nil
end

function StatusService:Start()
	local interval = 1 / Config.Status.TickRate
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < interval then
			return
		end
		local step = accumulated
		accumulated = 0
		local now = os.clock()
		for model, record in records do
			if not model.Parent then
				records[model] = nil
				continue
			end
			-- Stagger decay
			if record.stagger > 0 and now - record.lastStagger > S.DecayDelay then
				record.stagger = math.max(0, record.stagger - S.DecayPerSecond * step)
				model:SetAttribute("Stagger", math.floor(record.stagger))
			end
			-- Status ticks & expiry
			local changed = false
			for id, status in record.statuses do
				local def = StatusDefinitions.ById[id]
				if now >= status.expires then
					record.statuses[id] = nil
					changed = true
				elseif def.TickDamage and now >= status.nextTick then
					status.nextTick = now + def.TickInterval
					self:DealStatusDamage(model, status.source, def.TickDamage * status.stacks, id)
				end
			end
			if changed then
				publish(model, record)
			end
		end
	end)
end

return StatusService
