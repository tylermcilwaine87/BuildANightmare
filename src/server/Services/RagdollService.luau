--[[
	RagdollService  (ModuleScript)
	Location: ServerScriptService/Server/Services/RagdollService

	Realistic ragdoll knockdowns (Config.Ragdoll). A big HEAVY hit throws a Handler or a
	Nightmare off its feet with real physics, then it gets back up.

	What makes it look real:
	  * Anatomical joints: knees and elbows are HINGES that only bend the natural way; the
	    neck and waist barely move; shoulders and hips swing wide; wrists / ankles flex a
	    little (JOINTS below). Unknown joints (Nightmare parts) get a sensible default.
	  * Joint friction: every joint resists a little, like muscle, so limbs fall with weight
	    instead of flailing like rope.
	  * Body physics: neighbouring body parts don't collide with each other (no jitter),
	    limbs grip the floor (high friction, no bounce).
	  * The hit throws the body AWAY from the attacker and tips it over backwards (a spin
	    around the right axis), instead of a random tumble.
	  * It only gets back up once the body has settled (not mid-air), and the client plays
	    a face-down or face-up get-up to match how it landed.

	Works with both joint types: Motor6D (classic rigs, Nightmares) and AnimationConstraint
	(avatars with Roblox's joint upgrade). The joint holding the HumanoidRootPart stays.
	While down: the model's "Ragdolled" attribute is true (Nightmare AI pauses, Handlers
	can't attack or dive). Bosses (KnockbackImmune) only go down when CombatService's
	odd-time roll lets them (options.AllowImmune): they topple slowly and are stood back up
	on the floor at their full height.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Passives = require(Shared:WaitForChild("PassiveDefinitions"))

local RagdollService = {}

local CFG = Config.Ragdoll
local active = {} -- [Model] = record
local lastDown = setmetatable({}, { __mode = "k" }) -- [Model] = os.clock()

-- Anatomical limits (degrees) and friction (muscle resistance) per joint name.
-- Hinge: Lower/Upper around the joint's X axis (knee bends back: negative; elbow bends forward: positive).
local JOINTS = {
	Neck = { Type = "Ball", Cone = 30, Twist = 35, Friction = 18 },
	Waist = { Type = "Ball", Cone = 25, Twist = 25, Friction = 45 },
	LeftShoulder = { Type = "Ball", Cone = 95, Twist = 75, Friction = 5 },
	RightShoulder = { Type = "Ball", Cone = 95, Twist = 75, Friction = 5 },
	LeftElbow = { Type = "Hinge", Lower = 0, Upper = 140, Friction = 3 },
	RightElbow = { Type = "Hinge", Lower = 0, Upper = 140, Friction = 3 },
	LeftWrist = { Type = "Ball", Cone = 40, Twist = 30, Friction = 1 },
	RightWrist = { Type = "Ball", Cone = 40, Twist = 30, Friction = 1 },
	LeftHip = { Type = "Ball", Cone = 75, Twist = 35, Friction = 14 },
	RightHip = { Type = "Ball", Cone = 75, Twist = 35, Friction = 14 },
	LeftKnee = { Type = "Hinge", Lower = -140, Upper = 0, Friction = 6 },
	RightKnee = { Type = "Hinge", Lower = -140, Upper = 0, Friction = 6 },
	LeftAnkle = { Type = "Ball", Cone = 30, Twist = 20, Friction = 2 },
	RightAnkle = { Type = "Ball", Cone = 30, Twist = 20, Friction = 2 },
}
local DEFAULT_JOINT = { Type = "Ball", Cone = 55, Twist = 40, Friction = 10 }

local LIMB_PHYSICS = PhysicalProperties.new(0.9, 0.9, 0.02, 1, 1) -- density, friction, elasticity

function RagdollService:Init(services)
	self.Services = services
	self.PlayerFX = Net.Get("PlayerFX")
end

function RagdollService:IsRagdolled(model: Model): boolean
	return active[model] ~= nil
end

-- Throws a freshly ragdolled body as ONE object: every loose piece gets the launch velocity
-- plus the tumble (spin) around the root. Once the joints are physics constraints, each
-- limb is its own assembly, so pushing only the root would leave the body folding in place.
-- (The client does the same for its own character: HandlerAnimator.)
function RagdollService.Throw(model: Model, velocity: Vector3, spin: Vector3)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local center = root and root.Position or model:GetPivot().Position
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored and part.AssemblyRootPart == part then
			part.AssemblyLinearVelocity = velocity + spin:Cross(part.Position - center)
			part.AssemblyAngularVelocity = spin
		end
	end
end

-- Builds the physical joint for one rig joint (between attachments a0 and a1).
local function makeJoint(record, name: string, a0: Attachment, a1: Attachment)
	local spec = JOINTS[name] or DEFAULT_JOINT
	local constraint
	if spec.Type == "Hinge" then
		constraint = Instance.new("HingeConstraint")
		constraint.LimitsEnabled = true
		constraint.LowerAngle = spec.Lower
		constraint.UpperAngle = spec.Upper
		-- a weak motor holding still = friction in the joint
		constraint.ActuatorType = Enum.ActuatorType.Motor
		constraint.AngularVelocity = 0
		constraint.MotorMaxTorque = spec.Friction * 40
	else
		constraint = Instance.new("BallSocketConstraint")
		constraint.LimitsEnabled = true
		constraint.UpperAngle = spec.Cone
		constraint.TwistLimitsEnabled = true
		constraint.TwistLowerAngle = -spec.Twist
		constraint.TwistUpperAngle = spec.Twist
		constraint.MaxFrictionTorque = spec.Friction * 40
	end
	constraint.Name = "RagdollJoint"
	constraint.Attachment0 = a0
	constraint.Attachment1 = a1
	constraint.Parent = a0.Parent
	table.insert(record.Created, constraint)
	-- the two body parts at a joint overlap: never let them push each other (jitter)
	local noCollide = Instance.new("NoCollisionConstraint")
	noCollide.Part0 = a0.Parent :: BasePart
	noCollide.Part1 = a1.Parent :: BasePart
	noCollide.Parent = a0.Parent
	table.insert(record.Created, noCollide)
end

local function restore(model: Model, record)
	if active[model] ~= record then
		return
	end
	active[model] = nil
	for _, item in record.Created do
		if item.Parent then
			item:Destroy()
		end
	end
	for joint in record.Joints do
		if joint.Parent then
			joint.Enabled = true
		end
	end
	for part, saved in record.Parts do
		if part.Parent then
			part.CanCollide = saved.CanCollide
			part.CustomPhysicalProperties = saved.Physics
		end
	end
	if not model.Parent then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
	-- Server-owned bodies (Nightmares) are stood back up here; a Handler's client stands
	-- itself up (its Humanoid gets up as soon as PlatformStand ends).
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and not Players:GetPlayerFromCharacter(model) and humanoid and humanoid.Health > 0 then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.zAxis
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		-- stand it up ON the floor beneath it at its proper height (a boss's hips are many
		-- studs up: lifting it a fixed amount would leave it half in the ground)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { model }
		local hit = workspace:Raycast(root.Position + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
		local standY = hit and (hit.Position.Y + humanoid.HipHeight + root.Size.Y / 2 + 0.2) or (root.Position.Y + 1.5)
		local at = Vector3.new(root.Position.X, standY, root.Position.Z)
		model:PivotTo(CFrame.lookAt(at, at + flat))
	end
	model:SetAttribute("Ragdolled", nil)
end

-- Gets up once the body has (mostly) stopped moving, so nobody stands up mid-air.
local function restoreWhenSettled(model: Model, record, root: BasePart)
	local deadline = os.clock() + 2
	while active[model] == record and root.Parent and os.clock() < deadline do
		if root.AssemblyLinearVelocity.Magnitude < 4 then
			break
		end
		task.wait(0.15)
	end
	restore(model, record)
end

-- Knocks `model` down. `direction` = flat direction of the hit (away from the attacker),
-- `throw` = launch velocity for a Handler (client-owned; Nightmares were already thrown by
-- CombatService's knockback). Returns true if it happened.
-- options: AllowImmune (a boss, floored by CombatService's odd-time roll), SpinScale (how
-- fast it tips over: a huge body topples slowly), Flip (rad/s: a leg sweep's heels-over-
-- head rotation instead of the usual tip-over).
function RagdollService:Ragdoll(model: Model, throw: Vector3?, direction: Vector3?, duration: number?, options): boolean
	if active[model] or (model:GetAttribute("KnockbackImmune") and not (options and options.AllowImmune)) then
		return false
	end
	if Passives.Has(model, "Hover") then
		return false -- (passive) it just drifts with the blow: never floored
	end
	local now = os.clock()
	if lastDown[model] and now - lastDown[model] < CFG.Cooldown and not (options and options.IgnoreCooldown) then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or root.Anchored then
		return false
	end
	lastDown[model] = now

	local record = { Joints = {}, Parts = {}, Created = {} }
	for _, joint in model:GetDescendants() do
		if joint:IsA("AnimationConstraint") and joint.Enabled and joint.Attachment0 and joint.Attachment1 then
			-- avatars with Roblox's joint upgrade: reuse the joint's own attachments
			local a0, a1 = joint.Attachment0, joint.Attachment1
			if a0.Parent ~= root and a1.Parent ~= root and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
				makeJoint(record, joint.Name, a0, a1)
				record.Joints[joint] = true
				joint.Enabled = false
			end
		elseif joint:IsA("Motor6D") and joint.Enabled and joint.Part0 and joint.Part1 and joint.Part0 ~= root and joint.Part1 ~= root then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = joint.C0
			a0.Parent = joint.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = joint.C1
			a1.Parent = joint.Part1
			table.insert(record.Created, a0)
			table.insert(record.Created, a1)
			makeJoint(record, joint.Name, a0, a1)
			record.Joints[joint] = true
			joint.Enabled = false
		end
	end
	for _, part in model:GetDescendants() do
		local accessory = part:FindFirstAncestor("HeldWeapon") or part:FindFirstAncestor("FistRightHand") or part:FindFirstAncestor("FistLeftHand")
		if part:IsA("BasePart") and part ~= root and (part.Transparency < 1 or part:GetAttribute("Gloved")) and not accessory then
			record.Parts[part] = { CanCollide = part.CanCollide, Physics = part.CustomPhysicalProperties }
			part.CanCollide = true
			part.CustomPhysicalProperties = LIMB_PHYSICS
		end
	end
	humanoid.PlatformStand = true
	model:SetAttribute("Ragdolled", true)
	active[model] = record

	-- tip over backwards, away from the hit (head goes the way the hit pushes)
	local dir = direction and Vector3.new(direction.X, 0, direction.Z)
	dir = dir and dir.Magnitude > 0.01 and dir.Unit or nil
	-- (options.Flip: a swept body rotates much faster, heels over head)
	local spin = dir and Vector3.yAxis:Cross(dir) * (options and options.Flip or 7) * (options and options.SpinScale or 1) or nil

	local length = duration or CFG.Duration
	if Passives.Has(model, "Bouncy") then
		length *= Passives.ById.Bouncy.DurationMultiplier -- (passive) springs back up
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		self.PlayerFX:FireClient(player, "Ragdoll", { Velocity = throw or Vector3.zero, Spin = spin, Duration = length })
	elseif root:GetNetworkOwner() == nil then
		RagdollService.Throw(model, throw or root.AssemblyLinearVelocity, spin or Vector3.zero)
	elseif model:GetAttribute("PossessedBy") and root:GetNetworkOwner().UserId == model:GetAttribute("PossessedBy") then
		-- a Nightmare its player is driving (NIGHTMARE UNDERGROUND): their client simulates
		-- it, so the throw happens there
		self.Services.PossessionService:AllowBurst(model, length + 0.5)
		self.PlayerFX:FireClient(root:GetNetworkOwner(), "BodyRagdoll", { Model = model, Velocity = throw or Vector3.zero, Spin = spin or Vector3.zero })
	end
	task.delay(length, restoreWhenSettled, model, record, root)
	return true
end

function RagdollService:Start()
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		if character then
			active[character] = nil
		end
	end)
end

return RagdollService
