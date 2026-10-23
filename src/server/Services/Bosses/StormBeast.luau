--[[
	StormBeast  (ModuleScript)
	Location: ServerScriptService/Server/Services/Bosses/StormBeast

	BOSS 3: THE STORM BEAST. A huge four-legged beast of living lightning: crackling
	mane, spiked back plates, forked tail. Fast and aggressive; its theme is LIGHTNING
	and MOBILITY. Its legs use Sub_Legs_FL/FR/BL/BR motors, so the client animator
	trots it like a Quadruped Nightmare.

	Every attack is telegraphed and leaves a recovery window.
	  Thunder Pounce   red circle under the target, then it LANDS there   24 dmg, HEAVY
	                   (2 pounces once supercharged, +1 on Nightmare)
	  Chain Lightning  bolts hop between up to 3 targets                  14 dmg + SHOCK
	  Thunderstorm     bolts strike all over the plateau                  12 dmg each
	  Claw Swipe       a wide swipe in front                              18 dmg
	  Static Nova      (supercharged) a ring blast around itself          22 dmg + SHOCK
	  SUPERCHARGED at 50% HP (60% on Nightmare). No healing.

	ctx API (provided by BossService): see BossService "Context" section.
]]

local StormBeast = {}

local RGB = Color3.fromRGB
local Mat = Enum.Material
local V = Vector3.new
local BOLT = RGB(140, 220, 255)
local SUPERCHARGED = RGB(255, 245, 120)

StormBeast.PreferredRange = 10

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
	local p = Instance.new(shape == "Wedge" and "WedgePart" or "Part")
	p.Name = name
	if shape and shape ~= "Wedge" then
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
function StormBeast.BuildModel(groundCF: CFrame, hitboxSize: Vector3)
	local hipHeight = 4
	local rootCF = groundCF * CFrame.new(0, hipHeight + hitboxSize.Y / 2, 0)

	local model = Instance.new("Model")
	model.Name = "StormBeast"
	model:SetAttribute("Archetype", "Quadruped")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = hitboxSize
	root.CFrame = rootCF
	root.Transparency = 1
	root.CanCollide = true
	root.CustomPhysicalProperties = PhysicalProperties.new(4, 0.3, 0)
	root.Parent = model
	model.PrimaryPart = root

	local fur, dark, belly = RGB(38, 44, 70), RGB(22, 24, 38), RGB(70, 80, 110)
	local core = helper(model, "Core_Root", rootCF)
	motor("Joint_Core", root, core, rootCF)
	local function at(x, y, z)
		return rootCF * CFrame.new(x, y, z)
	end

	-- Body: a long, low torso with a deep chest.
	piece(model, core, "Torso", V(8, 6.5, 12), at(0, 1, 0.5), fur, Mat.Slate)
	piece(model, core, "Chest", V(7.5, 7, 4.5), at(0, 0.6, -5), fur, Mat.Slate)
	piece(model, core, "Belly", V(6, 1.2, 10), at(0, -2.4, 0.5), belly, Mat.Slate)
	-- Spiked back plates (lightning-yellow) along the spine.
	for i, z in { -5, -2.5, 0, 2.5, 5 } do
		local height = (i == 2 or i == 3) and 3.6 or 2.6
		piece(model, core, "BackSpike", V(1.2, height, 2.4), at(0, 4.2 + height / 2 - 0.6, z) * CFrame.Angles(math.rad(-25), 0, 0), RGB(255, 225, 80), Mat.Neon, "Wedge")
	end
	-- Crackling mane around the neck.
	for _, offset in { V(-3.4, 3, -6), V(3.4, 3, -6), V(-2.4, 4.6, -5.5), V(2.4, 4.6, -5.5), V(0, 5.4, -5) } do
		piece(model, core, "Mane", V(1.6, 3.2, 1.6), at(offset.X, offset.Y, offset.Z) * CFrame.Angles(math.rad(-30), 0, math.rad(offset.X * 8)), BOLT, Mat.Neon)
	end

	-- Head: wolf-like snout, glowing eyes, lightning horns.
	local neck = at(0, 2.5, -7)
	local head = helper(model, "Head_Root", neck)
	motor("Joint_Head", core, head, neck)
	piece(model, head, "Head", V(5, 4.2, 5), neck * CFrame.new(0, 0.6, -2.4), fur, Mat.Slate)
	piece(model, head, "Snout", V(3.4, 2.4, 3.4), neck * CFrame.new(0, -0.4, -5.6), fur, Mat.Slate)
	piece(model, head, "Jaw", V(3.2, 1, 3.6), neck * CFrame.new(0, -1.8, -5.2), dark, Mat.Slate)
	piece(model, head, "Fang", V(0.5, 1.2, 0.5), neck * CFrame.new(-1.1, -1.4, -7.2), RGB(240, 240, 220), Mat.SmoothPlastic)
	piece(model, head, "Fang", V(0.5, 1.2, 0.5), neck * CFrame.new(1.1, -1.4, -7.2), RGB(240, 240, 220), Mat.SmoothPlastic)
	for _, side in { -1, 1 } do
		piece(model, head, "Eye", V(1, 0.6, 0.3), neck * CFrame.new(1.4 * side, 1.4, -4.95), BOLT, Mat.Neon)
		piece(model, head, "Horn", V(0.8, 3.6, 0.8), neck * CFrame.new(1.8 * side, 3.6, -1.8) * CFrame.Angles(math.rad(-35), 0, math.rad(-20 * side)), BOLT, Mat.Neon)
		piece(model, head, "HornFork", V(0.6, 1.8, 0.6), neck * CFrame.new(2.6 * side, 4.4, -1) * CFrame.Angles(math.rad(-10), 0, math.rad(-55 * side)), BOLT, Mat.Neon)
	end

	-- Four legs on Sub_Legs_* motors (the client animator trots them).
	local legs = { FL = V(-3.2, -2, -4.2), FR = V(3.2, -2, -4.2), BL = V(-3.2, -2, 4.4), BR = V(3.2, -2, 4.4) }
	for name, offset in legs do
		local hip = at(offset.X, offset.Y, offset.Z)
		local legRoot = helper(model, "Leg_" .. name, hip)
		motor("Sub_Legs_" .. name, core, legRoot, hip)
		piece(model, legRoot, "Thigh", V(2.4, 3.4, 2.8), hip * CFrame.new(0, -1.4, 0), fur, Mat.Slate)
		piece(model, legRoot, "Shin", V(1.8, 3, 2), hip * CFrame.new(0, -4, 0.2), dark, Mat.Slate)
		piece(model, legRoot, "Paw", V(2.6, 1, 3.2), hip * CFrame.new(0, -5.6, -0.4), dark, Mat.Slate)
		piece(model, legRoot, "Claws", V(2.4, 0.4, 0.8), hip * CFrame.new(0, -5.8, -2.1), BOLT, Mat.Neon)
	end

	-- Forked lightning tail.
	local tailBase = at(0, 2.5, 6.6)
	local tail = helper(model, "Tail_Root", tailBase)
	motor("Joint_Tail", core, tail, tailBase)
	piece(model, tail, "Tail", V(1.4, 1.4, 6), tailBase * CFrame.new(0, 1.2, 2.8) * CFrame.Angles(math.rad(25), 0, 0), fur, Mat.Slate)
	piece(model, tail, "TailFork", V(0.8, 0.8, 3), tailBase * CFrame.new(-0.9, 2.8, 6.2) * CFrame.Angles(math.rad(35), math.rad(-25), 0), BOLT, Mat.Neon)
	piece(model, tail, "TailFork", V(0.8, 0.8, 3), tailBase * CFrame.new(0.9, 2.8, 6.2) * CFrame.Angles(math.rad(35), math.rad(25), 0), BOLT, Mat.Neon)

	local light = Instance.new("PointLight")
	light.Name = "StormGlow"
	light.Color = BOLT
	light.Range = 24
	light.Brightness = 2
	light.Parent = root
	return model, hipHeight
end

------------------------------------------------------------------------------------------
-- Spawn / phases
------------------------------------------------------------------------------------------
local function recolourNeon(model: Model, color: Color3)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Material == Mat.Neon and d.Name ~= "BackSpike" then
			d.Color = color
		end
	end
	local light = model.PrimaryPart and model.PrimaryPart:FindFirstChild("StormGlow")
	if light then
		light.Color = color
	end
end

local MODE_COLOUR = { Hard = RGB(255, 90, 80), Nightmare = RGB(190, 110, 255) }

function StormBeast.OnSpawn(ctx)
	local color = MODE_COLOUR[ctx.Encounter.Mode]
	if color then
		recolourNeon(ctx.Model, color)
	end
end

local function supercharged(ctx): boolean
	return ctx.Overdrive
end

-- A ring blast around the beast (also used when it supercharges).
local function staticNova(ctx, radius: number, damage: number)
	local center = ctx:GroundPosition(ctx.Model)
	local windup = ctx:WindupTime(1.1)
	ctx:Circle(center, radius, windup)
	ctx:Action("StaticNova", windup, windup + 0.8)
	if not ctx:Wait(windup) then
		return false
	end
	ctx:Impact(center, radius)
	ctx:DamageCircle(center, radius, damage, { Knockback = 40, Status = "Shock" })
	return true
end

function StormBeast.OnPhase(ctx, phase: number)
	if phase ~= 2 then
		return
	end
	ctx:Stop()
	ctx:Banner("SUPERCHARGED!", "The Storm Beast crackles with power!")
	recolourNeon(ctx.Model, SUPERCHARGED)
	local light = ctx.Root:FindFirstChild("StormGlow")
	if light then
		light.Brightness = 4
		light.Range = 32
	end
	ctx.Humanoid.WalkSpeed = ctx.Definition.WalkSpeed * 1.3
	if staticNova(ctx, 12, 14) then
		ctx:Wait(0.8)
	end
end

------------------------------------------------------------------------------------------
-- Attacks
------------------------------------------------------------------------------------------
local Attacks = {}

-- Leaps onto a target's spot (more than once when supercharged / on Nightmare).
Attacks.ThunderPounce = {
	Weight = function(_, distance)
		return distance > 14 and 40 or 20
	end,
	Run = function(ctx, target)
		local pounces = 1 + (supercharged(ctx) and 1 or 0) + (ctx.ModeConfig.ExtraPounces or 0)
		for i = 1, math.min(pounces, 3) do
			local victim = i == 1 and target or (ctx:PickTarget() or target)
			local position = ctx:GroundPosition(victim)
			ctx:Face(position)
			local windup = ctx:WindupTime(i == 1 and 1.0 or 0.8)
			ctx:Circle(position, 8, windup)
			ctx:Action("ThunderPounce", windup, windup + 0.4)
			if not ctx:Wait(windup) then
				return
			end
			ctx:PlaceAt(position, position + (position - ctx.Root.Position))
			ctx:Impact(position, 8)
			ctx:DamageCircle(position, 8, 24, { Heavy = true, Knockback = 40 })
			if i < pounces and not ctx:Wait(0.35) then
				return
			end
		end
		ctx:Wait(1.2) -- recovery: the punish window
	end,
}

-- Bolts hop between up to three targets, one after another.
Attacks.ChainLightning = {
	Weight = function()
		return 25
	end,
	Run = function(ctx)
		local targets = ctx:Targets()
		if #targets == 0 then
			return
		end
		local windup = ctx:WindupTime(0.9)
		ctx:Action("ChainLightning", windup, windup + 0.9)
		local from = ctx.Root.Position + Vector3.new(0, 6, 0)
		local hops = math.min(3, #targets)
		for i = 1, hops do
			local position = ctx:GroundPosition(targets[ctx.Random:NextInteger(1, #targets)])
			local impactTime = windup + (i - 1) * 0.35
			ctx:Circle(position, 5, impactTime)
			local source = from
			task.delay(math.max(impactTime - 0.3, 0), function()
				if ctx:Alive() then
					ctx:Projectile(source, position, 0.3)
				end
			end)
			task.delay(impactTime, function()
				if ctx:Alive() then
					ctx:Impact(position, 5)
					ctx:DamageCircle(position, 5, 14, { Knockback = 10, Status = "Shock" })
				end
			end)
			from = position + Vector3.new(0, 2, 0)
		end
		ctx:Wait(windup + hops * 0.35 + 0.8)
	end,
}

-- Lightning strikes all over the plateau (near players and at random).
Attacks.Thunderstorm = {
	Weight = function(_, distance)
		return distance > 14 and 30 or 15
	end,
	Run = function(ctx)
		local windup = ctx:WindupTime(1.0)
		local count = (supercharged(ctx) and 12 or 8) + (ctx.ModeConfig.BarrageBonus or 0)
		ctx:Action("Thunderstorm", windup, windup + 0.8)
		local targets = ctx:Targets()
		if #targets == 0 then
			return
		end
		for i = 1, count do
			local position
			if i % 2 == 1 then
				local victim = targets[ctx.Random:NextInteger(1, #targets)]
				position = ctx:ClampToArena(ctx:GroundPosition(victim) + Vector3.new(ctx.Random:NextNumber(-8, 8), 0, ctx.Random:NextNumber(-8, 8)))
			else
				local angle = ctx.Random:NextNumber(0, math.pi * 2)
				local distance = ctx.Random:NextNumber(0, ctx.Arena.Radius)
				position = ctx:ClampToArena(ctx.Arena.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
			end
			local impactTime = windup + (i - 1) * 0.12
			ctx:Circle(position, 5, impactTime)
			task.delay(math.max(impactTime - 0.3, 0), function()
				if ctx:Alive() then
					ctx:Projectile(position + Vector3.new(0, 45, 0), position, 0.3)
				end
			end)
			task.delay(impactTime, function()
				if ctx:Alive() then
					ctx:Impact(position, 5)
					ctx:DamageCircle(position, 5, 12, { Knockback = 15 })
				end
			end)
		end
		ctx:Wait(windup + count * 0.12 + 0.8)
	end,
}

-- A wide claw swipe in front.
Attacks.ClawSwipe = {
	Weight = function(_, distance)
		return distance < 14 and 40 or 0
	end,
	Run = function(ctx, target)
		ctx:Face(ctx:Position(target))
		local windup = ctx:WindupTime(0.8)
		local boxCF, boxSize = ctx:FrontBox(12, 14)
		ctx:Box(boxCF, boxSize, windup)
		ctx:Action("Swipe", windup, windup + 0.7)
		if not ctx:Wait(windup) then
			return
		end
		ctx:DamageBox(boxCF, boxSize, 18, { Knockback = 30 })
		ctx:Wait(0.9)
	end,
}

-- Supercharged only: a shocking ring around itself (punishes hugging it).
Attacks.StaticNova = {
	Weight = function(ctx, distance)
		return supercharged(ctx) and (distance < 16 and 30 or 10) or 0
	end,
	Run = function(ctx)
		if staticNova(ctx, 15, 22) then
			ctx:Wait(1.1)
		end
	end,
}

StormBeast.Attacks = Attacks

function StormBeast.ChooseAttack(ctx, distance: number)
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
	return "ThunderPounce", Attacks.ThunderPounce
end

return StormBeast
