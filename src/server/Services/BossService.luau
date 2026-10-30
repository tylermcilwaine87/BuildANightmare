--[[
	BossService  (ModuleScript)
	Location: ServerScriptService/Server/Services/BossService

	Runs boss ENCOUNTERS end to end:

	  Start  -> validate request -> reserve an arena slot (one per active encounter)
	         -> teleport Handler + Nightmare in -> intro banner -> boss wakes
	  Fight  -> generic boss state machine at 10 Hz (shared by every boss):
	              Idle, Chase, Attacking (Windup/Attack/Recovery run inside the
	              attack), PhaseTransition, Defeated
	            The boss behaviour module (Bosses/<BossId>) chooses and runs attacks.
	  Victory-> BossRewardService grants loot EXACTLY ONCE per player per encounter
	         -> reward screen -> player chooses REPLAY or RETURN (auto-return later)
	  Fail   -> every participating Handler is knocked out, or they leave

	Bosses scale with participant count (Config.Bosses.HealthScaling). Parties (Phase 6):
	the leader starts the fight and every free member comes along; a knocked-out member
	rejoins the arena on respawn, and the fight fails only if everyone is down at once.

	Difficulties (Phase 5): Normal / Hard / Nightmare, chosen at the portal. Each needs
	the previous one beaten (BossDefinitions.IsModeUnlocked). Tutorial players always get
	the Tutorial mode regardless of what they ask for.

	Remote BossRequest (RemoteFunction):
	  "Start", bossId, mode?   "Leave"   "Replay"   "Return"
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local BossDefinitions = require(Shared:WaitForChild("BossDefinitions"))

local BossesFolder = script.Parent:WaitForChild("Bosses")
local ArenaBuilder = require(BossesFolder:WaitForChild("ArenaBuilder"))

local BossService = {}

local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))

local behaviours = {} -- [bossId] = module (lazy)
local arenas = {} -- [arenaType .. slot] = arena info (built once, reused)
local slotInUse = {} -- [arenaType] = { [slot] = true }
local displays = {} -- [arenaType] = dormant boss statue in the world arena (slot 1)
local encounters = {} -- [id] = encounter
local playerEncounter: { [Player]: any } = {}

local function behaviourFor(bossId: string)
	if not behaviours[bossId] then
		behaviours[bossId] = require(BossesFolder:WaitForChild(bossId))
	end
	return behaviours[bossId]
end

------------------------------------------------------------------------------------------
-- Context: the API boss behaviour modules use (keeps them small and safe)
------------------------------------------------------------------------------------------
local Context = {}
Context.__index = Context

-- False once the fight ends OR the boss is staggered or knocked down: either interrupts
-- the attack.
function Context:Alive(): boolean
	local enc = self.Encounter
	return enc.State == "Fighting" and self.Model.Parent ~= nil and self.Humanoid.Health > 0 and not BossService.Services.StatusService:IsStaggered(self.Model) and not self.Model:GetAttribute("Ragdolled")
end

-- Waits; returns false if the fight ended meanwhile (attacks must then stop).
function Context:Wait(seconds: number): boolean
	task.wait(seconds)
	return self:Alive()
end

function Context:WindupTime(base: number): number
	local multiplier = self.ModeConfig.WindupMultiplier * (self.Overdrive and 0.8 or 1)
	-- Never shorter than MinWindup unless the attack was designed faster to begin with.
	return math.max(base * multiplier, math.min(base, Config.Bosses.MinWindup))
end

function Context:Action(name: string, windup: number, duration: number)
	local model = self.Model
	model:SetAttribute("ActionName", name)
	model:SetAttribute("ActionWindup", windup)
	model:SetAttribute("ActionDuration", duration)
	model:SetAttribute("ActionSeq", (model:GetAttribute("ActionSeq") or 0) + 1)
end

function Context:Stop()
	self.Humanoid:MoveTo(self.Root.Position)
end

function Context:Face(position: Vector3)
	local direction = Util.FlatUnit(position - self.Root.Position)
	if direction then
		self.Root.CFrame = CFrame.lookAt(self.Root.Position, self.Root.Position + direction)
	end
end

function Context:Position(model: Model): Vector3
	local root = model:FindFirstChild("HumanoidRootPart")
	return root and root.Position or model:GetPivot().Position
end

function Context:GroundPosition(model: Model): Vector3
	local p = self:Position(model)
	return Vector3.new(p.X, self.Arena.GroundY, p.Z)
end

function Context:ClampToArena(position: Vector3): Vector3
	local center = self.Arena.Center
	local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local limit = self.Arena.Radius - 3
	if offset.Magnitude > limit then
		offset = offset.Unit * limit
	end
	return Vector3.new(center.X + offset.X, self.Arena.GroundY, center.Z + offset.Z)
end

-- A flat box on the floor in front of the boss: returns CFrame, Size.
function Context:FrontBox(length: number, width: number): (CFrame, Vector3)
	local look = Util.FlatUnit(self.Root.CFrame.LookVector) or Vector3.zAxis
	local base = Vector3.new(self.Root.Position.X, self.Arena.GroundY, self.Root.Position.Z)
	local centre = base + look * (self.Root.Size.Z / 2 + length / 2)
	return CFrame.lookAt(centre, centre + look), Vector3.new(width, 1, length)
end

function Context:Targets(): { Model }
	return BossService:GetTargets(self.Encounter)
end

function Context:PickTarget(): Model?
	return BossService:PickTarget(self.Brain, os.clock(), true)
end

function Context:Circle(position: Vector3, radius: number, duration: number, style: string?)
	return BossService.Services.TelegraphService:Circle(position, radius, duration, style)
end

function Context:Box(cframe: CFrame, size: Vector3, duration: number, style: string?)
	return BossService.Services.TelegraphService:Box(cframe, size, duration, style)
end

function Context:Impact(position: Vector3, radius: number)
	BossService.Services.TelegraphService:Impact(position, radius, "Hostile")
end

-- A heavyweight landing / slam at `position`: every nearby client gets the ground
-- shockwave, dust, flying debris and a camera jolt scaled by distance (EffectsController
-- "Slam"). `power` ~1 for a slam, more for bigger.
function Context:SlamFX(position: Vector3, radius: number, power: number?)
	Net.FireNearby(BossService.WorldFX, position, Config.Performance.EffectRadius + radius, "Slam", { Position = position, Radius = radius, Power = power or 1 })
end

-- Physically leaps the boss so it lands at `landing` (on the arena floor) after `airTime`
-- seconds: a real ballistic jump under the place's gravity, not a teleport.
function Context:Leap(landing: Vector3, airTime: number)
	local root, humanoid = self.Root, self.Humanoid
	if root.Anchored or self.Model:GetAttribute("Ragdolled") then
		return
	end
	local standY = self.Arena.GroundY + humanoid.HipHeight + root.Size.Y / 2
	local from = root.Position
	local offset = Vector3.new(landing.X - from.X, standY - from.Y, landing.Z - from.Z)
	local gravity = Workspace.Gravity
	local velocity = Vector3.new(offset.X / airTime, (offset.Y + 0.5 * gravity * airTime * airTime) / airTime, offset.Z / airTime)
	-- The flight is the same ballistic arc (gravity, apex ~6 studs) but driven frame by
	-- frame on an anchored body rather than by free physics: clients draw free-physics
	-- bodies ~0.3 s behind (Roblox's interpolation), which put the fists-into-the-floor
	-- frame of the animation in mid-air on screen. Anchored CFrames arrive as fast as the
	-- attack's own signal, so body, animation and impact land together for everyone.
	local start, facing = from, root.CFrame.Rotation
	root.Anchored = true
	local began = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.min(os.clock() - began, airTime)
		local position = start + Vector3.new(velocity.X * t, velocity.Y * t - 0.5 * gravity * t * t, velocity.Z * t)
		if root.Parent then
			root.CFrame = CFrame.new(position) * facing
		end
		if t >= airTime then
			connection:Disconnect()
			if root.Parent then
				root.Anchored = false
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end)
	-- landing on top of someone: ghosted against players / Nightmares through the flight and
	-- a moment after (as PlaceAt does), so physics can't crush anyone through the floor
	root.CollisionGroup = "BossPhasing"
	self.PhaseToken = (self.PhaseToken or 0) + 1
	local token = self.PhaseToken
	task.delay(airTime + 0.8, function()
		if self.PhaseToken == token and root.Parent then
			root.CollisionGroup = "Enemies"
		end
	end)
end

-- Drives the boss in a straight line along the floor to `to` over `time` (a charge): anchored
-- and moved frame by frame like Leap, ghosted through players on the way.
function Context:Dash(to: Vector3, time: number)
	local root = self.Root
	if root.Anchored or self.Model:GetAttribute("Ragdolled") then
		return
	end
	local standY = self.Arena.GroundY + self.Humanoid.HipHeight + root.Size.Y / 2
	local from = Vector3.new(root.Position.X, standY, root.Position.Z)
	local goal = Vector3.new(to.X, standY, to.Z)
	local facing = (goal - from).Magnitude > 0.1 and CFrame.lookAt(from, goal).Rotation or root.CFrame.Rotation
	root.Anchored = true
	root.CollisionGroup = "BossPhasing"
	self.PhaseToken = (self.PhaseToken or 0) + 1
	local token = self.PhaseToken
	local began = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local k = math.min((os.clock() - began) / time, 1)
		if root.Parent then
			root.CFrame = CFrame.new(from:Lerp(goal, k)) * facing
		end
		if k >= 1 then
			connection:Disconnect()
			if root.Parent then
				root.Anchored = false
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end)
	task.delay(time + 0.6, function()
		if self.PhaseToken == token and root.Parent then
			root.CollisionGroup = "Enemies"
		end
	end)
end

-- A SIGNATURE COMBO: one continuous keyframed clip (BossPoses <action>, its "Hit" marker
-- on the first beat) carrying several telegraphed beats. beats = { { At = clip seconds,
-- Warn = how long before it the warning shows (default: from the beat before),
-- Telegraph = function(ctx, lead) -> data (draw the warning; return whatever Strike
-- needs), Strike = function(ctx, data) } }. Every beat runs on the clip's own clock, scaled
-- by the windup multiplier, so each impact lands on its animation frame. Returns false if
-- the fight ended or the boss was interrupted.
function Context:Combo(action: string, duration: number, beats, recovery: number?): boolean
	local first = beats[1].At
	local windup = self:WindupTime(first)
	local scale = windup / first
	local started = os.clock()
	local function elapsed()
		return os.clock() - started
	end
	-- the first warning goes up with the clip
	local data = {}
	data[1] = beats[1].Telegraph and beats[1].Telegraph(self, windup) or nil
	self:Action(action, windup, duration * scale)
	local previous = 0
	for index, beat in beats do
		local at = beat.At * scale
		if index > 1 then
			local warnAt = beat.Warn and (at - beat.Warn * scale) or previous
			if not self:Wait(math.max(0, warnAt - elapsed())) then
				return false
			end
			data[index] = beat.Telegraph and beat.Telegraph(self, math.max(0.3, at - elapsed())) or nil
		end
		if not self:Wait(math.max(0, at - elapsed())) then
			return false
		end
		beat.Strike(self, data[index])
		if RunService:IsStudio() and Config.Dev.LogNightmareCombos then
			print(("[BossCombo] %s beat %d @%.2f s (its frame: %.2f s)"):format(action, index, elapsed(), at))
		end
		previous = at
	end
	if not self:Wait(math.max(0, duration * scale - elapsed())) then
		return false
	end
	return self:Wait(recovery or 1.2)
end

function Context:Projectile(from: Vector3, to: Vector3, duration: number)
	BossService.Services.TelegraphService:Projectile(from, to, duration)
end

local function damage(self, targets, amount: number, opts)
	opts = opts or {}
	local combat = BossService.Services.CombatService
	for _, target in targets do
		-- a slam throws everyone OUTWARD from where it landed (not just away from the boss)
		local hitDirection
		if typeof(opts.Radial) == "Vector3" then
			local p = target:GetPivot().Position
			hitDirection = Util.FlatUnit(p - opts.Radial) or Util.FlatUnit(p - self.Root.Position)
		end
		combat:ApplyDamage({
			Attacker = self.Model,
			Target = target,
			BaseDamage = amount * self.ModeConfig.DamageMultiplier,
			AttackPower = 100,
			Knockback = opts.Knockback,
			Heavy = opts.Heavy,
			React = opts.Heavy and "Heavy" or "Cross", -- (a Nightmare takes it: NightmarePoses Reactions)
			HitDirection = hitDirection,
			Unblockable = opts.Unblockable,
			Status = opts.Status, -- e.g. "Shock" (Storm Beast), "Weaken" (Abyssal Maw)
			Ground = opts.Ground, -- comes up out of the floor (a hovering Nightmare is above it)
			Source = "Boss:" .. self.Definition.Id,
		})
	end
end

-- Flat circle on the floor (a cylinder, not a sphere: tall characters can't dodge by height).
function Context:DamageCircle(position: Vector3, radius: number, amount: number, opts)
	local hits = {}
	for _, target in self:Targets() do
		local root = target:FindFirstChild("HumanoidRootPart")
		if root then
			local reach = radius + math.max(root.Size.X, root.Size.Z) / 2
			if Util.FlatDistance(root.Position, position) <= reach and math.abs(root.Position.Y - position.Y) < 20 then
				table.insert(hits, target)
			end
		end
	end
	damage(self, hits, amount, opts)
end

function Context:DamageBox(cframe: CFrame, size: Vector3, amount: number, opts)
	local tall = cframe * CFrame.new(0, 6, 0)
	local hits = BossService.Services.HitDetectionService:QueryBox(tall, Vector3.new(size.X, 14, size.Z), { self.Model })
	damage(self, hits, amount, opts)
end

-- Several circles at once; a target standing in two of them is only hit ONCE.
function Context:DamageCircles(positions: { Vector3 }, radius: number, amount: number, opts)
	local hits = {}
	for _, target in self:Targets() do
		local root = target:FindFirstChild("HumanoidRootPart")
		if root then
			local reach = radius + math.max(root.Size.X, root.Size.Z) / 2
			for _, position in positions do
				if Util.FlatDistance(root.Position, position) <= reach and math.abs(root.Position.Y - position.Y) < 20 then
					table.insert(hits, target)
					break
				end
			end
		end
	end
	damage(self, hits, amount, opts)
end

-- Several boxes at once (CFrame, Size pairs); each target is hit at most ONCE.
function Context:DamageBoxes(boxes: { { CFrame: CFrame, Size: Vector3 } }, amount: number, opts)
	local seen, hits = {}, {}
	for _, box in boxes do
		local tall = box.CFrame * CFrame.new(0, 6, 0)
		for _, target in BossService.Services.HitDetectionService:QueryBox(tall, Vector3.new(box.Size.X, 14, box.Size.Z), { self.Model }) do
			if not seen[target] then
				seen[target] = true
				table.insert(hits, target)
			end
		end
	end
	damage(self, hits, amount, opts)
end

-- Moves the boss so it stands on the arena floor at `position`, facing `facing` (for
-- pounces, eruptions...). Keeps its height above the floor.
function Context:PlaceAt(position: Vector3, facing: Vector3?)
	local ground = self:ClampToArena(position)
	local height = self.Humanoid.HipHeight + self.Root.Size.Y / 2
	local at = Vector3.new(ground.X, self.Arena.GroundY + height, ground.Z)
	local look = facing and Vector3.new(facing.X, at.Y, facing.Z) or (at + self.Root.CFrame.LookVector)
	if (look - at).Magnitude < 0.1 then
		look = at + self.Root.CFrame.LookVector
	end
	-- Landing on top of someone: ghost the boss for players / Nightmares for a moment, so
	-- the physics engine can't shove anyone through the floor while the knockback throws
	-- them clear.
	local root = self.Root
	root.CollisionGroup = "BossPhasing"
	self.PhaseToken = (self.PhaseToken or 0) + 1
	local token = self.PhaseToken
	task.delay(1.2, function()
		if self.PhaseToken == token and root.Parent then
			root.CollisionGroup = "Enemies"
		end
	end)
	self.Model:PivotTo(CFrame.lookAt(at, look))
	root.AssemblyLinearVelocity = Vector3.zero
end

-- The point mirrored through the arena centre (rotated by `degrees`, default 180).
function Context:Reflect(position: Vector3, degrees: number?): Vector3
	local center = self.Arena.Center
	local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local rotated = CFrame.Angles(0, math.rad(degrees or 180), 0):VectorToWorldSpace(offset)
	return Vector3.new(center.X + rotated.X, self.Arena.GroundY, center.Z + rotated.Z)
end

-- Pulls every target within radius toward the boss.
function Context:Pull(radius: number, strength: number)
	local playerFX = BossService.PlayerFX
	local origin = self.Root.Position
	for _, target in self:Targets() do
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and Util.FlatDistance(root.Position, origin) <= radius then
			local toward = Util.FlatUnit(origin - root.Position)
			if toward then
				local velocity = toward * strength + Vector3.new(0, 10, 0)
				local player = Players:GetPlayerFromCharacter(target)
				if player then
					playerFX:FireClient(player, "Impulse", { Velocity = velocity, Duration = 0.35 })
				elseif not root.Anchored then
					root:ApplyImpulse(velocity * root.AssemblyMass)
				end
			end
		end
	end
end

-- Shoves every target along `direction` (arena hazards: wind gusts...).
function Context:Push(direction: Vector3, strength: number)
	local flat = Util.FlatUnit(direction)
	if not flat then
		return
	end
	local velocity = flat * strength + Vector3.new(0, 12, 0)
	for _, target in self:Targets() do
		local root = target:FindFirstChild("HumanoidRootPart")
		if root then
			local player = Players:GetPlayerFromCharacter(target)
			if player then
				BossService.PlayerFX:FireClient(player, "Impulse", { Velocity = velocity, Duration = 0.45 })
			elseif not root.Anchored then
				root:ApplyImpulse(velocity * root.AssemblyMass)
			end
		end
	end
end

function Context:Banner(title: string, subtitle: string?)
	for _, player in self.Encounter.Players do
		BossService.BossEvent:FireClient(player, "Phase", { Title = title, Subtitle = subtitle })
	end
end

------------------------------------------------------------------------------------------
-- Targeting
------------------------------------------------------------------------------------------
function BossService:GetTargets(enc): { Model }
	local list = {}
	for _, player in enc.Players do
		if not enc.InArena[player] then
			continue -- waiting to come back or out: the boss ignores them (and their Nightmare)
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			table.insert(list, character)
		end
		local nightmare = self.Services.NightmareSpawnService:GetNightmare(player)
		local nmHumanoid = nightmare and nightmare:FindFirstChildOfClass("Humanoid")
		if nmHumanoid and nmHumanoid.Health > 0 then
			table.insert(list, nightmare)
		end
	end
	return list
end

-- Highest threat wins, with periodic random switches so nobody is targeted forever.
function BossService:PickTarget(brain, now: number, forceRandom: boolean?): Model?
	local targets = self:GetTargets(brain.Encounter)
	if #targets == 0 then
		return nil
	end
	if forceRandom or now >= brain.NextSwitch then
		brain.NextSwitch = now + brain.Random:NextNumber(Config.Bosses.TargetSwitchInterval[1], Config.Bosses.TargetSwitchInterval[2])
		brain.Target = targets[brain.Random:NextInteger(1, #targets)]
		return brain.Target
	end
	if brain.Target and table.find(targets, brain.Target) then
		return brain.Target
	end
	local best, bestScore = nil, -math.huge
	for _, target in targets do
		local score = (brain.Threat[target] or 0) + 1
		if CollectionService:HasTag(target, "Nightmare") then
			score *= Config.Bosses.ThreatNightmareBias
		end
		if score > bestScore then
			best, bestScore = target, score
		end
	end
	brain.Target = best
	return best
end

------------------------------------------------------------------------------------------
-- Boss brain tick
------------------------------------------------------------------------------------------
-- Safety net for every arena: a Handler or Nightmare that ends up below the floor
-- (physics glitch, knockback off an edge...) is put back at the arena entrance.
local FALL_LIMIT = 12 -- studs below the floor
function BossService:RescueFallen(enc)
	local floor = enc.Arena.GroundY - FALL_LIMIT
	local spawnCF = enc.Arena.PlayerSpawn
	for _, player in enc.Players do
		if enc.InArena[player] then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root.Position.Y < floor then
				character:PivotTo(spawnCF)
				root.AssemblyLinearVelocity = Vector3.zero
				self.Services.NightmareSpawnService:TeleportNightmare(player, spawnCF * CFrame.new(5, 0, 4))
			else
				local nightmare = self.Services.NightmareSpawnService:GetNightmare(player)
				local nightmareRoot = nightmare and nightmare:FindFirstChild("HumanoidRootPart")
				if nightmareRoot and nightmareRoot.Position.Y < floor and root then
					self.Services.NightmareSpawnService:TeleportNightmare(player, root.CFrame * CFrame.new(5, 0, 4))
				end
			end
		end
	end
end

function BossService:Tick(brain, now: number)
	local enc = brain.Encounter
	local ctx = brain.Context
	if enc.State ~= "Fighting" or brain.Humanoid.Health <= 0 then
		return
	end

	self:RescueFallen(enc)

	-- Phase transitions at health thresholds (never heals).
	local thresholds = ctx.ModeConfig.PhaseThresholds or brain.Definition.PhaseThresholds
	local nextThreshold = thresholds[brain.Phase]
	if ctx.ModeConfig.Overdrive and nextThreshold and brain.Humanoid.Health / brain.Humanoid.MaxHealth <= nextThreshold and brain.State == "Chase" then
		brain.Phase += 1
		brain.Model:SetAttribute("Phase", brain.Phase)
		ctx.Overdrive = true
		brain.State = "PhaseTransition"
		task.spawn(function()
			local ok, err = pcall(brain.Behaviour.OnPhase, ctx, brain.Phase)
			if not ok then
				warn("[BossService] OnPhase failed:", err)
			end
			brain.State = "Chase"
			brain.NextAttackAt = os.clock() + 0.5
		end)
		return
	end

	if brain.State ~= "Chase" then
		return
	end
	if self.Services.StatusService:IsStaggered(brain.Model) or brain.Model:GetAttribute("Ragdolled") then
		if not brain.Model:GetAttribute("Ragdolled") then
			ctx:Stop()
		end
		-- (after a knockdown it gets its bearings before swinging again)
		brain.NextAttackAt = math.max(brain.NextAttackAt, now + (brain.Model:GetAttribute("Ragdolled") and 1.2 or 0.6))
		return
	end
	brain.Humanoid.WalkSpeed = (ctx.Overdrive and brain.Definition.WalkSpeed * 1.35 or brain.Definition.WalkSpeed) * self.Services.StatusService:SpeedMultiplier(brain.Model)

	local target = self:PickTarget(brain, now)
	if not target then
		ctx:Stop()
		return
	end
	local targetPosition = ctx:Position(target)
	local distance = Util.FlatDistance(brain.Root.Position, targetPosition)

	if now >= brain.NextAttackAt then
		local name, attack = brain.Behaviour.ChooseAttack(ctx, distance)
		ctx.LastAttack = name
		brain.State = "Attacking"
		ctx:Stop()
		task.spawn(function()
			local ok, err = pcall(attack.Run, ctx, target)
			if not ok then
				warn(("[BossService] attack %s failed: %s"):format(name, tostring(err)))
			end
			brain.State = "Chase"
			-- the rhythm: sometimes straight into the next attack (a chain); otherwise, or at
			-- the end of a chain, it's EXPOSED for a moment: the punish window
			local bosses = Config.Bosses
			local chainChance = ctx.Overdrive and bosses.Chain.OverdriveChance or bosses.Chain.Chance
			if ok and ctx:Alive() and (brain.ChainCount or 0) < bosses.Chain.Max and brain.Random:NextNumber() < chainChance then
				brain.ChainCount = (brain.ChainCount or 0) + 1
				brain.NextAttackAt = os.clock() + bosses.Chain.Delay
				return
			end
			brain.ChainCount = 0
			local exposed = ctx.Overdrive and bosses.Exposed.OverdriveTime or bosses.Exposed.Time
			if ctx:Alive() then
				brain.Model:SetAttribute("ExposedUntil", Workspace:GetServerTimeNow() + exposed)
			end
			local delay = ctx.Overdrive and bosses.OverdriveAttackDelay or bosses.AttackDelay
			-- (it doesn't swing again before the window closes)
			brain.NextAttackAt = os.clock() + math.max(delay * (ctx.ModeConfig.AttackDelayMultiplier or 1), exposed)
		end)
		return
	end

	if distance > brain.Behaviour.PreferredRange then
		brain.Humanoid:MoveTo(targetPosition)
	else
		ctx:Stop()
		ctx:Face(targetPosition)
	end
end

------------------------------------------------------------------------------------------
-- Encounters
------------------------------------------------------------------------------------------
-- Slots are per arena type: slot 1 is the arena at the end of the boss's route; while
-- it's busy, more groups get identical copies far away.
local function reserveSlot(arenaType: string): number?
	slotInUse[arenaType] = slotInUse[arenaType] or {}
	for slot = 1, Config.Bosses.MaxArenas do
		if not slotInUse[arenaType][slot] then
			slotInUse[arenaType][slot] = true
			return slot
		end
	end
	return nil
end

local function arenaOrigin(arenaType: string, slot: number): CFrame
	local typeInfo = ArenaBuilder.Types[arenaType]
	if slot == 1 then
		return WorldDefinitions.Regions[typeInfo.Region].Arena
	end
	local spacing = Config.Bosses.ArenaSpacing
	local center = Config.Bosses.ArenaOrigin + Vector3.new((slot - 2) * spacing, 0, typeInfo.Row * spacing)
	return CFrame.lookAt(center, center - Vector3.zAxis)
end

function BossService:GetArena(arenaType: string, slot: number)
	local key = arenaType .. slot
	if not arenas[key] then
		arenas[key] = ArenaBuilder.Types[arenaType].Build(arenaOrigin(arenaType, slot), key, slot == 1)
	end
	return arenas[key]
end

-- A dormant, anchored copy of the boss standing in its world arena between fights, so
-- players see who rules the place before they challenge it.
function BossService:ShowDisplay(arenaType: string)
	if displays[arenaType] then
		return
	end
	for _, bossId in BossDefinitions.Order do
		local def = BossDefinitions.Get(bossId)
		if def and (def.Arena or "Junkyard") == arenaType then
			local arena = self:GetArena(arenaType, 1)
			local ok, model = pcall(function()
				local m = behaviourFor(def.Id).BuildModel(arena.BossSpawn, def.HitboxSize)
				return m
			end)
			if ok and model then
				model.Name = def.Id .. "_Dormant"
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
					end
				end
				model:SetAttribute("Dormant", true)
				model.Parent = arena.Folder
				displays[arenaType] = model
			end
			return
		end
	end
end

-- A stone monument of each boss beside its gate in the Forge: you can see from the hub
-- which path leads to which boss. Glowing parts keep the region's colour.
function BossService:BuildMonuments()
	local hub = Workspace:FindFirstChild("NightmareForgeHub")
	if not hub then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "BossMonuments"
	folder.Parent = hub
	for _, bossId in BossDefinitions.Order do
		local def = BossDefinitions.Get(bossId)
		local regionId = WorldDefinitions.BossRegion[bossId]
		local region = regionId and WorldDefinitions.Regions[regionId]
		if def and region then
			local dir = region.Direction
			local gatePos = WorldDefinitions.HubCenter + dir * (WorldDefinitions.HubRadius - 4)
			local gate = CFrame.lookAt(gatePos, gatePos + dir)
			local base = gate * CFrame.new(28, 0, 18) -- inside the gate, to the right of the path
			local pedestalTop = base.Position + Vector3.new(0, 4, 0)
			local pedestal = Instance.new("Part")
			pedestal.Name = "MonumentPedestal"
			pedestal.Anchored = true
			pedestal.Size = Vector3.new(16, 4, 16)
			pedestal.CFrame = CFrame.new(base.Position + Vector3.new(0, 2, 0))
			pedestal.Color = Color3.fromRGB(70, 64, 84)
			pedestal.Material = Enum.Material.Slate
			pedestal.Parent = folder
			local trim = pedestal:Clone()
			trim.Name = "MonumentTrim"
			trim.Size = Vector3.new(16.4, 0.4, 16.4)
			trim.CFrame = CFrame.new(pedestalTop - Vector3.new(0, 0.3, 0))
			trim.Color = region.Color:Lerp(Color3.new(0, 0, 0), WorldDefinitions.HubNeonDim)
			trim.Material = Enum.Material.Neon
			trim.CanCollide = false
			trim.Parent = folder
			local ok, model = pcall(function()
				local faceHub = CFrame.lookAt(pedestalTop, Vector3.new(WorldDefinitions.HubCenter.X, pedestalTop.Y, WorldDefinitions.HubCenter.Z))
				return (behaviourFor(bossId).BuildModel(faceHub, def.HitboxSize))
			end)
			if ok and model then
				model.Name = bossId .. "_Monument"
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						if d.Material == Enum.Material.Neon then
							d.Color = region.Color:Lerp(Color3.new(0, 0, 0), WorldDefinitions.HubNeonDim)
						else
							d.Material = Enum.Material.Slate
							d.Color = Color3.fromRGB(118, 112, 128)
						end
					elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
						d.Enabled = false
					end
				end
				model.Parent = folder
			end
		end
	end
end

function BossService:HideDisplay(arenaType: string)
	if displays[arenaType] then
		displays[arenaType]:Destroy()
		displays[arenaType] = nil
	end
end

-- Arena hazards (ArenaBuilder) fire on a timer while the fight lasts. None in the
-- tutorial; more often on harder difficulties and once the boss is in overdrive.
local HAZARD_PACE = { Normal = 1.3, Hard = 1.0, Nightmare = 0.8 }
function BossService:RunHazards(enc)
	local hazards = enc.Arena.Hazards
	local pace = HAZARD_PACE[enc.Mode]
	if not hazards or #hazards == 0 or not pace then
		return
	end
	task.spawn(function()
		local index = math.random(1, #hazards)
		task.wait(6 * pace)
		while enc.State == "Fighting" do
			local ctx = enc.Brain and enc.Brain.Context
			if ctx then
				local hazard = hazards[index]
				index = index % #hazards + 1
				if RunService:IsStudio() then
					print(("[BossService] arena hazard: %s"):format(hazard.Name))
				end
				local ok, err = pcall(hazard.Run, ctx, enc.Arena)
				if not ok then
					warn(("[BossService] hazard %s failed: %s"):format(hazard.Name, tostring(err)))
				end
			end
			local overdrive = ctx and ctx.Overdrive
			task.wait((overdrive and 6.5 or 8.5) * pace * (0.85 + math.random() * 0.3))
		end
	end)
end

function BossService:GetEncounter(player: Player)
	return playerEncounter[player]
end

function BossService:SpawnBoss(enc)
	local definition = BossDefinitions.Get(enc.BossId)
	local behaviour = behaviourFor(enc.BossId)
	local modeConfig = definition.Modes[enc.Mode]

	local model, hipHeight = behaviour.BuildModel(enc.Arena.BossSpawn, definition.HitboxSize)
	local scaling = Config.Bosses.HealthScaling[math.clamp(#enc.Players, 1, #Config.Bosses.HealthScaling)]
	local maxHealth = math.floor(definition.MaxHealth * modeConfig.HealthMultiplier * scaling)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = definition.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated } do
		humanoid:SetStateEnabled(state, false)
	end

	model:SetAttribute("DisplayName", definition.DisplayName)
	model:SetAttribute("BossId", definition.Id)
	model:SetAttribute("EncounterId", enc.Id)
	model:SetAttribute("Defence", definition.Defence)
	model:SetAttribute("Phase", 1)
	model:SetAttribute("KnockbackImmune", true)
	model:SetAttribute("StaggerMax", math.floor((definition.StaggerMax or 300) * modeConfig.HealthMultiplier ^ 0.5))
	model:SetAttribute("Stagger", 0)
	model:SetAttribute("ActionSeq", 0)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Enemies"
		end
	end
	CollectionService:AddTag(model, "Enemy")
	CollectionService:AddTag(model, "Boss")
	model.Parent = Workspace:FindFirstChild("Enemies") or Workspace
	pcall(function()
		model.PrimaryPart:SetNetworkOwner(nil)
	end)

	local brain = {
		Encounter = enc,
		Model = model,
		Humanoid = humanoid,
		Root = model.PrimaryPart,
		Definition = definition,
		Behaviour = behaviour,
		State = "Chase",
		Phase = 1,
		NextAttackAt = os.clock() + 1.5,
		Threat = {},
		Target = nil,
		NextSwitch = os.clock() + 10,
		Random = Random.new(),
	}
	local ctx = setmetatable({
		Encounter = enc,
		Brain = brain,
		Model = model,
		Humanoid = humanoid,
		Root = brain.Root,
		Arena = enc.Arena,
		Definition = definition,
		ModeConfig = modeConfig,
		Overdrive = false,
		LastAttack = nil,
		Random = brain.Random,
	}, Context)
	brain.Context = ctx
	enc.Brain = brain
	model:SetAttribute("Mode", enc.Mode)
	if behaviour.OnSpawn then
		local ok, err = pcall(behaviour.OnSpawn, ctx)
		if not ok then
			warn("[BossService] OnSpawn failed:", err)
		end
	end

	humanoid.Died:Connect(function()
		model:SetAttribute("Defeated", true)
		self:Victory(enc)
	end)
end

function BossService:StartEncounter(player: Player, bossId: string, requestedMode: string?)
	if playerEncounter[player] then
		return { Ok = false, Error = "You're already in a boss fight." }
	end
	if self.Services.DuelService:IsInMatch(player) then
		return { Ok = false, Error = "Finish your duel first." }
	end
	local definition = BossDefinitions.Get(bossId)
	if not definition then
		return { Ok = false, Error = "Unknown boss." }
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return { Ok = false, Error = "You need to be alive to enter." }
	end
	-- Parties: only the leader starts; every available member comes along.
	local party = self.Services.PartyService:GetParty(player)
	if party and party.Leader ~= player then
		return { Ok = false, Error = "Only the party leader can start a boss fight." }
	end
	local profile = self.Services.PlayerDataService:Get(player)
	local bossUnlocked, lockReason = BossDefinitions.IsBossUnlocked(profile and profile.Bosses, bossId)
	if not bossUnlocked then
		return { Ok = false, Error = lockReason }
	end
	local mode, reason = self.Services.TutorialService:BossModeFor(player)
	if not mode then
		return { Ok = false, Error = reason }
	end
	if mode == "Tutorial" and not definition.Modes.Tutorial then
		return { Ok = false, Error = "Finish your training first." }
	end
	-- Past the tutorial, the player picks a difficulty (default Normal).
	if mode == "Normal" and requestedMode and requestedMode ~= "Normal" then
		local unlocked, why = BossDefinitions.IsModeUnlocked(profile and profile.Bosses, bossId, requestedMode)
		if not unlocked then
			return { Ok = false, Error = why }
		end
		mode = requestedMode
	end
	if not definition.Modes[mode] then
		return { Ok = false, Error = "That difficulty isn't available yet." }
	end
	-- One arena per (arena type, slot), built on first use and reused.
	local arenaType = ArenaBuilder.Types[definition.Arena or "Junkyard"] and (definition.Arena or "Junkyard") or "Junkyard"
	local slot = reserveSlot(arenaType)
	if not slot then
		return { Ok = false, Error = "All arenas are busy. Try again in a moment." }
	end
	local arenaOk, arenaInfo = pcall(self.GetArena, self, arenaType, slot)
	if not arenaOk then
		slotInUse[arenaType][slot] = nil
		warn("[BossService] arena build failed:", arenaInfo)
		return { Ok = false, Error = "The arena couldn't be prepared. Try again." }
	end
	local arenaKey = arenaType .. slot
	if slot == 1 then
		self:HideDisplay(arenaType)
	end

	-- Who goes in: the starter + every party member who is free right now.
	local participants = { player }
	for _, member in party and party.Members or {} do
		if member ~= player then
			local free, why = self:CanJoin(member)
			if free then
				table.insert(participants, member)
			else
				self.Services.PartyService.PartyEvent:FireClient(member, "Result", { Text = ("You couldn't join the boss fight: %s."):format(why) })
			end
		end
	end

	local enc = {
		Id = HttpService:GenerateGUID(false),
		BossId = bossId,
		Mode = mode,
		Slot = slot,
		ArenaType = arenaType,
		Arena = arenas[arenaKey],
		Players = participants,
		State = "Intro",
		StartTime = 0,
		Rewarded = {},
		Connections = {},
		-- Comebacks (Config.Party.Revives): who is fighting in the arena right now, who is
		-- waiting to come back (seconds), and who is out for the rest of the fight.
		InArena = {},
		PendingRejoin = {},
		Out = {},
		RevivesLeft = 0,
		RevivesUsed = 0,
	}
	local revives = Config.Party.Revives[mode]
	enc.RevivesLeft = revives == "PartySize" and #participants or (revives or 0)
	encounters[enc.Id] = enc

	for index, participant in participants do
		playerEncounter[participant] = enc
		enc.InArena[participant] = true
		local pCharacter = participant.Character
		local pHumanoid = pCharacter and pCharacter:FindFirstChildOfClass("Humanoid")
		if pHumanoid then
			table.insert(enc.Connections, pHumanoid.Died:Connect(function()
				self:OnHandlerDown(enc, participant)
			end))
		end
		-- Teleport in side by side (server can move the character; the Nightmare follows).
		local spawnCF = enc.Arena.PlayerSpawn * CFrame.new((index - (#participants + 1) / 2) * 7, 0, 0)
		if pCharacter then
			pCharacter:PivotTo(spawnCF)
		end
		self.Services.NightmareSpawnService:TeleportNightmare(participant, spawnCF * CFrame.new(5, 0, 4))
		self.BossEvent:FireClient(participant, "Start", {
			BossId = bossId,
			Name = definition.DisplayName,
			Title = definition.Title,
			Mode = mode,
			PartySize = #participants,
			Revives = #participants > 1 and enc.RevivesLeft or nil, -- solo: no comebacks to show
			IntroDelay = Config.Bosses.IntroDelay,
			-- for the client's intro camera
			ArenaCenter = enc.Arena.Center,
			BossPosition = enc.Arena.BossSpawn.Position,
			Region = ArenaBuilder.Types[arenaType].Region,
		})
	end

	task.delay(Config.Bosses.IntroDelay, function()
		if enc.State ~= "Intro" then
			return
		end
		self:SpawnBoss(enc)
		enc.State = "Fighting"
		enc.StartTime = os.clock()
		if enc.Mode ~= "Tutorial" then
			self:RunHazards(enc)
		end
	end)

	return { Ok = true, Mode = mode, PartySize = #participants }
end

-- Can this party member be pulled into a fight right now? ok, reason
function BossService:CanJoin(player: Player): (boolean, string?)
	if playerEncounter[player] then
		return false, "you're already in a boss fight"
	end
	if self.Services.DuelService:IsInMatch(player) then
		return false, "you're in a duel"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "you were knocked out"
	end
	return true, nil
end

-- A knocked-out member respawns at the Forge (Roblox). If a comeback was reserved for
-- them, wait the extra delay and put them back in the arena; otherwise they stay out.
function BossService:OnCharacterAdded(player: Player, character: Model)
	local enc = playerEncounter[player]
	local delay = enc and enc.PendingRejoin[player]
	if not delay or (enc.State ~= "Fighting" and enc.State ~= "Intro") then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	task.wait(delay)
	if playerEncounter[player] ~= enc or enc.PendingRejoin[player] == nil or (enc.State ~= "Fighting" and enc.State ~= "Intro") then
		return
	end
	enc.PendingRejoin[player] = nil
	enc.InArena[player] = true
	local spawnCF = enc.Arena.PlayerSpawn
	character:PivotTo(spawnCF)
	self.Services.NightmareSpawnService:TeleportNightmare(player, spawnCF * CFrame.new(5, 0, 4))
	table.insert(enc.Connections, humanoid.Died:Connect(function()
		self:OnHandlerDown(enc, player)
	end))
	for _, member in enc.Players do
		self.BossEvent:FireClient(member, "Revives", { Left = enc.RevivesLeft, Text = player.DisplayName .. " is back in the fight!" })
	end
end

-- Is any participant alive AND in the arena? (Waiting to come back / out don't count.)
function BossService:AnyoneStanding(enc): boolean
	for _, member in enc.Players do
		local character = member.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if enc.InArena[member] and humanoid and humanoid.Health > 0 then
			return true
		end
	end
	return false
end

-- A Handler in the arena was knocked out. The fight fails when nobody is left standing
-- IN THE ARENA (players waiting to come back, or already out, don't count). Otherwise a
-- comeback is reserved for them if the pool allows (Config.Party.Revives), or they're
-- out for the rest of the fight (but still rewarded if the party wins).
function BossService:OnHandlerDown(enc, player: Player)
	if enc.State ~= "Fighting" and enc.State ~= "Intro" then
		return
	end
	enc.InArena[player] = nil
	if not self:AnyoneStanding(enc) then
		self:Fail(enc, "KnockedOut")
		return
	end

	local rejoinIn
	if enc.RevivesLeft > 0 then
		enc.RevivesLeft -= 1
		enc.RevivesUsed += 1
		local delays = Config.Party.RejoinDelays
		enc.PendingRejoin[player] = delays[math.min(enc.RevivesUsed, #delays)]
		rejoinIn = Players.RespawnTime + enc.PendingRejoin[player]
	else
		enc.Out[player] = true
	end
	for _, member in enc.Players do
		self.BossEvent:FireClient(member, "Revives", {
			Left = enc.RevivesLeft,
			Text = rejoinIn and ("%s is down! Back in %ds."):format(player.DisplayName, math.floor(rejoinIn + 0.5))
				or ("%s is out of the fight!"):format(player.DisplayName),
		})
	end
	self.BossEvent:FireClient(player, "Down", { RejoinIn = rejoinIn })
end

function BossService:Fail(enc, reason: string)
	if enc.State == "Failed" or enc.State == "Victory" or enc.State == "Closed" then
		return
	end
	enc.State = "Failed"
	local fightTime = enc.StartTime > 0 and math.floor(os.clock() - enc.StartTime) or 0
	for _, player in enc.Players do
		if player.Parent then
			self.BossEvent:FireClient(player, "End", { Result = "Failed", Reason = reason })
			self.Services.GameAnalyticsService:Event(player, "BossFail", fightTime, { enc.BossId, enc.Mode, #enc.Players })
		end
	end
	task.delay(reason == "KnockedOut" and 3 or 0, function()
		for _, player in table.clone(enc.Players) do
			if reason ~= "KnockedOut" then
				self:ReturnToHub(player, enc)
			end
			playerEncounter[player] = nil
		end
		self:Close(enc)
	end)
end

function BossService:Victory(enc)
	if enc.State ~= "Fighting" then
		return
	end
	enc.State = "Victory"
	local fightTime = os.clock() - enc.StartTime

	for _, player in enc.Players do
		if player.Parent and not enc.Rewarded[player] then
			enc.Rewarded[player] = true -- set BEFORE granting: no double rewards, ever
			local summary = self.Services.BossRewardService:GrantVictory(player, enc.BossId, enc.Mode, fightTime)
			if enc.Mode ~= "Tutorial" then
				self.Services.ChallengeService:Notify(player, "BossWin", 1, { BossId = enc.BossId, Mode = enc.Mode })
			end
			self.BossEvent:FireClient(player, "End", { Result = "Victory", Time = math.floor(fightTime + 0.5) })
			self.Services.GameAnalyticsService:Event(player, "BossWin", math.floor(fightTime + 0.5), { enc.BossId, enc.Mode, #enc.Players })
			if summary then
				self.RewardNotification:FireClient(player, summary)
				if enc.Mode == "Tutorial" and summary.Parts[1] then
					self.Services.TutorialService:Notify(player, "TutorialBossWon", { PartId = summary.Parts[1].Id })
				end
			end
		end
	end

	task.delay(Config.Bosses.VictoryReturnTimeout, function()
		if enc.State == "Victory" then
			for _, player in table.clone(enc.Players) do
				self:ReturnToHub(player, enc)
				playerEncounter[player] = nil
			end
			self:Close(enc)
		end
	end)
end

function BossService:Close(enc)
	if enc.State == "Closed" then
		return
	end
	enc.State = "Closed"
	for _, connection in enc.Connections do
		connection:Disconnect()
	end
	if enc.Brain and enc.Brain.Model then
		local model = enc.Brain.Model
		task.delay(2, function()
			model:Destroy()
		end)
	end
	encounters[enc.Id] = nil
	if slotInUse[enc.ArenaType] then
		slotInUse[enc.ArenaType][enc.Slot] = nil
	end
	if enc.Slot == 1 then
		task.delay(2.5, function()
			if not (slotInUse[enc.ArenaType] and slotInUse[enc.ArenaType][1]) then
				pcall(self.ShowDisplay, self, enc.ArenaType)
			end
		end)
	end
end

-- After a fight players come back out at the arena's gate plaza (the waystone there
-- takes them home); without an arena, to the Forge spawn.
function BossService:ReturnToHub(player: Player, enc)
	local character = player.Character
	if character and character.Parent then
		local cframe = (enc and enc.Arena and enc.Arena.ReturnCFrame) or CFrame.new(Config.World.HubSpawn)
		character:PivotTo(cframe)
		self.Services.NightmareSpawnService:TeleportNightmare(player, cframe * CFrame.new(5, 0, 4))
	end
end

-- Remove one player from their encounter (leave button / disconnect / return).
function BossService:Leave(player: Player, teleport: boolean)
	local enc = playerEncounter[player]
	if not enc then
		return
	end
	playerEncounter[player] = nil
	local index = table.find(enc.Players, player)
	if index then
		table.remove(enc.Players, index)
	end
	enc.InArena[player] = nil
	enc.PendingRejoin[player] = nil
	enc.Out[player] = nil
	if teleport then
		self:ReturnToHub(player, enc)
	end
	if #enc.Players == 0 then
		if enc.State == "Fighting" or enc.State == "Intro" then
			enc.State = "Failed"
		end
		self:Close(enc)
	elseif enc.State == "Fighting" and not self:AnyoneStanding(enc) then
		-- The last one standing left while the rest were down: the fight is lost.
		self:Fail(enc, "KnockedOut")
	end
end

function BossService:HandleRequest(player: Player, action, arg, arg2)
	if not self.Services.AntiExploitService:Allow(player, "BossRequest") then
		return { Ok = false, Error = "Slow down a little!" }
	end
	if not self.Services.PlayerDataService:Get(player) then
		return { Ok = false, Error = "Your profile is still loading." }
	end

	if action == "Start" then
		if type(arg) ~= "string" then
			return { Ok = false, Error = "Unknown boss." }
		end
		if arg2 ~= nil and not (type(arg2) == "string" and Config.Difficulties[arg2]) then
			return { Ok = false, Error = "Unknown difficulty." }
		end
		return self:StartEncounter(player, arg, arg2)
	elseif action == "Leave" then
		local enc = playerEncounter[player]
		if enc and (enc.State == "Fighting" or enc.State == "Intro") then
			-- Only the one leaving: the rest of the party fights on.
			self.BossEvent:FireClient(player, "End", { Result = "Failed", Reason = "Left" })
			for _, p in enc.Players do
				if p ~= player then
					self.Services.PartyService.PartyEvent:FireClient(p, "Result", { Text = player.DisplayName .. " left the boss fight." })
				end
			end
		end
		self:Leave(player, true)
		return { Ok = true }
	elseif action == "Return" then
		self:Leave(player, true)
		return { Ok = true }
	elseif action == "Replay" then
		local enc = playerEncounter[player]
		local bossId = enc and enc.BossId
		if not enc or enc.State ~= "Victory" then
			return { Ok = false, Error = "Nothing to replay." }
		end
		local mode = Config.Difficulties[enc.Mode] and enc.Mode or nil -- same difficulty again
		local party = self.Services.PartyService:GetParty(player)
		if party and party.Leader ~= player then
			return { Ok = false, Error = "Only the party leader can start the next fight." }
		end
		-- Everyone still in this encounter leaves it first so the party can come along again.
		for _, member in table.clone(enc.Players) do
			self:Leave(member, false)
		end
		return self:StartEncounter(player, bossId, mode)
	end
	return { Ok = false, Error = "Unknown request." }
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function BossService:Init(services)
	self.Services = services
	self.BossEvent = Net.Get("BossEvent")
	self.RewardNotification = Net.Get("RewardNotification")
	self.PlayerFX = Net.Get("PlayerFX")
	self.WorldFX = Net.Get("WorldFX")
end

function BossService:Start()
	Net.Get("BossRequest").OnServerInvoke = function(player, action, arg, arg2)
		return self:HandleRequest(player, action, arg, arg2)
	end

	-- The first arena of every boss stands at the end of its route from the start, with
	-- the boss itself waiting inside.
	for arenaType in ArenaBuilder.Types do
		local ok, err = pcall(function()
			self:GetArena(arenaType, 1)
			self:ShowDisplay(arenaType)
		end)
		if not ok then
			warn(("[BossService] world arena %s failed to build: %s"):format(arenaType, tostring(err)))
		end
	end
	local monumentsOk, monumentsErr = pcall(self.BuildMonuments, self)
	if not monumentsOk then
		warn("[BossService] boss monuments failed:", monumentsErr)
	end

	-- Threat: bosses remember who hurts them.
	self.Services.CombatService:OnDamaged(function(target, attacker, amount)
		if not CollectionService:HasTag(target, "Boss") or not attacker then
			return
		end
		for _, enc in encounters do
			if enc.Brain and enc.Brain.Model == target then
				enc.Brain.Threat[attacker] = (enc.Brain.Threat[attacker] or 0) + amount
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:Leave(player, false)
	end)

	-- Party members knocked out mid-fight are put back in the arena when they respawn.
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(self.OnCharacterAdded, self, player, character)
		end)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end

	local step = 1 / Config.Bosses.AIUpdateRate
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < step then
			return
		end
		accumulated = 0
		local now = os.clock()
		for _, enc in encounters do
			if enc.Brain then
				local ok, err = pcall(self.Tick, self, enc.Brain, now)
				if not ok then
					warn("[BossService] tick failed:", err)
				end
			end
		end
	end)
end

return BossService
