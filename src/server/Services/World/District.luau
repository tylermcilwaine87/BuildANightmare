--[[
	District  (ModuleScript)
	Location: ServerScriptService/Server/Services/World/District

	NIGHTMARE UNDERGROUND — THE FIGHTING DISTRICT (WorldDefinitions.District): the venue for the
	1v1 mode, built just outside the Forge's south-east rim, past the Colosseum. A gap in the
	rim wall opens onto a short plaza; the building's mechanical doors face the hub.

	OUTSIDE  a huge lit sign, two giant holographic Nightmares trading blows on the roof,
	         advertising screens (UGScreen: the client cycles them), statues of two legends
	         and their trophies, fight posters, championship banners, a queue of spectators,
	         chimneys, gears and pistons, spotlights on the facade.
	INSIDE   the lobby:
	           RANKED terminals (prompt UGRankedQueue)   CASUAL terminals (UndergroundQueue)
	           the private duel station (UGPrivateDuel: the client's player list)
	           the fighter stats terminal (UGStats)      the loadout station (OpenWorkshop)
	           the trophy showcase                       the season rewards display
	           the leaderboard (part UGLeaderboard)      the LIVE NOW screens (UGLiveBoard)
	           spectator stands                          heavy bags + dummy spots (UGDummySpot)
	           the practice arena door (UGPractice: to the Training Arena)
	DistrictService fills the boards, spawns the dummies and runs the server-side prompts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local District = {}

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad = math.rad
local M = Enum.Material
local P, ball, cyl, rod, disc = Kit.P, Kit.Ball, Kit.Cyl, Kit.Rod, Kit.Disc
local glow = { NoCollide = true, Shadow = false }

local RED = RGB(255, 50, 60)
local BLUE = RGB(70, 140, 255)
local GOLD = RGB(255, 196, 70)
local STEEL = RGB(40, 38, 46)
local STEEL_DARK = RGB(24, 22, 28)
local RUST = RGB(92, 56, 40)
local HAZARD = RGB(240, 190, 40)

-- The lobby's frame: the floor's centre at y = 1 (the hub floor's top), -Z toward the hub.
local function frame(): CFrame
	local c = WorldDefinitions.District.Center
	local hub = WorldDefinitions.HubCenter
	return CFrame.lookAt(c, V3(hub.X, c.Y, hub.Z))
end
District.Frame = frame

-- Building dimensions (lobby inside the walls).
local HALF_X, HALF_Z, HEIGHT = 52, 48, 36
local DOOR_HALF, DOOR_H = 13, 22
local PLAZA_FROM, PLAZA_TO, PLAZA_HALF = -114, -HALF_Z, 32

local function prompt(parent: Instance, name: string, action: string, object: string, hold: number?, distance: number?)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = distance or 10
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

------------------------------------------------------------------------------------------
-- Little builders
------------------------------------------------------------------------------------------
-- A blocky spectator (or a statue, in stone) standing / sitting at `cf` (cf at the feet).
local SKIN = { RGB(110, 86, 70), RGB(200, 160, 130), RGB(150, 110, 90), RGB(80, 60, 50) }
local SHIRTS = { RGB(150, 30, 40), RGB(30, 30, 36), RGB(60, 60, 70), RGB(40, 60, 120), RGB(200, 200, 205), RGB(110, 40, 120) }
local function spectator(parent: Instance, cf: CFrame, rng: Random, sitting: boolean?, cheering: boolean?)
	local m = Kit.Model("Spectator", parent)
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
	local legs = RGB(30, 28, 34)
	local lift = sitting and -0.9 or 0
	if sitting then
		P(m, cf * CF(-0.5, 1.6, -0.8), V3(0.9, 0.9, 1.8), legs, M.Fabric, glow)
		P(m, cf * CF(0.5, 1.6, -0.8), V3(0.9, 0.9, 1.8), legs, M.Fabric, glow)
	else
		P(m, cf * CF(-0.5, 1.25, 0), V3(0.9, 2.5, 0.9), legs, M.Fabric, glow)
		P(m, cf * CF(0.5, 1.25, 0), V3(0.9, 2.5, 0.9), legs, M.Fabric, glow)
	end
	P(m, cf * CF(0, 3.5 + lift, 0), V3(2, 2.1, 1), shirt, M.Fabric, glow)
	ball(m, (cf * CF(0, 5.1 + lift, 0)).Position, 1.4, skin, M.SmoothPlastic, glow)
	for _, s in { -1, 1 } do
		if cheering then
			P(m, cf * CF(s * 1.3, 5.1 + lift, 0) * ANG(0, 0, rad(-s * 20)), V3(0.7, 2.2, 0.7), shirt, M.Fabric, glow)
		else
			P(m, cf * CF(s * 1.35, 3.4 + lift, 0), V3(0.7, 2, 0.7), shirt, M.Fabric, glow)
		end
	end
	m.WorldPivot = cf
	Kit.Tag(m, cheering and "WBob" or "WSwing", cheering and { Amp = 0.35, Speed = rng:NextNumber(5, 8) } or { Axis = "Z", Angle = 3, Speed = rng:NextNumber(1.5, 3) })
	return m
end

-- A Nightmare fighter in its guard, built in one material (a statue, or a hologram).
-- cf at the feet, facing -Z. Returns the model and its two arm models (to animate).
local function fighter(parent: Instance, cf: CFrame, scale: number, color: Color3, mat, opts, name: string)
	local m = Kit.Model(name, parent)
	local o = opts or {}
	local function part(c: CFrame, size: Vector3, into: Instance?)
		return P(into or m, cf * CF(c.Position * scale) * c.Rotation, size * scale, color, mat, o)
	end
	-- legs: bladed stance, knees bent
	part(CF(-0.9, 1.6, 0.5) * ANG(rad(-12), 0, 0), V3(1.1, 3.3, 1.1))
	part(CF(0.9, 1.6, -0.6) * ANG(rad(14), 0, 0), V3(1.1, 3.3, 1.1))
	-- hips, chest (wide: a heavyweight), head down behind the guard
	part(CF(0, 3.5, 0), V3(2.6, 1, 1.5))
	part(CF(0, 5.2, -0.15) * ANG(rad(-8), 0, 0), V3(3.6, 2.8, 2))
	part(CF(0, 7.15, -0.4), V3(1.5, 1.5, 1.5))
	-- horns / crest: they're Nightmares, not people
	part(CF(-0.55, 8.1, -0.3) * ANG(0, 0, rad(25)), V3(0.3, 1.1, 0.3))
	part(CF(0.55, 8.1, -0.3) * ANG(0, 0, rad(-25)), V3(0.3, 1.1, 0.3))
	local arms = {}
	for _, s in { -1, 1 } do
		local arm = Kit.Model(s < 0 and "ArmL" or "ArmR", m)
		local shoulder = cf * CF(V3(s * 2.2, 6.2, -0.2) * scale)
		part(CF(s * 2.25, 5.4, -0.9) * ANG(rad(60), 0, 0), V3(0.9, 2.4, 0.9), arm) -- upper arm, forward
		part(CF(s * 1.6, 6.3, -2.0) * ANG(rad(-20), 0, rad(s * 15)), V3(0.8, 2.2, 0.8), arm) -- forearm, up
		part(CF(s * 1.3, 7.5, -2.3), V3(1.3, 1.3, 1.3), arm) -- fist by the chin
		arm.WorldPivot = shoulder
		arms[s] = arm
	end
	m.WorldPivot = cf
	return m, arms
end

-- A matchmaking / station terminal: cf at the floor, its screen facing -Z.
local function terminal(parent: Instance, cf: CFrame, color: Color3, title: string, subtitle: string, promptName: string, action: string, object: string)
	local m = Kit.Model("Terminal_" .. promptName, parent)
	local L, C = Kit.Frame(cf)
	P(m, C(0, 0.3, 0), V3(6, 0.6, 4), STEEL_DARK, M.DiamondPlate)
	local body = P(m, C(0, 3.6, 0.3), V3(5, 6, 2.6), STEEL, M.Metal)
	for _, x in { -2.6, 2.6 } do
		P(m, C(x, 3.6, 0.3), V3(0.25, 6.2, 2.8), color, M.Neon, glow)
	end
	P(m, C(0, 6.75, 0.3), V3(5.4, 0.3, 2.9), color, M.Neon, glow)
	Kit.Sign(m, C(0, 4.9, -1.05), V3(4.4, 2, 0.1), title, color, { Color = RGB(10, 8, 12) })
	Kit.Sign(m, C(0, 3.2, -1.05), V3(4.4, 1.1, 0.1), subtitle, RGB(230, 225, 232), { Color = RGB(10, 8, 12), Font = Enum.Font.GothamBold })
	-- the console it's operated from
	P(m, C(0, 1.9, -1.4) * ANG(rad(-35), 0, 0), V3(4.2, 0.3, 1.6), STEEL_DARK, M.Metal)
	P(m, C(0, 2.0, -1.45) * ANG(rad(-35), 0, 0), V3(3.6, 0.1, 1.2), color, M.Neon, { NoCollide = true, Shadow = false, Transparency = 0.3 })
	local light = P(m, C(0, 7.2, 0.3), V3(0.4, 0.4, 0.4), color, M.Neon, glow)
	Kit.Light(light, color, 1.2, 12)
	prompt(body, promptName, action, object, 0.25, 9)
	Kit.Billboard(m, L(0, 9.4, 0.3), title, nil, color, Vector2.new(8, 1.4), 70)
	return m
end

-- A screen for the client to fill (UGScreen): a frame with a dark panel and a SurfaceGui.
local function screen(parent: Instance, cf: CFrame, size: Vector2, color: Color3, name: string, tag: string?)
	local panel = P(parent, cf, V3(size.X, size.Y, 0.5), RGB(8, 6, 10), M.SmoothPlastic, { Name = name })
	local L, C = Kit.Frame(cf)
	for _, x in { -1, 1 } do
		P(parent, C(x * (size.X / 2 + 0.25), 0, 0), V3(0.5, size.Y + 1, 0.8), color, M.Neon, glow)
	end
	for _, y in { -1, 1 } do
		P(parent, C(0, y * (size.Y / 2 + 0.25), 0), V3(size.X + 1, 0.5, 0.8), STEEL, M.Metal)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Parent = panel
	if tag then
		Kit.Tag(panel, tag)
	end
	return panel, gui
end

------------------------------------------------------------------------------------------
-- The ground, the way in from the hub, the shell
------------------------------------------------------------------------------------------
local function buildGround(m, F)
	local L, C = Kit.Frame(F)
	-- rock under it (the mesa ends at the rim), then clear the shoulder above the floor
	-- (terrain snaps to a 4-stud grid: the rock stops well under the floor slabs and the clear
	-- starts below the floor, or the voxels round up into humps through it)
	Workspace.Terrain:FillBlock(C(0, -26, -28), V3(150, 40, 190), M.Basalt)
	Workspace.Terrain:FillBlock(C(0, 43, -32), V3(178, 96, 204), M.Air)

	-- the plaza from the rim gap to the doors, and the lobby floor
	P(m, C(0, 0.03, (PLAZA_FROM + PLAZA_TO) / 2), V3(PLAZA_HALF * 2, 2, PLAZA_TO - PLAZA_FROM), RGB(58, 52, 62), M.Pavement, { Name = "DistrictPlaza" })
	P(m, C(0, -1, 0), V3(HALF_X * 2 + 16, 4, HALF_Z * 2 + 16), STEEL_DARK, M.Concrete, { Name = "DistrictBase" })
	P(m, C(0, 0.05, 0), V3(HALF_X * 2, 2, HALF_Z * 2), RGB(34, 30, 38), M.Slate, { Name = "LobbyFloor" })
	-- the walkway: a red strip down the middle to the doors, steel kerbs, lamps, rope posts
	P(m, C(0, 1.06, (PLAZA_FROM + PLAZA_TO) / 2), V3(6, 0.1, PLAZA_TO - PLAZA_FROM), RGB(120, 20, 26), M.Fabric)
	P(m, C(0, 1.1, (PLAZA_FROM + PLAZA_TO) / 2), V3(0.4, 0.1, PLAZA_TO - PLAZA_FROM), RED, M.Neon, glow)
	for _, x in { -PLAZA_HALF, PLAZA_HALF } do
		P(m, C(x, 1.5, (PLAZA_FROM + PLAZA_TO) / 2), V3(1.4, 1, PLAZA_TO - PLAZA_FROM), STEEL, M.DiamondPlate)
	end
	for z = PLAZA_FROM + 10, PLAZA_TO - 12, 14 do
		for _, x in { -9, 9 } do
			cyl(m, L(x, 1, z), L(x, 4.2, z), 0.5, GOLD, M.Metal)
			ball(m, L(x, 4.5, z), 0.8, GOLD, M.Metal)
		end
		for _, x in { -9, 9 } do
			Kit.Cable(m, L(x, 4.1, z), L(x, 4.1, z + 14), 0.8, 0.3, RGB(140, 20, 30), M.Fabric)
		end
		for _, x in { -PLAZA_HALF + 3, PLAZA_HALF - 3 } do
			Kit.Lamp(m, L(x, 1, z + 7), RGB(255, 120, 120), 11, STEEL_DARK)
		end
	end

	-- the arch over the gap in the rim: you can't miss it from the Colosseum
	local archZ = -(WorldDefinitions.District.Center - WorldDefinitions.HubCenter).Magnitude + WorldDefinitions.HubRadius - 1
	for _, x in { -16, 16 } do
		P(m, C(x, 9, archZ), V3(4, 18, 4), STEEL, M.DiamondPlate)
		P(m, C(x, 9, archZ - 2.1), V3(0.5, 18, 0.3), RED, M.Neon, glow)
	end
	P(m, C(0, 19.5, archZ), V3(38, 3.5, 4), STEEL_DARK, M.Metal)
	Kit.Sign(m, C(0, 19.5, archZ - 2.05), V3(34, 3, 0.1), "NIGHTMARE UNDERGROUND  ·  THE FIGHTING DISTRICT", RED, { Color = RGB(12, 8, 10) })
	-- (and the way there from the Colosseum: a red line in the hub floor to the arch)
	local start = WorldDefinitions.HubCenter + (WorldDefinitions.District.Center - WorldDefinitions.HubCenter).Unit * 156
	rod(m, V3(start.X, 1.12, start.Z), L(0, 1.12, archZ), 1, 0.08, RED, M.Neon, glow)
end

local function buildShell(m, F, rng)
	local L, C = Kit.Frame(F)
	local wallH = HEIGHT
	local y = 1 + wallH / 2
	-- walls: diamond plate on a rusted steel frame
	P(m, C(0, y, HALF_Z + 1), V3(HALF_X * 2 + 4, wallH, 2), STEEL, M.DiamondPlate)
	P(m, C(-HALF_X - 1, y, 0), V3(2, wallH, HALF_Z * 2 + 2), STEEL, M.DiamondPlate)
	P(m, C(HALF_X + 1, y, 0), V3(2, wallH, HALF_Z * 2 + 2), STEEL, M.DiamondPlate)
	local sideW = HALF_X + 2 - DOOR_HALF
	for _, s in { -1, 1 } do
		P(m, C(s * (DOOR_HALF + sideW / 2), y, -HALF_Z - 1), V3(sideW, wallH, 2), STEEL, M.DiamondPlate)
	end
	P(m, C(0, 1 + DOOR_H + (wallH - DOOR_H) / 2, -HALF_Z - 1), V3(DOOR_HALF * 2, wallH - DOOR_H, 2), STEEL, M.DiamondPlate)
	-- (the practice arena's door in the right wall: a recess with a lit frame)
	-- roof and its edge
	P(m, C(0, 1 + wallH + 0.5, 0), V3(HALF_X * 2 + 4, 1, HALF_Z * 2 + 4), STEEL_DARK, M.Metal)
	for _, s in { -1, 1 } do
		P(m, C(0, 1 + wallH + 1.2, s * (HALF_Z + 2)), V3(HALF_X * 2 + 6, 0.5, 0.5), RED, M.Neon, glow)
		P(m, C(s * (HALF_X + 2), 1 + wallH + 1.2, 0), V3(0.5, 0.5, HALF_Z * 2 + 6), RED, M.Neon, glow)
	end
	-- the frame: columns down the facade, rusted bands across it
	for _, x in { -HALF_X - 2, -DOOR_HALF - 2, DOOR_HALF + 2, HALF_X + 2 } do
		P(m, C(x, y + 1, -HALF_Z - 2.6), V3(4, wallH + 2, 3), RUST, M.CorrodedMetal)
		P(m, C(x, y + 1, -HALF_Z - 4.15), V3(0.6, wallH, 0.2), RED, M.Neon, glow)
	end
	for _, band in { 8, 30 } do
		for _, s in { -1, 1 } do
			P(m, C(s * (HALF_X + DOOR_HALF + 2) / 2, band, -HALF_Z - 2.3), V3(HALF_X - DOOR_HALF - 2, 1.4, 1.2), RUST, M.CorrodedMetal)
		end
	end
	-- pipes along the side walls
	for _, s in { -1, 1 } do
		for k, h in { 6, 9, 31 } do
			cyl(m, L(s * (HALF_X + 2.6), h, -HALF_Z), L(s * (HALF_X + 2.6), h, HALF_Z), k == 3 and 1.6 or 1, k == 2 and RUST or STEEL, M.Metal)
		end
		for z = -HALF_Z + 8, HALF_Z - 8, 16 do
			P(m, C(s * (HALF_X + 2.6), 7.5, z), V3(1.2, 5, 1.2), STEEL_DARK, M.Metal)
		end
	end

	-- THE DOORS: two huge slabs, run open on rails, held by hydraulic rams
	local doorW = DOOR_HALF + 1
	for _, s in { -1, 1 } do
		local door = P(m, C(s * (DOOR_HALF + doorW / 2), 1 + DOOR_H / 2, -HALF_Z - 4.6), V3(doorW, DOOR_H, 1.6), RGB(56, 52, 60), M.DiamondPlate)
		door.Name = "Door"
		for k = 0, 4 do
			P(m, C(s * (DOOR_HALF + doorW / 2), 3 + k * 4.4, -HALF_Z - 5.45) * ANG(0, 0, rad(35)), V3(doorW * 0.9, 0.9, 0.1), k % 2 == 0 and HAZARD or STEEL_DARK, M.SmoothPlastic, glow)
		end
		-- the ram: a cylinder from the facade to the door's inner edge
		cyl(m, L(s * (DOOR_HALF + doorW + 3), 12, -HALF_Z - 5.8), L(s * (DOOR_HALF + 1), 12, -HALF_Z - 5.8), 1.2, RGB(150, 150, 160), M.Metal)
		cyl(m, L(s * (DOOR_HALF + doorW + 3), 12, -HALF_Z - 5.8), L(s * (DOOR_HALF + doorW - 2), 12, -HALF_Z - 5.8), 1.8, HAZARD, M.Metal)
	end
	P(m, C(0, 1.2, -HALF_Z - 4.6), V3(DOOR_HALF * 4 + 4, 0.4, 2.2), STEEL_DARK, M.Metal) -- the rail
	-- the light spilling out of the doorway
	local spill = P(m, C(0, DOOR_H - 1, -HALF_Z + 1), V3(DOOR_HALF * 2, 0.4, 0.4), RED, M.Neon, glow)
	Kit.Light(spill, RED, 2, 30, { Kind = "SpotLight", Face = Enum.NormalId.Bottom, Angle = 110 })

	-- THE SIGN over the doors
	Kit.Sign(m, C(0, 30, -HALF_Z - 4.3), V3(HALF_X + 18, 9, 0.6), "NIGHTMARE UNDERGROUND", RED, { Color = RGB(10, 6, 8) })
	Kit.Sign(m, C(0, 24.6, -HALF_Z - 4.3), V3(34, 3.2, 0.5), "THE FIGHTING DISTRICT  ·  1v1  ·  YOU ARE YOUR NIGHTMARE", RGB(240, 230, 235), { Color = RGB(10, 6, 8), Font = Enum.Font.GothamBold })
	for _, yy in { 25.2, 34.8 } do
		local bar = P(m, C(0, yy, -HALF_Z - 4.7), V3(HALF_X + 20, 0.5, 0.5), RED, M.Neon, glow)
		Kit.Tag(bar, "WPulse", { Min = 0, Max = 0.5, Speed = 2 })
	end
	local signLight = P(m, C(0, 36.5, -HALF_Z - 9), V3(0.4, 0.4, 0.4), RED, M.Neon, glow)
	Kit.Light(signLight, RGB(255, 90, 100), 3, 30, { Kind = "SpotLight", Face = Enum.NormalId.Back, Angle = 70 })
	Kit.Billboard(m, L(0, 46, -HALF_Z - 4), "NIGHTMARE UNDERGROUND", "The Fighting District", RED, Vector2.new(34, 7), 600)

	-- advertising screens on the facade (UGScreen: the client cycles what they show)
	for _, s in { -1, 1 } do
		screen(m, C(s * (DOOR_HALF + 19), 18, -HALF_Z - 4.4), Vector2.new(16, 8), s < 0 and RED or BLUE, "AdScreen", "UGScreen")
	end
	-- posters of the legends
	local POSTERS = {
		{ "IRONJAW", "31-0  ·  29 KO\nTHE UNDISPUTED", RED },
		{ "MOTHER MANDIBLE", "BITES FIRST\nASKS NEVER", GOLD },
		{ "KID CHROME", "FASTEST HANDS\nIN THE UNDERGROUND", BLUE },
		{ "THE GRAVE BARON", "NOBODY HAS\nSEEN ROUND 3", RGB(190, 120, 255) },
	}
	for i, poster in POSTERS do
		local x = (i <= 2 and -1 or 1) * (DOOR_HALF + 19.5 + ((i - 1) % 2) * 11.5)
		Kit.Sign(m, C(x, 7.6, -HALF_Z - 3.7), V3(9, 2.4, 0.4), poster[1], poster[3], { Color = RGB(14, 10, 12) })
		Kit.Sign(m, C(x, 4.4, -HALF_Z - 3.7), V3(9, 4, 0.4), poster[2], RGB(235, 230, 235), { Color = RGB(30, 20, 24), Font = Enum.Font.GothamBold })
	end
	-- championship banners hanging down the frame columns
	for i, x in { -HALF_X - 2, -DOOR_HALF - 2, DOOR_HALF + 2, HALF_X + 2 } do
		local banner = Kit.Sign(m, C(x, 19, -HALF_Z - 4.6), V3(3.4, 12, 0.2), i % 2 == 1 and "CHAMPION\nSHIP\nSERIES" or "SEASON\n1", GOLD, { Color = i % 2 == 1 and RGB(110, 14, 20) or RGB(16, 16, 20) })
		banner.CanCollide = false
	end

	-- the roof: chimneys smoking, gears turning, the hologram projectors
	for _, s in { -1, 1 } do
		local base = L(s * (HALF_X - 8), 1 + wallH + 1, HALF_Z - 10)
		cyl(m, base, base + V3(0, 16, 0), 5, RUST, M.CorrodedMetal)
		cyl(m, base + V3(0, 14, 0), base + V3(0, 16.5, 0), 6, STEEL_DARK, M.Metal)
		Kit.Emitter(m, CF(base + V3(0, 17, 0)), V3(3, 0.5, 3), Kit.TEX.Smoke, Kit.SmokeFX(RGB(60, 50, 54), 6, 5))
		-- a gear on each side wall
		local gear = Kit.Model("Gear", m)
		local center = C(s * (HALF_X + 3.6), 22, -HALF_Z + 14) * ANG(0, rad(90), 0)
		disc(gear, center * ANG(rad(90), 0, 0), 12, 1, RUST, M.CorrodedMetal)
		for k = 0, 9 do
			P(gear, center * ANG(0, 0, rad(k * 36)) * CF(0, 6.4, 0), V3(1.6, 1.6, 1), RUST, M.CorrodedMetal)
		end
		disc(gear, center * ANG(rad(90), 0, 0) * CF(0, 0.6, 0), 3, 0.4, HAZARD, M.Metal)
		gear.WorldPivot = center
		Kit.Tag(gear, "WSpin", { Axis = "Z", Speed = s * 0.4 })
	end
	-- spectators queuing outside, and a crowd round the doors
	for k = 0, 9 do
		spectator(m, C(-24 + (k % 2) * 2.2, 1, PLAZA_TO - 8 - k * 3.4) * ANG(0, rad(180 + rng:NextNumber(-15, 15)), 0), rng)
	end
	for k = 0, 7 do
		local x = rng:NextNumber(14, 28) * (k % 2 == 0 and 1 or -1)
		spectator(m, C(x, 1, PLAZA_TO - rng:NextNumber(14, 34)) * ANG(0, rad(rng:NextNumber(150, 210)), 0), rng, false, k % 3 == 0)
	end
	-- spotlights on the facade from the plaza's corners
	for _, s in { -1, 1 } do
		local foot = L(s * (PLAZA_HALF - 4), 1, PLAZA_TO - 26)
		cyl(m, foot, foot + V3(0, 3, 0), 1.2, STEEL_DARK, M.Metal)
		local head = P(m, CFrame.lookAt(foot + V3(0, 3.8, 0), L(0, 24, -HALF_Z)), V3(2.4, 2.4, 3), STEEL, M.Metal)
		local lens = P(m, head.CFrame * CF(0, 0, -1.55), V3(2, 2, 0.1), RGB(255, 240, 230), M.Neon, glow)
		Kit.Light(lens, RGB(255, 225, 220), 4, 60, { Kind = "SpotLight", Face = Enum.NormalId.Front, Angle = 40 })
	end
end

------------------------------------------------------------------------------------------
-- The roof show: two giant holographic Nightmares trading blows, and the legends' statues
------------------------------------------------------------------------------------------
local function buildHolograms(m, F)
	local L, C = Kit.Frame(F)
	local roof = 1 + HEIGHT + 1
	for _, s in { -1, 1 } do
		local color = s < 0 and RED or BLUE
		local spot = C(s * 9, roof + 3, -6) * ANG(0, rad(s * 90), 0)
		disc(m, C(s * 9, roof + 0.5, -6), 10, 1, STEEL_DARK, M.Metal)
		local emitter = disc(m, C(s * 9, roof + 1.1, -6), 7, 0.2, color, M.Neon, glow)
		Kit.Light(emitter, color, 2.5, 40)
		Kit.Emitter(m, C(s * 9, roof + 2, -6), V3(6, 1, 6), Kit.TEX.Spark, Kit.MotesFX(color, 14, 6, 0.4))
		local body, arms = fighter(m, spot, 3, color, M.Neon, { NoCollide = true, Shadow = false, Transparency = 0.55 }, "Hologram")
		Kit.Tag(emitter, "WPulse", { Min = 0, Max = 0.4, Speed = 3 })
		body.Name = "Hologram"
		-- each throws punches: the lead arm fast, the rear arm slower (WSwing on the shoulder)
		Kit.Tag(arms[s], "WSwing", { Axis = "X", Angle = 24, Speed = 3.4 })
		Kit.Tag(arms[-s], "WSwing", { Axis = "X", Angle = 18, Speed = 2.1 })
	end
end

local function buildStatues(m, F)
	local L, C = Kit.Frame(F)
	for _, s in { -1, 1 } do
		local base = C(s * 23, 1, PLAZA_TO - 16) * ANG(0, rad(s * -25), 0)
		local _, BC = Kit.Frame(base)
		P(m, BC(0, 2, 0), V3(10, 4, 10), RGB(52, 48, 56), M.Marble)
		P(m, BC(0, 4.2, 0), V3(11, 0.4, 11), GOLD, M.Metal)
		fighter(m, BC(0, 4.4, 0), 2, RGB(140, 132, 128), M.Marble, nil, "Statue")
		Kit.Sign(m, BC(0, 2, -5.05), V3(8, 2.4, 0.2), s < 0 and "IRONJAW\nFIRST CHAMPION" or "MOTHER MANDIBLE\nNIGHTMARE LEGEND", GOLD, { Color = RGB(30, 26, 22), Font = Enum.Font.GothamBold })
		-- the trophy at its feet, turning
		local trophy = Kit.Model("Trophy", m)
		local foot = BC(5.6, 0, -5.6)
		P(m, foot * CF(0, 1.5, 0), V3(2.4, 3, 2.4), RGB(40, 36, 44), M.Marble)
		cyl(trophy, (foot * CF(0, 3, 0)).Position, (foot * CF(0, 3.6, 0)).Position, 1.8, GOLD, M.Metal)
		cyl(trophy, (foot * CF(0, 3.6, 0)).Position, (foot * CF(0, 4.8, 0)).Position, 0.5, GOLD, M.Metal)
		ball(trophy, (foot * CF(0, 5.6, 0)).Position, 2, GOLD, M.Metal)
		disc(trophy, foot * CF(0, 6.5, 0), 2.4, 0.3, GOLD, M.Metal)
		trophy.WorldPivot = foot * CF(0, 4, 0)
		Kit.Tag(trophy, "WSpin", { Axis = "Y", Speed = 0.6 })
	end
end

------------------------------------------------------------------------------------------
-- The lobby
------------------------------------------------------------------------------------------
local function buildLobby(m, F, rng)
	local L, C = Kit.Frame(F)
	-- floor markings: a ring in the middle, lanes to the wings
	Kit.Ring(m, C(0, 1.1, -4), 16, 0.1, 0.8, 48, RED, M.Neon, glow)
	Kit.Ring(m, C(0, 1.08, -4), 19, 0.08, 0.4, 48, RGB(70, 20, 26), M.Slate, glow)
	-- the ceiling: trusses and lights
	for z = -HALF_Z + 8, HALF_Z - 8, 16 do
		P(m, C(0, HEIGHT - 1.5, z), V3(HALF_X * 2, 1.6, 1.2), STEEL_DARK, M.Metal)
		for x = -HALF_X + 12, HALF_X - 12, 24 do
			local lamp = P(m, C(x, HEIGHT - 3, z), V3(3, 0.6, 3), RGB(255, 235, 225), M.Neon, glow)
			Kit.Light(lamp, RGB(255, 228, 220), 3.2, 44, { Kind = "SpotLight", Face = Enum.NormalId.Bottom, Angle = 120 })
			Kit.Light(lamp, RGB(255, 200, 200), 0.6, 26)
		end
	end
	for x = -HALF_X + 6, HALF_X - 6, 26 do
		P(m, C(x, HEIGHT - 0.8, 0), V3(1.2, 1.2, HALF_Z * 2), STEEL_DARK, M.Metal)
	end
	-- banners from the ceiling
	for i, x in { -30, -10, 10, 30 } do
		local banner = Kit.Sign(m, C(x * 1.35, HEIGHT - 6, HALF_Z - 8), V3(5, 7, 0.2), ({ "RUST", "STEEL", "TITANIUM", "LEGEND" })[i], ({ RGB(190, 110, 70), RGB(190, 195, 205), RGB(150, 210, 255), GOLD })[i], { Color = RGB(20, 14, 18) })
		banner.CanCollide = false
		Kit.Tag(banner, "WSwing", { Axis = "X", Angle = 2, Speed = 0.6 })
	end

	-- THE TROPHY SHOWCASE in the middle: a glass case on a plinth, the belts and cups inside
	P(m, C(0, 2, -4), V3(14, 2, 8), STEEL_DARK, M.Marble)
	P(m, C(0, 3.1, -4), V3(14.4, 0.2, 8.4), GOLD, M.Metal)
	P(m, C(0, 7.1, -4), V3(13.6, 7.8, 7.6), RGB(200, 220, 255), M.Glass, { Transparency = 0.75, Name = "ShowcaseGlass" })
	for i, x in { -4.5, 0, 4.5 } do
		local trophy = Kit.Model("ShowcaseTrophy", m)
		local foot = C(x, 3.2, -4)
		local h = i == 2 and 1.4 or 1
		cyl(trophy, (foot * CF(0, 0, 0)).Position, (foot * CF(0, 0.6, 0)).Position, 1.6 * h, GOLD, M.Metal)
		cyl(trophy, (foot * CF(0, 0.6, 0)).Position, (foot * CF(0, 1.8 * h, 0)).Position, 0.4 * h, GOLD, M.Metal)
		ball(trophy, (foot * CF(0, 2.6 * h, 0)).Position, 1.8 * h, i == 2 and GOLD or RGB(200, 205, 215), M.Metal)
		trophy.WorldPivot = foot * CF(0, 1.5, 0)
		Kit.Tag(trophy, "WSpin", { Axis = "Y", Speed = 0.5 })
	end
	Kit.Sign(m, C(0, 2, -8.05), V3(12, 1.4, 0.1), "CHAMPIONSHIP TROPHIES", GOLD, { Color = RGB(20, 16, 18) })
	local caseLight = P(m, C(0, 11.2, -4), V3(12, 0.3, 6), RGB(255, 240, 210), M.Neon, glow)
	Kit.Light(caseLight, RGB(255, 225, 180), 2, 16, { Kind = "SpotLight", Face = Enum.NormalId.Bottom, Angle = 90 })

	-- THE LIVE NOW SCREENS, hung over the showcase back to back (UGLiveBoard: DistrictService)
	cyl(m, L(-8, HEIGHT - 1, -4), L(-8, 23, -4), 0.3, STEEL_DARK, M.Metal)
	cyl(m, L(8, HEIGHT - 1, -4), L(8, 23, -4), 0.3, STEEL_DARK, M.Metal)
	for _, s in { -1, 1 } do
		screen(m, C(0, 20, -4 + s * 0.3) * ANG(0, s > 0 and rad(180) or 0, 0), Vector2.new(18, 7), RED, "UGLiveBoard")
	end

	-- MATCHMAKING: ranked on the left wall (gold), casual beside them (red)
	for i, z in { -26, -12 } do
		terminal(m, C(-HALF_X + 4, 1, z) * ANG(0, rad(-90), 0), GOLD, "RANKED", i == 1 and "1v1 · best of 3 · the ladder" or "1v1 · best of 3 · the ladder", "UGRankedQueue", "Find a ranked fight", "Nightmare Underground · Ranked")
	end
	for _, z in { 4, 18 } do
		terminal(m, C(-HALF_X + 4, 1, z) * ANG(0, rad(-90), 0), RED, "CASUAL", "1v1 · best of 3 · no ladder", "UndergroundQueue", "Find a fight", "Nightmare Underground · Casual")
	end
	Kit.Sign(m, C(-HALF_X + 0.1, 16, -4) * ANG(0, rad(-90), 0), V3(40, 4, 0.2), "MATCHMAKING  ·  RANKED  ·  CASUAL", RGB(240, 230, 235), { Color = RGB(16, 10, 12) })

	-- the PRIVATE DUEL station and the FIGHTER STATS terminal, by the doors on the left
	terminal(m, C(-34, 1, -HALF_Z + 6) * ANG(0, rad(180), 0), RGB(200, 120, 255), "PRIVATE DUEL", "challenge someone here", "UGPrivateDuel", "Challenge a player", "Nightmare Underground · Private duel")
	terminal(m, C(-20, 1, -HALF_Z + 6) * ANG(0, rad(180), 0), RGB(120, 220, 255), "FIGHTER STATS", "your record and numbers", "UGStats", "View your stats", "Nightmare Underground")

	-- the LOADOUT & INSPECTION station, by the doors on the right: a turntable and the Workshop
	local pad = C(32, 1, -HALF_Z + 10)
	disc(m, pad * CF(0, 0.3, 0), 12, 0.6, STEEL_DARK, M.DiamondPlate)
	Kit.Ring(m, pad * CF(0, 0.65, 0), 6, 0.1, 0.5, 32, GOLD, M.Neon, glow)
	local turntable = disc(m, pad * CF(0, 0.75, 0), 8, 0.2, RGB(60, 56, 64), M.Metal)
	Kit.Tag(turntable, "WSpin", { Axis = "Y", Speed = 0.4 })
	terminal(m, C(42, 1, -HALF_Z + 6) * ANG(0, rad(180), 0), GOLD, "LOADOUT", "inspect and tune your Nightmare", "OpenWorkshop", "Open the Workshop", "Loadout & Inspection")

	-- THE TRAINING CORNER (right): heavy bags on a rack, the dummies (UGDummySpot)
	local rackZ1, rackZ2 = -28, -6
	for _, z in { rackZ1, rackZ2 } do
		P(m, C(HALF_X - 6, 9, z), V3(1.4, 16, 1.4), STEEL, M.Metal)
	end
	P(m, C(HALF_X - 6, 16.7, (rackZ1 + rackZ2) / 2), V3(1.4, 1.4, rackZ2 - rackZ1 + 1.4), STEEL, M.Metal)
	P(m, C(HALF_X - 9, 1.1, (rackZ1 + rackZ2) / 2), V3(14, 0.1, rackZ2 - rackZ1 + 6), RGB(30, 48, 80), M.Fabric)
	for k, z in { -24, -17, -10 } do
		-- (real physics: a bag hangs on a rope and swings when a fighter piles into it)
		local anchor = P(m, C(HALF_X - 6, 15.8, z), V3(0.8, 0.4, 0.8), STEEL_DARK, M.Metal, { Name = "BagHook" })
		local bag = Instance.new("Part")
		bag.Name = "HeavyBag"
		bag.Shape = Enum.PartType.Cylinder
		bag.Size = V3(6, 2.6, 2.6)
		bag.CFrame = C(HALF_X - 6, 9.5, z) * ANG(0, 0, rad(90))
		bag.Color = k == 2 and RGB(140, 24, 30) or RGB(36, 32, 38)
		bag.Material = M.Leather
		bag.CustomPhysicalProperties = PhysicalProperties.new(1.4, 0.6, 0.1, 1, 1)
		bag.Anchored = false
		bag.Parent = m
		local a0 = Instance.new("Attachment")
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Position = V3(3, 0, 0)
		a1.Parent = bag
		local rope = Instance.new("RopeConstraint")
		rope.Attachment0 = a0
		rope.Attachment1 = a1
		rope.Length = 3.4
		rope.Visible = true
		rope.Color = BrickColor.new("Dark stone grey")
		rope.Thickness = 0.15
		rope.Parent = bag
	end
	for _, z in { 8, 20 } do
		local spot = P(m, C(HALF_X - 10, 1.05, z), V3(5, 0.1, 5), RGB(30, 48, 80), M.Fabric, { NoCollide = true, Name = "UGDummySpot" })
		spot:SetAttribute("FacingX", -1)
		Kit.Tag(spot, "UGDummySpot")
	end
	Kit.Sign(m, C(HALF_X - 0.1, 16, -6) * ANG(0, rad(90), 0), V3(36, 4, 0.2), "THE TRAINING CORNER  ·  BAGS · DUMMIES", RGB(240, 230, 235), { Color = RGB(16, 10, 12) })

	-- THE PRACTICE ARENA door, in the right wall at the back
	local door = C(HALF_X - 0.4, 1, 34) * ANG(0, rad(90), 0)
	local _, DC = Kit.Frame(door)
	P(m, DC(0, 7, 0.2), V3(10, 14, 0.6), RGB(10, 30, 50), M.Neon, { NoCollide = true, Shadow = false, Transparency = 0.25, Name = "PracticePortal" })
	for _, x in { -5.6, 5.6 } do
		P(m, DC(x, 7.5, 0), V3(1.2, 15, 1.6), STEEL, M.Metal)
	end
	P(m, DC(0, 15, 0), V3(12.4, 1.2, 1.6), STEEL, M.Metal)
	local practice = P(m, DC(0, 3, -1.4), V3(10, 6, 1), STEEL_DARK, M.Metal, { Transparency = 1, NoCollide = true, Name = "PracticeDoor" })
	prompt(practice, "UGPractice", "Go to the Practice Arena", "Training Arena", 0.4, 10)
	Kit.Sign(m, DC(0, 17, -0.1), V3(14, 2.4, 0.2), "PRACTICE ARENA  →", RGB(120, 200, 255), { Color = RGB(10, 14, 20) })

	-- THE BACK WALL: the leaderboard (UGLeaderboard), the season's rewards, the stands
	screen(m, C(0, 18.5, HALF_Z - 0.4), Vector2.new(30, 12), GOLD, "UGLeaderboard")
	local season = P(m, C(-32, 18, HALF_Z - 0.3), V3(18, 12, 0.4), RGB(12, 8, 12), M.SmoothPlastic, { Name = "SeasonBoard" })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Parent = season
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui
	local LINES = {
		{ "SEASON 1  ·  THE RANKED LEAGUE", GOLD, 0.14 },
		{ "Climb the ladder: the ranks and what each one is worth", RGB(200, 195, 210), 0.07 },
		{ "NIGHTMARE LEGEND  ·  a title, a crown, the Hall's wall", RGB(255, 80, 90), 0.09 },
		{ "MYTHIC  ·  a mythic finisher pose", RGB(220, 120, 255), 0.09 },
		{ "TITANIUM  ·  a titanium ring walk", RGB(150, 210, 255), 0.09 },
		{ "CHROME  ·  a chrome corner banner", RGB(220, 225, 235), 0.09 },
		{ "STEEL  ·  a steel name plate", RGB(170, 175, 185), 0.09 },
		{ "IRON  ·  an iron emblem", RGB(150, 130, 120), 0.09 },
		{ "RUST  ·  where everybody starts", RGB(190, 110, 70), 0.09 },
		{ "Cosmetic only. Nothing you can buy makes you hit harder.", RGB(160, 155, 170), 0.07 },
	}
	for i, line in LINES do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = i
		label.Size = UDim2.fromScale(1, line[3])
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = i == 1 and Enum.Font.GothamBlack or Enum.Font.GothamBold
		label.TextColor3 = line[2]
		label.Text = line[1]
		label.Parent = gui
	end
	for _, x in { -41.5, -22.5 } do
		P(m, C(x, 18, HALF_Z - 0.3), V3(0.5, 13, 0.8), GOLD, M.Neon, glow)
	end
	-- the stands: three tiers along the back on the right, a crowd watching the screens
	for tier = 0, 2 do
		local z = HALF_Z - 4 - tier * 4
		P(m, C(22, 1 + (3 - tier) * 0.8, z), V3(32, 1.6 * (3 - tier), 4), RGB(50, 44, 54), M.Concrete)
		for x = 8, 36, 3.2 do
			if rng:NextNumber() < 0.6 then
				spectator(m, C(x, 1 + (3 - tier) * 1.6, z) * ANG(0, rad(rng:NextNumber(-10, 10)), 0), rng, true, rng:NextNumber() < 0.15)
			end
		end
	end
	Kit.Sign(m, C(22, 9.8, HALF_Z - 0.3), V3(30, 2.4, 0.2), "SPECTATORS  ·  WATCH THE FIGHTS ON THE SCREENS", RGB(240, 230, 235), { Color = RGB(16, 10, 12) })
end

function District.Build(root)
	local m = Kit.Model("FightingDistrict", root)
	local F = frame()
	local rng = Random.new(1717)
	buildGround(m, F)
	buildShell(m, F, rng)
	buildHolograms(m, F)
	buildStatues(m, F)
	buildLobby(m, F, rng)
end

return District
