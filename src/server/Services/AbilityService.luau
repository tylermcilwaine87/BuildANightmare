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

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
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

-- How far in front of its body a Nightmare's mouth reaches when it snaps shut: the head's
-- front face at rest plus the bite's forward thrust of the core (NightmarePoses BITE pushes
-- the core 1 stud forward on the snap). Measured from the parts once and cached.
local BITE_THRUST = 1
local function mouthReach(brain): number
	if brain.mouthReach then
		return brain.mouthReach
	end
	local rootCFrame = brain.root.CFrame
	local front = 0
	for _, part in brain.model:GetDescendants() do
		if part:IsA("BasePart") and part.Name:sub(1, 5) == "Head_" then
			local relative = rootCFrame:ToObjectSpace(part.CFrame)
			local depth = math.abs(relative.XVector.Z) * part.Size.X + math.abs(relative.YVector.Z) * part.Size.Y + math.abs(relative.ZVector.Z) * part.Size.Z
			front = math.max(front, -relative.Position.Z + depth / 2)
		end
	end
	brain.mouthReach = (front > 0 and front or brain.hitboxSize.Z / 2) + BITE_THRUST
	return brain.mouthReach
end

-- How close the Nightmare needs to be (centre to centre, minus target radius) to cast.
function AbilityService:GetCastRange(brain, def): number
	local half = brain.hitboxSize.Z / 2
	if def.Type == "Melee" and def.Lunge then
		-- a bite only goes off once the lunge can carry the jaws onto the target (Reach: a
		-- striking limb that isn't the mouth, e.g. the scorpion's stinger, measured)
		return math.min(half + def.Range - 0.5, (def.Reach or mouthReach(brain)) + def.Lunge - 0.4)
	elseif def.Type == "Melee" then
		return half + def.Range - 0.5
	elseif def.Type == "AoE" then
		return def.Offset + def.Radius * 0.7
	elseif def.Type == "Dash" then
		return half + def.Distance * 0.9
	elseif def.Type == "Pull" then
		return def.Range
	elseif def.Type == "Leap" then
		return def.Leap + half
	elseif def.Type == "Breath" then
		return half + def.Range * 0.8
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

-- `motion` (optional) = how the blow's force travels, for the victim's reaction:
--   "Grip"  a bite that clamps and tears back: the victim is jerked TOWARD the attacker
--   a Vector3 = that world direction (a slash sweeping across them)
local function damageTargets(self, brain, targets, def, knockback, motion)
	local combat = self.Services.CombatService
	for _, target in targets do
		local hitDirection
		if motion == "Grip" then
			hitDirection = Util.FlatUnit(brain.root.Position - target:GetPivot().Position)
		elseif typeof(motion) == "Vector3" then
			hitDirection = motion
		end
		combat:ApplyDamage({
			Attacker = brain.model,
			Target = target,
			BaseDamage = def.Damage,
			AttackPower = brain.stats.AttackPower,
			Knockback = knockback or 0,
			Stagger = def.Stagger or 15,
			Heavy = def.Heavy == true,
			Status = def.Element and StatusDefinitions.ByElement[def.Element] or nil,
			HitDirection = hitDirection,
			Source = "Ability:" .. def.DisplayName,
		})
	end
end

-- The floor's height under `position` (nil over a void), ignoring every character.
local FLOOR_PARAMS = RaycastParams.new()
FLOOR_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
local function floorAt(position: Vector3, ignore): number?
	FLOOR_PARAMS.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), FLOOR_PARAMS)
	return hit and hit.Position.Y or nil
end

-- A short physical lunge at the target during the windup (a bite closing in): the body
-- travels at most `maxDistance` studs, stopping with its front just short of the target,
-- arriving as the windup ends (the contact frame).
local function lungeAt(brain, target: Model?, windup: number, maxDistance: number, reach: number?)
	local root = brain.root
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	local attachment = root:FindFirstChild("FacingAttachment")
	if not targetRoot or not attachment or root.Anchored then
		return
	end
	-- stop where the mouth meets the target's body (teeth sinking in a little), not where
	-- the bounding boxes touch: the box is far deeper than the head reaches
	local offset = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	local extents = target:GetExtentsSize()
	local contact = (reach or mouthReach(brain)) + math.max(extents.X, extents.Z) / 2 - 0.4
	local travel = math.clamp(offset.Magnitude - contact, 0, maxDistance)
	if travel < 0.3 then
		return
	end
	-- Driven frame by frame on the anchored body (not by a physics force): clients draw
	-- free-physics bodies ~0.3 s behind, which made the jaws snap shut before the mouth
	-- arrived on screen. Anchored CFrames reach clients as fast as the animation's own
	-- start signal, so the lunge, the snap and the hit land together for everyone.
	local start, duration = windup * 0.4, windup * 0.6
	task.delay(start, function()
		if not root.Parent or root.Anchored then
			return
		end
		local from = root.CFrame
		local step = offset.Unit * travel
		root.Anchored = true
		local began = os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local t = math.min((os.clock() - began) / duration, 1)
			local eased = 1 - (1 - t) * (1 - t) -- fast off the mark, settling into the bite
			if root.Parent then
				root.CFrame = from + step * eased
			end
			if t >= 1 then
				connection:Disconnect()
				if root.Parent then
					root.Anchored = false
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end)
	end)
end

local function stillValid(brain, castToken: number): boolean
	return brain.castToken == castToken and brain.model.Parent ~= nil and brain.humanoid.Health > 0
end

-- A body small enough to be lifted and shaken in the jaws (not a boss, not a player's
-- own character, nothing much bigger than the biter).
local function canHold(brain, target: Model): boolean
	local root = target:FindFirstChild("HumanoidRootPart")
	if not root or root.Anchored or target:GetAttribute("BossId") or target:GetAttribute("Ragdolled") then
		return false
	end
	if Players:GetPlayerFromCharacter(target) then
		return false
	end
	local mine, theirs = brain.model:GetExtentsSize(), target:GetExtentsSize()
	return math.max(theirs.X, theirs.Y, theirs.Z) <= math.max(mine.X, mine.Y, mine.Z) * 1.4
end

-- THE CLAMP (a bite with def.Clamp). The jaws lock on to the nearest body they hit, which
-- takes the first share of the damage (no knockdown: it's held). A body that can be held
-- is locked into the mouth and thrashed side to side with the head (in step with the
-- animation's thrash), helpless, for Hold seconds; the biter stays planted. Then the head
-- RIPS away: the rest of the damage and a hard throw to the biter's left (the way the
-- rip yanks). Anything else in the bite takes a normal hit.
function AbilityService:ClampAndRip(brain, castToken: number, hits, def)
	local clamp = def.Clamp
	local root = brain.root
	local mouth = mouthReach(brain)
	local mouthPoint = (root.CFrame * CFrame.new(0, 0, -mouth)).Position
	table.sort(hits, function(a, b)
		return (a:GetPivot().Position - mouthPoint).Magnitude < (b:GetPivot().Position - mouthPoint).Magnitude
	end)
	local victim = table.remove(hits, 1)
	if #hits > 0 then
		damageTargets(self, brain, hits, def, 10, "Grip")
	end
	local combat = self.Services.CombatService
	local source = "Ability:" .. def.DisplayName
	combat:ApplyDamage({
		Attacker = brain.model,
		Target = victim,
		BaseDamage = def.Damage * clamp.Share,
		AttackPower = brain.stats.AttackPower,
		Knockback = 0,
		Stagger = def.Stagger or 15,
		Status = def.Element and StatusDefinitions.ByElement[def.Element] or nil,
		HitDirection = Util.FlatUnit(root.Position - victim:GetPivot().Position),
		NoKnockdown = true,
		Source = source,
	})

	local victimRoot = victim:FindFirstChild("HumanoidRootPart")
	local victimHumanoid = victim:FindFirstChildOfClass("Humanoid")
	local hold = victimRoot and victimHumanoid and victimHumanoid.Health > 0 and canHold(brain, victim)
	local grip = (root.CFrame * CFrame.new(0, 0, -mouth))
	local relative = hold and grip:ToObjectSpace(victimRoot.CFrame)
	if hold then
		victim:SetAttribute("Gripped", true)
	end
	local began = os.clock()
	local released = false
	local connection
	local function release()
		if released then
			return
		end
		released = true
		connection:Disconnect()
		if hold and victimRoot.Parent then
			victimRoot.Anchored = false
			victimRoot.AssemblyLinearVelocity = Vector3.zero
		end
		if victim.Parent then
			victim:SetAttribute("Gripped", nil)
		end
		if root.Parent then
			root.Anchored = false
		end
	end
	connection = RunService.Heartbeat:Connect(function()
		if not stillValid(brain, castToken) or brain.model:GetAttribute("Ragdolled") or not victim.Parent or (victimHumanoid and victimHumanoid.Health <= 0) then
			release()
			return
		end
		root.Anchored = true -- planted for the whole hold
		if hold then
			-- thrashed with the head: a yaw swing about the mouth, lifting a little each shake
			local t = os.clock() - began
			local ramp = math.min(t / 0.12, 1)
			local shake = math.sin(t * math.pi * 2 * clamp.Shake) * math.rad(16) * ramp
			local lift = math.abs(math.sin(t * math.pi * 2 * clamp.Shake)) * 0.25 * ramp
			victimRoot.Anchored = true
			victimRoot.CFrame = grip * CFrame.Angles(0, shake, 0) * CFrame.new(0, lift, 0) * relative
		end
	end)
	task.delay(clamp.Hold, function()
		local wasValid = not released and stillValid(brain, castToken)
		release()
		if not wasValid or not victim.Parent or (victimHumanoid and victimHumanoid.Health <= 0) then
			return
		end
		-- RIP: torn away to the biter's left and out
		local throw = (-root.CFrame.RightVector * 0.9 + root.CFrame.LookVector * 0.35).Unit
		combat:ApplyDamage({
			Attacker = brain.model,
			Target = victim,
			BaseDamage = def.Damage * (1 - clamp.Share),
			AttackPower = brain.stats.AttackPower,
			Knockback = clamp.RipKnockback,
			Stagger = def.Stagger or 15,
			Heavy = true,
			HitDirection = throw,
			Source = source,
		})
	end)
end

local function ignoreList(brain)
	local ignore = { brain.model }
	if brain.owner.Character then
		table.insert(ignore, brain.owner.Character)
	end
	return ignore
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
	-- Each ability plays ITS OWN animation ("Ability_<Id>", e.g. Ability_Bite; the animator
	-- falls back to the ability type's generic motion if it has none yet), performed by the
	-- limb it comes from (ActionSource: Head, RightArm, LeftArm, Tail...).
	local source = brain.model:GetAttribute(("Ability%dSource"):format(slot)) or ""
	brain.model:SetAttribute("ActionSource", source)
	ai:PlayAction(brain, "Ability_" .. def.Id, windup, total)
	self.Services.TutorialService:Notify(brain.owner, "AbilityUsed")
	self.Services.ChallengeService:Notify(brain.owner, "AbilityUsed")

	local root = brain.root
	local hitbox = brain.hitboxSize

	if def.Type == "Melee" then
		if def.Lunge and target then
			lungeAt(brain, target, windup, def.Lunge, def.Reach)
		end
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			-- how the blow lands on them: a bite grips and tears back; a sweep carries them
			-- across the way the claw travels (a left-arm claw sweeps the other way)
			local motion
			if def.Motion == "Grip" then
				motion = "Grip"
			elseif def.Motion == "Sweep" then
				local across = source == "LeftArm" and root.CFrame.RightVector or -root.CFrame.RightVector
				motion = (across * 0.8 + root.CFrame.LookVector * 0.6).Unit
			end
			local cframe = root.CFrame * CFrame.new(0, 0, -(hitbox.Z / 2 + def.Range / 2))
			local hits = hitDetection:QueryBox(cframe, Vector3.new(def.Width, hitbox.Y + 2, def.Range), ignoreList(brain), root.Position)
			if def.Clamp and #hits > 0 then
				self:ClampAndRip(brain, castToken, hits, def)
			else
				damageTargets(self, brain, hits, def, def.Knockback or 15, motion)
			end
		end)
		if def.Clamp then
			-- committed until the rip: nothing (not even a queued ability) cuts the hold short
			brain.busyUntil = now + windup + def.Clamp.Hold + def.Recovery
			brain.cancelableAt = now + windup + def.Clamp.Hold + 0.05
		end
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
	elseif def.Type == "Leap" then
		self:Leap(brain, castToken, def, target, windup)
	elseif def.Type == "Breath" then
		self:Breath(brain, castToken, def, windup)
		local breathing = def.Ticks * def.Interval
		brain.busyUntil = now + windup + breathing + def.Recovery
		brain.cancelableAt = now + windup + breathing
	elseif def.Type == "Shield" then
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			brain.model:SetAttribute("Shield", def.Amount)
			brain.model:SetAttribute("ShieldMax", def.Amount)
			if def.Retaliate then
				brain.model:SetAttribute("RetaliateUntil", Workspace:GetServerTimeNow() + def.Duration)
				brain.model:SetAttribute("RetaliateStatus", def.Retaliate.Status)
				brain.model:SetAttribute("RetaliateRange", def.Retaliate.Range)
			end
			Net.FireNearby(self.Services.TelegraphService.WorldFX, brain.root.Position, Config.Performance.EffectRadius, "Shield", { Target = brain.model, Duration = def.Duration })
			task.delay(def.Duration, function()
				if brain.model.Parent then
					brain.model:SetAttribute("Shield", 0)
				end
			end)
		end)
	end
end

-- LEAP (Meteor Fist): crouch through the first part of the windup, then the body flies
-- an arc onto the target (at most def.Leap studs, def.Height high at the top) and lands
-- on the Hit frame; Damage in Radius around the fist (just in front of the body), with a
-- knockdown. Driven frame by frame on the anchored body, like the bite's lunge, so every
-- client sees it land with the animation.
function AbilityService:Leap(brain, castToken: number, def, target: Model?, windup: number)
	local root = brain.root
	local hitbox = brain.hitboxSize
	local ignore = ignoreList(brain)
	local start = root.Position
	local look = Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
	local reachAhead = def.FistAhead or hitbox.Z / 2 -- where the fist comes down, ahead of the body
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	local landing
	if targetRoot then
		table.insert(ignore, target)
		local offset = Util.Flat(targetRoot.Position - start)
		local travel = math.clamp(offset.Magnitude - reachAhead, 0, def.Leap)
		look = Util.FlatUnit(offset) or look
		landing = start + look * travel
	else
		landing = start + look * def.Leap * 0.6
	end
	-- keep the same standing height over a different floor
	local floorHere, floorThere = floorAt(start, ignore), floorAt(landing, ignore)
	if floorHere and floorThere then
		landing = Vector3.new(landing.X, start.Y + (floorThere - floorHere), landing.Z)
	else
		landing = Vector3.new(landing.X, start.Y, landing.Z)
	end
	local ground = landing - Vector3.new(0, hitbox.Y / 2 + brain.humanoid.HipHeight, 0)
	local center = ground + look * reachAhead
	self.Services.TelegraphService:Circle(center, def.Radius, windup, "Friendly")

	local takeoff = windup * 0.3
	task.delay(takeoff, function()
		if not stillValid(brain, castToken) or root.Anchored then
			return
		end
		local flight = windup - takeoff
		local facing = CFrame.lookAt(Vector3.zero, look)
		root.Anchored = true
		local began = os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local t = math.min((os.clock() - began) / flight, 1)
			if not stillValid(brain, castToken) or brain.model:GetAttribute("Ragdolled") then
				connection:Disconnect()
				if root.Parent then
					root.Anchored = false
				end
				return
			end
			local arc = 4 * t * (1 - t) * def.Height
			root.CFrame = facing + start:Lerp(landing, t) + Vector3.new(0, arc, 0)
			if t >= 1 then
				connection:Disconnect()
				root.Anchored = false
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end)
	end)

	task.delay(windup, function()
		if not stillValid(brain, castToken) then
			return
		end
		local telegraphs = self.Services.TelegraphService
		telegraphs:Impact(center, def.Radius, "Friendly")
		Net.FireNearby(telegraphs.WorldFX, center, Config.Performance.EffectRadius, "Slam", { Position = center, Radius = def.Radius, Power = 0.8, Fire = true })
		local hits = {}
		for _, model in self.Services.HitDetectionService:QueryRadius(center + Vector3.new(0, 3, 0), def.Radius + 3, ignoreList(brain), root.Position) do
			local r = model:FindFirstChild("HumanoidRootPart")
			if r and Util.FlatDistance(r.Position, center) <= def.Radius + math.max(r.Size.X, r.Size.Z) / 2 then
				table.insert(hits, model)
			end
		end
		damageTargets(self, brain, hits, def, 30)
	end)
end

-- BREATH (Dragon Breath): from the Hit frame on, Ticks blasts Interval apart: everything
-- within Range of the head's front and inside the Cone in front takes Damage (and the
-- element's status). The fire on screen (WorldFX "Breath") is the same cone.
function AbilityService:Breath(brain, castToken: number, def, windup: number)
	local root = brain.root
	local halfCone = math.rad(def.Cone / 2)
	local duration = def.Ticks * def.Interval
	task.delay(windup, function()
		if not stillValid(brain, castToken) then
			return
		end
		Net.FireNearby(self.Services.TelegraphService.WorldFX, root.Position, Config.Performance.EffectRadius, "Breath", {
			Target = brain.model, Duration = duration, Range = def.Range, Cone = def.Cone,
		})
	end)
	for tick = 0, def.Ticks - 1 do
		task.delay(windup + tick * def.Interval, function()
			if not stillValid(brain, castToken) then
				return
			end
			local look = Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
			-- (the head's front + its thrust: 3.5 studs out on the Dragon Skull, measured)
			local mouth = root.Position + look * mouthReach(brain)
			local hits = {}
			for _, model in self.Services.HitDetectionService:QueryRadius(mouth, def.Range + 3, ignoreList(brain), root.Position) do
				local r = model:FindFirstChild("HumanoidRootPart")
				if r then
					local offset = Util.Flat(r.Position - mouth)
					local size = math.max(r.Size.X, r.Size.Z) / 2
					local distance = offset.Magnitude
					-- inside the cone (a body's own width counts: its edge can be in the fire)
					local angle = distance > 0.01 and math.acos(math.clamp(offset.Unit:Dot(look), -1, 1)) or 0
					local slack = distance > 0.01 and math.atan2(size, distance) or math.pi
					if distance <= def.Range + size and angle <= halfCone + slack then
						table.insert(hits, model)
					end
				end
			end
			damageTargets(self, brain, hits, def, 2)
		end)
	end
end

return AbilityService
