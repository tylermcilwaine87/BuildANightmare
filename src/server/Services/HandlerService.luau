--[[
	HandlerService  (ModuleScript)
	Location: ServerScriptService/Server/Services/HandlerService

	Server-authoritative Handler (player avatar) combat state:
	  * Stamina (attribute "Stamina" on the character, regenerates after a short delay)
	  * Dodge: costs 25 stamina, 1s cooldown, 0.3s invulnerability. The CLIENT moves the
	    character (it owns its physics); the SERVER decides stamina, cooldown and i-frames.
	  * Guard: 0.15s startup, -65% blockable damage (heavy attacks: -30%), drains stamina
	    per damage absorbed, breaks at 0 stamina (1.2s stun, can't guard).
	Attributes replicated on the character: Stamina, MaxStamina, Guarding, GuardBroken.

	CombatService calls :ModifyIncomingDamage() for every hit on a Handler.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local HandlerService = {}

local H = Config.Handler
local states: { [Player]: any } = {}

local function newState()
	return {
		Stamina = H.Stamina.Max,
		LastSpend = 0,
		LastDodge = -math.huge,
		InvulnerableUntil = 0,
		GuardRequested = false,
		GuardActiveAt = math.huge,
		GuardBrokenUntil = 0,
	}
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function HandlerService:Init(services)
	self.Services = services
	self.Feedback = Net.Get("CombatFeedback")
end

function HandlerService:Start()
	local function onPlayer(player: Player)
		states[player] = newState()
		-- Shift is our dodge key: turn off Shift-Lock so the two don't fight.
		player.DevEnableMouseLock = false
		player.CharacterAdded:Connect(function(character)
			states[player] = newState()
			character:SetAttribute("MaxStamina", H.Stamina.Max)
			character:SetAttribute("Stamina", H.Stamina.Max)
			character:SetAttribute("Guarding", false)
			character:SetAttribute("GuardBroken", false)
		end)
		if player.Character then
			player.Character:SetAttribute("MaxStamina", H.Stamina.Max)
			player.Character:SetAttribute("Stamina", H.Stamina.Max)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	-- 10 Hz stamina / guard upkeep.
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.1 then
			return
		end
		local step = accumulated
		accumulated = 0
		local now = os.clock()
		for player, state in states do
			self:Tick(player, state, now, step)
		end
	end)
end

function HandlerService:Tick(player: Player, state, now: number, dt: number)
	local character = player.Character
	local humanoid = getHumanoid(player)
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	local guarding = self:IsGuarding(player)
	if not guarding and now - state.LastSpend >= H.Stamina.RegenDelay and state.Stamina < H.Stamina.Max then
		state.Stamina = math.min(H.Stamina.Max, state.Stamina + H.Stamina.RegenPerSecond * dt)
	end

	local broken = now < state.GuardBrokenUntil
	local walkSpeed = 16
	if self.Services.PossessionService:IsPossessing(player) or self.Services.DuelService:IsFrozen(player) then
		walkSpeed = 0 -- channelling: the Handler stands still while you control the Nightmare
	elseif broken then
		walkSpeed = H.Guard.BreakWalkSpeed
	elseif state.GuardRequested then
		walkSpeed = H.Guard.WalkSpeed
	end
	local cap = self.Services.MeleeService:WalkSpeedCap(player) -- the Magnet held: walk, don't run
	if cap then
		walkSpeed = math.min(walkSpeed, cap)
	end
	walkSpeed *= self.Services.StatusService:SpeedMultiplier(character)
	if humanoid.WalkSpeed ~= walkSpeed then
		humanoid.WalkSpeed = walkSpeed
	end

	character:SetAttribute("Stamina", math.floor(state.Stamina + 0.5))
	character:SetAttribute("Guarding", guarding)
	character:SetAttribute("GuardBroken", broken)
end

function HandlerService:Spend(state, amount: number)
	state.Stamina = math.max(0, state.Stamina - amount)
	state.LastSpend = os.clock()
end

function HandlerService:IsGuarding(player: Player): boolean
	local state = states[player]
	if not state then
		return false
	end
	local now = os.clock()
	return state.GuardRequested and now >= state.GuardActiveAt and now >= state.GuardBrokenUntil
end

function HandlerService:IsInvulnerable(player: Player): boolean
	local state = states[player]
	return state ~= nil and os.clock() < state.InvulnerableUntil
end

-- Returns true if the dodge was accepted (stamina spent, i-frames granted).
local DODGE_POSES = { Dive = true, DodgeLeft = true, DodgeRight = true }
function HandlerService:TryDodge(player: Player, pose: string?): boolean
	local state = states[player]
	local humanoid = getHumanoid(player)
	if not state or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local now = os.clock()
	if now - state.LastDodge < H.Dodge.Cooldown - 0.05 or state.Stamina < H.Dodge.StaminaCost or now < state.GuardBrokenUntil then
		return false
	end
	if self.Services.PossessionService:IsPossessing(player) or self.Services.DuelService:IsFrozen(player) then
		return false
	end
	if player.Character and player.Character:GetAttribute("Ragdolled") then
		return false -- knocked down: get up first
	end
	state.LastDodge = now
	self.Services.MeleeService:Interrupt(player) -- a dive cuts whatever strike you were in
	state.InvulnerableUntil = now + H.Dodge.InvulnerableTime
	state.PerfectCredited = false
	self:Spend(state, H.Dodge.StaminaCost)
	-- other players see the same roll: the forward dive or a side dive
	self.Services.MeleeService:StampPose(player.Character, DODGE_POSES[pose] and pose or "Dive")
	self.Services.TutorialService:Notify(player, "Dodged")
	return true
end

-- The STEP BACK: a short hop back. Cheaper than the dive, shorter i-frames, and it opens
-- the counter window (ConsumeCounter). Returns true if accepted.
function HandlerService:TryStepBack(player: Player): boolean
	local state = states[player]
	local humanoid = getHumanoid(player)
	if not state or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local cfg = H.StepBack
	local now = os.clock()
	if now - (state.LastStepBack or -math.huge) < cfg.Cooldown - 0.05 or state.Stamina < cfg.StaminaCost or now < state.GuardBrokenUntil then
		return false
	end
	if self.Services.PossessionService:IsPossessing(player) or self.Services.DuelService:IsFrozen(player) then
		return false
	end
	if player.Character and player.Character:GetAttribute("Ragdolled") then
		return false
	end
	state.LastStepBack = now
	self.Services.MeleeService:Interrupt(player) -- (so does a step back)
	state.CounterUsed = false
	state.InvulnerableUntil = math.max(state.InvulnerableUntil, now + cfg.InvulnerableTime)
	self:Spend(state, cfg.StaminaCost)
	self.Services.MeleeService:StampPose(player.Character, "StepBack")
	return true
end

-- True (once) if a counter attack is allowed right now: a step back happened within the
-- counter window (plus a little latency allowance).
function HandlerService:ConsumeCounter(player: Player): boolean
	local state = states[player]
	if not state or state.CounterUsed then
		return false
	end
	if os.clock() - (state.LastStepBack or -math.huge) > H.StepBack.CounterWindow + 0.15 then
		return false
	end
	state.CounterUsed = true
	return true
end

-- Fresh round in a duel: full stamina, no guard, no lingering i-frames or guard break.
function HandlerService:ResetForDuel(player: Player)
	local state = newState()
	states[player] = state
	local character = player.Character
	if character then
		character:SetAttribute("Stamina", state.Stamina)
		character:SetAttribute("Guarding", false)
		character:SetAttribute("GuardBroken", false)
	end
end

function HandlerService:SetGuard(player: Player, wanted: boolean)
	local state = states[player]
	if not state then
		return
	end
	if wanted and not state.GuardRequested then
		state.GuardRequested = true
		state.GuardActiveAt = os.clock() + H.Guard.Startup
	elseif not wanted then
		state.GuardRequested = false
		state.GuardActiveAt = math.huge
	end
end

--[[
	Called by CombatService for every hit on a Handler character.
	params.Unblockable -> guard has no effect; params.Heavy -> reduced block.
	Returns the adjusted damage (0 when dodged).
]]
function HandlerService:ModifyIncomingDamage(player: Player, amount: number, params): number
	local state = states[player]
	if not state then
		return amount
	end
	local possession = self.Services.PossessionService
	if os.clock() < state.InvulnerableUntil then
		-- A dodge that actually avoided an enemy hit charges the Possession Meter (once per dodge).
		if not state.PerfectCredited and params.Attacker and params.Attacker ~= player.Character then
			state.PerfectCredited = true
			possession:Gain(player, Config.Possession.Gains.PerfectDodge)
		end
		return 0
	end
	if possession:IsPossessing(player) then
		-- Channelling Handler: half damage, and big hits break the possession.
		amount *= 1 - Config.Possession.HandlerDamageReduction
		if params.Heavy or (params.Knockback or 0) >= Config.Possession.InterruptKnockback then
			possession:End(player, "Interrupted")
		end
		return amount
	end
	if params.Unblockable or not self:IsGuarding(player) then
		return amount
	end

	local reduction = params.Heavy and H.Guard.HeavyDamageReduction or H.Guard.DamageReduction
	local absorbed = amount * reduction
	self:Spend(state, absorbed * H.Guard.StaminaPerDamage * (params.Heavy and 2 or 1))

	local character = player.Character
	local position = character and character:GetPivot().Position or Vector3.zero
	if state.Stamina <= 0 then
		state.GuardBrokenUntil = os.clock() + H.Guard.BreakStunTime
		Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "GuardBreak", { Target = character, Position = position })
	else
		Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "Blocked", { Target = character, Position = position })
	end
	return amount - absorbed
end

return HandlerService
