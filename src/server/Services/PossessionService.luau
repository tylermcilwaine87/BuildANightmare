--[[
	PossessionService  (ModuleScript)
	Location: ServerScriptService/Server/Services/PossessionService

	NIGHTMARE POSSESSION: take direct control of your Nightmare for 10 seconds.

	METER (0-100, attribute "Possession" on the character), filled by:
	  Handler hits, Nightmare hits (more on a commanded target), ability hits, and
	  PERFECT DODGES (dodging through an enemy attack). Can't fill while possessing.

	ACTIVATE (F) when full and off cooldown:
	  * Network ownership of the Nightmare goes to the player, so movement is instant
	    and responsive. The companion AI pauses.
	  * The Handler channels: can't move or attack, takes 50% damage (not immune).
	    A heavy/knockback hit on the Handler, or a Handler KO, INTERRUPTS possession
	    and the remaining time is lost.
	  * Attacks are still SERVER-TIMED: the client only requests NM_Light, NM_Heavy, NM_Dodge,
	    abilities and the Ultimate; this service validates them.
	  * UNLEASHED: a possessed Nightmare has its own heavy-hitting moveset (Config.Possession
	    .Rampage, NightmareAIService:StartRage): ATTACK chains haymaker, elbow, launching
	    uppercut and a two-fist floor smash; HEAVY grabs and slams what it can lift, or
	    crushing-leaps onto anything else.
	  * Anti-exploit: the server watches the Nightmare's position. Teleporting, moving
	    faster than its stats allow or leaving the Handler's range ends possession and
	    snaps it back.
	ENDS after 10s, on F, on interruption, or if the Nightmare/Handler goes down.
	Then a 45s cooldown starts.

	Client notifications via PlayerFX: "PossessStart" { Model, Duration }, "PossessEnd" { Reason },
	"PossessDenied" { Text }.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local PossessionService = {}

local P = Config.Possession
local states: { [Player]: any } = {}
local invulnerableNightmares: { [Model]: number } = {}

local function getState(player: Player)
	local state = states[player]
	if not state then
		state = { Meter = 0, Active = false, EndsAt = 0, CooldownUntil = 0, Brain = nil, LastPosition = nil, LastCheck = 0, DodgeReadyAt = 0 }
		states[player] = state
	end
	return state
end

local function publish(player: Player, state)
	local character = player.Character
	if character then
		character:SetAttribute("Possession", math.floor(state.Meter))
		character:SetAttribute("Possessing", state.Active)
		character:SetAttribute("PossessionCooldownEnd", state.CooldownUntil - os.clock() + workspace:GetServerTimeNow())
	end
end

function PossessionService:Init(services)
	self.Services = services
	self.PlayerFX = Net.Get("PlayerFX")
end

function PossessionService:IsPossessing(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.Active
end

function PossessionService:IsNightmareInvulnerable(model: Model): boolean
	local untilTime = invulnerableNightmares[model]
	return untilTime ~= nil and os.clock() < untilTime
end

function PossessionService:Gain(player: Player, amount: number)
	local state = getState(player)
	if state.Active or amount <= 0 then
		return
	end
	state.Meter = math.min(P.MeterMax, state.Meter + amount)
	publish(player, state)
end

-- Duel rounds start with an empty meter and no cooldown, for both players equally.
function PossessionService:ResetForDuel(player: Player)
	self:End(player, "RoundOver")
	local state = getState(player)
	state.Meter = 0
	state.CooldownUntil = 0
	publish(player, state)
end

function PossessionService:Toggle(player: Player)
	local state = states[player]
	if state and state.Bound then
		return -- (NIGHTMARE UNDERGROUND: you ARE the Nightmare until the round's over)
	end
	if self:IsPossessing(player) then
		self:End(player, "Released")
	else
		self:Begin(player)
	end
end

-- NIGHTMARE UNDERGROUND (UndergroundService): the player drives their Nightmare until the
-- round is over. No meter, no timer, no cooldown, no Handler leash, and F doesn't let go.
function PossessionService:Bind(player: Player): boolean
	local state = getState(player)
	if state.Active then
		self:End(player, "Rebind")
	end
	return self:Begin(player, true)
end

function PossessionService:IsBound(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.Active and state.Bound == true
end

-- A body we know is about to move fast (thrown by a blow, knocked down): the anti-teleport
-- check lets it through for a moment.
function PossessionService:AllowBurst(model: Model, seconds: number?)
	for _, state in states do
		if state.Active and state.Brain and state.Brain.model == model then
			state.BurstUntil = math.max(state.BurstUntil or 0, os.clock() + (seconds or 1))
		end
	end
end

function PossessionService:Begin(player: Player, bound: boolean?)
	local state = getState(player)
	local now = os.clock()
	if state.Active then
		return false
	end
	if not bound and (state.Meter < P.MeterMax or now < state.CooldownUntil or self.Services.DuelService:IsFrozen(player)) then
		return false
	end
	local character = player.Character
	local handlerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	local brain = self.Services.NightmareAIService:GetBrain(player)
	if not handlerHumanoid or handlerHumanoid.Health <= 0 then
		return false
	end
	-- (the meter's full, so the HUD says READY: say why it isn't happening)
	if not brain or brain.humanoid.Health <= 0 then
		self.PlayerFX:FireClient(player, "PossessDenied", { Text = "Your Nightmare isn't here to possess." })
		return false
	end
	if not bound and self.Services.StatusService:IsStaggered(brain.model) then
		self.PlayerFX:FireClient(player, "PossessDenied", { Text = "Your Nightmare is staggered. Try again in a moment!" })
		return false
	end

	state.Active = true
	state.Bound = bound == true
	state.BurstUntil = 0
	if not bound then
		state.Meter = 0 -- (a bound fight leaves the companion meter as it was)
	end
	state.EndsAt = bound and math.huge or now + P.Duration
	state.Brain = brain
	state.LastPosition = brain.root.Position
	state.LastCheck = now

	if not bound then
		self.Services.ChallengeService:Notify(player, "Possessed")
	end

	-- Hand the body over to the player (your own guard comes down: you're not in that body now).
	if player.Character then
		self.Services.BlockService:Release(player.Character)
	end
	self.Services.NightmareAIService:DropGuard(brain)
	brain.possessedBy = player
	brain.queuedAbility = nil
	self.Services.NightmareAIService:StopFacing(brain)
	brain.humanoid.AutoRotate = true
	brain.humanoid.WalkSpeed = brain.stats.MoveSpeed
	brain.model:SetAttribute("PossessedBy", player.UserId)
	local ok = pcall(function()
		brain.root:SetNetworkOwner(player)
	end)
	if not ok then
		self:End(player, "Failed")
		return false
	end

	publish(player, state)
	self.PlayerFX:FireClient(player, "PossessStart", { Model = brain.model, Duration = not bound and P.Duration or nil, Bound = bound == true })
	return true
end

function PossessionService:End(player: Player, reason: string)
	local state = states[player]
	if not state or not state.Active then
		return
	end
	local wasBound = state.Bound
	state.Active = false
	state.Bound = false
	-- (a bound fight never starts the companion's possession cooldown)
	state.CooldownUntil = wasBound and state.CooldownUntil or os.clock() + P.Cooldown
	local brain = state.Brain
	state.Brain = nil
	if brain and brain.model.Parent then
		self.Services.BlockService:Release(brain.model)
		brain.possessedBy = nil
		brain.busyUntil = math.max(brain.busyUntil, os.clock() + 0.3)
		brain.model:SetAttribute("PossessedBy", nil)
		pcall(function()
			brain.root:SetNetworkOwner(nil)
		end)
	end
	publish(player, state)
	if player.Parent then
		self.PlayerFX:FireClient(player, "PossessEnd", { Reason = reason })
	end
end

------------------------------------------------------------------------------------------
-- Actions while possessed (all server-validated and server-timed)
------------------------------------------------------------------------------------------
local function activeBrain(self, player: Player)
	local state = states[player]
	if not state or not state.Active or not state.Brain then
		return nil
	end
	local brain = state.Brain
	if self.Services.DuelService:IsFrozen(player) then
		return nil -- (in your corner before FIGHT, or the round's over)
	end
	if brain.humanoid.Health <= 0 or self.Services.NightmareAIService:IsBusy(brain) or self.Services.BlockService:IsHolding(brain.model) then
		return nil, brain
	end
	return brain
end

function PossessionService:PossessedAction(player: Player, action: string)
	local now = os.clock()
	local state = states[player]
	if action == "NM_Dodge" then
		local brain = state and state.Active and state.Brain
		if brain and now >= state.DodgeReadyAt and not self.Services.StatusService:IsStaggered(brain.model) and not self.Services.DuelService:IsFrozen(player) then
			state.DodgeReadyAt = now + P.DodgeCooldown
			invulnerableNightmares[brain.model] = now + P.DodgeInvulnerable
			state.DodgeAllowanceUntil = now + P.DodgeDuration + 0.3 -- let the burst through the speed check
		end
		return
	end

	if action ~= "NM_Light" and action ~= "NM_Heavy" then
		return
	end
	local kind = action == "NM_Light" and "Light" or "Heavy"
	local ai = self.Services.NightmareAIService
	local brain, busyBrain = activeBrain(self, player)
	if not brain then
		-- UNLEASHED: a press in the last moments of a blow is held for the next one, so a
		-- rhythm of clicks chains (one press held at most; a later one replaces it)
		if busyBrain and not self.Services.BlockService:IsHolding(busyBrain.model) then
			local wait = busyBrain.busyUntil - now
			if wait > 0 and wait <= P.Rampage.BufferTime then
				state.buffered = kind
				local token = (state.bufferToken or 0) + 1
				state.bufferToken = token
				task.delay(wait + 0.01, function()
					if state.bufferToken == token and state.buffered then
						local queued = state.buffered
						state.buffered = nil
						local ready = activeBrain(self, player)
						if ready then
							ai:StartRage(ready, queued, os.clock())
						end
					end
				end)
			end
		end
		return
	end
	state.buffered = nil
	-- (a possessed Nightmare doesn't fight like the companion: Config.Possession.Rampage)
	ai:StartRage(brain, kind, now)
end

-- Blocking with the Nightmare you're controlling (hold; while it's up it can't attack).
function PossessionService:PossessedGuard(player: Player, wanted: boolean)
	local state = states[player]
	local brain = state and state.Active and state.Brain
	if not brain then
		return
	end
	local block = self.Services.BlockService
	if not wanted then
		block:Release(brain.model)
	elseif activeBrain(self, player) then
		block:Press(brain.model)
	end
end

function PossessionService:PossessedAbility(player: Player, slot: number)
	local brain = activeBrain(self, player)
	if not brain then
		return
	end
	local abilities = self.Services.AbilityService
	if not abilities:IsReady(brain, slot) then
		return
	end
	-- Aim: the nearest enemy roughly in front (a duel's opponents too), else straight ahead.
	local best, bestDistance = nil, 30
	local look = Util.FlatUnit(brain.root.CFrame.LookVector) or Vector3.zAxis
	local candidates = table.clone(game:GetService("CollectionService"):GetTagged("Enemy"))
	for _, model in self.Services.DuelService:GetOpponentModels(player) do
		table.insert(candidates, model)
	end
	for _, enemy in candidates do
		local root = enemy:FindFirstChild("HumanoidRootPart")
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local offset = Util.Flat(root.Position - brain.root.Position)
			if offset.Magnitude < bestDistance and (offset.Magnitude < 1 or look:Dot(offset.Unit) > 0.3) then
				best, bestDistance = enemy, offset.Magnitude
			end
		end
	end
	abilities:Execute(brain, slot, best)
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function PossessionService:Start()
	local combat = self.Services.CombatService
	local gains = P.Gains

	-- Meter gains from dealing damage.
	combat:OnDamaged(function(target, attacker, amount, params)
		if not attacker or amount <= 0 then
			return
		end
		local player = combat:GetOwnerPlayer(attacker)
		if not player then
			return
		end
		if attacker == player.Character then
			self:Gain(player, gains.HandlerHit)
		elseif params and type(params.Source) == "string" and string.sub(params.Source, 1, 8) == "Ability:" then
			self:Gain(player, gains.AbilityHit)
		else
			local brain = self.Services.NightmareAIService:GetBrain(player)
			local commanded = brain and brain.command == "Attack" and brain.commandTarget == target
			self:Gain(player, commanded and gains.CommandedHit or gains.NightmareHit)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local state = getState(player)
			if state.Active then
				self:End(player, "HandlerDown")
			end
			task.defer(publish, player, state)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			self:End(player, "HandlerDown")
			task.defer(publish, player, getState(player))
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:End(player, "Left")
		states[player] = nil
	end)

	-- 10 Hz watchdog: expiry, KOs, distance and speed (anti-teleport).
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.1 then
			return
		end
		accumulated = 0
		local now = os.clock()
		for player, state in states do
			if not state.Active then
				continue
			end
			local brain = state.Brain
			local character = player.Character
			local handlerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
			local handlerRoot = character and character:FindFirstChild("HumanoidRootPart")
			if now >= state.EndsAt then
				self:End(player, "Expired")
			elseif not brain or not brain.model.Parent or brain.humanoid.Health <= 0 then
				self:End(player, "NightmareDown")
			elseif not handlerHumanoid or handlerHumanoid.Health <= 0 or not handlerRoot then
				self:End(player, "HandlerDown")
			else
				local position = brain.root.Position
				local elapsed = math.max(now - state.LastCheck, 0.05)
				local speed = Util.FlatDistance(position, state.LastPosition) / elapsed
				local allowed = brain.stats.MoveSpeed * P.SpeedTolerance + 8
				if state.DodgeAllowanceUntil and now < state.DodgeAllowanceUntil then
					allowed += P.DodgeSpeed
				end
				if now < (state.BurstUntil or 0) then
					allowed += 160 -- (thrown by a blow: AllowBurst)
				end
				if speed > allowed + 60 then -- abilities like Blink Dash also move fast briefly
					self.Services.AntiExploitService:Flag(player, "PossessionSpeed")
					brain.model:PivotTo(CFrame.new(state.LastPosition) * brain.root.CFrame.Rotation)
					if state.Bound then
						-- (a fight goes on: snapped back to where it was, not taken away)
						state.LastCheck = now
					else
						self:End(player, "Invalid")
					end
				elseif not state.Bound and Util.FlatDistance(position, handlerRoot.Position) > P.MaxDistanceFromHandler then
					self:End(player, "TooFar")
				else
					state.LastPosition = position
					state.LastCheck = now
				end
			end
		end
	end)
end

return PossessionService
