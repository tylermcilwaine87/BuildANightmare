--[[
	AbyssRoute  (ModuleScript)
	Location: ServerScriptService/Server/Services/World/AbyssRoute

	THE DROWNED DESCENT (south): ~100 studs down a black canyon, through a dripping
	cavern and drowned ruins, to the Abyssal Maw's Cathedral on the abyss sea.

	  Hub gate → the drowned stairs down the canyon wall
	             (ledge east: the divers' camp, Diver's Lamp)
	           → the dripping cavern → the flooded ruins
	             (side path west: the drowned chapel, Drowned Hymn)
	           → the bone bridge (vertebrae and ribs of something enormous)
	             (ledge under the bridge: the pearl grotto, Black Pearl) → the Cathedral gate
	Background: a leviathan's skeleton, giant tentacles rising from the sea, eyes in the dark.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local AbyssRoute = {}

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local M = Enum.Material
local P, ball, cyl, rod, disc = Kit.P, Kit.Ball, Kit.Cyl, Kit.Rod, Kit.Disc
local glow = { NoCollide = true, Shadow = false }

local WET, MOSS, BONE = RGB(52, 62, 64), RGB(40, 70, 60), RGB(196, 190, 166)
local TEAL, SICK = RGB(70, 240, 190), RGB(150, 230, 90)
local FLESH = RGB(40, 66, 70)
local SEA_Y = -103

local function nearest(pts, p: Vector3)
	local best, bestPoint = math.huge, nil
	for _, q in pts do
		local d = V3(p.X - q.X, 0, p.Z - q.Z).Magnitude
		if d < best then
			best, bestPoint = d, q
		end
	end
	return best, bestPoint
end

local function mushroom(parent, rng: Random, ground: Vector3)
	local h = rng:NextNumber(2, 6)
	cyl(parent, ground, ground + V3(0, h, 0), h * 0.18, RGB(150, 170, 160), M.SmoothPlastic, { NoCollide = true })
	local cap = Kit.Ellipsoid(parent, CF(ground + V3(0, h, 0)), V3(h * 0.9, h * 0.35, h * 0.9), RGB(30, 60, 70), M.SmoothPlastic, { NoCollide = true })
	for k = 1, 4 do
		local a = k / 4 * 2 * pi
		ball(parent, ground + V3(cos(a) * h * 0.28, h - h * 0.05, sin(a) * h * 0.28), h * 0.14, TEAL, M.Neon, glow)
	end
	return cap
end

local function tentacle(parent, base: Vector3, height: number, width: number, swirl: number)
	local pts = {}
	for i = 0, 14 do
		local t = i / 14
		local a = t * swirl
		pts[#pts + 1] = base + V3(cos(a) * width * 1.5 * t, t * height, sin(a) * width * 1.5 * t)
	end
	Kit.Tube(parent, pts, width, width * 0.15, FLESH, M.SmoothPlastic, { NoCollide = true })
	for i = 2, 13, 2 do
		ball(parent, pts[i] + V3(0, 0, width * 0.4 * (1 - i / 15)), width * 0.25 * (1 - i / 16), RGB(180, 110, 130), M.SmoothPlastic, { NoCollide = true })
	end
end

local function lantern(parent, ground: Vector3)
	cyl(parent, ground, ground + V3(0, 6, 0), 0.35, RGB(40, 44, 44), M.Metal)
	rod(parent, ground + V3(0, 6, 0), ground + V3(1.6, 6.4, 0), 0.25, 0.25, RGB(40, 44, 44), M.Metal)
	local lamp = P(parent, CF(ground + V3(1.6, 5.4, 0)), V3(1, 1.4, 1), TEAL, M.Neon, glow)
	Kit.Tag(Kit.Light(lamp, TEAL, 1.4, 18), "WFlicker", { Min = 0.8, Max = 1.6, Speed = 3 })
end

-- Giant rib bone arching over a point.
local function rib(parent, from: Vector3, to: Vector3, height: number, d: number)
	Kit.Curve(parent, from, to, V3(0, height, 0), d, d * 0.6, BONE, M.Limestone, 10, { NoCollide = true })
end

function AbyssRoute.Build(root)
	local region = WorldDefinitions.Regions.Abyss
	local folder = Kit.Folder("Route_Abyss", root)
	local rng = Random.new(4804)

	local descentControl = {
		V3(0, 1, 172),
		V3(0, 1, 212),
		V3(25, -10, 262),
		V3(45, -22, 306),
		V3(20, -36, 348),
		V3(-30, -50, 376),
		V3(-60, -62, 420),
		V3(-40, -74, 470),
		V3(-20, -84, 518),
	}
	local descent = Kit.Smooth(descentControl, 3)
	local bridgeA, bridgeB = V3(-20, -84, 518), V3(-40, -92, 560)
	local final = Kit.Smooth({ bridgeB, WorldDefinitions.GatePlaza("Abyss").Position }, 2)
	local all = table.clone(descent)
	for _, p in final do
		table.insert(all, p)
	end

	-- The canyon: a deep cut, walls on both sides of the path.
	Kit.TBlock(CF(0, -150, 450), V3(520, 60, 560), M.Mud) -- canyon floor far below
	local pathOpts = { Width = 16, Thickness = 2, Color = WET, Material = M.Slate, Fill = M.Limestone, FillDepth = 90, FillWidth = 30, Edge = { Color = RGB(40, 140, 120), Material = M.Neon } }
	Kit.Path(folder, descent, pathOpts)
	Kit.Path(folder, final, pathOpts)
	for i = 2, #all - 1, 2 do
		local a, b = all[i], all[math.min(#all, i + 1)]
		local side = (b - a).Unit:Cross(V3(0, 1, 0))
		for _, s in { -1, 1 } do
			local r = rng:NextNumber(30, 46)
			local pos = a + side * s * (r + 18 + rng:NextNumber(0, 10)) + V3(0, rng:NextNumber(0, 24), 0)
			local d = nearest(all, pos)
			if d > r + 12 then
				Kit.THill(rng, pos, r, rng:NextNumber() < 0.5 and M.Limestone or M.Rock, 3)
			end
		end
	end
	-- The cavern roof over the middle stretch, dripping.
	do
		local a, b = V3(25, -36, 340), V3(-38, -50, 384)
		local cf = Kit.Look(a, b)
		Kit.TBlock(cf * CF(0, 30, 0), V3(90, 18, (b - a).Magnitude + 30), M.Rock)
		Kit.Emitter(folder, cf * CF(0, 18, 0), V3(40, 1, (b - a).Magnitude), Kit.TEX.Spark, {
			Color = ColorSequence.new(RGB(150, 230, 220)),
			LightEmission = 0.5,
			Size = NumberSequence.new(0.15),
			Lifetime = NumberRange.new(1, 1.4),
			Rate = 30,
			Speed = NumberRange.new(10, 14),
			EmissionDirection = Enum.NormalId.Bottom,
			Acceleration = V3(0, -30, 0),
		})
		for k = 1, 10 do
			local p = a:Lerp(b, k / 11) + V3(rng:NextNumber(-14, 14), 18, rng:NextNumber(-6, 6))
			local h = rng:NextNumber(4, 10)
			cyl(folder, p, p - V3(0, h, 0), rng:NextNumber(1, 2.4), RGB(60, 70, 72), M.Rock, { NoCollide = true }) -- stalactites
			ball(folder, p - V3(0, h, 0), 0.6, TEAL, M.Neon, glow)
		end
	end

	-- Nothing may ever block the walkway (canyon walls, the cavern roof's underside).
	Kit.ClearCorridor(descent, 20, 18)
	Kit.ClearCorridor(final, 20, 18)

	-- Flooded ruins: shallow dark water around the path (a shallow floor, so anyone who
	-- slips in can wade back out), with railings along the path through it.
	Kit.TBlock(CF(-62, -67, 422), V3(110, 4, 80), M.Limestone)
	Kit.TBlock(CF(-62, -64, 422), V3(110, 2, 80), M.Water)
	Kit.Path(folder, { V3(-60, -62, 410), V3(-60, -62, 434) }, { Width = 16, Thickness = 2, Color = WET, Material = M.Slate }) -- re-lay the path over the water
	for i = 1, #descent - 1 do
		local a, b = descent[i], descent[i + 1]
		local inWater = function(p)
			return p.X > -117 and p.X < -7 and p.Z > 382 and p.Z < 462
		end
		if inWater(a) or inWater(b) then
			local side = (b - a).Unit:Cross(V3(0, 1, 0))
			for _, s in { -1, 1 } do
				local mid = (a + b) / 2 + side * s * 7.6
				if (mid - V3(-68, -62, 426)).Magnitude > 14 then -- leave the chapel side path open
					rod(folder, a + side * s * 7.6 + V3(0, 2.6, 0), b + side * s * 7.6 + V3(0, 2.6, 0), 0.4, 0.4, RGB(60, 70, 70), M.Metal)
					P(folder, CF(a + side * s * 7.6 + V3(0, 1.3, 0)), V3(0.5, 2.6, 0.5), RGB(60, 70, 70), M.Metal)
				end
			end
		end
	end
	for k = 1, 8 do
		local p = V3(-60 + rng:NextNumber(-45, 45), -66, 422 + rng:NextNumber(-34, 34))
		if nearest(all, p) > 14 then
			local h = rng:NextNumber(6, 18)
			P(folder, CF(p + V3(0, h / 2, 0)) * ANG(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), V3(4, h, 4), RGB(66, 74, 76), M.Cobblestone)
			P(folder, CF(p + V3(0, h * 0.25, 0)), V3(4.4, h * 0.5, 4.4), MOSS, M.Grass, { NoCollide = true })
		end
	end

	-- Mushrooms, lanterns and bones along the descent
	for i = 2, #all - 1, 2 do
		local a, b = all[i], all[math.min(#all, i + 1)]
		local side = (b - a).Unit:Cross(V3(0, 1, 0))
		local s = (i % 4 == 0) and 1 or -1
		for _ = 1, 2 do
			mushroom(folder, rng, a + side * s * rng:NextNumber(9, 12) + (b - a).Unit * rng:NextNumber(-4, 4) - V3(0, 1, 0))
		end
		if i % 6 == 0 then
			lantern(folder, a - side * s * 9 - V3(0, 1, 0))
		end
	end
	for k = 1, 4 do
		local i = 4 + k * 5
		local a = all[math.min(i, #all)]
		local b = all[math.min(i + 1, #all)]
		local side = (b - a).Unit:Cross(V3(0, 1, 0))
		rib(folder, a + side * 12 - V3(0, 2, 0), a - side * 12 - V3(0, 2, 0), 18, 2.6)
	end

	-- 1) The divers' camp (ledge east of the stairs)
	do
		local camp = V3(86, -22, 300)
		Kit.TBlock(CF(camp - V3(0, 40, 0)), V3(30, 80, 26), M.Limestone)
		Kit.Path(folder, { V3(52, -22, 304), camp + V3(-12, 0, 0) }, { Width = 8, Thickness = 2, Color = WET, Material = M.Slate })
		disc(folder, CF(camp - V3(0, 1, 0)), 24, 2, WET, M.Slate)
		lantern(folder, camp + V3(-4, 0, -6))
		P(folder, CF(camp + V3(4, 1.2, -4)), V3(3, 2.4, 2.4), RGB(80, 66, 50), M.WoodPlanks)
		cyl(folder, camp + V3(8, 0, 5), camp + V3(8, 3, 5), 1.6, RGB(110, 90, 60), M.Fabric) -- coiled rope
		Kit.Cable(folder, camp + V3(10, 1, 8), camp + V3(14, -40, 12), 0, 0.25, RGB(120, 100, 70), M.Fabric, 3)
		Kit.Relic(folder, "DiversLamp", camp + V3(2, 0, 6), region.Color)
	end

	-- 2) The drowned chapel (west of the flooded ruins)
	do
		local chapel = V3(-116, -62, 430)
		Kit.TBlock(CF(chapel - V3(0, 40, 0)), V3(40, 80, 34), M.Limestone)
		Kit.Path(folder, { V3(-72, -62, 426), chapel + V3(16, 0, 0) }, { Width = 8, Thickness = 2, Color = WET, Material = M.Slate })
		disc(folder, CF(chapel - V3(0, 1, 0)), 32, 2, RGB(70, 76, 78), M.Cobblestone)
		for _, w in { { -14, 0, 2, 26, 14 }, { 0, -13, 28, 2, 9 }, { 0, 13, 28, 2, 5 } } do
			P(folder, CF(chapel + V3(w[1], w[5] / 2, w[2])), V3(w[3], w[5], w[4]), RGB(74, 80, 82), M.Cobblestone)
		end
		-- the broken bell tower and its fallen bell
		P(folder, CF(chapel + V3(-14, 18, 0)), V3(6, 8, 6), RGB(74, 80, 82), M.Cobblestone)
		disc(folder, CF(chapel + V3(6, 1.8, -6)) * ANG(rad(70), 0, 0.3), 5, 4, RGB(80, 110, 90), M.Metal)
		for k = -1, 1 do
			P(folder, CF(chapel + V3(-6, 1, k * 4)), V3(2, 2, 3), RGB(60, 50, 42), M.WoodPlanks) -- pews
		end
		Kit.Relic(folder, "DrownedHymn", chapel + V3(-9, 0, 0), region.Color)
	end

	-- 3) The bone bridge: a giant spine with rib planks across the chasm
	do
		local dir = (bridgeB - bridgeA).Unit
		local side = dir:Cross(V3(0, 1, 0))
		local len = (bridgeB - bridgeA).Magnitude
		local count = math.floor(len / 3)
		for k = 0, count do
			local p = bridgeA:Lerp(bridgeB, k / count)
			local cf = CFrame.lookAt(p, p + dir)
			P(folder, cf * CF(0, -0.8, 0), V3(12, 1.6, 2.6), BONE, M.Limestone) -- vertebra slab
			if k % 2 == 0 then
				for _, s in { -1, 1 } do
					Kit.Curve(folder, p + side * s * 6, p + side * s * 9 + V3(0, 9, 0), side * s * 3, 1.2, 0.4, BONE, M.Limestone, 5, { NoCollide = true })
				end
			end
		end
		for _, s in { -1, 1 } do
			rod(folder, bridgeA + side * s * 6.2 + V3(0, 3, 0), bridgeB + side * s * 6.2 + V3(0, 3, 0), 0.6, 8, Color3.new(), M.SmoothPlastic, { Transparency = 1, Shadow = false })
		end
		-- dangling chains
		for k = 1, 4 do
			local p = bridgeA:Lerp(bridgeB, k / 5) + side * (k % 2 == 0 and 6 or -6)
			Kit.Cable(folder, p, p - V3(0, 12, 0), 0, 0.3, RGB(50, 56, 56), M.Metal, 3)
		end
	end

	-- 4) The pearl grotto (ledge beside the bridge)
	do
		local grotto = V3(10, -84, 534)
		Kit.TBlock(CF(grotto - V3(0, 30, 0)), V3(26, 60, 24), M.Limestone)
		Kit.Path(folder, { V3(-14, -84, 522), grotto + V3(-9, 0, -4) }, { Width = 6, Thickness = 1.6, Color = WET, Material = M.Slate })
		disc(folder, CF(grotto - V3(0, 1, 0)), 20, 2, WET, M.Slate)
		Kit.Ellipsoid(folder, CF(grotto + V3(2, 1, 2)), V3(10, 2.4, 8), RGB(80, 70, 90), M.SmoothPlastic)
		Kit.Ellipsoid(folder, CF(grotto + V3(2, 4, 5)) * ANG(rad(-55), 0, 0), V3(10, 2, 8), RGB(80, 70, 90), M.SmoothPlastic)
		for k = 1, 3 do
			local pearl = ball(folder, grotto + V3(k * 2 - 2, 2.6, 2), 1.2, RGB(30, 26, 40), M.Glass, { Reflect = 0.5 })
			Kit.Tag(Kit.Light(pearl, SICK, 1, 10), "WPulse", { Min = 0.4, Max = 1.6, Speed = 1.2 + k * 0.2 })
		end
		Kit.Relic(folder, "AbyssPearl", grotto + V3(-4, 0, 3), region.Color)
	end

	-- The abyss sea around the Cathedral
	Kit.TBlock(CF(-40, SEA_Y - 8, 720), V3(560, 16, 480), M.Water)
	Kit.TBlock(CF(-40, SEA_Y - 40, 720), V3(600, 48, 520), M.Mud)

	-- Background: a leviathan skeleton, tentacles rising from the sea, eyes in the dark
	do
		local spineA, spineB = V3(-330, SEA_Y + 4, 640), V3(-260, SEA_Y + 10, 880)
		Kit.Curve(folder, spineA, spineB, V3(-20, 14, 0), 9, 6, BONE, M.Limestone, 14, { NoCollide = true })
		for k = 1, 9 do
			local p = spineA:Lerp(spineB, k / 10)
			rib(folder, p + V3(-4, 0, 0), p + V3(70, -14, 0), 60 - math.abs(k - 5) * 5, 5)
		end
		local skull = V3(-340, SEA_Y + 20, 600)
		Kit.Ellipsoid(folder, CF(skull) * ANG(0, 0.4, 0.2), V3(40, 30, 60), BONE, M.Limestone, { NoCollide = true })
		ball(folder, skull + V3(12, 6, -18), 10, RGB(10, 14, 16), M.SmoothPlastic, { NoCollide = true })
	end
	for k = 1, 7 do
		local a = rad(-30 + k * 30)
		local base = V3(-40 + sin(a) * rng:NextNumber(300, 520), SEA_Y - 10, 700 + cos(a) * rng:NextNumber(260, 420))
		local t = Kit.Model("AbyssTentacle", folder)
		tentacle(t, base, rng:NextNumber(90, 160), rng:NextNumber(7, 12), rng:NextNumber(2, 4))
		t.WorldPivot = CF(base)
		Kit.Tag(t, "WSwing", { Angle = 5, Speed = rng:NextNumber(0.2, 0.4), Axis = "Z" })
	end
	for k = 1, 6 do
		local a = rad(-20 + k * 40)
		local pos = V3(-40 + sin(a) * 600, SEA_Y + rng:NextNumber(20, 70), 700 + cos(a) * 480)
		local eyes = Kit.Model("LurkingEyes", folder)
		for _, s in { -1, 1 } do
			local eye = ball(eyes, pos + V3(s * 9, 0, 0), 6, SICK, M.Neon, glow)
			Kit.Tag(eye, "WPulse", { Min = 0.05, Max = 1, Speed = rng:NextNumber(0.2, 0.5) })
		end
		eyes.WorldPivot = CF(pos)
		Kit.Tag(eyes, "WOrbit", { Center = pos, Radius = 20, Speed = rng:NextNumber(0.02, 0.05), Height = 6 })
	end
	-- sunken spires of a drowned city
	for k = 1, 5 do
		local base = V3(-40 + rng:NextNumber(-260, 260), SEA_Y - 20, 700 + rng:NextNumber(180, 300))
		local h = rng:NextNumber(60, 120)
		P(folder, CF(base + V3(0, h / 2, 0)) * ANG(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), V3(14, h, 14), RGB(50, 58, 60), M.Cobblestone, { NoCollide = true })
		for d = 0, 3 do
			disc(folder, CF(base + V3(0, h + d * 6, 0)), 12 - d * 3, 6, RGB(50, 58, 60), M.Cobblestone, { NoCollide = true })
		end
	end

	-- Mist and spores
	Kit.Emitter(folder, CF(-10, -60, 450), V3(240, 1, 320), Kit.TEX.Smoke, {
		Color = ColorSequence.new(RGB(70, 140, 140)),
		Size = NumberSequence.new(14, 26),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.8), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(12, 18),
		Rate = 10,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(80, 80),
	})
	Kit.Emitter(folder, CF(-10, -40, 450), V3(240, 1, 320), Kit.TEX.Spark, Kit.MotesFX(TEAL, 40, 0.6, 0.2))
end

return AbyssRoute
