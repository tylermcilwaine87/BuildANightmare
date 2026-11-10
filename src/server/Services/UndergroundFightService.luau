--[[
	UndergroundFightService  (ModuleScript)
	Location: ServerScriptService/Server/Services/UndergroundFightService

	NIGHTMARE UNDERGROUND, phase 2: how a fighter you're driving FIGHTS (Config.Underground.Fight).
	PossessionService hands every input from a bound player (PossessionService:Bind) to this
	service instead of the possession RAMPAGE moveset.

	  STRINGS      L (attack) and H (power) presses build a string: L jab, LL cross, LLL lead hook,
	               LLLL uppercut; H overhand; LH liver shot, LHL body-head, LHH body blast, LLH
	               one-two-overhand, LLLH the launcher. Each press throws ONE strike (its own
	               keyframed clip, NightmarePoses "UG_*"), timed and landed by the server
	               (NightmareAIService:StartString). A four-legged body has its own strikes on
	               the same buttons.
	  STAMINA      every strike costs it, body shots drain it; at 0 the fighter is GASSED (weak
	               strikes, no power shots) until it's back over Recovered.
	  GUARD        high by default; held while pulling back it drops to the body. A strike at the
	               other height goes round it (BlockService does the rest: the guard meter,
	               cracks, guard breaks).
	  PARRY        the guard raised just before a blow lands knocks it away and stuns the attacker.
	  SLIP         dodge + direction: off the line with i-frames; a blow that whiffs through it
	               opens a COUNTER window (the next strike hits harder).
	  FEINT        raising the guard during a power shot's wind-up pulls it.

	Everything is decided here, on the server: the client only sends presses (CombatAction
	NM_Light / NM_Heavy / NM_Dodge dir / NM_Guard wanted, low / NM_GuardLow low).
	Replicated on the body: UGStamina, UGGassed, GuardLow. Callouts: CombatFeedback "UGCallout".
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local UndergroundFightService = {}

local F = Config.Underground.Fight
local S = F.Stamina
local SLIP_ACTIONS = { Left = "Slip_L", Right = "Slip_R", Back = "PullBack", In = "RollUnder" }

local fighters: { [Model]: any } = {} -- [body] = its fight state

local function newState(player: Player)
	return {
		Player = player,
		Stamina = S.Max,
		LastSpend = -math.huge,
		Gassed = false,
		Chain = "",
		ChainResetAt = 0,
		PowerReadyAt = 0,
		CounterUntil = 0, -- your next strike is a counter until then
		CounterStrikeUntil = 0, -- the strike you're throwing is a counter until then
		SlipUntil = 0,
		SlipReadyAt = 0,
		ParryFrom = nil,
		LastGuardPress = -math.huge,
		GuardLow = false,
		Current = nil, -- the strike being thrown: { Def, Seq, HitAt, Token }
	}
end

local function publish(model: Model, state)
	local value = math.floor(state.Stamina + 0.5)
	if model:GetAttribute("UGStamina") ~= value then
		model:SetAttribute("UGStamina", value)
	end
	if (model:GetAttribute("UGGassed") == true) ~= state.Gassed then
		model:SetAttribute("UGGassed", state.Gassed or nil)
	end
end

function UndergroundFightService:Init(services)
	self.Services = services
	self.Feedback = Net.Get("CombatFeedback")
end

-- A fresh fighter (UndergroundService:PrepareFighter, and every round's countdown).
function UndergroundFightService:Register(model: Model, player: Player)
	local state = newState(player)
	fighters[model] = state
	model:SetAttribute("GuardLow", nil)
	publish(model, state)
end

function UndergroundFightService:IsFighter(model: Model?): boolean
	return model ~= nil and fighters[model] ~= nil
end

-- Studio (DevBridge): read a fighter's state, or put its stamina somewhere to test from.
function UndergroundFightService:DevState(model: Model, stamina: number?)
	local state = fighters[model]
	if not state or not RunService:IsStudio() then
		return nil
	end
	if stamina then
		state.Stamina = stamina
		state.LastSpend = os.clock() + 30
		state.Gassed = stamina <= 0
		publish(model, state)
	end
	return { Stamina = state.Stamina, Gassed = state.Gassed, Chain = state.Chain, GuardLow = state.GuardLow, Counter = os.clock() < state.CounterUntil }
end

-- Shown over the body it's about, to everyone watching (UndergroundController).
function UndergroundFightService:Callout(model: Model, text: string, kind: string?)
	local position = model:GetPivot().Position
	Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "UGCallout", { Target = model, Text = text, Kind = kind })
end

local function spend(model: Model, state, amount: number, now: number)
	state.Stamina = math.max(0, state.Stamina - amount)
	state.LastSpend = now
	publish(model, state)
end

local function gain(model: Model, state, amount: number)
	state.Stamina = math.min(S.Max, state.Stamina + amount)
	publish(model, state)
end

-- The body this player is driving in the Underground, and its state (nil if not fighting).
function UndergroundFightService:Fighter(player: Player)
	if not self.Services.PossessionService:IsBound(player) then
		return nil
	end
	local brain = self.Services.NightmareAIService:GetBrain(player)
	local state = brain and fighters[brain.model]
	if not state or not brain.possessedBy or brain.humanoid.Health <= 0 then
		return nil
	end
	return brain, state
end

local function movesFor(brain)
	return brain.model:GetAttribute("Archetype") == "Quadruped" and F.Moves.Quadruped or F.Moves.Biped
end

-- Can this body throw anything right now? (frozen in the corner, knocked down, stunned...)
function UndergroundFightService:CanAct(player: Player, brain): boolean
	local services = self.Services
	return not services.DuelService:IsFrozen(player)
		and not brain.model:GetAttribute("Ragdolled")
		and not services.StatusService:IsStaggered(brain.model)
		and not services.BlockService:IsBroken(brain.model)
end

------------------------------------------------------------------------------------------
-- Strikes
------------------------------------------------------------------------------------------
function UndergroundFightService:Throw(player: Player, brain, state, kind: string, now: number): boolean
	local ai = self.Services.NightmareAIService
	if now > state.ChainResetAt then
		state.Chain = ""
	end
	local seq = state.Chain .. kind
	if not F.Strings[seq] then
		seq = kind
	end
	local def = movesFor(brain)[F.Strings[seq]]
	if not def then
		return false
	end
	if def.Power then
		if state.Gassed or state.Stamina < def.Cost * 0.5 then
			self:Callout(brain.model, "GASSED", "Bad")
			return false
		elseif now < state.PowerReadyAt then
			return false
		end
	end
	local target = ai:RageTarget(brain)
	if not ai:StartString(brain, def, target, now) then
		return false
	end
	spend(brain.model, state, def.Cost, now)
	-- the next press comes as soon as this strike has landed and recovered
	local speedScale = 100 / brain.stats.AttackSpeed
	brain.busyUntil = now + (def.Hits[#def.Hits][1] + def.Recovery) * speedScale
	brain.cancelableAt = brain.busyUntil
	brain.target = target or brain.target
	state.Chain = F.Ends[seq] and "" or seq
	state.ChainResetAt = brain.busyUntil + F.ResetTime
	state.Current = { Def = def, Seq = seq, HitAt = now + def.Hits[1][1] * speedScale, Token = brain.castToken }
	-- thrown out of a slip or a parry: a COUNTER (this strike only)
	if now < state.CounterUntil then
		state.CounterUntil = 0
		state.CounterStrikeUntil = brain.busyUntil
	end
	if def.Power then
		state.PowerReadyAt = brain.busyUntil + F.PowerCooldown
	end
	return true
end

-- NM_Light / NM_Heavy from a bound player. A press in the last moments of a strike is held for
-- the next one, so a rhythm of clicks chains (one press held; a later one replaces it).
function UndergroundFightService:Action(player: Player, kind: string)
	local brain, state = self:Fighter(player)
	if not brain or (kind ~= "L" and kind ~= "H") then
		return
	end
	local now = os.clock()
	local services = self.Services
	if not self:CanAct(player, brain) or services.BlockService:IsHolding(brain.model) then
		return
	end
	local ai = services.NightmareAIService
	if ai:IsBusy(brain) then
		local wait = brain.busyUntil - now
		if wait > 0 and wait <= F.BufferTime then
			state.Buffered = kind
			local token = (state.BufferToken or 0) + 1
			state.BufferToken = token
			task.delay(wait + 0.01, function()
				if state.BufferToken ~= token or not state.Buffered then
					return
				end
				local queued = state.Buffered
				state.Buffered = nil
				local again, againState = self:Fighter(player)
				if again == brain and againState == state and self:CanAct(player, brain) and not ai:IsBusy(brain)
					and not services.BlockService:IsHolding(brain.model) then
					self:Throw(player, brain, state, queued, os.clock())
				end
			end)
		end
		return
	end
	state.Buffered = nil
	self:Throw(player, brain, state, kind, now)
end

------------------------------------------------------------------------------------------
-- Guard, parry, feint
------------------------------------------------------------------------------------------
function UndergroundFightService:Guard(player: Player, wanted: boolean, low: boolean?)
	local brain, state = self:Fighter(player)
	if not brain then
		return
	end
	local services = self.Services
	local block = services.BlockService
	local ai = services.NightmareAIService
	local model = brain.model
	local now = os.clock()
	-- (held: raised as soon as it can be, if it can't be right now: the Heartbeat below)
	state.GuardWanted = wanted
	if not wanted then
		block:Release(model)
		state.ParryFrom = nil
		state.GuardLow = false
		model:SetAttribute("GuardLow", nil)
		return
	end
	state.GuardLow = low == true
	model:SetAttribute("GuardLow", state.GuardLow or nil)
	if block:IsHolding(model) then
		return
	end
	-- FEINT: the guard during a power shot's wind-up pulls it
	local current = state.Current
	if current and current.Def.Power and brain.castToken == current.Token and now < current.HitAt - F.Feint.FeintBefore then
		brain.castToken += 1
		brain.busyUntil = now + F.Feint.Recover
		brain.cancelableAt = brain.busyUntil
		state.Current = nil
		state.Chain = ""
		state.CounterStrikeUntil = 0
		state.PowerReadyAt = now + F.Feint.Recover
		spend(model, state, F.Feint.Cost, now)
		ai:PlayAction(brain, F.Feint.Action, 0, 0.45)
		self:Callout(model, "FEINT", "Info")
		return
	end
	if ai:IsBusy(brain) or not self:CanAct(player, brain) then
		return
	end
	if block:Press(model) then
		state.ParryFrom = now - state.LastGuardPress >= F.Parry.Lockout and now or nil
		state.LastGuardPress = now
		state.Buffered = nil
	end
end

function UndergroundFightService:SetGuardLow(player: Player, low: boolean)
	local brain, state = self:Fighter(player)
	if brain then
		state.GuardLow = low == true
		brain.model:SetAttribute("GuardLow", state.GuardLow or nil)
	end
end

-- `attacker`'s strike met a guard the instant it came up: knocked away.
function UndergroundFightService:Parried(attacker: Model, target: Model, targetState)
	local services = self.Services
	local ai = services.NightmareAIService
	local now = os.clock()
	local brain = ai:GetBrainByModel(attacker)
	if brain then
		brain.castToken += 1
		brain.busyUntil = now + F.Parry.AttackerStun
		brain.cancelableAt = brain.busyUntil
		ai:PlayAction(brain, "UG_Parried", 0, 0.7)
	end
	local attackerState = fighters[attacker]
	if attackerState then
		attackerState.Chain = ""
		attackerState.Current = nil
		attackerState.Buffered = nil
		attackerState.CounterStrikeUntil = 0
	end
	services.BlockService:Stun(attacker, F.Parry.AttackerStun)
	targetState.ParryFrom = nil
	targetState.CounterUntil = now + F.CounterWindow
	gain(target, targetState, F.Parry.StaminaGain)
	self:Callout(target, "PARRY!", "Good")
	local position = target:GetPivot().Position
	Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "Parried", { Target = target, Attacker = attacker, Position = position })
end

------------------------------------------------------------------------------------------
-- Slips
------------------------------------------------------------------------------------------
function UndergroundFightService:Dodge(player: Player, direction: string?)
	local brain, state = self:Fighter(player)
	if not brain then
		return
	end
	local services = self.Services
	local ai = services.NightmareAIService
	local now = os.clock()
	local slip = F.Slip
	if now < state.SlipReadyAt or ai:IsBusy(brain) or not self:CanAct(player, brain) then
		return
	end
	if state.Stamina < slip.Cost * 0.5 then
		self:Callout(brain.model, "GASSED", "Bad")
		return
	end
	direction = SLIP_ACTIONS[direction or ""] and direction or "Back"
	local cfg = (direction == "Left" or direction == "Right") and slip.Side or slip[direction]
	services.BlockService:Release(brain.model)
	state.SlipReadyAt = now + slip.Cooldown
	state.SlipUntil = now + slip.Invulnerable
	state.SlipCredited = false
	state.Buffered = nil
	spend(brain.model, state, slip.Cost, now)
	brain.busyUntil = now + cfg.Time + 0.06
	brain.cancelableAt = brain.busyUntil
	ai:PlayAction(brain, SLIP_ACTIONS[direction], 0, 0.5)
	-- (the client moves the body: it's theirs. Let the burst through the speed check.)
	services.PossessionService:AllowBurst(brain.model, cfg.Time + 0.4)
end

------------------------------------------------------------------------------------------
-- A blow on a fighter (CombatService:ApplyDamage, before invulnerability and the guard).
-- Returns what's left of it (0: slipped or parried). May set params.Unblockable (it went round
-- the guard) and params.UGCounter.
------------------------------------------------------------------------------------------
function UndergroundFightService:Incoming(attacker: Model?, target: Model, amount: number, params): number
	local targetState = fighters[target]
	if not targetState or not attacker then
		return amount
	end
	local now = os.clock()
	local attackerState = fighters[attacker]
	local block = self.Services.BlockService
	-- SLIPPED: it went past the head
	if now < targetState.SlipUntil then
		if not targetState.SlipCredited then
			targetState.SlipCredited = true
			targetState.CounterUntil = now + F.CounterWindow
			self:Callout(target, "SLIPPED", "Good")
		end
		return 0
	end
	-- PARRIED: the guard came up right on it
	if targetState.ParryFrom and now - targetState.ParryFrom <= F.Parry.Window and block:IsHolding(target) and not params.Unblockable and attackerState then
		self:Parried(attacker, target, targetState)
		return 0
	end
	-- the guard at the wrong height: it goes round it
	local move = params.Move
	if move and move.Height and block:IsHolding(target) and not params.Unblockable then
		local low = targetState.GuardLow == true
		if (move.Height == "Body") ~= low then
			params.Unblockable = true
			self:Callout(target, move.Height == "Body" and "UNDER THE GUARD" or "OVER THE GUARD", "Bad")
		end
	end
	if attackerState then
		if now < attackerState.CounterStrikeUntil then
			amount *= F.CounterDamage
			params.UGCounter = true
		end
		if attackerState.Gassed then
			amount *= S.GassedDamage
		end
	end
	return amount
end

function UndergroundFightService:Start()
	-- after a blow lands: body shots sap stamina, a guard costs a little, the combo's name
	self.Services.CombatService:OnDamaged(function(target, attacker, amount, params)
		local targetState = fighters[target]
		if not targetState or amount <= 0 then
			return
		end
		local now = os.clock()
		local move = params.Move
		if params.WasGuarded then
			spend(target, targetState, S.BlockedCost, now)
		elseif move and move.Drain then
			targetState.Stamina = math.max(0, targetState.Stamina - move.Drain)
			publish(target, targetState)
		end
		local attackerState = attacker and fighters[attacker]
		if attackerState and not params.WasGuarded then
			if params.UGCounter then
				self:Callout(attacker, "COUNTER!", "Good")
			end
			local current = attackerState.Current
			if current and move == current.Def and not current.Called then
				current.Called = true
				local name = F.Names[current.Seq]
				if name then
					self:Callout(attacker, name, "Combo")
				end
			end
		end
	end)

	-- stamina: back after a breather, slower behind a guard (10 Hz)
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		-- a guard held through a strike, a slip, a feint or a stun comes up the moment the
		-- fighter is free (no parry: that's only for a press timed on the blow)
		local block = self.Services.BlockService
		local ai = self.Services.NightmareAIService
		for model, state in fighters do
			if state.GuardWanted and model.Parent and not block:IsHolding(model) then
				local brain, current = self:Fighter(state.Player)
				if brain and current == state and not ai:IsBusy(brain) and self:CanAct(state.Player, brain) and block:Press(model) then
					state.ParryFrom = nil
					state.Buffered = nil
				end
			end
		end
		accumulated += dt
		if accumulated < 0.1 then
			return
		end
		local step = accumulated
		accumulated = 0
		local now = os.clock()
		local block = self.Services.BlockService
		for model, state in fighters do
			if not model.Parent then
				fighters[model] = nil
				continue
			end
			if state.Stamina <= 0 and not state.Gassed then
				state.Gassed = true
				self:Callout(model, "GASSED", "Bad")
			elseif state.Gassed and state.Stamina >= S.Recovered then
				state.Gassed = false
			end
			if now - state.LastSpend >= S.RegenDelay and state.Stamina < S.Max then
				local rate = block:IsHolding(model) and S.GuardRegen or S.Regen
				state.Stamina = math.min(S.Max, state.Stamina + rate * step)
			end
			publish(model, state)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for model, state in fighters do
			if state.Player == player then
				fighters[model] = nil
			end
		end
	end)
end

return UndergroundFightService
