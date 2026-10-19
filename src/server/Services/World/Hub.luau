--[[
	Hub  (ModuleScript)
	Location: ServerScriptService/Server/Services/World/Hub

	THE NIGHTMARE FORGE: the central hub. A raised mesa with a paved plaza, the Nightmare
	Engine tower in the middle (the Crafting Forge anvil sits at its foot), four themed
	gates (one per boss route), and the facilities in the quarters between them:

	  NW  Nightmare Workshop        NE  Training Arena
	  SW  Hall of Nightmares        SE  Nightmare Colosseum
	      (showcase + leaderboard)

	Glowing conduits in each region's colour run from the Engine to its gate, so the way
	to every boss reads at a glance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local Hub = {}

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local M = Enum.Material
local P, ball, cyl, rod, disc = Kit.P, Kit.Ball, Kit.Cyl, Kit.Rod, Kit.Disc
local glow = { NoCollide = true, Shadow = false }

local STONE = RGB(72, 66, 86)
local STONE_LIGHT = RGB(96, 88, 112)
local IRON = RGB(36, 33, 44)
local VIOLET = RGB(190, 140, 255)

local REGIONS = WorldDefinitions.Regions

-- Gate frame: position on the hub rim, LookVector pointing OUT along the route.
local function gateCF(regionId: string): CFrame
	local dir = REGIONS[regionId].Direction
	local pos = WorldDefinitions.HubCenter + dir * (WorldDefinitions.HubRadius - 4)
	return CFrame.lookAt(pos, pos + dir)
end
Hub.GateCF = gateCF

------------------------------------------------------------------------------------------
-- Ground: mesa, plaza, rim wall
------------------------------------------------------------------------------------------
local function buildGround(root)
	local rng = Random.new(101)
	local c = WorldDefinitions.HubCenter
	local R = WorldDefinitions.HubRadius

	-- The mesa the Forge stands on (terrain), with rocky shoulders between the routes.
	Kit.TCyl(CF(c.X, -46, c.Z), 92, R + 30, M.Basalt)
	Kit.TCyl(CF(c.X, -96, c.Z), 20, R + 10, M.Basalt)
	for i = 0, 3 do
		local a = rad(45 + i * 90)
		local pos = V3(sin(a) * (R + 70), -10, cos(a) * (R + 70))
		Kit.THill(rng, pos, 60, M.Basalt, 4)
		Kit.THill(rng, pos + V3(sin(a) * 60, -20, cos(a) * 60), 55, M.Rock, 3)
	end

	-- Floor layers (top of the base at y = 1).
	disc(root, CF(c.X, 0, c.Z), R * 2, 2, STONE, M.Slate, { Name = "HubFloor" })
	disc(root, CF(c.X, 1.02, c.Z), 300, 0.1, RGB(84, 78, 98), M.Pavement, { Name = "HubOuterRing" })
	disc(root, CF(c.X, 1.04, c.Z), 140, 0.1, RGB(66, 58, 84), M.Marble, { Name = "HubPlaza" })
	Kit.Ring(root, CF(c.X, 1.1, c.Z), 70, 0.12, 1.2, 72, VIOLET, M.Neon, glow)
	Kit.Ring(root, CF(c.X, 1.1, c.Z), 150, 0.12, 0.8, 96, RGB(120, 90, 170), M.Neon, glow)
	for k = 1, 3 do
		Kit.Ring(root, CF(c.X, 1.07, c.Z), 70 + k * 20, 0.08, 0.5, 72, RGB(40, 36, 50), M.Slate, glow)
	end

	-- Rim wall with gaps at the four gates (gates are at 0/90/180/270 degrees here).
	for _, span in { { 9, 81 }, { 99, 171 }, { 189, 261 }, { 279, 351 } } do
		Kit.Ring(root, CF(c.X, 2.5, c.Z), R - 1, 3, 2.4, 22, STONE_LIGHT, M.Slate, nil, span[1], span[2])
		Kit.Ring(root, CF(c.X, 4.1, c.Z), R - 1, 0.25, 2.6, 22, RGB(120, 90, 170), M.Neon, glow, span[1], span[2])
		for a = span[1] + 6, span[2] - 6, 12 do
			local ang = rad(a)
			local pos = V3(c.X - (R - 1) * sin(ang), 1, c.Z - (R - 1) * cos(ang))
			P(root, CF(pos + V3(0, 4, 0)), V3(3.4, 8, 3.4), STONE_LIGHT, M.Slate)
			P(root, CF(pos + V3(0, 8.3, 0)), V3(4.2, 0.6, 4.2), IRON, M.Metal)
			disc(root, CF(pos + V3(0, 9, 0)), 2.6, 1.2, IRON, M.Metal)
			if (a // 12) % 2 == 0 then
				local flame = ball(root, pos + V3(0, 10, 0), 1, RGB(200, 150, 255), M.Neon, glow)
				Kit.Light(flame, RGB(190, 140, 255), 1.2, 16)
				Kit.Emitter(root, CF(pos + V3(0, 9.8, 0)), V3(1.2, 0.2, 1.2), Kit.TEX.Fire, {
					Color = ColorSequence.new(RGB(230, 200, 255), RGB(150, 80, 255)),
					LightEmission = 1,
					Size = NumberSequence.new(1.2, 0.1),
					Transparency = NumberSequence.new(0.2, 1),
					Lifetime = NumberRange.new(0.4, 0.8),
					Rate = 14,
					Speed = NumberRange.new(2, 4),
				})
			end
		end
	end

	-- Lamp posts around the inner plaza (skipping the conduit lines).
	for a = 15, 345, 30 do
		local ang = rad(a)
		Kit.Lamp(root, V3(c.X - 76 * sin(ang), 1, c.Z - 76 * cos(ang)), RGB(220, 190, 255), 10)
	end

	-- Purple embers drifting over the whole hub.
	Kit.Emitter(root, CF(c.X, 3, c.Z), V3(300, 1, 300), Kit.TEX.Spark, Kit.MotesFX(RGB(200, 150, 255), 30, 1.2, 0.22))
end

------------------------------------------------------------------------------------------
-- The Nightmare Engine (central landmark + Crafting Forge)
------------------------------------------------------------------------------------------
local function buildEngine(root)
	local engine = Kit.Model("NightmareEngine", root)
	local c = WorldDefinitions.HubCenter
	local L, C = Kit.Frame(CF(c))

	-- Stepped dais
	disc(engine, C(0, 0.5, 0), 50, 1, STONE_LIGHT, M.Slate)
	disc(engine, C(0, 1.5, 0), 42, 1, STONE, M.Slate)
	disc(engine, C(0, 2.5, 0), 34, 1, RGB(40, 36, 50), M.Marble)
	Kit.Ring(engine, C(0, 3.02, 0), 16.4, 0.08, 0.5, 40, VIOLET, M.Neon, glow)

	-- Core column with four region-coloured light strips
	disc(engine, C(0, 3, 0), 16, 2, IRON, M.DiamondPlate)
	cyl(engine, L(0, 3, 0), L(0, 42, 0), 10, IRON, M.Metal)
	for _, regionId in WorldDefinitions.RouteOrder do
		local d = REGIONS[regionId].Direction
		local color = REGIONS[regionId].Color
		P(engine, CF(L(0, 22, 0) + d * 5.05) * CFrame.lookAt(V3(), d).Rotation, V3(1.2, 38, 0.2), color, M.Neon, glow)
		-- Buttress arm reaching down to the dais, then a pipe that dives under the floor
		local foot = L(0, 3, 0) + d * 17
		rod(engine, foot, L(0, 30, 0) + d * 5, 2.6, 2.6, RGB(46, 42, 56), M.Metal)
		rod(engine, foot + V3(0, 1.5, 0), L(0, 30, 0) + d * 5 + V3(0, 1.5, 0), 0.5, 0.5, color, M.Neon, glow)
		Kit.Curve(engine, L(0, 36, 0) + d * 5, foot + d * 6 + V3(0, 0.5, 0), d * 9 + V3(0, 10, 0), 2.2, 2.2, RGB(60, 56, 70), M.Metal, 10)
	end

	-- The cage and the heart of the Forge
	for i = 0, 7 do
		local a = rad(i * 45)
		local out = V3(sin(a), 0, cos(a))
		Kit.Curve(engine, L(0, 41, 0) + out * 5, L(0, 64, 0) + out * 2, out * 8, 1.2, 0.8, RGB(70, 60, 90), M.Metal, 10)
	end
	local heart = ball(engine, L(0, 52, 0), 9, RGB(215, 175, 255), M.Neon, glow)
	Kit.Tag(heart, "WPulse", { Min = 0, Max = 0.35, Speed = 1.6 })
	Kit.Tag(Kit.Light(heart, RGB(200, 150, 255), 3, 70, { Shadows = true }), "WPulse", { Min = 2, Max = 4, Speed = 1.6 })
	ball(engine, L(0, 52, 0), 11, RGB(160, 120, 220), M.Glass, { NoCollide = true, Transparency = 0.6 })
	for i, spec in { { 10, 0.6, 20 }, { 12.5, -0.45, 60 }, { 15, 0.3, -35 } } do
		local ringModel = Kit.Model("EngineRing" .. i, engine)
		local cf = C(0, 52, 0, spec[3], i * 40, 0)
		Kit.Ring(ringModel, cf, spec[1], 0.5, 0.5, 40, i == 2 and RGB(255, 200, 120) or VIOLET, M.Neon, glow)
		ringModel.WorldPivot = cf
		Kit.Tag(ringModel, "WSpin", { Speed = spec[2], Axis = "Y" })
	end
	-- Spire and beacon
	for k = 0, 4 do
		disc(engine, C(0, 64 + k * 2, 0), 6 - k * 1.1, 2, IRON, M.Metal)
	end
	local beacon = ball(engine, L(0, 76, 0), 2.4, RGB(255, 230, 255), M.Neon, glow)
	Kit.Light(beacon, VIOLET, 2, 40)
	P(engine, C(0, 230, 0), V3(2, 300, 2), RGB(200, 160, 255), M.Neon, { NoCollide = true, Shadow = false, Transparency = 0.7, Name = "SkyBeam" })
	Kit.Emitter(engine, C(0, 52, 0), V3(10, 10, 10), Kit.TEX.Spark, Kit.MotesFX(RGB(220, 180, 255), 25, 3, 0.3))

	-- The Crafting Forge: anvil at the Engine's foot, facing the spawn.
	P(engine, C(0, 4.5, 11.5), V3(4, 3, 3), IRON, M.Metal)
	local anvil = P(engine, C(0, 6.6, 11.5), V3(7, 1.4, 3.6), RGB(46, 46, 56), M.Metal)
	rod(engine, L(-3.5, 6.6, 11.5), L(-6.2, 6.4, 11.5), 1.4, 1, RGB(46, 46, 56), M.Metal)
	disc(engine, C(6.5, 4.5, 10.5), 4, 3, IRON, M.Metal)
	local embers = ball(engine, L(6.5, 6.2, 10.5), 2.4, RGB(255, 120, 40), M.Neon, glow)
	Kit.Light(embers, RGB(255, 140, 60), 2, 22)
	Kit.Emitter(engine, C(6.5, 6.4, 10.5), V3(2, 0.2, 2), Kit.TEX.Fire, Kit.FireFX(20, 1.2))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenForge"
	prompt.ActionText = "Craft & Dismantle"
	prompt.ObjectText = "Crafting Forge"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anvil
	Kit.Sign(engine, CF(L(0, 10.5, 13.6), L(0, 10.5, 30)), V3(9, 1.6, 0.3), "⚒ CRAFTING FORGE", RGB(255, 170, 80))

	Kit.Billboard(root, L(0, 86, 0), "THE NIGHTMARE FORGE", "Four paths. Four Nightmares.", VIOLET, Vector2.new(46, 10), 900)
end

------------------------------------------------------------------------------------------
-- Gates (one per route), each themed after the region beyond it
------------------------------------------------------------------------------------------
local function gateScrap(g, L, C, color)
	local RUST, RUST2 = RGB(118, 64, 38), RGB(86, 50, 34)
	for _, s in { -1, 1 } do
		P(g, C(s * 18, 15, 0), V3(7, 30, 7), RUST, M.CorrodedMetal)
		for y = 4, 26, 6 do
			P(g, C(s * 18, y, 0), V3(7.6, 0.8, 7.6), RUST2, M.DiamondPlate)
		end
		-- smoke stack on each pillar
		cyl(g, L(s * 18, 30, 0), L(s * 18, 40, 0), 4, RGB(50, 46, 44), M.Metal)
		Kit.Emitter(g, C(s * 18, 41, 0), V3(3, 0.4, 3), Kit.TEX.Smoke, Kit.SmokeFX(RGB(70, 62, 58), 5, 3))
		local lamp = ball(g, L(s * 14, 26, -4), 1.6, color, M.Neon, glow)
		Kit.Light(lamp, color, 2, 26)
	end
	P(g, C(0, 31, 0), V3(44, 4, 6), RUST, M.CorrodedMetal)
	for i = -5, 5 do
		P(g, C(i * 4, 28.6, -3.1), V3(2, 0.8, 0.2), i % 2 == 0 and RGB(220, 170, 30) or RGB(25, 25, 25), M.SmoothPlastic, glow)
	end
	-- spinning gear on the lintel
	local gear = Kit.Model("Gear", g)
	local gcf = C(0, 38, 0, 90, 0, 0)
	disc(gear, gcf, 10, 1.2, RUST2, M.CorrodedMetal)
	disc(gear, gcf, 3, 1.6, RGB(40, 40, 44), M.Metal)
	for k = 0, 11 do
		P(gear, gcf * ANG(0, rad(k * 30), 0) * CF(0, 0, -5.4), V3(1.6, 1.2, 1.6), RUST2, M.CorrodedMetal)
	end
	gear.WorldPivot = gcf
	Kit.Tag(gear, "WSpin", { Speed = 0.6, Axis = "Y" })
	-- hanging chains
	for _, x in { -9, 9 } do
		Kit.Cable(g, L(x, 29, -2), L(x * 0.6, 18, -2), 0.5, 0.5, RGB(60, 56, 54), M.Metal, 6)
	end
end

local function gateMirror(g, L, C, color)
	local SILVER, GLASS = RGB(210, 214, 230), RGB(180, 200, 240)
	for _, s in { -1, 1 } do
		P(g, C(s * 18, 15, 0), V3(5, 30, 5), SILVER, M.Marble)
		P(g, C(s * 18, 15, 0), V3(5.6, 26, 1.2), GLASS, M.Glass, { Reflect = 0.5, Transparency = 0.2 })
		P(g, C(s * 18, 30.6, 0), V3(7, 1.2, 7), color, M.Neon, glow)
	end
	-- pointed glass arch
	Kit.Ring(g, C(0, 30, 0, 90, 0, 0), 18, 1.4, 1.4, 20, SILVER, M.Marble, nil, -90, 90)
	Kit.Ring(g, C(0, 30, 0, 90, 0, 0), 16.6, 0.3, 0.3, 20, color, M.Neon, glow, -90, 90)
	-- floating shards above the gate
	local rng = Random.new(7)
	for i = 1, 7 do
		local shard = P(g, C(rng:NextNumber(-20, 20), rng:NextNumber(40, 54), rng:NextNumber(-6, 6), rng:NextNumber(-30, 30), rng:NextNumber(0, 180), rng:NextNumber(-30, 30)), V3(1.2, rng:NextNumber(4, 9), rng:NextNumber(2, 4)), GLASS, M.Glass, { NoCollide = true, Reflect = 0.6, Transparency = 0.15 })
		Kit.Tag(shard, "WBob", { Amp = 1.2, Speed = 0.5 + i * 0.07 })
	end
end

local function gateStorm(g, L, C, color)
	local BASALT = RGB(46, 48, 58)
	for _, s in { -1, 1 } do
		P(g, C(s * 18, 16, 0, 0, 0, s * -4), V3(8, 32, 8), BASALT, M.Basalt)
		P(g, C(s * 18, 33, 0, 20, 30, s * 15), V3(5, 6, 5), BASALT, M.Basalt)
		-- torn banner
		P(g, C(s * 18, 20, -4.2), V3(4.4, 12, 0.2), RGB(40, 60, 100), M.Fabric)
		P(g, C(s * 18 + 1, 13.3, -4.2, 0, 0, 20), V3(2, 2.4, 0.2), RGB(40, 60, 100), M.Fabric)
	end
	P(g, C(0, 31, 0), V3(44, 5, 8), BASALT, M.Basalt)
	-- storm crystal crackling on top
	local crystal = P(g, C(0, 38, 0, 0, 45, 0), V3(3, 9, 3), color, M.Neon, glow)
	Kit.Tag(crystal, "WSpin", { Speed = 0.8, Axis = "Y" })
	Kit.Tag(Kit.Light(crystal, color, 3, 40), "WFlicker", { Min = 1, Max = 4, Speed = 6 })
	Kit.Emitter(g, C(0, 38, 0), V3(3, 8, 3), Kit.TEX.Spark, Kit.SparkFX(RGB(200, 240, 255), 25))
	-- lightning rods
	for _, s in { -1, 1 } do
		cyl(g, L(s * 18, 32, 0), L(s * 18, 44, 0), 0.6, RGB(120, 120, 130), M.Metal)
		ball(g, L(s * 18, 44.5, 0), 1.2, color, M.Neon, glow)
	end
end

local function gateAbyss(g, L, C, color)
	local MOSS, STONEC, BONE = RGB(48, 66, 58), RGB(56, 62, 66), RGB(196, 190, 170)
	for _, s in { -1, 1 } do
		P(g, C(s * 18, 14, 0), V3(7, 28, 7), STONEC, M.Cobblestone)
		P(g, C(s * 18, 6, 0), V3(7.4, 12, 7.4), MOSS, M.Grass, { NoCollide = true })
		-- tentacle wrapping the pillar
		local pts = {}
		for i = 0, 16 do
			local t = i / 16
			local a = t * pi * 3 + (s > 0 and 0 or pi)
			pts[#pts + 1] = L(s * 18 + cos(a) * 4.2, 1 + t * 30, sin(a) * 4.2)
		end
		Kit.Tube(g, pts, 1.8, 0.4, RGB(40, 70, 70), M.SmoothPlastic, { NoCollide = true })
	end
	-- a great ribcage arch
	for k = -2, 2 do
		Kit.Curve(g, L(-18, 26, k * 3), L(18, 26, k * 3), V3(0, 12 - math.abs(k) * 2, 0), 2.2, 2.2, BONE, M.Limestone, 10, { NoCollide = true })
	end
	local eye = ball(g, L(0, 36, 0), 3, color, M.Neon, glow)
	Kit.Tag(eye, "WPulse", { Min = 0, Max = 0.5, Speed = 0.8 })
	Kit.Light(eye, color, 2, 34)
	Kit.Emitter(g, C(0, 30, 0), V3(36, 2, 6), Kit.TEX.Spark, Kit.MotesFX(color, 12, -0.6, 0.25))
end

local GATE_BUILDERS = { Scrap = gateScrap, Mirror = gateMirror, Storm = gateStorm, Abyss = gateAbyss }

local function buildGates(root)
	for _, regionId in WorldDefinitions.RouteOrder do
		local region = REGIONS[regionId]
		local cf = gateCF(regionId)
		local L, C = Kit.Frame(cf)
		local g = Kit.Model("Gate_" .. regionId, root)
		GATE_BUILDERS[regionId](g, L, C, region.Color)

		-- Inlaid conduit from the Engine to the gate, in the region colour.
		local inner = WorldDefinitions.HubCenter + region.Direction * 26
		local outer = cf.Position
		rod(root, inner + V3(0, 1.05, 0), outer + V3(0, 1.05, 0), 5, 0.1, RGB(30, 28, 38), M.Slate, glow)
		rod(root, inner + V3(0, 1.12, 0), outer + V3(0, 1.12, 0), 1.2, 0.1, region.Color, M.Neon, glow)

		-- Sign facing the hub, with the boss's name.
		local def = region.Name .. "  ·  " .. (region.ArenaName or "")
		Kit.Sign(g, C(0, 24, 3.6) * ANG(0, pi, 0), V3(30, 4, 0.5), def, region.Color, { Color = RGB(18, 14, 22) })
		Kit.Billboard(g, L(0, 50, 0), region.Name, region.Subtitle, region.Color, Vector2.new(30, 7), 500)

		-- Waystone (fast travel to the boss gate once you've beaten that boss).
		Kit.Waystone(g, C(-26, 0, 14, 0, 180, 0), regionId, region.Color, "Travel", "Waystone · " .. (region.ArenaName or regionId))
		Kit.Sign(g, C(-26, 12.5, 14) * ANG(0, pi, 0), V3(10, 1.4, 0.3), "Unlocks when its boss is beaten", RGB(220, 220, 230))
	end
end

------------------------------------------------------------------------------------------
-- Facilities
------------------------------------------------------------------------------------------
local function facingHub(pos: Vector3): CFrame
	local c = WorldDefinitions.HubCenter
	return CFrame.lookAt(pos, V3(c.X, pos.Y, c.Z))
end

local function buildWorkshop(root)
	local center = Config.World.WorkshopCenter
	local w = Kit.Model("NightmareWorkshop", root)
	local L, C = Kit.Frame(facingHub(center))
	local WOOD, BLUE = RGB(92, 66, 46), RGB(110, 210, 255)

	disc(w, C(0, 0.1, 0), 44, 0.4, RGB(70, 54, 44), M.WoodPlanks)
	Kit.Ring(w, C(0, 0.35, 0), 21.5, 0.1, 0.6, 40, BLUE, M.Neon, glow)
	-- open pavilion: posts and a slanted roof, open towards the hub
	for _, p in { { -16, 6 }, { 16, 6 }, { -16, 16 }, { 16, 16 }, { 0, 18 } } do
		P(w, C(p[1], 7, p[2]), V3(1.6, 14, 1.6), WOOD, M.Wood)
	end
	P(w, C(0, 14.5, 11, -12, 0, 0), V3(38, 1, 18), RGB(60, 54, 62), M.Slate)
	P(w, C(0, 7, 18.6), V3(34, 14, 1), RGB(60, 48, 40), M.WoodPlanks)
	-- tool wall
	for i = -3, 3 do
		rod(w, L(i * 3.5, 6, 18), L(i * 3.5 + 0.6, 10, 18), 0.4, 0.4, RGB(140, 140, 150), M.Metal)
	end
	-- the bench
	local bench = P(w, C(0, 2.2, 8), V3(10, 3, 4.5), WOOD, M.WoodPlanks)
	P(w, C(0, 3.8, 8), V3(9, 0.2, 3.8), BLUE, M.Neon, glow)
	Kit.Light(bench, BLUE, 1.6, 18)
	for _, s in { -1, 1 } do
		local hanging = ball(w, L(s * 6, 11, 8), 0.9, RGB(255, 220, 160), M.Neon, glow)
		Kit.Light(hanging, RGB(255, 210, 150), 1.2, 16)
		Kit.Cable(w, L(s * 6, 14, 8), L(s * 6, 11.4, 8), 0, 0.1, RGB(30, 30, 30), M.Metal, 2)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenWorkshop"
	prompt.ActionText = "Open Workshop"
	prompt.ObjectText = "Nightmare Workshop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = bench
	-- display stands
	for i = -1, 1 do
		disc(w, C(i * 10, 0.8, 13), 5, 1.2, RGB(60, 52, 80), M.Marble)
		ball(w, L(i * 10, 1.6, 13), 1, BLUE, M.Neon, glow)
	end
	-- crates and parts lying around
	local rng = Random.new(31)
	for _ = 1, 8 do
		local s = rng:NextNumber(1.5, 3)
		P(w, C(rng:NextNumber(-20, 20), s / 2 + 0.3, rng:NextNumber(-4, 16), 0, rng:NextNumber(0, 90), 0), V3(s, s, s), RGB(110, 84, 58), M.WoodPlanks)
	end
	Kit.Sign(w, C(0, 17.5, 2), V3(24, 3.4, 0.5), "NIGHTMARE WORKSHOP", BLUE)
end

local function buildTraining(root)
	local c = Config.World.ArenaCenter
	local s = Config.World.ArenaSize
	local half = s / 2
	local t = Kit.Model("TrainingArena", root)
	local RED = RGB(255, 90, 90)
	P(t, CF(c + V3(0, 0.2, 0)), V3(s, 0.4, s), RGB(52, 44, 58), M.Concrete)
	Kit.Ring(t, CF(c + V3(0, 0.45, 0)), 14, 0.08, 0.6, 32, RED, M.Neon, glow)
	local wallH = 4
	local function wall(size, offset)
		P(t, CF(c + offset + V3(0, wallH / 2, 0)), size, RGB(60, 50, 70), M.Brick)
		P(t, CF(c + offset + V3(0, wallH + 0.15, 0)), V3(size.X, 0.3, size.Z), RED, M.Neon, glow)
	end
	local seg = (s - 16) / 2
	wall(V3(s, wallH, 2), V3(0, 0, -half)) -- north
	wall(V3(2, wallH, s), V3(half, 0, 0)) -- east
	-- west and south walls have 16-stud openings towards the hub
	wall(V3(2, wallH, seg), V3(-half, 0, -(8 + seg / 2)))
	wall(V3(2, wallH, seg), V3(-half, 0, 8 + seg / 2))
	wall(V3(seg, wallH, 2), V3(-(8 + seg / 2), 0, half))
	wall(V3(seg, wallH, 2), V3(8 + seg / 2, 0, half))
	-- target posts and floodlights
	for _, corner in { V3(-1, 0, -1), V3(1, 0, -1), V3(1, 0, 1) } do
		local pos = c + corner * (half - 4)
		cyl(t, pos, pos + V3(0, 16, 0), 0.8, IRON, M.Metal)
		local lamp = P(t, CF(pos + V3(0, 16.5, 0)), V3(2.4, 1, 2.4), RGB(255, 220, 160), M.Neon, glow)
		Kit.Light(lamp, RGB(255, 220, 170), 2.5, 50, { Kind = "SpotLight", Face = Enum.NormalId.Bottom, Angle = 80 })
	end
	Kit.Sign(t, CFrame.lookAt(c + V3(-half - 2, 9, half + 2), c + V3(-half - 30, 9, half + 30)), V3(20, 3.6, 0.5), "TRAINING ARENA", RED)
end

local function buildHall(root)
	local show = Config.Showcase
	local first = show.FirstPedestal
	local length = (show.Slots - 1) * show.Spacing
	local h = Kit.Model("HallOfNightmares", root)
	local GOLD = RGB(230, 180, 70)
	-- a dark red carpet under the pedestal row, flanked by pillars
	P(h, CF(first + V3(length / 2, 0.08, 0)), V3(length + 16, 0.12, 14), RGB(70, 16, 20), M.Fabric, glow)
	for i = 0, show.Slots do
		local x = first.X - show.Spacing / 2 + i * show.Spacing
		for _, z in { first.Z - 8.5, first.Z + 8.5 } do
			local pos = V3(x, 1, z)
			P(h, CF(pos + V3(0, 6, 0)), V3(2, 12, 2), RGB(60, 56, 64), M.Marble)
			P(h, CF(pos + V3(0, 12.3, 0)), V3(2.8, 0.6, 2.8), GOLD, M.Metal)
		end
	end
	-- statues of fallen champions (abstract)
	for _, x in { first.X - 14, first.X + length + 14 } do
		local base = V3(x, 1, first.Z)
		P(h, CF(base + V3(0, 1.5, 0)), V3(6, 3, 6), RGB(60, 56, 64), M.Marble)
		P(h, CF(base + V3(0, 7, 0)), V3(3, 8, 2), RGB(150, 140, 120), M.Marble)
		ball(h, base + V3(0, 12.4, 0), 2.6, RGB(150, 140, 120), M.Marble)
		rod(h, base + V3(0, 9.5, 0), base + V3(2.6, 15, 0), 0.6, 0.6, GOLD, M.Metal)
	end
end

local function buildColosseum(root)
	local c = Config.World.ColosseumCenter
	local col = Kit.Model("NightmareColosseum", root)
	local trim, stone = RGB(255, 70, 90), RGB(85, 70, 95)
	disc(col, CF(c + V3(0, 0.1, 0)), 46, 0.4, RGB(60, 48, 66), M.Marble)
	Kit.Ring(col, CF(c + V3(0, 0.35, 0)), 22.5, 0.1, 0.8, 40, trim, M.Neon, glow)
	local toHub = math.deg(math.atan2(-c.Z, -c.X))
	for i = 0, 11 do
		local deg = i * 30 + 15
		local diff = math.abs(((deg - toHub) + 180) % 360 - 180)
		if diff > 25 then
			local a = rad(deg)
			local pos = c + V3(cos(a) * 21, 8, sin(a) * 21)
			P(col, CF(pos), V3(2.8, 16, 2.8), stone, M.Marble)
			P(col, CF(pos + V3(0, 8.5, 0)), V3(3.8, 1, 3.8), trim, M.Neon, glow)
		end
	end
	local podium = P(col, CF(c + V3(0, 2.2, 0)), V3(6, 3, 6), RGB(40, 32, 48), M.Slate)
	P(col, CF(c + V3(0, 3.8, 0)), V3(5, 0.2, 5), trim, M.Neon, glow)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenColosseum"
	prompt.ActionText = "Open Colosseum"
	prompt.ObjectText = "Nightmare Duels"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = podium
	Kit.Billboard(col, c + V3(0, 24, 0), "THE NIGHTMARE COLOSSEUM", "Duels · Ranked · Team fights", trim, Vector2.new(26, 6), 300)
end

function Hub.Build(root)
	buildGround(root)
	buildEngine(root)
	buildGates(root)
	buildWorkshop(root)
	buildTraining(root)
	buildHall(root)
	buildColosseum(root)

	-- Spawn: south of the Engine, looking at it.
	local spawnPos = WorldDefinitions.HubSpawn - V3(0, 3.4, 0)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ForgeSpawn"
	spawn.Size = V3(10, 1, 10)
	spawn.CFrame = CFrame.lookAt(spawnPos, V3(0, spawnPos.Y, 0))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = RGB(90, 60, 140)
	spawn.Material = M.Neon
	spawn.Transparency = 0.5
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root

	-- Relic: tucked behind the Workshop.
	Kit.Relic(root, "ForgeEmber", V3(-128, 1, -112), RGB(255, 170, 90))

	-- Tone the hub's neon down (WorldDefinitions.HubNeonDim): a glow, not a glare. The hub
	-- is built first, so everything in `root` right now is hub.
	Hub.Dim(root)
end

function Hub.Dim(container: Instance)
	local dim = WorldDefinitions.HubNeonDim
	local scale = WorldDefinitions.HubLightScale
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") and d.Material == M.Neon then
			d.Color = d.Color:Lerp(Color3.new(0, 0, 0), dim)
		elseif d:IsA("Light") then
			d.Brightness *= scale
			-- pulsing / flickering lights get their brightness from Min/Max on the client
			for _, key in { "Min", "Max" } do
				local v = d:GetAttribute(key)
				if type(v) == "number" then
					d:SetAttribute(key, v * scale)
				end
			end
		end
	end
end

return Hub
