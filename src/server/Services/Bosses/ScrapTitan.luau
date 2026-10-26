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
		piece(model, core, "Shoulder", V(3.2, 3.2, 3.2), at(5.6 * side, 4.2, 0), metal, Mat.Metal, Enum.PartType.Ball)
	end
	-- Legs: jointed at the hip (Sub_Legs_L/R, like a Biped Nightmare's) and the knee
	-- (Knee_L/R), so it can squat, leap and land instead of sliding around on stilts.
	for _, side in { -1, 1 } do
		local tag = side < 0 and "L" or "R"
		local hip = at(2.5 * side, -4.2, 0)
		local thigh = helper(model, "Legs_" .. tag, hip)
		motor("Sub_Legs_" .. tag, core, thigh, hip)
		piece(model, thigh, "Thigh", V(2.8, 3.2, 2.8), hip * CFrame.new(0, -1.5, 0), rust, Mat.CorrodedMetal)
		piece(model, thigh, "KneeCap", V(2.4, 2.4, 2.4), hip * CFrame.new(0, -3.1, -0.3), dark, Mat.Metal, Enum.PartType.Ball)
		local kneeCF = hip * CFrame.new(0, -3.1, 0)
		local shin = helper(model, "Shin_" .. tag, kneeCF)
		motor("Knee_" .. tag, thigh, shin, kneeCF)
		piece(model, shin, "Leg", V(2.4, 2.6, 2.4), kneeCF * CFrame.new(0, -1.3, 0), rust, Mat.CorrodedMetal)
		piece(model, shin, "Foot", V(3.4, 1, 4.2), kneeCF * CFrame.new(0, -2.3, -0.6), dark, Mat.Metal)
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

-- GROUND SLAM (signature): a real leap. It squats with both fists rising, springs at the
-- marked spot (a ballistic jump timed to land on the impact), and brings its whole weight
-- down: both fists into the floor, a ground shockwave throwing everyone in the circle
-- OUTWARD from the impact, dust and debris flying, the camera jolting by distance. It
-- holds the landing (punish window). Keyframed animation: BossPoses.ScrapTitan.Slam (its
-- Hit marker lands on the impact; the leap leaves the floor at its "spring" key).
local SLAM_RADIUS = 11
local FIST_REACH = 7 -- the fists land this far in front of where its body lands
local SLAM_AIR = 0.5 -- seconds in the air (the animation's spring -> impact, at base speed)
Attacks.GroundSlam = {
	Weight = function(_, distance)
		return distance < 18 and 25 or 35
	end,
	Run = function(ctx, target)
		local function slam(victim, windupBase)
			local position = ctx:GroundPosition(victim)
			ctx:Face(position)
			local windup = ctx:WindupTime(windupBase)
			ctx:Circle(position, SLAM_RADIUS, windup)
			ctx:Action("Slam", windup, windup + 0.6)
			-- spring off the floor so it lands with its fists on the mark at the impact
			local air = math.min(SLAM_AIR * windup / 1.3, windup - 0.2)
			if not ctx:Wait(windup - air) then
				return false
			end
			local toward = (position - ctx.Root.Position) * Vector3.new(1, 0, 1)
			local landing = toward.Magnitude > FIST_REACH and position - toward.Unit * FIST_REACH or ctx.Root.Position
			ctx:Leap(ctx:ClampToArena(landing), air)
			if not ctx:Wait(air) then
				return false
			end
			ctx:Impact(position, SLAM_RADIUS)
			ctx:SlamFX(position, SLAM_RADIUS, 1)
			ctx:DamageCircle(position, SLAM_RADIUS, 28, { Heavy = true, Knockback = 40, Radial = position })
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

------------------------------------------------------------------------------------------
-- SIGNATURE COMBOS (ctx:Combo: one continuous clip, several telegraphed beats, each
-- landing on its animation frame; BossPoses.ScrapTitan.<name>)
------------------------------------------------------------------------------------------
local function frontPoint(ctx, distance: number): Vector3
	local look = (ctx.Root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	return ctx:ClampToArena(ctx:GroundPosition(ctx.Model) + look * (ctx.Root.Size.Z / 2 + distance))
end
local function boxBeat(at: number, length: number, width: number, damage: number, opts)
	return {
		At = at,
		Telegraph = function(ctx, lead)
			local cf, size = ctx:FrontBox(length, width)
			ctx:Box(cf, size, lead)
			return { cf, size }
		end,
		Strike = function(ctx, box)
			ctx:DamageBox(box[1], box[2], damage, opts)
		end,
	}
end

-- WRECKING COMBO: the wrecking ball swung across, backhanded back the other way, then
-- raised and smashed down in front.
Attacks.WreckingCombo = {
	Weight = function(_, distance)
		return distance < 18 and 22 or 0
	end,
	Run = function(ctx, target)
		ctx:Face(ctx:Position(target))
		ctx:Combo("WreckingCombo", 3.0, {
			boxBeat(0.85, 16, 14, 18, { Knockback = 20 }),
			boxBeat(1.45, 16, 14, 18, { Knockback = 25 }),
			{
				At = 2.15,
				Telegraph = function(c, lead)
					local point = frontPoint(c, 6)
					c:Circle(point, 8, lead)
					return point
				end,
				Strike = function(c, point)
					c:Impact(point, 8)
					c:SlamFX(point, 8, 0.9)
					c:DamageCircle(point, 8, 26, { Heavy = true, Knockback = 40, Radial = point })
				end,
			},
		}, 1.4)
	end,
}

-- MAGNET UPPERCUT: the magnet drags everyone in, the wrecking ball comes up underneath
-- whoever arrived, then a stomp that throws everyone off it.
Attacks.MagnetUppercut = {
	Weight = function(_, distance)
		return distance < 26 and 18 or 10
	end,
	Run = function(ctx, target)
		ctx:Face(ctx:Position(target))
		ctx:Combo("MagnetUppercut", 2.8, {
			{
				At = 1.0,
				Telegraph = function(c, lead)
					c:Circle(c:GroundPosition(c.Model), 26, lead, "Pull")
				end,
				Strike = function(c)
					c:Pull(26, 55)
				end,
			},
			boxBeat(1.5, 10, 11, 22, { Heavy = true, Knockback = 35 }),
			{
				At = 2.15,
				Telegraph = function(c, lead)
					local center = c:GroundPosition(c.Model)
					c:Circle(center, 10, lead)
					return center
				end,
				Strike = function(c, center)
					c:Impact(center, 10)
					c:SlamFX(center, 10, 0.8)
					c:DamageCircle(center, 10, 20, { Knockback = 35, Radial = center })
				end,
			},
		}, 1.2)
	end,
}

-- SCRAP QUAKE: stomp, stomp, then both fists into the floor and the scrap around it erupts.
Attacks.ScrapQuake = {
	Weight = function(_, distance)
		return distance < 20 and 18 or 8
	end,
	Run = function(ctx, target)
		ctx:Face(ctx:Position(target))
		local function stomp(at: number, side: number)
			return {
				At = at,
				Telegraph = function(c, lead)
					local foot = c:ClampToArena((c.Root.CFrame * CFrame.new(side * 4, 0, -2)).Position)
					c:Circle(foot, 7, lead)
					return foot
				end,
				Strike = function(c, foot)
					c:Impact(foot, 7)
					c:SlamFX(foot, 7, 0.6)
					c:DamageCircle(foot, 7, 16, { Knockback = 25, Radial = foot })
				end,
			}
		end
		ctx:Combo("ScrapQuake", 2.8, {
			stomp(0.7, -1),
			stomp(1.2, 1),
			{
				At = 1.85,
				Warn = 0.65,
				Telegraph = function(c, lead)
					local point = frontPoint(c, 5)
					local ring = {}
					for i = 1, 6 do
						local spot = c:ClampToArena(point + CFrame.Angles(0, math.rad(60 * i), 0):VectorToWorldSpace(Vector3.new(0, 0, 15)))
						table.insert(ring, spot)
						c:Circle(spot, 4.5, lead)
					end
					c:Circle(point, 10, lead)
					return { Point = point, Ring = ring }
				end,
				Strike = function(c, data)
					c:Impact(data.Point, 10)
					c:SlamFX(data.Point, 10, 1)
					c:DamageCircle(data.Point, 10, 26, { Heavy = true, Knockback = 40, Radial = data.Point })
					for _, spot in data.Ring do
						c:Impact(spot, 4.5)
					end
					c:DamageCircles(data.Ring, 4.5, 12, { Knockback = 15 })
				end,
			},
		}, 1.5)
	end,
}

-- REACTOR RUSH (Overdrive only): it drops its shoulder and charges straight through the
-- target's spot, backhands whoever is in front, then the reactor bursts around it.
Attacks.ReactorRush = {
	Weight = function(ctx, distance)
		return ctx.Overdrive and (distance > 12 and 28 or 14) or 0
	end,
	Run = function(ctx, target)
		ctx:Face(ctx:Position(target))
		local from = ctx:GroundPosition(ctx.Model)
		ctx:Combo("ReactorRush", 3.2, {
			{
				At = 1.0,
				Telegraph = function(c, lead)
					local aim = c:GroundPosition(target)
					local direction = (aim - from) * Vector3.new(1, 0, 1)
					direction = direction.Magnitude > 0.1 and direction.Unit or (c.Root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
					local stop = c:ClampToArena(aim + direction * 6)
					local length = (stop - from).Magnitude
					local mid = (from + stop) / 2
					local cf = CFrame.lookAt(mid, mid + direction)
					c:Box(cf, Vector3.new(12, 1, length), lead)
					return { Stop = stop, CF = cf, Size = Vector3.new(12, 1, length) }
				end,
				Strike = function(c, data)
					c:Dash(data.Stop, 0.35)
					c:DamageBox(data.CF, data.Size, 24, { Heavy = true, Knockback = 45 })
				end,
			},
			boxBeat(1.6, 14, 14, 18, { Knockback = 30 }),
			{
				At = 2.3,
				Warn = 0.7,
				Telegraph = function(c, lead)
					local center = c:GroundPosition(c.Model)
					c:Circle(center, 13, lead)
					return center
				end,
				Strike = function(c, center)
					c:Impact(center, 13)
					c:SlamFX(center, 13, 1.2)
					c:DamageCircle(center, 13, 22, { Knockback = 45, Radial = center })
				end,
			},
		}, 1.6)
	end,
}

ScrapTitan.Attacks = Attacks

function ScrapTitan.ChooseAttack(ctx, distance: number)
	-- Studio testing: workspace attribute ForceBossAttack = "GroundSlam" repeats that attack
	local forced = game:GetService("RunService"):IsStudio() and workspace:GetAttribute("ForceBossAttack")
	if forced and Attacks[forced] then
		return forced, Attacks[forced]
	end
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
