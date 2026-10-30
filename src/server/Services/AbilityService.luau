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

	Every ability really DOES what its animation shows, in step with it (the animation's
	"Hit" frame is the ability's Windup): a bite's jaws lock on and the victim is held in
	them; a charge drives the body through what it runs into; a tentacle hauls its catch up
	and slams it down. Bodies are moved frame by frame while anchored (not by physics
	forces): clients see anchored CFrames as fast as the animation's own start signal, so
	the motion and the animation land together for everyone.
	State-dependent effects (where a charge went, what a magnet locked on to) go out as
	WorldFX "AbilityFX" { Kind = ..., ... } for AbilityEffects on the client.
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

local function radiusOf(model: Model): number
	local root = model:FindFirstChild("HumanoidRootPart")
	return root and math.max(root.Size.X, root.Size.Z) / 2 or 1
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
	elseif def.Type == "Charge" then
		return half + def.Distance * ((def.StopOnHit or def.Blink) and 0.9 or 0.75)
	elseif def.Type == "Pull" then
		return def.Range
	elseif def.Type == "Leap" then
		return def.Leap + half
	elseif def.Type == "Breath" or def.Type == "Glare" then
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

-- STUDIO ONLY (tools/AbilityLab): keep the combat brain off this body (as the Nightmare Gym
-- does), and cast one of its abilities on a chosen target, so a test measures that ability
-- and nothing else.
function AbilityService:DevHoldBrain(player: Player, on: boolean)
	local brain = RunService:IsStudio() and self.Services.NightmareAIService:GetBrain(player)
	if brain then
		brain.scripted = on or nil
		self.Services.NightmareAIService:Stop(brain)
	end
end

function AbilityService:DevCast(player: Player, slot: number, target: Model?)
	local brain = RunService:IsStudio() and self.Services.NightmareAIService:GetBrain(player)
	if brain then
		self:Execute(brain, slot, target)
	end
end

-- The way a blow's force travels, for the victim's reaction (nil = straight away from
-- the attacker):
--   "Grip"       a bite that clamps and tears back: jerked TOWARD the attacker
--   "Sweep"      a claw raking across (right to left for a right arm)
--   "SweepBack"  the backhand, the other way
--   "Up"         a rising blow
--   a Vector3    that world direction
local function directionFor(brain, motion, target: Model, source: string?): Vector3?
	local root = brain.root
	if motion == "Grip" then
		return Util.FlatUnit(root.Position - target:GetPivot().Position)
	elseif motion == "Sweep" or motion == "SweepBack" then
		local across = source == "LeftArm" and root.CFrame.RightVector or -root.CFrame.RightVector
		if motion == "SweepBack" then
			across = -across
		end
		return (across * 0.8 + root.CFrame.LookVector * 0.6).Unit
	elseif motion == "Up" then
		return (root.CFrame.LookVector * 0.55 + Vector3.yAxis * 0.85).Unit
	elseif typeof(motion) == "Vector3" then
		return motion
	end
	return nil
end

-- Damage to each of `targets`. `opts` (all optional):
--   Share        of def.Damage (default all of it)
--   Knockback    (default 15)        Motion   see directionFor
--   Heavy, Launch, Crumple, Thrown, NoKnockdown, NoStatus   (CombatService:ApplyDamage)
--   Stagger      (default def.Stagger or 15, scaled by Share)
--   From         a centre point: each is driven straight away from it (a blast)
local function damageTargets(self, brain, targets, def, opts)
	opts = opts or {}
	local combat = self.Services.CombatService
	local share = opts.Share or 1
	local source = brain.model:GetAttribute("ActionSource")
	for _, target in targets do
		local direction = directionFor(brain, opts.Motion, target, source)
		if opts.From then
			direction = Util.FlatUnit(target:GetPivot().Position - opts.From) or direction
		end
		combat:ApplyDamage({
			Attacker = brain.model,
			Target = target,
			BaseDamage = def.Damage * share,
			AttackPower = brain.stats.AttackPower,
			Knockback = opts.Knockback or 15,
			Stagger = opts.Stagger or (def.Stagger or 15) * math.max(share, 0.35),
			Heavy = opts.Heavy or (share >= 0.5 and def.Heavy == true) or nil,
			Launch = opts.Launch,
			Crumple = opts.Crumple,
			-- (a launch always throws a body the server moves; against a player it stays the
			-- usual knockdown chance, so PvP isn't decided by one trip)
			Thrown = opts.Thrown or (opts.Launch ~= nil and not Players:GetPlayerFromCharacter(target)) or nil,
			NoKnockdown = opts.NoKnockdown,
			Status = (not opts.NoStatus and def.Element) and StatusDefinitions.ByElement[def.Element] or nil,
			HitDirection = direction,
			Source = "Ability:" .. def.DisplayName,
		})
	end
end

local function fireFX(self, position: Vector3, data)
	Net.FireNearby(self.Services.TelegraphService.WorldFX, position, Config.Performance.EffectRadius, "AbilityFX", data)
end

-- The floor's height under `position` (nil over a void), ignoring every character.
local FLOOR_PARAMS = RaycastParams.new()
FLOOR_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
local function floorAt(position: Vector3, ignore): number?
	FLOOR_PARAMS.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), FLOOR_PARAMS)
	return hit and hit.Position.Y or nil
end

local function ignoreList(brain)
	local ignore = { brain.model }
	if brain.owner.Character then
		table.insert(ignore, brain.owner.Character)
	end
	return ignore
end

local function stillValid(brain, castToken: number): boolean
	return brain.castToken == castToken and brain.model.Parent ~= nil and brain.humanoid.Health > 0
end

local function alive(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return model.Parent ~= nil and (not humanoid or humanoid.Health > 0)
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

-- A body small enough to be lifted and shaken in the jaws (not a boss, not a player's
-- own character, nothing much bigger than the biter).
local function canHold(brain, target: Model): boolean
	local root = target:FindFirstChild("HumanoidRootPart")
	if not root or root.Anchored or target:GetAttribute("BossId") or target:GetAttribute("Ragdolled") or target:GetAttribute("Gripped") then
		return false
	end
	if Players:GetPlayerFromCharacter(target) then
		return false
	end
	local mine, theirs = brain.model:GetExtentsSize(), target:GetExtentsSize()
	return math.max(theirs.X, theirs.Y, theirs.Z) <= math.max(mine.X, mine.Y, mine.Z) * 1.4
end

-- THE HOLD (every ability that grabs): each frame the victim's root is set to `place(t)`
-- (t = seconds into the hold), anchored, helpless; the holder is planted unless something
-- else is driving it. After `duration` - or as soon as the cast is cut short, the holder
-- goes down or the victim dies - it's let go and `finish(completed)` runs.
function AbilityService:Hold(brain, castToken: number, victim: Model, duration: number, place, finish, planted: boolean?)
	local root = brain.root
	local victimRoot = victim:FindFirstChild("HumanoidRootPart")
	victim:SetAttribute("Gripped", true)
	local began = os.clock()
	local done = false
	local connection
	local function stop(completed: boolean)
		if done then
			return
		end
		done = true
		connection:Disconnect()
		if victimRoot.Parent then
			victimRoot.Anchored = false
			victimRoot.AssemblyLinearVelocity = Vector3.zero
		end
		if victim.Parent then
			victim:SetAttribute("Gripped", nil)
		end
		if planted ~= false and root.Parent then
			root.Anchored = false
		end
		finish(completed)
	end
	connection = RunService.Heartbeat:Connect(function()
		if not stillValid(brain, castToken) or brain.model:GetAttribute("Ragdolled") or not alive(victim) or not victimRoot.Parent then
			stop(false)
			return
		end
		local t = math.min(os.clock() - began, duration)
		if planted ~= false then
			root.Anchored = true
		end
		victimRoot.Anchored = true
		victimRoot.CFrame = place(t)
		if t >= duration then
			stop(true)
		end
	end)
	return stop
end

-- THE CLAMP (a bite with def.Clamp). The jaws lock on to the nearest body they hit, which
-- takes the first share of the damage (no knockdown: it's held). A body that can be held
-- is locked into the mouth and shaken with the head (in step with the animation), helpless,
-- for Hold seconds; the biter stays planted. Then the head RIPS away: the rest of the damage
-- and a hard throw. Anything else in the bite takes a normal hit.
--   Style "Thrash" (default): swung side to side, Swing degrees, lifting a little each shake
--   Style "Convulse": jolted in small fast random twitches (the Charged Bite's current)
--   Ticks { { seconds after the snap, share }, ... }: extra jolts of damage while held
--   Throw "Left" (default: torn away to the biter's left) or "Forward" (blasted away)
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
		damageTargets(self, brain, hits, def, { Knockback = 10, Motion = "Grip" })
	end
	damageTargets(self, brain, { victim }, def, { Share = clamp.Share, Knockback = 0, Motion = "Grip", NoKnockdown = true })

	local victimRoot = victim:FindFirstChild("HumanoidRootPart")
	local hold = victimRoot and alive(victim) and canHold(brain, victim)
	local grip = root.CFrame * CFrame.new(0, 0, -mouth)
	local relative = hold and grip:ToObjectSpace(victimRoot.CFrame)
	local swing = math.rad(clamp.Swing or 16)
	local liftHeight = clamp.Lift or 0.25
	local random = Random.new()
	local function rip(completed: boolean)
		if not completed or not stillValid(brain, castToken) or not alive(victim) then
			return
		end
		-- RIP: torn away to the biter's left and out (or blasted straight away)
		local throw
		if clamp.Throw == "Forward" then
			throw = (root.CFrame.LookVector * 0.9 + Vector3.yAxis * 0.3).Unit
		else
			throw = (-root.CFrame.RightVector * 0.9 + root.CFrame.LookVector * 0.35).Unit
		end
		damageTargets(self, brain, { victim }, def, {
			Share = 1 - clamp.Share - (clamp.Ticks and #clamp.Ticks * clamp.Ticks[1][2] or 0),
			Knockback = clamp.RipKnockback, Heavy = true, Motion = throw, NoStatus = true,
		})
	end
	-- the jolts while it's held
	for _, tick in clamp.Ticks or {} do
		task.delay(tick[1], function()
			if stillValid(brain, castToken) and alive(victim) and (not hold or victim:GetAttribute("Gripped")) then
				damageTargets(self, brain, { victim }, def, { Share = tick[2], Knockback = 0, NoKnockdown = true, NoStatus = true, Stagger = 4 })
			end
		end)
	end
	if hold then
		self:Hold(brain, castToken, victim, clamp.Hold, function(t)
			local ramp = math.min(t / 0.12, 1)
			local yaw, lift
			if clamp.Style == "Convulse" then
				yaw = (math.sin(t * math.pi * 2 * clamp.Shake) * 0.6 + (random:NextNumber() - 0.5) * 0.8) * swing * ramp
				lift = random:NextNumber() * liftHeight * ramp
			else
				-- thrashed with the head: a yaw swing about the mouth, lifting a little each shake
				yaw = math.sin(t * math.pi * 2 * clamp.Shake) * swing * ramp
				lift = math.abs(math.sin(t * math.pi * 2 * clamp.Shake)) * liftHeight * ramp
			end
			return grip * CFrame.Angles(0, yaw, 0) * CFrame.new(0, lift, 0) * relative
		end, rip)
	else
		-- too big to lift: the jaws hang on while the biter digs in, then let go
		root.Anchored = true
		task.delay(clamp.Hold, function()
			if root.Parent then
				root.Anchored = false
			end
			rip(true)
		end)
	end
end

-- THE WRAP (Tentacle Lash): the lash lands at the end of its reach; the body nearest the
-- tip that can be carried is caught (Wrap.Share), reeled in to Wrap.Reach in front over
-- ReelTime, hoisted Wrap.Lift studs by LiftAt, and slammed down into the floor at SlamAt:
-- the rest of the damage, crumpling it. Everything else in the lash just takes it.
function AbilityService:WrapAndSlam(brain, castToken: number, hits, def)
	local wrap = def.Wrap
	local root = brain.root
	local half = brain.hitboxSize.Z / 2
	local tip = (root.CFrame * CFrame.new(0, 0, -(half + def.Range))).Position
	table.sort(hits, function(a, b)
		return (a:GetPivot().Position - tip).Magnitude < (b:GetPivot().Position - tip).Magnitude
	end)
	local victim = hits[1]
	local victimRoot = victim:FindFirstChild("HumanoidRootPart")
	if not victimRoot or not canHold(brain, victim) then
		damageTargets(self, brain, hits, def, { Knockback = 12, Motion = "Grip" })
		return
	end
	table.remove(hits, 1)
	if #hits > 0 then
		damageTargets(self, brain, hits, def, { Share = wrap.Share, Knockback = 10 })
	end
	damageTargets(self, brain, { victim }, def, { Share = wrap.Share, Knockback = 0, Motion = "Grip", NoKnockdown = true })
	fireFX(self, root.Position, { Kind = "Lash", Model = brain.model, Target = victim, Time = wrap.SlamAt })
	local start = victimRoot.CFrame
	local standY = start.Position.Y
	local radius = radiusOf(victim)
	local function place(t: number): CFrame
		local front = root.CFrame * CFrame.new(0, 0, -(half + wrap.Reach + radius))
		local spot = Vector3.new(front.Position.X, standY, front.Position.Z)
		local facing = CFrame.lookAt(spot, Vector3.new(root.Position.X, standY, root.Position.Z)).Rotation
		if t < wrap.ReelTime then
			-- hauled in along the floor, faster and faster
			local k = (t / wrap.ReelTime) ^ 2
			return start:Lerp(facing + spot, k)
		elseif t < wrap.LiftAt then
			-- hoisted up high, dangling
			local k = (t - wrap.ReelTime) / (wrap.LiftAt - wrap.ReelTime)
			k = k * k * (3 - 2 * k)
			return facing * CFrame.Angles(math.rad(-25) * k, 0, 0) + spot + Vector3.new(0, wrap.Lift * k, 0)
		end
		-- and smashed down
		local k = math.min((t - wrap.LiftAt) / (wrap.SlamAt - wrap.LiftAt), 1)
		return facing * CFrame.Angles(math.rad(-25 + 70 * k), 0, 0) + spot + Vector3.new(0, wrap.Lift * (1 - k * k), 0)
	end
	self:Hold(brain, castToken, victim, wrap.SlamAt, place, function(completed)
		if not completed or not alive(victim) then
			return
		end
		local at = victimRoot.Position - Vector3.new(0, victimRoot.Size.Y / 2, 0)
		Net.FireNearby(self.Services.TelegraphService.WorldFX, at, Config.Performance.EffectRadius, "Slam", { Position = at, Radius = 3.5, Power = 0.55 })
		damageTargets(self, brain, { victim }, def, { Share = 1 - wrap.Share, Knockback = 0, Crumple = true, Heavy = true, Thrown = true })
	end)
end

-- THE PIN (Venom Sting): the stinger goes into the nearest body it hits that can be held
-- (Pin.Share) and stays in: pinned where it stands, sagging, for Pin.Hold seconds while
-- the tail pumps venom into it (each pump: a share of the damage and a poison stack, a
-- jolt), then the stinger is yanked out and it's kicked away (the rest).
function AbilityService:PinAndPump(brain, castToken: number, hits, def)
	local pin = def.Pin
	local root = brain.root
	local point = (root.CFrame * CFrame.new(0, 0, -(def.Reach or brain.hitboxSize.Z / 2))).Position
	table.sort(hits, function(a, b)
		return (a:GetPivot().Position - point).Magnitude < (b:GetPivot().Position - point).Magnitude
	end)
	local victim = hits[1]
	local victimRoot = victim:FindFirstChild("HumanoidRootPart")
	if not victimRoot or not canHold(brain, victim) then
		damageTargets(self, brain, hits, def, { Knockback = def.Knockback })
		return
	end
	table.remove(hits, 1)
	if #hits > 0 then
		damageTargets(self, brain, hits, def, { Share = pin.Share, Knockback = def.Knockback })
	end
	damageTargets(self, brain, { victim }, def, { Share = pin.Share, Knockback = 0, NoKnockdown = true })
	local start = victimRoot.CFrame
	local pumps = pin.Pumps
	local lastPump = -math.huge
	for _, pump in pumps do
		task.delay(pump[1], function()
			if stillValid(brain, castToken) and alive(victim) and victim:GetAttribute("Gripped") then
				lastPump = os.clock()
				damageTargets(self, brain, { victim }, def, { Share = pump[2], Knockback = 0, NoKnockdown = true, Stagger = 5 })
			end
		end)
	end
	self:Hold(brain, castToken, victim, pin.Hold, function(t)
		-- driven down onto the point, buckling; every pump jolts it
		local sag = math.min(t / 0.15, 1)
		local jolt = math.max(0, 1 - (os.clock() - lastPump) / 0.12)
		return start * CFrame.new(0, -0.35 * sag - 0.15 * jolt, 0) * CFrame.Angles(math.rad(-10 * sag - 6 * jolt), 0, 0)
	end, function(completed)
		if not completed or not alive(victim) then
			return
		end
		local spent = pin.Share
		for _, pump in pumps do
			spent += pump[2]
		end
		damageTargets(self, brain, { victim }, def, { Share = math.max(1 - spent, 0.1), Knockback = pin.YankKnockback, NoStatus = true })
	end)
end

-- STRIKES: several blows in one move, each at its own time (see AbilityDefinitions).
function AbilityService:Strikes(brain, castToken: number, def)
	local root = brain.root
	local hitbox = brain.hitboxSize
	for _, strike in def.Strikes do
		task.delay(strike.At, function()
			if not stillValid(brain, castToken) then
				return
			end
			local cframe = root.CFrame * CFrame.new(0, 0, -(hitbox.Z / 2 + def.Range / 2))
			local hits = self.Services.HitDetectionService:QueryBox(cframe, Vector3.new(def.Width, hitbox.Y + 2, def.Range), ignoreList(brain), root.Position)
			damageTargets(self, brain, hits, def, {
				Share = strike.Share, Knockback = strike.Knockback, Motion = strike.Motion, NoKnockdown = strike.NoKnockdown,
				NoStatus = strike.NoStatus, Heavy = strike.Heavy, Launch = strike.Launch,
			})
		end)
	end
end

-- Moves the anchored body from `from` to `to` over `duration` (ease: k -> 0..1, arc: studs
-- of height at the middle), calling `onStep(k)` each frame; `onDone(stoppedEarly)` at the
-- end. Returns a function that stops it where it is.
local function drive(brain, castToken: number, from: CFrame, to: CFrame, duration: number, ease, arc: number, onStep, onDone)
	local root = brain.root
	root.Anchored = true
	local began = os.clock()
	local connection
	local finished = false
	local function finish(early: boolean)
		if finished then
			return
		end
		finished = true
		connection:Disconnect()
		if root.Parent then
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if onDone then
			onDone(early)
		end
	end
	connection = RunService.Heartbeat:Connect(function()
		if not stillValid(brain, castToken) or brain.model:GetAttribute("Ragdolled") then
			finish(true)
			return
		end
		local t = duration > 0 and math.min((os.clock() - began) / duration, 1) or 1
		local k = ease(t)
		root.CFrame = from:Lerp(to, k) + Vector3.new(0, 4 * t * (1 - t) * arc, 0)
		if onStep then
			onStep(k)
		end
		if t >= 1 then
			finish(false)
		end
	end)
	return function()
		finish(true)
	end
end

-- THE CHARGE (Frost Ram, Bat Dive, Blink Dash, Phoenix Dive): the body is driven Distance
-- studs along its facing (onto the target if it has one), stopping short of walls, over
-- Time seconds from the windup (Early: arriving AT the windup instead - a dive that lands
-- on the hit frame), Arc studs high at the middle. On the way:
--   Gore         the first body it runs into that can be carried is gored (Gore.Share) and
--                carried on the horns to the end of the run, then tossed (the rest, a launch)
--   PassThrough  every body it passes through takes that share (and is knocked aside)
--   StopOnHit    the first body it reaches takes the hit and the charge stops there
--   (otherwise)  it ploughs through: half the damage, knocked aside
--   a boss stops it dead and takes the full hit
-- At the end: EndBurst (a blast round where it stops), Bounce (kicks off backwards).
-- Blink: the body vanishes and comes out at the end at once; the tear it leaves along the
-- way cuts everything on it Blink.RiftDelay seconds later.
function AbilityService:Charge(brain, castToken: number, def, target: Model?, windup: number)
	local root = brain.root
	local hitbox = brain.hitboxSize
	local half = hitbox.Z / 2
	local hitDetection = self.Services.HitDetectionService
	local look = Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
	local distance = def.Distance
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	if targetRoot then
		local offset = Util.Flat(targetRoot.Position - root.Position)
		look = Util.FlatUnit(offset) or look
		if def.StopOnHit then
			-- a dive lands ON them: its front just into their body
			distance = math.clamp(offset.Magnitude - half - radiusOf(target) + 0.6, 0, def.Distance)
		end
	end
	local startAt = def.Early and math.max(windup - def.Time, 0) or windup
	task.delay(startAt, function()
		if not stillValid(brain, castToken) or brain.model:GetAttribute("Ragdolled") then
			return
		end
		local from = CFrame.lookAt(root.Position, root.Position + look)
		-- stop short of walls (a body's half-length clear of them)
		local clear = hitDetection:ClearDistance(root.Position, look * (distance + half)) - half - 0.3
		local travel = math.clamp(clear, 0, distance)
		local endPosition = from.Position + look * travel
		local ignore = ignoreList(brain)
		local floorHere, floorThere = floorAt(from.Position, ignore), floorAt(endPosition, ignore)
		if floorHere and floorThere and math.abs(floorThere - floorHere) < 4 then
			endPosition += Vector3.new(0, floorThere - floorHere, 0)
		end
		local to = CFrame.lookAt(endPosition, endPosition + look)
		if def.Trail then
			fireFX(self, from.Position, { Kind = "Trail", Style = def.Trail, Model = brain.model, From = from.Position, To = endPosition, Time = def.Time, Delay = def.Blink and def.Blink.RiftDelay or nil })
		end

		-- BLINK: gone, and out at the far end; the tear cuts along the line a moment later
		if def.Blink then
			root.Anchored = true
			root.CFrame = to
			task.delay(0.05, function()
				if root.Parent then
					root.Anchored = false
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end)
			task.delay(def.Blink.RiftDelay, function()
				if not stillValid(brain, castToken) then
					return
				end
				local mid = (from.Position + endPosition) / 2
				local box = CFrame.lookAt(mid, mid + look)
				local hits = hitDetection:QueryBox(box, Vector3.new(def.Width, hitbox.Y + 2, travel + hitbox.Z), ignore)
				damageTargets(self, brain, hits, def, { Knockback = 12, Motion = Vector3.yAxis * 0.5 + look * 0.2 })
			end)
			return
		end

		local hit = {}
		local gored, goredRoot, letGo = nil, nil, nil
		local stopNow
		local function contact()
			local front = root.CFrame * CFrame.new(0, 0, -(half + 0.8))
			for _, victim in hitDetection:QueryBox(front, Vector3.new(def.Width, hitbox.Y + 2, 2.4), ignore) do
				if hit[victim] then
					continue
				end
				hit[victim] = true
				local side = Util.FlatUnit(victim:GetPivot().Position - root.Position)
				local aside = side and (side - look * side:Dot(look)) or Vector3.zero
				aside = aside.Magnitude > 0.05 and aside.Unit or root.CFrame.RightVector
				if victim:GetAttribute("BossId") or (def.StopOnHit and not gored) then
					-- a wall of flesh (or the dive's landing): the full hit, and it stops here
					damageTargets(self, brain, { victim }, def, { Knockback = def.StopOnHit and 18 or 0, Motion = look })
					if stopNow then
						stopNow()
					end
					return
				elseif def.Gore and not gored and canHold(brain, victim) then
					gored, goredRoot = victim, victim:FindFirstChild("HumanoidRootPart")
					damageTargets(self, brain, { victim }, def, { Share = def.Gore.Share, Knockback = 0, NoKnockdown = true, Motion = look })
					local radius = radiusOf(victim)
					local reach = mouthReach(brain) - BITE_THRUST + radius * 0.6
					local lift = def.Gore.Lift
					local began = os.clock()
					-- scooped up on the horns and carried, riding the charge
					letGo = self:Hold(brain, castToken, victim, def.Time + 0.3, function()
						local k = math.min((os.clock() - began) / 0.12, 1)
						return root.CFrame * CFrame.new(0, lift * k, -reach) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(-30 * k), 0, 0)
					end, function() end, false)
				elseif def.PassThrough then
					damageTargets(self, brain, { victim }, def, { Share = def.PassThrough, Knockback = 22, Motion = (aside + Vector3.yAxis * 0.4).Unit })
				else
					-- ploughed through: thrown aside
					damageTargets(self, brain, { victim }, def, { Share = 0.5, Knockback = 28, Motion = (aside * 0.8 + look * 0.4 + Vector3.yAxis * 0.3).Unit })
				end
			end
		end
		local ease = def.Arc and function(t)
			return t
		end or function(t)
			return 1 - (1 - t) ^ 2.2 -- off like a shot, easing only at the very end
		end
		stopNow = drive(brain, castToken, from, to, def.Time, ease, def.Arc or 0, contact, function(early)
			if not stillValid(brain, castToken) then
				return
			end
			local here = root.Position
			-- the gored body is tossed up and over off the horns
			if letGo then
				letGo()
			end
			if gored and alive(gored) then
				fireFX(self, goredRoot.Position, { Kind = "Shatter", Style = def.Trail, Position = goredRoot.Position })
				damageTargets(self, brain, { gored }, def, { Share = 1 - def.Gore.Share, Knockback = 0, Heavy = true, Launch = def.Gore.Toss, Motion = (look + Vector3.yAxis).Unit })
			end
			if def.EndBurst then
				local burst = def.EndBurst
				local center = here + look * (half * 0.5)
				fireFX(self, center, { Kind = "Burst", Style = def.Trail, Position = center, Radius = burst.Radius })
				local blast = {}
				for _, model in hitDetection:QueryRadius(center, burst.Radius + 2, ignore, here) do
					if Util.FlatDistance(model:GetPivot().Position, center) <= burst.Radius + radiusOf(model) then
						table.insert(blast, model)
					end
				end
				damageTargets(self, brain, blast, def, { Share = burst.Share, Knockback = 30, From = center })
			end
			if def.Bounce then
				-- kick off them, backwards and up a little
				local back = root.CFrame - look * def.Bounce
				drive(brain, castToken, root.CFrame, back, 0.22, function(t)
					return 1 - (1 - t) ^ 2
				end, 1.2)
			end
		end)
	end)
end

-- THE GLARE (Visor Glare): from the hit frame a beam pours out of the head for Ticks x
-- Interval: each tick everything in the beam (Range long, Width wide, straight ahead) takes
-- Damage; the last tick staggers. The beam on screen rides the head (animation markers).
function AbilityService:Glare(brain, castToken: number, def, windup: number)
	local root = brain.root
	local hitbox = brain.hitboxSize
	for tick = 0, def.Ticks - 1 do
		task.delay(windup + tick * def.Interval, function()
			if not stillValid(brain, castToken) then
				return
			end
			local cframe = root.CFrame * CFrame.new(0, 0, -(hitbox.Z / 2 + def.Range / 2))
			local hits = self.Services.HitDetectionService:QueryBox(cframe, Vector3.new(def.Width, hitbox.Y + 2, def.Range), ignoreList(brain), root.Position)
			local last = tick == def.Ticks - 1
			damageTargets(self, brain, hits, def, {
				Share = 1, Knockback = last and 14 or 2, NoKnockdown = not last, NoStatus = tick % 2 == 1,
				Stagger = last and (def.Stagger or 8) * 3 or def.Stagger,
			})
		end)
	end
end

-- THE REEL (Magnet Pull): the magnet locks on to the target (Reel.Share). A body that can
-- be held is DRAGGED along the floor into the claw over Reel.Time (faster and faster),
-- swung up overhead (Reel.Lift) and SLAMMED down in front at Reel.SlamAt: the rest,
-- crumpling it. A player is yanked in by an impulse instead and takes the slam if still
-- in reach.
function AbilityService:Reel(brain, castToken: number, def, target: Model)
	local reel = def.Reel
	local root = brain.root
	local half = brain.hitboxSize.Z / 2
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	fireFX(self, root.Position, { Kind = "MagnetLock", Model = brain.model, Target = target, Time = reel.Time })
	damageTargets(self, brain, { target }, def, { Share = reel.Share, Knockback = 0, Motion = "Grip", NoKnockdown = true })
	local radius = radiusOf(target)
	local function slam()
		if not stillValid(brain, castToken) or not alive(target) then
			return
		end
		local at = targetRoot.Position - Vector3.new(0, targetRoot.Size.Y / 2, 0)
		Net.FireNearby(self.Services.TelegraphService.WorldFX, at, Config.Performance.EffectRadius, "Slam", { Position = at, Radius = 3.5, Power = 0.6 })
		damageTargets(self, brain, { target }, def, { Share = 1 - reel.Share, Knockback = 0, Crumple = true, Heavy = true, Thrown = true })
	end
	if not canHold(brain, target) then
		-- a player (or something too big): yanked in, and slammed if it's still there
		if not targetRoot.Anchored and not target:GetAttribute("KnockbackImmune") then
			local toward = Util.FlatUnit(root.Position - targetRoot.Position)
			local distance = Util.FlatDistance(root.Position, targetRoot.Position) - (half + reel.Reach + radius)
			if toward and distance > 0 then
				targetRoot:ApplyImpulse((toward * math.min(distance * 4, 90) + Vector3.new(0, 12, 0)) * targetRoot.AssemblyMass)
			end
		end
		task.delay(reel.SlamAt, function()
			if alive(target) and Util.FlatDistance(root.Position, targetRoot.Position) <= half + reel.Reach + radius + 3 then
				slam()
			end
		end)
		return
	end
	local start = targetRoot.CFrame
	local standY = start.Position.Y
	local function place(t: number): CFrame
		local catch = root.CFrame * CFrame.new(0, 0, -(half + reel.Reach + radius))
		local spot = Vector3.new(catch.Position.X, standY, catch.Position.Z)
		local facing = CFrame.lookAt(spot, Vector3.new(root.Position.X, standY, root.Position.Z)).Rotation
		if t < reel.Time then
			-- dragged in along the floor, faster and faster
			local k = (t / reel.Time) ^ 2
			return start:Lerp(facing + spot, k)
		end
		local span = reel.SlamAt - reel.Time
		local p = (t - reel.Time) / span
		if p < 0.6 then
			-- swung up over the claw
			local k = p / 0.6
			k = k * k * (3 - 2 * k)
			return facing * CFrame.Angles(math.rad(-40 * k), 0, 0) + spot + Vector3.new(0, reel.Lift * k, 0) + root.CFrame.LookVector * (-1.2 * k)
		end
		-- and brought down hard
		local k = (p - 0.6) / 0.4
		return facing * CFrame.Angles(math.rad(-40 + 90 * k), 0, 0) + spot + Vector3.new(0, reel.Lift * (1 - k * k), 0) + root.CFrame.LookVector * (-1.2 * (1 - k))
	end
	self:Hold(brain, castToken, target, reel.SlamAt, place, function(completed)
		if completed then
			slam()
		end
	end)
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
	local windup = def.Windup
	local length, committed = AbilityDefinitions.Length(def)

	brain.busyUntil = now + length
	brain.cancelableAt = now + committed + 0.05 -- the next queued ability may only cut the RECOVERY
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
	ai:PlayAction(brain, "Ability_" .. def.Id, windup, length)
	self.Services.TutorialService:Notify(brain.owner, "AbilityUsed")
	self.Services.ChallengeService:Notify(brain.owner, "AbilityUsed")

	local root = brain.root
	local hitbox = brain.hitboxSize

	if def.Type == "Melee" then
		if def.Lunge and target then
			lungeAt(brain, target, windup, def.Lunge, def.Reach)
		end
		if def.Strikes then
			self:Strikes(brain, castToken, def)
			return
		end
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			local cframe = root.CFrame * CFrame.new(0, 0, -(hitbox.Z / 2 + def.Range / 2))
			local hits = hitDetection:QueryBox(cframe, Vector3.new(def.Width, hitbox.Y + 2, def.Range), ignoreList(brain), root.Position)
			if #hits == 0 then
				return
			end
			if def.Clamp then
				self:ClampAndRip(brain, castToken, hits, def)
			elseif def.Wrap then
				self:WrapAndSlam(brain, castToken, hits, def)
			elseif def.Pin then
				self:PinAndPump(brain, castToken, hits, def)
			else
				-- how the blow lands on them: a bite grips and tears back; a sweep carries them
				-- across the way the claw travels (a left-arm claw sweeps the other way)
				damageTargets(self, brain, hits, def, { Knockback = def.Knockback or 15, Motion = def.Motion })
			end
		end)
	elseif def.Type == "AoE" then
		local ground = root.Position - Vector3.new(0, hitbox.Y / 2 + brain.humanoid.HipHeight, 0)
		local center = ground + Util.Flat(root.CFrame.LookVector) * def.Offset
		telegraphs:Circle(center, def.Radius, windup, "Friendly")
		local function blast(radius: number, share: number, knockback: number)
			local hits = {}
			for _, model in hitDetection:QueryRadius(center + Vector3.new(0, 3, 0), radius + 3, ignoreList(brain), root.Position) do
				local r = model:FindFirstChild("HumanoidRootPart")
				if r and Util.FlatDistance(r.Position, center) <= radius + math.max(r.Size.X, r.Size.Z) / 2 then
					table.insert(hits, model)
				end
			end
			damageTargets(self, brain, hits, def, {
				Share = share, Knockback = knockback, Launch = share >= 0.5 and def.Launch or nil, From = def.Radial and center or nil,
			})
		end
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			telegraphs:Impact(center, def.Radius, "Friendly")
			if def.Slam then
				Net.FireNearby(telegraphs.WorldFX, center, Config.Performance.EffectRadius, "Slam", { Position = center, Radius = def.Radius, Power = 1 })
			end
			blast(def.Radius, def.Aftershock and 1 - def.Aftershock.Share or 1, 20)
		end)
		if def.Aftershock then
			task.delay(windup + def.Aftershock.At, function()
				if not stillValid(brain, castToken) then
					return
				end
				Net.FireNearby(telegraphs.WorldFX, center, Config.Performance.EffectRadius, "Slam", { Position = center, Radius = def.Aftershock.Radius, Power = 0.5 })
				blast(def.Aftershock.Radius, def.Aftershock.Share, 12)
			end)
		end
	elseif def.Type == "Charge" then
		self:Charge(brain, castToken, def, target, windup)
	elseif def.Type == "Pull" then
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			local tRoot = target and target:FindFirstChild("HumanoidRootPart")
			if not tRoot or not alive(target) or Util.FlatDistance(tRoot.Position, root.Position) > def.Range + 3 then
				return
			end
			if def.Reel then
				self:Reel(brain, castToken, def, target)
				return
			end
			if not tRoot.Anchored and not target:GetAttribute("KnockbackImmune") then
				local toward = Util.FlatUnit(root.Position - tRoot.Position)
				local distance = Util.FlatDistance(root.Position, tRoot.Position) - (hitbox.Z / 2 + 3)
				if toward and distance > 0 then
					tRoot:ApplyImpulse((toward * math.min(distance * 4, 90) + Vector3.new(0, 12, 0)) * tRoot.AssemblyMass)
				end
			end
			damageTargets(self, brain, { target }, def, { Knockback = 0 })
		end)
	elseif def.Type == "Leap" then
		self:Leap(brain, castToken, def, target, windup)
	elseif def.Type == "Breath" then
		self:Breath(brain, castToken, def, windup)
	elseif def.Type == "Glare" then
		self:Glare(brain, castToken, def, windup)
	elseif def.Type == "Shield" then
		task.delay(windup, function()
			if not stillValid(brain, castToken) then
				return
			end
			-- (ShieldStyle: which shield it is, for its look on every client: AbilityEffects)
			brain.model:SetAttribute("ShieldStyle", def.Id)
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
		damageTargets(self, brain, hits, def, { Knockback = 30, From = center })
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
			damageTargets(self, brain, hits, def, { Knockback = 2 })
		end)
	end
end

return AbilityService
