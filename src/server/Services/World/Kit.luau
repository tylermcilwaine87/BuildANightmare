--[[
	Kit  (ModuleScript)
	Location: ServerScriptService/Server/Services/World/Kit

	Building blocks for the world and boss arenas: parts, shapes, terrain, walkable
	paths, lights, particles, signs, relics, waystones, and the animation tags the client
	(WorldController) brings to life:

	  WSpin     Model/Part  spin around its pivot      attrs Speed (rad/s), Axis "X"|"Y"|"Z"
	  WBob      Model/Part  float up and down          attrs Amp, Speed
	  WSwing    Model/Part  pendulum around its pivot  attrs Angle (deg), Speed, Axis
	  WOrbit    Model/Part  circle a point             attrs Center, Radius, Speed, Height
	  WConveyor Model       slats scroll along -Z      attrs Speed, Spacing
	  WPulse    Part/Light  glow pulse                 attrs Min, Max, Speed
	  WFlicker  Light       flicker                    attrs Min, Max, Speed
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Kit = {}

local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad, sin, pi = math.rad, math.sin, math.pi
local M = Enum.Material
local Shape = Enum.PartType

Kit.TEX = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

------------------------------------------------------------------------------------------
-- Parts and shapes
------------------------------------------------------------------------------------------
-- opts: Shape, NoCollide, Transparency, Reflect, Shadow (false = no shadow), Name
function Kit.P(parent, cf: CFrame, size: Vector3, color: Color3, mat, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	if opts.Shape then
		p.Shape = opts.Shape
	end
	p.Name = opts.Name or "Part"
	p.Anchored = true
	p.CanCollide = not opts.NoCollide
	p.CanTouch = false
	p.CanQuery = not opts.NoCollide
	p.CastShadow = opts.Shadow ~= false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	p.Reflectance = opts.Reflect or 0
	p.Transparency = opts.Transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local P = Kit.P

local function shaped(opts, shape)
	local o = opts and table.clone(opts) or {}
	o.Shape = shape
	return o
end

-- CFrame at the midpoint of a->b with -Z pointing at b.
function Kit.Look(a: Vector3, b: Vector3, up: Vector3?)
	local dir = b - a
	local u = up or V3(0, 1, 0)
	if dir.Magnitude > 0 and math.abs(dir.Unit:Dot(u.Unit)) > 0.98 then
		u = math.abs(dir.Unit.Z) < 0.9 and V3(0, 0, 1) or V3(1, 0, 0)
	end
	return CFrame.lookAt((a + b) / 2, b, u)
end
local look = Kit.Look

function Kit.Ball(parent, pos: Vector3, d: number, color, mat, opts)
	return P(parent, CF(pos), V3(d, d, d), color, mat, shaped(opts, Shape.Ball))
end
local ball = Kit.Ball

function Kit.Cyl(parent, a: Vector3, b: Vector3, d: number, color, mat, opts)
	local len = (b - a).Magnitude
	if len < 0.02 then
		return nil
	end
	return P(parent, look(a, b) * ANG(0, rad(90), 0), V3(len, d, d), color, mat, shaped(opts, Shape.Cylinder))
end
local cyl = Kit.Cyl

-- Block from a to b. w = width (local X), h = thickness (local Y). opts.Up picks the roll.
function Kit.Rod(parent, a: Vector3, b: Vector3, w: number, h: number, color, mat, opts)
	local len = (b - a).Magnitude
	if len < 0.02 then
		return nil
	end
	return P(parent, look(a, b, opts and opts.Up), V3(w, h, len), color, mat, opts)
end
local rod = Kit.Rod

-- Cylinder lying flat (axis = cf.UpVector).
function Kit.Disc(parent, cf: CFrame, d: number, thickness: number, color, mat, opts)
	return P(parent, cf * ANG(0, 0, rad(90)), V3(thickness, d, d), color, mat, shaped(opts, Shape.Cylinder))
end
local disc = Kit.Disc

function Kit.DiscAlong(parent, pos: Vector3, dir: Vector3, d: number, thickness: number, color, mat, opts)
	return disc(parent, CFrame.lookAt(pos, pos + dir) * ANG(rad(-90), 0, 0), d, thickness, color, mat, opts)
end

function Kit.Ellipsoid(parent, cf: CFrame, size: Vector3, color, mat, opts)
	local p = P(parent, cf, size, color, mat, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Torus of short blocks in cf's XZ plane (angles in degrees, default full circle).
function Kit.Ring(parent, cf: CFrame, radius: number, h: number, w: number, segs: number, color, mat, opts, from: number?, to: number?)
	from, to = from or 0, to or 360
	local span = to - from
	local segLen = 2 * pi * radius * (span / 360) / segs * 1.08
	local parts = {}
	for i = 0, segs - 1 do
		local a = rad(from + span * (i + 0.5) / segs)
		local c = typeof(color) == "function" and color(i) or color
		parts[#parts + 1] = P(parent, cf * ANG(0, a, 0) * CF(0, 0, -radius), V3(segLen, h, w), c, mat, opts)
	end
	return parts
end

function Kit.CurvePts(a: Vector3, b: Vector3, bend, n: number?)
	n = n or 12
	local pts = {}
	for i = 0, n do
		local t = i / n
		local off
		if typeof(bend) == "function" then
			off = bend(t)
		elseif bend then
			off = bend * sin(pi * t)
		else
			off = V3()
		end
		pts[#pts + 1] = a:Lerp(b, t) + off
	end
	return pts
end
local curvePts = Kit.CurvePts

-- Smooth tube through points (cylinders joined by balls): pipes, tentacles, horns, cables.
function Kit.Tube(parent, pts, d0: number, d1: number, color, mat, opts)
	local n = #pts
	for i = 1, n do
		local t = (i - 1) / math.max(1, n - 1)
		ball(parent, pts[i], d0 + (d1 - d0) * t, color, mat, opts)
		if i > 1 then
			local tm = (i - 1.5) / math.max(1, n - 1)
			cyl(parent, pts[i - 1], pts[i], d0 + (d1 - d0) * tm, color, mat, opts)
		end
	end
end
local tube = Kit.Tube

function Kit.Curve(parent, a, b, bend, d0, d1, color, mat, n, opts)
	tube(parent, curvePts(a, b, bend, n or 10), d0, d1, color, mat, opts)
end

-- Sagging cable / chain between two points.
function Kit.Cable(parent, a: Vector3, b: Vector3, sag: number, d: number, color, mat, segs: number?)
	segs = segs or 8
	local pts = {}
	for i = 0, segs do
		local t = i / segs
		pts[#pts + 1] = a:Lerp(b, t) - V3(0, sag * 4 * t * (1 - t), 0)
	end
	tube(parent, pts, d, d, color, mat, { NoCollide = true })
end

-- Local-space helpers for a frame. L = point, C = CFrame (degrees), Vt = direction,
-- R = world position with the frame's rotation (+ degrees).
function Kit.Frame(cf: CFrame)
	local rot = cf.Rotation
	local function L(x, y, z)
		return cf:PointToWorldSpace(V3(x, y, z))
	end
	local function C(x, y, z, rx, ry, rz)
		return cf * CF(x, y, z) * ANG(rad(rx or 0), rad(ry or 0), rad(rz or 0))
	end
	local function Vt(x, y, z)
		return cf:VectorToWorldSpace(V3(x, y, z))
	end
	local function R(pos, rx, ry, rz)
		return CF(pos) * rot * ANG(rad(rx or 0), rad(ry or 0), rad(rz or 0))
	end
	return L, C, Vt, R
end

function Kit.Model(name: string, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Kit.Folder(name: string, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Kit.Tag(inst, name: string, attrs)
	CollectionService:AddTag(inst, name)
	for k, v in attrs or {} do
		inst:SetAttribute(k, v)
	end
	return inst
end

------------------------------------------------------------------------------------------
-- Light and particles
------------------------------------------------------------------------------------------
function Kit.Light(part, color, brightness: number, range: number, opts)
	opts = opts or {}
	local l = Instance.new(opts.Kind or "PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = opts.Shadows == true
	if opts.Face then
		l.Face = opts.Face
	end
	if opts.Angle then
		l.Angle = opts.Angle
	end
	l.Parent = part
	return l
end

-- An invisible emitter part with a ParticleEmitter configured by `props`.
function Kit.Emitter(parent, cf: CFrame, size: Vector3, texture: string, props)
	local p = P(parent, cf, size, Color3.new(), M.SmoothPlastic, { Transparency = 1, Shadow = false, NoCollide = true, Name = "Emitter" })
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = p
	return p, e
end

function Kit.FireFX(rate: number?, size: number?)
	local s = size or 1.4
	return {
		Color = ColorSequence.new(RGB(255, 205, 100), RGB(255, 70, 20)),
		LightEmission = 1,
		Size = NumberSequence.new(s, s * 0.1),
		Transparency = NumberSequence.new(0.1, 1),
		Lifetime = NumberRange.new(0.45, 0.9),
		Rate = rate or 30,
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(12, 12),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	}
end

function Kit.SmokeFX(color: Color3, rate: number?, size: number?)
	local s = size or 2
	return {
		Color = ColorSequence.new(color),
		Size = NumberSequence.new(s, s * 3.5),
		Transparency = NumberSequence.new(0.4, 1),
		Lifetime = NumberRange.new(4, 7),
		Rate = rate or 6,
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(10, 10),
		Acceleration = V3(1.5, 0.6, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
	}
end

function Kit.SparkFX(color: Color3?, rate: number?)
	return {
		Color = ColorSequence.new(color or RGB(255, 225, 140), RGB(255, 110, 30)),
		LightEmission = 1,
		Size = NumberSequence.new(0.2, 0),
		Lifetime = NumberRange.new(0.3, 0.7),
		Rate = rate or 40,
		Speed = NumberRange.new(10, 20),
		SpreadAngle = Vector2.new(50, 50),
		Acceleration = V3(0, -45, 0),
	}
end

-- Slow drifting motes over an area (embers, dust, spores, snow...).
function Kit.MotesFX(color: Color3, rate: number?, rise: number?, size: number?)
	return {
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Size = NumberSequence.new(size or 0.2, 0),
		Lifetime = NumberRange.new(5, 9),
		Rate = rate or 15,
		Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = V3(0.6, rise or 1, 0),
	}
end

------------------------------------------------------------------------------------------
-- Terrain
------------------------------------------------------------------------------------------
local terrain = Workspace.Terrain

function Kit.TBlock(cf: CFrame, size: Vector3, mat)
	terrain:FillBlock(cf, size, mat)
end

function Kit.TBall(pos: Vector3, radius: number, mat)
	terrain:FillBall(pos, radius, mat)
end

-- Vertical cylinder (cf.UpVector axis).
function Kit.TCyl(cf: CFrame, height: number, radius: number, mat)
	terrain:FillCylinder(cf, height, radius, mat)
end

function Kit.TWedge(cf: CFrame, size: Vector3, mat)
	terrain:FillWedge(cf, size, mat)
end

-- A lumpy hill: a few overlapping balls.
function Kit.THill(rng: Random, pos: Vector3, radius: number, mat, lumps: number?)
	terrain:FillBall(pos, radius, mat)
	for _ = 1, lumps or 3 do
		local offset = V3(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 0.4), rng:NextNumber(-1, 1)) * radius * 0.7
		terrain:FillBall(pos + offset, radius * rng:NextNumber(0.45, 0.8), mat)
	end
end

------------------------------------------------------------------------------------------
-- Walkable paths
------------------------------------------------------------------------------------------
-- Builds a path through `points` (each is the walking surface height). opts:
--   Width, Thickness, Color, Material
--   Fill      terrain material piled under the path (embankment), FillDepth, FillWidth
--   Rails     true = posts + rail on both sides (RailColor, RailMaterial)
--   Edge      { Color, Material } thin trim strip along both edges (glowing guides)
--   Pads      false = no round joint pads
function Kit.Path(parent, points, opts)
	local w = opts.Width or 14
	local t = opts.Thickness or 2
	local color, mat = opts.Color or RGB(70, 66, 74), opts.Material or M.Slate
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		local cf = look(a, b)
		P(parent, cf * CF(0, -t / 2, 0), V3(w, t, len + 0.4), color, mat, { Name = "Path" })
		if opts.Fill then
			local depth = opts.FillDepth or 40
			terrain:FillBlock(cf * CF(0, -t - depth / 2 + 1, 0), V3(opts.FillWidth or (w + 10), depth, len + 2), opts.Fill)
		end
		if opts.Edge then
			for _, side in { -1, 1 } do
				P(parent, cf * CF(side * (w / 2 - 0.35), 0.06, 0), V3(0.5, 0.15, len + 0.4), opts.Edge.Color, opts.Edge.Material or M.Neon, { NoCollide = true, Shadow = false, Name = "PathEdge" })
			end
		end
		if opts.Rails then
			local railColor, railMat = opts.RailColor or RGB(40, 40, 46), opts.RailMaterial or M.Metal
			for _, side in { -1, 1 } do
				local sa = a + cf.RightVector * side * (w / 2 - 0.4)
				local sb = b + cf.RightVector * side * (w / 2 - 0.4)
				rod(parent, sa + V3(0, 3, 0), sb + V3(0, 3, 0), 0.4, 0.4, railColor, railMat)
				local posts = math.max(1, math.floor(len / 8))
				for k = 0, posts do
					local p = sa:Lerp(sb, k / posts)
					P(parent, CF(p + V3(0, 1.5, 0)), V3(0.5, 3, 0.5), railColor, railMat)
				end
			end
		end
	end
	if opts.Pads ~= false then
		-- Round pads fill the gaps at the joints. On a slope a flat pad's downhill edge
		-- would stick up above the ramp (a ledge you can't walk up), so sink it by the
		-- steepest neighbouring slope.
		local function slope(a: Vector3, b: Vector3): number
			local flat = V3(b.X - a.X, 0, b.Z - a.Z).Magnitude
			return flat > 0.01 and math.abs(b.Y - a.Y) / flat or 0
		end
		for i = 2, #points - 1 do
			local s = math.max(slope(points[i - 1], points[i]), slope(points[i], points[i + 1]))
			local drop = (w / 2) * s + 0.05
			disc(parent, CF(points[i] - V3(0, t / 2 + drop, 0)), w, t, color, mat, { Name = "PathPad" })
		end
	end
end

-- Carves open air above a path so no terrain (crags, canyon walls) can ever block it.
-- Call AFTER all terrain near the path is placed.
function Kit.ClearCorridor(points, width: number, height: number?)
	local h = height or 22
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		terrain:FillBlock(look(a, b) * CF(0, h / 2 + 0.6, 0), V3(width, h, (b - a).Magnitude + 2), Enum.Material.Air)
	end
end

-- Interpolates a smooth path: Catmull-Rom through control points, `perSegment` samples.
function Kit.Smooth(points, perSegment: number?)
	local n = perSegment or 4
	local out = {}
	for i = 1, #points - 1 do
		local p0 = points[math.max(1, i - 1)]
		local p1 = points[i]
		local p2 = points[i + 1]
		local p3 = points[math.min(#points, i + 2)]
		for s = 0, n - 1 do
			local t = s / n
			local t2, t3 = t * t, t * t * t
			out[#out + 1] = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
		end
	end
	out[#out + 1] = points[#points]
	return out
end

------------------------------------------------------------------------------------------
-- Signs, lamps, relics, waystones
------------------------------------------------------------------------------------------
-- A slab with text on its FRONT face (-Z of cf).
function Kit.Sign(parent, cf: CFrame, size: Vector3, text: string, textColor: Color3, opts)
	opts = opts or {}
	local board = P(parent, cf, size, opts.Color or RGB(20, 16, 26), opts.Material or M.Slate, { Name = "Sign" })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.94, 0.86)
	label.Position = UDim2.fromScale(0.03, 0.07)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = opts.Font or Enum.Font.GothamBlack
	label.TextColor3 = textColor
	label.TextStrokeTransparency = 0.5
	label.Parent = gui
	return board
end

-- Floating title in the world (always faces the camera).
function Kit.Billboard(parent, pos: Vector3, title: string, subtitle: string?, color: Color3, size: Vector2?, maxDistance: number?)
	local anchor = P(parent, CF(pos), V3(0.4, 0.4, 0.4), Color3.new(), M.SmoothPlastic, { Transparency = 1, NoCollide = true, Shadow = false, Name = "TitleAnchor" })
	local s = size or Vector2.new(30, 7)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(s.X, 0, s.Y, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = maxDistance or 320
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, subtitle and 0.62 or 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Text = title
	t.Parent = bb
	if subtitle then
		local st = Instance.new("TextLabel")
		st.BackgroundTransparency = 1
		st.Position = UDim2.fromScale(0, 0.64)
		st.Size = UDim2.fromScale(1, 0.32)
		st.Font = Enum.Font.GothamBold
		st.TextScaled = true
		st.TextColor3 = Color3.new(1, 1, 1)
		st.TextStrokeTransparency = 0.3
		st.Text = subtitle
		st.Parent = bb
	end
	return anchor
end

function Kit.Lamp(parent, ground: Vector3, color: Color3, height: number?, poleColor: Color3?)
	local h = height or 9
	local pole = poleColor or RGB(34, 32, 40)
	disc(parent, CF(ground + V3(0, 0.4, 0)), 1.8, 0.8, pole, M.Metal)
	cyl(parent, ground, ground + V3(0, h, 0), 0.45, pole, M.Metal)
	local bulb = ball(parent, ground + V3(0, h + 0.4, 0), 1.1, color, M.Neon, { NoCollide = true, Shadow = false })
	P(parent, CF(ground + V3(0, h + 1.1, 0)), V3(1.6, 0.3, 1.6), pole, M.Metal, { NoCollide = true })
	Kit.Light(bulb, color, 1.4, 20)
	return bulb
end

-- A hidden collectible (ExplorationService handles the prompt).
function Kit.Relic(parent, relicId: string, pos: Vector3, color: Color3)
	local model = Kit.Model("Relic_" .. relicId, parent)
	disc(model, CF(pos + V3(0, 0.3, 0)), 3, 0.6, RGB(30, 26, 36), M.Slate)
	local gem = P(model, CF(pos + V3(0, 2.4, 0)) * ANG(rad(45), 0, rad(45)), V3(1.3, 1.3, 1.3), color, M.Neon, { NoCollide = true, Shadow = false, Name = "Gem" })
	Kit.Light(gem, color, 1.6, 14)
	local halo = Kit.Model("Halo", model)
	Kit.Ring(halo, CF(pos + V3(0, 2.4, 0)) * ANG(rad(70), 0, 0), 1.6, 0.12, 0.12, 14, color, M.Neon, { NoCollide = true, Shadow = false })
	halo.WorldPivot = CF(pos + V3(0, 2.4, 0))
	Kit.Tag(halo, "WSpin", { Speed = 1.2, Axis = "Y" })
	Kit.Emitter(model, CF(pos + V3(0, 2.4, 0)), V3(1, 1, 1), Kit.TEX.Spark, Kit.MotesFX(color, 6, 1.5, 0.25))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Relic"
	prompt.ActionText = "Take"
	prompt.ObjectText = "Relic"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("RelicId", relicId)
	prompt.Parent = gem
	Kit.Tag(model, "Relic", { RelicId = relicId })
	Kit.Tag(gem, "WBob", { Amp = 0.35, Speed = 2 })
	return model
end

-- A waystone: fast travel between the Forge and a boss gate (ExplorationService).
-- target = "Hub" or a region id.
function Kit.Waystone(parent, cf: CFrame, target: string, color: Color3, actionText: string, objectText: string)
	local model = Kit.Model("Waystone_" .. target, parent)
	local L, C = Kit.Frame(cf)
	disc(model, C(0, 0.4, 0), 7, 0.8, RGB(36, 32, 42), M.Slate)
	disc(model, C(0, 0.85, 0), 5.6, 0.1, color, M.Neon, { NoCollide = true, Shadow = false })
	local stone = P(model, C(0, 4.4, 0), V3(2.4, 7, 1.6), RGB(46, 42, 54), M.Slate)
	P(model, C(0, 4.4, -0.82), V3(1.2, 5, 0.1), color, M.Neon, { NoCollide = true, Shadow = false })
	local core = ball(model, L(0, 9, 0), 1.4, color, M.Neon, { NoCollide = true, Shadow = false })
	Kit.Tag(core, "WBob", { Amp = 0.4, Speed = 1.6 })
	Kit.Light(core, color, 1.5, 16)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Waystone"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Target", target)
	prompt.Parent = stone
	return model
end

return Kit
