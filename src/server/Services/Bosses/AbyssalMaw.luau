--[[
	AbyssalMaw  (ModuleScript)
	Location: ServerScriptService/Server/Services/Bosses/AbyssalMaw

	BOSS 4: THE ABYSSAL MAW. A colossal worm-like maw rising out of the ground: rings of
	teeth, glowing eyes, two great tentacles. Its theme is BURROWING and DEVOURING: it
	travels underground and erupts under its prey.

	Every attack is telegraphed and leaves a recovery window.
	  Burrow & Erupt    sinks out of reach, red circle under a target,   30 dmg, HEAVY
	                    then bursts up there
	  Tentacle Slam     long red lines toward up to 3 targets             20 dmg
	  Abyssal Inhale    blue ring pulls everyone in, then a bite          32 dmg, HEAVY
	  Ink Spit          globs land around targets                         12 dmg + WEAKEN
	  Abyss Pools       (after the abyss opens) dark pools that keep      6 dmg / pulse
	                    hurting anyone standing in them
	  THE ABYSS OPENS at 50% HP (60% on Nightmare). No healing.

	ctx API (provided by BossService): see BossService "Context" section.
]]

local AbyssalMaw = {}

local RGB = Color3.fromRGB
local Mat = Enum.Material
local V = Vector3.new
local GLOW = RGB(90, 255, 200)
local OPEN = RGB(255, 60, 90)

AbyssalMaw.PreferredRange = 14

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
-- Returns model, hipHeight. Its lower body sinks into the floor (it lives below).
function AbyssalMaw.BuildModel(groundCF: CFrame, hitboxSize: Vector3)
	local hipHeight = 0.5
	local rootCF = groundCF * CFrame.new(0, hipHeight + hitboxSize.Y / 2, 0)

	local model = Instance.new("Model")
	model.Name = "AbyssalMaw"
	model:SetAttribute("Archetype", "Floating") -- slow sway
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = hitboxSize
	root.CFrame = rootCF
	root.Transparency = 1
	root.CanCollide = true
	root.CustomPhysicalProperties = PhysicalProperties.new(6, 0.3, 0)
	root.Parent = model
	model.PrimaryPart = root

	local hide, plate, gum, tooth = RGB(40, 46, 52), RGB(62, 74, 70), RGB(120, 40, 60), RGB(230, 225, 205)
	local core = helper(model, "Core_Root", rootCF)
	motor("Joint_Core", root, core, rootCF)
	local function at(x, y, z)
		return rootCF * CFrame.new(x, y, z)
	end

	-- Segmented body rising out of the ground (bottom segments sink below the floor).
	for i, segment in { { -10, 13 }, { -6, 12 }, { -2, 11 }, { 2, 10.5 } } do
		local y, width = segment[1], segment[2]
		piece(model, core, "Segment", V(4, width, width), at(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), i % 2 == 0 and plate or hide, Mat.Slate, Enum.PartType.Cylinder)
		piece(model, core, "SegmentRidge", V(0.6, width + 0.6, width + 0.6), at(0, y + 2, 0) * CFrame.Angles(0, 0, math.rad(90)), GLOW, Mat.Neon, Enum.PartType.Cylinder)
	end

	-- Head: a huge round maw facing forward, ringed with teeth.
	local neck = at(0, 5, 0)
	local head = helper(model, "Head_Root", neck)
	motor("Joint_Head", core, head, neck)
	local mouth = neck * CFrame.new(0, 1.5, -1.2)
	piece(model, head, "Head", V(12, 11, 9), neck * CFrame.new(0, 1.5, 1), hide, Mat.Slate)
	piece(model, head, "Maw", V(1, 8.5, 8.5), mouth * CFrame.new(0, 0, -3.4) * CFrame.Angles(0, math.rad(90), 0), gum, Mat.SmoothPlastic, Enum.PartType.Cylinder)
	piece(model, head, "Throat", V(1.1, 5, 5), mouth * CFrame.new(0, 0, -3.5) * CFrame.Angles(0, math.rad(90), 0), RGB(10, 5, 12), Mat.SmoothPlastic, Enum.PartType.Cylinder)
	for i = 1, 12 do
		local angle = (i / 12) * math.pi * 2
		local radius = 3.6
		piece(model, head, "Tooth", V(0.7, 1.8, 0.7), mouth * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, -4) * CFrame.Angles(0, 0, angle + math.rad(90)), tooth, Mat.SmoothPlastic, "Wedge")
	end
	-- Eyes: a cluster of glowing dots above the maw.
	for _, offset in { V(-3.4, 5.4), V(3.4, 5.4), V(-1.6, 6.4), V(1.6, 6.4), V(0, 5.6) } do
		piece(model, head, "Eye", V(1, 1, 0.4), neck * CFrame.new(offset.X, offset.Y, -3.6), GLOW, Mat.Neon, Enum.PartType.Ball)
	end

	-- Two great tentacles on the arm joints (the animator swings them for attacks).
	for _, side in { -1, 1 } do
		local shoulder = at(6.4 * side, 2, -1)
		local arm = helper(model, side < 0 and "LeftArm_Root" or "RightArm_Root", shoulder)
		motor(side < 0 and "Joint_LeftArm" or "Joint_RightArm", core, arm, shoulder)
		for i = 1, 4 do
			local size = 2.6 - i * 0.4
			piece(model, arm, "Tentacle", V(size, 3, size), shoulder * CFrame.new(1.2 * side * i, -i * 1.6, -i * 0.8) * CFrame.Angles(math.rad(-20), 0, math.rad(35 * side)), i % 2 == 0 and plate or hide, Mat.Slate)
		end
		piece(model, arm, "TentacleTip", V(0.8, 2.2, 0.8), shoulder * CFrame.new(6 * side, -7.6, -4) * CFrame.Angles(math.rad(-20), 0, math.rad(35 * side)), GLOW, Mat.Neon)
	end

	local light = Instance.new("PointLight")
	light.Name = "MawGlow"
	light.Color = GLOW
	light.Range = 26
	light.Brightness = 2
	light.Parent = root
	return model, hipHeight
end

------------------------------------------------------------------------------------------
-- Spawn / phases
------------------------------------------------------------------------------------------
local function recolourGlow(model: Model, color: Color3)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Material == Mat.Neon then
			d.Color = color
		end
	end
	local light = model.PrimaryPart and model.PrimaryPart:FindFirstChild("MawGlow")
	if light then
		light.Color = color
	end
end

local MODE_COLOUR = { Hard = RGB(255, 140, 60), Nightmare = RGB(190, 90, 255) }

function AbyssalMaw.OnSpawn(ctx)
	local color = MODE_COLOUR[ctx.Encounter.Mode]
	if color then
		recolourGlow(ctx.Model, color)
	end
end

local Attacks = {}

function AbyssalMaw.OnPhase(ctx, phase: number)
	if phase ~= 2 then
		return
	end
	ctx:Stop()
	ctx:Banner("THE ABYSS OPENS!", "Dark pools spread across the floor...")
	ctx:Action("Roar", 0.3, 2)
	recolourGlow(ctx.Model, OPEN)
	if not ctx:Wait(1) then
		return
	end
	Attacks.AbyssPools.Run(ctx)
end

------------------------------------------------------------------------------------------
-- Attacks
------------------------------------------------------------------------------------------
-- Sinks out of reach, then bursts up under a target. Always comes back up, even if the
-- fight ends or it's staggered mid-burrow.
Attacks.BurrowErupt = {
	Weight = function(_, distance)
		return distance > 16 and 40 or 25
	end,
	Run = function(ctx, target)
		ctx:Action("Burrow", 0.3, 1)
		if not ctx:Wait(0.5) then
			return
		end
		local home = ctx:GroundPosition(ctx.Model)
		ctx.Root.Anchored = true
		ctx.Model:PivotTo(ctx.Root.CFrame - Vector3.new(0, 45, 0)) -- underground: can't be hit
		local function emerge(position: Vector3)
			ctx.Root.Anchored = false
			ctx:PlaceAt(position)
		end
		if not ctx:Wait(0.6) then
			emerge(home)
			return
		end
		local victim = ctx:PickTarget() or target
		local position = ctx:GroundPosition(victim)
		local windup = ctx:WindupTime(1.3)
		ctx:Circle(position, 10, windup)
		if not ctx:Wait(windup) then
			emerge(home)
			return
		end
		emerge(position)
		ctx:Action("Erupt", 0.05, 0.8)
		ctx:Impact(position, 10)
		ctx:DamageCircle(position, 10, 30, { Heavy = true, Knockback = 50 })
		ctx:Wait(1.5) -- recovery: the punish window
	end,
}

-- Long lines lashing toward up to three targets.
Attacks.TentacleSlam = {
	Weight = function()
		return 30
	end,
	Run = function(ctx)
		local targets = ctx:Targets()
		if #targets == 0 then
			return
		end
		local origin = ctx:GroundPosition(ctx.Model)
		local boxes = {}
		for i = 1, math.min(3, #targets) do
			local toward = ctx:GroundPosition(targets[i]) - origin
			local direction = toward.Magnitude > 0.1 and toward.Unit or ctx.Root.CFrame.LookVector
			local length = 32
			local middle = origin + direction * (length / 2 + 3)
			table.insert(boxes, { CFrame = CFrame.lookAt(middle, middle + direction), Size = Vector3.new(6, 1, length) })
		end
		local windup = ctx:WindupTime(1.1)
		for _, box in boxes do
			ctx:Box(box.CFrame, box.Size, windup)
		end
		ctx:Action("TentacleSlam", windup, windup + 0.8)
		if not ctx:Wait(windup) then
			return
		end
		ctx:DamageBoxes(boxes, 20, { Knockback = 25 })
		ctx:Wait(1.1)
	end,
}

-- Pulls everyone in, then bites.
Attacks.AbyssalInhale = {
	Weight = function(_, distance)
		return distance > 12 and 25 or 15
	end,
	Run = function(ctx)
		local windup = ctx:WindupTime(1.2)
		local center = ctx:GroundPosition(ctx.Model)
		ctx:Circle(center, 32, windup, "Pull")
		ctx:Circle(center, 9, windup + 0.7, "Hostile")
		ctx:Action("Inhale", windup, windup + 1.4)
		if not ctx:Wait(windup) then
			return
		end
		ctx:Pull(32, 55)
		if not ctx:Wait(0.7) then
			return
		end
		ctx:Impact(center, 9)
		ctx:DamageCircle(center, 9, 32, { Heavy = true, Knockback = 40 })
		ctx:Wait(1.2)
	end,
}

-- Ink globs land around targets and WEAKEN.
Attacks.InkSpit = {
	Weight = function()
		return 25
	end,
	Run = function(ctx)
		local targets = ctx:Targets()
		if #targets == 0 then
			return
		end
		local windup = ctx:WindupTime(1.0)
		local count = (ctx.Overdrive and 6 or 4) + (ctx.ModeConfig.BarrageBonus or 0)
		ctx:Action("InkSpit", windup, windup + 0.8)
		local mouth = ctx.Root.Position + Vector3.new(0, 8, 0)
		for i = 1, count do
			local victim = targets[ctx.Random:NextInteger(1, #targets)]
			local position = ctx:ClampToArena(ctx:GroundPosition(victim) + Vector3.new(ctx.Random:NextNumber(-7, 7), 0, ctx.Random:NextNumber(-7, 7)))
			local impactTime = windup + (i - 1) * 0.2
			ctx:Circle(position, 6, impactTime)
			task.delay(math.max(impactTime - 0.5, 0), function()
				if ctx:Alive() then
					ctx:Projectile(mouth, position, 0.5)
				end
			end)
			task.delay(impactTime, function()
				if ctx:Alive() then
					ctx:Impact(position, 6)
					ctx:DamageCircle(position, 6, 12, { Knockback = 10, Status = "Weaken" })
				end
			end)
		end
		ctx:Wait(windup + count * 0.2 + 0.8)
	end,
}

-- After the abyss opens: dark pools that keep hurting anyone standing in them.
Attacks.AbyssPools = {
	Weight = function(ctx)
		return ctx.Overdrive and 25 or 0
	end,
	Run = function(ctx)
		local targets = ctx:Targets()
		if #targets == 0 then
			return
		end
		local big = ctx.ModeConfig.BigPools == true
		local radius = big and 9 or 7
		local count = big and 5 or 3
		local points = {}
		for i = 1, count do
			local position
			if i <= #targets then
				position = ctx:GroundPosition(targets[i])
			else
				local angle = ctx.Random:NextNumber(0, math.pi * 2)
				position = ctx.Arena.Center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * ctx.Random:NextNumber(8, ctx.Arena.Radius - 8)
			end
			table.insert(points, ctx:ClampToArena(position))
		end
		local windup = ctx:WindupTime(1.0)
		local pulses, interval = 4, 0.75
		ctx:Action("AbyssPools", windup, windup + 0.6)
		for _, point in points do
			ctx:Circle(point, radius, windup + pulses * interval) -- stays up while it hurts
		end
		if not ctx:Wait(windup) then
			return
		end
		for _ = 1, pulses do
			for _, point in points do
				ctx:Impact(point, radius)
			end
			ctx:DamageCircles(points, radius, 6, { Ground = true }) -- (a hovering Nightmare floats over the pools)
			if not ctx:Wait(interval) then
				return
			end
		end
		ctx:Wait(0.5)
	end,
}

AbyssalMaw.Attacks = Attacks

function AbyssalMaw.ChooseAttack(ctx, distance: number)
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
	return "BurrowErupt", Attacks.BurrowErupt
end

return AbyssalMaw
