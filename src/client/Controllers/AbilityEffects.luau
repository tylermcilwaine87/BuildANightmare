--[[
	AbilityEffects  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/AbilityEffects

	The look and sound of every Nightmare ability (client only; nothing here affects play).
	Three ways in:
	  * animation markers on the ability's own clip (NightmarePoses), so every effect lands
	    on its exact frame for everyone watching:
	      "FX_<Name>"   one of the EFFECTS below, at the limb doing the move (ActionSource)
	      "SFX_<Key>"   that sound (AudioDefinitions) at the limb
	  * WorldFX "AbilityFX" from the server, for what depends on the fight (the path a charge
	    really took, what a magnet or a lash caught): { Kind = "Trail" | "Shatter" | "Burst" |
	    "MagnetLock" | "Lash", ... }
	  * landed hits (CombatFeedback "Damage" with Source "Ability:<name>"): each ability's
	    own contact burst (ice shards, sparks, venom, fire...)
	A shield ability's look stays on the body while its shield holds (the model's
	ShieldStyle / Shield attributes): chips flying off it as it soaks hits, shattering when
	it breaks.
	Respects the Impact effects setting (Reduced: fewer pieces; Minimal: only what's needed
	to read the move) and Camera shake (through EffectsController).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))

local AbilityEffects = {}

local localPlayer = Players.LocalPlayer
local controllers
local folder: Folder

local TEX = {
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
}
local COLORS = {
	Ice = Color3.fromRGB(170, 230, 255),
	IceDeep = Color3.fromRGB(90, 170, 230),
	Frost = Color3.fromRGB(225, 245, 255),
	Electric = Color3.fromRGB(120, 220, 255),
	Volt = Color3.fromRGB(255, 240, 120),
	Fire = Color3.fromRGB(255, 130, 30),
	FireCore = Color3.fromRGB(255, 225, 140),
	Ember = Color3.fromRGB(255, 80, 20),
	Void = Color3.fromRGB(170, 90, 255),
	VoidDark = Color3.fromRGB(40, 10, 70),
	Venom = Color3.fromRGB(120, 255, 90),
	Shadow = Color3.fromRGB(60, 25, 95),
	Magnet = Color3.fromRGB(90, 170, 255),
	Steel = Color3.fromRGB(200, 205, 215),
	Lava = Color3.fromRGB(255, 96, 22),
	Basalt = Color3.fromRGB(52, 40, 46),
	Crystal = Color3.fromRGB(180, 130, 255),
	CrystalBlue = Color3.fromRGB(130, 210, 255),
	Steam = Color3.fromRGB(235, 235, 230),
}

------------------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------------------
local function level(): string
	return controllers.SettingsController:Get("ImpactEffects") or "Full"
end
-- how many pieces at this setting (Full: n, Reduced: about half, Minimal: none)
local function amount(n: number): number
	local l = level()
	if l == "Minimal" then
		return 0
	elseif l == "Reduced" then
		return math.ceil(n / 2)
	end
	return n
end

local function isMine(model: Model?): boolean
	return model ~= nil and model:GetAttribute("OwnerUserId") == localPlayer.UserId
end

local function nearCamera(position: Vector3, range: number): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= range
end

------------------------------------------------------------------------------------------
-- Building blocks
------------------------------------------------------------------------------------------
local function newPart(props, class: string?): BasePart
	local p = Instance.new(class or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = folder
	return p
end

local function sequence(a, b)
	if typeof(a) == "Color3" then
		return ColorSequence.new(a, b or a)
	end
	return NumberSequence.new(a, b or a)
end

-- A burst of particles at `position` (opts: Texture, Color, Color2, Size, Size2, Speed,
-- Life, Spread, Count, Light, Drag, Accel, Direction (a unit Vector3: the emission's axis),
-- Transparency, Rot).
local function particles(position: Vector3, opts)
	local count = amount(opts.Count or 12)
	if count <= 0 then
		return
	end
	local anchor = newPart({ Size = Vector3.one * 0.1, Transparency = 1, CFrame = CFrame.new(position) })
	local attachment = Instance.new("Attachment")
	if opts.Direction then
		attachment.CFrame = CFrame.fromRotationBetweenVectors(Vector3.yAxis, opts.Direction.Unit)
	end
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = opts.Texture or TEX.Smoke
	emitter.Color = sequence(opts.Color or Color3.new(1, 1, 1), opts.Color2)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, opts.Size or 1), NumberSequenceKeypoint.new(1, opts.Size2 or (opts.Size or 1) * 2) })
	emitter.Transparency = opts.Transparency or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	local life = opts.Life or 0.5
	emitter.Lifetime = NumberRange.new(life * 0.7, life)
	local speed = opts.Speed or 8
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	local spread = opts.Spread or 180
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.LightEmission = opts.Light or 0
	emitter.Drag = opts.Drag or 2
	emitter.Acceleration = opts.Accel or Vector3.zero
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-(opts.Rot or 90), opts.Rot or 90)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
	Debris:AddItem(anchor, life + 0.2)
end

-- A continuous emitter on a (moving) part for `duration` seconds.
local function emitterOn(part: BasePart, offset: CFrame?, opts, duration: number)
	if level() == "Minimal" and not opts.Essential then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.CFrame = offset or CFrame.identity
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = opts.Texture or TEX.Fire
	emitter.Color = sequence(opts.Color or COLORS.Fire, opts.Color2)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, opts.Size or 0.6), NumberSequenceKeypoint.new(1, opts.Size2 or 0) })
	emitter.Transparency = opts.Transparency or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	local life = opts.Life or 0.35
	emitter.Lifetime = NumberRange.new(life * 0.7, life)
	emitter.Speed = NumberRange.new((opts.Speed or 2) * 0.5, opts.Speed or 2)
	emitter.SpreadAngle = Vector2.new(opts.Spread or 30, opts.Spread or 30)
	emitter.Rate = (level() == "Reduced" and 0.5 or 1) * (opts.Rate or 40)
	emitter.LightEmission = opts.Light or 0.8
	emitter.Drag = opts.Drag or 1
	emitter.Acceleration = opts.Accel or Vector3.new(0, 4, 0)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.LockedToPart = opts.Locked == true
	emitter.Parent = attachment
	local light
	if opts.Glow then
		light = Instance.new("PointLight")
		light.Color = opts.Glow
		light.Range = opts.GlowRange or 8
		light.Brightness = opts.GlowBrightness or 2
		light.Parent = attachment
	end
	task.delay(duration, function()
		emitter.Enabled = false
		if light then
			TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 0 }):Play()
		end
	end)
	Debris:AddItem(attachment, duration + life + 0.3)
	return attachment
end

-- Pieces flung out from `position` along `direction` (spread), falling under gravity:
-- shards of ice, sparks, splinters, drops.
local function pieces(position: Vector3, direction: Vector3?, opts)
	local count = amount(opts.Count or 8)
	local travel = (direction and direction.Magnitude > 0.01) and direction.Unit or Vector3.yAxis
	local size = opts.Size or 0.25
	for i = 1, count do
		local spread = Vector3.new(math.random() - 0.5, math.random() - 0.4, math.random() - 0.5) * (opts.Spread or 1.4)
		local velocity = (travel + spread).Unit * (opts.Speed or 18) * (0.55 + math.random() * 0.6) + Vector3.new(0, opts.Up or 6, 0)
		local colors = opts.Colors or { opts.Color or Color3.new(1, 1, 1) }
		local stretch = opts.Stretch or 1
		local bit = newPart({
			Size = Vector3.new(size, size, size * stretch) * (0.7 + math.random() * 0.6),
			CFrame = CFrame.lookAt(position, position + velocity) * CFrame.Angles(math.random() * 6, 0, 0),
			Color = colors[(i % #colors) + 1],
			Material = opts.Material or Enum.Material.Neon,
			Transparency = opts.Transparency or 0,
		})
		if opts.Shape then
			bit.Shape = opts.Shape
		end
		local life = (opts.Life or 0.45) * (0.7 + math.random() * 0.6)
		local gravity = opts.Gravity or 30
		local start = os.clock()
		local spin = CFrame.Angles(math.random() * 0.4, math.random() * 0.4, 0)
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			if t >= life or not bit.Parent then
				connection:Disconnect()
				bit:Destroy()
				return
			end
			local p = position + velocity * t - Vector3.new(0, 0.5 * gravity * t * t, 0)
			bit.CFrame = (CFrame.new(p) * bit.CFrame.Rotation) * spin
			bit.Transparency = math.max(opts.Transparency or 0, (t / life) ^ 2)
		end)
	end
end

-- A flat ring rolling out over the floor (or standing, `normal` = its axis).
local function ring(position: Vector3, radius: number, color: Color3, opts)
	opts = opts or {}
	local normal = opts.Normal or Vector3.yAxis
	local base = CFrame.fromRotationBetweenVectors(Vector3.xAxis, normal) + position
	local part = newPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(opts.Thickness or 0.25, radius * 0.4, radius * 0.4),
		CFrame = base,
		Color = color,
		Material = opts.Material or Enum.Material.Neon,
		Transparency = opts.Transparency or 0.25,
	})
	local time = opts.Time or 0.4
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, time + 0.05)
end

-- A ball of light swelling and fading (a flash), with a light on it.
local function flash(position: Vector3, size: number, color: Color3, time: number?)
	time = time or 0.22
	local ball = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.4, CFrame = CFrame.new(position), Color = color, Material = Enum.Material.Neon, Transparency = 0.15 })
	TweenService:Create(ball, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = size * 3
	light.Brightness = 4
	light.Parent = ball
	TweenService:Create(light, TweenInfo.new(time), { Brightness = 0 }):Play()
	Debris:AddItem(ball, time + 0.05)
end

-- A jagged bolt of lightning between two points.
local function bolt(from: Vector3, to: Vector3, color: Color3, width: number?, time: number?)
	local points = { from }
	local length = (to - from).Magnitude
	local steps = math.clamp(math.floor(length / 1.2), 2, 8)
	for i = 1, steps - 1 do
		local jitter = length * 0.12
		table.insert(points, from:Lerp(to, i / steps) + Vector3.new((math.random() - 0.5) * jitter, (math.random() - 0.5) * jitter, (math.random() - 0.5) * jitter))
	end
	table.insert(points, to)
	width = (width or 0.14) * 1.6
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local segment = newPart({ Size = Vector3.new(width, width, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color, Material = Enum.Material.Neon })
		TweenService:Create(segment, TweenInfo.new(time or 0.18), { Transparency = 1 }):Play()
		Debris:AddItem(segment, (time or 0.18) + 0.03)
	end
end

-- A living rope between two moving points for `time` seconds (a tentacle's whip): segments
-- from getFrom() to getTo(), thinning toward the end, a wave running down it; `reach` (t ->
-- 0..1) is how far along it has got. Returns nothing; it cleans itself up.
local function rope(getFrom, getTo, time: number, opts)
	local count = 14
	local segments = {}
	for i = 1, count do
		segments[i] = newPart({ Size = Vector3.one * 0.1, Color = opts.Color, Material = opts.Material or Enum.Material.SmoothPlastic })
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		local a, b = getFrom(), getTo()
		if t >= time or not a or not b then
			connection:Disconnect()
			for _, segment in segments do
				segment:Destroy()
			end
			return
		end
		local along = b - a
		local length = along.Magnitude
		local direction = length > 0.01 and along.Unit or Vector3.yAxis
		local side = direction:Cross(Vector3.yAxis)
		side = side.Magnitude > 0.01 and side.Unit or Vector3.xAxis
		local up = side:Cross(direction)
		local reach = opts.Reach and opts.Reach(t) or 1
		local amplitude = (opts.Wave or 0.35) * (1 - t / time * 0.6)
		local function point(k: number): Vector3
			local wave = math.sin(k * 9 - t * 26) * amplitude * math.sin(k * math.pi)
			return a + along * k * reach + up * wave + side * wave * 0.4
		end
		local width = opts.Width or 0.42
		for i, segment in segments do
			local p0, p1 = point((i - 1) / count), point(i / count)
			local w = width * (1 - (i - 1) / count * 0.7)
			segment.Size = Vector3.new(w, w, (p1 - p0).Magnitude + w * 0.5)
			segment.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
		end
	end)
end

-- A trail of light hanging in the air along a list of points (a claw's arc, a slash mark).
local function arc(points, color: Color3, width: number, time: number)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local k = i / (#points - 1)
		local w = width * math.sin(k * math.pi) + 0.05
		local segment = newPart({ Size = Vector3.new(w, w * 0.4, (b - a).Magnitude + w * 0.5), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color, Material = Enum.Material.Neon, Transparency = 0.1 })
		TweenService:Create(segment, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(w * 0.2, w * 0.1, segment.Size.Z) }):Play()
		Debris:AddItem(segment, time + 0.05)
	end
end

-- A flat mark left on the floor (frost, scorch, venom) that fades.
local FLOOR_PARAMS = RaycastParams.new()
FLOOR_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
local function floorBelow(position: Vector3, depth: number?): RaycastResult?
	local ignore = { folder }
	for _, tag in { "Nightmare", "Enemy" } do
		for _, model in CollectionService:GetTagged(tag) do
			table.insert(ignore, model)
		end
	end
	if localPlayer.Character then
		table.insert(ignore, localPlayer.Character)
	end
	FLOOR_PARAMS.FilterDescendantsInstances = ignore
	return Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -(depth or 12), 0), FLOOR_PARAMS)
end
local function floorMark(position: Vector3, size: number, color: Color3, material, time: number, transparency: number?)
	local hit = floorBelow(position)
	if not hit then
		return nil
	end
	local mark = newPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, size, size),
		CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, math.random() * 6, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0.3,
	})
	task.delay(time * 0.6, function()
		if mark.Parent then
			TweenService:Create(mark, TweenInfo.new(time * 0.4), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(mark, time + 0.05)
	return mark
end

------------------------------------------------------------------------------------------
-- Where things are on a Nightmare (any parts combination)
------------------------------------------------------------------------------------------
local function rootOf(model: Model): BasePart?
	return model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The visual pieces of a slot ("<Slot>_<n>", NightmareAssembler).
local function slotParts(model: Model, slot: string)
	local list = {}
	local pattern = "^" .. slot .. "_%d+$"
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name:match(pattern) and d.Transparency < 0.95 then
			table.insert(list, d)
		end
	end
	return list
end

-- The far end of a limb (an arm's claw, a tail's tip, a wing's tip): the point of its
-- pieces farthest from its joint. Returns the point and the piece it's on.
local function limbTip(model: Model, slot: string): (Vector3?, BasePart?)
	local base = model:FindFirstChild(slot .. "_Root")
	if not base then
		return nil, nil
	end
	local best, bestDistance, bestPart = nil, -1, nil
	for _, p in slotParts(model, slot) do
		local offset = p.Position - base.Position
		local dir = offset.Magnitude > 0.01 and offset.Unit or -base.CFrame.UpVector
		local extent = (math.abs(p.CFrame.XVector:Dot(dir)) * p.Size.X + math.abs(p.CFrame.YVector:Dot(dir)) * p.Size.Y + math.abs(p.CFrame.ZVector:Dot(dir)) * p.Size.Z) / 2
		local distance = offset:Dot(dir) + extent
		if distance > bestDistance then
			best, bestDistance, bestPart = p.Position + dir * extent, distance, p
		end
	end
	return best, bestPart
end

-- The front of the head (its mouth / visor / horns), and which way it faces.
local function headFront(model: Model): (Vector3?, Vector3?)
	local base = model:FindFirstChild("Head_Root")
	if not base then
		return nil, nil
	end
	local forward = base.CFrame.LookVector
	local front, sum, n = -math.huge, Vector3.zero, 0
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and (p.Name:match("^Head_%d+$")) and p.Transparency < 0.95 then
			local extent = (math.abs(p.CFrame.XVector:Dot(forward)) * p.Size.X + math.abs(p.CFrame.YVector:Dot(forward)) * p.Size.Y + math.abs(p.CFrame.ZVector:Dot(forward)) * p.Size.Z) / 2
			front = math.max(front, (p.Position - base.Position):Dot(forward) + extent)
			sum += p.Position
			n += 1
		end
	end
	if n == 0 then
		return nil, nil
	end
	local center = sum / n
	return center + forward * (front - (center - base.Position):Dot(forward)), forward
end

-- Where a move's effect comes from: the limb doing it.
local function sourcePoint(model: Model): (Vector3?, BasePart?)
	local source = model:GetAttribute("ActionSource") or ""
	if source == "Head" then
		local point = headFront(model)
		return point, model:FindFirstChild("Head_Root") :: BasePart?
	elseif source == "RightArm" or source == "LeftArm" or source == "Tail" or source == "Back" then
		return limbTip(model, source)
	end
	local root = rootOf(model)
	return root and root.Position, root
end

local function feet(model: Model): { Vector3 }
	local root = rootOf(model)
	local list = {}
	if not root then
		return list
	end
	for _, name in { "Legs_L", "Legs_R", "Legs_FL", "Legs_FR", "Legs_BL", "Legs_BR" } do
		local leg = model:FindFirstChild(name)
		if leg then
			local hit = floorBelow(leg.Position, 14)
			table.insert(list, hit and hit.Position or leg.Position)
		end
	end
	if #list == 0 then
		local hit = floorBelow(root.Position, 14)
		table.insert(list, hit and hit.Position or root.Position)
	end
	return list
end

local function groundUnder(model: Model): Vector3?
	local root = rootOf(model)
	if not root then
		return nil
	end
	local hit = floorBelow(root.Position, 16)
	return hit and hit.Position or root.Position - Vector3.new(0, root.Size.Y / 2, 0)
end

-- The body this one is holding in its jaws / on its sting (the server marks it Gripped).
local function heldBy(model: Model, near: Vector3): Model?
	local best, bestDistance = nil, 8
	for _, tag in { "Nightmare", "Enemy" } do
		for _, other in CollectionService:GetTagged(tag) do
			local root = other ~= model and other:GetAttribute("Gripped") and rootOf(other)
			if root and (root.Position - near).Magnitude < bestDistance then
				best, bestDistance = other, (root.Position - near).Magnitude
			end
		end
	end
	return best
end

local function play(sound: string, position: Vector3?)
	controllers.AudioController:Play(sound, position)
end

local function shake(model: Model, duration: number, strength: number, range: number?)
	local root = rootOf(model)
	local character = localPlayer.Character
	local mine = character and character:FindFirstChild("HumanoidRootPart")
	if isMine(model) or (root and mine and (mine.Position - root.Position).Magnitude < (range or 18)) then
		controllers.EffectsController:Shake(duration, strength)
	end
end

------------------------------------------------------------------------------------------
-- Trails on a limb (claw arcs)
------------------------------------------------------------------------------------------
local trails = setmetatable({}, { __mode = "k" }) -- [model] = trail
local TRAIL_STYLE = {
	RustySlash = { Color = Color3.fromRGB(255, 200, 120), Light = 0.6 },
	DemonRend = { Color = COLORS.Fire, Light = 1 },
	MeteorFist = { Color = COLORS.Fire, Light = 1 },
}
local function trailOn(model: Model, abilityId: string)
	local _, part = sourcePoint(model)
	if not part then
		return
	end
	local style = TRAIL_STYLE[abilityId] or { Color = Color3.new(1, 1, 1), Light = 0.5 }
	local base = model:FindFirstChild((model:GetAttribute("ActionSource") or "") .. "_Root")
	local tip = select(1, sourcePoint(model))
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	local towardBase = base and (base.Position - tip).Unit or Vector3.yAxis
	a0.WorldPosition = tip
	a1.WorldPosition = tip + towardBase * 0.9
	a0.Parent, a1.Parent = part, part
	a0.WorldPosition, a1.WorldPosition = tip, tip + towardBase * 0.9
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(style.Color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.18
	trail.LightEmission = style.Light
	trail.WidthScale = NumberSequence.new(1, 0.3)
	trail.Parent = part
	local old = trails[model]
	if old then
		old.Enabled = false
	end
	trails[model] = trail
	Debris:AddItem(a0, 3)
	Debris:AddItem(a1, 3)
	Debris:AddItem(trail, 3)
end
local function trailOff(model: Model)
	local trail = trails[model]
	if trail then
		trail.Enabled = false
		trails[model] = nil
	end
end

------------------------------------------------------------------------------------------
-- Shields that stay on the body while they hold
------------------------------------------------------------------------------------------
local shields = setmetatable({}, { __mode = "k" }) -- [model] = { Parts = {...}, Style = id }
local function clearShield(model: Model, shatter: boolean)
	local shield = shields[model]
	if not shield then
		return
	end
	shields[model] = nil
	for _, part in shield.Parts do
		if part.Parent then
			if shatter then
				pieces(part.Position, (part.Position - (rootOf(model) and rootOf(model).Position or part.Position)), { Count = 3, Colors = { part.Color }, Material = part.Material, Size = 0.3, Speed = 16, Life = 0.6, Gravity = 40 })
			end
			TweenService:Create(part, TweenInfo.new(shatter and 0.12 or 0.4), { Transparency = 1, Size = part.Size * (shatter and 1.3 or 0.6) }):Play()
			Debris:AddItem(part, 0.45)
		end
	end
	local root = rootOf(model)
	if shatter and root then
		local sound = shield.Style == "CrystalBarrier" and "GlassShatter" or shield.Style == "MagmaShell" and "RockDebris" or "MetalClang"
		play(sound, root.Position)
	end
end

-- Pieces of shield standing round the body, riding it (welded to the root).
local function shieldPieces(model: Model, style: string, build)
	local root = rootOf(model)
	if not root then
		return
	end
	clearShield(model, false)
	local list = {}
	build(root, list)
	shields[model] = { Parts = list, Style = style }
	-- (gone with the shield; never left behind)
	task.delay(8, function()
		if shields[model] and shields[model].Parts == list then
			clearShield(model, false)
		end
	end)
end

local function weldTo(root: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = root, part
	weld.Parent = part
end

------------------------------------------------------------------------------------------
-- EFFECTS (by marker name "FX_<Name>")
------------------------------------------------------------------------------------------
local EFFECTS = {}

-- FROST ------------------------------------------------------------------------------
function EFFECTS.FrostBreath(model)
	local mouth, forward = headFront(model)
	if not mouth then
		return
	end
	for _, side in { -1, 1 } do
		local right = forward:Cross(Vector3.yAxis).Unit
		particles(mouth + right * side * 0.25, { Color = COLORS.Frost, Size = 0.5, Size2 = 1.8, Speed = 6, Life = 0.7, Spread = 18, Count = 8, Direction = (forward - Vector3.yAxis * 0.5 + right * side * 0.3), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }) })
	end
	particles(mouth, { Texture = TEX.Sparkle, Color = COLORS.Ice, Size = 0.3, Size2 = 0.05, Speed = 4, Life = 0.6, Count = 6, Light = 1 })
end

function EFFECTS.FrostScrape(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local list = feet(model)
	local at = list[1]
	local back = -root.CFrame.LookVector
	pieces(at + Vector3.new(0, 0.2, 0), back + Vector3.yAxis * 0.4, { Count = 7, Colors = { COLORS.Ice, COLORS.Frost, COLORS.IceDeep }, Material = Enum.Material.Ice, Size = 0.22, Speed = 14, Life = 0.5, Up = 8 })
	particles(at, { Color = COLORS.Frost, Size = 0.6, Size2 = 1.6, Speed = 5, Life = 0.5, Count = 6, Direction = back + Vector3.yAxis })
	floorMark(at - root.CFrame.LookVector * 0.6, 1.6, COLORS.Ice, Enum.Material.Ice, 2.2, 0.35)
end

function EFFECTS.FrostAura(model)
	local head = model:FindFirstChild("Head_Root")
	if head then
		emitterOn(head, CFrame.new(0, 0.5, -0.6), { Texture = TEX.Smoke, Color = COLORS.Frost, Size = 0.8, Size2 = 1.8, Life = 0.5, Speed = 1, Spread = 180, Rate = 30, Light = 0.2, Accel = Vector3.zero, Locked = false, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }) }, 0.5)
		emitterOn(head, CFrame.new(0, 0.5, -0.6), { Texture = TEX.Sparkle, Color = COLORS.Ice, Size = 0.35, Size2 = 0, Life = 0.4, Speed = 2, Spread = 180, Rate = 25, Light = 1, Accel = Vector3.zero }, 0.5)
	end
end

function EFFECTS.HornToss(model)
	local mouth, forward = headFront(model)
	if not mouth then
		return
	end
	flash(mouth + Vector3.new(0, 0.6, 0), 3, COLORS.Ice)
	pieces(mouth, forward + Vector3.yAxis * 1.4, { Count = 10, Colors = { COLORS.Ice, COLORS.Frost, COLORS.IceDeep }, Material = Enum.Material.Ice, Size = 0.3, Speed = 20, Up = 10, Life = 0.6 })
	play("IceShatter", mouth)
end

function EFFECTS.IceSkid(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local look = root.CFrame.LookVector
	for _, at in feet(model) do
		pieces(at + Vector3.new(0, 0.2, 0), look + Vector3.yAxis * 0.5, { Count = 6, Colors = { COLORS.Ice, COLORS.Frost }, Material = Enum.Material.Ice, Size = 0.2, Speed = 16, Up = 6, Life = 0.45 })
		particles(at, { Color = COLORS.Frost, Size = 0.8, Size2 = 2.2, Speed = 7, Life = 0.6, Count = 6, Direction = look + Vector3.yAxis * 0.6, Spread = 40 })
	end
	shake(model, 0.15, 0.08)
end

-- ELECTRIC ---------------------------------------------------------------------------
function EFFECTS.JawArcs(model)
	local mouth = headFront(model)
	local head = model:FindFirstChild("Head_Root")
	if not mouth or not head then
		return
	end
	for i = 0, 5 do
		task.delay(i * 0.05, function()
			local center = head.Position:Lerp(mouth, 0.6)
			local a = center + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6
			local b = center + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6
			bolt(a, b, i % 2 == 0 and COLORS.Electric or COLORS.Volt, 0.08, 0.1)
		end)
	end
	particles(mouth, { Texture = TEX.Sparkle, Color = COLORS.Volt, Size = 0.35, Size2 = 0, Speed = 6, Life = 0.3, Count = 8, Light = 1 })
end

function EFFECTS.ShockSnap(model)
	local mouth = headFront(model)
	if not mouth then
		return
	end
	flash(mouth, 3.2, COLORS.Volt, 0.18)
	for _ = 1, 5 do
		local dir = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5).Unit
		bolt(mouth, mouth + dir * (1.5 + math.random() * 1.5), COLORS.Electric, 0.1, 0.15)
	end
	play("Zap", mouth)
	shake(model, 0.1, 0.1)
end

function EFFECTS.Zap(model)
	local mouth = headFront(model)
	if not mouth then
		return
	end
	local victim = heldBy(model, mouth)
	local victimRoot = victim and rootOf(victim)
	local to = victimRoot and victimRoot.Position or mouth + (Vector3.new(math.random() - 0.5, -0.3, math.random() - 0.5)) * 2
	bolt(mouth, to, COLORS.Volt, 0.16, 0.2)
	bolt(mouth, to + Vector3.new(0, 0.5, 0), COLORS.Electric, 0.09, 0.2)
	if victimRoot then
		flash(victimRoot.Position, 2.4, COLORS.Electric, 0.15)
		particles(victimRoot.Position, { Texture = TEX.Sparkle, Color = COLORS.Volt, Size = 0.4, Size2 = 0, Speed = 10, Life = 0.35, Count = 12, Light = 1 })
		controllers.EffectsController:Flash(victim)
	end
	play("Zap", mouth)
	play("Shock", to)
end

function EFFECTS.Discharge(model)
	local mouth, forward = headFront(model)
	if not mouth then
		return
	end
	flash(mouth, 5, COLORS.Volt, 0.25)
	for i = -2, 2 do
		local dir = (CFrame.fromAxisAngle(Vector3.yAxis, math.rad(i * 12)):VectorToWorldSpace(forward) + Vector3.new(0, (math.random() - 0.4) * 0.4, 0)).Unit
		bolt(mouth, mouth + dir * (6 + math.random() * 4), i % 2 == 0 and COLORS.Volt or COLORS.Electric, 0.16, 0.25)
	end
	ring(mouth, 5, COLORS.Electric, { Normal = forward, Time = 0.3, Thickness = 0.2 })
	shake(model, 0.2, 0.18, 24)
end

-- VISOR ------------------------------------------------------------------------------
function EFFECTS.VisorCharge(model)
	local head = model:FindFirstChild("Head_Root")
	local mouth, forward = headFront(model)
	if not head or not mouth then
		return
	end
	local offset = head.CFrame:PointToObjectSpace(mouth + forward * 0.1 + Vector3.new(0, 0.15, 0))
	local attachment = Instance.new("Attachment")
	attachment.Position = offset
	attachment.Parent = head
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 80)
	light.Range = 4
	light.Brightness = 0
	light.Parent = attachment
	TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 6, Range = 12 }):Play()
	local glow = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2, Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.Neon, Transparency = 0.2 })
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 0.55 or not attachment.Parent then
			connection:Disconnect()
			glow:Destroy()
			return
		end
		glow.CFrame = CFrame.new(attachment.WorldPosition)
		glow.Size = Vector3.one * (0.2 + 1.1 * (t / 0.55) ^ 2)
		if math.random() < 0.35 then
			-- sparks drawn in toward the visor
			local from = attachment.WorldPosition + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3
			bolt(from, attachment.WorldPosition, Color3.fromRGB(255, 190, 110), 0.05, 0.08)
		end
	end)
	Debris:AddItem(attachment, 1.6)
end

function EFFECTS.VisorBeam(model, action)
	local def = AbilityDefinitions.Get(action:gsub("^Ability_", ""):gsub("_Left$", ""))
	local head = model:FindFirstChild("Head_Root")
	if not head or not def then
		return
	end
	local duration = (def.Ticks or 4) * (def.Interval or 0.2)
	local fullRange = def.Range or 12
	local range = fullRange
	local core = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(range, 0.5, 0.5), Color = Color3.fromRGB(255, 245, 220), Material = Enum.Material.Neon })
	local outer = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(range, 1.4, 1.4), Color = Color3.fromRGB(255, 130, 40), Material = Enum.Material.Neon, Transparency = 0.55 })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = range
	light.Brightness = 2
	light.Parent = core
	local start = os.clock()
	local lastSpark = 0
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > duration or not head.Parent then
			connection:Disconnect()
			TweenService:Create(core, TweenInfo.new(0.15), { Transparency = 1, Size = Vector3.new(range, 0.05, 0.05) }):Play()
			TweenService:Create(outer, TweenInfo.new(0.15), { Transparency = 1, Size = Vector3.new(range, 0.1, 0.1) }):Play()
			Debris:AddItem(core, 0.2)
			Debris:AddItem(outer, 0.2)
			return
		end
		local mouth, forward = headFront(model)
		if not mouth then
			return
		end
		local flicker = 1 + math.sin(t * 60) * 0.12
		-- it glares DOWN at them: from the visor to waist height on whatever's at the far end
		-- (a head sits well above a small enemy; the sweep is the head's own)
		local flat = Vector3.new(forward.X, 0, forward.Z)
		flat = flat.Magnitude > 0.01 and flat.Unit or forward
		local floor = floorBelow(mouth + flat * fullRange, 14)
		local aim = mouth + flat * fullRange
		if floor then
			aim = Vector3.new(aim.X, floor.Position.Y + 1.5, aim.Z)
		end
		forward = (aim - mouth).Unit
		range = (aim - mouth).Magnitude
		local mid = mouth + forward * (range / 2)
		local along = CFrame.lookAt(mid, mid + forward) * CFrame.Angles(0, math.rad(90), 0)
		core.CFrame, outer.CFrame = along, along
		core.Size = Vector3.new(range, 0.5 * flicker, 0.5 * flicker)
		outer.Size = Vector3.new(range, 1.4 * flicker, 1.4 * flicker)
		if t - lastSpark > 0.07 then
			lastSpark = t
			local endPoint = mouth + forward * range
			local hit = floorBelow(endPoint, 8)
			local at = hit and (endPoint.Y - hit.Position.Y < 4) and hit.Position or endPoint
			pieces(at, Vector3.yAxis + forward * -0.5, { Count = 3, Colors = { Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 140, 40) }, Size = 0.1, Stretch = 4, Speed = 14, Life = 0.3 })
			if hit then
				floorMark(hit.Position, 0.9, Color3.fromRGB(30, 22, 18), Enum.Material.Slate, 2.5, 0.35)
			end
		end
	end)
end

function EFFECTS.Vent(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local head = model:FindFirstChild("Head_Root")
	local at = head and head.Position + Vector3.new(0, 0.8, 0) or root.Position + Vector3.new(0, root.Size.Y * 0.4, 0)
	for _, side in { -1, 1 } do
		particles(at + root.CFrame.RightVector * side * 0.8, { Color = COLORS.Steam, Size = 0.6, Size2 = 2.6, Speed = 8, Life = 0.9, Spread = 15, Count = 10, Direction = Vector3.yAxis + root.CFrame.RightVector * side * 0.5 + (-root.CFrame.LookVector * 0.3), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }) })
	end
end

-- CLAWS ------------------------------------------------------------------------------
function EFFECTS.TrailOn(model, action)
	trailOn(model, (action:gsub("^Ability_", ""):gsub("_Left$", "")))
end

function EFFECTS.TrailOff(model)
	trailOff(model)
end

function EFFECTS.Sparks(model)
	for _, side in { "RightArm", "LeftArm" } do
		local tip = limbTip(model, side)
		if tip then
			pieces(tip, Vector3.yAxis, { Count = 6, Colors = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 160, 50) }, Size = 0.1, Stretch = 4, Speed = 18, Life = 0.35 })
		end
	end
	local root = rootOf(model)
	if root then
		flash(root.Position + root.CFrame.LookVector * 1.5 + Vector3.new(0, 0.5, 0), 1.6, Color3.fromRGB(255, 220, 140), 0.12)
	end
end

-- TENTACLE ---------------------------------------------------------------------------
-- The lash: the tentacle's end shoots out to the whole of its reach (the limb is far shorter
-- than the lash lands) and CRACKS out there, then snaps back. (What it catches is hauled in
-- on "Lash", below.)
function EFFECTS.WhipCrack(model, action)
	local tip = sourcePoint(model)
	local root = rootOf(model)
	local def = AbilityDefinitions.Get(action:gsub("^Ability_", ""):gsub("_Left$", ""))
	if not tip or not root then
		return
	end
	local look = root.CFrame.LookVector
	local range = (def and def.Range or 11) + root.Size.Z / 2
	local crack = Vector3.new(root.Position.X, root.Position.Y, root.Position.Z) + look * range
	rope(function()
		return (sourcePoint(model))
	end, function()
		return crack
	end, 0.3, {
		Color = COLORS.Shadow,
		Wave = 0.25,
		Reach = function(t)
			return t < 0.07 and t / 0.07 or math.max(1 - (t - 0.07) / 0.23, 0)
		end,
	})
	task.delay(0.06, function()
		flash(crack, 2.2, COLORS.Void, 0.15)
		ring(crack, 3, COLORS.Void, { Normal = look, Time = 0.25, Thickness = 0.15 })
		pieces(crack, look, { Count = 8, Colors = { COLORS.Shadow, COLORS.VoidDark }, Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Ball, Size = 0.18, Speed = 12, Life = 0.5 })
	end)
	shake(model, 0.08, 0.06)
end

-- What the lash caught: the rope runs from the limb to the victim for as long as it's held,
-- bands of it coiled round the body.
local function lash(data)
	local model, target = data.Model, data.Target
	if typeof(model) ~= "Instance" or typeof(target) ~= "Instance" then
		return
	end
	local targetRoot = rootOf(target)
	if not targetRoot then
		return
	end
	local time = math.clamp(tonumber(data.Time) or 0.75, 0.1, 3)
	rope(function()
		return (sourcePoint(model))
	end, function()
		return targetRoot.Parent and targetRoot.Position or nil
	end, time, { Color = COLORS.Shadow, Wave = 0.18 })
	local bands = {}
	local _, size = target:GetBoundingBox()
	local across = math.max(size.X, size.Z) + 0.35
	for i = 1, 3 do
		bands[i] = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, across, across), Color = i == 2 and COLORS.Void or COLORS.Shadow, Material = i == 2 and Enum.Material.Neon or Enum.Material.SmoothPlastic })
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() - start >= time or not targetRoot.Parent then
			connection:Disconnect()
			for _, band in bands do
				band:Destroy()
			end
			return
		end
		for i, band in bands do
			local height = (i - 2) * size.Y * 0.28
			band.CFrame = targetRoot.CFrame * CFrame.new(0, height, 0) * CFrame.Angles(0, 0, math.rad(90 + (i - 2) * 12))
		end
	end)
	play("TentacleSlime", targetRoot.Position)
end

-- DEMON ------------------------------------------------------------------------------
function EFFECTS.Ignite(model, action)
	local _, part = sourcePoint(model)
	if not part then
		return
	end
	local def = AbilityDefinitions.Get(action:gsub("^Ability_", ""):gsub("_Left$", ""))
	local length = def and AbilityDefinitions.Length(def) or 1.2
	emitterOn(part, CFrame.identity, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 0.9, Size2 = 0.1, Life = 0.35, Speed = 2, Spread = 25, Rate = 60, Light = 1, Accel = Vector3.new(0, 6, 0), Glow = COLORS.Fire, GlowRange = 10 }, length - 0.2)
	local tip = sourcePoint(model)
	if tip then
		flash(tip, 2, COLORS.Fire, 0.2)
	end
end

local function rend(model, from: Vector3, to: Vector3, bulge: Vector3)
	local root = rootOf(model)
	if not root then
		return
	end
	local origin = root.Position + root.CFrame.LookVector * 2.4 + Vector3.new(0, 0.6, 0)
	local cf = root.CFrame.Rotation
	for claw = -1, 1 do
		local shift = cf:VectorToWorldSpace(Vector3.new(0, claw * 0.35, claw * 0.1))
		local points = {}
		for i = 0, 8 do
			local k = i / 8
			local p = from:Lerp(to, k) + bulge * math.sin(k * math.pi)
			table.insert(points, origin + cf:VectorToWorldSpace(p) + shift)
		end
		arc(points, claw == 0 and COLORS.FireCore or COLORS.Fire, 0.28, 0.35)
	end
	particles(origin, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1, Size2 = 0.2, Speed = 6, Life = 0.4, Count = 10, Light = 1 })
end
function EFFECTS.RendA(model)
	rend(model, Vector3.new(1.6, 1.8, 0), Vector3.new(-1.6, -1.2, 0), Vector3.new(0, 0, -0.6))
end
function EFFECTS.RendB(model)
	rend(model, Vector3.new(-1.6, 1.8, 0), Vector3.new(1.6, -1.2, 0), Vector3.new(0, 0, -0.6))
end
function EFFECTS.RendUp(model)
	rend(model, Vector3.new(0.3, -1.6, 0), Vector3.new(-0.2, 2.6, 0), Vector3.new(0, 0, -0.9))
end

function EFFECTS.FireBurst(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local at = root.Position + root.CFrame.LookVector * 2.6 + Vector3.new(0, 0.8, 0)
	flash(at, 4, COLORS.Fire, 0.25)
	particles(at, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.6, Size2 = 0.3, Speed = 12, Life = 0.5, Count = 22, Light = 1, Drag = 3 })
	pieces(at, Vector3.yAxis, { Count = 10, Colors = { COLORS.Fire, COLORS.FireCore }, Size = 0.14, Speed = 18, Up = 12, Life = 0.7, Gravity = 20 })
	shake(model, 0.15, 0.14)
end

-- MAGNET -----------------------------------------------------------------------------
function EFFECTS.MagnetCharge(model)
	local _, part = sourcePoint(model)
	if not part then
		return
	end
	emitterOn(part, CFrame.identity, { Texture = TEX.Sparkle, Color = COLORS.Magnet, Size = 0.4, Size2 = 0, Life = 0.25, Speed = 3, Spread = 180, Rate = 50, Light = 1, Accel = Vector3.zero, Glow = COLORS.Magnet, GlowRange = 8 }, 0.4)
	for i = 0, 4 do
		task.delay(i * 0.08, function()
			local tip = sourcePoint(model)
			if tip then
				bolt(tip, tip + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2, COLORS.Magnet, 0.06, 0.08)
			end
		end)
	end
end

local function magnetLock(data)
	local model, target = data.Model, data.Target
	if typeof(model) ~= "Instance" or typeof(target) ~= "Instance" then
		return
	end
	local targetRoot = rootOf(target)
	if not targetRoot then
		return
	end
	local time = math.clamp(tonumber(data.Time) or 0.45, 0.1, 2) + 0.2
	local beam = newPart({ Size = Vector3.new(0.3, 0.3, 1), Color = COLORS.Magnet, Material = Enum.Material.Neon, Transparency = 0.2 })
	local start = os.clock()
	local lastArc = 0
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		local tip = sourcePoint(model)
		if t > time or not tip or not targetRoot.Parent then
			connection:Disconnect()
			beam:Destroy()
			return
		end
		local to = targetRoot.Position
		beam.Size = Vector3.new(0.18 + 0.12 * math.sin(t * 50), 0.18, (to - tip).Magnitude)
		beam.CFrame = CFrame.lookAt((tip + to) / 2, to)
		if t - lastArc > 0.06 then
			lastArc = t
			bolt(tip, to, Color3.fromRGB(180, 220, 255), 0.07, 0.07)
		end
	end)
	local tip = sourcePoint(model)
	if tip then
		flash(tip, 2, COLORS.Magnet, 0.15)
	end
	flash(targetRoot.Position, 3, COLORS.Magnet, 0.2)
	-- dragged along the floor: dust behind them
	for i = 1, 5 do
		task.delay(i * 0.08, function()
			if targetRoot.Parent then
				controllers.EffectsController:Dust(targetRoot.Position - Vector3.new(0, targetRoot.Size.Y / 2, 0), 0.7)
			end
		end)
	end
end

-- HAMMER -----------------------------------------------------------------------------
function EFFECTS.HammerGlow(model)
	local _, part = sourcePoint(model)
	if part then
		emitterOn(part, CFrame.identity, { Texture = TEX.Sparkle, Color = Color3.fromRGB(255, 170, 70), Size = 0.4, Size2 = 0, Life = 0.3, Speed = 4, Spread = 180, Rate = 30, Light = 1, Glow = Color3.fromRGB(255, 150, 50), GlowRange = 12, GlowBrightness = 3 }, 0.55)
	end
end

function EFFECTS.GroundCrack(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local tip = sourcePoint(model) or root.Position + root.CFrame.LookVector * 4
	local hit = floorBelow(tip, 14)
	local at = hit and hit.Position or tip
	-- cracks running out from the impact
	for i = 1, amount(8) do
		local angle = (i / 8) * math.pi * 2 + math.random() * 0.5
		local length = 2.5 + math.random() * 3
		local from = at
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		for _ = 1, 3 do
			local to = from + (direction + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.6).Unit * (length / 3)
			local crack = newPart({ Size = Vector3.new(0.16, 0.05, (to - from).Magnitude), CFrame = CFrame.lookAt((from + to) / 2, to) + Vector3.new(0, 0.05, 0), Color = Color3.fromRGB(20, 16, 14), Material = Enum.Material.SmoothPlastic })
			local glow = newPart({ Size = Vector3.new(0.06, 0.06, (to - from).Magnitude), CFrame = crack.CFrame + Vector3.new(0, 0.02, 0), Color = Color3.fromRGB(255, 140, 50), Material = Enum.Material.Neon, Transparency = 0.2 })
			TweenService:Create(glow, TweenInfo.new(0.8), { Transparency = 1 }):Play()
			task.delay(1.6, function()
				TweenService:Create(crack, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end)
			Debris:AddItem(crack, 2.3)
			Debris:AddItem(glow, 0.85)
			from = to
		end
	end
end

-- WINGS ------------------------------------------------------------------------------
function EFFECTS.WingGust(model)
	local ground = groundUnder(model)
	if ground then
		controllers.EffectsController:Dust(ground, 1.2)
		ring(ground + Vector3.new(0, 0.2, 0), 4, Color3.fromRGB(230, 225, 215), { Time = 0.35, Transparency = 0.6, Material = Enum.Material.SmoothPlastic })
	end
	for _, tip in { limbTip(model, "Back") } do
		if typeof(tip) == "Vector3" then
			particles(tip, { Color = Color3.fromRGB(220, 220, 220), Size = 0.4, Size2 = 1.4, Speed = 6, Life = 0.4, Count = 5, Direction = -Vector3.yAxis, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }) })
		end
	end
end

function EFFECTS.Ghosts(model)
	for i = 0, 3 do
		task.delay(i * 0.06, function()
			if model.Parent then
				controllers.EffectsController:Afterimage(model)
			end
		end)
	end
end

function EFFECTS.VoidGather(model)
	local root = rootOf(model)
	if not root then
		return
	end
	for i = 1, amount(14) do
		task.delay(math.random() * 0.2, function()
			if not root.Parent then
				return
			end
			local from = root.Position + Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5).Unit * (3 + math.random() * 2)
			local mote = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * (0.15 + math.random() * 0.2), CFrame = CFrame.new(from), Color = i % 3 == 0 and COLORS.VoidDark or COLORS.Void, Material = Enum.Material.Neon })
			TweenService:Create(mote, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(root.Position), Size = Vector3.one * 0.05 }):Play()
			Debris:AddItem(mote, 0.25)
		end)
	end
	local light = Instance.new("PointLight")
	light.Color = COLORS.Void
	light.Range = 10
	light.Brightness = 0
	light.Parent = root
	TweenService:Create(light, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 4 }):Play()
	Debris:AddItem(light, 0.4)
end

function EFFECTS.Vanish(model)
	local root = rootOf(model)
	if not root then
		return
	end
	controllers.EffectsController:Afterimage(model)
	flash(root.Position, 4, COLORS.Void, 0.2)
	particles(root.Position, { Texture = TEX.Sparkle, Color = COLORS.Void, Size = 0.5, Size2 = 0, Speed = 10, Life = 0.4, Count = 18, Light = 1 })
end

function EFFECTS.Appear(model)
	local root = rootOf(model)
	if not root then
		return
	end
	flash(root.Position, 3.5, COLORS.Void, 0.2)
	local ground = groundUnder(model)
	if ground then
		ring(ground + Vector3.new(0, 0.15, 0), 5, COLORS.Void, { Time = 0.3 })
	end
	particles(root.Position, { Color = COLORS.VoidDark, Size = 1, Size2 = 2.5, Speed = 6, Life = 0.5, Count = 10, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }) })
end

function EFFECTS.WingsIgnite(model, action)
	local def = AbilityDefinitions.Get(action:gsub("^Ability_", ""):gsub("_Left$", ""))
	local length = def and AbilityDefinitions.Length(def) or 0.85
	for _, part in slotParts(model, "Back") do
		if part.Size.Magnitude > 1 then
			emitterOn(part, CFrame.identity, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.2, Size2 = 0.2, Life = 0.35, Speed = 1.5, Spread = 60, Rate = 45, Light = 1, Accel = Vector3.new(0, 5, 0) }, length - 0.1)
		end
	end
	local root = rootOf(model)
	if root then
		flash(root.Position + root.CFrame.LookVector * -0.8, 4, COLORS.Fire, 0.3)
	end
end

function EFFECTS.PhoenixFlare(model)
	local root = rootOf(model)
	if not root then
		return
	end
	flash(root.Position, 6, COLORS.FireCore, 0.3)
	ring(root.Position, 7, COLORS.Fire, { Normal = root.CFrame.LookVector, Time = 0.35 })
	pieces(root.Position, Vector3.yAxis, { Count = 14, Colors = { COLORS.Fire, COLORS.FireCore, COLORS.Ember }, Size = 0.35, Stretch = 2.5, Speed = 22, Spread = 3, Up = 4, Life = 0.6, Gravity = 8 })
end

-- TAIL -------------------------------------------------------------------------------
function EFFECTS.SweepRing(model)
	local ground = groundUnder(model)
	if not ground then
		return
	end
	ring(ground + Vector3.new(0, 0.3, 0), 8, Color3.fromRGB(235, 225, 205), { Time = 0.4, Transparency = 0.45, Material = Enum.Material.SmoothPlastic, Thickness = 0.5 })
	for i = 1, amount(10) do
		local angle = i / 10 * math.pi * 2
		controllers.EffectsController:Dust(ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 5, 1)
	end
end

function EFFECTS.VenomDrip(model)
	for i = 0, 5 do
		task.delay(i * 0.07, function()
			local tip = limbTip(model, "Tail")
			if tip then
				pieces(tip, -Vector3.yAxis, { Count = 1, Colors = { COLORS.Venom }, Shape = Enum.PartType.Ball, Size = 0.14, Speed = 1, Spread = 0.3, Up = 0, Life = 0.6, Gravity = 25 })
			end
		end)
	end
end

function EFFECTS.VenomPump(model)
	local base = model:FindFirstChild("Tail_Root")
	local tip = limbTip(model, "Tail")
	if not base or not tip then
		return
	end
	-- a bead of venom running down the tail into the sting
	local bead = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, CFrame = CFrame.new(base.Position), Color = COLORS.Venom, Material = Enum.Material.Neon, Transparency = 0.1 })
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / 0.16
		local now = limbTip(model, "Tail")
		if t >= 1 or not now or not base.Parent then
			connection:Disconnect()
			bead:Destroy()
			if now then
				flash(now, 1.6, COLORS.Venom, 0.15)
				pieces(now, Vector3.yAxis, { Count = 5, Colors = { COLORS.Venom, Color3.fromRGB(60, 160, 40) }, Shape = Enum.PartType.Ball, Size = 0.14, Speed = 8, Life = 0.4 })
			end
			return
		end
		-- along an arc over the back (the tail curls up)
		local p = base.Position:Lerp(now, t) + Vector3.new(0, math.sin(t * math.pi) * 1.2, 0)
		bead.CFrame = CFrame.new(p)
	end)
end

function EFFECTS.VenomSpray(model)
	local tip = limbTip(model, "Tail")
	local root = rootOf(model)
	if not tip or not root then
		return
	end
	pieces(tip, Vector3.yAxis + root.CFrame.LookVector * 0.6, { Count = 14, Colors = { COLORS.Venom, Color3.fromRGB(80, 200, 60) }, Shape = Enum.PartType.Ball, Size = 0.18, Speed = 14, Spread = 1.8, Life = 0.7, Gravity = 35 })
	particles(tip, { Color = Color3.fromRGB(150, 255, 120), Size = 0.6, Size2 = 2, Speed = 4, Life = 0.7, Count = 8, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }) })
	for i = 1, 3 do
		floorMark(tip + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3), 0.8 + math.random() * 0.8, COLORS.Venom, Enum.Material.Neon, 2.5, 0.45)
	end
end

-- GENERAL ----------------------------------------------------------------------------
function EFFECTS.Stomp(model)
	local ground = groundUnder(model)
	if ground then
		controllers.EffectsController:Dust(ground, 1.8)
		ring(ground + Vector3.new(0, 0.2, 0), 5, Color3.fromRGB(230, 220, 200), { Time = 0.35, Transparency = 0.5, Material = Enum.Material.SmoothPlastic })
	end
	shake(model, 0.15, 0.12)
end

-- SHIELDS ----------------------------------------------------------------------------
function EFFECTS.PlateLock(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local size = root.Size
	shieldPieces(model, "ReinforcedGuard", function(r, list)
		local radius = math.max(size.X, size.Z) * 0.55 + 0.4
		for i = 1, 8 do
			local angle = i / 8 * math.pi * 2
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local final = CFrame.lookAt(r.Position + out * radius, r.Position + out * (radius + 1)) + Vector3.new(0, (i % 2 == 0) and 0.6 or -0.4, 0)
			local plate = newPart({ Size = Vector3.new(1.3, 1.6, 0.12), CFrame = final + out * 2.5, Color = Color3.fromRGB(120, 130, 145), Material = Enum.Material.DiamondPlate, Transparency = 0.15 })
			local edge = newPart({ Size = Vector3.new(1.35, 0.08, 0.16), CFrame = final * CFrame.new(0, 0.8, 0) + out * 2.5, Color = Color3.fromRGB(80, 220, 255), Material = Enum.Material.Neon })
			TweenService:Create(plate, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = final }):Play()
			TweenService:Create(edge, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = final * CFrame.new(0, 0.8, 0) }):Play()
			task.delay(0.13, function()
				if plate.Parent and r.Parent then
					weldTo(r, plate)
					weldTo(r, edge)
				end
			end)
			table.insert(list, plate)
			table.insert(list, edge)
		end
	end)
	ring(root.Position, 6, Color3.fromRGB(80, 220, 255), { Time = 0.3 })
end

function EFFECTS.CrystalRing(model)
	local root = rootOf(model)
	local ground = groundUnder(model)
	if not root or not ground then
		return
	end
	shieldPieces(model, "CrystalBarrier", function(r, list)
		local radius = math.max(r.Size.X, r.Size.Z) * 0.6 + 1
		for i = 1, 9 do
			local angle = i / 9 * math.pi * 2 + math.random() * 0.2
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local height = 2.2 + math.random() * 1.6
			local base = ground + out * radius
			-- (the crystal's length runs along -Z: tipped up out of the floor, leaning outward)
			local tilt = CFrame.lookAt(base, base + out) * CFrame.Angles(math.rad(65 + math.random() * 15), 0, 0)
			local crystal = newPart({ Size = Vector3.new(0.7, 0.7, height), Color = i % 2 == 0 and COLORS.Crystal or COLORS.CrystalBlue, Material = Enum.Material.Glass, Transparency = 0.25 })
			crystal.CFrame = tilt * CFrame.new(0, 0, -height / 2) - Vector3.new(0, height, 0)
			local final = tilt * CFrame.new(0, 0, -height / 2) * CFrame.Angles(0, 0, math.rad(45))
			TweenService:Create(crystal, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = final }):Play()
			-- its point: two wedges back to back on the end of the shaft
			local tipHeight = 0.9 + math.random() * 0.5
			local tipBase = final * CFrame.new(0, 0, -height / 2) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, tipHeight / 2, 0)
			local tips = {}
			for side = 1, 2 do
				local wedge = Instance.new("WedgePart")
				wedge.Anchored, wedge.CanCollide, wedge.CanQuery, wedge.CanTouch, wedge.CastShadow = true, false, false, false, false
				wedge.Size = Vector3.new(0.7, tipHeight, 0.35)
				wedge.Color, wedge.Material, wedge.Transparency = crystal.Color, crystal.Material, crystal.Transparency
				local cf = side == 1 and tipBase * CFrame.new(0, 0, -0.175) or tipBase * CFrame.new(0, 0, 0.175) * CFrame.Angles(0, math.pi, 0)
				wedge.CFrame = cf - Vector3.new(0, height, 0)
				wedge.Parent = folder
				TweenService:Create(wedge, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = cf }):Play()
				table.insert(tips, wedge)
				table.insert(list, wedge)
			end
			task.delay(0.15, function()
				if crystal.Parent and r.Parent then
					weldTo(r, crystal)
					for _, wedge in tips do
						weldTo(r, wedge)
					end
				end
			end)
			table.insert(list, crystal)
		end
	end)
	pieces(ground + Vector3.new(0, 0.5, 0), Vector3.yAxis, { Count = 14, Colors = { COLORS.Crystal, COLORS.CrystalBlue }, Material = Enum.Material.Glass, Size = 0.25, Speed = 14, Spread = 2.5, Life = 0.6 })
	flash(root.Position, 5, COLORS.Crystal, 0.3)
	shake(model, 0.15, 0.12)
end

function EFFECTS.MagmaRise(model)
	for _, at in feet(model) do
		particles(at, { Texture = TEX.Fire, Color = COLORS.Lava, Color2 = COLORS.Ember, Size = 0.8, Size2 = 0.1, Speed = 5, Life = 0.4, Count = 8, Light = 1, Direction = Vector3.yAxis, Spread = 25 })
		floorMark(at, 2.2, COLORS.Lava, Enum.Material.Neon, 1.2, 0.3)
	end
end

function EFFECTS.MagmaCrust(model)
	local root = rootOf(model)
	if not root then
		return
	end
	shieldPieces(model, "MagmaShell", function(r, list)
		local radius = math.max(r.Size.X, r.Size.Z) * 0.5 + 0.3
		for i = 1, 10 do
			local angle = i / 10 * math.pi * 2
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local y = (i % 3 - 1) * 0.8
			local cf = CFrame.lookAt(r.Position + out * radius + Vector3.new(0, y, 0), r.Position + out * (radius + 1) + Vector3.new(0, y, 0)) * CFrame.Angles(math.random() * 0.4, math.random() * 0.4, math.random() * 6)
			local rock = newPart({ Size = Vector3.new(1.1 + math.random() * 0.5, 1 + math.random() * 0.5, 0.35), CFrame = cf - out * 1.2, Color = COLORS.Basalt, Material = Enum.Material.Basalt })
			local seam = newPart({ Size = Vector3.new(rock.Size.X * 0.9, 0.07, 0.38), CFrame = cf * CFrame.Angles(0, 0, math.random() * 6) - out * 1.2, Color = COLORS.Lava, Material = Enum.Material.Neon })
			TweenService:Create(rock, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = cf }):Play()
			TweenService:Create(seam, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = cf * CFrame.Angles(0, 0, math.random() * 6) }):Play()
			task.delay(0.13, function()
				if rock.Parent and r.Parent then
					weldTo(r, rock)
					weldTo(r, seam)
				end
			end)
			table.insert(list, rock)
			table.insert(list, seam)
		end
	end)
	flash(root.Position, 5, COLORS.Lava, 0.3)
	particles(root.Position, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.2, Size2 = 0.2, Speed = 10, Life = 0.45, Count = 16, Light = 1 })
end

-- REACTOR ----------------------------------------------------------------------------
function EFFECTS.OverloadCharge(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 80)
	light.Range = 6
	light.Brightness = 0
	light.Parent = root
	TweenService:Create(light, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 8, Range = 20 }):Play()
	Debris:AddItem(light, 1.0)
	local _, size = model:GetBoundingBox()
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 0.95 or not root.Parent then
			connection:Disconnect()
			return
		end
		-- arcs crawling over the body, more and more of them
		if math.random() < 0.15 + t * 0.6 then
			local function onBody()
				return root.Position + Vector3.new((math.random() - 0.5) * size.X, (math.random() - 0.3) * size.Y, (math.random() - 0.5) * size.Z) * 0.8
			end
			bolt(onBody(), onBody(), math.random() < 0.5 and COLORS.Volt or Color3.fromRGB(255, 170, 60), 0.07 + t * 0.06, 0.08)
		end
		if t > 0.5 and math.random() < 0.2 then
			local ground = groundUnder(model)
			if ground then
				local spot = ground + Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
				bolt(root.Position, spot, COLORS.Volt, 0.08, 0.1)
				pieces(spot, Vector3.yAxis, { Count = 3, Colors = { COLORS.Volt }, Size = 0.08, Stretch = 4, Speed = 10, Life = 0.25 })
			end
		end
	end)
end

function EFFECTS.OverloadBlast(model, action)
	local root = rootOf(model)
	if not root then
		return
	end
	local def = AbilityDefinitions.Get(action:gsub("^Ability_", ""))
	local radius = def and def.Radius or 12
	local blast = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = CFrame.new(root.Position), Color = Color3.fromRGB(255, 230, 170), Material = Enum.Material.Neon, Transparency = 0.05 })
	TweenService:Create(blast, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
	Debris:AddItem(blast, 0.4)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = radius * 3
	light.Brightness = 10
	light.Parent = blast
	local ground = groundUnder(model) or root.Position
	ring(ground + Vector3.new(0, 0.3, 0), radius * 1.3, Color3.fromRGB(255, 160, 60), { Time = 0.45, Thickness = 0.5 })
	for i = 1, 10 do
		local angle = i / 10 * math.pi * 2
		local out = Vector3.new(math.cos(angle), (math.random() - 0.3) * 0.5, math.sin(angle)).Unit
		bolt(root.Position, root.Position + out * (radius * (0.6 + math.random() * 0.5)), i % 2 == 0 and COLORS.Volt or Color3.fromRGB(255, 160, 60), 0.18, 0.25)
	end
	particles(root.Position, { Color = Color3.fromRGB(90, 80, 75), Size = 2, Size2 = 5, Speed = 18, Life = 0.9, Count = 18, Drag = 4, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }) })
	shake(model, 0.4, 0.4, radius * 3)
	if isMine(model) then
		controllers.EffectsController:ImpactPunch(1)
	end
end

-- FIRE / BREATH ----------------------------------------------------------------------
function EFFECTS.FistIgnite(model, action)
	EFFECTS.Ignite(model, action)
end

function EFFECTS.Inhale(model)
	local mouth, forward = headFront(model)
	if not mouth then
		return
	end
	for i = 1, amount(18) do
		task.delay(math.random() * 0.3, function()
			local current = headFront(model) or mouth
			local spread = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3
			local from = current + forward * (3 + math.random() * 2) + spread
			local mote = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * (0.15 + math.random() * 0.15), CFrame = CFrame.new(from), Color = i % 2 == 0 and COLORS.Fire or Color3.fromRGB(200, 200, 200), Material = i % 2 == 0 and Enum.Material.Neon or Enum.Material.SmoothPlastic, Transparency = 0.3 })
			TweenService:Create(mote, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(current), Size = Vector3.one * 0.04 }):Play()
			Debris:AddItem(mote, 0.28)
		end)
	end
	local head = model:FindFirstChild("Head_Root")
	if head then
		local light = Instance.new("PointLight")
		light.Color = COLORS.Fire
		light.Range = 6
		light.Brightness = 0
		light.Parent = head
		TweenService:Create(light, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 4 }):Play()
		Debris:AddItem(light, 0.5)
	end
end

function EFFECTS.SmokeSnort(model)
	local mouth, forward = headFront(model)
	if not mouth then
		return
	end
	for _, side in { -1, 1 } do
		local right = forward:Cross(Vector3.yAxis).Unit
		particles(mouth + right * side * 0.25 + Vector3.new(0, 0.2, 0), { Color = Color3.fromRGB(70, 65, 62), Size = 0.4, Size2 = 1.8, Speed = 3, Life = 1.1, Spread = 20, Count = 7, Direction = Vector3.yAxis + forward * 0.5, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }), Accel = Vector3.new(0, 2, 0) })
	end
	particles(mouth, { Texture = TEX.Fire, Color = COLORS.Ember, Size = 0.25, Size2 = 0, Speed = 3, Life = 0.5, Count = 5, Light = 1 })
end

------------------------------------------------------------------------------------------
-- Server-driven effects (WorldFX "AbilityFX")
------------------------------------------------------------------------------------------
local function trail(data)
	local from, to = data.From, data.To
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local style = data.Style
	local time = math.clamp(tonumber(data.Time) or 0.4, 0, 2)
	local path = to - from
	local length = path.Magnitude
	local direction = length > 0.01 and path.Unit or Vector3.zAxis
	if style == "Void" then
		-- the tear in the air: a jagged violet line hanging where the body went, splitting
		-- open (Delay later) in a flash of cuts, then sealing
		local points = {}
		local segments = math.max(3, math.floor(length / 1.5))
		local right = direction:Cross(Vector3.yAxis)
		for i = 0, segments do
			local k = i / segments
			local jitter = (i == 0 or i == segments) and 0 or (math.random() - 0.5) * 0.9
			table.insert(points, from:Lerp(to, k) + right * jitter + Vector3.new(0, (math.random() - 0.5) * 0.6, 0))
		end
		local parts = {}
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local seg = newPart({ Size = Vector3.new(0.12, 0.5, (b - a).Magnitude + 0.2), CFrame = CFrame.lookAt((a + b) / 2, b), Color = COLORS.Void, Material = Enum.Material.Neon, Transparency = 0.1 })
			local dark = newPart({ Size = Vector3.new(0.14, 0.3, (b - a).Magnitude + 0.2), CFrame = seg.CFrame, Color = COLORS.VoidDark, Material = Enum.Material.Neon })
			table.insert(parts, seg)
			table.insert(parts, dark)
		end
		local delay = math.clamp(tonumber(data.Delay) or 0.25, 0, 1)
		task.delay(delay, function()
			-- it SPLITS: the tear tears wide, cuts flash across it, and it seals
			for _, seg in parts do
				if seg.Parent then
					TweenService:Create(seg, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(seg.Size.X, seg.Size.Y * 4, seg.Size.Z) }):Play()
					task.delay(0.12, function()
						TweenService:Create(seg, TweenInfo.new(0.2), { Size = Vector3.new(0.02, 0.02, seg.Size.Z), Transparency = 1 }):Play()
					end)
					Debris:AddItem(seg, 0.4)
				end
			end
			for i = 1, amount(6) do
				local at = from:Lerp(to, math.random())
				local cut = CFrame.lookAt(at, at + direction) * CFrame.Angles(0, 0, math.random() * 6)
				local slash = newPart({ Size = Vector3.new(0.08, 2.6, 0.08), CFrame = cut, Color = Color3.fromRGB(230, 200, 255), Material = Enum.Material.Neon })
				TweenService:Create(slash, TweenInfo.new(0.18), { Transparency = 1, Size = Vector3.new(0.02, 3.4, 0.02) }):Play()
				Debris:AddItem(slash, 0.2)
				if i == 1 then
					flash(from:Lerp(to, 0.5), 4, COLORS.Void, 0.2)
				end
			end
			play("VoidWhoosh", from:Lerp(to, 0.5))
		end)
		return
	end
	-- ICE / FIRE: patches laid along the floor behind the body as it goes
	local steps = math.max(2, math.floor(length / 1.6))
	for i = 0, steps do
		task.delay(time * i / steps, function()
			local at = from + direction * (length * i / steps)
			if style == "Ice" then
				floorMark(at, 2.4 + math.random() * 0.8, COLORS.Ice, Enum.Material.Ice, 3, 0.3)
				if i % 2 == 0 then
					local hit = floorBelow(at)
					if hit then
						pieces(hit.Position + Vector3.new(0, 0.2, 0), -direction + Vector3.yAxis, { Count = 3, Colors = { COLORS.Ice, COLORS.Frost }, Material = Enum.Material.Ice, Size = 0.2, Speed = 10, Life = 0.4 })
					end
				end
			elseif style == "Fire" then
				floorMark(at, 2 + math.random(), Color3.fromRGB(40, 25, 18), Enum.Material.Slate, 2.6, 0.3)
				local hit = floorBelow(at)
				if hit then
					local anchor = newPart({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(hit.Position) })
					emitterOn(anchor, CFrame.identity, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.2, Size2 = 0.2, Life = 0.45, Speed = 3, Spread = 15, Rate = 18, Light = 1, Accel = Vector3.new(0, 5, 0) }, 1.2)
					Debris:AddItem(anchor, 2)
				end
			end
		end)
	end
end

local function shatter(data)
	if typeof(data.Position) ~= "Vector3" then
		return
	end
	local at = data.Position
	if data.Style == "Ice" then
		flash(at, 4, COLORS.Ice, 0.25)
		pieces(at, Vector3.yAxis, { Count = 16, Colors = { COLORS.Ice, COLORS.Frost, COLORS.IceDeep }, Material = Enum.Material.Ice, Size = 0.35, Speed = 18, Spread = 2.4, Life = 0.7, Gravity = 40 })
		particles(at, { Color = COLORS.Frost, Size = 1, Size2 = 3, Speed = 8, Life = 0.7, Count = 10 })
		play("IceShatter", at)
		play("FrostBurst", at)
	end
end

local function burst(data)
	if typeof(data.Position) ~= "Vector3" then
		return
	end
	local at, radius = data.Position, math.clamp(tonumber(data.Radius) or 5, 1, 20)
	if data.Style == "Fire" then
		flash(at, radius * 1.6, COLORS.FireCore, 0.3)
		ring(at, radius * 1.4, COLORS.Fire, { Time = 0.4 })
		particles(at, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 2, Size2 = 0.5, Speed = radius * 3, Life = 0.5, Count = 26, Light = 1, Drag = 4 })
		local hit = floorBelow(at)
		if hit then
			floorMark(hit.Position, radius * 1.6, Color3.fromRGB(35, 22, 16), Enum.Material.Slate, 3, 0.25)
		end
		play("Explosion", at)
	end
end

------------------------------------------------------------------------------------------
-- What a landed hit looks like, by ability (the Bite and Rusty Slash keep EffectsController's)
------------------------------------------------------------------------------------------
local CONTACT = {
	["Ability:Charged Bite"] = function(at)
		particles(at, { Texture = TEX.Sparkle, Color = COLORS.Volt, Size = 0.5, Size2 = 0, Speed = 12, Life = 0.35, Count = 14, Light = 1 })
		bolt(at + Vector3.new(0, 1.5, 0), at - Vector3.new(0, 0.5, 0), COLORS.Electric, 0.1, 0.12)
	end,
	["Ability:Frost Ram"] = function(at, dir)
		pieces(at, dir or Vector3.yAxis, { Count = 10, Colors = { COLORS.Ice, COLORS.Frost }, Material = Enum.Material.Ice, Size = 0.28, Speed = 16, Life = 0.5 })
		play("IceCrack", at)
	end,
	["Ability:Visor Glare"] = function(at)
		pieces(at, Vector3.yAxis, { Count = 5, Colors = { Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 140, 40) }, Size = 0.1, Stretch = 4, Speed = 16, Life = 0.3 })
		play("Sizzle", at)
	end,
	["Ability:Tentacle Lash"] = function(at, dir)
		pieces(at, dir or Vector3.yAxis, { Count = 8, Colors = { COLORS.Shadow, COLORS.VoidDark, COLORS.Void }, Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Size = 0.2, Speed = 12, Life = 0.5 })
		play("TentacleSlime", at)
	end,
	["Ability:Demon Rend"] = function(at, dir)
		controllers.EffectsController:HitBurst(at, dir, "Slash", false)
		particles(at, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1, Size2 = 0.2, Speed = 8, Life = 0.35, Count = 10, Light = 1 })
	end,
	["Ability:Magnet Pull"] = function(at)
		pieces(at, Vector3.yAxis, { Count = 8, Colors = { COLORS.Magnet, Color3.fromRGB(220, 230, 255) }, Size = 0.1, Stretch = 4, Speed = 18, Life = 0.35 })
	end,
	["Ability:Bat Dive"] = function(at, dir)
		controllers.EffectsController:HitBurst(at, dir, "Slash", false)
	end,
	["Ability:Blink Dash"] = function(at)
		pieces(at, Vector3.yAxis, { Count = 10, Colors = { COLORS.Void, Color3.fromRGB(230, 200, 255) }, Size = 0.12, Stretch = 5, Speed = 20, Life = 0.35 })
		flash(at, 2.5, COLORS.Void, 0.15)
	end,
	["Ability:Tail Sweep"] = function(at)
		controllers.EffectsController:Dust(at - Vector3.new(0, 1.5, 0), 1)
	end,
	["Ability:Phoenix Dive"] = function(at)
		particles(at, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.4, Size2 = 0.2, Speed = 10, Life = 0.4, Count = 14, Light = 1 })
		play("FireWhoosh", at)
	end,
	["Ability:Venom Sting"] = function(at, dir)
		pieces(at, (dir and -dir or Vector3.zero) + Vector3.yAxis, { Count = 8, Colors = { COLORS.Venom, Color3.fromRGB(60, 160, 40) }, Shape = Enum.PartType.Ball, Size = 0.16, Speed = 12, Life = 0.5 })
	end,
}

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function AbilityEffects:Init(registry)
	controllers = registry
end

function AbilityEffects:Start()
	folder = Instance.new("Folder")
	folder.Name = "AbilityEffects"
	folder.Parent = Workspace

	controllers.NightmareAnimator.MarkerReached:Connect(function(model: Model, action: string?, name: string)
		if type(name) ~= "string" or not model or not model.Parent then
			return
		end
		local root = rootOf(model)
		if not root or not nearCamera(root.Position, 200) then
			return
		end
		local fx = name:match("^FX_(.+)$")
		if fx then
			local handler = EFFECTS[fx]
			if handler then
				local ok, err = pcall(handler, model, action or "")
				if not ok then
					warn("[AbilityEffects] " .. fx .. ": " .. tostring(err))
				end
			end
			return
		end
		local sound = name:match("^SFX_(.+)$")
		if sound then
			play(sound, (sourcePoint(model)) or root.Position)
		end
	end)

	Net.Get("WorldFX").OnClientEvent:Connect(function(kind, data)
		if kind ~= "AbilityFX" or type(data) ~= "table" then
			return
		end
		local ok, err = pcall(function()
			if data.Kind == "Trail" then
				trail(data)
			elseif data.Kind == "Shatter" then
				shatter(data)
			elseif data.Kind == "Burst" then
				burst(data)
			elseif data.Kind == "MagnetLock" then
				magnetLock(data)
			elseif data.Kind == "Lash" then
				lash(data)
			elseif AbilityEffects.Kinds[data.Kind] then
				AbilityEffects.Kinds[data.Kind](data)
			end
		end)
		if not ok then
			warn("[AbilityEffects] " .. tostring(data.Kind) .. ": " .. tostring(err))
		end
	end)

	Net.Get("CombatFeedback").OnClientEvent:Connect(function(kind, data)
		if kind ~= "Damage" or type(data) ~= "table" then
			return
		end
		local contact = type(data.Source) == "string" and CONTACT[data.Source]
		local target = typeof(data.Target) == "Instance" and data.Target or nil
		local root = target and rootOf(target)
		if contact and root then
			local dir = typeof(data.Dir) == "Vector3" and data.Dir or nil
			pcall(contact, root.Position + Vector3.new(0, 0.8, 0), dir)
		end
	end)

	-- shields: chips fly off as they soak a hit; they shatter when they break
	local function watchShield(model: Instance)
		local last = model:GetAttribute("Shield") or 0
		model:GetAttributeChangedSignal("Shield"):Connect(function()
			local now = model:GetAttribute("Shield") or 0
			local shield = shields[model]
			local root = rootOf(model)
			if shield and root then
				if now <= 0 then
					-- broken (or expired: it just falls away)
					clearShield(model, last > 0 and now < last and last > 1)
				elseif now < last then
					local piece = shield.Parts[math.random(1, #shield.Parts)]
					if piece and piece.Parent then
						pieces(piece.Position, piece.Position - root.Position, { Count = 4, Colors = { piece.Color }, Material = piece.Material, Size = 0.18, Speed = 14, Life = 0.4 })
					end
					local sound = shield.Style == "CrystalBarrier" and "CrystalChime" or shield.Style == "MagmaShell" and "Sizzle" or "ArmorClank"
					play(sound, root.Position)
				end
			end
			last = now
		end)
	end
	for _, model in CollectionService:GetTagged("Nightmare") do
		watchShield(model)
	end
	CollectionService:GetInstanceAddedSignal("Nightmare"):Connect(watchShield)
end

-- For UltimateEffects: the same building blocks, and the same three ways in.
AbilityEffects.Effects = EFFECTS -- "FX_<Name>" markers
AbilityEffects.Kinds = {} -- WorldFX "AbilityFX" kinds
AbilityEffects.Contact = CONTACT -- landed hits, by damage Source
AbilityEffects.Kit = {
	TEX = TEX, COLORS = COLORS, amount = amount, isMine = isMine, newPart = newPart, particles = particles,
	emitterOn = emitterOn, pieces = pieces, ring = ring, flash = flash, bolt = bolt, rope = rope,
	floorBelow = floorBelow, floorMark = floorMark, rootOf = rootOf, slotParts = slotParts, limbTip = limbTip,
	groundUnder = groundUnder, play = play, shake = shake,
}

return AbilityEffects
