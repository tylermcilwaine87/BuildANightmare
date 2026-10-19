--[[
	ScrapRoute  (ModuleScript)
	Location: ServerScriptService/Server/Services/World/ScrapRoute

	THE RUSTED EXPANSE (west): the walk from the Forge to the Scrap Titan's Foundry.

	  Hub gate → broken checkpoint (booth: Foreman's Badge)
	           → conveyor causeway past the Crusher (climb its stairs: Crusher Log)
	           → crane yard with half-built war machines
	             (side trip south: the smelting pit, Titan's Bolt)
	           → giant footprints and crushed wrecks → the Foundry gate
	Background: junk mountains, smokestacks, a fallen colossus.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local ScrapRoute = {}

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local M = Enum.Material
local P, ball, cyl, rod, disc = Kit.P, Kit.Ball, Kit.Cyl, Kit.Rod, Kit.Disc
local glow = { NoCollide = true, Shadow = false }

local RUST, RUST2, STEEL, DARK = RGB(122, 64, 36), RGB(86, 50, 34), RGB(88, 90, 94), RGB(40, 38, 37)
local CHROME, YELLOW, OIL = RGB(176, 176, 182), RGB(170, 128, 40), RGB(18, 16, 15)
local GLOW = RGB(255, 120, 30)
local SODIUM = RGB(255, 180, 110)
local JUNK_COLORS = { RUST, RUST2, STEEL, DARK, RGB(70, 84, 60), RGB(150, 122, 52), RGB(112, 40, 30), RGB(50, 70, 92) }
local JUNK_MATS = { M.CorrodedMetal, M.CorrodedMetal, M.Metal, M.DiamondPlate }

------------------------------------------------------------------------------------------
-- Props
------------------------------------------------------------------------------------------
local function junkPile(parent, rng, center: Vector3, radius: number, count: number, height: number?)
	local h = height or radius * 0.7
	for _ = 1, count do
		local up = rng:NextNumber()
		local r = radius * (1 - up) * rng:NextNumber()
		local a = rng:NextNumber() * 2 * pi
		local size = V3(rng:NextNumber(1.5, 6), rng:NextNumber(0.8, 3.5), rng:NextNumber(1.5, 6))
		P(parent, CF(center + V3(cos(a) * r, up * h + size.Y * 0.3, sin(a) * r)) * ANG(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.3), rng:NextNumber(-0.6, 0.6)), size, JUNK_COLORS[rng:NextInteger(1, #JUNK_COLORS)], JUNK_MATS[rng:NextInteger(1, #JUNK_MATS)])
	end
end

-- A wrecked car (crushed = flattened).
local function car(parent, cf: CFrame, color: Color3, crushed: boolean?)
	local h = crushed and 0.5 or 1
	local body = cf * CF(0, 1.3 * h, 0)
	P(parent, body, V3(6.4, 2.2 * h, 3.4), color, M.CorrodedMetal)
	P(parent, body * CF(0.4, 1.6 * h, 0), V3(3.6, 1.2 * h, 3.2), color, M.CorrodedMetal)
	P(parent, body * CF(0.4, 1.6 * h, -1.62), V3(3.2, 0.9 * h, 0.1), RGB(28, 32, 36), M.Glass, { Reflect = 0.2 })
	for _, w in { { -2.2, -1.75 }, { 2.2, -1.75 }, { -2.2, 1.75 }, { 2.2, 1.75 } } do
		P(parent, cf * CF(w[1], 0.8, w[2]) * ANG(0, rad(90), 0), V3(0.7, 1.6, 1.6), RGB(20, 20, 22), M.Fabric, { Shape = Enum.PartType.Cylinder })
	end
end

local function barrel(parent, ground: Vector3, color: Color3, burning: boolean?)
	local cf = CF(ground + V3(0, 1.7, 0))
	disc(parent, cf, 2.4, 3.4, color, M.CorrodedMetal)
	disc(parent, cf * CF(0, 0.85, 0), 2.56, 0.18, DARK, M.Metal)
	disc(parent, cf * CF(0, -0.85, 0), 2.56, 0.18, DARK, M.Metal)
	if burning then
		local flame = ball(parent, ground + V3(0, 3.5, 0), 1.1, GLOW, M.Neon, { NoCollide = true, Shadow = false, Transparency = 0.3 })
		Kit.Tag(Kit.Light(flame, RGB(255, 140, 60), 2.5, 20, { Shadows = true }), "WFlicker", { Min = 1.6, Max = 3.2, Speed = 9 })
		Kit.Emitter(parent, CF(ground + V3(0, 3.5, 0)), V3(1.6, 0.2, 1.6), Kit.TEX.Fire, Kit.FireFX(30))
		Kit.Emitter(parent, CF(ground + V3(0, 5.5, 0)), V3(1, 0.2, 1), Kit.TEX.Smoke, Kit.SmokeFX(RGB(40, 36, 34), 3, 1.5))
	end
end

-- Lattice light tower with a sodium floodlight aimed at `target`.
local function floodTower(parent, ground: Vector3, target: Vector3, height: number?)
	local h = height or 22
	for _, o in { V3(-1, 0, -1), V3(1, 0, -1), V3(-1, 0, 1), V3(1, 0, 1) } do
		rod(parent, ground + o * 1.6, ground + o * 0.6 + V3(0, h, 0), 0.4, 0.4, YELLOW, M.CorrodedMetal)
	end
	for y = 4, h - 2, 4 do
		P(parent, CF(ground + V3(0, y, 0)), V3(2.8 - y / h, 0.3, 2.8 - y / h), YELLOW, M.CorrodedMetal, glow)
	end
	local head = P(parent, CFrame.lookAt(ground + V3(0, h + 1, 0), target), V3(3, 2, 1.2), DARK, M.Metal)
	P(parent, head.CFrame * CF(0, 0, -0.65), V3(2.6, 1.6, 0.1), RGB(255, 220, 170), M.Neon, glow)
	Kit.Light(head, SODIUM, 4, 60, { Kind = "SpotLight", Face = Enum.NormalId.Front, Angle = 60, Shadows = true })
end

local function smokestack(parent, ground: Vector3, height: number, diameter: number)
	cyl(parent, ground - V3(0, 10, 0), ground + V3(0, height, 0), diameter, RGB(70, 52, 44), M.Brick)
	for k = 1, 3 do
		local y = height * (0.55 + k * 0.12)
		disc(parent, CF(ground + V3(0, y, 0)), diameter + 0.8, 3, k % 2 == 0 and RGB(170, 40, 30) or RGB(220, 210, 200), M.SmoothPlastic)
	end
	local top = ground + V3(0, height, 0)
	local beacon = ball(parent, top + V3(0, 1.5, 0), 2.5, RGB(255, 60, 40), M.Neon, glow)
	Kit.Tag(beacon, "WPulse", { Min = 0, Max = 0.8, Speed = 2 })
	Kit.Emitter(parent, CF(top + V3(0, 2, 0)), V3(diameter * 0.7, 1, diameter * 0.7), Kit.TEX.Smoke, {
		Color = ColorSequence.new(RGB(60, 52, 48), RGB(110, 96, 88)),
		Size = NumberSequence.new(diameter * 0.8, diameter * 3),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(10, 16),
		Rate = 3,
		Speed = NumberRange.new(8, 12),
		SpreadAngle = Vector2.new(8, 8),
		Acceleration = V3(-2, 0.5, 0),
		RotSpeed = NumberRange.new(-10, 10),
	})
end

local function crane(parent, ground: Vector3, height: number, reach: number, yaw: number, swingTag: boolean?)
	local base = CF(ground) * ANG(0, rad(yaw), 0)
	local L, C = Kit.Frame(base)
	P(parent, C(0, 1.5, 0), V3(10, 3, 10), DARK, M.Metal)
	for _, o in { { -1.6, -1.6 }, { 1.6, -1.6 }, { -1.6, 1.6 }, { 1.6, 1.6 } } do
		rod(parent, L(o[1], 3, o[2]), L(o[1] * 0.6, height, o[2] * 0.6), 0.6, 0.6, YELLOW, M.CorrodedMetal)
	end
	for y = 8, height - 2, 7 do
		P(parent, C(0, y, 0), V3(3.4, 0.4, 3.4), YELLOW, M.CorrodedMetal, glow)
	end
	P(parent, C(0, height + 2, 0), V3(5, 4, 5), RGB(60, 56, 54), M.Metal)
	P(parent, C(0, height + 4.5, -reach / 2 + 6), V3(2.4, 2, reach), YELLOW, M.CorrodedMetal)
	P(parent, C(0, height + 4.5, 8), V3(4, 4, 6), DARK, M.Metal) -- counterweight
	local tip = L(0, height + 3.5, -reach + 7)
	local hookModel = Kit.Model("CraneHook", parent)
	local hookPos = tip - V3(0, height * 0.55, 0)
	Kit.Cable(hookModel, tip, hookPos, 0, 0.3, DARK, M.Metal, 4)
	P(hookModel, CF(hookPos - V3(0, 1.2, 0)), V3(2.4, 2.4, 1), DARK, M.Metal)
	P(hookModel, CF(hookPos - V3(0, 4, 0)) * ANG(0.2, 0.6, 0.15), V3(5, 3, 4), RUST2, M.CorrodedMetal)
	if swingTag then
		hookModel.WorldPivot = CF(tip)
		Kit.Tag(hookModel, "WSwing", { Angle = 6, Speed = 0.7, Axis = "X" })
	end
end

-- Shipping container.
local function container(parent, cf: CFrame, color: Color3)
	P(parent, cf, V3(8, 8, 20), color, M.CorrodedMetal)
	for z = -9, 9, 1.5 do
		P(parent, cf * CF(4.05, 0, z), V3(0.2, 7.6, 0.5), color, M.CorrodedMetal, glow)
		P(parent, cf * CF(-4.05, 0, z), V3(0.2, 7.6, 0.5), color, M.CorrodedMetal, glow)
	end
end

-- Half-built war machine on a gantry: the Titan building an army.
local function warMachine(parent, ground: Vector3, yaw: number)
	local L, C = Kit.Frame(CF(ground) * ANG(0, rad(yaw), 0))
	-- gantry
	for _, s in { -1, 1 } do
		P(parent, C(s * 11, 15, 0), V3(1.6, 30, 1.6), YELLOW, M.CorrodedMetal)
	end
	P(parent, C(0, 30.5, 0), V3(24, 1.6, 2), YELLOW, M.CorrodedMetal)
	-- skeleton body hanging from chains
	Kit.Cable(parent, L(-3, 30, 0), L(-2.4, 24, 0), 0, 0.4, DARK, M.Metal, 3)
	Kit.Cable(parent, L(3, 30, 0), L(2.4, 24, 0), 0, 0.4, DARK, M.Metal, 3)
	P(parent, C(0, 21, 0), V3(8, 6, 5), RUST, M.CorrodedMetal)
	P(parent, C(0, 21, -2.6), V3(5, 3, 0.4), OIL, M.Metal)
	local eye = ball(parent, L(0, 25, -1.5), 1.2, RGB(255, 60, 30), M.Neon, glow)
	Kit.Tag(eye, "WPulse", { Min = 0, Max = 0.9, Speed = 0.6 })
	for _, s in { -1, 1 } do
		rod(parent, L(s * 4.6, 23, 0), L(s * 6, 15, -1), 1, 1, STEEL, M.Metal) -- arm frame
		rod(parent, L(s * 2.4, 18, 0), L(s * 2.6, 9, 0.5), 1.2, 1.2, STEEL, M.Metal) -- leg frame
		rod(parent, L(s * 2.6, 9, 0.5), L(s * 2.6, 3, -0.5), 1, 1, STEEL, M.Metal)
	end
	-- sparks from welding
	Kit.Emitter(parent, C(2, 20, -2.8), V3(0.4, 0.4, 0.4), Kit.TEX.Spark, Kit.SparkFX(nil, 30))
	-- parts waiting on the floor
	P(parent, C(7, 1.5, 4), V3(4, 3, 4), RUST2, M.CorrodedMetal)
	ball(parent, L(-7, 2, 4), 4, DARK, M.Metal)
end

local function footprint(parent, ground: Vector3, yaw: number)
	local _, C = Kit.Frame(CF(ground) * ANG(0, rad(yaw), 0))
	Kit.Ellipsoid(parent, C(0, 0.05, 0), V3(7, 0.3, 10), RGB(26, 22, 20), M.SmoothPlastic, glow)
	for k = -1, 1 do
		Kit.Ellipsoid(parent, C(k * 2.6, 0.05, -6.2 + math.abs(k) * 0.8), V3(2, 0.3, 3.4), RGB(26, 22, 20), M.SmoothPlastic, glow)
	end
end

------------------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------------------
function ScrapRoute.Build(root)
	local region = WorldDefinitions.Regions.Scrap
	local folder = Kit.Folder("Route_Scrap", root)
	local rng = Random.new(1201)

	-- Ground: a rust-brown wasteland west of the Forge.
	Kit.TBlock(CF(-520, -15, 20), V3(740, 30, 600), M.Ground)
	for _, h in { { -300, -14, -190, 64 }, { -360, -20, 200, 72 }, { -520, -16, -210, 84 }, { -580, -12, 230, 78 }, { -240, -16, 170, 50 }, { -820, -10, -120, 90 }, { -830, -10, 200, 90 }, { -420, -18, -240, 60 } } do
		Kit.THill(rng, V3(h[1], h[2], h[3]), h[4], M.Ground, 4)
		-- junk crowning each hill
		for _ = 1, 26 do
			local a = rng:NextNumber() * 2 * pi
			local up = rng:NextNumber(0.35, 1)
			local dir = V3(cos(a) * math.sqrt(1 - up * up), up, sin(a) * math.sqrt(1 - up * up))
			local pos = V3(h[1], h[2], h[3]) + dir * h[4] * 0.97
			local size = V3(rng:NextNumber(3, 12), rng:NextNumber(2, 7), rng:NextNumber(3, 12))
			P(folder, CF(pos) * ANG(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0, 6.3), rng:NextNumber(-0.7, 0.7)), size, JUNK_COLORS[rng:NextInteger(1, #JUNK_COLORS)], JUNK_MATS[rng:NextInteger(1, #JUNK_MATS)])
		end
	end

	-- The road.
	local control = {
		V3(-172, 1, 0),
		V3(-215, 1, 0),
		V3(-262, 1, -24),
		V3(-318, 4, -40),
		V3(-386, 4, -32),
		V3(-432, 1, -2),
		V3(-482, 1, 28),
		V3(-540, 1, 44),
		WorldDefinitions.GatePlaza("Scrap").Position,
	}
	local road = Kit.Smooth(control, 3)
	Kit.Path(folder, road, { Width = 18, Thickness = 2, Color = RGB(54, 50, 47), Material = M.Asphalt, Edge = { Color = RGB(150, 112, 36), Material = M.SmoothPlastic } })

	-- Road lights and hazard posts
	for i = 4, #road - 3, 5 do
		local a, b = road[i], road[i + 1]
		local side = (b - a).Unit:Cross(V3(0, 1, 0))
		local s = (i // 5) % 2 == 0 and 1 or -1
		floodTower(folder, a + side * s * 13 - V3(0, 1, 0), a + V3(0, 0, 0), 20)
	end

	-- 1) Broken checkpoint with a guard booth (relic inside)
	do
		local L, C = Kit.Frame(CF(-262, 1, -52))
		P(folder, C(0, 4.5, 0), V3(12, 9, 0.8), RGB(80, 84, 76), M.CorrodedMetal) -- back wall; the door faces the road
		P(folder, C(-6, 4.5, 5), V3(0.8, 9, 10), RGB(80, 84, 76), M.CorrodedMetal)
		P(folder, C(6, 4.5, 5), V3(0.8, 9, 10), RGB(80, 84, 76), M.CorrodedMetal)
		P(folder, C(-3.8, 4.5, 10), V3(4.4, 9, 0.8), RGB(80, 84, 76), M.CorrodedMetal)
		P(folder, C(3.8, 4.5, 10), V3(4.4, 9, 0.8), RGB(80, 84, 76), M.CorrodedMetal)
		P(folder, C(0, 9.4, 5, 0, 0, 4), V3(13.5, 0.8, 11.5), RUST2, M.CorrodedMetal)
		P(folder, C(-6.45, 5.5, 5), V3(0.1, 2.5, 6), RGB(30, 40, 44), M.Glass, { Reflect = 0.3, Transparency = 0.4 })
		P(folder, C(0, 1.9, 2), V3(6, 0.4, 2.4), RGB(80, 60, 42), M.WoodPlanks) -- desk
		P(folder, C(0, 1, 2), V3(5.6, 1.6, 2), RGB(60, 44, 32), M.WoodPlanks)
		local bulb = ball(folder, L(0, 8.4, 5), 0.6, RGB(255, 220, 160), M.Neon, glow)
		Kit.Tag(Kit.Light(bulb, RGB(255, 210, 150), 1.2, 12), "WFlicker", { Min = 0.2, Max = 1.4, Speed = 5 })
		Kit.Relic(folder, "ForemanBadge", L(0, 1.4, 2) + V3(0, 0.8, 0), region.Color)
		-- barrier posts beside the road: one arm raised, the other snapped off and lying
		P(folder, CF(-250, 3, -4), V3(1.6, 4, 1.6), YELLOW, M.CorrodedMetal)
		rod(folder, V3(-250, 5, -4), V3(-250, 14, -10), 0.8, 0.8, RGB(220, 200, 40), M.SmoothPlastic)
		P(folder, CF(-276, 3, -44), V3(1.6, 4, 1.6), YELLOW, M.CorrodedMetal)
		P(folder, CF(-283, 1.4, -42) * ANG(0, 0.5, 0.1), V3(0.8, 0.8, 15), RGB(220, 200, 40), M.SmoothPlastic)
		Kit.Sign(folder, CFrame.lookAt(V3(-240, 7, 18), V3(-200, 7, 18)), V3(14, 3, 0.4), "TRESPASSERS WILL BE RECYCLED", RGB(255, 170, 60), { Color = RGB(60, 40, 30), Material = M.CorrodedMetal })
		P(folder, CF(-240, 3, 18), V3(0.8, 6, 0.8), DARK, M.Metal)
		barrel(folder, V3(-248, 1, 22), RGB(60, 90, 70), true)
		barrel(folder, V3(-246, 1, 26), RUST, false)
	end

	-- 2) Conveyor causeway feeding the Crusher (climb the stairs: relic on the roof)
	do
		local a, b = V3(-300, 6, -60), V3(-428, 6, -62)
		local dir = (b - a).Unit
		rod(folder, a - V3(0, 1, 0), b - V3(0, 1, 0), 9, 1.4, DARK, M.Metal)
		for _, s in { -1, 1 } do
			local off = dir:Cross(V3(0, 1, 0)) * s * 4.8
			rod(folder, a + off + V3(0, 0.6, 0), b + off + V3(0, 0.6, 0), 0.6, 1.4, YELLOW, M.CorrodedMetal)
		end
		local legs = math.floor((b - a).Magnitude / 12)
		for k = 0, legs do
			local p = a:Lerp(b, k / legs)
			P(folder, CF(p - V3(0, 3.5, 0)), V3(7, 6, 1.2), DARK, M.Metal)
		end
		local belt = Kit.Model("Conveyor", folder)
		local count = math.floor((b - a).Magnitude / 2)
		for k = 0, count - 1 do
			local p = a + dir * (k * 2 + 1) + V3(0, 0.15, 0)
			P(belt, CFrame.lookAt(p, p + dir), V3(7.6, 0.3, 1.4), RGB(28, 28, 30), M.Fabric, glow)
		end
		Kit.Tag(belt, "WConveyor", { Speed = 5, Spacing = 2 })

		-- The Crusher building
		local L, C = Kit.Frame(CF(-446, 1, -70))
		P(folder, C(0, 11, 0), V3(28, 22, 26), RUST, M.CorrodedMetal)
		P(folder, C(14.2, 8, 8), V3(0.6, 8, 8), OIL, M.Metal) -- intake mouth (east face)
		for k = -2, 2 do
			P(folder, C(14.4, 8 + k * 1.6, 8), V3(0.4, 0.4, 8.4), STEEL, M.Metal, glow)
		end
		P(folder, C(0, 22.4, 0), V3(29, 0.8, 27), RUST2, M.DiamondPlate)
		local hammer = Kit.Model("CrusherHammer", folder)
		P(hammer, C(-4, 28, -4), V3(8, 6, 8), DARK, M.Metal)
		cyl(hammer, L(-4, 31, -4), L(-4, 36, -4), 2, CHROME, M.Metal)
		Kit.Tag(hammer, "WBob", { Amp = 2.5, Speed = 2.2 })
		for _, s in { -1, 1 } do
			P(folder, C(-4 + s * 5, 30, -4), V3(1.2, 14, 1.2), YELLOW, M.CorrodedMetal)
		end
		smokestack(folder, L(8, 22.8, -8), 26, 4)
		local warn = ball(folder, L(14.6, 14, 8), 1.2, GLOW, M.Neon, glow)
		Kit.Tag(warn, "WPulse", { Min = 0, Max = 0.9, Speed = 4 })
		Kit.Light(warn, GLOW, 2, 18)
		-- outside stairs on the west wall up to the roof
		local steps = 22
		for k = 0, steps - 1 do
			P(folder, C(-17, 0.5 + k, 18 - k * 1.45), V3(5, 1, 1.6), STEEL, M.DiamondPlate)
		end
		rod(folder, L(-19.6, 4, 18), L(-19.6, 25, -13.9), 0.3, 0.3, YELLOW, M.Metal, glow)
		P(folder, C(-17, 22.4, -12), V3(6, 0.8, 4), STEEL, M.DiamondPlate)
		Kit.Relic(folder, "CrusherLog", L(-8, 22.8, 6), region.Color)
		junkPile(folder, rng, L(0, 0, -24), 9, 20)
	end

	-- 3) Crane yard: cranes, containers, half-built war machines
	do
		crane(folder, V3(-405, 0, -46), 44, 46, -20, true)
		crane(folder, V3(-520, 0, 92), 50, 52, 150, true)
		local colors = { RGB(150, 50, 40), RGB(50, 90, 120), RGB(90, 100, 60), RGB(170, 120, 40) }
		for k = 0, 5 do
			local stackH = rng:NextInteger(1, 3)
			for h = 0, stackH - 1 do
				container(folder, CF(-500 + k * 9.5, 5 + h * 8, -38) * ANG(0, rad(rng:NextNumber(-3, 3)), 0), colors[rng:NextInteger(1, #colors)])
			end
		end
		warMachine(folder, V3(-460, 1, -20), 10)
		warMachine(folder, V3(-505, 1, -12), -15)
		junkPile(folder, rng, V3(-470, 0, 62), 12, 30)
		barrel(folder, V3(-450, 1, 16), RGB(120, 40, 30), true)
		car(folder, CF(-440, 1, 22) * ANG(0, 0.4, 0), RGB(60, 80, 100))
	end

	-- 4) Smelting pit (side trip south): molten channel, a pouring ladle, the Titan's Bolt
	do
		local pit = V3(-440, 1, 82)
		Kit.TBlock(CF(pit - V3(0, 2, 0)), V3(36, 4, 22), M.CrackedLava)
		P(folder, CF(pit - V3(0, 0.6, 0)), V3(32, 0.4, 18), GLOW, M.Neon, { NoCollide = false, Shadow = false, Transparency = 0.15 })
		Kit.Light(P(folder, CF(pit + V3(0, 3, 0)), V3(1, 1, 1), GLOW, M.Neon, { Transparency = 1, NoCollide = true, Shadow = false }), GLOW, 3, 40)
		Kit.Emitter(folder, CF(pit), V3(30, 0.4, 16), Kit.TEX.Spark, Kit.MotesFX(RGB(255, 170, 60), 20, 3, 0.3))
		for _, s in { -1, 1 } do
			P(folder, CF(pit + V3(0, 1, s * 11)), V3(38, 2, 2), DARK, M.Metal)
		end
		-- ladle on a gantry, tipped, pouring
		P(folder, CF(pit + V3(-22, 12, 0)), V3(2, 24, 2), YELLOW, M.CorrodedMetal)
		P(folder, CF(pit + V3(-12, 24, 0)), V3(22, 2, 2), YELLOW, M.CorrodedMetal)
		local ladle = CF(pit + V3(-6, 17, 0)) * ANG(0, 0, rad(-35))
		disc(folder, ladle, 8, 6, DARK, M.Metal)
		disc(folder, ladle * CF(0, 3.05, 0), 6.8, 0.2, GLOW, M.Neon, glow)
		local stream = P(folder, CF(pit + V3(-1.5, 9, 0)), V3(1.4, 14, 1.4), RGB(255, 150, 40), M.Neon, glow)
		Kit.Tag(stream, "WPulse", { Min = 0, Max = 0.3, Speed = 6 })
		-- the sheared bolt
		local boltAt = V3(-468, 1, 96)
		cyl(folder, boltAt + V3(-5, 1.6, 0), boltAt + V3(5, 1.6, 1), 3.2, CHROME, M.Metal)
		disc(folder, CF(boltAt + V3(5.6, 1.6, 1.06)) * ANG(0, 0, rad(90)), 5, 1.6, CHROME, M.Metal)
		Kit.Relic(folder, "TitanBolt", boltAt + V3(0, 0, -6), region.Color)
		Kit.Sign(folder, CFrame.lookAt(V3(-420, 5, 62), V3(-420, 5, 30)), V3(10, 2.4, 0.3), "SMELTER  ▸  DANGER", RGB(255, 150, 60), { Color = RGB(60, 40, 30), Material = M.CorrodedMetal })
	end

	-- 5) Approach: the Titan's footprints, flattened wrecks, the Foundry looming ahead
	do
		for k = 0, 5 do
			local t = k / 5
			local p = V3(-505 - t * 70, 1, 40 + (k % 2 == 0 and -6 or 6))
			footprint(folder, p, 90 + rng:NextNumber(-8, 8))
		end
		for k = 1, 4 do
			car(folder, CF(-500 - k * 16, 1, 64 + rng:NextNumber(-4, 4)) * ANG(0, rng:NextNumber(0, 6.3), 0), JUNK_COLORS[rng:NextInteger(1, #JUNK_COLORS)], true)
			car(folder, CF(-505 - k * 15, 1, 16 + rng:NextNumber(-4, 4)) * ANG(0, rng:NextNumber(0, 6.3), 0), JUNK_COLORS[rng:NextInteger(1, #JUNK_COLORS)], true)
		end
		junkPile(folder, rng, V3(-560, 0, 80), 14, 34)
		junkPile(folder, rng, V3(-560, 0, 2), 12, 28)
	end

	-- Background: smokestacks, a fallen colossus, distant cranes
	for _, s in { { -760, -260, 170, 26 }, { -860, -150, 210, 30 }, { -920, 110, 190, 28 }, { -800, 260, 150, 24 }, { -640, -320, 140, 22 }, { -980, -20, 230, 32 } } do
		smokestack(folder, V3(s[1], 0, s[2]), s[3], s[4])
	end
	crane(folder, V3(-700, 0, -250), 90, 80, 30, false)
	crane(folder, V3(-720, 0, 300), 80, 70, 200, false)
	do -- fallen colossus half-buried in the junk hill to the north
		local c = V3(-520, 30, -205)
		P(folder, CF(c) * ANG(0.4, 0.5, 0.3), V3(40, 30, 26), RUST, M.CorrodedMetal)
		P(folder, CF(c + V3(14, 28, -6)) * ANG(0.2, 0.4, 0.6), V3(20, 18, 18), DARK, M.Metal)
		local eyePos = c + V3(16, 30, 4)
		local eye = ball(folder, eyePos, 4, RGB(255, 80, 40), M.Neon, glow)
		Kit.Tag(eye, "WPulse", { Min = 0.2, Max = 0.95, Speed = 0.4 })
		rod(folder, c + V3(-14, 4, 10), c + V3(-40, 30, 40), 8, 8, STEEL, M.Metal)
		rod(folder, c + V3(-40, 30, 40), c + V3(-50, 60, 30), 6, 6, STEEL, M.Metal)
		for k = -1, 1 do
			rod(folder, c + V3(-50, 60, 30), c + V3(-50 + k * 6, 72, 30 + k * 2), 2, 2, CHROME, M.Metal)
		end
	end

	-- Drifting embers and ash over the whole expanse
	Kit.Emitter(folder, CF(-400, 4, 30), V3(440, 1, 300), Kit.TEX.Spark, Kit.MotesFX(RGB(255, 160, 70), 40, 1.4, 0.2))
	Kit.Emitter(folder, CF(-400, 40, 30), V3(440, 1, 300), Kit.TEX.Smoke, {
		Color = ColorSequence.new(RGB(110, 90, 80)),
		Size = NumberSequence.new(10, 24),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.88), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(14, 20),
		Rate = 4,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(80, 80),
		Acceleration = V3(-1.5, 0, 0),
	})
end

return ScrapRoute
