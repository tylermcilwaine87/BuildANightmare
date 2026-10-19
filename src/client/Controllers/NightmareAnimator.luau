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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AnimationDefinitions = require(Shared:WaitForChild("AnimationDefinitions"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local POSES = require(script.Parent:WaitForChild("NightmarePoses"))
local BOSS_POSES = require(script.Parent:WaitForChild("BossPoses"))

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
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function angleAt(def, joint: string, t: number): (number, number, number)
	local keys = def.Keys
	local prev, nextKey = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i].T and t <= keys[i + 1].T then
			prev, nextKey = keys[i], keys[i + 1]
			break
		end
	end
	local a = prev[joint] or { 0, 0, 0 }
	local b = nextKey[joint] or { 0, 0, 0 }
	local span = nextKey.T - prev.T
	local k = span > 0 and smooth(math.clamp((t - prev.T) / span, 0, 1)) or 1
	return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

-- every joint a pose keys anywhere (+ which one carries a position)
local poseJoints = setmetatable({}, { __mode = "k" })
local function jointsOf(def)
	local joints = poseJoints[def]
	if not joints then
		joints = {}
		for _, key in def.Keys do
			for name in key do
				if name ~= "T" and not name:match("Pos$") then
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

function NightmareAnimator:PlayKeyframed(state)
	local model = state.model
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
			for _, marker in def.Markers or {} do
				track:GetMarkerReachedSignal(marker[2]):Once(function()
					markerEvent:Fire(model, state.action, marker[2])
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
local function applyPose(state, now: number)
	local pose = state.pose
	local def = pose.Def
	local t = (now - pose.Start) * pose.Speed
	for _, marker in def.Markers or {} do
		if marker[1] > pose.LastT and marker[1] <= t then
			markerEvent:Fire(state.model, state.action, marker[2])
		end
	end
	pose.LastT = t
	if t > def.Duration then
		state.pose = nil
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
		local style = ACTION_ARMS[action] or (abilityDef and ACTION_ARMS["Ability_" .. abilityDef.Type]) or "Both"
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
	end
	local wobble = staggered and math.sin(now * 28) * 0.18 or 0
	setTransform(motors.Joint_Core, CFrame.new(hitShove.X, bob + sink + ultimateLift + hitShove.Y, -0.7 * lunge + hitShove.Z) * CFrame.Angles(lean + collapse + (staggered and 0.25 or 0), 0, math.sin(state.walkPhase) * 0.05 * move + wobble + hitRoll))

	-- Head (whips further than the body on a hit)
	setTransform(motors.Joint_Head, CFrame.Angles(headPitch + hitPitch * 1.4 + math.sin(now * 0.9 + state.seed) * 0.04, headYaw + math.sin(now * 0.5 + state.seed) * 0.08, hitRoll * 1.6))

	-- Arms
	local idleSway = math.sin(now * 1.6 + state.seed) * 0.06
	local walkSwing = math.sin(state.walkPhase) * 0.5 * move
	setTransform(motors.Joint_RightArm, CFrame.Angles(rightSwing + idleSway + walkSwing, 0, 0))
	setTransform(motors.Joint_LeftArm, CFrame.Angles(leftSwing + idleSway - walkSwing, 0, 0))

	-- Legs
	local stride = math.sin(state.walkPhase) * 0.6 * move
	setTransform(motors.Sub_Legs_L, CFrame.Angles(stride, 0, 0))
	setTransform(motors.Sub_Legs_R, CFrame.Angles(-stride, 0, 0))
	-- Quadruped trot: diagonal pairs move together.
	setTransform(motors.Sub_Legs_FL, CFrame.Angles(stride, 0, 0))
	setTransform(motors.Sub_Legs_BR, CFrame.Angles(stride, 0, 0))
	setTransform(motors.Sub_Legs_FR, CFrame.Angles(-stride, 0, 0))
	setTransform(motors.Sub_Legs_BL, CFrame.Angles(-stride, 0, 0))
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

	-- a keyframed attack overrides the joints it keys (the rest keep their procedural motion)
	currentSkip = nil
	if state.pose then
		applyPose(state, now)
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

function NightmareAnimator:Start()
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
		local scrubAction, scrubTime = IS_STUDIO and Workspace:GetAttribute("NMScrubAction"), Workspace:GetAttribute("NMScrubTime")
		for model, state in tracked do
			local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - cameraPosition).Magnitude <= CULL_DISTANCE then
				if type(scrubAction) == "string" and type(scrubTime) == "number" then
					local library = libraryFor(model)
					local def = (library and library[scrubAction]) or (POSES.Common and POSES.Common[scrubAction])
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
