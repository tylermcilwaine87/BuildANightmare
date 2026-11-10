--[[
	NightmareAnimator  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/NightmareAnimator

	Procedural, client-side animation for EVERY part combination. Instead of authoring an
	animation per creature, each joint is driven by its ROLE:

	  Joint_Core        idle breathing / floating bob, forward lean while moving,
	                    flinch on hit, lunge on bites, collapse on defeat
	  Joint_Head        idle glances, "IdleLook" personality, bite nod
	  Joint_RightArm /  idle sway, walk swing, windup -> strike -> recover on combo hits
	  Joint_LeftArm
	  Joint_Tail        lazy sway
	  Joint_Legs        hover wobble (floating legs)
	  Sub_Legs_L/R      walking stride
	  Sub_Back_L/R      wing flaps

	Writes Motor6D.Transform only (purely visual, never replicated) so it cannot affect
	server hitboxes. Models far from the camera are skipped. Phase 7 can layer authored
	AnimationTracks on top for signature parts without changing this contract.
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AnimationDefinitions = require(Shared:WaitForChild("AnimationDefinitions"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local POSES = require(script.Parent:WaitForChild("NightmarePoses"))
local PoseCurve = require(script.Parent:WaitForChild("PoseCurve"))
local BOSS_POSES = require(script.Parent:WaitForChild("BossPoses"))
local BossMotion = require(script.Parent:WaitForChild("BossMotion"))
local FightAim = require(script.Parent:WaitForChild("FightAim"))
local RingCraft = require(script.Parent:WaitForChild("RingCraft"))

-- The keyframed-attack library for a model, and the asset name prefix:
-- bosses by BossId (BossPoses), Nightmares by body plan (NightmarePoses).
local function libraryFor(model: Model)
	local bossId = model:GetAttribute("BossId")
	if bossId then
		return BOSS_POSES[bossId], "Boss_" .. bossId
	end
	if CollectionService:HasTag(model, "Nightmare") then
		local archetype = model:GetAttribute("Archetype") or "Biped"
		return POSES[archetype], "Nightmare_" .. archetype
	end
	return nil, nil
end

local NightmareAnimator = {}

-- MarkerReached(model, actionName, markerName): a keyframed attack reached an event marker
local markerEvent = Instance.new("BindableEvent")
NightmareAnimator.MarkerReached = markerEvent.Event
local IS_STUDIO = RunService:IsStudio()

local CULL_DISTANCE = 160
local STRIKE_TIME = 0.12

local tracked = {} -- [Model] = state
local labCache = { Source = nil, Def = nil } -- Studio pose lab (NMScrubAction = "Lab")

-- Which limbs each action uses. Unknown actions swing both arms.
local ACTION_ARMS = {
	Combo1 = "Right",
	Combo2 = "Left",
	Combo3 = "Both",
	Swipe = "Right",
	Slam = "Both",
	Barrage = "Left",
	MagnetPull = "Both",
	Roar = "Roar",
	Ability_Melee = "Both",
	Ability_AoE = "Both",
	Ability_Pull = "Right",
	Ability_Dash = "Lunge",
	Ability_Shield = "None",
	Heavy = "Heavy",
	Ultimate = "Ultimate",
	-- the beast moves are keyframed whole-body (NightmarePoses): no procedural arm swing
	Beast_Pounce = "None",
	Beast_Roll = "None",
	Beast_TailWhip = "None",
	Beast_Headbutt = "None",
	-- UNLEASHED (possessed): whole-body keyframed blows too
	Rage_Haymaker = "None",
	Rage_Elbow = "None",
	Rage_Uppercut = "None",
	Rage_Smash = "None",
	Rage_GrabSlam = "None",
	Rage_Leap = "None",
	-- NIGHTMARE UNDERGROUND: single keyframed strikes (Config.Underground.Fight)
	UG_Jab = "None",
	UG_Cross = "None",
	UG_HookL = "None",
	UG_Uppercut = "None",
	UG_LiverHook = "None",
	UG_Overhand = "None",
	UG_Launcher = "None",
	UG_BodyBlast = "None",
	UG_Parried = "None",
	UG_Feint = "None",
	Slip_L = "None",
	Slip_R = "None",
	PullBack = "None",
	RollUnder = "None",
	-- footwork (NightmareAIService Fight)
	StepBack = "Hop",
	Sidestep = "Hop",
	DashIn = "Lunge",
}

------------------------------------------------------------------------------------------
-- Tracking
------------------------------------------------------------------------------------------
local function untrack(model: Model)
	local state = tracked[model]
	if not state then
		return
	end
	for _, connection in state.connections do
		connection:Disconnect()
	end
	tracked[model] = nil
end

local function track(model: Model)
	if tracked[model] then
		return
	end
	local state = {
		model = model,
		motors = {},
		seed = math.random() * 10,
		walkPhase = 0,
		action = nil,
		actionStart = 0,
		windup = 0,
		duration = 0,
		flinch = 0,
		defeatT = 0,
		connections = {},
	}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			state.motors[d.Name] = d
		end
	end
	table.insert(state.connections, model.DescendantAdded:Connect(function(d)
		if d:IsA("Motor6D") then
			state.motors[d.Name] = d
		end
	end))
	-- the knockdown ends: get up properly instead of popping straight upright
	table.insert(state.connections, model:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if model:GetAttribute("Ragdolled") then
			if state.track then
				state.track:Stop(0)
				state.track = nil
			end
			state.pose = nil
			return
		end
		local def = POSES.Common and POSES.Common.GetUp
		if def then
			state.action = "GetUp"
			state.pose = { Def = def, Start = os.clock(), Speed = 1, LastT = -1 }
		end
	end))
	table.insert(state.connections, model:GetAttributeChangedSignal("ActionSeq"):Connect(function()
		state.action = model:GetAttribute("ActionName")
		state.windup = model:GetAttribute("ActionWindup") or 0.25
		state.duration = model:GetAttribute("ActionDuration") or 0.6
		state.actionStart = os.clock()
		NightmareAnimator:PlayKeyframed(state)
	end))
	table.insert(state.connections, model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			untrack(model)
		end
	end))
	tracked[model] = state
end

------------------------------------------------------------------------------------------
-- Curves
------------------------------------------------------------------------------------------
-- Arm swing for an attack: raise during windup, slam during strike, settle in recovery.
-- Returns (armAngle, lungeAmount 0..1)
local function swingCurve(t: number, windup: number): (number, number)
	local raised = 2.3
	if t < windup then
		local p = windup > 0 and t / windup or 1
		return raised * (1 - (1 - p) ^ 2), 0
	elseif t < windup + STRIKE_TIME then
		local p = (t - windup) / STRIKE_TIME
		return raised + (0.35 - raised) * p, p
	end
	local p = math.clamp((t - windup - STRIKE_TIME) / 0.3, 0, 1)
	return 0.35 * (1 - p), 1 - p
end

-- Joints an AnimationTrack is driving right now (the procedural layer leaves them alone so
-- the animation shows; tails / wings / anything it doesn't key keep their procedural sway).
local currentSkip = nil
local function setTransform(motor: Motor6D?, cframe: CFrame)
	if motor and not (currentSkip and currentSkip[motor.Name]) then
		motor.Transform = cframe
	end
end

------------------------------------------------------------------------------------------
-- Keyframed attacks (NightmarePoses): an animation asset through the Animator when one
-- exists (published Id, or the editable KeyframeSequence previewed in Studio), else the
-- same keyframes evaluated here. Played at the speed that lands its "Hit" frame on the
-- server's hit (the attack's windup).
------------------------------------------------------------------------------------------
-- (how a clip moves between its keys: splines, eases, stops - see PoseCurve)
local angleAt = PoseCurve.Sample

-- every joint a pose keys anywhere (+ which one carries a position)
local poseJoints = setmetatable({}, { __mode = "k" })
local function jointsOf(def)
	local joints = poseJoints[def]
	if not joints then
		joints = {}
		for _, key in def.Keys do
			for name, value in key do
				if type(value) == "table" and not name:match("Pos$") then
					joints[name] = true
				end
			end
		end
		poseJoints[def] = joints
	end
	return joints
end

local function hitTime(def): number
	for _, marker in def.Markers or {} do
		if marker[2] == "Hit" then
			return marker[1]
		end
	end
	return def.Duration * 0.45
end

-- The asset id for prefix/action: published (AnimationDefinitions.Nightmare / .Boss) or, in
-- Studio, the KeyframeSequence Shared/Animations/.../<prefix>_<Action>.
local assetIds = {}
local function assetId(prefix: string, action: string): string?
	local key = prefix .. "_" .. action
	local published = (AnimationDefinitions.Nightmare and AnimationDefinitions.Nightmare[key]) or (AnimationDefinitions.Boss and AnimationDefinitions.Boss[key])
	if published and published.Id ~= "" then
		return published.Id
	end
	if not IS_STUDIO or not Config.Dev.PreviewKeyframesInStudio then
		return nil
	end
	if assetIds[key] == nil then
		assetIds[key] = false
		local folder = Shared:FindFirstChild("Animations")
		local sequence = folder and folder:FindFirstChild(key, true)
		if sequence and sequence:IsA("KeyframeSequence") then
			local ok, result = pcall(KeyframeSequenceProvider.RegisterKeyframeSequence, KeyframeSequenceProvider, sequence)
			assetIds[key] = ok and result or false
		end
	end
	return assetIds[key] or nil
end

-- Every change of clip blends over from wherever the body is right now (a clip's rest key
-- would otherwise snap the guard's hands down for a frame).
local function startFade(state, time: number)
	local from = {}
	for name, motor in state.motors do
		from[name] = motor.Transform
	end
	state.fade = { From = from, Start = os.clock(), Time = time }
end

local function applyFade(state, now: number)
	local fade = state.fade
	if not fade then
		return
	end
	local k = (now - fade.Start) / fade.Time
	if k >= 1 then
		state.fade = nil
		return
	end
	k = k * k * (3 - 2 * k)
	for name, from in fade.From do
		local motor = state.motors[name]
		if motor and not (currentSkip and currentSkip[name]) then
			motor.Transform = from:Lerp(motor.Transform, k)
		end
	end
end

local ARM_COMBOS = { Combo1 = true, Combo2 = true, Combo3 = true }

function NightmareAnimator:PlayKeyframed(state)
	local model = state.model
	startFade(state, 0.09)
	if state.track then
		state.track:Stop(0.1)
		state.track = nil
	end
	state.pose = nil
	local library, prefix = libraryFor(model)
	-- Nightmares also share POSES.Common (any body plan: bites, slashes, get-ups...)
	local common = CollectionService:HasTag(model, "Nightmare") and POSES.Common or nil
	local function find(name: string)
		if library and library[name] then
			return library[name], prefix
		elseif common and common[name] then
			return common[name], "Nightmare_Common"
		end
		return nil, nil
	end
	local action = state.action
	-- an arm ability performed by the LEFT limb plays the mirrored version
	if model:GetAttribute("ActionSource") == "LeftArm" and find(action .. "_Left") then
		action ..= "_Left"
	end
	local def
	def, prefix = find(action)
	-- (the basic punches need a fist: an armless biped keeps its procedural headbutt)
	if ARM_COMBOS[action] and model:GetAttribute("Archetype") ~= "Quadruped" and not state.motors.Joint_RightArm and not state.motors.Joint_LeftArm then
		def = nil
	end
	if not def then
		return
	end
	state.action = action
	local speed = state.windup > 0.01 and hitTime(def) / state.windup or 1
	local id = assetId(prefix, state.action)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if id and humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action2
			-- one connection per marker NAME for the track's life (a combo has several
			-- "BagJab" / "Whoosh" markers; each one must fire once, in order)
			local names, actionName = {}, state.action
			for _, marker in def.Markers or {} do
				names[marker[2]] = true
			end
			for name in names do
				local connection = track:GetMarkerReachedSignal(name):Connect(function()
					markerEvent:Fire(model, actionName, name)
				end)
				track.Stopped:Once(function()
					connection:Disconnect()
				end)
			end
			track:Play(0.06, 1, speed)
			state.track = track
			state.trackJoints = jointsOf(def)
			return
		end
	end
	state.pose = { Def = def, Start = os.clock(), Speed = speed, LastT = -1 }
end

-- Applies a code-evaluated keyframed attack over the procedural pose (after it).
local function applyPose(state, now: number, dt: number)
	local pose = state.pose
	local def = pose.Def
	-- HIT-STOP: the attacker's clip holds on the contact frame for a moment
	if state.hitStopUntil and now < state.hitStopUntil then
		pose.Start += dt
	end
	local t = (now - pose.Start) * pose.Speed
	for _, marker in def.Markers or {} do
		if marker[1] > pose.LastT and marker[1] <= t then
			markerEvent:Fire(state.model, state.action, marker[2])
		end
	end
	for _, key in def.Keys do
		if key.Stop and key.T > pose.LastT and key.T <= t then
			RingCraft.Thud(state)
		end
	end
	pose.LastT = t
	if t > def.Duration then
		state.pose = nil
		startFade(state, 0.14)
		return
	end
	for joint in jointsOf(def) do
		local motor = state.motors[joint]
		if motor then
			local x, y, z = angleAt(def, joint, t)
			local cframe = CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
			local hasPos = false
			for _, key in def.Keys do
				if key[joint .. "Pos"] then
					hasPos = true
					break
				end
			end
			if hasPos then
				local px, py, pz = angleAt(def, joint .. "Pos", t)
				cframe = CFrame.new(px, py, pz) * cframe
			end
			motor.Transform = cframe
		end
	end
	-- the punches go all the way out and connect
	if def.Aim then
		state.aimRig = state.aimRig or FightAim.Rig(state.model, state.motors)
		if state.aimRig.Root then
			FightAim.Apply(def, t, state.aimRig)
		end
	end
end

-- The fighting stance (server: attribute FightStance), laid over the procedural pose by its
-- weight: hands up, bladed, knees bent, and a light bounce in the feet.
local function applyStance(state, weight: number, now: number)
	local stance = POSES.Stance and POSES.Stance[state.model:GetAttribute("Archetype") or "Biped"]
	if not stance or weight <= 0.001 then
		return
	end
	for joint, value in stance do
		if joint ~= "Joint_CorePos" then
			local motor = state.motors[joint]
			if motor and not (currentSkip and currentSkip[joint]) then
				motor.Transform = motor.Transform * CFrame.Angles(math.rad(value[1]) * weight, math.rad(value[2]) * weight, math.rad(value[3]) * weight)
			end
		end
	end
	local core = state.motors.Joint_Core
	if core and not (currentSkip and currentSkip.Joint_Core) then
		local lift = stance.Joint_CorePos or { 0, 0, 0 }
		local bounce = math.sin(now * 6.4 + state.seed) * 0.05
		local shift = math.sin(now * 3.2 + state.seed) * 0.04
		core.Transform = CFrame.new(lift[1] * weight + shift * weight, (lift[2] + bounce) * weight, lift[3] * weight) * core.Transform
	end
end

-- BLOCKING (attribute Guarding, BlockService): the guard stance, for as long as it's held. Below
-- the meter's CrackAt the stance fails, by how far: the arms drop, it sinks, and it shakes.
local function applyGuard(state, weight: number, now: number)
	if weight <= 0.001 then
		return
	end
	local model, motors = state.model, state.motors
	local library = POSES[model:GetAttribute("Archetype") or "Biped"]
	-- (the Underground's LOW guard: dropped to the body while pulling back)
	local low = model:GetAttribute("GuardLow") and ((library and library.Guard_Low) or POSES.Common.Guard_Low)
	local hold = (low or (library and library.Guard_Hold) or POSES.Common.Guard_Hold).Keys[3]
	local failing = math.clamp(1 - (model:GetAttribute("GuardLevel") or Config.Block.Max) / Config.Block.CrackAt, 0, 1)
	local shake = math.sin(now * 42) * failing * 2.5
	for joint, value in hold do
		local motor = type(value) == "table" and motors[joint]
		if motor then
			local x = value[1] + shake
			if joint == "Joint_RightArm" or joint == "Joint_LeftArm" then
				x -= 38 * failing
			elseif joint == "Sub_RightArm_Fore" or joint == "Sub_LeftArm_Fore" then
				x -= 30 * failing
			elseif joint == "Joint_Core" then
				x -= 16 * failing
			elseif joint == "Joint_Head" then
				x += 22 * failing
			end
			motor.Transform = motor.Transform:Lerp(CFrame.Angles(math.rad(x), math.rad(value[2]), math.rad(value[3])), weight)
		end
	end
	local core = motors.Joint_Core
	local lift = hold.Joint_CorePos
	if core and lift then
		core.Transform = CFrame.new(lift[1] * weight, (lift[2] - 0.35 * failing) * weight, lift[3] * weight) * core.Transform
	end
end

-- A hit reaction (POSES.Reactions) on top of everything else the body is doing.
local function applyReaction(state, now: number)
	local react = state.react
	if not react then
		return
	end
	local def = react.Def
	local t = (now - react.Start) / react.Scale
	if t >= def.Duration then
		state.react = nil
		return
	end
	for joint in jointsOf(def) do
		local motor = state.motors[joint]
		if motor and not (currentSkip and currentSkip[joint]) then
			local x, y, z = angleAt(def, joint, t)
			motor.Transform = motor.Transform * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
		end
	end
	local core = state.motors.Joint_Core
	if core and not (currentSkip and currentSkip.Joint_Core) then
		local px, py, pz = angleAt(def, "Joint_CorePos", t)
		core.Transform = CFrame.new(px, py, pz) * core.Transform
	end
end

------------------------------------------------------------------------------------------
-- Per-frame animation
------------------------------------------------------------------------------------------
local function animate(state, root: BasePart, dt: number, now: number)
	local model = state.model
	local motors = state.motors
	if state.track and not state.track.IsPlaying then
		state.track = nil
	end
	currentSkip = state.track and state.trackJoints or nil

	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local move = math.clamp(speed / 14, 0, 1)
	state.walkPhase += dt * (4 + speed * 0.45) * (move > 0.05 and 1 or 0.2)

	local floating = model:GetAttribute("Archetype") == "Floating"
	local defeated = model:GetAttribute("Defeated") == true
	state.flinch = math.max(0, state.flinch - dt * 3.2) -- (~0.3 s from the hit back to neutral)
	if defeated then
		state.defeatT = math.min(1, state.defeatT + dt * 2.5)
	end

	-- Attack / action layer
	local rightSwing, leftSwing, lunge, headPitch, headYaw = 0, 0, 0, 0, 0
	local ultimateLift, hopLean, hopCrouch = 0, 0, 0
	local staggered = (model:GetAttribute("StaggeredUntil") or 0) > Workspace:GetServerTimeNow()
	local actionTime = now - state.actionStart
	if state.action and actionTime <= state.duration then
		local hasRight = motors.Joint_RightArm ~= nil
		local hasLeft = motors.Joint_LeftArm ~= nil
		local action = state.action

		-- (an ability with no keyframed animation yet falls back to its type's motion)
		local abilityDef = action:sub(1, 8) == "Ability_" and AbilityDefinitions.Get(action:sub(9))
		local style = ACTION_ARMS[action] or (abilityDef and ACTION_ARMS["Ability_" .. abilityDef.Type])
			or (action:sub(1, 9) == "Ultimate_" and "Ultimate") or "Both"
		if action == "IdleLook" then
			headYaw = math.sin(actionTime / state.duration * math.pi * 2) * 0.7
		elseif style == "Roar" then
			headPitch = 0.5 * math.sin(math.min(actionTime / 0.4, 1) * math.pi / 2)
			state.flinch = math.max(state.flinch, 0.4 * math.abs(math.sin(actionTime * 20)))
		elseif style == "None" then
			lunge = 0
		elseif style == "Hop" then
			-- quick step out: sink, lean away, guard up, then settle
			local p = math.sin(math.clamp(actionTime / state.duration, 0, 1) * math.pi)
			hopLean = 0.35 * p
			hopCrouch = -0.35 * p
			rightSwing = 0.9 * p
			leftSwing = 0.9 * p
			headPitch = -0.15 * p
		elseif style == "Ultimate" then
			-- Arms rise overhead through the startup and stay up while it plays out.
			local p = math.clamp(actionTime / math.max(state.windup, 0.01), 0, 1)
			rightSwing = 2.9 * p
			leftSwing = 2.9 * p
			headPitch = 0.35 * p
			ultimateLift = 0.8 * p
		elseif style == "Heavy" then
			local angle, thrust = swingCurve(actionTime, state.windup)
			rightSwing = (hasRight or not hasLeft) and angle * 1.15 or 0
			leftSwing = hasLeft and angle * 1.15 or 0
			if not hasRight and not hasLeft then
				headPitch = -angle * 0.35
			end
			lunge = thrust * 1.3
		elseif style == "Lunge" then
			local _, thrust = swingCurve(actionTime, state.windup)
			lunge = thrust * 1.5
			headPitch = -0.3 * thrust
		else
			local angle, thrust = swingCurve(actionTime, state.windup)
			local useRight, useLeft = false, false
			if style == "Right" then
				useRight, useLeft = hasRight, (not hasRight) and hasLeft
			elseif style == "Left" then
				useLeft, useRight = hasLeft, (not hasLeft) and hasRight
			else
				useRight, useLeft = hasRight, hasLeft
			end
			if useRight then
				rightSwing = angle
			end
			if useLeft then
				leftSwing = angle
			end
			if not useRight and not useLeft then
				-- Armless Nightmares bite / headbutt instead.
				headPitch = -angle * 0.25
			end
			lunge = thrust
		end
	end

	-- Core
	local bob
	if floating then
		bob = math.sin(now * 2 + state.seed) * 0.35
	else
		bob = math.sin(now * 3 + state.seed) * 0.06 + math.abs(math.sin(state.walkPhase)) * 0.15 * move
	end
	-- the hit reaction: tilt the way the force went (local space: +Z = backward, +X = right),
	-- shoved a little that way, knees sagging under a heavy one; snaps in fast, springs back
	local f = state.flinch
	local snap = f > 0 and math.sin(math.min((1 - f) / 0.25, 1) * math.pi * 0.5) * f or 0
	local dir = state.flinchDir or Vector3.zero
	local force = (state.flinchHeavy and 0.6 or 0.32) * snap
	local hitPitch, hitRoll = dir.Z * force, -dir.X * force
	local hitShove = Vector3.new(dir.X, math.min(dir.Y, 0) - (state.flinchHeavy and 0.6 or 0), dir.Z) * 0.35 * snap

	local lean = -0.12 * move + hopLean + hitPitch
	local sink, collapse = hopCrouch, 0
	if defeated then
		sink = -1.2 * state.defeatT
		collapse = 1.1 * state.defeatT
	elseif staggered and model:GetAttribute("BossId") then
		-- BROKEN (Config.Bosses): the boss sags to its knees, hunched over, while it's open
		sink -= 1.4
		collapse = -0.55 -- (+X leans back; the stagger's own +0.25 is folded into this)
	end
	local wobble = staggered and math.sin(now * 28) * 0.18 or 0
	setTransform(motors.Joint_Core, CFrame.new(hitShove.X, bob + sink + ultimateLift + hitShove.Y, -0.7 * lunge + hitShove.Z) * CFrame.Angles(lean + collapse + (staggered and 0.25 or 0), 0, math.sin(state.walkPhase) * 0.05 * move + wobble + hitRoll))

	-- Head (whips further than the body on a hit)
	setTransform(motors.Joint_Head, CFrame.Angles(headPitch + hitPitch * 1.4 + math.sin(now * 0.9 + state.seed) * 0.04, headYaw + math.sin(now * 0.5 + state.seed) * 0.08, hitRoll * 1.6))

	-- the fighting stance: how far into it the body is (it comes up fast, and drops slowly)
	local bossId = model:GetAttribute("BossId")
	local bossMotion = bossId and BossMotion[bossId]
	local wantStance = model:GetAttribute("FightStance") == true and not defeated
	state.stance = (state.stance or 0) + ((wantStance and 1 or 0) - (state.stance or 0)) * math.min(1, dt * (wantStance and 9 or 4))
	local stance = state.stance

	-- Arms (a boss's own motion drives its limbs: BossMotion)
	local idleSway = math.sin(now * 1.6 + state.seed) * 0.06 * (1 - stance * 0.6)
	local walkSwing = math.sin(state.walkPhase) * 0.5 * move * (1 - stance * 0.85)
	if bossMotion then
		idleSway, walkSwing = 0, 0
	end
	setTransform(motors.Joint_RightArm, CFrame.Angles(rightSwing + idleSway + walkSwing, 0, 0))
	setTransform(motors.Joint_LeftArm, CFrame.Angles(leftSwing + idleSway - walkSwing, 0, 0))

	-- Legs (in the stance it's footwork: the feet step the way the body is really going, a
	-- shuffle to the side when it circles, not a walk)
	local stride = math.sin(state.walkPhase) * 0.6 * move * (1 - stance * 0.3)
	local forward, side = stride, 0
	if stance > 0.01 and speed > 0.5 then
		local localVelocity = root.CFrame:VectorToObjectSpace(velocity)
		local along, across = -localVelocity.Z / speed, localVelocity.X / speed
		forward = stride * (1 + (along - 1) * stance)
		side = stride * across * stance * 0.7
	end
	if bossMotion then
		forward, side, stride = 0, 0, 0
	end
	setTransform(motors.Sub_Legs_L, CFrame.Angles(forward, 0, side))
	setTransform(motors.Sub_Legs_R, CFrame.Angles(-forward, 0, -side))
	-- Quadruped trot: diagonal pairs move together.
	setTransform(motors.Sub_Legs_FL, CFrame.Angles(forward, 0, side))
	setTransform(motors.Sub_Legs_BR, CFrame.Angles(forward, 0, side))
	setTransform(motors.Sub_Legs_FR, CFrame.Angles(-forward, 0, -side))
	setTransform(motors.Sub_Legs_BL, CFrame.Angles(-forward, 0, -side))
	if floating then
		setTransform(motors.Joint_Legs, CFrame.Angles(math.sin(now * 3) * 0.1, 0, math.sin(now * 2.3) * 0.1))
	end

	-- Wings
	local flapSpeed = floating and 6 or (2.5 + move * 4)
	local flap = math.sin(now * flapSpeed + state.seed) * 0.3
	setTransform(motors.Sub_Back_R, CFrame.Angles(0, 0, flap))
	setTransform(motors.Sub_Back_L, CFrame.Angles(0, 0, -flap))

	-- Tail
	setTransform(motors.Joint_Tail, CFrame.Angles(0, math.sin(now * 2.2 + state.seed) * 0.25 + math.sin(state.walkPhase) * 0.2 * move, 0))

	-- (joints only clips and the layers below move: back to rest, so those layers add to a clean
	-- pose each frame rather than to their own last frame)
	setTransform(motors.Sub_RightArm_Fore, CFrame.identity)
	setTransform(motors.Sub_LeftArm_Fore, CFrame.identity)
	setTransform(motors.Sub_Head_Jaw, CFrame.identity)
	setTransform(motors.Knee_L, CFrame.identity)
	setTransform(motors.Knee_R, CFrame.identity)
	if not floating then
		setTransform(motors.Joint_Legs, CFrame.identity)
	end
	if bossMotion then
		bossMotion(state, motors, root, dt, now, speed, markerEvent)
	end
	applyStance(state, stance, now)
	local ringed = not bossId and CollectionService:HasTag(model, "Nightmare")
	-- (behind a guard it isn't slipping about: the stance is set)
	local wantGuard = ringed and model:GetAttribute("Guarding") == true and not defeated
	state.guardWeight = (state.guardWeight or 0) + ((wantGuard and 1 or 0) - (state.guardWeight or 0)) * math.min(1, dt * 16)
	if ringed then
		RingCraft.Apply(state, root, stance * (1 - state.guardWeight), dt, now, speed, velocity, markerEvent)
		applyGuard(state, state.guardWeight, now)
	end

	-- a keyframed attack overrides the joints it keys (the rest keep their procedural motion)
	local skipping = currentSkip
	currentSkip = nil
	if state.pose then
		applyPose(state, now, dt)
	end
	currentSkip = skipping
	applyFade(state, now)
	applyReaction(state, now)
	currentSkip = nil
	if ringed then
		RingCraft.Settle(state)
	end
end

------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------
-- A hit lands: the body snaps the way the blow's force travelled (`direction`, world
-- space; default straight back), the head whipping further than the torso, and a heavy
-- blow sags the knees. It springs back over ~0.3 s.
function NightmareAnimator:Flinch(model: Model?, direction: Vector3?, heavy: boolean?)
	local state = model and tracked[model]
	if not state then
		return
	end
	state.flinch = 1
	state.flinchHeavy = heavy == true
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then
		state.flinchDir = root.CFrame:VectorToObjectSpace(direction.Unit)
	else
		state.flinchDir = Vector3.new(0, 0, 1) -- pushed straight back
	end
end

-- A blow of a known kind lands (Config.Nightmare.Reactions): the body reacts to WHERE it was
-- hit: a jab rocks the head back, a hook whips it round, a body shot folds it up...
function NightmareAnimator:React(model: Model?, kind: string): boolean
	local state = model and tracked[model]
	if not state or not POSES.Reactions then
		return false
	end
	local set = model:GetAttribute("Archetype") == "Quadruped" and POSES.Reactions.Quadruped or POSES.Reactions.Biped
	local def = set[kind]
	if not def then
		return false
	end
	-- (a bigger body takes the same blow slower)
	local scale = model:GetAttribute("BossId") and 1.25 or 1
	state.react = { Def = def, Start = os.clock(), Scale = scale }
	return true
end

-- The attacker's clip holds on its contact frame for a moment: the blow has weight.
function NightmareAnimator:HitStop(model: Model?, time: number)
	local state = model and tracked[model]
	if state then
		state.hitStopUntil = os.clock() + time
	end
end

function NightmareAnimator:Start()
	-- the sculpted part meshes, loaded up front: a body showing up shouldn't be missing pieces
	-- for its first moments
	task.spawn(function()
		local meshes = Shared:FindFirstChild("Meshes")
		local templates = meshes and meshes:FindFirstChild("PartMeshes")
		if templates then
			pcall(ContentProvider.PreloadAsync, ContentProvider, templates:GetChildren())
		end
	end)

	for _, tag in { "Nightmare", "Enemy" } do
		for _, model in CollectionService:GetTagged(tag) do
			track(model)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(track)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(untrack)
	end

	RunService.PreSimulation:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local cameraPosition = camera.CFrame.Position
		local now = os.clock()
		-- Studio scrubbing: workspace attributes NMScrubAction = "Heavy", NMScrubTime = 0.45
		-- hold every Nightmare on that frame of its body plan's keyframed attack
		-- (NMScrubAction = "Lab" holds the pose in the NMPoseLab attribute (JSON), so a move
		-- can be tuned live from the command bar)
		local scrubAction, scrubTime = IS_STUDIO and Workspace:GetAttribute("NMScrubAction"), Workspace:GetAttribute("NMScrubTime")
		local labDef = nil
		if scrubAction == "Lab" then
			local source = Workspace:GetAttribute("NMPoseLab")
			if source ~= labCache.Source then
				labCache.Source = source
				local ok, decoded = pcall(HttpService.JSONDecode, HttpService, source or "")
				labCache.Def = ok and type(decoded) == "table" and decoded or nil
			end
			labDef = labCache.Def
		end
		for model, state in tracked do
			local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - cameraPosition).Magnitude <= CULL_DISTANCE then
				if type(scrubAction) == "string" and type(scrubTime) == "number" then
					local library = libraryFor(model)
					local def = labDef or (library and library[scrubAction]) or (POSES.Common and POSES.Common[scrubAction])
					if def then
						state.action = scrubAction
						state.pose = { Def = def, Start = now - scrubTime, Speed = 1, LastT = math.huge }
					end
				end
				animate(state, root, dt, now)
			end
		end
	end)
end

return NightmareAnimator
