--[[
	MirrorRoute  (ModuleScript)
	Location: ServerScriptService/Server/Services/World/MirrorRoute

	THE SHATTERED REACH (east): glowing white walkways floating over a silver mirror
	lake, towards the Mirror Warden's Hall of Reflections.

	  Hub gate → glass bridge → Plaza of Echoes (mirrored statues, one of each pair broken;
	           a narrow beam north to a floating island: Cracked Locket)
	           → mirrored zigzag (mirror walls at every turn)
	             (side bridge south: the Reflection Pool, Silver Quill)
	           → (side bridge north: the Abandoned Temple, Warden's Sigil) → the Hall's gate
	Everything important has an upside-down "reflection" hanging beneath it.
	Background: giant drifting mirror shards, inverted floating islands, fractured towers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local MirrorRoute = {}

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local M = Enum.Material
local P, ball, cyl, rod, disc = Kit.P, Kit.Ball, Kit.Cyl, Kit.Rod, Kit.Disc
local glow = { NoCollide = true, Shadow = false }

local WHITE, SILVER, PALE = RGB(226, 226, 238), RGB(196, 200, 220), RGB(160, 150, 200)
local GLASS = RGB(190, 205, 240)
local VIOLET, CYAN = RGB(200, 170, 255), RGB(150, 230, 255)
local LAKE_Y = -70

local mirrorOpts = { Reflect = 0.55, Transparency = 0.15 }

-- A tall ornate mirror. broken = cracked with shards on the floor.
local function mirror(parent, cf: CFrame, height: number, width: number, broken: boolean?, rng: Random?)
	local _, C = Kit.Frame(cf)
	P(parent, C(0, height / 2, 0), V3(width, height, 0.4), broken and RGB(120, 130, 160) or GLASS, M.Glass, mirrorOpts)
	for _, s in { -1, 1 } do
		P(parent, C(s * (width / 2 + 0.5), height / 2, 0), V3(1, height + 1, 1), SILVER, M.Marble)
	end
	P(parent, C(0, height + 0.5, 0), V3(width + 2, 1, 1), SILVER, M.Marble)
	P(parent, C(0, height + 1.6, 0), V3(2.4, 2.4, 0.6), VIOLET, M.Neon, glow)
	if broken and rng then
		for _ = 1, 6 do
			P(parent, C(rng:NextNumber(-width, width), 0.2, rng:NextNumber(-4, 4), 0, rng:NextNumber(0, 180), 90), V3(0.2, rng:NextNumber(1, 3), rng:NextNumber(1, 2)), GLASS, M.Glass, { Reflect = 0.5, NoCollide = true })
		end
	end
end

-- An abstract robed statue; `broken` = toppled, headless.
local function statue(parent, ground: Vector3, yaw: number, broken: boolean?)
	local base = CF(ground) * ANG(0, rad(yaw), 0)
	local L, C = Kit.Frame(base)
	P(parent, C(0, 1, 0), V3(5, 2, 5), SILVER, M.Marble)
	if broken then
		local body = C(0, 4.4, 1.5, 70, 0, 8)
		Kit.Ellipsoid(parent, body, V3(3, 9, 3), WHITE, M.Marble)
		ball(parent, L(2.5, 2.8, -3), 2.2, WHITE, M.Marble)
	else
		Kit.Ellipsoid(parent, C(0, 7, 0), V3(3.4, 10, 3.4), WHITE, M.Marble)
		ball(parent, L(0, 13, 0), 2.4, WHITE, M.Marble)
		for _, s in { -1, 1 } do
			rod(parent, L(s * 1.6, 10, 0), L(s * 3, 14.5, -1), 0.8, 0.8, WHITE, M.Marble)
		end
		P(parent, C(0, 13, -1.2), V3(1.6, 0.3, 0.2), VIOLET, M.Neon, glow)
	end
end

-- A floating mirror shard (decor).
local function shard(parent, rng: Random, pos: Vector3, scale: number)
	local p = P(parent, CF(pos) * ANG(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.3), rng:NextNumber(-0.5, 0.5)), V3(rng:NextNumber(0.6, 1.4) * scale * 0.15, rng:NextNumber(3, 6) * scale, rng:NextNumber(1.5, 3) * scale), GLASS, M.Glass, { Reflect = 0.6, Transparency = 0.1, NoCollide = true })
	Kit.Tag(p, "WBob", { Amp = scale * 0.25, Speed = rng:NextNumber(0.3, 0.7) })
	return p
end

-- A walkway support: a slim white column down to the lake, with a glowing band.
local function support(parent, top: Vector3)
	cyl(parent, top - V3(0, 2, 0), V3(top.X, LAKE_Y, top.Z), 2.2, WHITE, M.Marble)
	disc(parent, CF(top - V3(0, 6, 0)), 3, 0.5, VIOLET, M.Neon, glow)
end

function MirrorRoute.Build(root)
	local region = WorldDefinitions.Regions.Mirror
	local folder = Kit.Folder("Route_Mirror", root)
	local rng = Random.new(2402)

	-- The mirror lake far below (not solid: falling in = back to the Forge).
	P(folder, CF(760, LAKE_Y, -20), V3(1200, 1, 1300), RGB(150, 156, 186), M.SmoothPlastic, { NoCollide = true, Reflect = 0.75, Shadow = false, Name = "MirrorLake" })
	Kit.Emitter(folder, CF(520, LAKE_Y + 6, -20), V3(700, 1, 600), Kit.TEX.Smoke, {
		Color = ColorSequence.new(RGB(230, 226, 255)),
		Size = NumberSequence.new(14, 26),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.8), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(14, 20),
		Rate = 8,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(80, 80),
	})

	-- The walkway.
	local control = {
		V3(172, 1, 0),
		V3(212, 1, 0),
		V3(258, 6, 20),
		V3(298, 10, 26),
		V3(342, 10, 22),
		V3(382, 10, -8),
		V3(428, 4, -34),
		V3(478, 4, -22),
		V3(532, 1, -40),
		WorldDefinitions.GatePlaza("Mirror").Position,
	}
	local walk = Kit.Smooth(control, 3)
	Kit.Path(folder, walk, { Width = 14, Thickness = 1.6, Color = WHITE, Material = M.Marble, Edge = { Color = VIOLET, Material = M.Neon } })
	for i = 3, #walk - 2, 2 do
		if walk[i].X > 215 then
			support(folder, walk[i])
		end
	end
	-- low glass rails along the whole walkway
	for i = 1, #walk - 1 do
		local a, b = walk[i], walk[i + 1]
		if a.X > 210 then
			local side = (b - a).Unit:Cross(V3(0, 1, 0))
			for _, s in { -1, 1 } do
				rod(folder, a + side * s * 6.6 + V3(0, 1.4, 0), b + side * s * 6.6 + V3(0, 1.4, 0), 0.3, 2.8, GLASS, M.Glass, { Reflect = 0.4, Transparency = 0.35 })
			end
		end
	end

	-- 1) Plaza of Echoes
	do
		local center = V3(320, 10, 26)
		disc(folder, CF(center - V3(0, 0.8, 0)), 50, 1.6, WHITE, M.Marble)
		Kit.Ring(folder, CF(center + V3(0, 0.05, 0)), 24.4, 0.1, 0.8, 48, VIOLET, M.Neon, glow)
		Kit.Ring(folder, CF(center + V3(0, 0.05, 0)), 12, 0.1, 0.5, 32, CYAN, M.Neon, glow)
		disc(folder, CF(center + V3(0, 0.02, 0)), 20, 0.06, RGB(120, 120, 150), M.Glass, { Reflect = 0.6, NoCollide = true })
		support(folder, center)
		-- mirrored statue pairs; one of each pair is broken
		for k, x in { -14, 0, 14 } do
			statue(folder, center + V3(x, 0, -17), 0, false)
			statue(folder, center + V3(x, 0, 17), 180, k == 2)
		end
		-- two great mirrors behind the statue rows (off the walkway), one shattered
		mirror(folder, CFrame.lookAt(center + V3(-8, 0, -23), center + V3(-8, 0, -40)), 16, 8, false)
		mirror(folder, CFrame.lookAt(center + V3(0, 0, 23), center + V3(0, 0, 40)), 16, 8, true, rng)
		-- the reflection: an upside-down ghost of the plaza hanging beneath it
		local ghost = Kit.Model("PlazaReflection", folder)
		for _, x in { -14, 0, 14 } do
			for _, z in { -17, 17 } do
				Kit.Ellipsoid(ghost, CF(center + V3(x, -9, z)), V3(3.4, 10, 3.4), PALE, M.Glass, { NoCollide = true, Transparency = 0.5 })
				ball(ghost, center + V3(x, -15, z), 2.4, PALE, M.Glass, { NoCollide = true, Transparency = 0.5 })
			end
		end
		-- narrow beam north to a floating island (Cracked Locket)
		local island = V3(332, 14, -46)
		Kit.Path(folder, { center + V3(4, 0, -24), island + V3(0, 0, 10) }, { Width = 3, Thickness = 1, Color = GLASS, Material = M.Glass, Edge = { Color = CYAN, Material = M.Neon } })
		Kit.TBall(island - V3(0, 9, 0), 14, M.Salt)
		Kit.TBall(island - V3(0, 20, 0), 9, M.Glacier)
		disc(folder, CF(island - V3(0, 0.6, 0)), 24, 1.2, WHITE, M.Marble)
		for k = 1, 5 do
			local a = k / 5 * 2 * pi
			local base = island + V3(cos(a) * 9, 0, sin(a) * 9)
			P(folder, CF(base + V3(0, 3, 0)) * ANG(rng:NextNumber(-0.3, 0.3), a, rng:NextNumber(-0.3, 0.3)), V3(1.6, 6, 1.6), CYAN, M.Glass, { Reflect = 0.3, Transparency = 0.2 })
		end
		Kit.Relic(folder, "CrackedLocket", island, region.Color)
	end

	-- 2) Mirror walls at every turn of the zigzag
	for _, i in { 13, 16, 19, 22 } do
		local a, b = walk[i], walk[math.min(#walk, i + 1)]
		local dir = (b - a).Unit
		local side = dir:Cross(V3(0, 1, 0))
		for _, s in { -1, 1 } do
			local base = a + side * s * 9 - V3(0, 0.2, 0)
			mirror(folder, CFrame.lookAt(base, base + side * s), 13, 9, rng:NextNumber() < 0.35, rng)
		end
	end

	-- 3) Reflection Pool (side bridge south)
	do
		local from = V3(453, 4, -20)
		local pool = V3(456, 4, 42)
		Kit.Path(folder, { from, pool + V3(0, 0, -15) }, { Width = 6, Thickness = 1.2, Color = WHITE, Material = M.Marble, Edge = { Color = VIOLET, Material = M.Neon } })
		disc(folder, CF(pool - V3(0, 0.8, 0)), 32, 1.6, WHITE, M.Marble)
		support(folder, pool)
		disc(folder, CF(pool + V3(0, 0.03, 0)), 16, 0.08, RGB(60, 64, 96), M.Glass, { Reflect = 0.85, NoCollide = true })
		Kit.Ring(folder, CF(pool + V3(0, 0.1, 0)), 8.2, 0.12, 0.5, 28, CYAN, M.Neon, glow)
		-- a kneeling figure staring into the pool
		Kit.Ellipsoid(folder, CF(pool + V3(-9.5, 2.4, 0)) * ANG(0, 0, rad(-25)), V3(3, 5, 3), WHITE, M.Marble)
		ball(folder, pool + V3(-7.8, 4.6, 0), 2, WHITE, M.Marble)
		Kit.Relic(folder, "SilverQuill", pool + V3(8, 0, 6), region.Color)
	end

	-- 4) Abandoned Temple (side bridge north, near the end)
	do
		local temple = V3(530, 1, -100)
		Kit.Path(folder, { V3(528, 1, -50), temple + V3(0, 0, 18) }, { Width = 8, Thickness = 1.4, Color = WHITE, Material = M.Marble, Edge = { Color = VIOLET, Material = M.Neon } })
		disc(folder, CF(temple - V3(0, 0.8, 0)), 40, 1.6, WHITE, M.Marble)
		support(folder, temple)
		for k = 0, 9 do
			local a = k / 10 * 2 * pi
			local base = temple + V3(cos(a) * 16, 0, sin(a) * 16)
			if k == 3 or k == 7 then
				-- fallen column
				rod(folder, base + V3(0, 1.2, 0), base + V3(cos(a + 1.2) * 14, 1.2, sin(a + 1.2) * 14), 2.4, 2.4, WHITE, M.Marble)
			else
				local h = (k % 3 == 0) and 9 or 18
				P(folder, CF(base + V3(0, h / 2, 0)), V3(2.4, h, 2.4), WHITE, M.Marble)
				P(folder, CF(base + V3(0, h + 0.4, 0)), V3(3.2, 0.8, 3.2), SILVER, M.Marble)
			end
		end
		P(folder, CF(temple + V3(0, 1.5, 0)), V3(6, 3, 4), SILVER, M.Marble) -- altar
		P(folder, CF(temple + V3(0, 3.1, 0)), V3(5, 0.2, 3), VIOLET, M.Neon, glow)
		mirror(folder, CFrame.lookAt(temple + V3(0, 0, -10), temple + V3(0, 0, 10)), 20, 10, true, rng)
		Kit.Relic(folder, "WardenSigil", temple + V3(0, 3.2, 0), region.Color)
	end

	-- Lanterns along the walkway
	for i = 2, #walk - 1, 3 do
		local a, b = walk[i], walk[i + 1]
		local side = (b - a).Unit:Cross(V3(0, 1, 0))
		local s = (i % 2 == 0) and 1 or -1
		local lantern = ball(folder, a + side * s * 7.4 + V3(0, 6, 0), 1, CYAN, M.Neon, glow)
		Kit.Light(lantern, RGB(200, 220, 255), 1.2, 18)
		cyl(folder, a + side * s * 7.4, a + side * s * 7.4 + V3(0, 5.5, 0), 0.3, SILVER, M.Metal)
	end

	-- Floating shards everywhere near the route
	for _ = 1, 60 do
		local i = rng:NextInteger(1, #walk)
		local off = V3(rng:NextNumber(-60, 60), rng:NextNumber(-10, 50), rng:NextNumber(-60, 60))
		if off.Magnitude > 22 then
			shard(folder, rng, walk[i] + off, rng:NextNumber(1, 3))
		end
	end

	-- Background: giant drifting mirror shards, inverted islands, fractured towers
	for k = 1, 14 do
		local a = rad(-70 + k * 10)
		local dist = rng:NextNumber(700, 1100)
		local pos = V3(cos(a) * dist, rng:NextNumber(20, 160), sin(a) * dist)
		local slab = Kit.Model("GiantShard", folder)
		P(slab, CF(pos) * ANG(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.3), rng:NextNumber(-0.4, 0.4)), V3(6, rng:NextNumber(90, 200), rng:NextNumber(30, 60)), GLASS, M.Glass, { NoCollide = true, Reflect = 0.6, Transparency = 0.1, Shadow = false })
		slab.WorldPivot = CF(pos)
		Kit.Tag(slab, "WSpin", { Speed = rng:NextNumber(0.02, 0.06), Axis = "Y" })
	end
	for k = 1, 7 do
		local a = rad(-50 + k * 14)
		local pos = V3(cos(a) * rng:NextNumber(420, 650), rng:NextNumber(110, 200), sin(a) * rng:NextNumber(420, 650))
		Kit.TBall(pos, rng:NextNumber(22, 34), M.Salt)
		-- inverted spire hanging beneath
		for d = 0, 5 do
			disc(folder, CF(pos - V3(0, 26 + d * 9, 0)), 26 - d * 4.4, 9, WHITE, M.Marble, { NoCollide = true })
		end
		local tip = ball(folder, pos - V3(0, 82, 0), 4, VIOLET, M.Neon, glow)
		Kit.Light(tip, VIOLET, 2, 60)
	end
	for k = 1, 6 do
		local a = rad(-40 + k * 16)
		local base = V3(cos(a) * 900, LAKE_Y, sin(a) * 900)
		local h = rng:NextNumber(160, 280)
		P(folder, CF(base + V3(0, h * 0.35, 0)), V3(30, h * 0.7, 30), WHITE, M.Marble, { NoCollide = true })
		P(folder, CF(base + V3(4, h * 0.85, 2)) * ANG(0.2, 0.3, 0.25), V3(26, h * 0.25, 26), WHITE, M.Marble, { NoCollide = true })
		P(folder, CF(base + V3(0, h * 0.7, 0)), V3(31, 2, 31), VIOLET, M.Neon, glow)
	end

	-- Silver motes drifting up
	Kit.Emitter(folder, CF(420, 0, -10), V3(420, 1, 260), Kit.TEX.Spark, Kit.MotesFX(RGB(230, 226, 255), 30, 0.8, 0.25))
end

return MirrorRoute
