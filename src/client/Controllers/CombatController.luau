--[[
	CombatController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController

	Client side of combat. It only REQUESTS actions; the server decides outcomes.
	  * Attack / Kick buttons -> MeleeController (punch & kick combos, weapons)
	  * Dive (Shift), Step back (X) and the counter window after it, Guard
	  * Target selection for "sic 'em": the living enemy best aligned with the camera
	  * Nightmare commands: Attack(target) / Follow / Retreat / ToggleSummon
	  * Red outline Highlight on the focused target while the Attack command is active
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

local CombatController = {}

local localPlayer = Players.LocalPlayer
local TARGET_RANGE = 90

local controllers
local combatAction: RemoteEvent
local nightmareCommand: RemoteEvent
local guarding = false
local currentTarget: Model? = nil
local targetHighlight: Highlight? = nil

function CombatController:Init(registry)
	controllers = registry
	combatAction = Net.Get("CombatAction")
	nightmareCommand = Net.Get("NightmareCommand")
end

local function isAlive(model: Model?): boolean
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and not model:GetAttribute("Defeated")
end

function CombatController:SetTarget(model: Model?)
	currentTarget = model
	if targetHighlight then
		targetHighlight:Destroy()
		targetHighlight = nil
	end
	if model then
		targetHighlight = Instance.new("Highlight")
		targetHighlight.FillTransparency = 1
		targetHighlight.OutlineColor = Color3.fromRGB(255, 70, 70)
		targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		targetHighlight.Adornee = model
		targetHighlight.Parent = Workspace:FindFirstChild("ClientEffects") or Workspace
	end
end

function CombatController:GetTarget(): Model?
	return currentTarget
end

function CombatController:FindBestTarget(): Model?
	local character = localPlayer.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not myRoot or not camera then
		return nil
	end
	local cameraLook = camera.CFrame.LookVector

	local best, bestScore = nil, -math.huge
	local candidates = CollectionService:GetTagged("Enemy")
	for _, model in controllers.PvPController:GetOpponentModels() do
		table.insert(candidates, model)
	end
	for _, enemy in candidates do
		local root = enemy:FindFirstChild("HumanoidRootPart")
		if root and isAlive(enemy) then
			local distance = (root.Position - myRoot.Position).Magnitude
			if distance <= TARGET_RANGE then
				local toEnemy = (root.Position - camera.CFrame.Position).Unit
				local alignment = cameraLook:Dot(toEnemy)
				if alignment > 0.35 then
					-- (distance counts for a lot: an enemy right in front of you beats one
					-- lined up 50 studs behind it; measured, the old weighting picked a
					-- Scrapling 57 studs off over a dummy 6 studs ahead)
					local score = alignment * 2 - distance / 25
					if score > bestScore then
						best, bestScore = enemy, score
					end
				end
			end
		end
	end
	return best
end

-- A quick flat slide of your own character (the step back; MeleeController has its own).
local function slide(root: BasePart, direction: Vector3, distance: number, duration: number)
	local attachment = root:FindFirstChild("RootAttachment")
	if not attachment then
		return
	end
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.MaxForce = 1e5
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (distance / duration)
	mover.Parent = root
	task.delay(duration, function()
		mover:Destroy()
	end)
end

local lastStepBack = -math.huge
local counterUsed = true

-- True (once) if a punch / kick right now should be a COUNTER: a step back happened
-- within the counter window and hasn't been cashed in yet. MeleeController asks.
function CombatController:TakeCounter(): boolean
	if counterUsed or os.clock() - lastStepBack > Config.Handler.StepBack.CounterWindow then
		return false
	end
	counterUsed = true
	return true
end

-- Attack button (LMB / R2 / ATTACK): punches, or the equipped weapon (MeleeController).
function CombatController:BasicAttack()
	if guarding then
		return
	end
	controllers.MeleeController:Press("P")
end

-- Kick button (right-click / gamepad X / KICK).
function CombatController:Kick()
	if guarding then
		return
	end
	controllers.MeleeController:Press("K")
end

-- STEP BACK (X, or Shift while moving backwards): a quick hop straight back, still facing
-- the fight. Punch or kick straight after it to COUNTER (TakeCounter).
function CombatController:StepBack()
	if (controllers.WorkshopController:IsOpen() or controllers.GymController:IsActive()) then
		return
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or character:GetAttribute("Ragdolled") then
		return
	end
	local cfg = Config.Handler.StepBack
	local now = os.clock()
	if now - lastStepBack < cfg.Cooldown or (character:GetAttribute("Stamina") or 0) < cfg.StaminaCost or character:GetAttribute("GuardBroken") then
		return
	end
	lastStepBack = now
	counterUsed = false
	controllers.MeleeController:Interrupt() -- cancels the strike you were in

	-- back = away from whatever you're fighting (lock-on target), else toward the camera
	local target = controllers.LockOnController:GetTarget()
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	local away = (targetRoot and Util.FlatUnit(root.Position - targetRoot.Position))
		or (camera and Util.FlatUnit(-camera.CFrame.LookVector))
		or Util.FlatUnit(-root.CFrame.LookVector)
		or -Vector3.zAxis
	root.CFrame = CFrame.lookAt(root.Position, root.Position - away)
	slide(root, away, cfg.Distance, cfg.Duration)
	-- keep facing the fight while sliding (holding S would otherwise turn you around)
	if humanoid.AutoRotate then
		humanoid.AutoRotate = false
		task.delay(cfg.Duration + 0.1, function()
			if humanoid.Parent and not controllers.LockOnController:IsLocked() then
				humanoid.AutoRotate = true
			end
		end)
	end
	controllers.HandlerAnimator:Play("StepBack")
	controllers.EffectsController:Afterimage(character)
	combatAction:FireServer("StepBack")
end

-- Dodge = the DIVE: a low, fast leap in the direction you're moving (forward if you're
-- standing still). The client moves its own character instantly (responsive); the server
-- decides stamina, cooldown and invulnerability (i-frames cover the airborne part).
local lastDodge = -math.huge
function CombatController:Dodge()
	if (controllers.WorkshopController:IsOpen() or controllers.GymController:IsActive()) then
		return
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local attachment = root and root:FindFirstChild("RootAttachment")
	if not humanoid or humanoid.Health <= 0 or not attachment or character:GetAttribute("Ragdolled") then
		return
	end
	-- Pulling BACK while pressing dodge = the step back instead of a dive (that's how
	-- controllers and phones get it).
	local moving = Util.FlatUnit(humanoid.MoveDirection)
	local camera = Workspace.CurrentCamera
	local lockTarget = controllers.LockOnController:GetTarget()
	local lockRoot = lockTarget and lockTarget:FindFirstChild("HumanoidRootPart")
	local forward = lockRoot and Util.FlatUnit(lockRoot.Position - root.Position) or (camera and Util.FlatUnit(camera.CFrame.LookVector))
	if moving and forward and moving:Dot(forward) < -0.6 then
		self:StepBack()
		return
	end
	local cfg = Config.Handler.Dodge
	local now = os.clock()
	if now - lastDodge < cfg.Cooldown or (character:GetAttribute("Stamina") or 0) < cfg.StaminaCost or character:GetAttribute("GuardBroken") then
		return
	end
	lastDodge = now
	controllers.MeleeController:Interrupt() -- cancels the strike you were in

	local direction = Util.FlatUnit(humanoid.MoveDirection) or Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
	-- Facing someone and dodging sideways: the SIDE DIVE (stay facing them, roll over the
	-- shoulder). Otherwise the forward dive roll, facing the way you go.
	local slot, motion = "Dive", cfg
	local opponent = lockRoot or self:NearestOpponentAhead(root)
	if opponent then
		local toward = Util.FlatUnit(opponent.Position - root.Position)
		local side = toward and toward:Cross(Vector3.yAxis) -- (points to your right)
		local amount = side and direction:Dot(side) or 0
		if math.abs(amount) > 0.55 then
			slot = amount > 0 and "DodgeRight" or "DodgeLeft"
			motion = cfg.Side
			direction = side * math.sign(amount)
			root.CFrame = CFrame.lookAt(root.Position, root.Position + toward)
		end
	end
	if slot == "Dive" then
		-- face the dive, launch upward a little, and carry forward for the dive's duration
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	end
	-- The body keeps its facing until it's back up: "Diving" tells lock-on not to turn it,
	-- and AutoRotate is held off.
	character:SetAttribute("Diving", true)
	humanoid.AutoRotate = false
	task.delay(motion.Duration + motion.RollDuration, function()
		character:SetAttribute("Diving", nil)
		if humanoid.Parent and not controllers.LockOnController:IsLocked() then
			humanoid.AutoRotate = true
		end
	end)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = direction * motion.Speed + Vector3.new(0, motion.Hop, 0)
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.MaxForce = 1e5
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * motion.Speed
	mover.Parent = root
	-- then the roll: slower, low to the floor, back on your feet at the end
	local baseHip = humanoid:GetAttribute("BaseHipHeight") or humanoid.HipHeight
	humanoid:SetAttribute("BaseHipHeight", baseHip)
	task.delay(motion.Duration, function()
		if mover.Parent then
			mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * motion.RollSpeed
		end
		if humanoid.Parent then
			humanoid.HipHeight = baseHip * 0.7
		end
	end)
	task.delay(motion.Duration + motion.RollDuration, function()
		mover:Destroy()
		if humanoid.Parent then
			humanoid.HipHeight = baseHip
		end
	end)

	-- a side dive circles AROUND them: the body stays turned toward them and the dive keeps
	-- steering sideways relative to them, so you come out of the roll squared up and still
	-- in range to counter (instead of sliding off in a straight line)
	if motion == cfg.Side and opponent then
		local startTime = os.clock()
		local sideSign = direction:Dot(root.CFrame.RightVector) >= 0 and 1 or -1
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local elapsed = os.clock() - startTime
			if elapsed > motion.Duration + motion.RollDuration + 0.15 or not opponent.Parent or not root.Parent then
				connection:Disconnect()
				return
			end
			local at = Vector3.new(opponent.Position.X, root.Position.Y, opponent.Position.Z)
			if (at - root.Position).Magnitude > 0.5 then
				root.CFrame = CFrame.lookAt(root.Position, at)
			end
			if mover.Parent then
				local speed = elapsed < motion.Duration and motion.Speed or motion.RollSpeed
				local side = root.CFrame.RightVector * sideSign
				mover.PlaneVelocity = Vector2.new(side.X, side.Z) * speed
			end
		end)
	end

	controllers.HandlerAnimator:Play(slot)
	controllers.EffectsController:Afterimage(character)
	combatAction:FireServer("Dodge", direction, slot)
end

-- The closest enemy / opposing body within 14 studs in front of you (60 degree cone around
-- where your CAMERA looks: you aim with the camera, and your body turns to face wherever
-- you walk), or nil: "facing someone" for the side dodge when you aren't locked on.
function CombatController:NearestOpponentAhead(root: BasePart): BasePart?
	local best, bestDistance = nil, 14
	local camera = Workspace.CurrentCamera
	local look = Util.FlatUnit(camera and camera.CFrame.LookVector or root.CFrame.LookVector)
	for _, tag in { "Enemy", "Nightmare" } do
		for _, model in CollectionService:GetTagged(tag) do
			local other = model:FindFirstChild("HumanoidRootPart")
			if other and model ~= localPlayer.Character and model:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
				local offset = other.Position - root.Position
				local flat = Util.FlatUnit(offset)
				local distance = offset.Magnitude
				if flat and look and distance < bestDistance and flat:Dot(look) > 0.5 then
					best, bestDistance = other, distance
				end
			end
		end
	end
	return best
end

function CombatController:SetGuard(wanted: boolean)
	if wanted and (controllers.WorkshopController:IsOpen() or controllers.GymController:IsActive()) then
		return
	end
	if guarding == wanted then
		return
	end
	guarding = wanted
	-- (you're holding it up the instant you press: your own screen doesn't wait for the server)
	local character = localPlayer.Character
	if character then
		character:SetAttribute("GuardHeld", wanted or nil)
	end
	if controllers.PossessionController:IsPossessing() then
		combatAction:FireServer("NM_Guard", wanted)
	else
		combatAction:FireServer("Guard", wanted)
	end
	self:FaceWhileGuarding(wanted)
end

-- The nearest body that could hit you, any direction: enemies, others' Nightmares, and in a duel
-- the other Handler.
function CombatController:NearestThreat(root: BasePart): BasePart?
	local best, bestDistance = nil, 24
	local function consider(model: Model)
		local other = model:FindFirstChild("HumanoidRootPart")
		if other and other ~= root and model ~= localPlayer.Character and model:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
			local distance = (other.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	for _, tag in { "Enemy", "Nightmare" } do
		for _, model in CollectionService:GetTagged(tag) do
			consider(model)
		end
	end
	if controllers.PvPController:IsInMatch() then
		for _, model in controllers.PvPController:GetOpponentModels() do
			consider(model)
		end
	end
	return best
end

-- A guard only covers what's in front, so a held guard keeps turning to the nearest threat: you
-- can walk backwards and keep it up. (Locked on, the lock already does this.)
local guardTurn: RBXScriptConnection? = nil
function CombatController:FaceWhileGuarding(wanted: boolean)
	if guardTurn then
		guardTurn:Disconnect()
		guardTurn = nil
	end
	local body = controllers.PossessionController:GetModel() or localPlayer.Character
	local humanoid = body and body:FindFirstChildOfClass("Humanoid")
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	local locked = controllers.LockOnController:GetTarget() ~= nil
	if not wanted then
		if not locked then
			humanoid.AutoRotate = true
		end
		return
	end
	if locked then
		return
	end
	guardTurn = RunService.RenderStepped:Connect(function(dt)
		local threat = root.Parent and self:NearestThreat(root)
		humanoid.AutoRotate = threat == nil
		if threat then
			local at = Vector3.new(threat.Position.X, root.Position.Y, threat.Position.Z)
			if (at - root.Position).Magnitude > 0.5 then
				root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, at), math.min(1, dt * 14))
			end
		end
	end)
end

function CombatController:IsGuarding(): boolean
	return guarding
end

function CombatController:UseAbility(slot: number)
	if (controllers.WorkshopController:IsOpen() or controllers.GymController:IsActive()) then
		return
	end
	local nightmare = controllers.ClientState:GetMyNightmare()
	if not nightmare then
		controllers.HUDController:Toast("Your Nightmare isn't here!", nil, 1.5)
		return
	end
	local abilityId = nightmare:GetAttribute(("Ability%dId"):format(slot))
	if not abilityId or abilityId == "" then
		controllers.HUDController:Toast("No ability in that slot — equip a part with one.", nil, 2)
		return
	end
	local readyAt = nightmare:GetAttribute(("Ability%dReadyAt"):format(slot)) or 0
	if Workspace:GetServerTimeNow() < readyAt then
		return
	end
	-- If nothing is targeted, aim the ability at whatever we're looking at.
	if not currentTarget then
		local target = self:FindBestTarget()
		if target then
			self:SetTarget(target)
			nightmareCommand:FireServer("Attack", target)
		end
	end
	combatAction:FireServer("Ability", slot)
end

function CombatController:CommandAttackTarget()
	local target = self:FindBestTarget()
	if not target then
		controllers.HUDController:Toast("No enemy in sight — look toward one.", nil, 1.5)
		return
	end
	if not controllers.ClientState:GetMyNightmare() then
		controllers.HUDController:Toast("Your Nightmare isn't here!", nil, 1.5)
		return
	end
	self:SetTarget(target)
	nightmareCommand:FireServer("Attack", target)
end

function CombatController:CommandFollow()
	self:CommandDefend()
end

function CombatController:CommandDefend()
	self:SetTarget(nil)
	nightmareCommand:FireServer("Defend")
end

function CombatController:CommandAggressive()
	self:SetTarget(nil)
	nightmareCommand:FireServer("Aggressive")
end

-- T: flip between DEFEND and AGGRESSIVE.
function CombatController:ToggleStance()
	local nightmare = controllers.ClientState:GetMyNightmare()
	if nightmare and nightmare:GetAttribute("Command") == "Aggressive" then
		self:CommandDefend()
	else
		self:CommandAggressive()
	end
end

function CombatController:Ultimate()
	if (controllers.WorkshopController:IsOpen() or controllers.GymController:IsActive()) then
		return
	end
	local nightmare = controllers.ClientState:GetMyNightmare()
	if not nightmare then
		return
	end
	local ultimateId = nightmare:GetAttribute("UltimateId")
	if not ultimateId or ultimateId == "" then
		controllers.HUDController:Toast("This build has no Ultimate. Cores (and Void Wings) grant one.", nil, 2)
		return
	end
	local energy = nightmare:GetAttribute("UltimateEnergy") or 0
	if energy < Config.Ultimate.EnergyMax then
		controllers.HUDController:Toast(("Ultimate charging: %d%%"):format(energy), nil, 1.5)
		return
	end
	combatAction:FireServer("Ultimate")
end

function CombatController:CommandRetreat()
	self:SetTarget(nil)
	nightmareCommand:FireServer("Retreat")
end

function CombatController:ToggleSummon()
	nightmareCommand:FireServer("ToggleSummon")
end

function CombatController:Start()
	-- Drop the highlight once the focused target dies or the order changes.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.2 or not currentTarget then
			return
		end
		elapsed = 0
		local nightmare = controllers.ClientState:GetMyNightmare()
		local commandActive = nightmare and nightmare:GetAttribute("Command") == "Attack"
		if controllers.PossessionController:IsPossessing() then
			commandActive = true -- keep the highlight while you're driving
		end
		if not isAlive(currentTarget) or (nightmare and not commandActive) then
			self:SetTarget(nil)
		end
	end)
end

return CombatController
