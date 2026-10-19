--[[
	ArenaBuilder  (ModuleScript)
	Location: ServerScriptService/Server/Services/Bosses/ArenaBuilder

	Builds the four boss arenas, each handcrafted around its boss:

	  Junkyard        THE TITAN'S FOUNDRY      furnace walls, cogs, smokestacks, a press
	                  Hazards: steam vents burst, the hydraulic press slams a lane
	  MirrorHall      THE HALL OF REFLECTIONS  a ring of giant mirrors, floating shards
	                  Hazards: the mirrors fire reflected beams across the floor
	  ThunderPlateau  THE TEMPEST SUMMIT       a mountain top under a storm vortex
	                  Hazards: lightning strikes, wind gusts
	  SunkenAbyss     THE MAW CATHEDRAL        a flooded cathedral ringed by teeth
	                  Hazards: tentacles slam from the water, abyss bubbles

	Every arena: a circular fight floor (Radius), walls with ONE entrance facing the route,
	a sealed barrier in that entrance, and a plaza outside it with the challenge altar
	(ProximityPrompt "BossPortal") and a waystone back to the Forge.

	Build(origin, name, isWorld): origin = CFrame at the floor centre, LookVector pointing
	out through the entrance. Slot 1 of each type is built in the world (isWorld = true);
	extra slots are copies far away. Returns:
	  { Folder, Center, GroundY, Radius, PlayerSpawn, BossSpawn, ReturnCFrame?, Hazards }
	Hazards = { { Name, Run = function(ctx, arena) } } (BossService runs them on a timer
	during fights; ctx is the boss Context, so damage scales with the difficulty).
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))
local Kit = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("Kit"))

local ArenaBuilder = {}

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local M = Enum.Material
local P, ball, cyl, rod, disc = Kit.P, Kit.Ball, Kit.Cyl, Kit.Rod, Kit.Disc
local glow = { NoCollide = true, Shadow = false }

local function arenaFolder(name: string): Folder
	local root = Workspace:FindFirstChild("BossArenas")
	if not root then
		root = Instance.new("Folder")
		root.Name = "BossArenas"
		root.Parent = Workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = root
	return folder
end

-- Angle (radians) of the entrance in the ring helpers' convention (the entrance is local -Z).
local ENTRANCE_GAP = 26 -- degrees each side of the entrance left open in the walls

-- Clears terrain above a world arena's floor (route scenery must never end up inside the
-- fight). Terrain is stored in 4-stud voxels: a fill rounds a partly covered voxel UP to
-- solid, and a solid voxel's smooth surface is drawn about 2 studs ABOVE its top. Rock
-- whose top was exactly floor height poked up to 5 studs through the floor (players
-- spawned inside it). So the arena is cleared from one voxel below the voxel line under
-- the floor: the terrain surface then ends 2+ studs under the floor top, hidden by the
-- floor plates. Call it again after an arena fills terrain of its own (mountain top...).
local function clearAbove(origin: CFrame, wallR: number)
	local below = math.floor(origin.Y / 4) * 4 - origin.Y -- 0 to -4 studs
	Kit.TCyl(CFrame.new(origin.Position + V3(0, below - 4 + 60, 0)), 120, wallR + 24, Enum.Material.Air)
	-- the approach outside the gate only needs the voxel line (a stud of ground showing
	-- beside the walkway out there is fine; a ditch would not be)
	Kit.TBlock(origin * CF(0, below + 30, -(WorldDefinitions.GateDistance + wallR) / 2), V3(48, 60, WorldDefinitions.GateDistance - wallR + 48), Enum.Material.Air)
end

-- Shared layout: floor, entrance gate with barrier, approach, plaza, altar, waystone.
local function common(folder, origin: CFrame, opts)
	local L, C = Kit.Frame(origin)
	local R = opts.Radius
	local wallR = R + 6

	if opts.IsWorld then
		clearAbove(origin, wallR)
	end

	-- the approach from the gate out to the plaza
	local plazaZ = -WorldDefinitions.GateDistance
	P(folder, C(0, -opts.FloorThickness / 2, (-wallR + plazaZ) / 2 - 2), V3(26, opts.FloorThickness, -plazaZ - wallR + 8), opts.ApproachColor, opts.ApproachMaterial, { Name = "Approach" })
	disc(folder, C(0, -opts.FloorThickness / 2, plazaZ), 40, opts.FloorThickness, opts.ApproachColor, opts.ApproachMaterial, { Name = "Plaza" })
	Kit.Ring(folder, C(0, 0.08, plazaZ), 19.6, 0.1, 0.8, 40, opts.Accent, M.Neon, glow)

	-- the sealed entrance: two great pillars and a shimmering barrier
	for _, s in { -1, 1 } do
		P(folder, C(s * 14, opts.WallHeight / 2 + 4, -wallR), V3(8, opts.WallHeight + 8, 8), opts.GateColor, opts.GateMaterial)
		P(folder, C(s * 14, opts.WallHeight + 8.5, -wallR), V3(9, 1.2, 9), opts.Accent, M.Neon, glow)
	end
	P(folder, C(0, opts.WallHeight + 6, -wallR), V3(36, 4, 6), opts.GateColor, opts.GateMaterial)
	local barrier = P(folder, C(0, opts.WallHeight / 2 + 2, -wallR), V3(20, opts.WallHeight + 4, 1), opts.Accent, M.ForceField, { Transparency = 0.25, Name = "Barrier" })
	barrier.CastShadow = false
	Kit.Light(barrier, opts.Accent, 1.5, 24)
	Kit.Sign(folder, C(0, opts.WallHeight + 6, -wallR - 3.1), V3(30, 3.4, 0.4), opts.Title, opts.Accent, { Color = RGB(14, 12, 18) })

	-- the challenge altar (opens the boss portal UI on the client)
	local altarCF = C(-12, 0, plazaZ + 4, 0, 90, 0)
	local _, AC = Kit.Frame(altarCF)
	P(folder, AC(0, 1.5, 0), V3(6, 3, 6), opts.GateColor, opts.GateMaterial)
	P(folder, AC(0, 3.4, 0), V3(5, 0.8, 5), RGB(24, 20, 28), M.Slate)
	local crystal = P(folder, AC(0, 6.5, 0, 0, 45, 0), V3(2.2, 4.4, 2.2), opts.Accent, M.Neon, glow)
	Kit.Tag(crystal, "WBob", { Amp = 0.5, Speed = 1.4 })
	Kit.Light(crystal, opts.Accent, 2, 24)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BossPortal"
	prompt.ActionText = "Challenge"
	prompt.ObjectText = opts.BossName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("BossId", opts.BossId)
	prompt.Parent = crystal
	Kit.Billboard(folder, AC(0, 11, 0).Position, "CHALLENGE", opts.BossName, opts.Accent, Vector2.new(12, 3.4), 120)

	-- waystone home
	Kit.Waystone(folder, C(12, 0, plazaZ + 4, 0, -90, 0), "Hub", RGB(190, 140, 255), "Return", "Waystone · The Nightmare Forge")

	return L, C, wallR
end

local function spawns(origin: CFrame)
	local L = function(x, y, z)
		return origin:PointToWorldSpace(V3(x, y, z))
	end
	-- player: root 5 studs up, so even a tall avatar (HipHeight + half its root above 3)
	-- drops onto the floor instead of starting with its feet inside it
	return CFrame.lookAt(L(0, 5, -38), L(0, 5, 0)), CFrame.lookAt(L(0, 0, 28), L(0, 0, 0))
end

local function info(folder, origin: CFrame, radius: number, regionId: string, hazards)
	local playerSpawn, bossSpawn = spawns(origin)
	return {
		Folder = folder,
		Center = origin.Position,
		GroundY = origin.Y,
		Radius = radius,
		PlayerSpawn = playerSpawn,
		BossSpawn = bossSpawn,
		ReturnCFrame = WorldDefinitions.GatePlaza(regionId) * CF(0, 3, 6),
		Hazards = hazards,
	}
end

-- Random point on the fight floor near a random target (or anywhere).
local function nearTarget(ctx, spread: number): Vector3
	local targets = ctx:Targets()
	if #targets > 0 then
		local target = targets[ctx.Random:NextInteger(1, #targets)]
		local p = ctx:GroundPosition(target)
		return ctx:ClampToArena(p + V3(ctx.Random:NextNumber(-spread, spread), 0, ctx.Random:NextNumber(-spread, spread)))
	end
	local a = ctx.Random:NextNumber(0, 2 * pi)
	return ctx:ClampToArena(ctx.Arena.Center + V3(cos(a), 0, sin(a)) * ctx.Random:NextNumber(0, ctx.Arena.Radius))
end

local function fighting(ctx): boolean
	return ctx.Encounter.State == "Fighting"
end

------------------------------------------------------------------------------------------
-- 1. THE TITAN'S FOUNDRY (Scrap Titan)
------------------------------------------------------------------------------------------
function ArenaBuilder.BuildJunkyard(origin: CFrame, name: string, isWorld: boolean?)
	local folder = arenaFolder(name)
	local R = 60
	local RUST, RUST2, DARK, GLOW = RGB(122, 64, 36), RGB(86, 50, 34), RGB(40, 38, 37), RGB(255, 120, 30)
	local wallH = 26
	local L, C, wallR = common(folder, origin, {
		Radius = R,
		IsWorld = isWorld,
		FloorThickness = 4,
		WallHeight = wallH,
		ApproachColor = RGB(58, 54, 50),
		ApproachMaterial = M.DiamondPlate,
		GateColor = RUST,
		GateMaterial = M.CorrodedMetal,
		Accent = GLOW,
		Title = "THE TITAN'S FOUNDRY",
		BossName = "The Scrap Titan",
		BossId = "ScrapTitan",
	})
	if isWorld then
		Kit.TCyl(origin * CF(0, -30, 0), 56, wallR + 50, M.Ground)
		clearAbove(origin, wallR) -- (the fill rounds the floor's voxel up to solid)
	end

	-- floor: scorched plate with a hazard-striped ring
	disc(folder, C(0, -2, 0), (wallR + 4) * 2, 4, RGB(56, 52, 50), M.DiamondPlate)
	Kit.Ring(folder, C(0, 0.06, 0), R - 1, 0.1, 2, 60, function(i)
		return i % 2 == 0 and RGB(210, 160, 30) or RGB(22, 22, 22)
	end, M.SmoothPlastic, glow)
	disc(folder, C(0, 0.04, 0), 30, 0.08, RGB(40, 34, 30), M.Metal, glow)

	-- furnace walls (gap at the entrance), with glowing furnace mouths and pipes
	Kit.Ring(folder, C(0, wallH / 2, 0), wallR, wallH, 6, 40, RUST, M.CorrodedMetal, nil, ENTRANCE_GAP, 360 - ENTRANCE_GAP)
	Kit.Ring(folder, C(0, wallH + 0.6, 0), wallR, 1.2, 7, 40, RUST2, M.DiamondPlate, nil, ENTRANCE_GAP, 360 - ENTRANCE_GAP)
	for k = 0, 9 do
		local a = rad(ENTRANCE_GAP + 16 + k * 31)
		local dir = V3(-sin(a), 0, -cos(a))
		-- Layers are spaced apart (wall face → backing panel → glow → bars) so no two
		-- surfaces are flush: flush faces z-fight and flicker.
		local base = origin.Position + origin:VectorToWorldSpace(dir) * (wallR - 3.6)
		local facing = CFrame.lookAt(base, origin.Position)
		P(folder, facing * CF(0, 8, 0), V3(9, 10, 0.6), RGB(20, 14, 12), M.Metal)
		local mouth = P(folder, facing * CF(0, 7, -0.45), V3(7, 7, 0.1), GLOW, M.Neon, glow)
		Kit.Tag(mouth, "WPulse", { Min = 0, Max = 0.2, Speed = 0.6 + k * 0.05 })
		Kit.Light(mouth, GLOW, 1.6, 24)
		for g = -2, 2 do
			P(folder, facing * CF(g * 1.6, 7, -0.85), V3(0.35, 8, 0.3), DARK, M.Metal, glow)
		end
		-- pilasters either side of the furnace mouth
		for _, s in { -1, 1 } do
			P(folder, facing * CF(s * 6, wallH / 2, 0.6), V3(2.4, wallH, 2), RUST2, M.CorrodedMetal)
		end
	end
	-- giant cogs set into the wall
	for _, deg in { 70, 290 } do
		local a = rad(deg)
		local dir = origin:VectorToWorldSpace(V3(-sin(a), 0, -cos(a)))
		local pos = origin.Position + dir * (wallR - 3.5) + V3(0, 16, 0)
		local cog = Kit.Model("Cog", folder)
		local cf = CFrame.lookAt(pos, origin.Position) * ANG(rad(90), 0, 0)
		disc(cog, cf, 16, 1.5, RUST2, M.CorrodedMetal, glow)
		disc(cog, cf, 5, 2, DARK, M.Metal, glow)
		for t = 0, 13 do
			P(cog, cf * ANG(0, rad(t * 360 / 14), 0) * CF(0, 0, -8.6), V3(2.4, 1.5, 2.4), RUST2, M.CorrodedMetal, glow)
		end
		cog.WorldPivot = cf
		Kit.Tag(cog, "WSpin", { Speed = deg == 70 and 0.4 or -0.4, Axis = "Y" })
	end
	-- smokestacks behind the walls
	for _, deg in { 120, 160, 200, 240 } do
		local a = rad(deg)
		local pos = origin.Position + origin:VectorToWorldSpace(V3(-sin(a), 0, -cos(a))) * (wallR + 18)
		cyl(folder, pos - V3(0, 10, 0), pos + V3(0, 70, 0), 9, RGB(70, 52, 44), M.Brick)
		disc(folder, CF(pos + V3(0, 56, 0)), 10, 3, RGB(170, 40, 30), M.SmoothPlastic)
		Kit.Emitter(folder, CF(pos + V3(0, 71, 0)), V3(6, 1, 6), Kit.TEX.Smoke, Kit.SmokeFX(RGB(60, 52, 48), 4, 8))
		local fireTop = ball(folder, pos + V3(0, 70, 0), 4, GLOW, M.Neon, glow)
		Kit.Tag(fireTop, "WPulse", { Min = 0.1, Max = 0.6, Speed = 2 })
	end

	-- steam vents (hazard positions) in a ring
	local vents = {}
	for k = 0, 5 do
		local a = rad(30 + k * 60)
		local pos = L(-sin(a) * 34, 0, -cos(a) * 34)
		disc(folder, CF(pos + V3(0, 0.1, 0)), 8, 0.2, DARK, M.DiamondPlate, glow)
		for g = -2, 2 do
			P(folder, CF(pos + V3(g * 1.4, 0.25, 0)), V3(0.3, 0.1, 6), RGB(80, 80, 84), M.Metal, glow)
		end
		local _, steam = Kit.Emitter(folder, CF(pos + V3(0, 0.5, 0)), V3(5, 0.2, 5), Kit.TEX.Smoke, {
			Color = ColorSequence.new(RGB(230, 230, 230)),
			Size = NumberSequence.new(3, 9),
			Transparency = NumberSequence.new(0.3, 1),
			Lifetime = NumberRange.new(1.2, 2),
			Rate = 1.5,
			Speed = NumberRange.new(10, 18),
			SpreadAngle = Vector2.new(10, 10),
		})
		vents[k + 1] = { Position = pos, Steam = steam }
	end

	-- the hydraulic press: a gantry across the arena, the press head rides along it
	local gantryY = 34
	for _, s in { -1, 1 } do
		P(folder, C(s * (wallR + 2), gantryY / 2, 0), V3(4, gantryY, 4), RGB(150, 112, 40), M.CorrodedMetal)
	end
	P(folder, C(0, gantryY + 2, 0), V3(wallR * 2 + 8, 4, 5), RGB(150, 112, 40), M.CorrodedMetal)
	local press = P(folder, C(0, gantryY - 6, 0), V3(14, 6, 14), DARK, M.Metal, { Name = "PressHead" })
	local pressPiston = P(folder, C(0, gantryY - 1.5, 0), V3(3, 5, 3), RGB(176, 176, 182), M.Metal, { NoCollide = true, Name = "PressPiston" })
	press.CanCollide = false
	press.CanQuery = false

	-- hanging chains and floodlights
	for k = -2, 2 do
		local top = L(k * 18, gantryY, 0)
		Kit.Cable(folder, top, top - V3(0, 8 + math.abs(k) * 2, 0), 0, 0.5, DARK, M.Metal, 3)
	end
	for _, deg in { 45, 135, 225, 315 } do
		local a = rad(deg)
		local pos = L(-sin(a) * (wallR - 2), wallH + 2, -cos(a) * (wallR - 2))
		local lamp = P(folder, CFrame.lookAt(pos, origin.Position), V3(4, 2, 2), RGB(255, 220, 160), M.Neon, glow)
		Kit.Light(lamp, RGB(255, 210, 150), 3, 80, { Kind = "SpotLight", Face = Enum.NormalId.Front, Angle = 70, Shadows = true })
	end
	Kit.Emitter(folder, C(0, 4, 0), V3(R * 1.6, 1, R * 1.6), Kit.TEX.Spark, Kit.MotesFX(RGB(255, 160, 60), 25, 2, 0.22))

	-- Hazards
	local hazards = {
		{
			Name = "SteamVents",
			Run = function(ctx)
				local picks = {}
				local pool = table.clone(vents)
				for _ = 1, math.min(#pool, ctx.Overdrive and 3 or 2) do
					table.insert(picks, table.remove(pool, ctx.Random:NextInteger(1, #pool)))
				end
				for _, vent in picks do
					ctx:Circle(vent.Position, 7, 1.6)
				end
				task.wait(1.6)
				if not fighting(ctx) then
					return
				end
				local positions = {}
				for _, vent in picks do
					vent.Steam:Emit(40)
					table.insert(positions, vent.Position)
					ctx:Impact(vent.Position, 7)
				end
				ctx:DamageCircles(positions, 7, 10, { Knockback = 45 })
			end,
		},
		{
			Name = "HydraulicPress",
			Run = function(ctx)
				local target = nearTarget(ctx, 4)
				local localX = math.clamp(origin:PointToObjectSpace(target).X, -(R - 10), R - 10)
				local up = C(localX, gantryY - 6, 0)
				local down = C(localX, 3, 0)
				TweenService:Create(press, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { CFrame = up }):Play()
				TweenService:Create(pressPiston, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { CFrame = C(localX, gantryY - 1.5, 0) }):Play()
				task.wait(0.6)
				local zoneCF = C(localX, 0, 0)
				ctx:Box(zoneCF, V3(15, 1, 15), 1.5)
				task.wait(1.5)
				if not fighting(ctx) then
					return
				end
				TweenService:Create(press, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = down }):Play()
				task.wait(0.16)
				ctx:Impact(zoneCF.Position, 9)
				ctx:DamageBox(zoneCF, V3(15, 1, 15), 22, { Knockback = 60, Heavy = true })
				task.wait(0.9)
				TweenService:Create(press, TweenInfo.new(1, Enum.EasingStyle.Sine), { CFrame = up }):Play()
			end,
		},
	}
	return info(folder, origin, R, "Scrap", hazards)
end

------------------------------------------------------------------------------------------
-- 2. THE HALL OF REFLECTIONS (Mirror Warden)
------------------------------------------------------------------------------------------
function ArenaBuilder.BuildMirrorHall(origin: CFrame, name: string, isWorld: boolean?)
	local folder = arenaFolder(name)
	local R = 54
	local WHITE, SILVER, GLASS, VIOLET, CYAN = RGB(226, 226, 238), RGB(196, 200, 220), RGB(180, 200, 240), RGB(200, 170, 255), RGB(150, 230, 255)
	local wallH = 30
	local L, C, wallR = common(folder, origin, {
		Radius = R,
		IsWorld = isWorld,
		FloorThickness = 3,
		WallHeight = wallH,
		ApproachColor = WHITE,
		ApproachMaterial = M.Marble,
		GateColor = SILVER,
		GateMaterial = M.Marble,
		Accent = VIOLET,
		Title = "THE HALL OF REFLECTIONS",
		BossName = "The Mirror Warden",
		BossId = "MirrorWarden",
	})
	-- the hall floats: a stepped underside with an inverted spire
	for d = 0, 4 do
		disc(folder, C(0, -3 - d * 6, 0), (wallR + 6) * 2 - d * 30, 6, WHITE, M.Marble)
	end
	local tip = ball(folder, L(0, -36, 0), 8, VIOLET, M.Neon, glow)
	Kit.Light(tip, VIOLET, 3, 80)
	if not isWorld then
		P(folder, C(0, -60, 0), V3(900, 1, 900), RGB(150, 156, 186), M.SmoothPlastic, { NoCollide = true, Reflect = 0.75, Shadow = false })
	end

	-- floor: dark reflective glass with glowing rings and a star
	disc(folder, C(0, -1.5, 0), (wallR + 6) * 2, 3, RGB(28, 30, 48), M.Glass, { Reflect = 0.35 })
	Kit.Ring(folder, C(0, 0.06, 0), R - 2, 0.1, 0.8, 64, VIOLET, M.Neon, glow)
	Kit.Ring(folder, C(0, 0.06, 0), 15, 0.1, 0.6, 40, CYAN, M.Neon, glow)
	for k = 0, 7 do
		local a = rad(k * 45)
		rod(folder, L(-sin(a) * 15, 0.07, -cos(a) * 15), L(-sin(a) * (R - 2), 0.07, -cos(a) * (R - 2)), 0.4, 0.1, RGB(150, 130, 220), M.Neon, glow)
	end

	-- the ring of giant mirrors (hazard: they fire reflected beams)
	local mirrors = {}
	local count = 16
	for k = 0, count - 1 do
		local deg = (k + 0.5) * 360 / count
		if deg > ENTRANCE_GAP and deg < 360 - ENTRANCE_GAP then
			local a = rad(deg)
			local dir = V3(-sin(a), 0, -cos(a))
			local base = origin.Position + origin:VectorToWorldSpace(dir) * wallR
			local face = CFrame.lookAt(base, V3(origin.X, base.Y, origin.Z))
			local width = 2 * pi * wallR / count - 3
			P(folder, face * CF(0, wallH / 2, 0), V3(width, wallH, 0.6), GLASS, M.Glass, { Reflect = 0.65, Transparency = 0.1 })
			for _, s in { -1, 1 } do
				P(folder, face * CF(s * (width / 2 + 1), wallH / 2, 0.4), V3(2, wallH + 2, 2), WHITE, M.Marble)
			end
			P(folder, face * CF(0, wallH + 1, 0.4), V3(width + 4, 2, 2), WHITE, M.Marble)
			local gem = P(folder, face * CF(0, wallH + 3, 0), V3(2.4, 2.4, 0.8), VIOLET, M.Neon, glow)
			table.insert(mirrors, { Position = base + V3(0, 0, 0), Face = face, Gem = gem })
		end
	end
	-- floating shards and a crystal chandelier
	local rng = Random.new(77)
	for _ = 1, 26 do
		local a = rng:NextNumber(0, 2 * pi)
		local d = rng:NextNumber(10, R)
		local p = P(folder, CF(L(-sin(a) * d, rng:NextNumber(30, 52), -cos(a) * d)) * ANG(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6), rng:NextNumber(-0.6, 0.6)), V3(0.6, rng:NextNumber(4, 10), rng:NextNumber(2, 4)), GLASS, M.Glass, { NoCollide = true, Reflect = 0.6, Transparency = 0.15 })
		Kit.Tag(p, "WBob", { Amp = 1.5, Speed = rng:NextNumber(0.3, 0.6) })
	end
	local chandelier = Kit.Model("Chandelier", folder)
	local ccf = C(0, 48, 0)
	Kit.Ring(chandelier, ccf, 14, 0.6, 0.6, 32, SILVER, M.Metal)
	for k = 0, 11 do
		local a = rad(k * 30)
		P(chandelier, ccf * CF(-sin(a) * 14, -3, -cos(a) * 14), V3(1, 6, 1), CYAN, M.Glass, { NoCollide = true, Transparency = 0.2 })
	end
	local core = ball(chandelier, ccf.Position, 5, RGB(230, 220, 255), M.Neon, glow)
	Kit.Light(core, RGB(220, 210, 255), 1, 90, { Shadows = true })
	chandelier.WorldPivot = ccf
	Kit.Tag(chandelier, "WSpin", { Speed = 0.15, Axis = "Y" })
	Kit.Emitter(folder, C(0, 4, 0), V3(R * 1.6, 1, R * 1.6), Kit.TEX.Spark, Kit.MotesFX(RGB(230, 226, 255), 25, 1, 0.2))

	local beamColor = RGB(220, 200, 255)
	local hazards = {
		{
			Name = "MirrorBeams",
			Run = function(ctx)
				local n = ctx.Overdrive and 3 or 2
				local shots = {}
				for _ = 1, n do
					local m = mirrors[ctx.Random:NextInteger(1, #mirrors)]
					local target = nearTarget(ctx, 6)
					local from = V3(m.Position.X, ctx.Arena.GroundY, m.Position.Z)
					local dir = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
					if dir.Magnitude < 1 then
						dir = (ctx.Arena.Center - from) * V3(1, 0, 1)
					end
					dir = dir.Unit
					local length = R * 2.2
					local cf = CFrame.lookAt(from + dir * length / 2, from + dir * length)
					ctx:Box(cf, V3(6, 1, length), 1.5)
					m.Gem.Color = RGB(255, 255, 255)
					table.insert(shots, { CFrame = cf, Size = V3(6, 1, length), Mirror = m })
				end
				task.wait(1.5)
				if not fighting(ctx) then
					return
				end
				for _, shot in shots do
					local beam = P(folder, shot.CFrame * CF(0, 3, 0), V3(1.6, 1.6, shot.Size.Z), beamColor, M.Neon, glow)
					task.delay(0.35, function()
						beam:Destroy()
					end)
					shot.Mirror.Gem.Color = VIOLET
				end
				ctx:DamageBoxes(shots, 14, { Knockback = 30 })
			end,
		},
	}
	return info(folder, origin, R, "Mirror", hazards)
end

------------------------------------------------------------------------------------------
-- 3. THE TEMPEST SUMMIT (Storm Beast)
------------------------------------------------------------------------------------------
function ArenaBuilder.BuildThunderPlateau(origin: CFrame, name: string, isWorld: boolean?)
	local folder = arenaFolder(name)
	local R = 54
	local ROCK, DARK, BOLT = RGB(74, 78, 90), RGB(40, 42, 52), RGB(120, 210, 255)
	local wallH = 12
	local L, C, wallR = common(folder, origin, {
		Radius = R,
		IsWorld = isWorld,
		FloorThickness = 3,
		WallHeight = wallH,
		ApproachColor = RGB(78, 80, 92),
		ApproachMaterial = M.Slate,
		GateColor = DARK,
		GateMaterial = M.Basalt,
		Accent = BOLT,
		Title = "THE TEMPEST SUMMIT",
		BossName = "The Storm Beast",
		BossId = "StormBeast",
	})
	-- the mountain top under the summit
	if isWorld then
		Kit.TCyl(origin * CF(0, -70, 0), 140, wallR + 40, M.Basalt)
		Kit.TCyl(origin * CF(0, -170, 0), 80, wallR + 90, M.Basalt)
		clearAbove(origin, wallR) -- (the fill rounds the floor's voxel up to solid)
	else
		cyl(folder, L(0, -2, 0), L(0, -80, 0), (wallR + 20) * 2, DARK, M.Basalt)
	end
	disc(folder, C(0, -1.5, 0), (wallR + 8) * 2, 3, ROCK, M.Slate)
	-- cracked energy lines in the floor
	local rng = Random.new(91)
	for _ = 1, 14 do
		local a = rng:NextNumber(0, 2 * pi)
		local p0 = L(-sin(a) * rng:NextNumber(4, 12), 0.05, -cos(a) * rng:NextNumber(4, 12))
		local p1 = p0 + V3(-sin(a), 0, -cos(a)) * rng:NextNumber(14, R - 12) + V3(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
		local line = rod(folder, p0, p1, 0.5, 0.1, BOLT, M.Neon, glow)
		Kit.Tag(line, "WPulse", { Min = 0, Max = 0.8, Speed = rng:NextNumber(1, 3) })
	end
	Kit.Ring(folder, C(0, 0.06, 0), 16, 0.1, 0.8, 40, BOLT, M.Neon, glow)

	-- jagged rim of rock spires and lightning rods (gap at the entrance)
	Kit.Ring(folder, C(0, wallH / 2, 0), wallR, wallH, 5, 36, DARK, M.Basalt, nil, ENTRANCE_GAP, 360 - ENTRANCE_GAP)
	for k = 0, 17 do
		local deg = k * 20 + 10
		if deg > ENTRANCE_GAP + 4 and deg < 360 - ENTRANCE_GAP - 4 then
			local a = rad(deg)
			local base = L(-sin(a) * (wallR + 2), 0, -cos(a) * (wallR + 2))
			local h = rng:NextNumber(18, 34)
			P(folder, CF(base + V3(0, h / 2, 0)) * ANG(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6), rng:NextNumber(-0.2, 0.2)), V3(6, h, 6), DARK, M.Basalt)
			if k % 3 == 0 then
				cyl(folder, base + V3(0, h, 0), base + V3(0, h + 14, 0), 0.8, RGB(130, 130, 140), M.Metal)
				local rodTip = ball(folder, base + V3(0, h + 14.6, 0), 1.8, BOLT, M.Neon, glow)
				Kit.Tag(Kit.Light(rodTip, BOLT, 1.6, 26), "WFlicker", { Min = 0.4, Max = 2.4, Speed = 6 })
			end
		end
	end
	-- the great storm crystal behind the Beast's side
	local crystal = P(folder, C(0, 26, wallR + 14, 0, 45, 8), V3(10, 34, 10), BOLT, M.Neon, glow)
	Kit.Tag(crystal, "WPulse", { Min = 0.05, Max = 0.5, Speed = 1.4 })
	Kit.Light(crystal, BOLT, 1.5, 90, { Shadows = true })
	-- the storm vortex overhead
	local vortex = Kit.Model("Vortex", folder)
	local vcf = C(0, 80, 0)
	for k = 1, 3 do
		Kit.Ring(vortex, vcf * CF(0, k * 6, 0), 30 + k * 18, 3, 8, 40, RGB(70, 78, 96), M.SmoothPlastic, { NoCollide = true, Transparency = 0.55 + k * 0.1, Shadow = false })
	end
	vortex.WorldPivot = vcf
	Kit.Tag(vortex, "WSpin", { Speed = 0.12, Axis = "Y" })
	Kit.Emitter(folder, C(0, 8, 0), V3(R * 1.6, 1, R * 1.6), Kit.TEX.Smoke, {
		Color = ColorSequence.new(RGB(150, 160, 180)),
		Size = NumberSequence.new(4, 8),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.85), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(3, 4),
		Rate = 14,
		Speed = NumberRange.new(30, 40),
		EmissionDirection = Enum.NormalId.Left,
	})

	local jitter = Random.new()
	local function bolt(at: Vector3)
		local model = Kit.Model("Bolt", folder)
		local prev = at + V3(0, 90, 0)
		for k = 1, 7 do
			local p = at:Lerp(at + V3(0, 90, 0), 1 - k / 7) + (k < 7 and V3(jitter:NextNumber(-5, 5), 0, jitter:NextNumber(-5, 5)) or V3())
			cyl(model, prev, p, 1.2, RGB(220, 245, 255), M.Neon, glow)
			prev = p
		end
		local flash = P(model, CF(at + V3(0, 4, 0)), V3(1, 1, 1), BOLT, M.Neon, { NoCollide = true, Transparency = 1, Shadow = false })
		Kit.Light(flash, BOLT, 8, 60)
		task.delay(0.25, function()
			model:Destroy()
		end)
	end

	local hazards = {
		{
			Name = "LightningStrikes",
			Run = function(ctx)
				local n = ctx.Overdrive and 4 or 3
				local spots = {}
				for _ = 1, n do
					local p = nearTarget(ctx, 8)
					table.insert(spots, p)
					ctx:Circle(p, 6, 1.3)
				end
				task.wait(1.3)
				if not fighting(ctx) then
					return
				end
				for _, p in spots do
					bolt(p)
					ctx:Impact(p, 6)
				end
				ctx:DamageCircles(spots, 6, 12, { Status = "Shock" })
			end,
		},
		{
			Name = "WindGust",
			Run = function(ctx)
				local a = ctx.Random:NextNumber(0, 2 * pi)
				local dir = V3(cos(a), 0, sin(a))
				-- warning: three wind lanes across the whole summit
				for k = -1, 1 do
					local centre = ctx.Arena.Center + dir:Cross(V3(0, 1, 0)) * k * 30
					ctx:Box(CFrame.lookAt(V3(centre.X, ctx.Arena.GroundY, centre.Z), V3(centre.X, ctx.Arena.GroundY, centre.Z) + dir), V3(14, 1, R * 2), 1.4, "Pull")
				end
				task.wait(1.4)
				if not fighting(ctx) then
					return
				end
				ctx:Push(dir, 70)
			end,
		},
	}
	return info(folder, origin, R, "Storm", hazards)
end

------------------------------------------------------------------------------------------
-- 4. THE MAW CATHEDRAL (Abyssal Maw)
------------------------------------------------------------------------------------------
function ArenaBuilder.BuildSunkenAbyss(origin: CFrame, name: string, isWorld: boolean?)
	local folder = arenaFolder(name)
	local R = 52
	local STONE, MOSS, BONE = RGB(58, 66, 70), RGB(40, 70, 60), RGB(196, 190, 166)
	local TEAL = RGB(70, 240, 190)
	local wallH = 22
	local L, C, wallR = common(folder, origin, {
		Radius = R,
		IsWorld = isWorld,
		FloorThickness = 12,
		WallHeight = wallH,
		ApproachColor = RGB(52, 62, 64),
		ApproachMaterial = M.Slate,
		GateColor = STONE,
		GateMaterial = M.Cobblestone,
		Accent = TEAL,
		Title = "THE MAW CATHEDRAL",
		BossName = "The Abyssal Maw",
		BossId = "AbyssalMaw",
	})
	-- 12 studs thick floor (top at the origin): physics can never push anyone through it
	disc(folder, C(0, -6, 0), (wallR + 6) * 2, 12, STONE, M.Cobblestone)
	disc(folder, C(0, 0.04, 0), R * 2 - 30, 0.08, MOSS, M.Grass, glow)
	Kit.Ring(folder, C(0, 0.06, 0), R - 1, 0.1, 1, 56, TEAL, M.Neon, glow)
	if isWorld then
		Kit.TCyl(origin * CF(0, -30, 0), 40, wallR + 10, M.Limestone)
		clearAbove(origin, wallR) -- (the fill rounds the floor's voxel up to solid)
	else
		P(folder, C(0, -6, 0), V3(700, 1, 700), RGB(14, 40, 44), M.Glass, { Reflect = 0.4, Transparency = 0.1 })
	end

	-- cathedral walls with glowing lancet windows (gap at the entrance)
	Kit.Ring(folder, C(0, wallH / 2, 0), wallR, wallH, 5, 40, STONE, M.Cobblestone, nil, ENTRANCE_GAP, 360 - ENTRANCE_GAP)
	for k = 0, 9 do
		local a = rad(ENTRANCE_GAP + 18 + k * 30.5)
		local base = L(-sin(a) * (wallR - 3.1), 0, -cos(a) * (wallR - 3.1)) -- clear of the wall face (no flicker)
		local face = CFrame.lookAt(base, V3(origin.X, base.Y, origin.Z))
		local window = P(folder, face * CF(0, 11, 0), V3(4, 12, 0.3), TEAL, M.Neon, glow)
		Kit.Tag(window, "WPulse", { Min = 0.2, Max = 0.7, Speed = 0.5 + k * 0.05 })
		ball(folder, (face * CF(0, 17, 0)).Position, 4, TEAL, M.Neon, glow)
		P(folder, face * CF(0, wallH + 6, 1), V3(5, 12, 5), STONE, M.Cobblestone) -- buttress pinnacle
	end
	-- the maw: a ring of enormous teeth leaning in over the walls
	for k = 0, 21 do
		local deg = (k + 0.5) * 360 / 22
		if deg > ENTRANCE_GAP and deg < 360 - ENTRANCE_GAP then
			local a = rad(deg)
			local base = L(-sin(a) * (wallR + 3), wallH - 2, -cos(a) * (wallR + 3))
			local tipPos = L(-sin(a) * (wallR - 10), wallH + 22, -cos(a) * (wallR - 10))
			Kit.Curve(folder, base, tipPos, V3(0, 4, 0), 5.5, 0.6, BONE, M.Limestone, 6, { NoCollide = true })
		end
	end
	-- bone vault ribs arching over the nave
	for k = -2, 2 do
		Kit.Curve(folder, L(-wallR, wallH, k * 18), L(wallR, wallH, k * 18), V3(0, 34, 0), 3.2, 3.2, BONE, M.Limestone, 14, { NoCollide = true })
	end
	-- the abyss pool around the cathedral and things lurking in it
	local rng = Random.new(66)
	for k = 1, 6 do
		local a = rad(rng:NextNumber(40, 320))
		local base = L(-sin(a) * (wallR + 30), -12, -cos(a) * (wallR + 30))
		local pts = {}
		for i = 0, 12 do
			local t = i / 12
			pts[#pts + 1] = base + V3(sin(t * 3 + k) * 6 * t, t * rng:NextNumber(40, 60), cos(t * 3 + k) * 6 * t)
		end
		Kit.Tube(folder, pts, 5, 0.8, RGB(40, 66, 70), M.SmoothPlastic, { NoCollide = true })
	end
	local core = P(folder, C(0, 40, 0), V3(1, 1, 1), TEAL, M.Neon, { Transparency = 1, NoCollide = true, Shadow = false })
	Kit.Tag(Kit.Light(core, TEAL, 2, 100), "WPulse", { Min = 1.2, Max = 2.4, Speed = 0.6 })
	Kit.Emitter(folder, C(0, 2, 0), V3(R * 1.6, 1, R * 1.6), Kit.TEX.Spark, Kit.MotesFX(TEAL, 30, 0.6, 0.2))
	Kit.Emitter(folder, C(0, 1, 0), V3(R * 1.8, 1, R * 1.8), Kit.TEX.Smoke, {
		Color = ColorSequence.new(RGB(60, 120, 120)),
		Size = NumberSequence.new(6, 12),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.86), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(6, 9),
		Rate = 8,
		Speed = NumberRange.new(0.5, 1),
	})

	local function tentacleSlam(ctx)
		local target = nearTarget(ctx, 4)
		local fromDir = (target - ctx.Arena.Center) * V3(1, 0, 1)
		if fromDir.Magnitude < 1 then
			local a = ctx.Random:NextNumber(0, 2 * pi)
			fromDir = V3(cos(a), 0, sin(a))
		end
		fromDir = fromDir.Unit
		local edge = ctx.Arena.Center + fromDir * (R + 2)
		local tip = edge - fromDir * 36
		local cf = CFrame.lookAt(V3((edge.X + tip.X) / 2, ctx.Arena.GroundY, (edge.Z + tip.Z) / 2), V3(tip.X, ctx.Arena.GroundY, tip.Z))
		ctx:Box(cf, V3(9, 1, 36), 1.8)
		task.wait(1.8)
		if not fighting(ctx) then
			return
		end
		local model = Kit.Model("Tentacle", folder)
		local pts = {}
		for i = 0, 10 do
			local t = i / 10
			pts[#pts + 1] = edge:Lerp(tip, t) + V3(0, ctx.Arena.GroundY - edge.Y + 2 + sin(t * pi) * 1.5, 0)
		end
		Kit.Tube(model, pts, 6, 1.2, RGB(40, 66, 70), M.SmoothPlastic, { NoCollide = true })
		ctx:Impact(cf.Position, 10)
		ctx:DamageBox(cf, V3(9, 1, 36), 16, { Knockback = 40, Status = "Weaken" })
		task.delay(1.2, function()
			model:Destroy()
		end)
	end

	local hazards = {
		{ Name = "TentacleSlam", Run = tentacleSlam },
		{
			Name = "AbyssBubbles",
			Run = function(ctx)
				local spots = {}
				for _ = 1, ctx.Overdrive and 4 or 3 do
					local p = nearTarget(ctx, 10)
					table.insert(spots, p)
					ctx:Circle(p, 5, 1.6)
				end
				task.wait(1.6)
				if not fighting(ctx) then
					return
				end
				for _, p in spots do
					ctx:Impact(p, 5)
				end
				ctx:DamageCircles(spots, 5, 9, { Status = "Weaken" })
			end,
		},
	}
	return info(folder, origin, R, "Abyss", hazards)
end

-- Arena types: Row = which row the far-away copies use; Region = its world region.
ArenaBuilder.Types = {
	Junkyard = { Row = 0, Region = "Scrap", Build = ArenaBuilder.BuildJunkyard },
	MirrorHall = { Row = 1, Region = "Mirror", Build = ArenaBuilder.BuildMirrorHall },
	ThunderPlateau = { Row = 2, Region = "Storm", Build = ArenaBuilder.BuildThunderPlateau },
	SunkenAbyss = { Row = 3, Region = "Abyss", Build = ArenaBuilder.BuildSunkenAbyss },
}

return ArenaBuilder
