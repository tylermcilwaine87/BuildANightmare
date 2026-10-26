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
	  ENGAGE   close distance (sometimes with a dash-in lunge), face, then fight WILD
	           (Config.Nightmare.Moveset / Wild): real strings picked at random - jab-cross-
	           hook, body hook into uppercut, overhands, teeps, roundhouses, clinch knees,
	           spinning back kicks - sometimes chained straight into the next, sometimes
	           sprinting round to the target's side or back first, sometimes a feint; the
	           HEAVY on a staggered target; hurt, it hits and runs. After a string it may
	           hop out and circle the target for a moment before going back in.
	  FOLLOW   stay at the Handler's side; face the Handler when idle; idle personality

	Commands (remote NightmareCommand), shown on the HUD:
	  "Attack", target   focus a specific enemy
	  "Focus", target    (sent when you lock on) go after that enemy, keeping the stance
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
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local Passives = require(Shared:WaitForChild("PassiveDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))

local COMBAT = require(Shared:WaitForChild("NightmareCombatDefinitions"))

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

-- STUDIO ONLY (DevBridge): make the player's Nightmare throw string `action` next (keep =
-- every time, until called again with nil). For demonstrations and measurements.
function NightmareAIService:DevForceString(player: Player, action: string?, keep: boolean?)
	local brain = brainByPlayer[player]
	if not RunService:IsStudio() or not brain then
		return false
	end
	brain.forceString, brain.forceKeep = action, keep == true
	return true
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

------------------------------------------------------------------------------------------
-- THE WILD MOVESET (Config.Nightmare.Moveset): real fighting strings, picked at random
------------------------------------------------------------------------------------------
local WILD = NM.Wild

-- (the combat brain's stamina and move tags: NightmareCombatDefinitions)
local function spendStamina(brain, amount: number, now: number)
	brain.stamina = math.max(0, brain.stamina - amount)
	brain.staminaSpentAt = now
end

-- HABITS (NightmareCombatDefinitions.Adapt): what this target keeps doing to it.
-- kind: "Attack" | "Guard" | "Evade" | "Hurt"
local function noteHabit(brain, target: Model?, kind: string)
	if not target or not brain.habits then
		return
	end
	local seen = brain.habits[target]
	if not seen then
		seen = {}
		brain.habits[target] = seen
	end
	seen[kind] = seen[kind] or {}
	table.insert(seen[kind], os.clock())
end

-- Which habits the target has shown lately: { Aggressor = true, ... } (names = Adapt keys).
local function adaptOf(brain, target: Model?)
	local out = {}
	local seen = target and brain.habits and brain.habits[target]
	if not seen then
		return out
	end
	local now = os.clock()
	for kind, times in seen do
		for i = #times, 1, -1 do
			if now - times[i] > COMBAT.Adapt.Window then
				table.remove(times, i)
			end
		end
		local name = COMBAT.HabitOf[kind]
		if name and #times >= COMBAT.Adapt[name].Threshold then
			out[name] = true
		end
	end
	return out
end

local function hasTag(def, tag: string): boolean
	return def.Tags ~= nil and table.find(def.Tags, tag) ~= nil
end

-- A MUTATED Nightmare's finishers carry its element: the last blow of a Finisher or
-- Signature combo always applies the first mutation's status (burn, chill, shock...).
local function elementOf(brain, def): string?
	if not (hasTag(def, "Finisher") or hasTag(def, "Signature")) then
		return nil
	end
	local ids = brain.model:GetAttribute("Mutations")
	local mutation = ids and MutationDefinitions.Get(string.split(ids, ",")[1])
	return mutation and mutation.OnHit and mutation.OnHit.Status or nil
end

-- What this body can throw: punches need an arm, kicks need two legs (a Biped); the beast
-- moves need four legs (Quad), a head (Head) or a tail (Tail).
local function bodyCan(brain)
	local model = brain.model
	return {
		Arms = model:FindFirstChild("RightArm_Root", true) ~= nil or model:FindFirstChild("LeftArm_Root", true) ~= nil,
		BothArms = model:FindFirstChild("RightArm_Root", true) ~= nil and model:FindFirstChild("LeftArm_Root", true) ~= nil,
		Legs = model:GetAttribute("Archetype") == "Biped" and model:FindFirstChild("Sub_Legs_R", true) ~= nil,
		Quad = model:GetAttribute("Archetype") == "Quadruped",
		Head = model:FindFirstChild("Joint_Head", true) ~= nil,
		Tail = model:FindFirstChild("Joint_Tail", true) ~= nil,
		Tentacle = model:GetAttribute("RightArmSet") == "Tentacle", -- (a Shadow Tentacle right arm)
	}
end

local function canThrow(def, can): boolean
	for _, need in { "Arms", "BothArms", "Legs", "Quad", "Head", "Tail", "Tentacle" } do
		if def[need] and not can[need] then
			return false
		end
	end
	return true
end

-- A string this body can do, by Weight, never the one it just threw (while there's a choice).
-- (`filter`: only strings it accepts, e.g. ones that leap far enough)
function NightmareAIService:PickString(brain, filter: ((any) -> boolean)?)
	local can = bodyCan(brain)
	-- STUDIO ONLY (DevForceString): the next string is this one, if the body can throw it
	if brain.forceString and RunService:IsStudio() then
		for _, def in NM.Moveset do
			if def.Action == brain.forceString and canThrow(def, can) then
				if not brain.forceKeep then
					brain.forceString = nil
				end
				return def
			end
		end
	end
	local options, total = {}, 0
	for _, def in NM.Moveset do
		-- (counters come out of an evade, signatures and unlockables only through the brain)
		local special = hasTag(def, "Counter") or hasTag(def, "Signature") or def.Unlock ~= nil
		if canThrow(def, can) and not special and def.Action ~= brain.lastString and (not filter or filter(def)) then
			table.insert(options, def)
			total += def.Weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for _, def in options do
		roll -= def.Weight
		if roll <= 0 then
			return def
		end
	end
	return options[#options]
end

-- STUDIO ONLY (DevBridge): throw string `action` at `target` right now (squared up to it),
-- for a clean measurement of one combo. Returns false if this body can't throw it.
function NightmareAIService:DevStartString(player: Player, action: string, target: Model)
	local brain = brainByPlayer[player]
	if not RunService:IsStudio() or not brain or typeof(target) ~= "Instance" then
		return false
	end
	local can = bodyCan(brain)
	for _, def in NM.Moveset do
		if def.Action == action and canThrow(def, can) then
			local root = target:FindFirstChild("HumanoidRootPart")
			if root then
				self:Face(brain, root.Position)
			end
			brain.target = target
			if def.Evade then
				self:StartCounter(brain, def, target, os.clock())
				return true
			end
			return self:StartString(brain, def, target, os.clock())
		end
	end
	return false
end

-- A short shove toward the target between the hits of a string (no animation of its own, so
-- the string keeps playing): pressing forward as they back off. (Over `duration`: a
-- pounce's leap, a rolling charge.)
local function pressIn(brain, direction: Vector3, distance: number, duration: number?)
	duration = duration or 0.12
	local attachment = brain.root:FindFirstChild("FacingAttachment")
	if not attachment or distance < 0.5 or brain.root.Anchored then
		return
	end
	local mover = Instance.new("LinearVelocity")
	mover.Name = "PressIn"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (distance / duration)
	mover.MaxForce = 1e6
	mover.Parent = brain.root
	task.delay(duration, function()
		mover:Destroy()
	end)
end

-- A body small enough to be grabbed in the clinch: an ordinary enemy the server moves
-- (never a boss or a player).
local function canClinch(target: Model): boolean
	local root = target:FindFirstChild("HumanoidRootPart")
	return root ~= nil and not root.Anchored and not CollectionService:HasTag(target, "Boss") and not target:GetAttribute("KnockbackImmune")
		and not target:GetAttribute("Ragdolled") and not Players:GetPlayerFromCharacter(target) and root:GetNetworkOwner() == nil
end

-- Throws string `def` at `target`: the keyframed animation plays at the speed AttackSpeed
-- gives it, each hit lands on its contact frame on whatever is in front by then (the
-- Nightmare keeps turning to face the target and presses in if it slipped back), a clinch
-- holds the target for the knees, and the last hit usually decides what happens next
-- (chain straight into another string, hit and run...).
function NightmareAIService:StartString(brain, def, target: Model, now: number)
	local speedScale = 100 / brain.stats.AttackSpeed
	local hits = def.Hits
	local lastHit = hits[#hits][1]
	-- the breather after it: the personality's and the mode's
	local pause = WILD.AfterStringRest * (brain.personality and brain.personality.Pause or 1) * (brain.mode and brain.mode.Pause or 1)
	brain.busyUntil = now + lastHit * speedScale + pause
	brain.cancelableAt = now + hits[1][1] * speedScale + 0.05
	brain.comboIndex = 1
	brain.lastString = def.Action
	brain.model:SetAttribute("NightmareGuard", nil)
	-- the combat brain's bookkeeping: stamina, variety, the signature cooldown
	if not brain.possessedBy then
		spendStamina(brain, COMBAT.CostOf(def), now)
	end
	table.insert(brain.history, 1, def.Action)
	if #brain.history > #COMBAT.Repeat then
		table.remove(brain.history)
	end
	if hasTag(def, "Signature") then
		brain.signatureReadyAt = now + COMBAT.SignatureCooldown
	end
	brain.finisherPending = true
	brain.chainPending = math.random() < WILD.ChainChance * (brain.flair or 1)
	if not brain.possessedBy then
		self:Stop(brain)
	end
	-- (the client plays the animation at hitTime / windup = 1 / speedScale)
	self:PlayAction(brain, def.Action, def.Duration * 0.45 * speedScale, def.Duration * speedScale)

	local castToken = brain.castToken
	local services = self.Services
	local reach = brain.stats.Reach + (def.ExtraReach or 0)
	local grabbed = nil
	local function release()
		if grabbed then
			local root = grabbed:FindFirstChild("HumanoidRootPart")
			if root and root.Parent then
				root.Anchored = false
			end
			grabbed:SetAttribute("Gripped", nil)
			grabbed = nil
		end
	end
	-- a LEAP (pounce, rolling charge, headbutt): the body really travels onto them, timed
	-- to arrive on the first hit
	local leap = def.Leap
	if leap then
		task.delay(leap.At * speedScale, function()
			if brains[brain.model] ~= brain or brain.humanoid.Health <= 0 or brain.castToken ~= castToken or brain.model:GetAttribute("Ragdolled") then
				return
			end
			local targetRoot = target.Parent and target:FindFirstChild("HumanoidRootPart")
			local toTarget = targetRoot and Util.FlatUnit(targetRoot.Position - brain.root.Position)
			if not toTarget then
				return
			end
			self:Face(brain, targetRoot.Position)
			local radius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
			local gap = Util.FlatDistance(targetRoot.Position, brain.root.Position) - radius - brain.hitboxSize.Z / 2 - reach * 0.4
			pressIn(brain, toTarget, math.clamp(gap, 0, leap.Max), leap.Time * speedScale)
		end)
	end
	local logging = RunService:IsStudio() and Config.Dev.LogNightmareCombos == true
	local startedAt = os.clock()
	for index, hit in hits do
		-- (hit[6].Chase: lunge after a body that slid away, landing just as this beat hits)
		local chase = hit[6] and hit[6].Chase
		if chase then
			task.delay(math.max(0, hit[1] * speedScale - 0.22), function()
				local targetRoot = target.Parent and target:FindFirstChild("HumanoidRootPart")
				local toTarget = targetRoot and Util.FlatUnit(targetRoot.Position - brain.root.Position)
				if brains[brain.model] ~= brain or brain.castToken ~= castToken or not toTarget then
					return
				end
				self:Face(brain, targetRoot.Position)
				local radius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
				local gap = Util.FlatDistance(targetRoot.Position, brain.root.Position) - radius - brain.hitboxSize.Z / 2 - reach * 0.8
				if gap > 0 then
					pressIn(brain, toTarget, math.min(gap + 0.5, chase), 0.2)
				end
			end)
		end
		task.delay(hit[1] * speedScale, function()
			if brains[brain.model] ~= brain or brain.humanoid.Health <= 0 or brain.castToken ~= castToken
				or services.StatusService:IsStaggered(brain.model) or brain.model:GetAttribute("Ragdolled") then
				if logging then
					local why = brain.castToken ~= castToken and "interrupted" or services.StatusService:IsStaggered(brain.model) and "staggered" or "down / gone"
					print(("[Combo] %s hit %d @%.2f SKIPPED (%s)"):format(def.Action, index, os.clock() - startedAt, why))
				end
				release()
				return
			end
			local targetRoot = target.Parent and target:FindFirstChild("HumanoidRootPart")
			if targetRoot and not grabbed then
				-- stay on them: square up, and step in if they've slipped just out of reach
				self:Face(brain, targetRoot.Position)
				local toTarget = Util.FlatUnit(targetRoot.Position - brain.root.Position)
				local radius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
				local gap = Util.FlatDistance(targetRoot.Position, brain.root.Position) - radius - brain.hitboxSize.Z / 2 - reach * 0.8
				if toTarget and gap > 0 and gap < 4 then
					pressIn(brain, toTarget, gap + 0.5)
				end
			end
			-- the clinch: grab them on the first beat (only if they're really within reach) and
			-- hold them for the rest
			if def.Clinch and index == 1 and targetRoot and canClinch(target) then
				local radius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
				if Util.FlatDistance(targetRoot.Position, brain.root.Position) - radius - brain.hitboxSize.Z / 2 <= reach + 0.5 then
					grabbed = target
					target:SetAttribute("Gripped", true)
					targetRoot.Anchored = true
				end
			end
			-- a HOLD (Savage Execution): held up in its hands, facing it, on every beat: the
			-- face of the victim at Hold.Reach (where the headbutt lands), its upper body at
			-- the hands' height (a small one is lifted off its feet, never more than Hold.Lift);
			-- on the throw it's slung round to the side it goes flying (Hold.Throw)
			-- (Hold.Path: carried along a path instead - the tentacle: { x right, height above
			-- where they stood, z back } per beat - gliding to the next point between beats)
			if def.Hold and grabbed and targetRoot then
				local hold = def.Hold
				local radius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
				if index == 1 then
					brain.holdStandY = targetRoot.Position.Y
				end
				local standing = brain.holdStandY or targetRoot.Position.Y
				local function holdAt(offset: Vector3, lifted: number?)
					local at = (brain.root.CFrame * CFrame.new(offset.X, 0, offset.Z)).Position
					local y = lifted or math.clamp(brain.root.Position.Y + hold.Height - targetRoot.Size.Y * 0.25, standing, standing + hold.Lift)
					at = Vector3.new(at.X, y, at.Z)
					return CFrame.lookAt(at, Vector3.new(brain.root.Position.X, at.Y, brain.root.Position.Z)) * targetRoot.CFrame:ToObjectSpace(target:GetPivot())
				end
				if hold.Path then
					local point = hold.Path[index]
					target:PivotTo(holdAt(point, standing + point.Y))
					local nextPoint = hold.Path[index + 1]
					if nextPoint and hits[index + 1] then
						-- glide to the next point by the next beat
						local from, to = target:GetPivot(), holdAt(nextPoint, standing + nextPoint.Y)
						local duration = (hits[index + 1][1] - hit[1]) * speedScale
						local heldNow = grabbed
						task.spawn(function()
							local started = os.clock()
							while grabbed == heldNow and target.Parent and os.clock() - started < duration do
								local k = (os.clock() - started) / duration
								target:PivotTo(from:Lerp(to, k * k * (3 - 2 * k)))
								task.wait()
							end
						end)
					end
				else
					local offset = index == #hits and hold.Throw or Vector3.new(0, 0, -(hold.Reach + radius))
					target:PivotTo(holdAt(offset))
				end
			end
			if index == #hits then
				release() -- the last one sends them flying
			end
			-- hit[6] = options: Radius (a shockwave round the impact in front: everything in it,
			-- with the slam effect), Up (studs: the box reaches higher - blows in the air),
			-- Force (always knocks down), Crumple (drops them where they stand)
			local options = hit[6] or {}
			local hitbox = brain.hitboxSize
			local victims
			if options.Radius then
				local center = (brain.root.CFrame * CFrame.new(0, 0, -(hitbox.Z / 2 + reach * 0.5))).Position
				victims = services.HitDetectionService:QueryRadius(center, options.Radius, ignoreList(brain), brain.root.Position)
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = ignoreList(brain)
				local floor = Workspace:Raycast(center, Vector3.new(0, -(hitbox.Y + 12), 0), params)
				local ground = floor and floor.Position or center
				Net.FireNearby(services.TelegraphService.WorldFX, ground, Config.Performance.EffectRadius, "Slam", { Position = ground, Radius = options.Radius, Power = 0.8 })
			else
				local up = options.Up or 0
				local boxCFrame = brain.root.CFrame * CFrame.new(0, up / 2, -(hitbox.Z / 2 + reach / 2))
				victims = services.HitDetectionService:QueryBox(boxCFrame, Vector3.new(hitbox.X + 2, hitbox.Y + 2 + up, reach), ignoreList(brain), brain.root.Position)
			end
			if logging then
				local names = {}
				for _, v in victims do
					table.insert(names, v.Name)
				end
				print(("[Combo] %s hit %d @%.2f gap %.1f -> %s"):format(def.Action, index, os.clock() - startedAt, targetRoot and Util.FlatDistance(targetRoot.Position, brain.root.Position) or -1, #names > 0 and table.concat(names, ",") or "MISS"))
			end
			-- the OPENER missed (they're out of reach): a thinking fighter doesn't swing on
			-- at air. By personality it breaks off and resets (the client blends out of the
			-- combination into footwork), else it keeps going and tries to catch them.
			if index == 1 and #victims == 0 and #hits > 1 and not brain.possessedBy then
				brain.whiffs[def.Action] = os.clock()
				noteHabit(brain, target, "Evade")
				local abort = brain.personality and brain.personality.Abort or 0.6
				if math.random() < abort then
					brain.castToken += 1
					brain.busyUntil = os.clock() + 0.35
					brain.finisherPending = false
					brain.chainPending = false
					self:PlayAction(brain, "Gym_Bounce", 0.3, 0.6)
					if logging then
						print(("[Combo] %s ABORTED after a missed opener (%s)"):format(def.Action, brain.personality and brain.personality.Name or "?"))
					end
					release()
					return
				end
			end
			-- the last hit landed: mastery (the brain's unlocks), and a FINISHER moment
			if index == #hits and #victims > 0 and not brain.possessedBy then
				local profile = services.PlayerDataService:Get(brain.owner)
				if profile and profile.ComboMastery and not brain.model:GetAttribute("DevBuild") then
					local count = (profile.ComboMastery[def.Action] or 0) + 1
					profile.ComboMastery[def.Action] = count
					-- MASTERED: a combo that this one unlocks (its "II" version) is now open
					for _, other in NM.Moveset do
						local mastery = other.Unlock and other.Unlock.Mastery
						if mastery and mastery.Action == def.Action and mastery.Count == count then
							Net.Get("UIStateUpdate"):FireClient(brain.owner, "Toast", {
								Text = ("%s MASTERED: your Nightmare now fights with %s."):format(COMBAT.DisplayName(def.Action), COMBAT.DisplayName(other.Action)),
							})
						end
					end
				end
				if hasTag(def, "Finisher") or hasTag(def, "Signature") then
					Net.FireNearby(services.CombatService.Feedback, brain.root.Position, Config.Performance.EffectRadius, "Finisher", {
						Attacker = brain.model, Target = victims[1], Name = def.Display or def.Action, Signature = hasTag(def, "Signature"), Element = elementOf(brain, def),
					})
				end
			end
			-- the last beat of a THROW goes off to the side it slings them (Throw); a throw or a
			-- signature's last blow always puts them down
			local finalBlow = options.Force or (index == #hits and (def.Throw ~= nil or hasTag(def, "Signature")))
			local throwDirection = nil
			if def.Throw and index == #hits then
				local side = Util.FlatUnit(brain.root.CFrame.RightVector) or Vector3.xAxis
				local look = Util.FlatUnit(brain.root.CFrame.LookVector) or Vector3.zAxis
				throwDirection = ((def.Throw == "Left" and -side or side) * 0.75 + look * 0.65).Unit
			end
			for _, victim in victims do
				services.CombatService:ApplyDamage({
					Attacker = brain.model,
					Target = victim,
					BaseDamage = NM.StringDamage * hit[2],
					AttackPower = brain.stats.AttackPower,
					Knockback = hit[3] or 0,
					Heavy = hit[4] == true,
					Launch = hit[5],
					HitDirection = throwDirection,
					Crumple = options.Crumple,
					Thrown = finalBlow or nil,
					NoKnockdown = grabbed == victim, -- held in the clinch: rocked, not dropped
					Stagger = 4 + 6 * hit[2],
					Status = (index == #hits and elementOf(brain, def)) or rollOnHitStatus(brain, index == #hits and 3 or 1),
					Source = "NightmareString",
				})
			end
		end)
	end
	-- after it, when it's hurt: hit and RUN (sprint off, then dive back in)
	local health = brain.humanoid.Health / math.max(brain.humanoid.MaxHealth, 1)
	if not brain.possessedBy and health < WILD.HitAndRunHealth and math.random() < WILD.HitAndRunChance then
		brain.runAt = brain.busyUntil
		brain.chainPending = false
	end
	return true
end

-- A feint: a bounce of footwork and slips (no hit), then straight in.
function NightmareAIService:StartFeint(brain, now: number)
	local speedScale = 100 / brain.stats.AttackSpeed
	local feint = NM.Feint
	brain.busyUntil = now + feint.Cut * speedScale
	brain.cancelableAt = brain.busyUntil
	self:Stop(brain)
	self:PlayAction(brain, feint.Action, feint.Duration * 0.45 * speedScale, feint.Duration * speedScale)
	brain.counterAt = brain.busyUntil -- then dash straight in and hit
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
	brain.model:SetAttribute("NightmareGuard", nil) -- (stepping out drops the guard)
	brain.busyUntil = now + FIGHT.DashTime + 0.08
	brain.cancelableAt = brain.busyUntil
	self:Stop(brain)
	if facing then
		self:Face(brain, facing)
	end
	self:PlayAction(brain, action, 0, FIGHT.DashTime + 0.2)
	if Passives.Has(brain.model, "Afterimage") then
		-- (passive) mid-step it's only an afterimage: nothing connects
		brain.model:SetAttribute("PhaseUntil", Workspace:GetServerTimeNow() + FIGHT.DashTime + 0.1)
	end

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
	if not fresh then
		return
	end
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return
	end
	local threat = brain.hitboxSize.Z / 2 + brain.stats.Reach + math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2 + 6
	if Util.FlatDistance(brain.root.Position, targetRoot.Position) > threat then
		return
	end
	-- the brain remembers how hard it's being pressed (ReadTarget: "pressured")
	table.insert(brain.pressure, now)
	noteHabit(brain, target, "Attack")
	-- a step costs stamina; an exhausted Nightmare can't always get out of the way
	local chance = FIGHT.ReactChance * (brain.personality and brain.personality.Dodge or 1)
	if brain.stamina < COMBAT.Stamina.StepCost then
		chance *= 0.3
	end
	if math.random() < chance then
		brain.reactAt = now + randomIn(FIGHT.ReactDelay)
	end
end

-- A counter combination: square up, start the string, and on its first beat (the slip)
-- slide out of the line to the right, untouchable for the slip (Evade).
function NightmareAIService:StartCounter(brain, def, target: Model, now: number)
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	local speedScale = 100 / brain.stats.AttackSpeed
	local evade = def.Evade
	self:Stop(brain)
	if targetRoot then
		self:Face(brain, targetRoot.Position)
	end
	self:StartString(brain, def, target, now)
	local right = Util.FlatUnit(brain.root.CFrame.RightVector) or Vector3.xAxis
	brain.model:SetAttribute("PhaseUntil", Workspace:GetServerTimeNow() + evade.Time * speedScale)
	pressIn(brain, right, evade.Distance, evade.Time * speedScale)
	brain.dashReadyAt = now + FIGHT.DashCooldown
	if RunService:IsStudio() and Config.Dev.LogNightmareCombos then
		print(("[Brain] %s COUNTERS with %s"):format(brain.model.Name, def.Action))
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
	-- a COUNTER COMBINATION: the slip is the first beat of the combo itself (one continuous
	-- animation): slide out of the line untouchable, then straight back in with the hits
	local counterChance = math.min(0.9, FIGHT.CounterChance * 0.6 * (brain.personality and brain.personality.Counter or 1) * (adaptOf(brain, target).Aggressor and COMBAT.Adapt.Aggressor.CounterChance or 1))
	local counter = math.random() < counterChance and self:PickCounter(brain, now)
	if counter and not brain.root.Anchored then
		self:StartCounter(brain, counter, target, now)
		return true
	end
	local stepped
	if math.random() < FIGHT.SidestepShare then
		local side = Vector3.new(-away.Z, 0, away.X) * (math.random() < 0.5 and -1 or 1)
		stepped = self:QuickStep(brain, (side + away * 0.3).Unit, FIGHT.SidestepDistance, "Sidestep", targetRoot.Position)
	else
		stepped = self:QuickStep(brain, away, FIGHT.StepBackDistance, "StepBack", targetRoot.Position)
	end
	if stepped then
		spendStamina(brain, COMBAT.Stamina.StepCost, now)
	end
	-- Step out... then straight back in with a hit (the attacker is stuck in its swing).
	if stepped and math.random() < math.min(0.95, FIGHT.CounterChance * (brain.personality and brain.personality.Counter or 1)) then
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
		if isValidEnemy(brain, enemy, handlerRoot) then
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

------------------------------------------------------------------------------------------
-- THE COMBAT BRAIN (NightmareCombatDefinitions): what to do next, by the situation
------------------------------------------------------------------------------------------
-- x weight from a { [tag] = multiplier } table for every tag `def` carries.
local function tagMultiplier(def, multipliers): number
	local m = 1
	for _, tag in COMBAT.TagsOf(def) do
		m *= multipliers[tag] or 1
	end
	return m
end

-- What's going on with the target right now (the brain's view of the fight).
function NightmareAIService:ReadTarget(brain, target: Model, now: number)
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local serverNow = Workspace:GetServerTimeNow()
	local recent = 0
	for i = #brain.pressure, 1, -1 do
		if now - brain.pressure[i] > COMBAT.PressureWindow then
			table.remove(brain.pressure, i)
		else
			recent += 1
		end
	end
	return {
		staggered = self.Services.StatusService:IsStaggered(target),
		guarding = target:GetAttribute("Guarding") == true or (target:GetAttribute("NightmareGuard") or 0) > serverNow,
		down = target:GetAttribute("Ragdolled") == true,
		lowHealth = humanoid ~= nil and humanoid.Health / math.max(humanoid.MaxHealth, 1) < COMBAT.LowHealth,
		armoured = CollectionService:HasTag(target, "Boss") or (target:GetAttribute("Defence") or 0) >= COMBAT.ArmouredDefence,
		fast = humanoid ~= nil and humanoid.WalkSpeed > COMBAT.FastSpeed,
		pressured = recent >= COMBAT.PressureAttacks,
		followUp = brain.ownerHitTarget == target and now - (brain.ownerHitAt or -math.huge) < 1.2,
		grabbable = canClinch(target),
	}
end

-- Is this string allowed right now (body, stamina, unlocks, cooldowns, target)?
function NightmareAIService:CanUse(brain, def, can, state, now: number): boolean
	if not canThrow(def, can) or hasTag(def, "Counter") then
		return false -- (counters only come out of an evade: React)
	end
	local floor = brain.mode and brain.mode.StaminaFloor or 0
	if COMBAT.CostOf(def) > brain.stamina - floor and brain.stamina < COMBAT.Stamina.Max then
		return false
	end
	if hasTag(def, "Grab") and def.Grab and not state.grabbable then
		return false -- (a held grab needs something that can be held)
	end
	if hasTag(def, "Signature") and (now < brain.signatureReadyAt or not (state.staggered or state.lowHealth)) then
		return false
	end
	return def.Unlock == nil or self:Unlocked(brain, def)
end

-- UNLOCKS (Config Moveset Unlock): Boss = beaten that boss; Mutation = a mutated part on
-- this Nightmare; Mastery = { Action, Count } = that combo finished Count fights.
-- (Studio: workspace attribute NMUnlockAll opens everything for testing.)
function NightmareAIService:Unlocked(brain, def): boolean
	local unlock = def.Unlock
	if not unlock or (RunService:IsStudio() and Workspace:GetAttribute("NMUnlockAll")) then
		return true
	end
	local profile = self.Services.PlayerDataService:Get(brain.owner)
	if not profile then
		return false
	end
	if unlock.Boss then
		local record = profile.Bosses[unlock.Boss]
		if not (record and (record.Wins or 0) > 0) then
			return false
		end
	end
	if unlock.Mutation and not brain.model:GetAttribute("Mutations") then
		return false
	end
	if unlock.Mastery and ((profile.ComboMastery or {})[unlock.Mastery.Action] or 0) < unlock.Mastery.Count then
		return false
	end
	return true
end

-- A COUNTER combination (tag Counter, with an Evade) this body can throw right now, by
-- Weight; nil when there's none or it's too tired.
function NightmareAIService:PickCounter(brain, now: number)
	-- (a counter is a moment, not a habit: a cooldown, and the same variety memory as strings)
	if brain.possessedBy or brain.stamina < COMBAT.Stamina.Low or now < (brain.counterReadyAt or 0) then
		return nil
	end
	local can = bodyCan(brain)
	local options, total, base = {}, 0, 0
	for _, def in NM.Moveset do
		if hasTag(def, "Counter") and def.Evade and canThrow(def, can) and COMBAT.CostOf(def) <= brain.stamina then
			local w = def.Weight
			for index, multiplier in COMBAT.Repeat do
				if brain.history[index] == def.Action then
					w *= multiplier
				end
			end
			table.insert(options, { Def = def, Weight = w })
			total += w
			base += def.Weight
		end
	end
	-- (just thrown it: much less likely to go for it again)
	if total <= 0 or math.random() > total / base then
		return nil
	end
	brain.counterReadyAt = now + COMBAT.CounterCooldown
	local roll = math.random() * total
	for _, option in options do
		roll -= option.Weight
		if roll <= 0 then
			return option.Def
		end
	end
	return options[#options].Def
end

-- Scores everything it could do and picks one in proportion. Returns { Kind, Def? }.
function NightmareAIService:ChooseMove(brain, target: Model, now: number, state)
	local personality = brain.personality or COMBAT.Personalities.Technical
	local mode = brain.mode or COMBAT.Modes.Balanced
	local can = bodyCan(brain)
	local options = {}
	local function add(kind, weight, def)
		if weight > 0 then
			table.insert(options, { Kind = kind, Weight = weight, Def = def })
		end
	end
	-- how this enemy has been fighting it (Adapt)
	if state.guarding then
		noteHabit(brain, target, "Guard")
	end
	local adapt = adaptOf(brain, target)
	local function adaptFootwork(kind)
		local m = 1
		for name in adapt do
			m *= COMBAT.Adapt[name].Footwork[kind] or 1
		end
		return m
	end

	-- forced (Studio demonstrations)
	if brain.forceString and RunService:IsStudio() then
		local forced = self:PickString(brain)
		if forced then
			return { Kind = "String", Def = forced }
		end
	end

	if not state.down then
		-- a MASTERED combo takes over from its base version (Replaces)
		local replaced = {}
		for _, def in NM.Moveset do
			if def.Replaces and canThrow(def, can) and self:Unlocked(brain, def) then
				replaced[def.Replaces] = true
			end
		end
		for _, def in NM.Moveset do
			if not replaced[def.Action] and self:CanUse(brain, def, can, state, now) then
				local w = def.Weight * tagMultiplier(def, personality.Tags) * tagMultiplier(def, mode.Tags)
				if state.staggered then w *= tagMultiplier(def, COMBAT.Situation.Staggered) end
				if state.guarding then w *= tagMultiplier(def, COMBAT.Situation.Guarding) end
				if state.lowHealth then w *= tagMultiplier(def, COMBAT.Situation.LowHealth) end
				if state.armoured then w *= tagMultiplier(def, COMBAT.Situation.Armoured) end
				if state.fast then w *= tagMultiplier(def, COMBAT.Situation.Fast) end
				if state.pressured then w *= tagMultiplier(def, COMBAT.Situation.Pressured) end
				for name in adapt do
					w *= tagMultiplier(def, COMBAT.Adapt[name].Tags)
				end
				if state.followUp and mode.FollowUp then
					w *= hasTag(def, "Light") and mode.FollowUp or 1.3
				end
				for index, multiplier in COMBAT.Repeat do
					if brain.history[index] == def.Action then
						w *= multiplier
					end
				end
				if now - (brain.whiffs[def.Action] or -math.huge) < COMBAT.WhiffMemory then
					w *= COMBAT.WhiffPenalty
				end
				add("String", w, def)
			end
		end
		if self:HeavyReady(brain, now) and can.Arms then
			local w = COMBAT.Footwork.Heavy * (personality.Tags.Heavy or 1) * (mode.Tags.Heavy or 1)
			if state.staggered then w *= 2.5 end
			if state.guarding then w *= 2.0 end -- (it breaks guards)
			add("Heavy", w)
		end
	end
	-- footwork: always possible; more so when tired, when they're down, when pressured
	local tired = brain.stamina < COMBAT.Stamina.Low
	local function footwork(kind)
		return COMBAT.Footwork[kind] * (personality.Footwork[kind] or 1) * (mode.Footwork[kind] or 1) * adaptFootwork(kind)
	end
	add("Circle", footwork("Circle") * (tired and 3 or 1) * (state.down and 6 or 1) * (mode.FollowUp and not state.followUp and 1.6 or 1))
	if not state.down then
		add("Feint", footwork("Feint") * (state.guarding and 1.6 or 1))
		add("Flank", footwork("Flank") * (state.guarding and 1.4 or 1) * (state.boss and 2 or 1) * (brain.flair or 1))
		add("Guard", footwork("Guard") * (state.pressured and 2.2 or 1) * (tired and 2.5 or 1))
	end

	local total = 0
	for _, option in options do
		total += option.Weight
	end
	if total <= 0 then
		return { Kind = "Circle" }
	end
	local roll = math.random() * total
	local picked = options[#options]
	for _, option in options do
		roll -= option.Weight
		if roll <= 0 then
			picked = option
			break
		end
	end
	if RunService:IsStudio() and Config.Dev.LogNightmareCombos then
		table.sort(options, function(a, b)
			return a.Weight > b.Weight
		end)
		local top = {}
		for i = 1, math.min(4, #options) do
			local o = options[i]
			table.insert(top, ("%s %.1f"):format(o.Def and o.Def.Action or o.Kind, o.Weight / total * 100))
		end
		local flags = {}
		for key, value in state do
			if value == true then
				table.insert(flags, key)
			end
		end
		for name in adapt do
			table.insert(flags, "adapt:" .. name)
		end
		print(("[Brain] %s (%s/%s, stamina %d%s) -> %s   [%s%%]"):format(
			brain.model.Name, brain.personality and brain.personality.Name or "?", brain.mode and brain.mode.Name or "?", brain.stamina,
			#flags > 0 and (", " .. table.concat(flags, ",")) or "", picked.Def and picked.Def.Action or picked.Kind, table.concat(top, " | ")))
	end
	return picked
end

-- GUARD: cover up for a moment (CombatService halves light hits; a Heavy breaks it).
function NightmareAIService:StartGuard(brain, now: number)
	local guard = COMBAT.Guard
	local time = randomIn(guard.Time)
	brain.busyUntil = now + time
	brain.cancelableAt = now + 0.15 -- (React may still step out of it)
	self:Stop(brain)
	self:PlayAction(brain, guard.Action, 0, time)
	brain.model:SetAttribute("NightmareGuard", Workspace:GetServerTimeNow() + time)
	spendStamina(brain, guard.StaminaDrain * time, now)
end

function NightmareAIService:Engage(brain, target: Model, now: number)
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	local targetRadius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
	local reach = brain.hitboxSize.Z / 2 + brain.stats.Reach
	local distance = Util.FlatDistance(brain.root.Position, targetRoot.Position)
	-- (Sprint passive) a far target: it breaks into a four-legged sprint to close in
	local sprint = Passives.ById.Sprint
	local sprinting = Passives.Has(brain.model, "Sprint") and distance > sprint.Distance
	brain.model:SetAttribute("Sprinting", sprinting or nil)
	self:SetSpeed(brain, brain.stats.MoveSpeed * (sprinting and sprint.SpeedMultiplier or 1))

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

	-- HIT AND RUN (hurt): sprint off at an angle for a moment, then dive straight back in.
	if brain.runAt and now >= brain.runAt then
		brain.runAt = nil
		local side = Vector3.new(-toTarget.Z, 0, toTarget.X) * (math.random() < 0.5 and -1 or 1)
		brain.running = { Until = now + randomIn(WILD.HitAndRunTime), Direction = (-toTarget + side * 0.8).Unit }
	end
	if brain.running then
		if now < brain.running.Until then
			self:SetSpeed(brain, brain.stats.MoveSpeed * WILD.FlankSpeed)
			self:StopFacing(brain)
			brain.nav:Stop()
			brain.humanoid:MoveTo(brain.root.Position + brain.running.Direction * 12)
			return
		end
		brain.running = nil
		brain.counterAt = now -- and back in, hard
	end

	-- FLANK: sprinting round to their side / back, then straight in from there.
	if brain.flank then
		local point = targetRoot.Position + brain.flank.Direction * (standOff + 2)
		if now < brain.flank.Until and Util.FlatDistance(brain.root.Position, point) > 2.5 then
			self:SetSpeed(brain, brain.stats.MoveSpeed * WILD.FlankSpeed)
			self:StopFacing(brain)
			brain.nav:Stop()
			brain.humanoid:MoveTo(point)
			return
		end
		brain.flank = nil
		brain.counterAt = now -- arrived (or gave up): dash in and hit
	end

	-- Just finished a combo or a heavy: hop back out, then circle for a moment instead of
	-- standing in front of the target trading hits. (Unless it's chaining: straight into
	-- the next string, no breather.)
	if brain.finisherPending and brain.chainPending then
		brain.finisherPending = false
		brain.chainPending = false
		brain.circleUntil = 0
	end
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
		local gap = distance - standOff
		-- A LEAPING string (pounce, rolling charge) can open from out here: the leap itself
		-- closes the gap (once per approach)
		if not brain.leapRolled and gap > 2.5 then
			brain.leapRolled = true
			if math.random() < WILD.LeapFromRangeChance * (brain.flair or 1) then
				local picked = self:PickString(brain, function(def)
					return def.Leap ~= nil and def.Leap.Max >= gap
				end)
				if picked then
					self:Stop(brain)
					self:Face(brain, targetRoot.Position)
					self:StartString(brain, picked, target, now)
					return
				end
			end
		end
		-- Gap closer: from a little outside reach, dash straight in (once per approach).
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
	brain.leapRolled = false

	self:Stop(brain)
	self:Face(brain, targetRoot.Position)

	-- Only swing once roughly facing the target, so attacks read as intentional.
	local look = Util.FlatUnit(brain.root.CFrame.LookVector)
	local wanted = Util.FlatUnit(targetRoot.Position - brain.root.Position)
	if not (look and wanted and look:Dot(wanted) > 0.8) then
		return
	end
	-- About to attack. A wild one doesn't always just swing: sometimes it sprints round to
	-- their side or back first, sometimes it feints. But a boss that's EXPOSED (just
	-- attacked) or BROKEN (on its knees) gets everything, right now (Config.Bosses).
	local flair = brain.flair or 1
	local isBoss = CollectionService:HasTag(target, "Boss")
	local opening = isBoss and ((target:GetAttribute("ExposedUntil") or 0) > Workspace:GetServerTimeNow() or self.Services.StatusService:IsStaggered(target))
	if opening then
		if self:HeavyReady(brain, now) and math.random() < 0.5 then
			self:StartHeavy(brain, now)
		else
			local picked = self:PickString(brain)
			if picked then
				self:StartString(brain, picked, target, now)
			else
				self:StartAttack(brain, now)
			end
		end
		brain.chainPending = true -- and keep going while it's open
		return
	end
	-- THE COMBAT BRAIN decides (personality, mode, the target's state, stamina, variety)
	local state = self:ReadTarget(brain, target, now)
	state.boss = isBoss -- (bosses get circled and flanked more: their reach is huge)
	local choice = self:ChooseMove(brain, target, now, state)
	if choice.Kind == "String" then
		self:StartString(brain, choice.Def, target, now)
	elseif choice.Kind == "Heavy" then
		self:StartHeavy(brain, now)
		spendStamina(brain, COMBAT.Stamina.CostByTag.Heavy, now)
	elseif choice.Kind == "Guard" then
		self:StartGuard(brain, now)
	elseif choice.Kind == "Feint" then
		self:StartFeint(brain, now)
	elseif choice.Kind == "Flank" then
		local angle = math.rad(randomIn(WILD.FlankAngle)) * (math.random() < 0.5 and -1 or 1)
		brain.flank = { Direction = CFrame.Angles(0, angle, 0):VectorToWorldSpace(-toTarget), Until = now + WILD.FlankTime }
	else -- Circle: reposition (and get its breath back) just outside reach
		brain.circleUntil = now + randomIn(FIGHT.CircleTime)
		brain.circleSign = math.random() < 0.5 and -1 or 1
	end
end

function NightmareAIService:Follow(brain, handlerRoot: BasePart, now: number)
	local desired = (handlerRoot.CFrame * CFrame.new(NM.FollowOffset)).Position
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
	-- stamina comes back once it stops spending it (the brain backs off when it's low)
	local stamina = COMBAT.Stamina
	if brain.stamina < stamina.Max and now - brain.staminaSpentAt > stamina.RegenDelay then
		brain.stamina = math.min(stamina.Max, brain.stamina + stamina.Regen * dt)
	end
	local shown = math.floor(brain.stamina / 5) * 5
	if brain.model:GetAttribute("Stamina") ~= shown then
		brain.model:SetAttribute("Stamina", shown)
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
		-- personality: how wild this one fights (chains, flanks, feints), 0.6 - 1.2
		flair = 0.6 + math.random() * 0.6,
		-- THE COMBAT BRAIN (NightmareCombatDefinitions): stamina, what it threw lately,
		-- which openers whiffed, how often the target has been attacking it, its style
		stamina = COMBAT.Stamina.Max,
		staminaSpentAt = 0,
		history = {},
		whiffs = {},
		pressure = {},
		habits = setmetatable({}, { __mode = "k" }), -- [target] = what it keeps doing (Adapt)
		signatureReadyAt = 0,
		possessedBy = nil,
		nextIdleAction = now + math.random(NM.IdleActionInterval[1], NM.IdleActionInterval[2]),
	}
	brains[model] = brain
	brainByPlayer[owner] = brain
	model:SetAttribute("Command", "Defend")
	self:ApplyStyle(owner)
end

-- Reads the owner's chosen fighting style (profile.NightmareStyle) onto their brain;
-- "Auto" picks the personality from the body.
function NightmareAIService:ApplyStyle(player: Player)
	local brain = brainByPlayer[player]
	if not brain then
		return
	end
	local profile = self.Services.PlayerDataService:Get(player)
	local style = profile and profile.NightmareStyle or { Personality = "Auto", Mode = "Balanced" }
	local id = style.Personality
	if not COMBAT.Personalities[id] then
		id = COMBAT.AutoPersonality(brain.model)
	end
	brain.personality = COMBAT.Personalities[id]
	brain.mode = COMBAT.Modes[style.Mode] or COMBAT.Modes.Balanced
	brain.model:SetAttribute("Personality", id)
	brain.model:SetAttribute("FightMode", style.Mode)
	-- (the command menu shows the CHOICE: "Auto" stays "Auto")
	player:SetAttribute("NightmarePersonality", style.Personality)
	player:SetAttribute("NightmareMode", style.Mode)
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

	-- FIGHTING STYLE: { Personality = id, Mode = id } (either may be left out); saved, and
	-- applied straight away if it's out
	if command == "Style" then
		local profile = self.Services.PlayerDataService:Get(player)
		if type(arg) ~= "table" or not profile then
			return
		end
		local style = profile.NightmareStyle
		if type(arg.Personality) == "string" and table.find(COMBAT.PersonalityOrder, arg.Personality) then
			style.Personality = arg.Personality
		end
		if type(arg.Mode) == "string" and COMBAT.Modes[arg.Mode] then
			style.Mode = arg.Mode
		end
		self:ApplyStyle(player)
		player:SetAttribute("NightmarePersonality", style.Personality)
		player:SetAttribute("NightmareMode", style.Mode)
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
	elseif command == "Focus" then
		-- your lock-on target: go after them, keeping the stance (Defend / Aggressive); a
		-- focused Attack switches to them too. A Retreat is left alone.
		local handlerRoot = getHandlerRoot(player)
		if brain.command == "Retreat" or typeof(arg) ~= "Instance" or not arg:IsA("Model") or not handlerRoot then
			return
		end
		if not isValidEnemy(brain, arg, handlerRoot) then
			return
		end
		if brain.command == "Attack" then
			setCommand(brain, "Attack", arg)
		end
		if brain.target ~= arg then
			brain.target = arg
			brain.targetSince = os.clock()
		end
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
		-- the OWNER landed a hit: the brain notes it (ReadTarget "followUp"), and in Assist
		-- mode it goes after whatever its Handler is hitting
		local ownerPlayer = attacker and Players:GetPlayerFromCharacter(attacker)
		local ownerBrain = ownerPlayer and brainByPlayer[ownerPlayer]
		if ownerBrain and CollectionService:HasTag(target, "Enemy") then
			ownerBrain.ownerHitAt, ownerBrain.ownerHitTarget = now, target
			if ownerBrain.mode and ownerBrain.mode.FollowUp and ownerBrain.command ~= "Retreat" and ownerBrain.command ~= "Attack" and ownerBrain.target ~= target then
				ownerBrain.target = target
				ownerBrain.targetSince = now
			end
		end
		local brain = brains[target]
		if not brain then
			return
		end
		brain.lastDamagedAt = now
		noteHabit(brain, attacker, "Hurt")
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
