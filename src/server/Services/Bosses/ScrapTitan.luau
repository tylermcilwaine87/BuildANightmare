--[[
	ScrapTitan  (ModuleScript)
	Location: ServerScriptService/Server/Services/Bosses/ScrapTitan

	Behaviour + placeholder model for BOSS 1: THE SCRAP TITAN.
	BossService runs the generic state machine (Chase -> Select Attack -> Windup ->
	Attack -> Recovery, Phase Transition, Defeated) and calls into this module.

	Every attack is telegraphed (TelegraphService) and has a recovery window to punish.
	  Swipe          close range; red box in front               20 dmg, blockable
	  Ground Slam    red circle under the target; long recovery  28 dmg, HEAVY
	                 OVERDRIVE: a second slam follows
	  Scrap Barrage  6 (9 in Overdrive) falling scrap circles   12 dmg each
	  Magnet Pull    blue ring: pulls everyone in, then a        16 dmg
	                 red sweep around the boss
	  OVERDRIVE at 50% HP: faster windups (x0.8), shorter gaps, faster movement, red
	  eyes, burning reactor. No healing.

	ctx API (provided by BossService): see BossService "Context" section.
]]

local ScrapTitan = {}

local RGB = Color3.fromRGB
local Mat = Enum.Material
local V = Vector3.new

ScrapTitan.PreferredRange = 12

------------------------------------------------------------------------------------------
-- Model
------------------------------------------------------------------------------------------
local function helper(model, name, cframe)
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

local function motor(name, part0, part1, jointWorld)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(jointWorld)
	m.C1 = part1.CFrame:ToObjectSpace(jointWorld)
	m.Parent = part0
end

local function piece(model, attachTo, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
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

-- groundCF: a CFrame on the arena floor facing the way the boss should face.
-- Returns model, hipHeight.
function ScrapTitan.BuildModel(groundCF: CFrame, hitboxSize: Vector3)
	local hipHeight = 3.6
	local rootCF = groundCF * CFrame.new(0, hipHeight + hitboxSize.Y / 2, 0)

	local model = Instance.new("Model")
	model.Name = "ScrapTitan"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = hitboxSize
	root.CFrame = rootCF
	root.Transparency = 1
	root.CanCollide = true
	root.CustomPhysicalProperties = PhysicalProperties.new(5, 0.3, 0)
	root.Parent = model
	model.PrimaryPart = root

	local rust, metal, dark, glow = RGB(125, 80, 55), RGB(110, 112, 120), RGB(50, 50, 58), RGB(255, 160, 40)

	local core = helper(model, "Core_Root", rootCF)
	motor("Joint_Core", root, core, rootCF)
	local function at(x, y, z)
		return rootCF * CFrame.new(x, y, z)
	end
	piece(model, core, "Torso", V(10, 8, 6), at(0, 1, 0), rust, Mat.CorrodedMetal)
	piece(model, core, "ChestPlate", V(8, 4, 0.6), at(0, 1.5, -3.1), metal, Mat.DiamondPlate)
	piece(model, core, "ReactorGlow", V(2.6, 2.6, 2.6), at(0, 1.5, -3.2), glow, Mat.Neon, Enum.PartType.Ball)
	piece(model, core, "CarDoor", V(3.5, 3, 0.4), at(-3.4, 2.5, -3.2) * CFrame.Angles(0, 0, math.rad(12)), RGB(60, 90, 140), Mat.Metal)
	piece(model, core, "Tire", V(1.2, 3.4, 3.4), at(3.8, -1.5, -3.2) * CFrame.Angles(0, math.rad(90), 0), dark, Mat.Fabric, Enum.PartType.Cylinder)
	piece(model, core, "Pelvis", V(7, 2.5, 5), at(0, -4, 0), dark, Mat.Metal)
	piece(model, core, "Chimney", V(4, 1.2, 1.2), at(3, 6.5, 1.5) * CFrame.Angles(0, 0, math.rad(90)), dark, Mat.Metal, Enum.PartType.Cylinder)
	for _, side in { -1, 1 } do
		piece(model, core, "Leg", V(2.6, 6, 2.6), at(2.5 * side, -7, 0), rust, Mat.CorrodedMetal)
		piece(model, core, "Foot", V(3.4, 1, 4.2), at(2.5 * side, -9.6, -0.6), dark, Mat.Metal)
		piece(model, core, "Shoulder", V(3.2, 3.2, 3.2), at(5.6 * side, 4.2, 0), metal, Mat.Metal, Enum.PartType.Ball)
	end

	-- Head
	local neck = at(0, 5, 0)
	local head = helper(model, "Head_Root", neck)
	motor("Joint_Head", core, head, neck)
	piece(model, head, "Head", V(4, 3, 3.5), neck * CFrame.new(0, 1.6, -0.3), metal, Mat.DiamondPlate)
	piece(model, head, "Eye", V(0.9, 0.5, 0.2), neck * CFrame.new(0.9, 1.9, -2.1), RGB(255, 200, 60), Mat.Neon)
	piece(model, head, "Eye", V(0.9, 0.5, 0.2), neck * CFrame.new(-0.9, 1.9, -2.1), RGB(255, 200, 60), Mat.Neon)
	piece(model, head, "Jaw", V(3.4, 0.8, 3), neck * CFrame.new(0, 0.3, -0.6), dark, Mat.Metal)

	-- Right arm: wrecking-ball fist
	local rightShoulder = at(6, 3.5, 0)
	local rightArm = helper(model, "RightArm_Root", rightShoulder)
	motor("Joint_RightArm", core, rightArm, rightShoulder)
	piece(model, rightArm, "UpperArm", V(2.4, 6, 2.4), rightShoulder * CFrame.new(0.6, -3, 0), rust, Mat.CorrodedMetal)
	piece(model, rightArm, "Fist", V(4.2, 3.6, 4.2), rightShoulder * CFrame.new(0.8, -7, 0), metal, Mat.DiamondPlate)

	-- Left arm: giant magnet
	local leftShoulder = at(-6, 3.5, 0)
	local leftArm = helper(model, "LeftArm_Root", leftShoulder)
	motor("Joint_LeftArm", core, leftArm, leftShoulder)
	piece(model, leftArm, "UpperArm", V(2.4, 6, 2.4), leftShoulder * CFrame.new(-0.6, -3, 0), rust, Mat.CorrodedMetal)
	piece(model, leftArm, "MagnetBase", V(4, 1.2, 2), leftShoulder * CFrame.new(-0.8, -6.4, 0), RGB(200, 40, 40), Mat.SmoothPlastic)
	piece(model, leftArm, "MagnetPoleA", V(1.2, 2.2, 2), leftShoulder * CFrame.new(-2.2, -8, 0), RGB(200, 40, 40), Mat.SmoothPlastic)
	piece(model, leftArm, "MagnetPoleB", V(1.2, 2.2, 2), leftShoulder * CFrame.new(0.6, -8, 0), RGB(200, 40, 40), Mat.SmoothPlastic)
	piece(model, leftArm, "MagnetTip", V(1.25, 0.5, 2.05), leftShoulder * CFrame.new(-2.2, -9.2, 0), RGB(230, 230, 240), Mat.Metal)
	piece(model, leftArm, "MagnetTip", V(1.25, 0.5, 2.05), leftShoulder * CFrame.new(0.6, -9.2, 0), RGB(230, 230, 240), Mat.Metal)

	return model, hipHeight
end

------------------------------------------------------------------------------------------
-- Spawn (difficulty look)
------------------------------------------------------------------------------------------
local MODE_GLOW = {
	Hard = RGB(255, 60, 60),
	Nightmare = RGB(170, 60, 255),
}

function ScrapTitan.OnSpawn(ctx)
	local glow = MODE_GLOW[ctx.Encounter.Mode]
	if not glow then
		return
	end
	for _, d in ctx.Model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Eye" or d.Name == "ReactorGlow") then
			d.Color = glow
		end
	end
	if ctx.Encounter.Mode == "Nightmare" then
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Range = 24
		light.Brightness = 3
		light.Parent = ctx.Model:FindFirstChild("ReactorGlow", true)
	end
end

------------------------------------------------------------------------------------------
-- Phases
------------------------------------------------------------------------------------------
function ScrapTitan.OnPhase(ctx, phase: number)
	if phase ~= 2 then
		return
	end
	ctx:Stop()
	ctx:Banner("OVERDRIVE!", "The Scrap Titan's reactor is overheating!")
	ctx:Action("Roar", 0.3, 2)
	local model = ctx.Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Eye" then
			d.Color = RGB(255, 40, 30)
		elseif d:IsA("BasePart") and d.Name == "ReactorGlow" then
			d.Color = RGB(255, 60, 30)
			local fire = Instance.new("Fire")
			fire.Size = 8
			fire.Heat = 12
			fire.Color = RGB(255, 120, 40)
			fire.SecondaryColor = RGB(255, 40, 20)
			fire.Parent = d
		end
	end
	ctx.Humanoid.WalkSpeed = ctx.Definition.WalkSpeed * 1.35
	ctx:Wait(2)
end

------------------------------------------------------------------------------------------
-- Attacks
------------------------------------------------------------------------------------------
local Attacks = {}

Attacks.Swipe = {
	Weight = function(_, distance)
		return distance < 18 and 45 or 0
	end,
	Run = function(ctx, target)
		ctx:Face(ctx:Position(target))
		local windup = ctx:WindupTime(0.85)
		local boxCF, boxSize = ctx:FrontBox(16, 14)
		ctx:Box(boxCF, boxSize, windup)
		ctx:Action("Swipe", windup, windup + 0.9)
		if not ctx:Wait(windup) then
			return
		end
		ctx:DamageBox(boxCF, boxSize, 20, { Knockback = 30 })
		ctx:Wait(0.9)
	end,
}

Attacks.GroundSlam = {
	Weight = function(_, distance)
		return distance < 18 and 25 or 35
	end,
	Run = function(ctx, target)
		local function slam(victim, windupBase)
			local position = ctx:GroundPosition(victim)
			ctx:Face(position)
			local windup = ctx:WindupTime(windupBase)
			ctx:Circle(position, 11, windup)
			ctx:Action("Slam", windup, windup + 0.6)
			if not ctx:Wait(windup) then
				return false
			end
			ctx:Impact(position, 11)
			ctx:DamageCircle(position, 11, 28, { Heavy = true, Knockback = 40 })
			return true
		end
		if not slam(target, 1.3) then
			return
		end
		-- Overdrive adds a follow-up slam; Nightmare difficulty adds ExtraSlams more.
		local followUps = (ctx.Overdrive and 1 or 0) + (ctx.ModeConfig.ExtraSlams or 0)
		for _ = 1, followUps do
			local victim = ctx:PickTarget() or target
			if not slam(victim, 0.9) then
				return
			end
		end
		ctx:Wait(1.6) -- recovery: the punish window
	end,
}

Attacks.ScrapBarrage = {
	Weight = function(_, distance)
		return distance < 18 and 15 or 35
	end,
	Run = function(ctx)
		local windup = ctx:WindupTime(1.1)
		local count = (ctx.Overdrive and 9 or 6) + (ctx.ModeConfig.BarrageBonus or 0)
		ctx:Action("Barrage", windup, windup + 0.8)
		local targets = ctx:Targets()
		if #targets == 0 then
			return
		end
		local launchFrom = ctx.Root.Position + Vector3.new(0, 8, 0)
		for i = 1, count do
			local victim = targets[ctx.Random:NextInteger(1, #targets)]
			local offset = Vector3.new(ctx.Random:NextNumber(-9, 9), 0, ctx.Random:NextNumber(-9, 9))
			local position = ctx:ClampToArena(ctx:GroundPosition(victim) + offset)
			local impactTime = windup + (i - 1) * 0.15
			ctx:Circle(position, 5, impactTime)
			task.delay(math.max(impactTime - 0.5, 0), function()
				if ctx:Alive() then
					ctx:Projectile(launchFrom, position, 0.5)
				end
			end)
			task.delay(impactTime, function()
				if ctx:Alive() then
					ctx:Impact(position, 5)
					ctx:DamageCircle(position, 5, 12, { Knockback = 15 })
				end
			end)
		end
		ctx:Wait(windup + count * 0.15 + 0.8)
	end,
}

Attacks.MagnetPull = {
	Weight = function(_, distance)
		return distance < 18 and 10 or 30
	end,
	Run = function(ctx)
		local windup = ctx:WindupTime(1.2)
		local center = ctx:GroundPosition(ctx.Model)
		ctx:Circle(center, 35, windup, "Pull")
		ctx:Circle(center, 10, windup + 0.7, "Hostile")
		ctx:Action("MagnetPull", windup, windup + 1.4)
		if not ctx:Wait(windup) then
			return
		end
		ctx:Pull(35, 55)
		if not ctx:Wait(0.7) then
			return
		end
		ctx:Impact(center, 10)
		ctx:DamageCircle(center, 10, 16, { Knockback = 35 })
		ctx:Wait(0.8)
	end,
}

ScrapTitan.Attacks = Attacks

function ScrapTitan.ChooseAttack(ctx, distance: number)
	local total = 0
	local weights = {}
	for name, attack in Attacks do
		local weight = attack.Weight(ctx, distance)
		if name == ctx.LastAttack then
			weight *= 0.35 -- avoid repeating the same attack
		end
		weights[name] = weight
		total += weight
	end
	local roll = ctx.Random:NextNumber(0, total)
	for name, weight in weights do
		roll -= weight
		if roll <= 0 and weight > 0 then
			return name, Attacks[name]
		end
	end
	return "GroundSlam", Attacks.GroundSlam
end

return ScrapTitan
