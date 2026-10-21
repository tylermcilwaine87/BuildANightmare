--[[
	NightmareAIService  (ModuleScript)
	Location: ServerScriptService/Server/Services/NightmareAIService

	Companion AI for every summoned Nightmare. One shared loop ticks all brains at
	Config.Nightmare.AIUpdateRate (10 Hz), never one loop per Nightmare.

	Per tick, in priority order:
	  (possessed) the player is driving it: AI does nothing (PossessionService)
	  (staggered) stunned: do nothing
	  EVADE    standing in a hostile telegraph? Maybe step out (70% chance, 0.25-0.5s
	           reaction), deliberately imperfect so player decisions still matter
	  REACT    the target starts an attack close by: sometimes hop back / sidestep, often
	           followed by a dash straight back in with a hit (Config.Nightmare.Fight)
	  (busy)   mid-attack or mid-ability: hold, keep facing the target
	  ABILITY  a queued Q/E ability: path into range, then cast (AbilityService)
	  ENGAGE   close distance (sometimes with a dash-in lunge), face, 3-hit combo + HEAVY
	           attack on its cooldown; after a finisher it may hop out and circle the
	           target for a moment before going back in
	  FOLLOW   stay at the Handler's side; face the Handler when idle; idle personality

	Commands (remote NightmareCommand), shown on the HUD:
	  "Attack", target   focus a specific enemy
	  "Defend"           stay close, only fight enemies near the Handler (default)
	  "Aggressive"       hunt enemies further out, use heavy attacks more often
	  "Retreat"          ignore enemies and return to the Handler for a few seconds
	  "ToggleSummon"     summon / recall (forwarded to NightmareSpawnService)
	  (Q/E = USE ABILITY via CombatAction; "Follow" is accepted as an alias of Defend)

	Movement uses NavigationService (straight line when clear, pathfinding otherwise).
	Clients learn about attacks through attributes on the model:
	  ActionName, ActionWindup, ActionDuration, then ActionSeq (incremented last).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))

local NightmareAIService = {}

local brains = {} -- [Model] = brain
local brainByPlayer = {} -- [Player] = brain

local NM = Config.Nightmare
local HEAVY = Config.HeavyAttack

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
local function getHandlerRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function leashFor(brain, model: Model): number
	local base = CollectionService:HasTag(model, "Boss") and NM.BossLeashRadius or NM.LeashRadius
	if brain.command == "Aggressive" then
		base += Config.Commands.Aggressive.LeashBonus
	end
	return base
end

local duelService -- set in Init (opponent Handlers/Nightmares count as enemies in a live duel)

local function isValidEnemy(brain, model: Model?, handlerRoot: BasePart): boolean
	if not model or not model.Parent then
		return false
	end
	if not CollectionService:HasTag(model, "Enemy") and not duelService:IsOpponentModel(brain.owner, model) then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or model:GetAttribute("Defeated") then
		return false
	end
	return Util.FlatDistance(root.Position, handlerRoot.Position) <= leashFor(brain, model)
end

function NightmareAIService:SetSpeed(brain, speed: number)
	local wanted = speed * self.Services.StatusService:SpeedMultiplier(brain.model)
	if brain.humanoid.WalkSpeed ~= wanted then
		brain.humanoid.WalkSpeed = wanted
	end
end

function NightmareAIService:Stop(brain)
	brain.nav:Stop()
end

function NightmareAIService:StopFacing(brain)
	if brain.align.Enabled then
		brain.align.Enabled = false
		brain.humanoid.AutoRotate = true
	end
end

function NightmareAIService:Face(brain, position: Vector3)
	local direction = Util.FlatUnit(position - brain.root.Position)
	if not direction then
		return
	end
	brain.humanoid.AutoRotate = false
	brain.align.CFrame = CFrame.lookAt(Vector3.zero, direction)
	brain.align.Enabled = true
end

function NightmareAIService:MoveTo(brain, position: Vector3)
	self:StopFacing(brain)
	brain.nav:MoveTo(position)
end

function NightmareAIService:PlayAction(brain, name: string, windup: number, duration: number)
	local model = brain.model
	model:SetAttribute("ActionName", name)
	model:SetAttribute("ActionWindup", windup)
	model:SetAttribute("ActionDuration", duration)
	model:SetAttribute("ActionSeq", (model:GetAttribute("ActionSeq") or 0) + 1)
end

local function setCommand(brain, command: string, target: Model?)
	brain.command = command
	brain.commandTarget = target
	brain.target = target
	brain.model:SetAttribute("Command", command)
end

function NightmareAIService:GetBrain(player: Player)
	return brainByPlayer[player]
end

function NightmareAIService:GetBrainByModel(model: Model)
	return brains[model]
end

function NightmareAIService:IsBusy(brain): boolean
	return os.clock() < brain.busyUntil or self.Services.StatusService:IsStaggered(brain.model) or brain.model:GetAttribute("Ragdolled") == true
end

------------------------------------------------------------------------------------------
-- Attacks (also used by PossessionService while a player is driving)
------------------------------------------------------------------------------------------
local function ignoreList(brain)
	local ignore = { brain.model }
	if brain.owner.Character then
		table.insert(ignore, brain.owner.Character)
	end
	return ignore
end

-- On-hit status passives from parts (e.g. Venomous Spider Legs poison every hit).
local function rollOnHitStatus(brain, comboHit: number?): string?
	for _, rule in brain.onHit do
		if (not rule.ComboHit or rule.ComboHit == comboHit) and math.random() < (rule.Chance or 1) then
			return rule.Status
		end
	end
	return nil
end

function NightmareAIService:StartAttack(brain, now: number)
	if now > brain.comboResetAt then
		brain.comboIndex = 1
	end
	local hitIndex = brain.comboIndex
	local hit = NM.Combo[hitIndex]
	local speedScale = 100 / brain.stats.AttackSpeed
	local windup = hit.Windup * speedScale
	local recovery = hit.Recovery * speedScale

	brain.busyUntil = now + windup + recovery
	brain.cancelableAt = now + windup + 0.05 -- once the hit lands, a queued ability may cut the recovery
	brain.comboResetAt = brain.busyUntil + NM.ComboResetTime
	brain.comboIndex = brain.comboIndex % #NM.Combo + 1
	brain.finisherPending = hitIndex == #NM.Combo -- footwork after the last hit (Engage)
	if not brain.possessedBy then
		self:Stop(brain)
	end
	self:PlayAction(brain, hit.Name, windup, windup + recovery)

	local castToken = brain.castToken
	task.delay(windup, function()
		-- The Nightmare may have died, been recalled, rebuilt, staggered or started an ability.
		if brains[brain.model] ~= brain or brain.humanoid.Health <= 0 or brain.castToken ~= castToken or self.Services.StatusService:IsStaggered(brain.model) then
			return
		end
		local hitbox = brain.hitboxSize
		local reach = brain.stats.Reach
		local boxCFrame = brain.root.CFrame * CFrame.new(0, 0, -(hitbox.Z / 2 + reach / 2))
		local boxSize = Vector3.new(hitbox.X + 2, hitbox.Y + 2, reach)

		local services = self.Services
		for _, target in services.HitDetectionService:QueryBox(boxCFrame, boxSize, ignoreList(brain), brain.root.Position) do
			services.CombatService:ApplyDamage({
				Attacker = brain.model,
				Target = target,
				BaseDamage = hit.Damage,
				AttackPower = brain.stats.AttackPower,
				Knockback = hit.Knockback,
				Stagger = Config.Stagger.ComboStagger[hitIndex],
				Status = rollOnHitStatus(brain, hitIndex),
				Source = "NightmareCombo",
			})
		end
	end)
	return true
end

function NightmareAIService:HeavyReady(brain, now: number): boolean
	return now >= brain.heavyReadyAt
end

function NightmareAIService:StartHeavy(brain, now: number)
	local speedScale = 100 / brain.stats.AttackSpeed
	local windup = HEAVY.Windup * speedScale
	local total = windup + HEAVY.Active + HEAVY.Recovery * speedScale
	local cooldownMultiplier = Config.Commands[brain.command] and Config.Commands[brain.command].HeavyCooldownMultiplier or 1
	brain.busyUntil = now + total
	brain.cancelableAt = now + windup + HEAVY.Active
	brain.heavyReadyAt = now + (brain.possessedBy and total or HEAVY.Cooldown * cooldownMultiplier)
	brain.comboIndex = 1
	brain.finisherPending = true
	if not brain.possessedBy then
		self:Stop(brain)
	end
	self:PlayAction(brain, HEAVY.Name, windup, total)

	local castToken = brain.castToken
	task.delay(windup, function()
		if brains[brain.model] ~= brain or brain.humanoid.Health <= 0 or brain.castToken ~= castToken or self.Services.StatusService:IsStaggered(brain.model) then
			return
		end
		local hitbox = brain.hitboxSize
		local reach = brain.stats.Reach + HEAVY.ExtraReach
		local boxCFrame = brain.root.CFrame * CFrame.new(0, 0, -(hitbox.Z / 2 + reach / 2))
		local services = self.Services
		for _, target in services.HitDetectionService:QueryBox(boxCFrame, Vector3.new(hitbox.X + 3, hitbox.Y + 2, reach), ignoreList(brain), brain.root.Position) do
			services.CombatService:ApplyDamage({
				Attacker = brain.model,
				Target = target,
				BaseDamage = HEAVY.Damage,
				AttackPower = brain.stats.AttackPower,
				Knockback = HEAVY.Knockback,
				Heavy = true, -- breaks guards (Phase 4 PvP)
				Stagger = HEAVY.Stagger,
				Status = rollOnHitStatus(brain, 3),
				Source = "NightmareHeavy",
			})
		end
	end)
	return true
end

------------------------------------------------------------------------------------------
-- Footwork (Config.Nightmare.Fight): quick steps, circling, gap closers
------------------------------------------------------------------------------------------
local FIGHT = NM.Fight

local function randomIn(range): number
	return range[1] + math.random() * (range[2] - range[1])
end

-- A quick step: a short, fast slide in `direction` (world, flat) while still facing the
-- target. Shortened so it never slides into a wall or off a ledge. Returns true if it went.
function NightmareAIService:QuickStep(brain, direction: Vector3, distance: number, action: string, facing: Vector3?, ignoreCooldown: boolean?): boolean
	local now = os.clock()
	local attachment = brain.root:FindFirstChild("FacingAttachment")
	if (now < (brain.dashReadyAt or 0) and not ignoreCooldown) or not attachment or brain.root.Anchored then
		return false
	end
	local radius = math.max(brain.hitboxSize.X, brain.hitboxSize.Z) / 2
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { brain.model, brain.owner.Character }
	local from = brain.root.Position
	local wall = workspace:Raycast(from, direction * (distance + radius), params)
	if wall then
		distance = math.max(0, (wall.Position - from).Magnitude - radius - 0.5)
	end
	if distance < 2 then
		return false
	end
	local landing = from + direction * distance
	if not workspace:Raycast(landing, Vector3.new(0, -(brain.hitboxSize.Y / 2 + brain.humanoid.HipHeight + 6), 0), params) then
		return false -- no floor there
	end

	brain.dashReadyAt = now + FIGHT.DashCooldown
	brain.busyUntil = now + FIGHT.DashTime + 0.08
	brain.cancelableAt = brain.busyUntil
	self:Stop(brain)
	if facing then
		self:Face(brain, facing)
	end
	self:PlayAction(brain, action, 0, FIGHT.DashTime + 0.2)

	local mover = Instance.new("LinearVelocity")
	mover.Name = "QuickStep"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (distance / FIGHT.DashTime)
	mover.MaxForce = 1e6
	mover.Parent = brain.root
	task.delay(FIGHT.DashTime, function()
		mover:Destroy()
	end)
	return true
end

-- Watches the target: when it starts an attack close by, maybe react (after a short,
-- human-ish delay) with a hop back or a sidestep.
local function watchTarget(brain, target: Model?, now: number)
	if not target then
		return
	end
	local seq = target:GetAttribute("ActionSeq")
	if seq == nil or seq == brain.seenSeq and target == brain.seenTarget then
		return
	end
	local fresh = target == brain.seenTarget
	brain.seenSeq, brain.seenTarget = seq, target
	if not fresh or math.random() >= FIGHT.ReactChance then
		return
	end
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return
	end
	local threat = brain.hitboxSize.Z / 2 + brain.stats.Reach + math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2 + 6
	if Util.FlatDistance(brain.root.Position, targetRoot.Position) <= threat then
		brain.reactAt = now + randomIn(FIGHT.ReactDelay)
	end
end

-- Performs a pending reaction. Returns true if it stepped.
function NightmareAIService:React(brain, target: Model, now: number): boolean
	local reactAt = brain.reactAt
	if not reactAt or now < reactAt then
		return false
	end
	if now > reactAt + 0.35 then
		brain.reactAt = nil -- too late, the hit is coming anyway
		return false
	end
	-- never cancels its own swing's windup; may cut the recovery
	if now < brain.busyUntil and now < (brain.cancelableAt or 0) then
		return false
	end
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	local away = targetRoot and Util.FlatUnit(brain.root.Position - targetRoot.Position)
	if not away then
		return false
	end
	brain.reactAt = nil
	local stepped
	if math.random() < FIGHT.SidestepShare then
		local side = Vector3.new(-away.Z, 0, away.X) * (math.random() < 0.5 and -1 or 1)
		stepped = self:QuickStep(brain, (side + away * 0.3).Unit, FIGHT.SidestepDistance, "Sidestep", targetRoot.Position)
	else
		stepped = self:QuickStep(brain, away, FIGHT.StepBackDistance, "StepBack", targetRoot.Position)
	end
	-- Step out... then straight back in with a hit (the attacker is stuck in its swing).
	if stepped and math.random() < FIGHT.CounterChance then
		brain.counterAt = now + FIGHT.DashTime + FIGHT.CounterDelay
		brain.circleUntil = 0
	end
	return stepped
end

------------------------------------------------------------------------------------------
-- Brain tick
------------------------------------------------------------------------------------------
local function chooseTarget(brain, handlerRoot: BasePart, now: number): Model?
	if brain.command == "Retreat" then
		if now < brain.retreatUntil then
			return nil
		end
		setCommand(brain, "Defend", nil)
	end

	if brain.command == "Attack" then
		if isValidEnemy(brain, brain.commandTarget, handlerRoot) then
			return brain.commandTarget
		end
		setCommand(brain, "Defend", nil) -- focused target died or fled: back to defending
	end

	if isValidEnemy(brain, brain.target, handlerRoot) then
		return brain.target
	end

	-- Auto-engage: nearest living enemy close to the HANDLER. Defend keeps it tight;
	-- Aggressive hunts further out. Bosses are always engaged within BossAggroRadius.
	local radius = (Config.Commands[brain.command] or Config.Commands.Defend).AggroRadius
	local best, bestDistance = nil, math.huge
	local candidates = CollectionService:GetTagged("Enemy")
	local opponents = duelService:GetOpponentModels(brain.owner)
	for _, model in opponents do
		table.insert(candidates, model)
	end
	for _, enemy in candidates do
		-- (NoNightmareTarget: a one-on-one for the Handler, e.g. the sparring fighter;
		-- still fair game if you send your Nightmare at it yourself)
		if isValidEnemy(brain, enemy, handlerRoot) and not (enemy:GetAttribute("NoNightmareTarget") and brain.commandTarget ~= enemy) then
			local limit = CollectionService:HasTag(enemy, "Boss") and NM.BossAggroRadius or radius
			if table.find(opponents, enemy) then
				limit = math.max(radius, 60) -- duel arenas are small: always engage the opponent
			end
			local distance = Util.FlatDistance(enemy.HumanoidRootPart.Position, handlerRoot.Position)
			if distance <= limit and distance < bestDistance then
				best, bestDistance = enemy, distance
			end
		end
	end
	return best
end

-- Imperfect telegraph avoidance. Returns true if the brain is busy evading.
function NightmareAIService:Evade(brain, now: number): boolean
	local telegraphs = self.Services.TelegraphService
	local zone = telegraphs:FindHostileZone(brain.root.Position, math.max(brain.hitboxSize.X, brain.hitboxSize.Z) / 2)
	if not zone then
		brain.evadeZone = nil
		return false
	end
	if brain.evadeZone ~= zone.Id then
		brain.evadeZone = zone.Id
		brain.evadeDecision = math.random() < NM.HazardDodgeChance
		brain.evadeAt = now + NM.HazardReactionTime[1] + math.random() * (NM.HazardReactionTime[2] - NM.HazardReactionTime[1])
	end
	if not brain.evadeDecision or now < brain.evadeAt then
		return false
	end
	local margin = math.max(brain.hitboxSize.X, brain.hitboxSize.Z) / 2 + 3
	self:SetSpeed(brain, brain.stats.MoveSpeed * 1.25)
	self:StopFacing(brain)
	brain.humanoid:MoveTo(telegraphs:EscapePoint(zone, brain.root.Position, margin)) -- direct: it's urgent
	return true
end

-- Handles a queued Q/E ability. Returns true if it took control this tick.
function NightmareAIService:HandleQueuedAbility(brain, target: Model?, now: number): boolean
	local queued = brain.queuedAbility
	if not queued then
		return false
	end
	local abilities = self.Services.AbilityService
	local def = AbilityDefinitions.Get(brain.abilities[queued.Slot])
	if now > queued.Expires then
		brain.queuedAbility = nil
		-- Say why instead of silently doing nothing.
		if def and brain.owner.Parent then
			Net.Get("UIStateUpdate"):FireClient(brain.owner, "Toast", {
				Text = target and ("%s cancelled: your Nightmare couldn't reach the target in time."):format(def.DisplayName)
					or ("%s cancelled: no target in range."):format(def.DisplayName),
			})
		end
		return false
	end
	if not def or not abilities:IsReady(brain, queued.Slot) then
		brain.queuedAbility = nil
		return false
	end

	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		if def.Type == "Pull" then
			return false -- nothing to pull yet; keep it queued until a target appears
		end
		abilities:Execute(brain, queued.Slot, nil)
		return true
	end

	local range = abilities:GetCastRange(brain, def)
	local targetRadius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
	local distance = Util.FlatDistance(brain.root.Position, targetRoot.Position) - targetRadius
	if distance <= range then
		abilities:Execute(brain, queued.Slot, target)
	else
		self:SetSpeed(brain, brain.stats.MoveSpeed)
		self:MoveTo(brain, targetRoot.Position)
	end
	return true
end

function NightmareAIService:Engage(brain, target: Model, now: number)
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	local targetRadius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
	local reach = brain.hitboxSize.Z / 2 + brain.stats.Reach
	local distance = Util.FlatDistance(brain.root.Position, targetRoot.Position)
	self:SetSpeed(brain, brain.stats.MoveSpeed)

	-- Target behind a wall or pillar: head for the target itself so the navigator paths
	-- around the obstacle. (Aiming for a stand-off point in front of it would pick a spot
	-- on OUR side of the pillar, and the Nightmare would shuttle back and forth there.)
	if not self.Services.HitDetectionService:HasLineOfSight(brain.root.Position, targetRoot.Position, target) then
		self:MoveTo(brain, targetRoot.Position)
		return
	end

	local toTarget = Util.FlatUnit(targetRoot.Position - brain.root.Position) or Vector3.zAxis
	local standOff = math.max(reach + targetRadius - 1.5, 1)
	local aggressive = brain.command == "Aggressive"

	-- Just finished a combo or a heavy: hop back out, then circle for a moment instead of
	-- standing in front of the target trading hits.
	if brain.finisherPending then
		brain.finisherPending = false
		if math.random() < FIGHT.AfterFinisherStepChance * (aggressive and 0.5 or 1) then
			self:QuickStep(brain, -toTarget, FIGHT.StepBackDistance, "StepBack", targetRoot.Position)
		end
		if math.random() < FIGHT.CircleChance * (aggressive and 0.4 or 1) then
			brain.circleUntil = now + FIGHT.DashTime + randomIn(FIGHT.CircleTime)
			brain.circleSign = math.random() < 0.5 and -1 or 1
		end
		if now < brain.busyUntil then
			return
		end
	end

	-- Counter: right after stepping out of an attack, dash back in and hit.
	if brain.counterAt and now >= brain.counterAt then
		brain.counterAt = nil
		local gap = distance - standOff
		if gap > 1.5 and self:QuickStep(brain, toTarget, gap, "DashIn", targetRoot.Position, true) then
			return
		end
	end

	-- Circling: strafe around the target at just outside reach, always facing it.
	if now < (brain.circleUntil or 0) then
		local radius = standOff + 2.5
		local fromTarget = brain.root.Position - targetRoot.Position
		fromTarget = Vector3.new(fromTarget.X, 0, fromTarget.Z)
		if fromTarget.Magnitude < 0.1 then
			fromTarget = -toTarget
		end
		local angle = math.rad(40) * brain.circleSign
		local around = CFrame.Angles(0, angle, 0):VectorToWorldSpace(fromTarget.Unit) * radius
		self:SetSpeed(brain, brain.stats.MoveSpeed * FIGHT.CircleSpeed)
		brain.nav:Stop()
		self:Face(brain, targetRoot.Position)
		brain.humanoid:MoveTo(targetRoot.Position + around)
		return
	end

	if distance > reach + targetRadius - 0.5 then
		-- Gap closer: from a little outside reach, dash straight in (once per approach).
		local gap = distance - standOff
		if not brain.lungeRolled and gap > 2 and gap <= FIGHT.LungeDistance then
			brain.lungeRolled = true
			if math.random() < FIGHT.LungeChance and self:QuickStep(brain, toTarget, gap, "DashIn", targetRoot.Position) then
				return
			end
		end
		self:MoveTo(brain, targetRoot.Position - toTarget * standOff)
		return
	end
	brain.lungeRolled = false

	self:Stop(brain)
	self:Face(brain, targetRoot.Position)

	-- Only swing once roughly facing the target, so attacks read as intentional.
	local look = Util.FlatUnit(brain.root.CFrame.LookVector)
	local wanted = Util.FlatUnit(targetRoot.Position - brain.root.Position)
	if not (look and wanted and look:Dot(wanted) > 0.8) then
		return
	end
	-- Heavy attack: after finishing a combo, or straight away on a staggered target.
	local targetStaggered = self.Services.StatusService:IsStaggered(target)
	if self:HeavyReady(brain, now) and (brain.comboIndex == 1 or targetStaggered) then
		self:StartHeavy(brain, now)
	else
		self:StartAttack(brain, now)
	end
end

function NightmareAIService:Follow(brain, handlerRoot: BasePart, now: number)
	local offset = NM.FollowOffset
	if handlerRoot.Parent and handlerRoot.Parent:GetAttribute("InStance") then
		-- squared up in a duel: the camera sits over the Handler's right shoulder, so keep
		-- out of its way on the left
		offset = Vector3.new(-offset.X, offset.Y, offset.Z)
	end
	local desired = (handlerRoot.CFrame * CFrame.new(offset)).Position
	-- its Handler is sparring: wait outside the ropes (FighterService)
	desired = self.Services.FighterService:OutsideRing(desired)
	local distance = Util.FlatDistance(brain.root.Position, desired)

	if distance > NM.FollowStopDistance then
		local speed = brain.stats.MoveSpeed
		if distance > NM.CatchUpDistance then
			speed *= NM.CatchUpSpeedMultiplier
		end
		self:SetSpeed(brain, speed)
		self:MoveTo(brain, desired)
		return
	end

	-- Idle beside the Handler: look at its creator, occasionally do something cute.
	self:Stop(brain)
	self:Face(brain, handlerRoot.Position)
	if now >= brain.nextIdleAction then
		brain.nextIdleAction = now + math.random(NM.IdleActionInterval[1], NM.IdleActionInterval[2])
		self:PlayAction(brain, "IdleLook", 0, 1.6)
	end
end

local function regenerate(brain, now: number, dt: number)
	if now - brain.lastDamagedAt < NM.OutOfCombatRegenDelay then
		return
	end
	local humanoid = brain.humanoid
	if humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * NM.OutOfCombatRegenPerSecond * dt)
	end
end

function NightmareAIService:Update(brain, now: number, dt: number)
	-- scripted = another service is driving it (the Nightmare Gym's training routine)
	if brain.humanoid.Health <= 0 or brain.possessedBy or brain.scripted then
		return
	end
	if duelService:IsFrozen(brain.owner) then
		self:Stop(brain)
		return
	end
	if self.Services.StatusService:IsStaggered(brain.model) or brain.model:GetAttribute("Ragdolled") or brain.model:GetAttribute("Gripped") then
		self:Stop(brain) -- (Gripped: held in another Nightmare's jaws)
		return
	end

	local handlerRoot = getHandlerRoot(brain.owner)
	if not handlerRoot then
		self:Stop(brain)
		return
	end

	-- Left far behind (e.g. Handler teleported): blink back beside the Handler.
	if Util.FlatDistance(brain.root.Position, handlerRoot.Position) > NM.TeleportDistance then
		self:TeleportToHandler(brain, handlerRoot)
		return
	end

	local target = chooseTarget(brain, handlerRoot, now)
	if target ~= brain.target then
		brain.targetSince = now
	end
	brain.target = target

	-- The target is winding up an attack close by: maybe hop back / sidestep (Fight).
	watchTarget(brain, target, now)
	if target and self:React(brain, target, now) then
		return
	end

	-- Busy swinging. A queued ability may cancel the swing's RECOVERY (never its windup),
	-- so Q/E feel responsive instead of waiting for the whole animation.
	local canCancel = brain.queuedAbility ~= nil and now >= (brain.cancelableAt or 0)
	if now < brain.busyUntil and not canCancel then
		if target then
			self:Face(brain, target.HumanoidRootPart.Position)
		end
		return
	end

	if self:Evade(brain, now) then
		return
	end

	if self:HandleQueuedAbility(brain, target, now) then
		return
	end
	if now < brain.busyUntil then
		return -- still recovering from a swing (we only got here to try the queued ability)
	end

	if target then
		self:Engage(brain, target, now)
	else
		self:Follow(brain, handlerRoot, now)
		regenerate(brain, now, dt)
	end
end

function NightmareAIService:TeleportToHandler(brain, handlerRoot: BasePart)
	brain.model:PivotTo(handlerRoot.CFrame * CFrame.new(NM.FollowOffset) + Vector3.new(0, 2, 0))
	brain.target = nil
	brain.nav.waypoints = nil
end

------------------------------------------------------------------------------------------
-- Registration (called by NightmareSpawnService)
------------------------------------------------------------------------------------------
function NightmareAIService:Register(model: Model, owner: Player, stats, info)
	local root = model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")

	local attachment = Instance.new("Attachment")
	attachment.Name = "FacingAttachment"
	attachment.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "FacingAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = 1e7
	align.MaxAngularVelocity = 20
	align.Responsiveness = 25
	align.Enabled = false
	align.Parent = root

	local now = os.clock()
	local brain = {
		model = model,
		owner = owner,
		humanoid = humanoid,
		root = root,
		align = align,
		nav = self.Services.NavigationService:Create(humanoid, root, info.HitboxSize),
		stats = stats,
		hitboxSize = info.HitboxSize,
		abilities = info.Abilities or {},
		onHit = info.OnHit or {},
		abilityReadyAt = {},
		queuedAbility = nil,
		castToken = 0,
		command = "Defend",
		commandTarget = nil,
		target = nil,
		retreatUntil = 0,
		busyUntil = 0,
		heavyReadyAt = 0,
		comboIndex = 1,
		comboResetAt = 0,
		lastDamagedAt = 0,
		possessedBy = nil,
		nextIdleAction = now + math.random(NM.IdleActionInterval[1], NM.IdleActionInterval[2]),
	}
	brains[model] = brain
	brainByPlayer[owner] = brain
	model:SetAttribute("Command", "Defend")
end

function NightmareAIService:Unregister(model: Model?)
	local brain = model and brains[model]
	if not brain then
		return
	end
	brains[model] = nil
	if brainByPlayer[brain.owner] == brain then
		brainByPlayer[brain.owner] = nil
	end
end

------------------------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------------------------
function NightmareAIService:HandleCommand(player: Player, command, arg)
	if not self.Services.AntiExploitService:Allow(player, "NightmareCommand") then
		return
	end
	if type(command) ~= "string" then
		return
	end

	if command == "ToggleSummon" then
		local spawnService = self.Services.NightmareSpawnService
		if self.Services.PossessionService:IsPossessing(player) or duelService:IsInMatch(player) then
			return
		end
		spawnService:SetSummoned(player, not spawnService:IsSummoned(player))
		return
	end

	local brain = brainByPlayer[player]
	if not brain then
		return
	end

	if command == "Attack" then
		local handlerRoot = getHandlerRoot(player)
		if typeof(arg) ~= "Instance" or not arg:IsA("Model") or not handlerRoot then
			return
		end
		if not isValidEnemy(brain, arg, handlerRoot) then
			return
		end
		setCommand(brain, "Attack", arg)
		self.Services.TutorialService:Notify(player, "CommandAttack")
	elseif command == "Defend" or command == "Follow" then
		setCommand(brain, "Defend", nil)
	elseif command == "Aggressive" then
		setCommand(brain, "Aggressive", nil)
	elseif command == "Retreat" then
		setCommand(brain, "Retreat", nil)
		brain.queuedAbility = nil
		brain.retreatUntil = os.clock() + NM.RetreatDuration
	end
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function NightmareAIService:Init(services)
	self.Services = services
	duelService = services.DuelService
end

function NightmareAIService:Start()
	Net.Get("NightmareCommand").OnServerEvent:Connect(function(player, command, arg)
		self:HandleCommand(player, command, arg)
	end)

	-- Retaliate when hit, and pause regeneration.
	self.Services.CombatService:OnDamaged(function(target, attacker)
		local now = os.clock()
		local attackerBrain = attacker and brains[attacker]
		if attackerBrain then
			attackerBrain.lastLandedAt = now
		end
		local brain = brains[target]
		if not brain then
			return
		end
		brain.lastDamagedAt = now
		if not attacker or attacker == brain.target or brain.command == "Retreat" or brain.command == "Attack" then
			return
		end
		if not CollectionService:HasTag(attacker, "Enemy") and not duelService:IsOpponentModel(brain.owner, attacker) then
			return
		end
		-- Idle: fight back. Busy with a target it can't actually hit (e.g. stuck behind a
		-- pillar) while something hits it: turn on the attacker instead of standing helpless.
		local lastProgress = math.max(brain.lastLandedAt or 0, brain.targetSince or 0)
		if not brain.target or now - lastProgress > NM.SwitchTargetAfter then
			brain.target = attacker
			brain.targetSince = now
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local brain = brainByPlayer[player]
		if brain then
			self:Unregister(brain.model)
		end
	end)

	local step = 1 / NM.AIUpdateRate
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < step then
			return
		end
		local elapsed = accumulated
		accumulated = 0
		local now = os.clock()
		for _, brain in brains do
			local ok, err = pcall(self.Update, self, brain, now, elapsed)
			if not ok then
				warn("[NightmareAI] update failed:", err)
			end
		end
	end)
end

return NightmareAIService
