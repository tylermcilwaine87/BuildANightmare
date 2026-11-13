--[[
	UndergroundArenas  (ModuleScript)
	Location: ServerScriptService/Server/Services/World/UndergroundArenas

	NIGHTMARE UNDERGROUND's themed arenas (Config.Underground.Arenas), picked at random for each
	fight by UndergroundService. EVERY arena has the SAME ring: the same 48 x 48 canvas, ropes /
	cage line, invisible walls, corners, starting spots and Handler booths (ring()), so a fight is
	fair wherever it happens. Only what's around the ring changes:

	  ColossusDome      the championship stadium: a seating bowl packed to the roof, a jumbotron
	                    and scoreboard over the ring, moving spotlights, smoke, banners, two
	                    fighter tunnels, LED boards round the floor, a turning championship display
	  UndergroundPit    the secret fight club: a cramped concrete room, a steel cage, the crowd
	                    pressed against it, rusty beams, exposed cables, flickering neon, graffiti,
	                    old fans, hanging chains, haze, posters of old champions
	  IronworksFurnace  a dead factory: furnaces roaring, molten metal behind the rails, a jib
	                    crane swinging, conveyors running, welding sparks, giant fans, hydraulic
	                    rams, steel floors

	Build(themeId, origin, seed) -> { Model, Theme, Center, Starts, Booths, Screens }
	  Screens: SurfaceGui-carrying parts named "UGBoard" (UndergroundService writes the fight on
	  them: names, round, clock, score, health).
	Moving set pieces use WorldController's tags (WSpin, WSwing, WBob, WConveyor, WPulse,
	WFlicker); advertising boards use DistrictController's UGScreen.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local Arenas = {}

local UG = Config.Underground
local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local M = Enum.Material
local P, ball, cyl, rod, disc = Kit.P, Kit.Ball, Kit.Cyl, Kit.Rod, Kit.Disc
local glow = { NoCollide = true, Shadow = false }

local CORNER_COLORS = { RGB(255, 60, 70), RGB(70, 140, 255) } -- side 1 red, side 2 blue
local APRON = 3 -- the ring floor's height above the venue floor

------------------------------------------------------------------------------------------
-- The ring (identical in every arena)
------------------------------------------------------------------------------------------
-- style: Canvas, Apron, Rope (colours), Cage (true: a steel cage instead of ropes)
local function ring(a: Instance, c: Vector3, style)
	local half = UG.RingHalf
	local floorY = c.Y + APRON
	P(a, CF(c + V3(0, APRON / 2, 0)), V3(half * 2 + 8, APRON, half * 2 + 8), style.Apron, M.Metal, { Name = "Apron" })
	P(a, CF(c + V3(0, APRON + 0.1, 0)), V3(half * 2 + 6, 0.2, half * 2 + 6), style.Canvas, style.CanvasMaterial or M.Fabric, { Name = "Canvas" })
	Kit.Ring(a, CF(c + V3(0, APRON + 0.22, 0)), 8, 0.05, 0.6, 40, style.Rope, M.Neon, glow)
	Kit.Ring(a, CF(c + V3(0, APRON + 0.22, 0)), half - 1.5, 0.05, 0.3, 64, style.Line or RGB(90, 30, 36), M.SmoothPlastic, glow)

	local corners = { V3(-half, 0, half), V3(half, 0, -half), V3(half, 0, half), V3(-half, 0, -half) }
	local postColors = { CORNER_COLORS[1], CORNER_COLORS[2], RGB(210, 210, 220), RGB(210, 210, 220) }
	for i, corner in corners do
		local base = c + corner + V3(0, APRON, 0)
		local height = style.Cage and 15 or 7
		cyl(a, base, base + V3(0, height, 0), style.Cage and 1.4 or 1.2, style.Cage and RGB(70, 66, 62) or postColors[i], M.Metal)
		cyl(a, base + V3(0, height - 0.4, 0), base + V3(0, height + 0.4, 0), 1.8, postColors[i], M.Neon, glow)
	end
	local around = { corners[1], corners[3], corners[2], corners[4] }
	for i = 1, 4 do
		local from, to = around[i], around[i % 4 + 1]
		if style.Cage then
			-- a steel cage: rails every 2 studs up, uprights every 4 along (see-through for the camera)
			for height = 1, 14, 2.6 do
				cyl(a, c + from + V3(0, APRON + height, 0), c + to + V3(0, APRON + height, 0), 0.22, RGB(96, 92, 86), M.Metal, glow)
			end
			local steps = 12
			for k = 1, steps - 1 do
				local p = c + from:Lerp(to, k / steps)
				cyl(a, p + V3(0, APRON, 0), p + V3(0, APRON + 14.5, 0), 0.3, RGB(80, 76, 70), M.Metal, glow)
			end
		else
			for _, height in { 2.2, 4, 5.8 } do
				cyl(a, c + from + V3(0, APRON + height, 0), c + to + V3(0, APRON + height, 0), 0.35, style.Rope, M.SmoothPlastic, glow)
			end
		end
		-- the fight's boundary: an invisible wall the fighters can't get through or over (the same
		-- in every arena, cage or ropes)
		local mid = c + (from + to) / 2 + V3(0, APRON + 8, 0)
		local along = to - from
		local size = math.abs(along.X) > 0.1 and V3(math.abs(along.X) + 2, 16, 1) or V3(1, 16, math.abs(along.Z) + 2)
		P(a, CF(mid), size, Color3.new(), M.SmoothPlastic, { Transparency = 1, Shadow = false, Name = "RingWall" })
	end

	-- the Handlers' corner booths, outside the red and blue corners
	local booths = {}
	for side = 1, 2 do
		local corner = corners[side]
		local out = V3(math.sign(corner.X), 0, math.sign(corner.Z))
		local spot = c + corner + out * 7
		P(a, CF(spot + V3(0, APRON / 2, 0)), V3(7, APRON, 7), RGB(30, 28, 34), M.Metal, { Name = "Booth" })
		P(a, CF(spot + V3(0, APRON + 0.1, 0)), V3(6.4, 0.2, 6.4), CORNER_COLORS[side], M.Neon, glow)
		for _, edge in { V3(3.3, 0, 0), V3(-3.3, 0, 0), V3(0, 0, 3.3), V3(0, 0, -3.3) } do
			local size = edge.X ~= 0 and V3(0.3, 3, 7) or V3(7, 3, 0.3)
			P(a, CF(spot + edge + V3(0, APRON + 1.5, 0)), size, RGB(70, 68, 76), M.Metal, { Name = "BoothRail" })
		end
		local stand = spot + V3(0, APRON + 3.2, 0)
		booths[side] = CFrame.lookAt(stand, V3(c.X, stand.Y, c.Z))
	end
	-- the fighters' corners (facing the middle)
	local starts = {}
	for side = 1, 2 do
		local corner = corners[side]
		local spot = c + V3(math.sign(corner.X) * UG.CornerInset, APRON, math.sign(corner.Z) * UG.CornerInset)
		starts[side] = CFrame.lookAt(spot, V3(c.X, spot.Y, c.Z))
	end
	return { Center = V3(c.X, floorY, c.Z), Starts = starts, Booths = booths, Corners = corners, Around = around, FloorY = floorY }
end

-- A board the fight is written on (UndergroundService fills "UGBoard" SurfaceGuis).
local function board(a: Instance, cf: CFrame, size: Vector2, frameColor: Color3)
	local panel = P(a, cf, V3(size.X, size.Y, 0.6), RGB(6, 5, 8), M.SmoothPlastic, { Name = "UGBoard" })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 0
	gui.Parent = panel
	local _, C = Kit.Frame(cf)
	for _, x in { -1, 1 } do
		P(a, C(x * (size.X / 2 + 0.3), 0, 0), V3(0.6, size.Y + 1.2, 1), frameColor, M.Neon, glow)
	end
	return panel
end

-- An advertising board the client cycles (UGScreen, DistrictController).
local function ad(a: Instance, cf: CFrame, size: Vector2, color: Color3)
	local panel = P(a, cf, V3(size.X, size.Y, 0.5), RGB(8, 6, 10), M.SmoothPlastic, { Name = "AdScreen" })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = panel
	Kit.Tag(panel, "UGScreen")
	local _, C = Kit.Frame(cf)
	P(a, C(0, -size.Y / 2 - 0.2, 0), V3(size.X + 0.4, 0.4, 0.7), color, M.Neon, glow)
	return panel
end

-- A blocky fan: standing (or sitting) at `cf` (feet), facing -Z. Into `into`.
local SHIRTS = { RGB(150, 30, 40), RGB(30, 30, 36), RGB(60, 60, 70), RGB(40, 60, 120), RGB(200, 200, 205), RGB(110, 40, 120), RGB(200, 160, 40) }
local function fan(into: Instance, cf: CFrame, rng: Random, armsUp: boolean?)
	local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
	P(into, cf * CF(0, 1.3, 0), V3(1.8, 2.6, 1.1), shirt, M.SmoothPlastic, { NoCollide = true, Shadow = false, Name = "Fan" })
	ball(into, (cf * CF(0, 3.2, 0)).Position, 1.3, RGB(rng:NextInteger(90, 200), rng:NextInteger(70, 150), rng:NextInteger(60, 120)), M.SmoothPlastic, { NoCollide = true, Shadow = false })
	if armsUp then
		P(into, cf * CF(-1.1, 3.6, 0) * ANG(0, 0, rad(20)), V3(0.5, 1.8, 0.5), shirt, M.SmoothPlastic, { NoCollide = true, Shadow = false })
		P(into, cf * CF(1.1, 3.6, 0) * ANG(0, 0, rad(-20)), V3(0.5, 1.8, 0.5), shirt, M.SmoothPlastic, { NoCollide = true, Shadow = false })
	end
end

------------------------------------------------------------------------------------------
-- 1. THE COLOSSUS DOME
------------------------------------------------------------------------------------------
local function colossusDome(a: Model, c: Vector3, rng: Random)
	local core = ring(a, c, { Canvas = RGB(30, 34, 60), Apron = RGB(20, 22, 34), Rope = RGB(230, 200, 90), Line = RGB(200, 170, 70) })
	local GOLD = RGB(255, 200, 70)
	local SEAT = RGB(34, 32, 44)
	local OUTER = 150
	-- the arena floor and the barrier round it (LED advertising boards on it)
	disc(a, CF(c + V3(0, -1, 0)), 120, 2, RGB(22, 22, 30), M.Concrete, { Name = "DomeFloor" })
	disc(a, CF(c + V3(0, -2, 0)), OUTER * 2 + 10, 2, RGB(18, 18, 24), M.Concrete)
	Kit.Ring(a, CF(c + V3(0, 0.08, 0)), 40, 0.1, 1.2, 64, RGB(90, 70, 160), M.Neon, glow)
	Kit.Ring(a, CF(c + V3(0, 2, 0)), 58, 4, 1.2, 48, RGB(28, 28, 36), M.Metal)
	for k = 0, 11 do
		local ang = k * 30 + 15
		ad(a, CF(c) * ANG(0, rad(ang), 0) * CF(0, 2.2, -57.2) * ANG(0, pi, 0), Vector2.new(20, 3), k % 2 == 0 and RGB(255, 60, 70) or RGB(80, 150, 255))
	end

	-- THE BOWL: twelve tiers rising to the roof, packed; two gaps for the fighter tunnels
	-- (behind the red and the blue corner)
	local tunnelAngles = {}
	for side = 1, 2 do
		local corner = core.Corners[side]
		-- Kit.Ring's angle: 0 = -Z, turning toward -X (CFrame.Angles about Y)
		tunnelAngles[side] = math.deg(math.atan2(-corner.X, -corner.Z))
	end
	local function inTunnel(deg: number): boolean
		for _, t in tunnelAngles do
			local diff = math.abs(((deg - t) + 180) % 360 - 180)
			if diff < 9 then
				return true
			end
		end
		return false
	end
	local tiers = 12
	for t = 0, tiers - 1 do
		local r = 62 + t * 7
		local top = 3 + t * 4
		local sections = 24
		for s = 0, sections - 1 do
			local from, to = s * 15, s * 15 + 15
			local mid = (from + to) / 2
			if not inTunnel(mid) then
				Kit.Ring(a, CF(c + V3(0, top / 2 - 1, 0)), r, top, 7.2, 3, SEAT, M.Concrete, nil, from, to)
				-- the crowd on this tier's step
				local section = Kit.Model("Crowd", a)
				local count = math.floor(2 * pi * r * (15 / 360) / 5.6)
				local cheering = rng:NextNumber() < 0.35
				for k = 0, count - 1 do
					if rng:NextNumber() < 0.6 then
						local deg = from + (k + 0.5) * 15 / count
						local spot = CF(c) * ANG(0, rad(deg), 0) * CF(rng:NextNumber(-0.6, 0.6), top - 1, -r + rng:NextNumber(-1, 1))
						fan(section, spot, rng, cheering and rng:NextNumber() < 0.6)
					end
				end
				section.WorldPivot = CF(c) * ANG(0, rad(mid), 0) * CF(0, top - 1, -r)
				if cheering then
					Kit.Tag(section, "WBob", { Amp = 0.5, Speed = rng:NextNumber(4, 7) })
				end
			end
		end
	end
	-- the outer wall and the roof: a ring wall, radial girders, a dark ceiling
	local roofY = 3 + tiers * 4 + 18
	Kit.Ring(a, CF(c + V3(0, roofY / 2, 0)), OUTER, roofY + 4, 3, 64, RGB(24, 22, 30), M.Concrete)
	disc(a, CF(c + V3(0, roofY + 2, 0)), OUTER * 2 + 6, 2, RGB(14, 13, 18), M.Concrete, { Name = "DomeRoof" })
	for k = 0, 15 do
		local angle = rad(k * 22.5)
		local out = V3(sin(angle), 0, cos(angle))
		rod(a, c + out * 30 + V3(0, roofY, 0), c + out * (OUTER - 2) + V3(0, roofY - 6, 0), 2, 3, RGB(50, 48, 58), M.DiamondPlate)
	end
	Kit.Ring(a, CF(c + V3(0, roofY, 0)), 30, 3, 2, 32, RGB(50, 48, 58), M.DiamondPlate)

	-- THE TUNNELS: lit arches into the bowl, the corner's colour, its name over them
	for side = 1, 2 do
		local ang = rad(tunnelAngles[side])
		local frame = CF(c) * ANG(0, ang, 0)
		local _, TC = Kit.Frame(frame)
		for _, x in { -9, 9 } do
			P(a, TC(x, 10, -66), V3(3, 20, 3), RGB(40, 38, 48), M.Metal)
			P(a, TC(x, 10, -64.4), V3(0.5, 20, 0.3), CORNER_COLORS[side], M.Neon, glow)
		end
		P(a, TC(0, 21, -66), V3(21, 3, 3), RGB(40, 38, 48), M.Metal)
		Kit.Sign(a, TC(0, 21, -64.4) * ANG(0, rad(180), 0), V3(18, 2.6, 0.2), side == 1 and "RED CORNER" or "BLUE CORNER", CORNER_COLORS[side], { Color = RGB(10, 8, 12) })
		-- the tunnel itself, running out under the stands
		P(a, TC(0, 9, -100), V3(18, 1, 66), RGB(24, 22, 28), M.Concrete) -- roof
		for _, x in { -9.5, 9.5 } do
			P(a, TC(x, 4, -100), V3(1, 10, 66), RGB(30, 28, 34), M.Concrete)
		end
		for z = -72, -128, -14 do
			local lamp = P(a, TC(0, 8.3, z), V3(3, 0.3, 1), CORNER_COLORS[side], M.Neon, glow)
			Kit.Light(lamp, CORNER_COLORS[side], 1.4, 14)
		end
	end

	-- OVER THE RING: the jumbotron (four screens), the scoreboard ring, the spotlights
	local jumbo = c + V3(0, core.FloorY - c.Y + 40, 0)
	P(a, CF(jumbo), V3(26, 14, 26), RGB(16, 15, 20), M.Metal, { Name = "Jumbotron" })
	for k = 0, 3 do
		board(a, CF(jumbo) * ANG(0, rad(k * 90), 0) * CF(0, 0, -13.4), Vector2.new(24, 12), GOLD)
	end
	for _, x in { -10, 10 } do
		cyl(a, jumbo + V3(x, 7, 0), c + V3(x, roofY, 0), 0.6, RGB(60, 58, 66), M.Metal)
	end
	Kit.Ring(a, CF(jumbo + V3(0, -9, 0)), 16, 1.6, 0.6, 40, RGB(255, 60, 70), M.Neon, glow)
	-- the moving spotlights: twelve heads on the roof ring sweeping the ring
	for k = 0, 11 do
		local angle = rad(k * 30)
		local at = c + V3(sin(angle) * 30, roofY - 2, cos(angle) * 30)
		local head = Kit.Model("Spotlight", a)
		local aim = CFrame.lookAt(at, c + V3(0, core.FloorY - c.Y, 0))
		P(head, aim * CF(0, 0, 1.4), V3(3.4, 3.4, 4), RGB(30, 30, 36), M.Metal)
		local lens = P(head, aim * CF(0, 0, -0.65), V3(3, 3, 0.2), RGB(255, 245, 230), M.Neon, glow)
		Kit.Light(lens, k % 3 == 0 and RGB(255, 120, 130) or RGB(255, 240, 220), 4, 90, { Kind = "SpotLight", Face = Enum.NormalId.Front, Angle = 18 })
		head.WorldPivot = aim
		Kit.Tag(head, "WSwing", { Axis = k % 2 == 0 and "X" or "Y", Angle = 9, Speed = 0.5 + (k % 4) * 0.12 })
	end
	local fill = P(a, CF(jumbo + V3(0, -12, 0)), V3(1, 1, 1), Color3.new(), M.SmoothPlastic, { Transparency = 1, NoCollide = true, Shadow = false })
	Kit.Light(fill, RGB(220, 210, 255), 1.4, 80)
	-- smoke machines at the ring's corners
	for _, corner in core.Corners do
		local out = corner * 1.4
		Kit.Emitter(a, CF(c + out + V3(0, 0.5, 0)), V3(3, 1, 3), Kit.TEX.Smoke, {
			Color = ColorSequence.new(RGB(150, 140, 180)),
			Size = NumberSequence.new(4, 14),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.82), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(5, 8),
			Rate = 4,
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(60, 60),
		})
	end
	-- championship banners down from the roof, and the turning championship display
	for k = 0, 7 do
		local angle = rad(k * 45 + 22.5)
		local at = c + V3(sin(angle) * 100, roofY - 14, cos(angle) * 100)
		local banner = Kit.Sign(a, CFrame.lookAt(at, V3(c.X, at.Y, c.Z)), V3(8, 20, 0.3), k % 2 == 0 and "CHAMPIONSHIP\nSERIES" or "THE\nCOLOSSUS", k % 2 == 0 and GOLD or RGB(255, 80, 90), { Color = RGB(30, 12, 18) })
		banner.CanCollide = false
		Kit.Tag(banner, "WSwing", { Axis = "X", Angle = 2, Speed = 0.4 })
	end
	local display = Kit.Model("ChampionshipDisplay", a)
	local dc = c + V3(0, core.FloorY - c.Y + 60, 0)
	Kit.Ring(display, CF(dc) * ANG(rad(90), 0, 0), 9, 1, 1.4, 36, GOLD, M.Neon, glow)
	ball(display, dc, 6, GOLD, M.Metal)
	disc(display, CF(dc + V3(0, -4, 0)), 6, 1, GOLD, M.Metal)
	display.WorldPivot = CF(dc)
	Kit.Tag(display, "WSpin", { Axis = "Y", Speed = 0.5 })
	-- the overhead scoreboards on the roof ring, facing the stands
	for k = 0, 3 do
		board(a, CF(c + V3(0, roofY - 10, 0)) * ANG(0, rad(k * 90 + 45), 0) * CF(0, 0, -128) * ANG(0, pi, 0), Vector2.new(30, 12), RGB(255, 60, 70))
	end
	return core
end

------------------------------------------------------------------------------------------
-- 2. THE UNDERGROUND PIT
------------------------------------------------------------------------------------------
local function undergroundPit(a: Model, c: Vector3, rng: Random)
	local core = ring(a, c, { Canvas = RGB(52, 48, 44), Apron = RGB(40, 36, 32), Rope = RGB(160, 30, 30), Line = RGB(120, 30, 30), Cage = true, CanvasMaterial = M.Concrete })
	local CONCRETE, DARK, RUST = RGB(58, 56, 58), RGB(30, 28, 30), RGB(110, 62, 40)
	local room, ceiling = 56, 26
	P(a, CF(c + V3(0, -0.5, 0)), V3(room * 2, 1, room * 2), CONCRETE, M.Concrete, { Name = "PitFloor" })
	for _, side in { { V3(room, ceiling / 2, 0), V3(2, ceiling, room * 2) }, { V3(-room, ceiling / 2, 0), V3(2, ceiling, room * 2) }, { V3(0, ceiling / 2, room), V3(room * 2, ceiling, 2) }, { V3(0, ceiling / 2, -room), V3(room * 2, ceiling, 2) } } do
		P(a, CF(c + side[1]), side[2], RGB(48, 46, 48), M.Concrete, { Name = "PitWall" })
	end
	P(a, CF(c + V3(0, ceiling, 0)), V3(room * 2, 2, room * 2), DARK, M.Concrete, { Name = "PitCeiling" })
	-- the tunnel in (behind the red corner): a dark corridor out through the wall
	P(a, CF(c + V3(-room, 6, room * 0.4)), V3(3, 12, 14), RGB(10, 9, 10), M.Concrete, { Name = "TunnelMouth" })

	-- rusty support beams and the girders across the ceiling
	for _, x in { -40, -14, 14, 40 } do
		for _, z in { -40, 40 } do
			P(a, CF(c + V3(x, ceiling / 2, z)), V3(2.4, ceiling, 2.4), RUST, M.CorrodedMetal)
		end
		P(a, CF(c + V3(x, ceiling - 1.5, 0)), V3(2, 2.4, room * 2), RUST, M.CorrodedMetal)
	end
	-- exposed cables sagging between the girders, chains hanging down
	for k = 1, 8 do
		local x1, x2 = rng:NextNumber(-50, 50), rng:NextNumber(-50, 50)
		local z = rng:NextNumber(-50, 50)
		Kit.Cable(a, c + V3(x1, ceiling - 2.5, z), c + V3(x2, ceiling - 2.5, z + rng:NextNumber(-10, 10)), rng:NextNumber(2, 5), 0.25, RGB(20, 20, 20), M.Rubber)
	end
	for k = 1, 10 do
		local x, z = rng:NextNumber(-48, 48), rng:NextNumber(-48, 48)
		if math.abs(x) > 30 or math.abs(z) > 30 then
			local chain = Kit.Model("Chain", a)
			local length = rng:NextNumber(5, 12)
			for i = 0, math.floor(length) do
				P(chain, CF(c + V3(x, ceiling - 1 - i, z)) * ANG(0, rad(i * 90), 0), V3(0.3, 0.9, 0.6), RGB(80, 78, 72), M.Metal, glow)
			end
			chain.WorldPivot = CF(c + V3(x, ceiling - 1, z))
			Kit.Tag(chain, "WSwing", { Axis = "X", Angle = 4, Speed = rng:NextNumber(0.6, 1.2) })
		end
	end
	-- the overhead light: one hard lamp over the cage, flickering, and neon along the walls
	local lamp = P(a, CF(c + V3(0, ceiling - 4, 0)), V3(8, 0.6, 8), RGB(255, 245, 225), M.Neon, glow)
	Kit.Tag(Kit.Light(lamp, RGB(255, 235, 210), 4, 50, { Kind = "SpotLight", Face = Enum.NormalId.Bottom, Angle = 80 }), "WFlicker", { Min = 3, Max = 4.4, Speed = 3 })
	P(a, CF(c + V3(0, ceiling - 2, 0)), V3(9, 3, 9), DARK, M.Metal)
	for _, wall in { { V3(room - 1.2, 18, 0), V3(0.3, 0.5, room * 1.6) }, { V3(-room + 1.2, 18, 0), V3(0.3, 0.5, room * 1.6) }, { V3(0, 18, room - 1.2), V3(room * 1.6, 0.5, 0.3) } } do
		local strip = P(a, CF(c + wall[1]), wall[2], rng:NextNumber() < 0.5 and RGB(255, 40, 120) or RGB(40, 220, 255), M.Neon, glow)
		Kit.Tag(strip, "WFlicker", { Min = 0, Max = 0.8, Speed = rng:NextNumber(2, 5) })
		Kit.Light(strip, strip.Color, 0.8, 22)
	end
	-- old industrial fans in the walls
	for _, spot in { V3(room - 1.5, 14, -30), V3(-room + 1.5, 14, 30) } do
		local face = CFrame.lookAt(c + spot, c + V3(0, spot.Y, spot.Z))
		disc(a, face * ANG(rad(90), 0, 0), 10, 1, DARK, M.Metal)
		local blades = Kit.Model("Fan", a)
		for k = 0, 3 do
			P(blades, face * CF(0, 0, -0.8) * ANG(0, 0, rad(k * 90)) * CF(0, 2.2, 0), V3(1.6, 4.2, 0.2), RGB(90, 86, 80), M.Metal, glow)
		end
		blades.WorldPivot = face * CF(0, 0, -0.8)
		Kit.Tag(blades, "WSpin", { Axis = "Z", Speed = 3 })
	end
	-- graffiti, the champions' posters, the metal fencing
	local TAGS = { { "NO RULES", RGB(255, 60, 140) }, { "IRONJAW WAS HERE", RGB(120, 255, 120) }, { "BITE BACK", RGB(255, 200, 40) }, { "PIT LIFE", RGB(80, 200, 255) }, { "DOWN = OUT", RGB(255, 90, 60) } }
	for i, tag in TAGS do
		local onLeft = i % 2 == 0
		local x = onLeft and -room + 1.05 or room - 1.05
		local cf = CFrame.lookAt(c + V3(x, rng:NextNumber(6, 13), rng:NextNumber(-40, 40)), c + V3(0, 8, 0) * V3(1, 0, 1) + V3(0, 8, 0)) * ANG(0, 0, rad(rng:NextNumber(-12, 12)))
		local sign = Kit.Sign(a, cf, V3(rng:NextNumber(12, 18), 4, 0.1), tag[1], tag[2], { Color = RGB(48, 46, 48), Font = Enum.Font.Bangers })
		sign.CanCollide = false
	end
	local LEGENDS = { "IRONJAW · 31-0", "MOTHER MANDIBLE", "KID CHROME", "THE GRAVE BARON" }
	for i, name in LEGENDS do
		local x = -36 + (i - 1) * 24
		Kit.Sign(a, CF(c + V3(x, 11, -room + 1.1)) * ANG(0, pi, 0), V3(8, 10, 0.2), "CHAMPION\n" .. name, RGB(255, 210, 120), { Color = RGB(60, 30, 26), Font = Enum.Font.GothamBold })
	end
	for _, z in { -36, 36 } do
		P(a, CF(c + V3(0, 3.5, z)), V3(room * 1.5, 7, 0.4), RGB(90, 90, 92), M.DiamondPlate, { Transparency = 0.35, Name = "Fence" })
	end
	-- the crowd, pressed right up against the cage on three sides
	for side = 0, 2 do
		local frame = CF(c) * ANG(0, rad(side * 90 + 90), 0)
		local section = Kit.Model("Crowd", a)
		for row = 0, 2 do
			for x = -22, 22, 3.2 do
				if rng:NextNumber() < 0.8 then
					local spot = frame * CF(x + rng:NextNumber(-0.7, 0.7), 0, -(UG.RingHalf + 8 + row * 3.2)) * ANG(0, rad(180 + rng:NextNumber(-20, 20)), 0)
					fan(section, spot, rng, rng:NextNumber() < 0.4)
				end
			end
		end
		section.WorldPivot = frame
		Kit.Tag(section, "WBob", { Amp = 0.35, Speed = 6 })
	end
	-- haze and dust in the air
	Kit.Emitter(a, CF(c + V3(0, 8, 0)), V3(room * 1.6, 6, room * 1.6), Kit.TEX.Smoke, {
		Color = ColorSequence.new(RGB(140, 125, 110)),
		Size = NumberSequence.new(8, 16),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.88), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(8, 12),
		Rate = 6,
		Speed = NumberRange.new(0.2, 0.6),
	})
	Kit.Emitter(a, CF(c + V3(0, 12, 0)), V3(room * 1.4, 10, room * 1.4), Kit.TEX.Spark, Kit.MotesFX(RGB(220, 200, 170), 18, 0.2, 0.12))
	-- the fight's board over the door
	board(a, CF(c + V3(0, 20, room - 1.3)), Vector2.new(24, 8), RGB(255, 60, 140))
	return core
end

------------------------------------------------------------------------------------------
-- 3. IRONWORKS FURNACE
------------------------------------------------------------------------------------------
local function ironworksFurnace(a: Model, c: Vector3, rng: Random)
	local core = ring(a, c, { Canvas = RGB(70, 66, 62), Apron = RGB(40, 38, 36), Rope = RGB(255, 140, 40), Line = RGB(220, 110, 30), CanvasMaterial = M.DiamondPlate })
	local STEEL, DARK, RUST, MOLTEN = RGB(72, 70, 72), RGB(28, 26, 26), RGB(110, 62, 40), RGB(255, 120, 30)
	local hall, height = 110, 70
	P(a, CF(c + V3(0, -0.5, 0)), V3(hall * 2, 1, hall * 2), RGB(56, 54, 54), M.DiamondPlate, { Name = "FactoryFloor" })
	for _, side in { { V3(hall, height / 2, 0), V3(2, height, hall * 2) }, { V3(-hall, height / 2, 0), V3(2, height, hall * 2) }, { V3(0, height / 2, hall), V3(hall * 2, height, 2) }, { V3(0, height / 2, -hall), V3(hall * 2, height, 2) } } do
		P(a, CF(c + side[1]), side[2], RGB(44, 40, 38), M.CorrodedMetal, { Name = "FactoryWall" })
	end
	P(a, CF(c + V3(0, height, 0)), V3(hall * 2, 2, hall * 2), DARK, M.Metal, { Name = "FactoryRoof" })
	-- the steel frame: columns and roof trusses
	for x = -hall + 20, hall - 20, 40 do
		for _, z in { -hall + 8, hall - 8 } do
			P(a, CF(c + V3(x, height / 2, z)), V3(3, height, 3), STEEL, M.Metal)
		end
		Kit.Rod(a, c + V3(x, height - 4, -hall), c + V3(x, height - 4, hall), 2, 4, STEEL, M.DiamondPlate)
	end

	-- THE FURNACES along the back wall: huge, glowing, roaring
	for k = -2, 2 do
		local base = c + V3(k * 36, 0, -hall + 18)
		cyl(a, base, base + V3(0, 40, 0), 22, RUST, M.CorrodedMetal)
		cyl(a, base + V3(0, 40, 0), base + V3(0, 64, 0), 8, DARK, M.Metal)
		local mouth = P(a, CF(base + V3(0, 9, 10.6)), V3(10, 10, 0.6), MOLTEN, M.Neon, glow)
		Kit.Light(mouth, RGB(255, 140, 50), 3, 40)
		Kit.Tag(mouth, "WPulse", { Min = 0, Max = 0.35, Speed = 1.5 + k * 0.2 })
		Kit.Emitter(a, CF(base + V3(0, 9, 11)), V3(8, 6, 1), Kit.TEX.Fire, Kit.FireFX(30, 3))
		Kit.Emitter(a, CF(base + V3(0, 64, 0)), V3(5, 1, 5), Kit.TEX.Smoke, Kit.SmokeFX(RGB(60, 50, 46), 4, 6))
	end
	-- molten metal behind the rails, both sides: a channel of glowing slag
	for _, s in { -1, 1 } do
		local channel = P(a, CF(c + V3(s * 82, 0.2, 0)), V3(18, 0.6, hall * 1.6), MOLTEN, M.CrackedLava, { Name = "MoltenChannel" })
		Kit.Light(channel, RGB(255, 120, 40), 2, 30)
		for z = -hall + 20, hall - 20, 6 do
			cyl(a, c + V3(s * 72, 0, z), c + V3(s * 72, 4, z), 0.4, RGB(240, 190, 40), M.Metal)
		end
		cyl(a, c + V3(s * 72, 4, -hall + 20), c + V3(s * 72, 4, hall - 20), 0.4, RGB(240, 190, 40), M.Metal)
		Kit.Emitter(a, CF(c + V3(s * 82, 1, 0)), V3(16, 1, hall * 1.4), Kit.TEX.Spark, Kit.SparkFX(RGB(255, 160, 60), 20))
	end

	-- the JIB CRANE: a column by the ring, its arm swinging over the floor with a hook
	local craneBase = c + V3(-48, 0, 44)
	cyl(a, craneBase, craneBase + V3(0, 46, 0), 3, RGB(240, 190, 40), M.Metal)
	local jib = Kit.Model("Crane", a)
	local pivot = CF(craneBase + V3(0, 46, 0))
	P(jib, pivot * CF(0, 0, -20), V3(2.4, 3, 42), RGB(240, 190, 40), M.Metal)
	P(jib, pivot * CF(0, 0, 4), V3(4, 4, 6), DARK, M.Metal) -- counterweight
	cyl(jib, (pivot * CF(0, -1, -36)).Position, (pivot * CF(0, -18, -36)).Position, 0.3, RGB(30, 30, 30), M.Metal, glow)
	P(jib, pivot * CF(0, -19, -36), V3(3, 2, 3), RGB(60, 58, 60), M.Metal, glow)
	jib.WorldPivot = pivot
	Kit.Tag(jib, "WSwing", { Axis = "Y", Angle = 50, Speed = 0.18 })

	-- CONVEYOR BELTS carrying scrap past the ring, two of them
	for _, x in { 52, 62 } do
		local belt = Kit.Model("Conveyor", a)
		P(a, CF(c + V3(x, 1.2, 0)), V3(7, 2.4, 140), DARK, M.Metal)
		for z = -70, 70, 2 do
			P(belt, CFrame.lookAt(c + V3(x, 2.55, z), c + V3(x, 2.55, z + 10)), V3(6.4, 0.3, 1.4), RGB(36, 34, 34), M.Fabric, glow)
		end
		Kit.Tag(belt, "WConveyor", { Speed = 5, Spacing = 2 })
		for z = -60, 60, 24 do
			P(a, CF(c + V3(x, 4, z + rng:NextNumber(-4, 4))) * ANG(rad(rng:NextNumber(0, 40)), rad(rng:NextNumber(0, 90)), 0), V3(rng:NextNumber(2, 4), rng:NextNumber(1.5, 3), rng:NextNumber(2, 4)), RUST, M.CorrodedMetal, glow)
		end
	end
	-- giant fans in the end walls
	for _, s in { -1, 1 } do
		local face = CFrame.lookAt(c + V3(s * (hall - 1.6), 34, 40), c + V3(0, 34, 40))
		disc(a, face * ANG(rad(90), 0, 0), 30, 2, DARK, M.Metal)
		local blades = Kit.Model("GiantFan", a)
		for k = 0, 4 do
			P(blades, face * CF(0, 0, -1.4) * ANG(0, 0, rad(k * 72)) * CF(0, 6.5, 0), V3(4, 12, 0.4), STEEL, M.Metal, glow)
		end
		blades.WorldPivot = face * CF(0, 0, -1.4)
		Kit.Tag(blades, "WSpin", { Axis = "Z", Speed = 1.4 * s })
	end
	-- hydraulic rams pumping, welding sparks spitting
	for k = 1, 4 do
		local at = c + V3(rng:NextNumber(-60, 60), 0, hall - 26 + rng:NextNumber(-6, 6))
		P(a, CF(at + V3(0, 4, 0)), V3(8, 8, 8), STEEL, M.Metal)
		local ram = Kit.Model("Ram", a)
		cyl(ram, at + V3(0, 8, 0), at + V3(0, 18, 0), 2.4, RGB(200, 200, 205), M.Metal)
		P(ram, CF(at + V3(0, 18.5, 0)), V3(9, 1.6, 9), RGB(240, 190, 40), M.Metal)
		ram.WorldPivot = CF(at + V3(0, 13, 0))
		Kit.Tag(ram, "WBob", { Amp = 3, Speed = 1.2 + k * 0.3 })
	end
	for k = 1, 6 do
		local at = c + V3(rng:NextNumber(-90, 90), rng:NextNumber(6, 20), rng:NextNumber(-90, 90))
		if math.abs(at.X - c.X) > 40 or math.abs(at.Z - c.Z) > 40 then
			local spark = P(a, CF(at), V3(0.6, 0.6, 0.6), RGB(255, 220, 160), M.Neon, glow)
			Kit.Tag(Kit.Light(spark, RGB(180, 220, 255), 2, 16), "WFlicker", { Min = 0, Max = 3, Speed = 8 })
			Kit.Emitter(a, CF(at), V3(0.5, 0.5, 0.5), Kit.TEX.Spark, Kit.SparkFX(RGB(255, 220, 140), 40))
		end
	end
	-- industrial lights hanging over the ring, and the board above the furnaces
	for _, p in { V3(-16, 0, -16), V3(16, 0, -16), V3(-16, 0, 16), V3(16, 0, 16) } do
		local at = c + p + V3(0, 34, 0)
		cyl(a, at, at + V3(0, height - 34, 0), 0.3, RGB(30, 30, 30), M.Metal)
		P(a, CF(at), V3(5, 1.4, 5), DARK, M.Metal)
		local bulb = P(a, CF(at + V3(0, -1, 0)), V3(3, 0.4, 3), RGB(255, 220, 170), M.Neon, glow)
		Kit.Light(bulb, RGB(255, 210, 160), 3.4, 60, { Kind = "SpotLight", Face = Enum.NormalId.Bottom, Angle = 70 })
	end
	board(a, CF(c + V3(0, 46, -hall + 2.4)) * ANG(0, pi, 0), Vector2.new(40, 12), MOLTEN)
	board(a, CF(c + V3(0, 30, hall - 2.4)), Vector2.new(30, 10), MOLTEN)
	Kit.Sign(a, CF(c + V3(0, 58, -hall + 2.2)) * ANG(0, pi, 0), V3(60, 6, 0.4), "IRONWORKS FURNACE", MOLTEN, { Color = RGB(20, 14, 10) })
	return core
end

------------------------------------------------------------------------------------------
Arenas.Builders = {
	ColossusDome = colossusDome,
	UndergroundPit = undergroundPit,
	IronworksFurnace = ironworksFurnace,
}

function Arenas.Build(themeId: string, origin: Vector3, seed: number)
	local builder = Arenas.Builders[themeId]
	assert(builder, "unknown Underground arena " .. tostring(themeId))
	local root = Workspace:FindFirstChild("UndergroundArenas") or Kit.Folder("UndergroundArenas", Workspace)
	local a = Kit.Model(themeId .. "_" .. seed, root)
	local core = builder(a, origin, Random.new(seed))
	local screens = {}
	for _, d in a:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "UGBoard" then
			table.insert(screens, d)
		end
	end
	return { Model = a, Theme = themeId, Center = core.Center, Starts = core.Starts, Booths = core.Booths, Screens = screens }
end

return Arenas
