--[[
	WeaponModels  (ModuleScript, used by MeleeService)
	Location: ServerScriptService/Server/Services/WeaponModels

	Builds the Handler's weapons out of parts. Each model is laid out around its GRIP at
	the origin, extending FORWARD (-Z): held in the right hand with the arm hanging, it
	points ahead; raise the arm and it rises with it. Welded parts are massless and
	non-colliding (purely visual: hits are hit boxes).

	The Chain Whip is different: only its grip and cap are built here. The chain itself is a
	rope simulation every client runs (ChainSimulator), hanging from the cap's
	"ChainStart" attachment, so it swings, drags along the floor, folds up and lashes out
	exactly the same for everyone.
]]

local WeaponModels = {}

local RGB = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local M = Enum.Material
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinders lie along X; turn them onto Z

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material, shape)
	local p = Instance.new(shape == "Wedge" and "WedgePart" or "Part")
	if shape and shape ~= "Wedge" then
		p.Shape = shape
	end
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function cylinderZ(model, name, length, diameter, z, color, material, x, y)
	return part(model, name, V(length, diameter, diameter), CF(x or 0, y or 0, z) * ALONG_Z, color, material, Enum.PartType.Cylinder)
end

local function light(p: BasePart, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Parent = p
end

-- A motion trail along the blade, from `a` to `b` (off until a swing: MeleeService turns it
-- on for the swing, so it follows exactly where the steel went).
local function addTrail(a: BasePart, b: BasePart, color: Color3, offsetA: Vector3?)
	local start = Instance.new("Attachment")
	start.Name = "TrailA"
	start.Position = offsetA or Vector3.zero
	start.Parent = a
	local finish = Instance.new("Attachment")
	finish.Name = "TrailB"
	finish.Parent = b
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = start
	trail.Attachment1 = finish
	trail.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.22
	trail.LightEmission = 0.8
	trail.FaceCamera = false
	trail.Enabled = false
	trail.Parent = a
end

local BUILDERS = {}

-- The Magnet: a red horseshoe magnet on a grip, a blue charge humming between the poles.
function BUILDERS.Magnet(model: Model)
	local red, silver, grip = RGB(205, 40, 40), RGB(220, 222, 230), RGB(40, 36, 34)
	cylinderZ(model, "Grip", 1.0, 0.36, 0.05, grip, M.Fabric)
	part(model, "Base", V(1.6, 0.46, 0.46), CF(0, 0, -0.7), red, M.SmoothPlastic)
	for _, x in { -0.6, 0.6 } do
		part(model, "Pole", V(0.42, 0.46, 1.2), CF(x, 0, -1.43), red, M.SmoothPlastic)
		part(model, "Tip", V(0.44, 0.48, 0.25), CF(x, 0, -2.13), silver, M.Metal)
	end
	part(model, "Band", V(1.64, 0.14, 0.14), CF(0, 0.24, -0.7), silver, M.Metal)
	local charge = part(model, "Charge", V(0.32, 0.32, 0.32), CF(0, 0, -1.85), RGB(90, 170, 255), M.Neon, Enum.PartType.Ball)
	charge.Transparency = 0.2
	light(charge, RGB(90, 170, 255), 1.2, 8)
end

-- Reaper Scythe: a long black snath, a bone-white grip and a great curved blade with a
-- glowing violet edge. Held two-handed; the blade hooks out to the right.
function BUILDERS.ReaperScythe(model: Model)
	local shaft, bone, steel, glow = RGB(28, 24, 34), RGB(214, 206, 186), RGB(70, 66, 82), RGB(170, 90, 255)
	cylinderZ(model, "Snath", 6.2, 0.3, -1.9, shaft, M.Wood)
	cylinderZ(model, "Grip", 1.0, 0.36, 0.1, bone, M.SmoothPlastic)
	cylinderZ(model, "Grip2", 0.8, 0.34, -2.2, bone, M.SmoothPlastic)
	cylinderZ(model, "Pommel", 0.3, 0.42, 1.2, steel, M.Metal)
	-- the head: a collar, a vertebra-like knuckle and the curved blade
	part(model, "Collar", V(0.5, 0.5, 0.5), CF(0, 0, -5.0), steel, M.Metal)
	part(model, "Knuckle", V(0.62, 0.62, 0.62), CF(0, 0.1, -5.15), bone, M.SmoothPlastic, Enum.PartType.Ball)
	-- The blade hooks out to the LEFT (-X): a right-hander's scythe sweeps right to left,
	-- so the point leads the swing and the edge (on the inside of the curve) cuts.
	local segments = 5
	for i = 1, segments do
		local t = (i - 0.5) / segments
		local x = -(0.35 + t * 3.6)
		local z = -5.0 + (t ^ 1.8) * 1.4 -- curving back toward you, like a real scythe
		local turn = math.rad(8 + t * 38)
		local width = 0.62 * (1 - t * 0.55)
		local seg = part(model, "Blade", V(0.82, 0.1, width), CF(x, 0, z) * CFrame.Angles(0, turn, 0), steel, M.Metal)
		seg.Reflectance = 0.15
		part(model, "Edge", V(0.82, 0.06, 0.1), CF(x, 0, z) * CFrame.Angles(0, turn, 0) * CF(0, 0, width / 2), glow, M.Neon)
	end
	local tip = part(model, "Tip", V(0.4, 0.1, 0.14), CF(-4.2, 0, -3.62) * CFrame.Angles(0, math.rad(52), 0), steel, M.Metal)
	light(tip, glow, 1.2, 10)
	addTrail(model:FindFirstChild("Knuckle"), tip, glow)
end

-- Rust Blade: a heavy machete, wrapped handle, pitted blade with a bright edge.
function BUILDERS.RustBlade(model: Model)
	local steel, rust, wrap = RGB(170, 172, 180), RGB(130, 72, 42), RGB(60, 40, 30)
	cylinderZ(model, "Handle", 1.3, 0.36, 0.1, wrap, M.Fabric)
	part(model, "Pommel", V(0.42, 0.42, 0.42), CF(0, 0, 0.8), RGB(80, 70, 60), M.Metal, Enum.PartType.Ball)
	part(model, "Guard", V(0.95, 0.24, 0.22), CF(0, 0, -0.62), RGB(80, 70, 60), M.Metal)
	part(model, "Blade", V(0.1, 0.62, 3.4), CF(0, 0.06, -2.4), steel, M.Metal)
	part(model, "Edge", V(0.06, 0.1, 3.4), CF(0, -0.27, -2.4), RGB(230, 232, 240), M.Neon).Transparency = 0.35
	part(model, "Rust", V(0.12, 0.3, 0.9), CF(0, 0.12, -1.6), rust, M.CorrodedMetal)
	local tip = part(model, "Tip", V(0.1, 0.62, 0.75), CF(0, 0.06, -4.47) * CFrame.Angles(0, math.rad(180), 0), steel, M.Metal, "Wedge")
	addTrail(model:FindFirstChild("Blade"), tip, RGB(220, 225, 240), V(0, 0, 1.5))
end

-- Chain Whip: a leather grip and a capped end the (client-simulated) chain hangs from.
function BUILDERS.ChainWhip(model: Model)
	local leather = RGB(70, 46, 34)
	cylinderZ(model, "Grip", 1.4, 0.38, 0.1, leather, M.Fabric)
	local cap = part(model, "Cap", V(0.48, 0.48, 0.48), CF(0, 0, -0.62), RGB(90, 90, 96), M.Metal, Enum.PartType.Ball)
	local start = Instance.new("Attachment")
	start.Name = "ChainStart"
	start.Position = V(0, 0, -0.22)
	start.Parent = cap
	model:SetAttribute("ChainLinks", 18) -- ~8.5 studs of chain (MeleeDefinitions whip Range matches)
end

-- Storm Spear: a javelin gripped at its balance point, a dark ash shaft wound with copper
-- coils and a steel leaf head that crackles with stored lightning. Held cocked over the
-- shoulder; it leaves your hand when you throw it (EffectsController draws the flight).
function BUILDERS.StormSpear(model: Model)
	local ash, copper, steel, storm = RGB(52, 44, 40), RGB(190, 110, 60), RGB(200, 206, 220), RGB(120, 210, 255)
	cylinderZ(model, "Shaft", 7.2, 0.22, -0.9, ash, M.Wood)
	cylinderZ(model, "Grip", 0.9, 0.28, 0, RGB(30, 26, 24), M.Fabric)
	for _, z in { -2.2, -2.75, -3.3 } do
		cylinderZ(model, "Coil", 0.18, 0.3, z, copper, M.Metal)
	end
	cylinderZ(model, "Butt", 0.35, 0.3, 2.75, copper, M.Metal)
	cylinderZ(model, "Socket", 0.5, 0.3, -4.6, steel, M.Metal)
	-- the leaf head: two wedges back to back, widest near the socket, a point at the front
	local head = part(model, "Head", V(0.08, 0.5, 1.0), CF(0, 0, -5.3), steel, M.Metal)
	head.Reflectance = 0.2
	part(model, "HeadTip", V(0.08, 0.25, 0.7), CF(0, 0.125, -6.15), steel, M.Metal, "Wedge")
	part(model, "HeadTip", V(0.08, 0.25, 0.7), CF(0, -0.125, -6.15) * CFrame.Angles(0, 0, math.pi), steel, M.Metal, "Wedge")
	part(model, "Spark", V(0.1, 0.12, 1.4), CF(0, 0, -5.5), storm, M.Neon).Transparency = 0.2
	light(head, storm, 1.5, 10)
end

-- Thunder Hammer (SHOP exclusive): a long iron-banded haft and a heavy double-faced head
-- across the end of it, blue lightning running in its runes. Held two-handed like the
-- scythe (its haft along the forearms).
function BUILDERS.ThunderHammer(model: Model)
	local haft, iron, steel, storm = RGB(70, 52, 40), RGB(80, 84, 96), RGB(150, 156, 170), RGB(120, 200, 255)
	cylinderZ(model, "Haft", 4.6, 0.3, -1.7, haft, M.Wood)
	cylinderZ(model, "Grip", 1.0, 0.36, 0.1, RGB(30, 26, 24), M.Fabric)
	cylinderZ(model, "Pommel", 0.3, 0.44, 0.7, iron, M.Metal)
	for _, z in { -1.4, -2.6 } do
		cylinderZ(model, "Band", 0.16, 0.38, z, iron, M.Metal)
	end
	-- the head across the haft (its faces point left and right of the swing)
	local head = part(model, "Head", V(2.0, 1.05, 1.05), CF(0, 0, -4.15), iron, M.Metal)
	head.Reflectance = 0.1
	for _, x in { -1.05, 1.05 } do
		part(model, "Face", V(0.18, 1.2, 1.2), CF(x, 0, -4.15), steel, M.Metal)
	end
	part(model, "Rune", V(1.6, 0.12, 1.07), CF(0, 0.2, -4.15), storm, M.Neon).Transparency = 0.1
	part(model, "Rune", V(1.6, 0.12, 1.07), CF(0, -0.2, -4.15), storm, M.Neon).Transparency = 0.1
	part(model, "Spike", V(0.3, 0.3, 0.5), CF(0, 0, -4.9), steel, M.Metal, "Wedge")
	light(head, storm, 1.4, 12)
	addTrail(model:FindFirstChild("Band"), head, storm)
end

-- Shadow Kunai (SHOP exclusive): three black kunai fanned between the fingers, ring
-- pommels and violet-edged blades. (Thrown ones are drawn by EffectsController.)
function BUILDERS.ShadowKunai(model: Model)
	local black, wrap, edge = RGB(30, 28, 36), RGB(110, 80, 160), RGB(170, 120, 255)
	for i, yaw in { -16, 0, 16 } do
		local turn = CFrame.Angles(0, math.rad(yaw), 0)
		local function at(z)
			return turn * CF(0, 0, z)
		end
		part(model, "Ring" .. i, V(0.08, 0.3, 0.3), at(0.45), black, M.Metal, Enum.PartType.Cylinder)
		part(model, "Wrap" .. i, V(0.14, 0.14, 0.55), at(0.05), wrap, M.Fabric)
		part(model, "Blade" .. i, V(0.06, 0.24, 0.9), at(-0.65), black, M.Metal)
		part(model, "Edge" .. i, V(0.07, 0.06, 0.9), at(-0.65) * CF(0, -0.1, 0), edge, M.Neon).Transparency = 0.2
		part(model, "Point" .. i, V(0.06, 0.24, 0.3), at(-1.25) * CFrame.Angles(0, math.rad(180), 0), black, M.Metal, "Wedge")
	end
end

-- How a weapon sits in the fist, if not straight out of it. The scythe's snath carries on
-- along the FOREARM (tipped 10 degrees past it), so when the arms swing the blade sweeps a
-- huge arc at chest height out at arm's length + 5 studs, instead of the pole standing
-- straight up whenever the arm is raised. The Thunder Hammer is held the same way.
local GRIPS = {
	ReaperScythe = CFrame.Angles(math.rad(-100), 0, 0),
	ThunderHammer = CFrame.Angles(math.rad(-100), 0, 0),
}

-- Builds weapon `id` held by `hand`. Returns the model, or nil for Fists.
function WeaponModels.Build(id: string, hand: BasePart): Model?
	local build = BUILDERS[id]
	if not build then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "HeldWeapon"
	build(model)
	-- lay it out in the hand: grip a little below the hand's centre, pointing forward
	-- (or turned, for weapons that sit differently in the fist: see GRIPS). Everything hangs
	-- off an invisible GRIP part on a "Wrist" weld, so a move can turn the weapon in the
	-- fist (HandlerPoses "Wrist" keys: a thrust points the blade along the forearm).
	local seat = CFrame.new(0, -0.2, 0) * (GRIPS[id] or CFrame.identity)
	local gripCFrame = hand.CFrame * seat
	local grip = part(model, "Grip", V(0.2, 0.2, 0.2), gripCFrame, RGB(0, 0, 0), M.SmoothPlastic)
	grip.Transparency = 1
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= grip then
			p.CFrame = gripCFrame * p.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = grip
			weld.Part1 = p
			weld.Parent = p
		end
	end
	local wrist = Instance.new("Weld")
	wrist.Name = "Wrist"
	wrist.Part0 = hand
	wrist.Part1 = grip
	wrist.C0 = seat
	wrist.Parent = grip
	model:SetAttribute("WeaponId", id)
	return model
end

return WeaponModels
