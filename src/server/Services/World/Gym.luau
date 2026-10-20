--[[
	Gym  (ModuleScript)
	Location: ServerScriptService/Server/Services/World/Gym

	THE NIGHTMARE GYM (AFK training), built in code like the rest of the world:

	  * The lift in the Forge (GymDefinitions.HubEntrance): a reinforced blockhouse with
	    sliding freight doors (opened per player by GymController), a pitch-black shaft
	    behind them (the camera pushes through it on the way in), signage, pipes, steam,
	    and the "EnterGym" prompt.
	  * The hall itself, far from the map (GymDefinitions.Origin): an underground monster
	    training facility. Six training bays (gantry, heavy bag, mirror, mat, a bench for
	    the Handler, a reward screen and a reward crate), a reinforced centre aisle with
	    weights, a cable machine, a giant dumbbell and reinforced dummies, lockers, banners,
	    trophy cabinets, display cases showing the real odds of each reward tier, a live
	    statistics wall, trusses, ducts, fans, lamps and steam.

	Gym.BuildBag(bay, centerY) (re)hangs a bay's heavy bag at a height that suits the
	Nightmare training there (GymService calls it). The bag is a visual: each client swings
	it from the strike markers of the Nightmare's animation (GymController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GymDefinitions = require(Shared:WaitForChild("GymDefinitions"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local Gym = {}

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad = math.rad
local M = Enum.Material
local P, ball, cyl, rod, disc = Kit.P, Kit.Ball, Kit.Cyl, Kit.Rod, Kit.Disc
local glow = { NoCollide = true, Shadow = false }
local deco = { NoCollide = true }

local STEEL = RGB(58, 60, 70)
local STEEL_DARK = RGB(30, 30, 36)
local CONCRETE = RGB(70, 66, 74)
local RED = RGB(255, 60, 90)
local RED_DIM = RGB(150, 30, 52)
local HAZARD_Y, HAZARD_K = RGB(230, 180, 30), RGB(24, 22, 24)
local WARM = RGB(255, 214, 170)
local BLACK = RGB(0, 0, 0)

local HALF = GymDefinitions.HallHalf
local BAG = GymDefinitions.Bag

local hall: Model? -- the built hall (BuildBag parents bags into it)

------------------------------------------------------------------------------------------
-- Small builders
------------------------------------------------------------------------------------------
-- Alternating yellow / black blocks between a and b (hazard striping).
local function hazard(parent, a: Vector3, b: Vector3, w: number, h: number, pieces: number)
	for i = 0, pieces - 1 do
		local p0 = a:Lerp(b, i / pieces)
		local p1 = a:Lerp(b, (i + 1) / pieces)
		rod(parent, p0, p1, w, h, i % 2 == 0 and HAZARD_Y or HAZARD_K, M.SmoothPlastic)
	end
end

-- A hanging industrial lamp: cable, shade, glowing bulb, a spotlight pointing down.
local function hangingLamp(parent, top: Vector3, drop: number, range: number?)
	local bottom = top - V3(0, drop, 0)
	cyl(parent, top, bottom, 0.15, STEEL_DARK, M.Metal, deco)
	disc(parent, CF(bottom - V3(0, 0.3, 0)), 3.4, 0.6, STEEL, M.Metal, deco)
	disc(parent, CF(bottom - V3(0, 0.75, 0)), 2.6, 0.3, STEEL_DARK, M.Metal, deco)
	local bulb = ball(parent, bottom - V3(0, 0.9, 0), 1, WARM, M.Neon, glow)
	Kit.Light(bulb, WARM, 3.2, range or 44, { Kind = "SpotLight", Face = Enum.NormalId.Bottom, Angle = 90, Shadows = true })
	return bulb
end

-- A wall fan in a square housing; spins about the wall's normal (the frame's Z).
local function wallFan(parent, cf: CFrame, size: number)
	P(parent, cf * CF(0, 0, 0.4), V3(size + 1.2, size + 1.2, 0.8), STEEL_DARK, M.DiamondPlate)
	local fan = Kit.Model("Fan", parent)
	disc(fan, cf * ANG(rad(90), 0, 0), size * 0.22, 0.6, STEEL, M.Metal, deco)
	for k = 0, 4 do
		P(fan, cf * ANG(0, 0, rad(k * 72)) * CF(0, size * 0.27, -0.1) * ANG(0, rad(18), 0), V3(size * 0.18, size * 0.42, 0.12), STEEL, M.Metal, deco)
	end
	fan.WorldPivot = cf
	Kit.Tag(fan, "WSpin", { Speed = 2.4, Axis = "Z" })
	-- grille
	for k = -2, 2 do
		P(parent, cf * CF(k * size * 0.2, 0, -0.35), V3(0.12, size, 0.12), STEEL_DARK, M.Metal, deco)
	end
end

local function steam(parent, cf: CFrame, rate: number?)
	Kit.Emitter(parent, cf, V3(1.4, 0.2, 1.4), Kit.TEX.Smoke, {
		Color = ColorSequence.new(RGB(200, 196, 210), RGB(120, 112, 130)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.75), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new(1.2, 5),
		Lifetime = NumberRange.new(2, 3.5),
		Rate = rate or 4,
		Speed = NumberRange.new(2.5, 4.5),
		SpreadAngle = Vector2.new(12, 12),
		Acceleration = V3(0, 0.6, 0),
		RotSpeed = NumberRange.new(-20, 20),
		Rotation = NumberRange.new(0, 360),
	})
end

-- A sliding freight door pair in an opening of `width` x `height` centred on cf
-- (cf faces OUT of the doorway, -Z). Each leaf is a Model the client slides sideways.
local function freightDoor(parent, name: string, cf: CFrame, width: number, height: number, open: boolean)
	local door = Kit.Model(name, parent)
	local leafW = width / 2
	for _, side in { -1, 1 } do
		local leaf = Kit.Model(side < 0 and "DoorL" or "DoorR", door)
		local closed = cf * CF(side * leafW / 2, height / 2, 0)
		local panel = P(leaf, closed, V3(leafW, height, 0.7), RGB(64, 66, 74), M.DiamondPlate, { Name = "Panel" })
		leaf.PrimaryPart = panel
		hazard(leaf, (closed * CF(-leafW / 2, -height / 2 + 0.7, -0.4)).Position, (closed * CF(leafW / 2, -height / 2 + 0.7, -0.4)).Position, 1.1, 0.12, 5)
		hazard(leaf, (closed * CF(-leafW / 2, height / 2 - 0.7, -0.4)).Position, (closed * CF(leafW / 2, height / 2 - 0.7, -0.4)).Position, 1.1, 0.12, 5)
		for k = -1, 1 do
			P(leaf, closed * CF(0, k * height * 0.25, -0.42), V3(leafW - 1, 0.25, 0.12), RGB(40, 40, 46), M.Metal)
		end
		-- the window slot in each leaf
		P(leaf, closed * CF(side * -leafW * 0.18, height * 0.2, -0.36), V3(leafW * 0.35, 1.2, 0.05), RGB(255, 120, 140), M.Neon, glow)
		leaf:SetAttribute("Slide", side * (leafW + 0.4)) -- studs along the frame's X when open
		leaf:SetAttribute("ClosedCF", leaf:GetPivot())
		if open then
			leaf:PivotTo(leaf:GetPivot() * CF(side * (leafW + 0.4), 0, 0))
		end
	end
	return door
end

------------------------------------------------------------------------------------------
-- The lift in the Forge
------------------------------------------------------------------------------------------
local function buildLift(root)
	local cf = GymDefinitions.EntranceCF()
	local L, C = Kit.Frame(cf)
	local g = Kit.Model("GymLift", root)

	P(g, C(0, 0.25, 7), V3(38, 0.5, 26), CONCRETE, M.Concrete)
	-- chevrons on the floor leading to the door
	for k = 1, 3 do
		local z = -3 - k * 2.2
		rod(g, L(-2, 0.55, z), L(0, 0.55, z - 1.2), 0.5, 0.06, HAZARD_Y, M.Neon, glow)
		rod(g, L(2, 0.55, z), L(0, 0.55, z - 1.2), 0.5, 0.06, HAZARD_Y, M.Neon, glow)
	end

	-- the blockhouse (door opening x -6..6, y 0..12 in the front face at z = 0)
	local WALL = RGB(78, 72, 82)
	P(g, C(-11, 9, 0.75), V3(10, 18, 1.5), WALL, M.Concrete)
	P(g, C(11, 9, 0.75), V3(10, 18, 1.5), WALL, M.Concrete)
	P(g, C(0, 15, 0.75), V3(12, 6, 1.5), WALL, M.Concrete)
	P(g, C(-15.25, 9, 9.75), V3(1.5, 18, 18), WALL, M.Concrete)
	P(g, C(15.25, 9, 9.75), V3(1.5, 18, 18), WALL, M.Concrete)
	P(g, C(0, 9, 18.25), V3(32, 18, 1.5), WALL, M.Concrete)
	P(g, C(0, 18.5, 9.5), V3(34, 1, 21), STEEL_DARK, M.DiamondPlate)
	-- reinforcing ribs and a steel skirt
	for _, x in { -15.5, -6.9, 6.9, 15.5 } do
		P(g, C(x, 9, -0.2), V3(1.3, 18, 0.9), STEEL, M.Metal)
	end
	P(g, C(0, 1, -0.1), V3(32, 2, 0.6), STEEL_DARK, M.DiamondPlate)

	-- the pitch-black shaft behind the doors (black neon ignores lighting: truly dark)
	local shaft = Kit.Model("Shaft", g)
	P(shaft, C(0, 0.55, 8), V3(12, 0.1, 14), BLACK, M.Neon, glow)
	P(shaft, C(-6.05, 6, 8), V3(0.1, 12, 14), BLACK, M.Neon, glow)
	P(shaft, C(6.05, 6, 8), V3(0.1, 12, 14), BLACK, M.Neon, glow)
	P(shaft, C(0, 6, 15), V3(12, 12, 0.1), BLACK, M.Neon, glow)
	P(shaft, C(0, 12.05, 8), V3(12, 0.1, 14), BLACK, M.Neon, glow)

	-- door frame (hazard striped) and the doors themselves
	hazard(g, L(-6.6, 0.5, -0.5), L(-6.6, 12.6, -0.5), 1.2, 1.2, 8)
	hazard(g, L(6.6, 0.5, -0.5), L(6.6, 12.6, -0.5), 1.2, 1.2, 8)
	hazard(g, L(-7.2, 13, -0.5), L(7.2, 13, -0.5), 1.2, 1.2, 9)
	freightDoor(g, "Door", C(0, 0.5, 0.35), 12, 12, false)

	-- signage
	Kit.Sign(g, CF(L(0, 15.6, -0.25), L(0, 15.6, -30)), V3(13, 2.6, 0.4), "NIGHTMARE GYM", RED, { Color = RGB(14, 10, 16) })
	Kit.Sign(g, CF(L(0, 17.4, -0.25), L(0, 17.4, -30)), V3(10, 0.9, 0.3), "SUBLEVEL B2  ·  AFK TRAINING", RGB(230, 220, 240), { Color = RGB(14, 10, 16) })
	Kit.Billboard(g, L(0, 28, 6), "THE NIGHTMARE GYM", "AFK training · rewards while you rest", RED, Vector2.new(26, 6), 320)

	-- warning beacons on the roof corners
	for _, x in { -14.5, 14.5 } do
		disc(g, C(x, 19.2, -0.2), 1.6, 0.4, STEEL_DARK, M.Metal)
		local beacon = ball(g, L(x, 19.9, -0.2), 1.2, RGB(255, 60, 40), M.Neon, glow)
		Kit.Tag(Kit.Light(beacon, RGB(255, 70, 40), 2, 18), "WFlicker", { Min = 0.5, Max = 3, Speed = 5 })
	end
	-- floodlights either side of the door
	for _, x in { -17.5, 17.5 } do
		Kit.Lamp(g, L(x, 0.5, -4), WARM, 13, STEEL_DARK)
	end

	-- pipes up the walls and across the roof, with steam from the vents
	for _, x in { -16.6, 16.6 } do
		cyl(g, L(x, 0.5, 3), L(x, 20.5, 3), 1, RGB(110, 60, 50), M.CorrodedMetal)
		cyl(g, L(x, 20.5, 3), L(x, 20.5, 14), 1, RGB(110, 60, 50), M.CorrodedMetal)
		for y = 4, 18, 7 do
			disc(g, C(x, y, 3), 1.5, 0.35, STEEL_DARK, M.Metal)
		end
	end
	for _, x in { -8, 8 } do
		P(g, C(x, 20, 12), V3(5, 2, 5), STEEL, M.Metal)
		wallFan(g, C(x, 21.05, 12, 90, 0, 0), 3.6) -- housing below, blades facing up
		steam(g, C(x, 21.4, 12), 3)
	end

	-- an advertising heavy bag on a jib beside the door
	rod(g, L(-15.6, 14, -0.2), L(-15.6, 14, -5), 0.8, 0.8, STEEL, M.Metal)
	rod(g, L(-15.6, 13.4, -0.4), L(-15.6, 10.2, -0.4), 0.5, 0.5, STEEL, M.Metal, { Up = cf.LookVector })
	Kit.Cable(g, L(-15.6, 13.6, -4.6), L(-15.6, 10.6, -4.6), 0, 0.2, STEEL_DARK, M.Metal, 3)
	P(g, C(-15.6, 8.2, -4.6) * ANG(0, 0, rad(90)), V3(4.8, 2.6, 2.6), RGB(120, 24, 30), M.Leather, { Shape = Enum.PartType.Cylinder })

	-- the prompt: walk up to the doors
	local promptPart = P(g, C(0, 4, -2.5), V3(10, 8, 1), BLACK, M.SmoothPlastic, { NoCollide = true, Transparency = 1, Shadow = false, Name = "PromptPart" })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterGym"
	prompt.ActionText = "Enter the Gym"
	prompt.ObjectText = "Nightmare Gym · AFK Training"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart

	-- control panel with a green "OPEN" light
	P(g, C(9.5, 4.5, -0.6), V3(2.2, 3.2, 0.8), STEEL_DARK, M.Metal)
	P(g, C(9.5, 5.3, -1.05), V3(1.4, 0.8, 0.1), RGB(80, 255, 140), M.Neon, glow)
	P(g, C(9.5, 4.1, -1.05), V3(0.6, 0.6, 0.1), RED, M.Neon, glow)

	-- the hub's neon glows, it doesn't glare: dim like the rest of the Forge
	require(script.Parent:WaitForChild("Hub")).Dim(g)
end

------------------------------------------------------------------------------------------
-- The hall
------------------------------------------------------------------------------------------
local function buildShell(h, L, C)
	local W, H, Z = HALF.X, HALF.Y, HALF.Z
	P(h, C(0, -1, 0), V3(W * 2 + 4, 2, Z * 2 + 4), RGB(80, 76, 86), M.Concrete, { Name = "Floor" })
	-- reinforced aisle down the middle
	P(h, C(0, 0.06, 0), V3(26, 0.12, Z * 2), RGB(92, 94, 104), M.DiamondPlate)
	for _, x in { -13.4, 13.4 } do
		P(h, C(x, 0.14, 0), V3(0.5, 0.06, Z * 2), RED_DIM, M.Neon, glow)
	end

	-- walls (the south wall has the 16 x 16 lift opening at x = 0)
	local WALL = RGB(62, 58, 68)
	P(h, C(-W - 1, H / 2, 0), V3(2, H, Z * 2 + 4), WALL, M.Concrete)
	P(h, C(W + 1, H / 2, 0), V3(2, H, Z * 2 + 4), WALL, M.Concrete)
	P(h, C(0, H / 2, -Z - 1), V3(W * 2 + 4, H, 2), WALL, M.Concrete)
	P(h, C(-(W + 10) / 2, H / 2, Z + 1), V3(W - 6, H, 2), WALL, M.Concrete)
	P(h, C((W + 10) / 2, H / 2, Z + 1), V3(W - 6, H, 2), WALL, M.Concrete)
	P(h, C(0, 16 + (H - 16) / 2, Z + 1), V3(16, H - 16, 2), WALL, M.Concrete)
	P(h, C(0, H + 1, 0), V3(W * 2 + 4, 2, Z * 2 + 4), STEEL_DARK, M.Metal, { Name = "Ceiling" })

	-- armoured lower band and a neon line along every wall
	for _, spec in {
		{ C(-W + 0.2, 3, 0), V3(0.4, 6, Z * 2) },
		{ C(W - 0.2, 3, 0), V3(0.4, 6, Z * 2) },
		{ C(0, 3, -Z + 0.2), V3(W * 2, 6, 0.4) },
	} do
		P(h, spec[1], spec[2], RGB(46, 46, 54), M.DiamondPlate)
	end
	P(h, C(-W + 0.3, 6.2, 0), V3(0.2, 0.3, Z * 2), RED, M.Neon, glow)
	P(h, C(W - 0.3, 6.2, 0), V3(0.2, 0.3, Z * 2), RED, M.Neon, glow)
	-- the strips wash the walls and floor with red light, and warm wall lamps light the bays
	for z = -Z + 8, Z - 8, 16 do
		for _, x in { -W + 1.2, W - 1.2 } do
			local wash = P(h, C(x, 6.4, z), V3(0.2, 0.2, 0.2), RED, M.Neon, { NoCollide = true, Shadow = false, Transparency = 1, Name = "Wash" })
			Kit.Light(wash, RGB(255, 70, 100), 0.7, 14)
			local lamp = P(h, C(x, 13, z + 8), V3(0.6, 1.2, 2.4), WARM, M.Neon, glow)
			Kit.Light(lamp, WARM, 1.4, 26)
		end
	end
	P(h, C(0, 6.2, -Z + 0.3), V3(W * 2, 0.3, 0.2), RED, M.Neon, glow)
	P(h, C(-W + 0.3, H - 1.5, 0), V3(0.2, 0.3, Z * 2), RGB(150, 90, 255), M.Neon, glow)
	P(h, C(W - 0.3, H - 1.5, 0), V3(0.2, 0.3, Z * 2), RGB(150, 90, 255), M.Neon, glow)

	-- steel columns along the side walls and trusses across the ceiling
	for z = -Z + 8, Z - 8, 16 do
		for _, x in { -W + 0.8, W - 0.8 } do
			P(h, C(x, H / 2, z), V3(1.6, H, 1.2), STEEL, M.Metal)
			P(h, C(x, H / 2, z), V3(0.6, H, 2.2), STEEL, M.Metal)
		end
		local top, bottom = H - 0.8, H - 4.4
		rod(h, L(-W, top, z), L(W, top, z), 0.8, 0.8, STEEL, M.Metal, deco)
		rod(h, L(-W, bottom, z), L(W, bottom, z), 0.8, 0.8, STEEL, M.Metal, deco)
		local x = -W
		local up = true
		while x < W do
			local nx = math.min(x + 8, W)
			rod(h, L(x, up and bottom or top, z), L(nx, up and top or bottom, z), 0.5, 0.5, STEEL, M.Metal, deco)
			x, up = nx, not up
		end
	end

	-- two big ventilation ducts down the hall
	for _, x in { -22, 22 } do
		cyl(h, L(x, H - 6, -Z), L(x, H - 6, Z), 4.2, RGB(120, 122, 132), M.Metal, deco)
		for z = -Z + 6, Z - 6, 12 do
			disc(h, C(x, H - 6, z, 90, 0, 0), 4.8, 0.5, RGB(90, 92, 100), M.Metal, deco)
		end
		-- drops into the hall with a vent each
		for _, z in { -36, 0, 36 } do
			cyl(h, L(x, H - 6, z), L(x, H - 11, z), 2.4, RGB(120, 122, 132), M.Metal, deco)
			disc(h, C(x, H - 11.2, z), 3, 0.5, STEEL_DARK, M.Metal, deco)
			steam(h, C(x, H - 11.6, z) * ANG(rad(180), 0, 0), 2)
		end
	end
	-- wall fans high on the north wall
	for _, x in { -36, 36 } do
		wallFan(h, C(x, H - 9, -Z + 0.6, 0, 180, 0), 8) -- turned to face into the hall
	end
	-- floor grates venting steam along the side walls
	for _, x in { -W + 3, W - 3 } do
		for _, z in { -48, -18, 12, 42 } do
			P(h, C(x, 0.08, z), V3(3, 0.16, 3), RGB(26, 26, 30), M.DiamondPlate)
			steam(h, C(x, 0.3, z), 3)
		end
	end
	-- aisle lamps
	for z = -Z + 16, Z - 16, 24 do
		hangingLamp(h, L(0, H, z), 8, 52)
	end
	-- drifting dust in the lamp light
	Kit.Emitter(h, C(0, 14, 0), V3(W * 2, 20, Z * 2), Kit.TEX.Spark, Kit.MotesFX(RGB(255, 210, 190), 14, 0.2, 0.12))
end

local function buildArrival(h, L, C)
	local Z = HALF.Z
	-- the lift shaft behind the south opening (dark: you arrive out of it)
	P(h, C(0, 0.05, Z + 8), V3(16, 0.1, 14), RGB(20, 20, 24), M.DiamondPlate)
	P(h, C(-8.5, 9, Z + 8), V3(1, 18, 14), STEEL_DARK, M.Metal)
	P(h, C(8.5, 9, Z + 8), V3(1, 18, 14), STEEL_DARK, M.Metal)
	P(h, C(0, 9, Z + 15.5), V3(18, 18, 1), STEEL_DARK, M.Metal)
	P(h, C(0, 17, Z + 8), V3(18, 1, 16), STEEL_DARK, M.Metal)
	-- the doors stand open inside the gym
	freightDoor(h, "ArrivalDoor", C(0, 0, Z + 1), 16, 16, true)
	hazard(h, L(-8.6, 0.2, Z - 0.2), L(-8.6, 16.4, Z - 0.2), 1.2, 1.2, 9)
	hazard(h, L(8.6, 0.2, Z - 0.2), L(8.6, 16.4, Z - 0.2), 1.2, 1.2, 9)
	hazard(h, L(-9.2, 16.9, Z - 0.2), L(9.2, 16.9, Z - 0.2), 1.2, 1.2, 10)
	Kit.Sign(h, CF(L(0, 19.5, Z - 0.1), L(0, 19.5, Z - 30)), V3(8, 2.4, 0.4), "B2", RED, { Color = RGB(14, 10, 16) })
	for _, x in { -11, 11 } do
		local beacon = ball(h, L(x, 18, Z - 0.6), 1.2, RGB(255, 60, 40), M.Neon, glow)
		Kit.Tag(Kit.Light(beacon, RGB(255, 70, 40), 1.6, 20), "WFlicker", { Min = 0.4, Max = 2.4, Speed = 5 })
	end

	-- lockers along the south wall either side of the lift
	local rng = Random.new(77)
	for _, side in { -1, 1 } do
		for k = 0, 13 do
			local x = side * (12 + k * 2.9)
			local tint = rng:NextNumber(-8, 8)
			local body = RGB(70 + tint, 84 + tint, 104 + tint)
			P(h, C(x, 4.2, Z - 1.2), V3(2.75, 8.4, 2.2), body, M.Metal)
			P(h, C(x + side * 0.9, 4.4, Z - 2.35), V3(0.18, 0.9, 0.12), RGB(200, 200, 210), M.Metal, deco)
			for y = 6.6, 7.4, 0.4 do
				P(h, C(x, y, Z - 2.33), V3(1.8, 0.12, 0.06), STEEL_DARK, M.Metal, deco)
			end
		end
		-- a bench in front of the lockers
		P(h, C(side * 30, 1.5, Z - 6), V3(18, 0.5, 2), RGB(96, 70, 48), M.WoodPlanks)
		for _, dx in { -7, 7 } do
			P(h, C(side * 30 + dx, 0.7, Z - 6), V3(0.5, 1.4, 1.6), STEEL_DARK, M.Metal)
		end
	end
end

local function buildDisplays(h, L, C)
	local Z = HALF.Z
	-- the live statistics wall (GymService writes into its labels)
	local screen = P(h, C(0, 19, -Z + 0.4), V3(34, 13, 0.6), RGB(8, 8, 12), M.SmoothPlastic, { Name = "StatsScreen" })
	local frame = { { 0, 6.9, 35.6, 0.8 }, { 0, -6.9, 35.6, 0.8 }, { -17.4, 0, 0.8, 14.6 }, { 17.4, 0, 0.8, 14.6 } }
	for _, f in frame do
		P(h, C(f[1], 19 + f[2], -Z + 0.5), V3(f[3], f[4], 0.9), STEEL, M.Metal)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Stats"
	gui.Face = Enum.NormalId.Back -- the face looking into the hall (+Z of the wall frame)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = screen
	local function label(name: string, y: number, height: number, color: Color3, text: string, font)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.05, y)
		t.Size = UDim2.fromScale(0.9, height)
		t.Font = font or Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = text
		t.Parent = gui
		return t
	end
	label("Title", 0.06, 0.2, RED, "TRAINING STATISTICS", Enum.Font.GothamBlack)
	label("Training", 0.34, 0.14, RGB(230, 225, 240), "NIGHTMARES IN TRAINING: 0")
	label("Rewards", 0.52, 0.14, RGB(230, 225, 240), "REWARDS EARNED HERE: 0")
	label("LastDrop", 0.72, 0.14, RGB(255, 200, 90), "LAST BIG DROP: —")

	-- banners down the side walls
	-- banners high on the side walls, between the bays, facing into the hall
	local slogans = { "TRAIN HARD", "NO MERCY", "FORGE THE BEAST", "BREAK LIMITS", "FEAR NOTHING", "NIGHTMARE GYM" }
	for i, z in { -48, -16, 16, -48, -16, 16 } do -- between the wall columns
		local side = i <= 3 and -1 or 1
		local pos = L(side * (HALF.X - 0.5), 25, z)
		local inward = GymDefinitions.Origin:VectorToWorldSpace(V3(-side, 0, 0))
		local banner = Kit.Sign(h, CF(pos, pos + inward), V3(7, 12, 0.2), slogans[i], RGB(240, 230, 235), { Color = RGB(110, 18, 34), Material = M.Fabric })
		banner.CanCollide = false
		local barCF = CF(pos + V3(0, 6.3, 0) + inward * 0.2)
		rod(h, (barCF * CF(0, 0, -4.2)).Position, (barCF * CF(0, 0, 4.2)).Position, 0.4, 0.4, STEEL, M.Metal, deco)
	end

	-- trophy cabinets under the statistics wall (an open frame with a glass front)
	for _, side in { -1, 1 } do
		local x = side * 25
		local WOOD = RGB(60, 40, 30)
		P(h, C(x, 5, -Z + 0.5), V3(12, 10, 0.4), WOOD, M.Wood)
		P(h, C(x, 0.25, -Z + 1.6), V3(12, 0.5, 2.6), WOOD, M.Wood)
		P(h, C(x, 9.75, -Z + 1.6), V3(12, 0.5, 2.6), WOOD, M.Wood)
		P(h, C(x - 5.8, 5, -Z + 1.6), V3(0.4, 10, 2.6), WOOD, M.Wood)
		P(h, C(x + 5.8, 5, -Z + 1.6), V3(0.4, 10, 2.6), WOOD, M.Wood)
		P(h, C(x, 5, -Z + 2.95), V3(11.2, 9, 0.12), RGB(180, 200, 220), M.Glass, { Transparency = 0.7, Reflect = 0.2 })
		for k = 0, 2 do
			local y = 1.6 + k * 3
			P(h, C(x, y, -Z + 1.6), V3(11, 0.25, 2.2), RGB(80, 56, 40), M.Wood)
			for t = -1, 1 do
				local base = L(x + t * 3.4, y + 0.15, -Z + 1.7)
				local gold = RGB(230, 180, 70)
				cyl(h, base, base + V3(0, 0.6, 0), 1, STEEL_DARK, M.Marble, deco)
				cyl(h, base + V3(0, 0.6, 0), base + V3(0, 1.6, 0), 0.3, gold, M.Metal, deco)
				ball(h, base + V3(0, 2, 0), 0.9 + (k == 2 and 0.3 or 0), gold, M.Metal, deco)
			end
		end
		local lamp = P(h, C(x, 10.2, -Z + 2.2), V3(10, 0.2, 0.4), WARM, M.Neon, glow)
		Kit.Light(lamp, WARM, 1.2, 10)
	end

	-- display cases with a glowing prize for each top tier and its REAL odds
	local odds = GymDefinitions.Odds(1)
	for i, tierId in { "Rare", "Epic", "Legendary", "Mythic" } do
		local tier = GymDefinitions.Tiers[tierId]
		local x = -21 + (i - 1) * 14
		local base = L(x, 0, -Z + 12)
		disc(h, CF(base + V3(0, 0.6, 0)), 5, 1.2, RGB(40, 36, 48), M.Marble)
		disc(h, CF(base + V3(0, 1.3, 0)), 3.6, 0.2, tier.Color, M.Neon, glow)
		cyl(h, base + V3(0, 1.4, 0), base + V3(0, 6.4, 0), 3.4, RGB(200, 220, 240), M.Glass, { NoCollide = true, Transparency = 0.75, Reflect = 0.2 })
		disc(h, CF(base + V3(0, 6.5, 0)), 3.8, 0.3, STEEL, M.Metal, deco)
		local prize = P(h, CF(base + V3(0, 3.6, 0)) * ANG(rad(45), 0, rad(45)), V3(1.4, 1.4, 1.4), tier.Color, M.Neon, glow)
		Kit.Tag(prize, "WBob", { Amp = 0.3, Speed = 1.5 + i * 0.2 })
		Kit.Light(prize, tier.Color, 1.4, 10)
		local pct = odds[tierId] * 100
		Kit.Sign(h, CF(base + V3(0, 0.6, 2.6), base + V3(0, 0.6, 30)), V3(4.6, 0.9, 0.2), ("%s · %s%%"):format(tierId:upper(), pct >= 1 and ("%.1f"):format(pct) or ("%.2f"):format(pct)), tier.Color)
	end

	Kit.Sign(h, CF(L(0, 29, -Z + 0.5), L(0, 29, 0)), V3(30, 4, 0.4), "THE NIGHTMARE GYM", RED, { Color = RGB(14, 10, 16) })
end

local function buildEquipment(h, L, C)
	local IRON, GRIP = RGB(36, 36, 40), RGB(160, 160, 170)
	-- a Nightmare-sized bench press
	local z = 44
	P(h, C(0, 2.2, z), V3(3.2, 0.8, 9), RGB(120, 20, 30), M.Fabric)
	for _, dz in { -3.6, 3.6 } do
		P(h, C(0, 1, z + dz), V3(2.6, 2, 0.6), STEEL_DARK, M.Metal)
	end
	for _, x in { -3, 3 } do
		P(h, C(x, 4, z - 3.2), V3(0.6, 8, 0.6), STEEL, M.Metal)
		P(h, C(x, 7, z - 2.9), V3(0.8, 0.4, 1.2), STEEL, M.Metal)
	end
	cyl(h, L(-9, 7.6, z - 3), L(9, 7.6, z - 3), 0.5, GRIP, M.Metal, deco)
	for _, x in { -7.4, -6.2, 6.2, 7.4 } do
		disc(h, C(x, 7.6, z - 3, 0, 0, 90), x * x > 50 and 4.8 or 5.8, 1, IRON, M.Metal, deco)
	end

	-- dumbbell rack (west of the aisle) and one GIANT dumbbell on the floor
	z = 18
	P(h, C(-9, 2.4, z), V3(2.4, 0.4, 14), STEEL, M.Metal)
	P(h, C(-9, 1.2, z), V3(2.4, 0.4, 14), STEEL, M.Metal)
	for _, dz in { -6.6, 0, 6.6 } do
		P(h, C(-9, 1.4, z + dz), V3(2.4, 2.8, 0.5), STEEL_DARK, M.Metal)
	end
	for k = 0, 4 do
		local size = 1 + k * 0.3
		local pz = z - 5.6 + k * 2.8
		cyl(h, L(-9, 2.6 + size / 2, pz - 0.9), L(-9, 2.6 + size / 2, pz + 0.9), 0.3, GRIP, M.Metal, deco)
		for _, s in { -1, 1 } do
			disc(h, C(-9, 2.6 + size / 2, pz + s * 0.9 * 1, 90, 0, 0), size, 0.5, IRON, M.Metal, deco)
		end
	end
	cyl(h, L(8, 3.2, z - 5), L(8, 3.2, z + 5), 1.4, GRIP, M.Metal)
	for _, s in { -1, 1 } do
		disc(h, C(8, 3.2, z + s * 4.2, 90, 0, 0), 6.4, 1.6, IRON, M.Metal)
		disc(h, C(8, 3.2, z + s * 5.2, 90, 0, 0), 5.6, 0.6, RED_DIM, M.Metal)
	end
	Kit.Sign(h, CF(L(8, 7.6, z), L(30, 7.6, z)), V3(6, 1, 0.2), "500 KG · NIGHTMARES ONLY", RGB(255, 200, 90))

	-- cable machine tower
	z = -6
	for _, x in { -4, 4 } do
		P(h, C(x, 8, z), V3(1, 16, 1), STEEL, M.Metal)
	end
	P(h, C(0, 16.4, z), V3(9, 0.8, 1.4), STEEL, M.Metal)
	for k = 0, 9 do
		P(h, C(0, 1 + k * 0.85, z), V3(4.6, 0.75, 2), k % 2 == 0 and IRON or RGB(50, 50, 56), M.Metal)
	end
	rod(h, L(-0.9, 9.6, z), L(-0.9, 16, z), 0.2, 0.2, GRIP, M.Metal, deco)
	rod(h, L(0.9, 9.6, z), L(0.9, 16, z), 0.2, 0.2, GRIP, M.Metal, deco)
	for _, x in { -3, 3 } do
		disc(h, C(x, 16.9, z, 90, 0, 0), 1.8, 0.5, GRIP, M.Metal, deco)
	end
	Kit.Cable(h, L(-3, 16.9, z), L(-6, 5, z + 2), 0, 0.15, RGB(20, 20, 22), M.Metal, 4)
	P(h, C(-6, 4.6, z + 2), V3(2.4, 0.4, 0.4), GRIP, M.Metal, deco)

	-- reinforced training dummies
	z = -30
	for _, x in { -6, 6 } do
		disc(h, C(x, 0.5, z), 4, 1, STEEL_DARK, M.Metal)
		cyl(h, L(x, 1, z), L(x, 6, z), 1, STEEL, M.Metal)
		P(h, C(x, 7.6, z), V3(3.4, 3.6, 2.2), RGB(90, 60, 40), M.Leather)
		for _, dy in { -1, 1 } do
			P(h, C(x, 7.6 + dy * 1.2, z), V3(3.6, 0.35, 2.4), STEEL_DARK, M.Metal, deco)
		end
		ball(h, L(x, 10.4, z), 2.2, RGB(90, 60, 40), M.Leather)
		disc(h, C(x, 7.6, z + 1.12, 90, 0, 0), 1.8, 0.1, RED, M.Neon, glow)
	end

	-- a giant kettlebell on a plinth
	z = -46
	P(h, C(0, 0.6, z), V3(8, 1.2, 8), RGB(46, 46, 54), M.DiamondPlate)
	ball(h, L(0, 4.4, z), 6, IRON, M.Metal)
	disc(h, C(0, 1.6, z), 4.6, 0.6, IRON, M.Metal)
	Kit.Ring(h, C(0, 8.2, z, 90, 0, 0), 1.7, 0.9, 0.9, 16, IRON, M.Metal, nil, 180, 360)
	Kit.Sign(h, CF(L(0, 1.6, z + 4.1), L(0, 1.6, z + 30)), V3(5, 0.8, 0.2), "TITAN BELL", RGB(255, 200, 90))
end

local function buildBay(h, i: number)
	local cf = GymDefinitions.BayCF(i)
	local L, C = Kit.Frame(cf)
	local bay = Kit.Model("Bay" .. i, h)
	local bagAt = GymDefinitions.BagOffset

	-- mat with a neon border
	P(bay, C(0, 0.1, -4), V3(24, 0.2, 22), RGB(34, 32, 38), M.Fabric)
	for _, spec in { { 0, -15, 24, 0.3 }, { 0, 7, 24, 0.3 }, { -12, -4, 0.3, 22 }, { 12, -4, 0.3, 22 } } do
		P(bay, C(spec[1], 0.22, spec[2]), V3(spec[3], 0.06, spec[4]), RED_DIM, M.Neon, glow)
	end

	-- the gantry the bag hangs from
	local beamY = GymDefinitions.BeamHeight
	for _, x in { -7, 7 } do
		P(bay, C(x, beamY / 2, bagAt.Z), V3(1.2, beamY, 1.2), STEEL, M.Metal)
		P(bay, C(x, beamY / 2, bagAt.Z), V3(0.5, beamY, 2), STEEL, M.Metal)
		P(bay, C(x, 0.4, bagAt.Z), V3(3, 0.8, 3), STEEL_DARK, M.DiamondPlate)
	end
	P(bay, C(0, beamY + 0.6, bagAt.Z), V3(16, 1.2, 1.4), STEEL, M.Metal)
	P(bay, C(0, beamY - 0.1, bagAt.Z), V3(1.4, 0.4, 1.4), STEEL_DARK, M.Metal)
	hazard(bay, L(-7.6, beamY + 1.3, bagAt.Z), L(7.6, beamY + 1.3, bagAt.Z), 0.4, 0.2, 8)

	-- the mirror on the side wall behind the bag (bays sit 32 studs out from the middle)
	local toWall = -(HALF.X - 32) + 0.6
	-- (dark gloss: Roblox reflections show the sky, which glared white in here)
	P(bay, C(0, 10.5, toWall), V3(16, 12, 0.3), RGB(36, 40, 50), M.SmoothPlastic, { Reflect = 0.18 })
	for _, spec in { { 0, 16.6, 16.6, 0.6 }, { 0, 4.4, 16.6, 0.6 }, { -8.3, 10.5, 0.6, 12.6 }, { 8.3, 10.5, 0.6, 12.6 } } do
		P(bay, C(spec[1], spec[2], toWall + 0.2), V3(spec[3], spec[4], 0.5), STEEL_DARK, M.Metal)
	end
	Kit.Sign(bay, CF(L(0, 19.2, toWall + 0.3), L(0, 19.2, 30)), V3(6, 1.6, 0.2), "BAY " .. i, RED, { Color = RGB(14, 10, 16) })

	-- a lamp over the bag
	hangingLamp(bay, L(0, HALF.Y, bagAt.Z + 4), HALF.Y - 26, 40)

	-- the Handler's bench on the aisle side
	P(bay, C(7.5, 1.3, 10), V3(6, 0.5, 2), RGB(96, 70, 48), M.WoodPlanks)
	for _, dx in { -2.4, 2.4 } do
		P(bay, C(7.5 + dx, 0.55, 10), V3(0.5, 1.1, 1.6), STEEL_DARK, M.Metal)
	end
	-- a water bottle and a towel
	cyl(bay, L(5.6, 1.55, 10), L(5.6, 2.5, 10), 0.4, RGB(80, 160, 255), M.Glass, deco)
	P(bay, C(9, 1.6, 10), V3(1.6, 0.12, 1.2), RGB(220, 220, 230), M.Fabric, deco)

	-- the bay's reward screen on a stand (GymController writes into it for its owner)
	local sc = cf * GymDefinitions.ScreenOffset
	local _, SC = Kit.Frame(sc)
	P(bay, SC(0, 2, 0), V3(0.6, 4, 0.6), STEEL, M.Metal)
	P(bay, SC(0, 0.2, 0), V3(2.4, 0.4, 2.4), STEEL_DARK, M.Metal)
	local screen = P(bay, CF(SC(0, 5.3, 0).Position, SC(0, 5.3, 6).Position + cf.RightVector * 3), V3(4.6, 2.8, 0.3), RGB(8, 8, 12), M.SmoothPlastic, { Name = "BayScreen" })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = screen
	for _, spec in {
		{ "Title", 0.04, 0.24, RED, "BAY " .. i, Enum.Font.GothamBlack },
		{ "Next", 0.34, 0.24, RGB(230, 225, 240), "FREE", Enum.Font.GothamBold },
		{ "Last", 0.66, 0.26, RGB(255, 200, 90), "", Enum.Font.GothamBold },
	} do
		local t = Instance.new("TextLabel")
		t.Name = spec[1]
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.05, spec[2])
		t.Size = UDim2.fromScale(0.9, spec[3])
		t.TextScaled = true
		t.Font = spec[6]
		t.TextColor3 = spec[4]
		t.Text = spec[5]
		t.Parent = gui
	end

	-- the reward crate (glows open on a good roll, client side)
	local cc = cf * GymDefinitions.CrateOffset
	local crate = Kit.Model("Crate", bay)
	local body = P(crate, cc * CF(0, 1.1, 0), V3(3, 2.2, 2.2), RGB(60, 52, 46), M.WoodPlanks, { Name = "Body" })
	crate.PrimaryPart = body
	for _, dy in { -0.8, 0.8 } do
		P(crate, cc * CF(0, 1.1 + dy, 0), V3(3.1, 0.25, 2.3), STEEL_DARK, M.Metal)
	end
	P(crate, cc * CF(0, 2.35, 0), V3(3.1, 0.3, 2.3), STEEL, M.Metal, { Name = "Lid" })
	local glowPart = P(crate, cc * CF(0, 2.6, 0), V3(2.6, 0.2, 1.8), RGB(255, 255, 255), M.Neon, { NoCollide = true, Shadow = false, Transparency = 1, Name = "Glow" })
	local light = Kit.Light(glowPart, RGB(255, 255, 255), 0, 14)
	light.Name = "GlowLight"

	-- a hook to hang the bag from (the bag itself is BuildBag's, sized per Nightmare)
	bay:SetAttribute("Bay", i)
end

------------------------------------------------------------------------------------------
-- The heavy bag (per bay, re-hung per Nightmare)
------------------------------------------------------------------------------------------
function Gym.BuildBag(i: number, centerY: number?): Model?
	if not hall then
		return nil
	end
	local bags = hall:FindFirstChild("Bags")
	local old = bags:FindFirstChild("Bag" .. i)
	if old then
		old:Destroy()
	end
	local cf = GymDefinitions.BayCF(i)
	local beamY = GymDefinitions.BeamHeight
	local pivot = (cf * CF(GymDefinitions.BagOffset.X, beamY - 0.3, GymDefinitions.BagOffset.Z)).Position
	local floorY = cf.Position.Y
	local cy = math.clamp(centerY or (floorY + 6.5), floorY + BAG.Height / 2 + 0.6, pivot.Y - BAG.Height / 2 - 2)
	local center = V3(pivot.X, cy, pivot.Z)
	local top = center + V3(0, BAG.Height / 2, 0)

	local bag = Instance.new("Model")
	bag.Name = "Bag" .. i
	bag.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams to clients whole
	bag:SetAttribute("Bay", i)
	bag:SetAttribute("Pivot", pivot)
	bag:SetAttribute("Length", pivot.Y - cy)

	local leather = RGB(120, 24, 30)
	local body = P(bag, CF(center) * ANG(0, 0, rad(90)), V3(BAG.Height, BAG.Radius * 2, BAG.Radius * 2), leather, M.Leather, { Shape = Enum.PartType.Cylinder, NoCollide = true, Name = "Bag" })
	bag.PrimaryPart = body
	-- caps, bands and a white stripe
	disc(bag, CF(top), BAG.Radius * 2 + 0.1, 0.35, RGB(40, 36, 40), M.Leather, { NoCollide = true, Name = "Cap" })
	disc(bag, CF(center - V3(0, BAG.Height / 2, 0)), BAG.Radius * 2 + 0.1, 0.3, RGB(40, 36, 40), M.Leather, { NoCollide = true })
	for _, dy in { -BAG.Height * 0.28, BAG.Height * 0.28 } do
		disc(bag, CF(center + V3(0, dy, 0)), BAG.Radius * 2 + 0.08, 0.25, RGB(26, 22, 26), M.Leather, { NoCollide = true })
	end
	disc(bag, CF(center + V3(0, BAG.Height * 0.08, 0)), BAG.Radius * 2 + 0.06, 0.5, RGB(230, 226, 220), M.Leather, { NoCollide = true })
	-- the swivel: four short chains from the cap to a ring, then the long chain
	local ring = top + V3(0, 1.4, 0)
	disc(bag, CF(ring), 0.6, 0.15, STEEL, M.Metal, { NoCollide = true })
	for k = 0, 3 do
		local a = rad(45 + k * 90)
		cyl(bag, top + V3(math.cos(a) * BAG.Radius * 0.8, 0.15, math.sin(a) * BAG.Radius * 0.8), ring, 0.1, STEEL, M.Metal, { NoCollide = true })
	end
	local length = pivot.Y - ring.Y
	local links = math.max(2, math.floor(length / 0.75))
	for k = 0, links - 1 do
		local y = ring.Y + (k + 0.5) * length / links
		P(bag, CF(V3(pivot.X, y, pivot.Z)) * ANG(0, k % 2 == 0 and 0 or rad(90), 0), V3(0.16, length / links + 0.12, 0.42), RGB(150, 150, 160), M.Metal, { NoCollide = true, Name = "Link" })
	end
	-- dust that puffs out of the leather on a hit (GymController calls :Emit)
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Texture = Kit.TEX.Smoke
	dust.Enabled = false
	dust.Color = ColorSequence.new(RGB(210, 196, 180))
	dust.Transparency = NumberSequence.new(0.55, 1)
	dust.Size = NumberSequence.new(0.6, 2.2)
	dust.Lifetime = NumberRange.new(0.4, 0.8)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Drag = 4
	dust.Parent = body
	bag.Parent = bags -- parented last, so clients receive it complete
	return bag
end

function Gym.Hall(): Model?
	return hall
end

function Gym.Build(root)
	buildLift(root)

	local origin = GymDefinitions.Origin
	local L, C = Kit.Frame(origin)
	local h = Kit.Model("NightmareGym", root)
	buildShell(h, L, C)
	buildArrival(h, L, C)
	buildDisplays(h, L, C)
	buildEquipment(h, L, C)
	for i = 1, GymDefinitions.BayCount do
		buildBay(h, i)
	end
	Kit.Folder("Bags", h)
	hall = h
	for i = 1, GymDefinitions.BayCount do
		Gym.BuildBag(i)
	end
end

return Gym
