--[[
	FighterService  (ModuleScript)
	Location: ServerScriptService/Server/Services/FighterService

	THE SPARRING FIGHTER: a human-sized opponent in the Training Arena who fights the way
	you do in your stance (FightRules), so the duel layer can be learned and shown:

	  * stands in a fighting stance facing you, circles at punching range (footwork)
	  * guards one side at a time (GuardDir), going back to a high guard between exchanges;
	    it only moves its guard to a side punch if it READS it in time (a human reaction
	    delay), so mixing up your sides is how you get through, like For Honor. Sometimes
	    it times its guard into your punch at the last moment: a PARRY.
	  * throws its own combos (jab, jab-cross, jab-cross-hook, hooks) with a short TELL
	    first: AttackSide / AttackAt attributes tell your screen which side is coming and
	    when (block it by guarding that side; flick there at the last moment to parry)
	  * reacts like you: parried = knocked off balance, clean medium hits interrupt it,
	    blocking costs it stamina (FighterStamina) and an empty tank breaks its guard
	  * heals up when left alone, comes back if it's knocked out

	Same moves and timings as your own punches (MeleeDefinitions), same server rules
	(CombatService:ApplyDamage / Defend). Clients animate it with the Handler poses
	(tag "Fighter": HandlerAnimator), from the HPose stamps below.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Melee = require(Shared:WaitForChild("MeleeDefinitions"))
local FightRules = require(Shared:WaitForChild("FightRules"))
local Net = require(Shared:WaitForChild("Net"))

local FighterService = {}

local CFG = {
	MaxHealth = 450,
	RegenDelay = 6, -- left alone this long: back to full health
	RespawnDelay = 4,
	StaminaMax = 100,
	StaminaRegen = 16, -- per second
	EngageRange = 32, -- notices players this close (in the arena)
	FightDistance = 5.2, -- wants to stand this far away (centre to centre): punching range
	TellTime = 0.3, -- its side shows this long before a strike starts (readable, fair)
	ComboGap = { 1.4, 2.8 }, -- seconds between its combos
	ReactTime = { 0.16, 0.3 }, -- how long it takes to read your side punch
	ReadChance = 0.55, -- how often it reads a side punch at all
	ParryChance = 0.18, -- how often a read becomes a timed parry
	ReturnHighAfter = 0.9, -- back to a high guard after this long on a side
	RoundRest = 8, -- after it drops you to 1 health it leaves you alone this long
	Combos = {
		{ "Jab" },
		{ "Jab", "Cross" },
		{ "Jab", "Cross", "Hook" },
		{ "Hook" },
		{ "RearHook" },
		{ "Jab", "RearHook" },
		{ "Cross", "Hook", "RearHook" },
	},
}

-- The sparring ring on the plaza between the Engine and the Training Arena (clear of the
-- Scraplings' patch). The fighter only takes on someone who steps through the ropes.
local RING_CENTER = Vector3.new(36, 1, -38)
local RING_HALF = 11

local fighters = {} -- [Model] = record
local stampCounter = 0

local function stamp(model: Model, pose: string)
	stampCounter += 1
	model:SetAttribute("HPose", pose .. "#" .. stampCounter)
end

function FighterService:Init(services)
	self.Services = services
end

------------------------------------------------------------------------------------------
-- Building one
------------------------------------------------------------------------------------------
function FighterService:Spawn(at: CFrame)
	local description = Instance.new("HumanoidDescription")
	-- a dark, wrapped-up sparring partner
	local skin = Color3.fromRGB(150, 110, 86)
	description.HeadColor, description.TorsoColor = skin, skin
	description.LeftArmColor, description.RightArmColor = skin, skin
	description.LeftLegColor, description.RightLegColor = Color3.fromRGB(40, 36, 48), Color3.fromRGB(40, 36, 48)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[FighterService] couldn't build the sparring fighter:", model)
		return
	end
	model.Name = "SparringFighter"
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	humanoid.MaxHealth = CFG.MaxHealth
	humanoid.Health = CFG.MaxHealth
	humanoid.WalkSpeed = 11
	humanoid.AutoRotate = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	model:SetAttribute("DisplayName", "Sparring Fighter")
	model:SetAttribute("EnemyType", "Fighter")
	model:SetAttribute("Defence", 0)
	model:SetAttribute("ActionSeq", 0)
	model:SetAttribute("InStance", true)
	model:SetAttribute("GuardDir", "High")
	model:SetAttribute("GuardDirAt", 0)
	model:SetAttribute("FighterStamina", CFG.StaminaMax)
	model:SetAttribute("InFight", true)
	model:SetAttribute("NoNightmareTarget", true) -- a duel: your Nightmare stays out of it
	model:PivotTo(at)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Enemies"
		end
	end
	-- turns it to face you (server-owned body; the humanoid only walks it)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = 1e6
	align.Responsiveness = 35
	align.Parent = root
	CollectionService:AddTag(model, "Enemy")
	CollectionService:AddTag(model, "Fighter")
	model.Parent = Workspace:FindFirstChild("Enemies") or Workspace
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	self.Services.MeleeService:ApplyFists(model)

	local record = {
		model = model,
		humanoid = humanoid,
		root = root,
		align = align,
		home = at,
		nextCombo = os.clock() + 2,
		busyUntil = 0,
		lastHit = 0,
		circle = 1,
		circleSwapAt = os.clock() + 3,
		guardSideSince = 0,
		combo = nil,
		restingFrom = {}, -- [Player] = until (a round it won: leaves them alone)
	}
	fighters[model] = record

	humanoid.Died:Connect(function()
		fighters[model] = nil
		model:SetAttribute("Defeated", true)
		task.delay(1.5, function()
			if model.Parent then
				model:Destroy()
			end
		end)
		task.delay(CFG.RespawnDelay, function()
			self:Spawn(at)
		end)
	end)
	return model
end

------------------------------------------------------------------------------------------
-- Defence: reading your punches
------------------------------------------------------------------------------------------
local function setGuard(model: Model, side: string)
	if model:GetAttribute("GuardDir") ~= side then
		model:SetAttribute("GuardDir", side)
		model:SetAttribute("GuardDirAt", os.clock())
	end
end

-- A player near it started a strike (their HPose stamp): maybe read it.
function FighterService:Read(record, move)
	if not move or not move.Dir or record.model:GetAttribute("GuardBroken") then
		return
	end
	local side = FightRules.SideOf(move)
	if math.random() > CFG.ReadChance then
		return -- didn't see it coming
	end
	local react = CFG.ReactTime[1] + math.random() * (CFG.ReactTime[2] - CFG.ReactTime[1])
	if math.random() < CFG.ParryChance then
		-- timed: the guard arrives just before the punch does
		react = math.max(0.02, move.HitTime - FightRules.ParryWindow * 0.6)
	end
	if react >= move.HitTime then
		return -- too slow: it lands
	end
	task.delay(react, function()
		if fighters[record.model] == record and not record.model:GetAttribute("Striking") then
			setGuard(record.model, side)
			record.guardSideSince = os.clock()
		end
	end)
end

------------------------------------------------------------------------------------------
-- Offence
------------------------------------------------------------------------------------------
local function slide(root: BasePart, direction: Vector3, distance: number, duration: number)
	if distance <= 0.2 then
		return
	end
	local attachment = root:FindFirstChildOfClass("Attachment")
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.MaxForce = 1e6
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (distance / duration)
	mover.Parent = root
	task.delay(duration, function()
		mover:Destroy()
		if root.Parent then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		end
	end)
end

local function canAct(record): boolean
	local model = record.model
	return record.humanoid.Health > 0
		and not model:GetAttribute("Ragdolled")
		and os.clock() >= (model:GetAttribute("ParriedUntil") or 0)
		and not model:GetAttribute("Stunned")
end

-- One strike of a combo: tell, then the punch, then the hit at its HitTime.
function FighterService:Strike(record, target: Model, moveId: string): number
	local move = Melee.Moves[moveId]
	local model, root = record.model, record.root
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not move or not targetRoot then
		return 0
	end
	local side = FightRules.SideOf(move)
	-- the tell: its side shows on your screen before it commits
	model:SetAttribute("AttackSide", side)
	model:SetAttribute("AttackAt", Workspace:GetServerTimeNow() + CFG.TellTime + move.HitTime)
	task.wait(CFG.TellTime)
	if fighters[model] ~= record or not canAct(record) then
		model:SetAttribute("AttackSide", nil)
		return 0
	end
	stamp(model, move.Pose)
	model:SetAttribute("Striking", true)
	local direction = Util.FlatUnit(targetRoot.Position - root.Position) or root.CFrame.LookVector
	local radius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
	local gap = Util.FlatDistance(targetRoot.Position, root.Position) - radius - (move.Contact or 2.3)
	slide(root, direction, math.clamp(gap, 0, move.Lunge or 0), math.max(move.HitTime, 0.08))
	task.wait(move.HitTime)
	model:SetAttribute("AttackSide", nil)
	if fighters[model] == record and canAct(record) and target.Parent then
		local reach = move.Range + (move.Lunge or 0) * 0.4
		local offset = targetRoot.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local inArc = flat.Magnitude < 1 or flat.Unit:Dot(Util.FlatUnit(root.CFrame.LookVector) or flat.Unit) >= math.cos(math.rad(move.Arc / 2))
		if inArc and flat.Magnitude - radius <= reach then
			self.Services.CombatService:ApplyDamage({
				Attacker = model,
				Target = target,
				BaseDamage = move.Damage,
				AttackPower = 100,
				Knockback = move.Knockback,
				Stagger = move.Stagger,
				Side = side,
				NonLethal = true, -- sparring: it can drop you to 1, never kill you
				Source = "Fighter:" .. move.Id,
			})
			-- dropped them to the floor: round over, it backs off and lets them recover
			local humanoid = target:FindFirstChildOfClass("Humanoid")
			local player = Players:GetPlayerFromCharacter(target)
			if humanoid and humanoid.Health <= 1 and player then
				record.restingFrom[player] = os.clock() + CFG.RoundRest
				record.interrupted = true
				Net.Get("UIStateUpdate"):FireClient(player, "Toast", { Text = "Sparring round over: the fighter got you. Get your breath back and go again." })
			end
		end
	end
	local recover = move.Cancel - move.HitTime
	task.wait(math.max(0.05, recover))
	model:SetAttribute("Striking", nil)
	return move.Duration - move.Cancel
end

function FighterService:RunCombo(record, target: Model)
	local list = CFG.Combos[math.random(1, #CFG.Combos)]
	record.combo = list
	setGuard(record.model, "High")
	for _, moveId in list do
		if fighters[record.model] ~= record or not canAct(record) or record.interrupted then
			break
		end
		self:Strike(record, target, moveId)
	end
	record.interrupted = nil
	record.combo = nil
	record.model:SetAttribute("Striking", nil)
	record.nextCombo = os.clock() + CFG.ComboGap[1] + math.random() * (CFG.ComboGap[2] - CFG.ComboGap[1])
end

------------------------------------------------------------------------------------------
-- The loop
------------------------------------------------------------------------------------------
local function nearestPlayer(record): (Model?, number)
	local best, bestDistance = nil, CFG.EngageRange
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local resting = (record.restingFrom[player] or 0) > os.clock()
		if root and humanoid and humanoid.Health > 1 and not resting and not character:GetAttribute("Ragdolled") then
			local distance = Util.FlatDistance(root.Position, record.root.Position)
			-- only someone inside the ropes
			local offset = root.Position - RING_CENTER
			local inRing = math.abs(offset.X) <= RING_HALF + 0.5 and math.abs(offset.Z) <= RING_HALF + 0.5
			if distance < bestDistance and inRing then
				best, bestDistance = character, distance
			end
		end
	end
	return best, bestDistance
end

function FighterService:Update(record, now: number, dt: number)
	local model, humanoid, root = record.model, record.humanoid, record.root
	-- stamina back over time; health back when left alone
	local stamina = model:GetAttribute("FighterStamina") or CFG.StaminaMax
	if stamina < CFG.StaminaMax then
		model:SetAttribute("FighterStamina", math.min(CFG.StaminaMax, stamina + CFG.StaminaRegen * dt))
	end
	if humanoid.Health < humanoid.MaxHealth and now - record.lastHit > CFG.RegenDelay then
		humanoid.Health = humanoid.MaxHealth
	end
	if not canAct(record) then
		humanoid:MoveTo(root.Position)
		return
	end
	local target, distance = nearestPlayer(record)
	if not target then
		record.align.Enabled = false
		if Util.FlatDistance(root.Position, record.home.Position) > 2 then
			humanoid:MoveTo(record.home.Position)
		end
		return
	end
	local targetRoot = target.HumanoidRootPart
	local toTarget = Util.FlatUnit(targetRoot.Position - root.Position) or root.CFrame.LookVector
	record.align.Enabled = true
	record.align.CFrame = CFrame.lookAt(Vector3.zero, toTarget)
	-- back to a high guard after holding a side for a while
	if model:GetAttribute("GuardDir") ~= "High" and now - record.guardSideSince > CFG.ReturnHighAfter and not model:GetAttribute("Striking") then
		setGuard(model, "High")
	end
	if record.combo then
		return -- striking
	end
	-- footwork: hold punching range and circle (switching direction now and then)
	if now >= record.circleSwapAt then
		record.circle = -record.circle
		record.circleSwapAt = now + 2 + math.random() * 3
	end
	local side = Vector3.new(-toTarget.Z, 0, toTarget.X) * record.circle
	local want = targetRoot.Position - toTarget * CFG.FightDistance + side * 2.5
	humanoid:MoveTo(Vector3.new(want.X, root.Position.Y, want.Z))
	-- attack when in range
	if now >= record.nextCombo and distance <= CFG.FightDistance + 1.5 then
		task.spawn(self.RunCombo, self, record, target)
	end
end

-- A point pushed out past the nearest rope if it's inside the ring (where a Nightmare
-- waits while its Handler spars: it's a one-on-one).
function FighterService:OutsideRing(point: Vector3): Vector3
	local offset = point - RING_CENTER
	local limit = RING_HALF + 3
	if math.abs(offset.X) >= limit or math.abs(offset.Z) >= limit then
		return point
	end
	if math.abs(offset.X) > math.abs(offset.Z) then
		return Vector3.new(RING_CENTER.X + math.sign(offset.X) * limit, point.Y, point.Z)
	end
	return Vector3.new(point.X, point.Y, RING_CENTER.Z + (offset.Z >= 0 and 1 or -1) * limit)
end

-- THE SPARRING RING (RING_CENTER / RING_HALF, top of the file): a raised mat, corner
-- posts, three ropes, a sign facing the hub.
local function buildRing(): Vector3
	local folder = Instance.new("Model")
	folder.Name = "SparringRing"
	local function part(cf: CFrame, size: Vector3, color: Color3, material, shape)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p.Parent = folder
		return p
	end
	local floorTop = RING_CENTER.Y + 1.2
	part(CFrame.new(RING_CENTER + Vector3.new(0, 0.6, 0)), Vector3.new(RING_HALF * 2 + 2, 1.2, RING_HALF * 2 + 2), Color3.fromRGB(40, 34, 48), Enum.Material.Concrete)
	part(CFrame.new(RING_CENTER + Vector3.new(0, 1.25, 0)), Vector3.new(RING_HALF * 2, 0.1, RING_HALF * 2), Color3.fromRGB(70, 30, 44), Enum.Material.Fabric)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local base = RING_CENTER + Vector3.new(sx * RING_HALF, 0, sz * RING_HALF)
			part(CFrame.new(base + Vector3.new(0, 3.6, 0)), Vector3.new(0.9, 5, 0.9), Color3.fromRGB(150, 90, 255), Enum.Material.Metal)
		end
	end
	for level = 1, 3 do
		local y = floorTop + level * 1.15
		for _, edge in { { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1) }, { Vector3.new(1, 0, -1), Vector3.new(1, 0, 1) }, { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1) }, { Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) } } do
			local a = RING_CENTER + edge[1] * RING_HALF + Vector3.new(0, y - RING_CENTER.Y, 0)
			local b = RING_CENTER + edge[2] * RING_HALF + Vector3.new(0, y - RING_CENTER.Y, 0)
			local rope = part(CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), Vector3.new((b - a).Magnitude, 0.22, 0.22), level == 2 and Color3.fromRGB(240, 236, 255) or Color3.fromRGB(200, 40, 70), Enum.Material.Fabric, Enum.PartType.Cylinder)
			rope.CanCollide = false
		end
	end
	-- a sign facing the hub
	local sign = part(CFrame.lookAt(RING_CENTER + Vector3.new(0, 9, RING_HALF + 1), Vector3.new(0, 9, 0)), Vector3.new(12, 2.2, 0.3), Color3.fromRGB(14, 10, 20), Enum.Material.Slate)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 80, 120)
	label.Text = "SPARRING RING · LOCK ON (Z) TO DUEL"
	label.Parent = gui
	folder.Parent = Workspace:FindFirstChild("NightmareForgeHub") or Workspace
	return RING_CENTER + Vector3.new(0, 1.3, 0)
end

function FighterService:Start()
	-- the sparring fighter waits in the middle of its ring
	task.defer(function()
		local floor = buildRing()
		self:Spawn(CFrame.lookAt(floor + Vector3.new(0, 3, -3), floor + Vector3.new(0, 3, 20)))
	end)

	-- reads your strikes (every Handler's HPose stamp near a fighter)
	local function watch(character: Model)
		character:GetAttributeChangedSignal("HPose"):Connect(function()
			local stampValue = character:GetAttribute("HPose")
			local pose = type(stampValue) == "string" and stampValue:match("^([^#]+)")
			local root = character:FindFirstChild("HumanoidRootPart")
			if not pose or not root then
				return
			end
			local move
			for _, m in Melee.Moves do
				if m.Pose == pose then
					move = m
					break
				end
			end
			for model, record in fighters do
				if Util.FlatDistance(record.root.Position, root.Position) < 12 then
					self:Read(record, move)
				end
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			watch(player.Character)
		end
		player.CharacterAdded:Connect(watch)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(watch)
	end)

	-- a clean medium / heavy hit interrupts its combo; any hit resets its heal timer
	self.Services.CombatService:OnDamaged(function(target, _attacker, _amount, params)
		local record = fighters[target]
		if record then
			record.lastHit = os.clock()
			if not params.Blocked and FightRules.Strength(params) ~= "Light" then
				record.interrupted = true
			end
		end
	end)
	-- parried: its combo stops there
	self.Services.CombatService:OnParry(function(_defender, attacker)
		local record = fighters[attacker]
		if record then
			record.interrupted = true
		end
	end)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.1 then
			return
		end
		local step = accumulated
		accumulated = 0
		local now = os.clock()
		for _, record in fighters do
			local ok, err = pcall(self.Update, self, record, now, step)
			if not ok then
				warn("[FighterService] update failed:", err)
			end
		end
	end)
end

return FighterService
