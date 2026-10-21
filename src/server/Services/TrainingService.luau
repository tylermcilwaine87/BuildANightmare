--[[
	TrainingService  (ModuleScript)
	Location: ServerScriptService/Server/Services/TrainingService

	Spawns and runs the Training Arena enemies (placeholder geometry, built in code):

	  Training Dummy  stationary, 400 HP, fully heals 5s after the last hit, respawns
	  Scrapling       small hostile robot: chases nearby Handlers/Nightmares, telegraphs a
	                  claw swipe for 0.7s (red floor marker on clients), turning to track
	                  its target (capped speed), then commits, lunges in and hits. Gives
	                  Phase 1 a real "defeat a training enemy" target that fights back.

	Enemies are tagged "Enemy" and expose attributes the client uses:
	  DisplayName, Defence, ActionName/ActionWindup/ActionDuration/ActionSeq,
	  TelegraphLength, TelegraphWidth, Defeated
	Phase 2's BossService reuses this enemy contract (tag + attributes + CombatService).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local TrainingService = {}

local RGB = Color3.fromRGB
local Mat = Enum.Material
local V = Vector3.new

local enemies = {} -- [Model] = record

------------------------------------------------------------------------------------------
-- Geometry helpers
------------------------------------------------------------------------------------------
local function helper(model: Model, name: string, cframe: CFrame): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = V(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = cframe
	p.Parent = model
	return p
end

local function motor(name: string, part0: BasePart, part1: BasePart, jointWorld: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(jointWorld)
	m.C1 = part1.CFrame:ToObjectSpace(jointWorld)
	m.Parent = part0
end

local function visual(model: Model, attachTo: BasePart, shape: string, size: Vector3, cframe: CFrame, color: Color3, material)
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = Enum.PartType[shape]
		p = part
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Mat.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	local w = Instance.new("Weld")
	w.Part0 = attachTo
	w.Part1 = p
	w.C0 = attachTo.CFrame:ToObjectSpace(cframe)
	w.Parent = p
	return p
end

local function makeRoot(model: Model, size: Vector3, cframe: CFrame, anchored: boolean): BasePart
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = size
	root.CFrame = cframe
	root.Transparency = 1
	root.Anchored = anchored
	root.CanCollide = true
	root.CanQuery = true
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local function makeHumanoid(model: Model, maxHealth: number, hipHeight: number, walkSpeed: number): Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = walkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Seated } do
		humanoid:SetStateEnabled(state, false)
	end
	return humanoid
end

------------------------------------------------------------------------------------------
-- Enemy builders. `ground` is a point on the floor; `facing` a point to look toward.
------------------------------------------------------------------------------------------
local function buildDummy(ground: Vector3, facing: Vector3): (Model, Humanoid)
	local cfg = Config.Enemies.TrainingDummy
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"

	local baseCF = CFrame.lookAt(ground, V(facing.X, ground.Y, facing.Z))
	local root = makeRoot(model, V(3, 5, 2), baseCF * CFrame.new(0, 2.5, 0), true)
	-- Joint at the base so hits make the whole dummy wobble from the floor.
	local core = helper(model, "Core_Root", baseCF)
	motor("Joint_Core", root, core, baseCF)

	local wood, burlap = RGB(90, 64, 42), RGB(196, 166, 115)
	visual(model, core, "Block", V(2.6, 0.4, 2.6), baseCF * CFrame.new(0, 0.2, 0), wood, Mat.WoodPlanks)
	visual(model, core, "Cylinder", V(3.6, 0.5, 0.5), baseCF * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.rad(90)), wood, Mat.Wood)
	visual(model, core, "Block", V(2.2, 2.2, 1.2), baseCF * CFrame.new(0, 3.3, 0), burlap, Mat.Fabric)
	visual(model, core, "Ball", V(1.5, 1.5, 1.5), baseCF * CFrame.new(0, 5.0, 0), burlap, Mat.Fabric)
	visual(model, core, "Cylinder", V(0.15, 1.7, 1.7), baseCF * CFrame.new(0, 3.3, -0.62) * CFrame.Angles(0, math.rad(90), 0), RGB(200, 50, 50))
	visual(model, core, "Cylinder", V(0.2, 0.8, 0.8), baseCF * CFrame.new(0, 3.3, -0.66) * CFrame.Angles(0, math.rad(90), 0), RGB(240, 240, 240))

	local humanoid = makeHumanoid(model, cfg.MaxHealth, 0, 0)
	model:SetAttribute("DisplayName", cfg.DisplayName)
	model:SetAttribute("Defence", cfg.Defence)
	model:SetAttribute("EnemyType", "TrainingDummy")
	model:SetAttribute("ActionSeq", 0)
	return model, humanoid
end

local function buildScrapling(ground: Vector3, facing: Vector3): (Model, Humanoid)
	local cfg = Config.Enemies.Scrapling
	local model = Instance.new("Model")
	model.Name = "Scrapling"

	local hipHeight = 0.75
	local rootSize = V(3, 3, 2.5)
	local rootPos = ground + V(0, hipHeight + rootSize.Y / 2 + 0.2, 0)
	local rootCF = CFrame.lookAt(rootPos, V(facing.X, rootPos.Y, facing.Z))
	local root = makeRoot(model, rootSize, rootCF, false)
	local core = helper(model, "Core_Root", rootCF)
	motor("Joint_Core", root, core, rootCF)

	local rust, metal, dark, glow = RGB(120, 95, 80), RGB(150, 150, 160), RGB(55, 55, 62), RGB(255, 70, 50)
	visual(model, core, "Block", V(2.6, 2, 2), rootCF * CFrame.new(0, 0.1, 0), rust, Mat.CorrodedMetal)
	visual(model, core, "Block", V(2.8, 0.4, 2.2), rootCF * CFrame.new(0, 1.1, 0), metal, Mat.Metal)
	visual(model, core, "Ball", V(1, 1, 1), rootCF * CFrame.new(0, 0.4, -1.0), glow, Mat.Neon)
	visual(model, core, "Cylinder", V(1, 0.12, 0.12), rootCF * CFrame.new(0.6, 1.8, 0) * CFrame.Angles(0, 0, math.rad(90)), dark, Mat.Metal)
	visual(model, core, "Ball", V(0.35, 0.35, 0.35), rootCF * CFrame.new(0.6, 2.35, 0), glow, Mat.Neon)
	for _, side in { -1, 1 } do
		visual(model, core, "Block", V(0.6, 1.3, 0.6), rootCF * CFrame.new(0.7 * side, -1.4, 0), dark, Mat.Metal)
		visual(model, core, "Block", V(0.9, 0.3, 1.1), rootCF * CFrame.new(0.7 * side, -2.1, -0.1), dark, Mat.Metal)
	end
	visual(model, core, "Block", V(0.5, 1.4, 0.5), rootCF * CFrame.new(-1.55, -0.3, 0) * CFrame.Angles(0, 0, math.rad(-10)), rust, Mat.CorrodedMetal)

	-- Animated right claw (client animator swings Joint_RightArm on "Swipe").
	local shoulder = rootCF * CFrame.new(1.4, 0.5, 0)
	local arm = helper(model, "RightArm_Root", shoulder)
	motor("Joint_RightArm", core, arm, shoulder)
	visual(model, arm, "Block", V(0.5, 1.5, 0.5), shoulder * CFrame.new(0.15, -0.75, 0), rust, Mat.CorrodedMetal)
	visual(model, arm, "Wedge", V(0.6, 0.6, 0.9), shoulder * CFrame.new(0.15, -1.7, -0.2), metal, Mat.Metal)

	local humanoid = makeHumanoid(model, cfg.MaxHealth, hipHeight, cfg.WalkSpeed)
	model:SetAttribute("DisplayName", cfg.DisplayName)
	model:SetAttribute("Defence", cfg.Defence)
	model:SetAttribute("EnemyType", "Scrapling")
	model:SetAttribute("ActionSeq", 0)
	model:SetAttribute("TelegraphLength", cfg.AttackRange)
	model:SetAttribute("TelegraphWidth", cfg.AttackWidth)
	return model, humanoid
end

local BUILDERS = {
	TrainingDummy = buildDummy,
	Scrapling = buildScrapling,
}

------------------------------------------------------------------------------------------
-- Spawning
------------------------------------------------------------------------------------------
function TrainingService:SpawnEnemy(placement)
	local model, humanoid = BUILDERS[placement.Kind](placement.Ground, placement.Facing)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Enemies"
		end
	end
	CollectionService:AddTag(model, "Enemy")
	model.Parent = Workspace:FindFirstChild("Enemies") or Workspace

	local root = model.PrimaryPart
	if not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end

	local record = {
		model = model,
		humanoid = humanoid,
		root = root,
		placement = placement,
		kind = placement.Kind,
		busyUntil = 0,
		nextAttack = 0,
		lastHit = 0,
	}
	enemies[model] = record

	humanoid.Died:Connect(function()
		model:SetAttribute("Defeated", true)
		enemies[model] = nil
		task.delay(1.5, function()
			if model.Parent then
				model:Destroy()
			end
		end)
		task.delay(Config.Enemies[placement.Kind].RespawnDelay, function()
			self:SpawnEnemy(placement)
		end)
	end)
end

------------------------------------------------------------------------------------------
-- Scrapling AI
------------------------------------------------------------------------------------------
local function findPlayerSideTarget(record): (Model?, number)
	local cfg = Config.Enemies.Scrapling
	local position = record.root.Position
	local home = record.placement.Ground
	local best, bestDistance = nil, cfg.AggroRadius

	local function consider(model: Model?)
		if not model or model:GetAttribute("Defeated") then
			return
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root then
			return
		end
		if Util.FlatDistance(root.Position, home) > cfg.LeashRadius then
			return
		end
		local distance = Util.FlatDistance(root.Position, position)
		if distance < bestDistance then
			best, bestDistance = model, distance
		end
	end

	for _, player in Players:GetPlayers() do
		consider(player.Character)
	end
	for _, nightmare in CollectionService:GetTagged("Nightmare") do
		consider(nightmare)
	end
	return best, bestDistance
end

function TrainingService:ScraplingAttack(record, target: Model, now: number)
	local cfg = Config.Enemies.Scrapling
	local model, root = record.model, record.root
	record.nextAttack = now + cfg.AttackCooldown
	record.busyUntil = now + cfg.AttackWindup + 0.3
	record.humanoid:MoveTo(root.Position)

	local direction = Util.FlatUnit(target.HumanoidRootPart.Position - root.Position)
	if direction then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	end

	model:SetAttribute("ActionName", "Swipe")
	model:SetAttribute("ActionWindup", cfg.AttackWindup)
	model:SetAttribute("ActionDuration", cfg.AttackWindup + 0.35)
	model:SetAttribute("ActionSeq", (model:GetAttribute("ActionSeq") or 0) + 1)

	-- Track the target through the windup (capped turn speed), then commit: stop turning
	-- and lunge a little into the swing if the target backed off.
	local commitAt = now + cfg.AttackWindup - cfg.TrackCommit
	local maxTurn = math.rad(cfg.TrackTurnRate)
	local lunged = 0
	local tracker
	tracker = RunService.Heartbeat:Connect(function(dt)
		local targetRoot = target.Parent and target:FindFirstChild("HumanoidRootPart")
		if enemies[model] ~= record or record.humanoid.Health <= 0 or model:GetAttribute("Ragdolled") or self.Services.StatusService:IsStaggered(model) or not targetRoot then
			tracker:Disconnect()
			return
		end
		local look = Util.FlatUnit(root.CFrame.LookVector)
		if os.clock() < commitAt then
			local want = Util.FlatUnit(targetRoot.Position - root.Position)
			if look and want then
				local angle = math.acos(math.clamp(look:Dot(want), -1, 1))
				local step = maxTurn * dt
				local turned = want
				if angle > step then
					local sign = look:Cross(want).Y >= 0 and 1 or -1
					turned = CFrame.fromAxisAngle(Vector3.yAxis, sign * step):VectorToWorldSpace(look)
				end
				root.CFrame = CFrame.lookAt(root.Position, root.Position + turned)
			end
			return
		end
		-- lunge straight ahead, only while still out of reach and for at most StepIn studs
		local reach = root.Size.Z / 2 + cfg.AttackRange * 0.8 + math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
		local gap = Util.FlatDistance(root.Position, targetRoot.Position) - reach
		if look and gap > 0.3 and lunged < cfg.StepIn then
			local speed = cfg.StepIn / cfg.TrackCommit
			lunged += speed * dt
			root.AssemblyLinearVelocity = look * speed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		end
		if os.clock() >= commitAt + cfg.TrackCommit then
			tracker:Disconnect()
		end
	end)

	task.delay(cfg.AttackWindup, function()
		if enemies[model] ~= record or record.humanoid.Health <= 0 or self.Services.StatusService:IsStaggered(model) or model:GetAttribute("Ragdolled") or model:GetAttribute("Gripped") then
			return -- staggering, knocking down or biting hold of a Scrapling cancels its swipe
		end
		local boxCFrame = root.CFrame * CFrame.new(0, 0, -(root.Size.Z / 2 + cfg.AttackRange / 2))
		local boxSize = V(cfg.AttackWidth, 5, cfg.AttackRange)
		local services = self.Services
		for _, victim in services.HitDetectionService:QueryBox(boxCFrame, boxSize, { model }, root.Position) do
			services.CombatService:ApplyDamage({
				Attacker = model,
				Target = victim,
				BaseDamage = cfg.AttackDamage,
				AttackPower = 100,
				Knockback = 12,
				Source = "Scrapling",
			})
		end
	end)
end

function TrainingService:UpdateScrapling(record, now: number)
	local cfg = Config.Enemies.Scrapling
	if record.humanoid.Health <= 0 or now < record.busyUntil then
		return
	end
	local status = self.Services.StatusService
	if record.model:GetAttribute("Ragdolled") or record.model:GetAttribute("Gripped") then
		return -- knocked down (physics has it) or held in a Nightmare's jaws
	end
	if status:IsStaggered(record.model) then
		record.humanoid:MoveTo(record.root.Position)
		return
	end
	record.humanoid.WalkSpeed = cfg.WalkSpeed * status:SpeedMultiplier(record.model)

	local target, distance = findPlayerSideTarget(record)
	if not target then
		if Util.FlatDistance(record.root.Position, record.placement.Ground) > 3 then
			record.humanoid:MoveTo(record.placement.Ground)
		end
		return
	end

	local targetRoot = target.HumanoidRootPart
	local reach = record.root.Size.Z / 2 + cfg.AttackRange * 0.8 + math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
	if distance > reach then
		record.humanoid:MoveTo(targetRoot.Position)
	elseif now >= record.nextAttack then
		self:ScraplingAttack(record, target, now)
	else
		record.humanoid:MoveTo(record.root.Position)
	end
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function TrainingService:Init(services)
	self.Services = services
end

function TrainingService:Start()
	local world = Config.World
	local center = world.ArenaCenter + V(0, 0.4, 0) -- arena floor top
	for _, offset in world.DummyOffsets do
		self:SpawnEnemy({ Kind = "TrainingDummy", Ground = center + offset, Facing = center })
	end
	for _, offset in world.ScraplingOffsets do
		self:SpawnEnemy({ Kind = "Scrapling", Ground = center + offset, Facing = center })
	end

	-- Dummies heal fully once left alone, so DPS testing always starts fresh.
	self.Services.CombatService:OnDamaged(function(target)
		local record = enemies[target]
		if record then
			record.lastHit = os.clock()
		end
	end)

	local step = 1 / Config.Enemies.Scrapling.AIUpdateRate
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < step then
			return
		end
		accumulated = 0
		local now = os.clock()
		for _, record in enemies do
			if record.kind == "Scrapling" then
				local ok, err = pcall(self.UpdateScrapling, self, record, now)
				if not ok then
					warn("[TrainingService] scrapling update failed:", err)
				end
			elseif record.kind == "TrainingDummy" then
				local humanoid = record.humanoid
				if humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth and now - record.lastHit > Config.Enemies.TrainingDummy.RegenDelay then
					humanoid.Health = humanoid.MaxHealth
				end
			end
		end
	end)
end

return TrainingService
