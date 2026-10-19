--[[
	MirrorWarden  (ModuleScript)
	Location: ServerScriptService/Server/Services/Bosses/MirrorWarden

	BOSS 2: THE MIRROR WARDEN. A floating crystal knight: faceless mirror mask with a
	crown of shards, a glass blade (right arm), a round mirror shield (left arm) and a
	tapering crystal tail. Every boss is its own creature; its theme is REFLECTION, so its
	attacks echo across the arena.

	Every attack is telegraphed and leaves a recovery window.
	  Mirror Combo     3 red boxes in front, one after another      12 / 14 / 22 dmg
	  Reflected Slam   circle on the target AND its mirror image    26 dmg, HEAVY
	                   across the arena centre (4-way once cracked)
	  Shard Storm      falling glass shards around everyone          11 dmg each
	  Shatter Nova     ring around the Warden: don't hug it          22 dmg
	  Prism Beam       (cracked only) two crossing beams: one        30 dmg
	                   through the target, one across it
	  THE MIRROR CRACKS at 50% HP (60% on Nightmare): faster, 4-way slams, more shards,
	  Prism Beam. No healing.

	ctx API (provided by BossService): see BossService "Context" section.
]]

local MirrorWarden = {}

local RGB = Color3.fromRGB
local Mat = Enum.Material
local V = Vector3.new
local GLASS = RGB(170, 220, 255)
local CRACKED = RGB(230, 170, 255)

MirrorWarden.PreferredRange = 11

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

-- Visual piece welded to `attachTo`. Glass pieces get reflectance + a little transparency.
local function piece(model, attachTo, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Mat.Glass
	if p.Material == Mat.Glass then
		p.Reflectance = 0.35
		p.Transparency = 0.2
	end
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

-- Re-tints every glass piece (difficulty look, cracking). Neon gems keep their glow.
local function glassify(model: Model, tint: Color3)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Material == Mat.Glass then
			d.Color = d.Color:Lerp(tint, 0.65)
		elseif d:IsA("BasePart") and d.Name == "HeartGem" then
			d.Color = tint
		end
	end
end

-- groundCF: a CFrame on the arena floor facing the way the boss should face.
-- Returns model, hipHeight.
function MirrorWarden.BuildModel(groundCF: CFrame, hitboxSize: Vector3)
	local hipHeight = 3 -- it hovers: the crystal tail never touches the floor
	local rootCF = groundCF * CFrame.new(0, hipHeight + hitboxSize.Y / 2, 0)

	local model = Instance.new("Model")
	model.Name = "MirrorWarden"
	model:SetAttribute("Archetype", "Floating") -- client animator: gentle hover bob
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = hitboxSize
	root.CFrame = rootCF
	root.Transparency = 1
	root.CanCollide = true
	root.CustomPhysicalProperties = PhysicalProperties.new(5, 0.3, 0)
	root.Parent = model
	model.PrimaryPart = root

	local deep, pale, silver, gem = RGB(110, 160, 230), GLASS, RGB(200, 210, 225), RGB(140, 230, 255)

	local core = helper(model, "Core_Root", rootCF)
	motor("Joint_Core", root, core, rootCF)
	local function at(x, y, z)
		return rootCF * CFrame.new(x, y, z)
	end
	-- Torso: a tall crystal with a glowing heart-gem and pauldrons.
	piece(model, core, "Torso", V(7, 7, 4), at(0, 1.5, 0), pale)
	piece(model, core, "ChestPlate", V(5.4, 4.5, 0.5), at(0, 2, -2.1), silver, Mat.Metal)
	piece(model, core, "HeartGem", V(1.8, 1.8, 1.8), at(0, 2.2, -2.4) * CFrame.Angles(0, 0, math.rad(45)), gem, Mat.Neon)
	piece(model, core, "Waist", V(4.5, 2.5, 3), at(0, -3, 0), deep)
	-- Tapering crystal tail instead of legs.
	piece(model, core, "TailUpper", V(3.2, 2.6, 2.4), at(0, -5.2, 0), pale)
	piece(model, core, "TailLower", V(1.8, 2.2, 1.4), at(0, -7.2, 0.2) * CFrame.Angles(math.rad(8), 0, 0), deep)
	piece(model, core, "TailTip", V(0.8, 1.4, 0.8), at(0, -8.6, 0.45) * CFrame.Angles(math.rad(15), 0, math.rad(45)), gem, Mat.Neon)
	for _, side in { -1, 1 } do
		piece(model, core, "Pauldron", V(3.2, 1.6, 3.6), at(4.6 * side, 4.3, 0) * CFrame.Angles(0, 0, math.rad(-15 * side)), silver, Mat.Metal)
		piece(model, core, "PauldronShard", V(0.8, 3.4, 0.8), at(5.6 * side, 5.8, 0) * CFrame.Angles(0, 0, math.rad(-25 * side)), pale)
	end

	-- Head: a faceless mirror mask with a crown of shards.
	local neck = at(0, 5, 0)
	local head = helper(model, "Head_Root", neck)
	motor("Joint_Head", core, head, neck)
	piece(model, head, "Head", V(3.4, 3.8, 3), neck * CFrame.new(0, 2, 0), deep)
	piece(model, head, "Mask", V(2.8, 3.2, 0.3), neck * CFrame.new(0, 2, -1.55), silver, Mat.SmoothPlastic).Reflectance = 0.85
	for i, x in { -1.2, -0.6, 0, 0.6, 1.2 } do
		local height = (i == 3) and 3.2 or ((i == 2 or i == 4) and 2.4 or 1.6)
		piece(model, head, "Crown", V(0.5, height, 0.5), neck * CFrame.new(x, 3.9 + height / 2, 0) * CFrame.Angles(0, 0, math.rad(-x * 12)), gem, Mat.Neon)
	end

	-- Right arm: a long glass blade.
	local rightShoulder = at(4.8, 3, 0)
	local rightArm = helper(model, "RightArm_Root", rightShoulder)
	motor("Joint_RightArm", core, rightArm, rightShoulder)
	piece(model, rightArm, "UpperArm", V(1.8, 4.5, 1.8), rightShoulder * CFrame.new(0.4, -2.3, 0), deep)
	piece(model, rightArm, "Gauntlet", V(2.2, 1.6, 2.2), rightShoulder * CFrame.new(0.5, -5, 0), silver, Mat.Metal)
	local bladeCF = rightShoulder * CFrame.new(0.5, -8.6, -1.2) * CFrame.Angles(math.rad(-20), 0, 0)
	piece(model, rightArm, "Blade", V(0.6, 7.5, 2.2), bladeCF, pale)
	piece(model, rightArm, "BladeEdge", V(0.25, 7.2, 0.4), bladeCF * CFrame.new(0, 0, -1.2), gem, Mat.Neon)

	-- Left arm: a round mirror shield.
	local leftShoulder = at(-4.8, 3, 0)
	local leftArm = helper(model, "LeftArm_Root", leftShoulder)
	motor("Joint_LeftArm", core, leftArm, leftShoulder)
	piece(model, leftArm, "UpperArm", V(1.8, 4.5, 1.8), leftShoulder * CFrame.new(-0.4, -2.3, 0), deep)
	piece(model, leftArm, "Gauntlet", V(2.2, 1.6, 2.2), leftShoulder * CFrame.new(-0.5, -5, 0), silver, Mat.Metal)
	local shieldCF = leftShoulder * CFrame.new(-1.6, -5.5, -1.2) * CFrame.Angles(0, math.rad(90), 0)
	piece(model, leftArm, "ShieldRim", V(0.5, 7.4, 7.4), shieldCF, silver, Mat.Metal, Enum.PartType.Cylinder)
	piece(model, leftArm, "ShieldMirror", V(0.55, 6.4, 6.4), shieldCF, silver, Mat.SmoothPlastic, Enum.PartType.Cylinder).Reflectance = 0.9

	local light = Instance.new("PointLight")
	light.Name = "WardenGlow"
	light.Color = GLASS
	light.Range = 26
	light.Brightness = 2
	light.Parent = root
	return model, hipHeight
end

------------------------------------------------------------------------------------------
-- Spawn / phases
------------------------------------------------------------------------------------------
local MODE_TINT = {
	Hard = RGB(255, 150, 160),
	Nightmare = RGB(180, 110, 255),
}

function MirrorWarden.OnSpawn(ctx)
	local tint = MODE_TINT[ctx.Encounter.Mode]
	if tint then
		glassify(ctx.Model, tint)
		local light = ctx.Root:FindFirstChild("WardenGlow")
		if light then
			light.Color = tint
		end
	end
end

-- Cracked = Overdrive (phase 2) or the Nightmare-difficulty twist.
local function reflections(ctx): boolean
	return ctx.Overdrive or ctx.ModeConfig.ExtraReflections == true
end

function MirrorWarden.OnPhase(ctx, phase: number)
	if phase ~= 2 then
		return
	end
	ctx:Stop()
	ctx:Banner("THE MIRROR CRACKS!", "Its reflections multiply...")
	ctx:Action("Roar", 0.3, 2)
	glassify(ctx.Model, CRACKED)
	local light = ctx.Root:FindFirstChild("WardenGlow")
	if light then
		light.Color = CRACKED
		light.Brightness = 3.5
	end
	ctx.Humanoid.WalkSpeed = ctx.Definition.WalkSpeed * 1.3
	-- A burst as it cracks: everyone close gets pushed back (telegraphed).
	local center = ctx:GroundPosition(ctx.Model)
	ctx:Circle(center, 12, 1.2)
	if not ctx:Wait(1.2) then
		return
	end
	ctx:Impact(center, 12)
	ctx:DamageCircle(center, 12, 14, { Knockback = 45 })
	ctx:Wait(0.8)
end

------------------------------------------------------------------------------------------
-- Attacks
------------------------------------------------------------------------------------------
local Attacks = {}

-- Three blade strikes: boxes in front, one after another.
Attacks.MirrorCombo = {
	Weight = function(_, distance)
		return distance < 16 and 40 or 0
	end,
	Run = function(ctx, target)
		local hits = {
			{ Name = "Combo1", Windup = 0.75, Damage = 12, Knockback = 0 },
			{ Name = "Combo2", Windup = 0.6, Damage = 14, Knockback = 10 },
			{ Name = "Combo3", Windup = 0.9, Damage = 22, Knockback = 30, Heavy = true },
		}
		for _, hit in hits do
			ctx:Face(ctx:Position(target))
			local windup = ctx:WindupTime(hit.Windup)
			local boxCF, boxSize = ctx:FrontBox(14, 11)
			ctx:Box(boxCF, boxSize, windup)
			ctx:Action(hit.Name, windup, windup + 0.35)
			if not ctx:Wait(windup) then
				return
			end
			ctx:DamageBox(boxCF, boxSize, hit.Damage, { Knockback = hit.Knockback, Heavy = hit.Heavy })
			if not ctx:Wait(0.25) then
				return
			end
		end
		ctx:Wait(1.0) -- recovery: the punish window
	end,
}

-- Slams the target's spot AND its reflection across the arena (4 spots once cracked).
Attacks.ReflectedSlam = {
	Weight = function(_, distance)
		return distance < 16 and 25 or 40
	end,
	Run = function(ctx, target)
		local radius = 9
		local position = ctx:GroundPosition(target)
		local angles = reflections(ctx) and { 90, 180, 270 } or { 180 }
		local points = { position }
		for _, degrees in angles do
			local point = ctx:Reflect(position, degrees)
			-- Skip echoes that land on top of another circle (target near the centre).
			local overlaps = false
			for _, existing in points do
				if (existing - point).Magnitude < radius * 1.5 then
					overlaps = true
					break
				end
			end
			if not overlaps then
				table.insert(points, point)
			end
		end
		ctx:Face(position)
		local windup = ctx:WindupTime(1.3)
		for _, point in points do
			ctx:Circle(point, radius, windup)
		end
		ctx:Action("Slam", windup, windup + 0.6)
		if not ctx:Wait(windup) then
			return
		end
		for _, point in points do
			ctx:Impact(point, radius)
		end
		ctx:DamageCircles(points, radius, 26, { Heavy = true, Knockback = 40 })
		ctx:Wait(1.4)
	end,
}

-- Glass shards rain down around every target.
Attacks.ShardStorm = {
	Weight = function(_, distance)
		return distance < 16 and 15 or 35
	end,
	Run = function(ctx)
		local windup = ctx:WindupTime(1.1)
		local count = (reflections(ctx) and 11 or 7) + (ctx.ModeConfig.BarrageBonus or 0)
		ctx:Action("Barrage", windup, windup + 0.8)
		local targets = ctx:Targets()
		if #targets == 0 then
			return
		end
		local launchFrom = ctx.Root.Position + Vector3.new(0, 12, 0)
		for i = 1, count do
			local victim = targets[ctx.Random:NextInteger(1, #targets)]
			local offset = Vector3.new(ctx.Random:NextNumber(-10, 10), 0, ctx.Random:NextNumber(-10, 10))
			local position = ctx:ClampToArena(ctx:GroundPosition(victim) + offset)
			local impactTime = windup + (i - 1) * 0.15
			ctx:Circle(position, 4.5, impactTime)
			task.delay(math.max(impactTime - 0.5, 0), function()
				if ctx:Alive() then
					ctx:Projectile(launchFrom, position, 0.5)
				end
			end)
			task.delay(impactTime, function()
				if ctx:Alive() then
					ctx:Impact(position, 4.5)
					ctx:DamageCircle(position, 4.5, 11, { Knockback = 15 })
				end
			end)
		end
		ctx:Wait(windup + count * 0.15 + 0.8)
	end,
}

-- A ring blast around the Warden: punishes standing right next to it.
Attacks.ShatterNova = {
	Weight = function(_, distance)
		return distance < 14 and 30 or 0
	end,
	Run = function(ctx)
		local radius = 15
		local center = ctx:GroundPosition(ctx.Model)
		local windup = ctx:WindupTime(1.1)
		ctx:Circle(center, radius, windup)
		ctx:Action("Roar", windup, windup + 0.8)
		if not ctx:Wait(windup) then
			return
		end
		ctx:Impact(center, radius)
		ctx:DamageCircle(center, radius, 22, { Knockback = 45 })
		ctx:Wait(1.2)
	end,
}

-- Cracked only: two crossing beams, one through the target and one across it.
Attacks.PrismBeam = {
	Weight = function(ctx)
		return reflections(ctx) and 30 or 0
	end,
	Run = function(ctx, target)
		local length = ctx.Arena.Radius * 2
		local width = 7
		local position = ctx:GroundPosition(target)
		ctx:Face(position)
		local beamCF, beamSize = ctx:FrontBox(length, width)
		local along = beamCF.LookVector
		local across = Vector3.new(-along.Z, 0, along.X)
		local crossCF = CFrame.lookAt(position, position + across)
		local crossSize = Vector3.new(width, 1, length)

		local windup = ctx:WindupTime(1.4)
		ctx:Box(beamCF, beamSize, windup)
		ctx:Box(crossCF, crossSize, windup)
		ctx:Action("Ultimate", windup, windup + 0.9)
		if not ctx:Wait(windup) then
			return
		end
		ctx:DamageBoxes({ { CFrame = beamCF, Size = beamSize }, { CFrame = crossCF, Size = crossSize } }, 30, { Knockback = 25 })
		ctx:Wait(1.3)
	end,
}

MirrorWarden.Attacks = Attacks

function MirrorWarden.ChooseAttack(ctx, distance: number)
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
	return "ReflectedSlam", Attacks.ReflectedSlam
end

return MirrorWarden
