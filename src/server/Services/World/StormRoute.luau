--[[
	StormRoute  (ModuleScript)
	Location: ServerScriptService/Server/Services/World/StormRoute

	THE STORM CLIFFS (north): a climb of ~120 studs up a storm-ravaged mountain to the
	Storm Beast's Tempest Summit.

	  Hub gate → switchback ledges past arcing storm pylons and burnt trees
	           (side spur: the ruined cliff fort, tower top: Last Banner)
	           (side spur east: the crystal grotto, Captured Storm Core)
	           (ledge before the bridge: the climbers' last camp, Scorched Helm)
	           → the broken rope bridge over the chasm → the final ramp → the Summit gate
	Background: snow-capped peaks, a shattered spire, floating rocks, rain and wind.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local StormRoute = {}

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local M = Enum.Material
local P, ball, cyl, rod, disc = Kit.P, Kit.Ball, Kit.Cyl, Kit.Rod, Kit.Disc
local glow = { NoCollide = true, Shadow = false }

local STONE, DARK, BOLT = RGB(70, 74, 86), RGB(40, 42, 52), RGB(120, 210, 255)
local WOOD, ROPE = RGB(84, 66, 50), RGB(120, 100, 70)
local BANNER = RGB(40, 60, 110)

-- Horizontal distance from p to the nearest of `pts`, and that point.
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

-- A jagged terrain crag (tilted slabs, not round hills) that never intrudes on the
-- walkable corridor.
local function crag(rng, pts, pos: Vector3, radius: number, mat)
	local d, q = nearest(pts, pos)
	if q and d < radius * 1.5 + 16 and pos.Y + radius * 1.6 > q.Y - 3 then
		-- too close and too tall: sink it so it stays below the path
		pos = V3(pos.X, q.Y - 6 - radius * 1.6, pos.Z)
	end
	for _ = 1, 3 do
		local size = V3(radius * rng:NextNumber(0.7, 1.2), radius * rng:NextNumber(1.6, 2.4), radius * rng:NextNumber(0.6, 1))
		Kit.TBlock(CF(pos + V3(rng:NextNumber(-0.4, 0.4) * radius, 0, rng:NextNumber(-0.4, 0.4) * radius)) * ANG(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6.3), rng:NextNumber(-0.25, 0.25)), size, mat)
	end
end

local function pylon(parent, ground: Vector3)
	disc(parent, CF(ground + V3(0, 0.5, 0)), 4, 1, DARK, M.Metal)
	cyl(parent, ground, ground + V3(0, 16, 0), 1, RGB(110, 112, 124), M.Metal)
	for k = 0, 4 do
		disc(parent, CF(ground + V3(0, 10 + k * 1.2, 0)), 2.6, 0.4, RGB(160, 120, 70), M.Metal)
	end
	local tip = ball(parent, ground + V3(0, 17, 0), 1.8, BOLT, M.Neon, glow)
	Kit.Tag(Kit.Light(tip, BOLT, 1.5, 22), "WFlicker", { Min = 0.4, Max = 2.5, Speed = 7 })
	Kit.Emitter(parent, CF(ground + V3(0, 17, 0)), V3(1.6, 1.6, 1.6), Kit.TEX.Spark, Kit.SparkFX(RGB(210, 240, 255), 10))
	return ground + V3(0, 17, 0)
end

-- A jagged arc of light between two points (flickers on the client).
local function arc(parent, rng: Random, a: Vector3, b: Vector3)
	local model = Kit.Model("Arc", parent)
	local prev = a
	for k = 1, 6 do
		local t = k / 6
		local p = a:Lerp(b, t) + (k < 6 and V3(rng:NextNumber(-2, 2), rng:NextNumber(-3, 1) - sin(t * pi) * 4, rng:NextNumber(-2, 2)) or V3())
		local seg = cyl(model, prev, p, 0.3, RGB(200, 240, 255), M.Neon, glow)
		Kit.Tag(seg, "WPulse", { Min = 0, Max = 1, Speed = 9 + k })
		prev = p
	end
end

local function deadTree(parent, rng: Random, ground: Vector3)
	local h = rng:NextNumber(10, 18)
	local top = ground + V3(rng:NextNumber(-1.5, 1.5), h, rng:NextNumber(-1.5, 1.5))
	cyl(parent, ground - V3(0, 1, 0), top, 1.4, RGB(26, 24, 26), M.Wood)
	for _ = 1, 4 do
		local from = ground:Lerp(top, rng:NextNumber(0.4, 0.9))
		cyl(parent, from, from + V3(rng:NextNumber(-5, 5), rng:NextNumber(1, 4), rng:NextNumber(-5, 5)), 0.5, RGB(26, 24, 26), M.Wood, { NoCollide = true })
	end
	Kit.Ellipsoid(parent, CF(ground + V3(0, 0.1, 0)), V3(8, 0.3, 8), RGB(20, 18, 22), M.Slate, glow) -- scorch mark
end

local function banner(parent, top: Vector3, height: number, torn: boolean?)
	cyl(parent, top - V3(0, height + 6, 0), top, 0.5, DARK, M.Metal)
	P(parent, CF(top - V3(0, height / 2 + 0.5, 1.6)), V3(0.15, height, 3), BANNER, M.Fabric, glow)
	if torn then
		P(parent, CF(top - V3(0, height + 1, 2.4)) * ANG(rad(20), 0, 0), V3(0.15, 2, 1.4), BANNER, M.Fabric, glow)
	end
	P(parent, CF(top - V3(0, height * 0.4, 0.85)), V3(0.2, 1.4, 1.4) * V3(1, 1, 1), BOLT, M.Neon, glow)
end

function StormRoute.Build(root)
	local region = WorldDefinitions.Regions.Storm
	local folder = Kit.Folder("Route_Storm", root)
	local rng = Random.new(3603)

	local climbControl = {
		V3(0, 1, -172),
		V3(0, 1, -212),
		V3(-28, 12, -262),
		V3(-66, 26, -296),
		V3(-58, 40, -340),
		V3(0, 54, -366),
		V3(58, 66, -392),
		V3(80, 78, -438),
		V3(52, 90, -478),
	}
	local climb = Kit.Smooth(climbControl, 3)
	local bridgeA, bridgeB = V3(52, 90, -478), V3(40, 96, -528)
	-- the last ramp reaches the plaza's height BEFORE the plaza's edge (no ledge)
	local plaza = WorldDefinitions.GatePlaza("Storm").Position
	local summit = { bridgeB, V3(40, 108, -548), V3(plaza.X, plaza.Y, plaza.Z + 24), plaza }
	local all = table.clone(climb)
	for _, p in Kit.Smooth(summit, 3) do
		table.insert(all, p)
	end
	for k = 1, 5 do
		table.insert(all, bridgeA:Lerp(bridgeB, k / 6)) -- keep crags off the bridge span too
	end

	-- The mountain: the ridge under the path, then crags and cliffs around it.
	local pathOpts = { Width = 16, Thickness = 2, Color = RGB(78, 80, 92), Material = M.Slate, Fill = M.Slate, FillDepth = 150, FillWidth = 40, Edge = { Color = RGB(60, 120, 170), Material = M.Neon } }
	Kit.Path(folder, climb, pathOpts)
	Kit.Path(folder, Kit.Smooth(summit, 3), pathOpts)
	Kit.TBlock(CF(0, -30, -300), V3(320, 60, 260), M.Basalt)
	Kit.TBlock(CF(40, -10, -520), V3(300, 100, 220), M.Basalt)
	local arenaCenter = region.Arena.Position
	for _ = 1, 40 do
		local pos = V3(rng:NextNumber(-180, 220), rng:NextNumber(-10, 110), rng:NextNumber(-660, -200))
		local radius = rng:NextNumber(18, 40)
		-- never inside the Tempest Summit (or its plaza)
		if V3(pos.X - arenaCenter.X, 0, pos.Z - arenaCenter.Z).Magnitude > 120 + radius * 1.5 then
			crag(rng, all, pos, radius, rng:NextNumber() < 0.6 and M.Slate or M.Basalt)
		end
	end
	-- The chasm under (and the air above) the bridge stays open: carve it back out.
	Kit.TBlock(Kit.Look(bridgeA, bridgeB) * CF(0, -30, 0), V3(60, 180, (bridgeB - bridgeA).Magnitude - 14), M.Air)
	Kit.TBlock(Kit.Look(bridgeA, bridgeB) * CF(0, 30, 0), V3(30, 60, (bridgeB - bridgeA).Magnitude + 20), M.Air)
	-- and nothing may ever block the walkway itself
	Kit.ClearCorridor(climb, 20, 26)
	Kit.ClearCorridor(Kit.Smooth(summit, 3), 20, 26)

	-- Pylons with arcs between them, burnt trees and scorch marks along the climb
	local pylonTips = {}
	for i = 3, #climb - 2, 5 do
		local a, b = climb[i], climb[i + 1]
		local side = (b - a).Unit:Cross(V3(0, 1, 0))
		local s = (i // 5) % 2 == 0 and 1 or -1
		table.insert(pylonTips, pylon(folder, a + side * s * 11 - V3(0, 1, 0)))
	end
	for i = 1, #pylonTips - 1 do
		if (pylonTips[i + 1] - pylonTips[i]).Magnitude < 90 then
			arc(folder, rng, pylonTips[i], pylonTips[i + 1])
		end
	end
	for i = 2, #climb - 1, 3 do
		local a, b = climb[i], climb[i + 1]
		local side = (b - a).Unit:Cross(V3(0, 1, 0))
		deadTree(folder, rng, a - side * ((i % 2 == 0) and 13 or -13) - V3(0, 1, 0))
	end

	-- 1) The ruined cliff fort (spur west of the ridge), Last Banner on the tower top
	do
		local fort = V3(4, 54, -412)
		Kit.TBlock(CF(fort - V3(0, 60, 0)), V3(52, 120, 46), M.Slate)
		Kit.Path(folder, { V3(2, 54, -370), fort + V3(0, 0, 18) }, { Width = 10, Thickness = 2, Color = RGB(78, 80, 92), Material = M.Slate })
		P(folder, CF(fort - V3(0, 1, 0)), V3(44, 2, 38), RGB(84, 82, 90), M.Cobblestone)
		for _, w in { { -21, 0, 2, 38, 8 }, { 21, 0, 2, 38, 5 }, { 0, -18, 44, 2, 10 } } do
			P(folder, CF(fort + V3(w[1], w[5] / 2, w[2])), V3(w[3], w[5], w[4]), RGB(88, 86, 96), M.Cobblestone)
		end
		for k = 1, 5 do
			P(folder, CF(fort + V3(rng:NextNumber(-16, 16), 1, rng:NextNumber(-12, 12))) * ANG(rng:NextNumber(0, 1), rng:NextNumber(0, 6), 0), V3(3, 2, 2) * rng:NextNumber(0.8, 1.6), RGB(88, 86, 96), M.Cobblestone)
		end
		-- tower with outside stairs
		local tower = fort + V3(-12, 0, -10)
		disc(folder, CF(tower + V3(0, 13, 0)), 12, 26, RGB(80, 78, 88), M.Cobblestone)
		disc(folder, CF(tower + V3(0, 26.5, 0)), 14, 1, DARK, M.Slate)
		for k = 0, 23 do
			local a = rad(k * 15)
			local r = 8.5
			P(folder, CF(tower + V3(cos(a) * r, 0.5 + k * 1.08, sin(a) * r)) * ANG(0, -a, 0), V3(4, 1, 3.4), RGB(70, 68, 76), M.Cobblestone)
		end
		for k = 0, 7 do
			local a = rad(k * 45)
			if k % 2 == 0 then
				P(folder, CF(tower + V3(cos(a) * 6.4, 28.5, sin(a) * 6.4)), V3(2, 3, 2), RGB(80, 78, 88), M.Cobblestone)
			end
		end
		banner(folder, tower + V3(0, 40, 0), 7, true)
		Kit.Relic(folder, "TornBanner", tower + V3(2, 27, 2), region.Color)
		banner(folder, fort + V3(18, 16, -16), 6, true)
		banner(folder, fort + V3(-18, 14, 16), 5, false)
	end

	-- 2) The crystal grotto (spur east), Captured Storm Core
	do
		local grotto = V3(124, 78, -432)
		Kit.TBlock(CF(grotto - V3(0, 60, 0)), V3(36, 120, 36), M.Basalt)
		Kit.Path(folder, { V3(84, 78, -432), grotto + V3(-12, 0, 0) }, { Width = 9, Thickness = 2, Color = RGB(78, 80, 92), Material = M.Slate })
		disc(folder, CF(grotto - V3(0, 1, 0)), 30, 2, RGB(60, 62, 74), M.Slate)
		for _ = 1, 9 do
			local a = rng:NextNumber(0, 2 * pi)
			local base = grotto + V3(cos(a) * rng:NextNumber(5, 12), 0, sin(a) * rng:NextNumber(5, 12))
			local h = rng:NextNumber(4, 11)
			P(folder, CF(base + V3(0, h / 2, 0)) * ANG(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 6), rng:NextNumber(-0.35, 0.35)), V3(h * 0.25, h, h * 0.25), BOLT, M.Neon, glow)
		end
		Kit.Tag(Kit.Light(P(folder, CF(grotto + V3(0, 6, 0)), V3(1, 1, 1), BOLT, M.Neon, { Transparency = 1, NoCollide = true, Shadow = false }), BOLT, 3, 34), "WFlicker", { Min = 1.5, Max = 4, Speed = 4 })
		Kit.Emitter(folder, CF(grotto + V3(0, 4, 0)), V3(20, 6, 20), Kit.TEX.Spark, Kit.SparkFX(RGB(210, 240, 255), 18))
		Kit.Relic(folder, "StormCore", grotto + V3(4, 0, 4), region.Color)
	end

	-- 3) The climbers' last camp (ledge before the bridge), Scorched Helm
	do
		local camp = V3(24, 90, -466)
		Kit.TBlock(CF(camp - V3(0, 40, 0)), V3(24, 80, 22), M.Slate)
		disc(folder, CF(camp - V3(0, 1, 0)), 20, 2, RGB(70, 72, 82), M.Slate)
		-- a collapsed tent
		rod(folder, camp + V3(-6, 0, -3), camp + V3(-2, 4, -3), 0.3, 0.3, WOOD, M.Wood)
		P(folder, CF(camp + V3(-4, 1.6, -1)) * ANG(0, 0.3, rad(30)), V3(7, 0.2, 6), RGB(140, 60, 40), M.Fabric)
		disc(folder, CF(camp + V3(3, 0.2, 2)), 3, 0.4, RGB(20, 18, 18), M.Slate) -- dead campfire
		Kit.Cable(folder, camp + V3(8, 1, -6), camp + V3(10, -20, -9), 0, 0.25, ROPE, M.Fabric, 3) -- rope over the edge
		Kit.Relic(folder, "ScorchedHelm", camp + V3(-2, 0, 4), region.Color)
	end

	-- 4) The broken rope bridge over the chasm
	do
		local dir = (bridgeB - bridgeA).Unit
		local side = dir:Cross(V3(0, 1, 0))
		local len = (bridgeB - bridgeA).Magnitude
		local planks = math.floor(len / 1.6)
		for k = 0, planks do
			local t = k / planks
			local p = bridgeA:Lerp(bridgeB, t) - V3(0, sin(t * pi) * 2.5 + 0.3, 0)
			local cf = CFrame.lookAt(p, p + dir)
			if k % 7 == 3 then
				P(folder, cf * CF(-2.4, 0, 0), V3(5, 0.5, 1.4), WOOD, M.WoodPlanks) -- half a plank left
			else
				P(folder, cf, V3(10, 0.5, 1.4), WOOD, M.WoodPlanks)
			end
		end
		for _, s in { -1, 1 } do
			for _, e in { bridgeA, bridgeB } do
				P(folder, CF(e + side * s * 5.6 + V3(0, 2, 0)), V3(1, 6, 1), WOOD, M.Wood)
			end
			Kit.Cable(folder, bridgeA + side * s * 5.6 + V3(0, 4, 0), bridgeB + side * s * 5.6 + V3(0, 4, 0), 3, 0.3, ROPE, M.Fabric, 12)
		end
		-- an invisible guard rail so a gust never pushes anyone off
		for _, s in { -1, 1 } do
			rod(folder, bridgeA + side * s * 5.8 + V3(0, 3, 0), bridgeB + side * s * 5.8 + V3(0, 3, 0), 0.6, 8, Color3.new(), M.SmoothPlastic, { Transparency = 1, Shadow = false })
		end
	end

	-- Torn banners and lightning rods leading to the Summit
	for k = 0, 2 do
		local t = k / 2
		local p = bridgeB:Lerp(WorldDefinitions.GatePlaza("Storm").Position, t)
		banner(folder, p + V3(-12, 14, 0), 7, k ~= 1)
		banner(folder, p + V3(12, 14, 0), 7, k == 1)
	end

	-- Floating rocks around the cliffs
	for _ = 1, 22 do
		local i = rng:NextInteger(1, #all)
		local off = V3(rng:NextNumber(-70, 70), rng:NextNumber(15, 60), rng:NextNumber(-70, 70))
		if V3(off.X, 0, off.Z).Magnitude > 28 then
			local rock = P(folder, CF(all[i] + off) * ANG(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)), V3(1, 1, 1) * rng:NextNumber(3, 9), STONE, M.Slate, { NoCollide = true })
			Kit.Tag(rock, "WBob", { Amp = rng:NextNumber(1, 3), Speed = rng:NextNumber(0.3, 0.8) })
		end
	end

	-- Background: snow-capped peaks and a shattered spire
	for k = 0, 12 do
		local a = rad(-60 + k * 10)
		local dist = rng:NextNumber(820, 1050)
		local pos = V3(sin(a) * dist, rng:NextNumber(-40, 20), -cos(a) * dist)
		local r = rng:NextNumber(150, 220)
		Kit.THill(rng, pos, r, M.Basalt, 3)
		Kit.TBall(pos + V3(0, r * 0.82, 0), r * 0.35, M.Snow)
	end
	do
		local base = V3(-260, 0, -900)
		P(folder, CF(base + V3(0, 110, 0)) * ANG(0, 0, 0.06), V3(40, 220, 40), DARK, M.Basalt, { NoCollide = true })
		P(folder, CF(base + V3(16, 240, 6)) * ANG(0.3, 0.2, 0.5), V3(30, 60, 30), DARK, M.Basalt, { NoCollide = true })
		local crown = ball(folder, base + V3(0, 228, 0), 10, BOLT, M.Neon, glow)
		Kit.Tag(crown, "WPulse", { Min = 0, Max = 0.9, Speed = 1.3 })
		Kit.Light(crown, BOLT, 4, 120)
	end

	-- Rain and wind over the whole climb
	Kit.Emitter(folder, CF(20, 170, -400), V3(360, 1, 400), Kit.TEX.Spark, {
		Color = ColorSequence.new(RGB(190, 210, 240)),
		LightEmission = 0.3,
		Size = NumberSequence.new(0.12),
		Transparency = NumberSequence.new(0.4, 0.8),
		Lifetime = NumberRange.new(1.6, 2.2),
		Rate = 260,
		Speed = NumberRange.new(90, 110),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(4, 4),
		Acceleration = V3(-20, 0, 0),
	})
	Kit.Emitter(folder, CF(150, 80, -420), V3(1, 120, 380), Kit.TEX.Smoke, {
		Color = ColorSequence.new(RGB(160, 170, 190)),
		Size = NumberSequence.new(6, 14),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(5, 7),
		Rate = 10,
		Speed = NumberRange.new(40, 60),
		EmissionDirection = Enum.NormalId.Left,
		SpreadAngle = Vector2.new(8, 8),
	})
end

return StormRoute
