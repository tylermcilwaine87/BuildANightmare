--[[
	BlockService  (ModuleScript)
	Location: ServerScriptService/Server/Services/BlockService

	BLOCKING, the same for every body that can do it: your Handler, a Nightmare you possess, and
	a Nightmare's combat brain. Server-authoritative; tuned in Config.Block.

	  The guard meter (attribute "GuardLevel", absent when full) is how long the stance holds.
	    Holding it drains it, and so does every blow it stops (Heavy and GuardBreak blows far more).
	    It only refills after a moment with the guard DOWN, so turtling isn't free.
	  Above CrackAt   a blow barely gets through.
	  Below CrackAt   the stance is failing (the clients sag and shake it by GuardLevel): more and
	                  more of each blow gets through, all the way down to LeakReduction.
	  At zero         the guard BREAKS: the crumble animation, BrokenTime with no guard and no dodge,
	                  so whoever broke it gets a free punish.
	  From behind     (outside ArcDot of where it faces) a guard stops nothing: go round a turtle.
	  Grabs and Unblockable moves go straight through, and a parry (HandlerService) beats all of it.

	So in a duel: light blows make someone block, blocking gives the attacker the initiative, and a
	Heavy, a GuardBreak string, a flank or a grab is how you open them up. Bosses keep their own
	reductions, so a stance is no easier against them than it was.

	Replicated: GuardLevel (0-100), Guarding (hands up, set as soon as it's pressed), GuardBroken.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local BlockService = {}

local B = Config.Block
local states = setmetatable({}, { __mode = "k" }) -- [Model] = its guard

local function stateOf(body: Model)
	local state = states[body]
	if not state then
		state = { Level = B.Max, Holding = false, ActiveAt = math.huge, BrokenUntil = 0, RegenAt = 0, LastRelease = -math.huge }
		states[body] = state
	end
	return state
end

local function publish(body: Model, state)
	-- (nothing to replicate while it's full, and whole numbers only)
	local level = state.Level < B.Max and math.ceil(state.Level) or nil
	if body:GetAttribute("GuardLevel") ~= level then
		body:SetAttribute("GuardLevel", level)
	end
end

function BlockService:Init(services)
	self.Services = services
	self.Feedback = Net.Get("CombatFeedback")
end

-- Hands up. False if the guard is broken. A fresh press straight after letting go costs a bit:
-- flicking it on and off doesn't get a free guard.
function BlockService:Press(body: Model, startup: number?): boolean
	local state = stateOf(body)
	local now = os.clock()
	if state.Holding then
		return true
	elseif now < state.BrokenUntil then
		return false
	end
	if now - state.LastRelease < B.RegenDelay then
		state.Level = math.max(1, state.Level - B.RepressCost)
	end
	state.Holding = true
	state.ActiveAt = now + (startup or B.Startup)
	body:SetAttribute("Guarding", true)
	publish(body, state)
	return true
end

function BlockService:Release(body: Model)
	local state = states[body]
	if state and state.Holding then
		local now = os.clock()
		state.Holding = false
		state.ActiveAt = math.huge
		state.LastRelease = now
		state.RegenAt = math.max(state.RegenAt, now + B.RegenDelay)
		body:SetAttribute("Guarding", nil)
	end
end

-- Hands up, whether or not the startup has finished (it can't throw anything like this).
function BlockService:IsHolding(body: Model?): boolean
	local state = body and states[body]
	return state ~= nil and state.Holding
end

function BlockService:IsBroken(body: Model?): boolean
	local state = body and states[body]
	return state ~= nil and os.clock() < state.BrokenUntil
end

-- Knocked out of being able to guard for a moment (a broken guard, a parried strike).
function BlockService:Stun(body: Model, time: number)
	local state = stateOf(body)
	local now = os.clock()
	self:Release(body)
	state.BrokenUntil = math.max(state.BrokenUntil, now + time)
	state.RegenAt = math.max(state.RegenAt, state.BrokenUntil + B.RegenDelay * 0.5)
	body:SetAttribute("GuardBroken", true)
end

function BlockService:Break(body: Model, attacker: Model?)
	local state = stateOf(body)
	state.Level = 0
	self:Stun(body, B.BrokenTime)
	publish(body, state)
	local services = self.Services
	local player = Players:GetPlayerFromCharacter(body)
	if player then
		services.HandlerService:OnGuardBroken(player)
	else
		services.NightmareAIService:OnGuardBroken(body)
	end
	local position = body:GetPivot().Position
	Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "GuardBreak", { Target = body, Attacker = attacker, Position = position })
end

-- What's left of a blow after the guard. Returns amount, stopped by a guard, broke the guard.
function BlockService:Resolve(body: Model, amount: number, attacker: Model?, params)
	local state = states[body]
	local now = os.clock()
	if params.Unblockable or not state or not state.Holding or now < state.ActiveAt or now < state.BrokenUntil then
		return amount, false, false
	end
	-- only what's in front of it: a guard doesn't cover its back
	if attacker then
		local facing = Util.FlatUnit(body:GetPivot().LookVector)
		local toward = Util.FlatUnit(attacker:GetPivot().Position - body:GetPivot().Position)
		if facing and toward and facing:Dot(toward) < B.ArcDot then
			return amount, false, false
		end
	end
	local boss = attacker ~= nil and CollectionService:HasTag(attacker, "Boss")
	local reduction
	if boss then
		reduction = params.Heavy and B.BossHeavyReduction or B.BossReduction
	else
		reduction = params.Heavy and B.HeavyReduction or B.Reduction
	end
	-- below CrackAt the stance is failing: the lower it gets, the more comes through
	local failing = math.clamp(1 - state.Level / B.CrackAt, 0, 1)
	reduction += (B.LeakReduction - reduction) * failing

	-- what the blow costs it, by how hard it was for this body
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	local share = amount / math.max(humanoid and humanoid.MaxHealth or 100, 1) * 100
	local cost = (B.HitCost + share * B.CostPerPercent) * (params.Heavy and B.HeavyCost or 1) * (params.GuardBreak and B.GuardBreakCost or 1)
	state.Level = math.max(0, state.Level - cost)
	state.RegenAt = math.max(state.RegenAt, now + B.RegenDelay)
	local through = amount * (1 - reduction)
	if state.Level <= 0 then
		self:Break(body, attacker)
		return through, true, true
	end
	publish(body, state)
	return through, true, false
end

-- Studio: put a stance at a level, to look at it or test from there (tools/BlockLab).
function BlockService:DevSetLevel(body: Model, level: number)
	if RunService:IsStudio() then
		local state = stateOf(body)
		state.Level = level
		state.RegenAt = os.clock() + 60
		publish(body, state)
	end
end

function BlockService:Start()
	-- 10 Hz, like the rest of the Handler's upkeep
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.1 then
			return
		end
		local step = accumulated
		accumulated = 0
		local now = os.clock()
		for body, state in states do
			if not body.Parent then
				states[body] = nil
				continue
			end
			if state.Holding then
				if body:GetAttribute("GuardSteady") then
					-- (the Training Arena's Guard Dummy: it never tires of holding it, and it
					-- recovers between your attempts, only blows wear it down)
					if now >= state.RegenAt and state.Level < B.Max then
						state.Level = math.min(B.Max, state.Level + B.RegenPerSecond * step)
					end
				elseif now >= state.ActiveAt then
					state.Level = math.max(0, state.Level - B.HoldDrain * step)
					if state.Level <= 0 then
						self:Break(body, nil) -- it just couldn't hold it up any longer
					end
				end
			elseif now >= state.BrokenUntil then
				if body:GetAttribute("GuardBroken") then
					body:SetAttribute("GuardBroken", nil)
					state.Level = math.max(state.Level, B.AfterBreak)
				end
				if now >= state.RegenAt and state.Level < B.Max then
					state.Level = math.min(B.Max, state.Level + B.RegenPerSecond * step)
				end
			end
			publish(body, state)
		end
	end)
end

return BlockService
