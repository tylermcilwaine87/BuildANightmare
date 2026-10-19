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

local NightmareAnimator = {}

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
	table.insert(state.connections, model:GetAttributeChangedSignal("ActionSeq"):Connect(function()
		state.action = model:GetAttribute("ActionName")
		state.windup = model:GetAttribute("ActionWindup") or 0.25
		state.duration = model:GetAttribute("ActionDuration") or 0.6
		state.actionStart = os.clock()
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

local function setTransform(motor: Motor6D?, cframe: CFrame)
	if motor then
		motor.Transform = cframe
	end
end

------------------------------------------------------------------------------------------
-- Per-frame animation
------------------------------------------------------------------------------------------
local function animate(state, root: BasePart, dt: number, now: number)
	local model = state.model
	local motors = state.motors

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

		local style = ACTION_ARMS[action] or "Both"
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
		for model, state in tracked do
			local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - cameraPosition).Magnitude <= CULL_DISTANCE then
				animate(state, root, dt, now)
			end
		end
	end)
end

return NightmareAnimator
