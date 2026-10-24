--[[
	PassiveService  (ModuleScript)
	Location: ServerScriptService/Server/Services/PassiveService

	The part passives that react to hits (PassiveDefinitions):
	  Splinters  whoever hits the Nightmare up close takes splinter damage back (once a
	             second per attacker)
	  Glare      the Nightmare's hits CHILL the target, at most once every few seconds
	(The rest live where they act: Bouncy / Hover in RagdollService, Hover's floor hazards
	and Sturdy in CombatService, Afterimage and Sprint in NightmareAIService.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Passives = require(Shared:WaitForChild("PassiveDefinitions"))
local Util = require(Shared:WaitForChild("Util"))

local PassiveService = {}

local splinterReady = setmetatable({}, { __mode = "k" }) -- [Nightmare] = { [attacker] = os.clock() }
local glareReady = setmetatable({}, { __mode = "k" }) -- [Nightmare] = os.clock()

-- Damage that came from a passive or a status tick never triggers another passive.
local function triggers(params): boolean
	local source = params and params.Source or ""
	return source:sub(1, 8) ~= "Passive:" and source:sub(1, 7) ~= "Status:"
end

function PassiveService:OnHit(target: Model, attacker: Model?, params)
	if not attacker or not triggers(params) then
		return
	end
	local now = os.clock()
	local combat = self.Services.CombatService

	-- SPLINTERS: hit it up close and you get a faceful of splinters
	if Passives.Has(target, "Splinters") and combat:IsAlive(target) then
		local def = Passives.ById.Splinters
		local ready = splinterReady[target] or {}
		splinterReady[target] = ready
		local close = Util.FlatDistance(target:GetPivot().Position, attacker:GetPivot().Position) <= def.Range
		if close and now >= (ready[attacker] or 0) then
			ready[attacker] = now + def.Cooldown
			combat:ApplyDamage({
				Attacker = target,
				Target = attacker,
				BaseDamage = def.Damage,
				AttackPower = 100,
				NoKnockdown = true,
				Source = "Passive:Splinters",
			})
		end
	end

	-- GLARE: the Nightmare's hit locks eyes with them: CHILLED
	if Passives.Has(attacker, "Glare") and CollectionService:HasTag(attacker, "Nightmare") and now >= (glareReady[attacker] or 0) then
		local def = Passives.ById.Glare
		glareReady[attacker] = now + def.Cooldown
		self.Services.StatusService:Apply(target, def.Status, attacker)
	end
end

-- A RETALIATING shield was hit (Magma Shell): the attacker, if close, gets its status
-- (once a second each). Called by CombatService as the shield absorbs the blow.
local retaliateReady = setmetatable({}, { __mode = "k" }) -- [shielded model] = { [attacker] = os.clock() }
function PassiveService:Retaliate(target: Model, attacker: Model?, params)
	if not attacker or not triggers(params) or attacker == target then
		return
	end
	local status = target:GetAttribute("RetaliateStatus")
	local range = target:GetAttribute("RetaliateRange") or 10
	if type(status) ~= "string" or Util.FlatDistance(target:GetPivot().Position, attacker:GetPivot().Position) > range then
		return
	end
	local ready = retaliateReady[target] or {}
	retaliateReady[target] = ready
	local now = os.clock()
	if now >= (ready[attacker] or 0) then
		ready[attacker] = now + 1
		self.Services.StatusService:Apply(attacker, status, target)
	end
end

function PassiveService:Init(services)
	self.Services = services
end

function PassiveService:Start()
	self.Services.CombatService:OnDamaged(function(target, attacker, _, params)
		self:OnHit(target, attacker, params or {})
	end)
end

return PassiveService
