--[[
	EffectsController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/EffectsController

	Client-only feedback. Nothing here affects gameplay.
	  * Floating damage numbers (capped so the screen never floods)
	  * Hit flash + flinch on the target
	  * Magnet beams and the thrown Storm Spear (WorldFX)
	  * Red floor telegraphs for enemy attacks during their windup
	  * Overhead name + health bars for Nightmares and enemies
	  * "DEFEATED" pop-ups
	Phase 3/7: pooled particles per element, camera shake (with reduction setting).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local StatusDefinitions = require(Shared:WaitForChild("StatusDefinitions"))
local Passives = require(Shared:WaitForChild("PassiveDefinitions"))

local EffectsController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local MAX_FLOATING_TEXT = 14

local effectsFolder: Folder
local activeFloatingText = 0
local controllers

local function newEffectPart(props): BasePart
	local p = Instance.new("Part")
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
	p.Parent = effectsFolder
	return p
end

------------------------------------------------------------------------------------------
-- Floating text
------------------------------------------------------------------------------------------
function EffectsController:PopText(position: Vector3, text: string, color: Color3, size: number?)
	local camera = Workspace.CurrentCamera
	if activeFloatingText >= MAX_FLOATING_TEXT then
		return
	end
	if camera and (camera.CFrame.Position - position).Magnitude > Config.Combat.DamageNumberMaxDistance then
		return
	end
	activeFloatingText += 1

	local start = position + Vector3.new(math.random(-10, 10) / 10, 3, math.random(-10, 10) / 10)
	local anchor = newEffectPart({ Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1, CFrame = CFrame.new(start) })
	local billboard = UIKit.New("BillboardGui", {
		Size = UDim2.fromOffset(160, 50),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = anchor,
	})
	local label = UIKit.New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		Font = UIKit.FontHeavy,
		TextSize = size or 28,
		Parent = billboard,
	})

	local info = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { CFrame = CFrame.new(start + Vector3.new(0, 2.5, 0)) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.8, function()
		activeFloatingText -= 1
		anchor:Destroy()
	end)
end

function EffectsController:Flash(model: Model?)
	if not model or not model.Parent or not controllers.SettingsController:Get("HitFlashes") then
		return
	end
	local highlight = UIKit.New("Highlight", {
		FillColor = Color3.new(1, 1, 1),
		FillTransparency = 0.35,
		OutlineTransparency = 1,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Adornee = model,
		Parent = effectsFolder,
	})
	Debris:AddItem(highlight, 0.1)
end

------------------------------------------------------------------------------------------
-- Weapons & telegraphs
------------------------------------------------------------------------------------------
-- The Storm Spear in flight: a glowing spear from the thrower's hand to where it lands,
-- with a lightning flash at the end.
function EffectsController:SpearThrow(from: Vector3, to: Vector3, time: number)
	-- the same spear you held (WeaponModels.StormSpear), laid out along -Z from its grip
	local spear = Instance.new("Model")
	spear.Name = "ThrownSpear"
	local function piece(size: Vector3, offset: CFrame, color: Color3, material, shape)
		local p = newEffectPart({ Size = size, CFrame = offset, Color = color, Material = material })
		if shape then
			p.Shape = shape
		end
		p.Parent = spear
		return p
	end
	local alongZ = CFrame.Angles(0, math.rad(90), 0)
	local storm = Color3.fromRGB(120, 210, 255)
	piece(Vector3.new(7.2, 0.22, 0.22), CFrame.new(0, 0, -0.9) * alongZ, Color3.fromRGB(52, 44, 40), Enum.Material.Wood, Enum.PartType.Cylinder)
	for _, z in { -2.2, -2.75, -3.3, 2.75 } do
		piece(Vector3.new(0.18, 0.3, 0.3), CFrame.new(0, 0, z) * alongZ, Color3.fromRGB(190, 110, 60), Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	local head = piece(Vector3.new(0.08, 0.5, 1.7), CFrame.new(0, 0, -5.6), Color3.fromRGB(200, 206, 220), Enum.Material.Metal)
	piece(Vector3.new(0.12, 0.14, 1.6), CFrame.new(0, 0, -5.6), storm, Enum.Material.Neon).Transparency = 0.15
	spear.WorldPivot = CFrame.new() -- the grip (no PrimaryPart: the pivot stays here)
	spear.Parent = effectsFolder
	spear:PivotTo(CFrame.lookAt(from, to))
	local light = Instance.new("PointLight")
	light.Color = storm
	light.Range = 14
	light.Brightness = 3
	light.Parent = head
	-- a shallow arc: up a little, then down into the target
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / time, 0, 1)
		local p = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * (to - from).Magnitude * 0.06, 0)
		local ahead = from:Lerp(to, math.min(t + 0.05, 1)) + Vector3.new(0, math.sin(math.min(t + 0.05, 1) * math.pi) * (to - from).Magnitude * 0.06, 0)
		if (ahead - p).Magnitude > 0.01 then
			spear:PivotTo(CFrame.lookAt(p, ahead))
		end
		if t >= 1 then
			connection:Disconnect()
			spear:Destroy()
			self:Lightning(to + Vector3.new(0, 14, 0), to)
		end
	end)
end

-- The Magnet's pull: a crackling blue line from the Handler to what it grabbed, held for
-- as long as the drag lasts.
function EffectsController:MagnetBeam(from: Model?, to: Model?, time: number?)
	local a = from and from:FindFirstChild("HumanoidRootPart")
	local b = to and to:FindFirstChild("HumanoidRootPart")
	if not a or not b then
		return
	end
	for i = 1, math.max(3, math.floor((time or 0.2) / 0.06)) do
		task.delay((i - 1) * 0.06, function()
			if a.Parent and b.Parent then
				local p0 = a.Position + a.CFrame.LookVector * 2
				local p1 = b.Position
				local beam = newEffectPart({
					Size = Vector3.new(0.25, 0.25, (p1 - p0).Magnitude),
					CFrame = CFrame.lookAt((p0 + p1) / 2, p1),
					Color = Color3.fromRGB(90, 170, 255),
					Material = Enum.Material.Neon,
					Transparency = 0.15,
				})
				TweenService:Create(beam, TweenInfo.new(0.2), { Transparency = 1, Size = Vector3.new(0.05, 0.05, beam.Size.Z) }):Play()
				Debris:AddItem(beam, 0.22)
			end
		end)
	end
end

-- Zig-zag neon bolt between two points (Shock chains).
function EffectsController:Lightning(from: Vector3, to: Vector3)
	local points = { from }
	for i = 1, 3 do
		local p = from:Lerp(to, i / 4)
		table.insert(points, p + Vector3.new(math.random(-10, 10) / 10, math.random(-10, 10) / 10, math.random(-10, 10) / 10))
	end
	table.insert(points, to)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local bolt = newEffectPart({
			Size = Vector3.new(0.2, 0.2, (b - a).Magnitude),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = Color3.fromRGB(255, 240, 120),
			Material = Enum.Material.Neon,
		})
		TweenService:Create(bolt, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		Debris:AddItem(bolt, 0.3)
	end
end

-- Big name callout when any Nightmare unleashes its Ultimate (owner + nearby players).
function EffectsController:UltimateBanner(data)
	local camera = Workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - data.Position).Magnitude > 150 then
		return
	end
	local mine = data.Model and data.Model:GetAttribute("OwnerUserId") == localPlayer.UserId
	local gui = localPlayer:FindFirstChild("PlayerGui")
	if not gui then
		return
	end
	local screen = UIKit.New("ScreenGui", { Name = "UltimateBanner", IgnoreGuiInset = true, DisplayOrder = 25, Parent = gui })
	local label = UIKit.Label({
		Text = data.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, mine and 0.26 or 0.18),
		Size = UDim2.fromScale(0.9, mine and 0.12 or 0.07),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UIKit.FontHeavy,
		TextColor3 = Color3.fromRGB(255, 210, 90),
		TextStrokeTransparency = 0.1,
		TextStrokeColor3 = Color3.fromRGB(90, 30, 140),
		MaxTextSize = mine and 64 or 32,
		Parent = screen,
	})
	local scale = UIKit.New("UIScale", { Scale = 1.6, Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if mine then
		self:Shake(0.3, 0.2)
	end
	task.delay(1.6, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.5)
		screen:Destroy()
	end)
end

-- Ghostly copy left behind when dodging.
function EffectsController:Afterimage(character: Model?)
	if not character then
		return
	end
	-- (a player's body parts are its children; a Nightmare's pieces sit deeper)
	local parts = Players:GetPlayerFromCharacter(character) and character:GetChildren() or character:GetDescendants()
	for _, d in parts do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
			local ghost = newEffectPart({
				Size = d.Size,
				CFrame = d.CFrame,
				Color = Color3.fromRGB(170, 140, 255),
				Material = Enum.Material.Neon,
				Transparency = 0.55,
			})
			TweenService:Create(ghost, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			Debris:AddItem(ghost, 0.32)
		end
	end
end

function EffectsController:Telegraph(enemy: Model)
	local root = enemy:FindFirstChild("HumanoidRootPart")
	local humanoid = enemy:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local length = enemy:GetAttribute("TelegraphLength") or 5
	local width = enemy:GetAttribute("TelegraphWidth") or 4
	local windup = enemy:GetAttribute("ActionWindup") or 0.6

	local floorY = root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2) + 0.08
	local function place(): CFrame
		local flat = CFrame.new(root.Position.X, floorY, root.Position.Z) * root.CFrame.Rotation
		return flat * CFrame.new(0, 0, -(root.Size.Z / 2 + length / 2))
	end
	local marker = newEffectPart({
		Size = Vector3.new(width, 0.1, length),
		CFrame = place(),
		Color = C.EnemyHP,
		Material = Enum.Material.Neon,
		Transparency = 0.75,
	})
	TweenService:Create(marker, TweenInfo.new(windup, Enum.EasingStyle.Linear), { Transparency = 0.25 }):Play()
	Debris:AddItem(marker, windup + 0.05)
	-- enemies track their target through the windup: the marker turns (and lunges) with them
	local follow
	follow = RunService.RenderStepped:Connect(function()
		if not marker.Parent or not root.Parent then
			follow:Disconnect()
			return
		end
		marker.CFrame = place()
	end)
end

------------------------------------------------------------------------------------------
-- Overhead health bars
------------------------------------------------------------------------------------------
local function attachHealthBar(model: Model)
	if CollectionService:HasTag(model, "Boss") then
		return -- bosses use the big HUD bar instead
	end
	local root = model:WaitForChild("HumanoidRootPart", 5)
	local humanoid = model:WaitForChild("Humanoid", 5)
	if not root or not humanoid or root:FindFirstChild("OverheadBar") then
		return
	end

	local isNightmare = CollectionService:HasTag(model, "Nightmare")
	local isMine = model:GetAttribute("OwnerUserId") == localPlayer.UserId

	local boxCFrame, boxSize = model:GetBoundingBox()
	local topOffset = (boxCFrame.Position.Y + boxSize.Y / 2) - root.Position.Y + 1.2

	local billboard = UIKit.New("BillboardGui", {
		Name = "OverheadBar",
		Size = UDim2.fromOffset(150, 38),
		StudsOffsetWorldSpace = Vector3.new(0, topOffset, 0),
		AlwaysOnTop = true,
		MaxDistance = 110,
		LightInfluence = 0,
		Adornee = root,
		Parent = root,
	})

	local title = model:GetAttribute("DisplayName") or model.Name
	if isNightmare then
		title = isMine and (title .. " (yours)") or ("%s · %s"):format(title, model:GetAttribute("OwnerName") or "?")
	end
	UIKit.New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = isNightmare and C.Text or Color3.fromRGB(255, 200, 200),
		TextStrokeTransparency = 0.4,
		Font = UIKit.Font,
		TextSize = 14,
		Parent = billboard,
	})
	local bar = UIKit.Bar({
		Position = UDim2.fromOffset(15, 21),
		Size = UDim2.new(1, -30, 0, 10),
		Color = isNightmare and C.NightmareHP or C.EnemyHP,
		Parent = billboard,
	})
	bar.Label.Visible = false

	local function update()
		UIKit.SetBar(bar, humanoid.Health, humanoid.MaxHealth)
	end
	update()
	humanoid.HealthChanged:Connect(update)

	-- Status effect icons (coloured tags) + stagger meter.
	billboard.Size = UDim2.fromOffset(150, 56)
	local statusLabel = UIKit.New("TextLabel", {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		RichText = true,
		Text = "",
		Font = UIKit.Font,
		TextSize = 12,
		TextStrokeTransparency = 0.4,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = billboard,
	})
	local staggerBar = UIKit.New("Frame", { Position = UDim2.fromOffset(15, 31), Size = UDim2.new(0, 0, 0, 3), BackgroundColor3 = Color3.fromRGB(255, 220, 90), BorderSizePixel = 0, Parent = billboard })
	local function updateStatus()
		local parts = {}
		for id, stacks in StatusDefinitions.Parse(model:GetAttribute("Statuses")) do
			local def = StatusDefinitions.Get(id)
			if def then
				table.insert(parts, ('<font color="#%s">%s%s</font>'):format(def.Color:ToHex(), def.Icon, stacks > 1 and ("x" .. stacks) or ""))
			end
		end
		statusLabel.Text = table.concat(parts, " ")
		local max = model:GetAttribute("StaggerMax") or 100
		staggerBar.Size = UDim2.new(0, 120 * math.clamp((model:GetAttribute("Stagger") or 0) / max, 0, 1), 0, 3)
	end
	model:GetAttributeChangedSignal("Statuses"):Connect(updateStatus)
	model:GetAttributeChangedSignal("Stagger"):Connect(updateStatus)
	updateStatus()
end

------------------------------------------------------------------------------------------
-- World telegraphs (bosses & AoE abilities), impacts, projectiles
------------------------------------------------------------------------------------------
local STYLE_COLORS = {
	Hostile = Color3.fromRGB(255, 60, 50),
	Pull = Color3.fromRGB(70, 150, 255),
	Friendly = Color3.fromRGB(170, 100, 255),
}

-- Circles: a faint full-size disc plus an inner disc that GROWS until impact, so
-- players can read exactly when it lands.
function EffectsController:TelegraphCircle(data)
	local color = STYLE_COLORS[data.Style] or STYLE_COLORS.Hostile
	local base = CFrame.new(data.Position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local diameter = data.Radius * 2
	local outer = newEffectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, diameter, diameter),
		CFrame = base,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.8,
	})
	local inner = newEffectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.14, 0.2, 0.2),
		CFrame = base * CFrame.new(0.02, 0, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
	})
	TweenService:Create(inner, TweenInfo.new(data.Duration, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, diameter, diameter) }):Play()
	Debris:AddItem(outer, data.Duration + 0.05)
	Debris:AddItem(inner, data.Duration + 0.05)
end

function EffectsController:TelegraphBox(data)
	local color = STYLE_COLORS[data.Style] or STYLE_COLORS.Hostile
	local flat = data.CFrame + Vector3.new(0, 0.08, 0)
	local outer = newEffectPart({
		Size = Vector3.new(data.Size.X, 0.12, data.Size.Z),
		CFrame = flat,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.8,
	})
	-- Fill grows from the back edge toward the far edge.
	local inner = newEffectPart({
		Size = Vector3.new(data.Size.X, 0.14, 0.2),
		CFrame = flat * CFrame.new(0, 0.01, data.Size.Z / 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
	})
	TweenService:Create(inner, TweenInfo.new(data.Duration, Enum.EasingStyle.Linear), {
		Size = Vector3.new(data.Size.X, 0.14, data.Size.Z),
		CFrame = flat * CFrame.new(0, 0.01, 0),
	}):Play()
	Debris:AddItem(outer, data.Duration + 0.05)
	Debris:AddItem(inner, data.Duration + 0.05)
end

function EffectsController:Impact(data)
	local color = STYLE_COLORS[data.Style] or STYLE_COLORS.Hostile
	local ring = newEffectPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1,
		CFrame = CFrame.new(data.Position),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.5),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	local size = data.Radius * 2
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(size, size * 0.35, size), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.4)

	-- Gentle camera shake when it's close (Phase 7 adds a reduce-shake setting).
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if camera and root and (root.Position - data.Position).Magnitude < data.Radius + 25 then
		controllers.EffectsController:Shake(0.25, data.Radius > 8 and 0.35 or 0.15)
	end
end

-- Dust kicked up off the floor at `position` (a footstep plant, a landing, a body hitting
-- the ground): a few soft puffs rolling outward, tinted to whatever the floor is. `size`
-- ~0.5 for a step, ~1 for a landing, 2+ for a heavy body or a boss stomp.
local DUST_PARAMS = RaycastParams.new()
DUST_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
function EffectsController:Dust(position: Vector3, size: number)
	local level = controllers.SettingsController:Get("ImpactEffects")
	if level == "Minimal" or (level == "Reduced" and size < 1) then
		return -- (reduced effects: skip the little ones)
	end
	DUST_PARAMS.FilterDescendantsInstances = { effectsFolder, localPlayer.Character }
	local hit = Workspace:Raycast(position + Vector3.new(0, 1.5, 0), Vector3.new(0, -6, 0), DUST_PARAMS)
	if not hit then
		return
	end
	local floorColor = hit.Instance:IsA("Terrain") and Color3.fromRGB(120, 112, 100) or hit.Instance.Color
	local color = floorColor:Lerp(Color3.fromRGB(200, 195, 185), 0.45)
	local count = math.clamp(math.floor(3 + size * 3), 3, 12)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.6
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local start = size * (0.4 + math.random() * 0.4)
		local puff = newEffectPart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * start,
			CFrame = CFrame.new(hit.Position + out * size * 0.3 + Vector3.new(0, start * 0.3, 0)),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.35,
		})
		local life = 0.45 + size * 0.15 + math.random() * 0.2
		TweenService:Create(puff, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * start * 2.6,
			CFrame = CFrame.new(hit.Position + out * size * (1.4 + math.random()) + Vector3.new(0, size * (0.4 + math.random() * 0.5), 0)),
			Transparency = 1,
		}):Play()
		Debris:AddItem(puff, life + 0.05)
	end
end

-- A heavyweight slam / landing (WorldFX "Slam" from a boss): layered so it reads as one
-- crushing moment without hiding the fight:
--   a low ground shockwave rolling out past the circle
--   dust bursting at the impact and rolling out around it
--   chunks of floor thrown up (real physics, they bounce and settle, then go)
--   the camera jolting and punching in, scaled by how close you are
-- (Impact effects setting: Reduced = fewer chunks; Minimal = no debris or dust ring.)
function EffectsController:Slam(data)
	local position, radius, power = data.Position, data.Radius or 10, data.Power or 1
	local level = controllers.SettingsController:Get("ImpactEffects")

	-- shockwave: a flat ring hugging the floor (a burning one for a fire slam: Meteor Fist)
	local ring = newEffectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 0.6, radius * 0.6),
		CFrame = CFrame.new(position + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = data.Fire and Color3.fromRGB(255, 120, 30) or Color3.fromRGB(235, 215, 180),
		Material = data.Fire and Enum.Material.Neon or Enum.Material.SmoothPlastic,
		Transparency = 0.35,
	})
	if data.Fire then
		-- the crater glows and smoulders where the fist came down
		local crater = newEffectPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, radius * 0.9, radius * 0.9),
			CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 90, 20),
			Material = Enum.Material.Neon,
			Transparency = 0.25,
		})
		TweenService:Create(crater, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Color = Color3.fromRGB(60, 20, 10) }):Play()
		Debris:AddItem(crater, 1.7)
	end
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, radius * 3.2, radius * 3.2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.5)

	-- dust: a big burst at the impact, then rolling out around it
	self:Dust(position, 2.6 * power)
	if level ~= "Minimal" then
		for i = 1, 8 do
			local angle = i / 8 * math.pi * 2
			self:Dust(position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.65, 1.3 * power)
		end
	end

	-- debris: chunks of the floor kicked up
	local chunks = level == "Minimal" and 0 or level == "Reduced" and 4 or 10
	DUST_PARAMS.FilterDescendantsInstances = { effectsFolder }
	local floor = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -6, 0), DUST_PARAMS)
	local color = floor and not floor.Instance:IsA("Terrain") and floor.Instance.Color or Color3.fromRGB(110, 100, 90)
	local material = floor and not floor.Instance:IsA("Terrain") and floor.Instance.Material or Enum.Material.Slate
	for _ = 1, chunks do
		local angle = math.random() * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local size = 0.5 + math.random() * 1.1
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(size, size * (0.5 + math.random() * 0.5), size * (0.6 + math.random() * 0.4))
		chunk.CFrame = CFrame.new(position + out * (1 + math.random() * radius * 0.4) + Vector3.new(0, 0.8, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		chunk.Color = color
		chunk.Material = material
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CastShadow = false
		chunk.CollisionGroup = "Effects"
		chunk.Parent = effectsFolder
		chunk.AssemblyLinearVelocity = out * (14 + math.random() * 22) * power + Vector3.new(0, 30 + math.random() * 28, 0)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18
		task.delay(1.8, function()
			if chunk.Parent then
				TweenService:Create(chunk, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(chunk, 2.4)
	end

	-- the camera: by distance
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local distance = (root.Position - position).Magnitude
		local reach = radius * 3.5
		if distance < reach then
			local closeness = 1 - distance / reach
			self:Shake(0.3 + 0.3 * closeness, (0.35 + 0.65 * closeness) * power)
			if distance < radius * 1.6 then
				self:ImpactPunch(0.8 * power)
			end
		end
	end
	controllers.AudioController:Play("BossSlam", position)
end

-- DRAGON BREATH (WorldFX "Breath"): fire pouring out of the head's front for Duration, in
-- the same cone the server burns (Cone degrees wide, Range long: particle speed x life).
-- It rides the head, so it follows the animation's thrust.
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
function EffectsController:Breath(data)
	local model = data.Target
	local root = typeof(model) == "Instance" and model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local head, best = nil, 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name:sub(1, 5) == "Head_" and part.Size.Magnitude > best then
			head, best = part, part.Size.Magnitude
		end
	end
	head = head or root
	local look = root.CFrame.LookVector
	-- the head's front face, straight ahead of it
	local extent = math.abs(head.CFrame.XVector:Dot(look)) * head.Size.X + math.abs(head.CFrame.YVector:Dot(look)) * head.Size.Y + math.abs(head.CFrame.ZVector:Dot(look)) * head.Size.Z
	local mouth = head.Position + look * (extent / 2)
	local localPos = head.CFrame:PointToObjectSpace(mouth)
	local localLook = head.CFrame:VectorToObjectSpace(look)
	local attachment = Instance.new("Attachment")
	-- (+Y of the attachment points out of the mouth: particles emit along Top)
	attachment.CFrame = CFrame.lookAt(localPos, localPos + localLook) * CFrame.Angles(-math.pi / 2, 0, 0)
	attachment.Parent = head

	local range = data.Range or 14
	local life = 0.4
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = FIRE_TEXTURE
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Lifetime = NumberRange.new(life * 0.9, life * 1.05)
	emitter.Speed = NumberRange.new(range / life * 0.92, range / life)
	emitter.SpreadAngle = Vector2.new((data.Cone or 50) / 2 * 0.85, (data.Cone or 50) / 2 * 0.85)
	emitter.Rate = 160
	emitter.Drag = 0.5
	emitter.LightEmission = 0.85
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.6, 2.6), NumberSequenceKeypoint.new(1, 3.6) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 150)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 140, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 30, 10)),
	})
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 40)
	light.Brightness = 3
	light.Range = range
	light.Parent = attachment
	controllers.AudioController:Play("Projectile", mouth)

	local duration = math.clamp(tonumber(data.Duration) or 1, 0.1, 4)
	task.delay(duration, function()
		emitter.Enabled = false
		light.Enabled = false
	end)
	Debris:AddItem(attachment, duration + life + 0.2)
end

-- What a landed blow does AT the point of contact (on top of the victim's body reaction):
--   Bite   a crunch: tooth-white and dark-red shards bursting out of the bite, a tight ring
--   Slash  a spray of hot sparks along the claw's travel; much bigger off armour (a target
--          with real Defence, a boss) with a metallic clang
-- `direction` = the way the blow travelled. Scaled by the Impact effects setting.
function EffectsController:HitBurst(position: Vector3, direction: Vector3?, style: string, armoured: boolean?)
	local level = controllers.SettingsController:Get("ImpactEffects")
	if level == "Minimal" then
		return
	end
	local travel = (direction and direction.Magnitude > 0.01) and direction.Unit or Vector3.new(0, 0, -1)
	local count, colors, speed, size
	if style == "Bite" then
		count, speed, size = 9, 16, 0.22
		colors = { Color3.fromRGB(245, 240, 225), Color3.fromRGB(140, 20, 30), Color3.fromRGB(90, 10, 18) }
		local ring = newEffectPart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.8,
			CFrame = CFrame.new(position),
			Color = Color3.fromRGB(255, 235, 220),
			Material = Enum.Material.Neon,
			Transparency = 0.35,
		})
		TweenService:Create(ring, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 3.2, Transparency = 1 }):Play()
		Debris:AddItem(ring, 0.2)
	else
		count, speed, size = armoured and 16 or 8, armoured and 34 or 24, 0.14
		colors = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 160, 50), Color3.fromRGB(255, 250, 220) }
	end
	if level == "Reduced" then
		count = math.ceil(count / 2)
	end
	for i = 1, count do
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.8 - 0.2, math.random() - 0.5) * (style == "Bite" and 1.6 or 0.9)
		local velocity = (travel + spread).Unit * speed * (0.6 + math.random() * 0.6) + Vector3.new(0, 6, 0)
		local bit = newEffectPart({
			Size = Vector3.new(size, size, size * (style == "Bite" and 1 or 4)),
			CFrame = CFrame.lookAt(position, position + velocity),
			Color = colors[(i % #colors) + 1],
			Material = style == "Bite" and Enum.Material.SmoothPlastic or Enum.Material.Neon,
		})
		local life = 0.25 + math.random() * 0.2
		TweenService:Create(bit, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(position + velocity * life, position + velocity * life + velocity) - Vector3.new(0, 3 * life * life * 10, 0),
			Transparency = 1,
		}):Play()
		Debris:AddItem(bit, life + 0.05)
	end
	controllers.AudioController:Play(style == "Bite" and "BiteImpact" or (armoured and "MetalSpark" or "ClawSlash"), position)
end

function EffectsController:Projectile(data)
	local chunk = newEffectPart({
		Size = Vector3.new(1.8, 1.4, 1.6),
		CFrame = CFrame.new(data.From),
		Color = Color3.fromRGB(110, 90, 75),
		Material = Enum.Material.CorrodedMetal,
	})
	local mid = (data.From + data.To) / 2 + Vector3.new(0, 18, 0)
	local half = data.Duration / 2
	TweenService:Create(chunk, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(mid) * CFrame.Angles(2, 1, 0) }):Play()
	task.delay(half, function()
		TweenService:Create(chunk, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(data.To) * CFrame.Angles(4, 2, 1) }):Play()
	end)
	Debris:AddItem(chunk, data.Duration + 0.05)
end

local shakeUntil, shakeStrength = 0, 0
local SHAKE_SCALE = { Full = 1, Reduced = 0.35, Off = 0 } -- Settings: CameraShake
function EffectsController:Shake(duration: number, strength: number)
	local scale = SHAKE_SCALE[controllers.SettingsController:Get("CameraShake")] or 1
	if scale <= 0 then
		return
	end
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
	shakeStrength = math.max(shakeStrength, strength * scale)
end

-- A heavy blow you landed: the field of view snaps in a few degrees and eases back out,
-- with a short sharp jolt. (Respects the CameraShake setting; subtle on purpose.)
local fovPunch = { Base = nil, Until = 0 }
function EffectsController:ImpactPunch(strength: number)
	local scale = SHAKE_SCALE[controllers.SettingsController:Get("CameraShake")] or 1
	local camera = Workspace.CurrentCamera
	if scale <= 0 or not camera then
		return
	end
	self:Shake(0.14, 0.35 * strength * scale)
	if os.clock() > fovPunch.Until then
		fovPunch.Base = camera.FieldOfView
	end
	local base = fovPunch.Base or camera.FieldOfView
	fovPunch.Until = os.clock() + 0.32
	camera.FieldOfView = base - 4 * strength * scale
	TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
end

function EffectsController:ShieldBubble(model: Model?, duration: number)
	if not model or not model.Parent then
		return
	end
	local highlight = UIKit.New("Highlight", {
		FillColor = Color3.fromRGB(120, 200, 255),
		FillTransparency = 0.6,
		OutlineColor = Color3.fromRGB(180, 230, 255),
		Adornee = model,
		Parent = effectsFolder,
	})
	local connection
	connection = model:GetAttributeChangedSignal("Shield"):Connect(function()
		if (model:GetAttribute("Shield") or 0) <= 0 then
			highlight:Destroy()
			connection:Disconnect()
		end
	end)
	task.delay(duration + 0.1, function()
		if highlight.Parent then
			highlight:Destroy()
		end
		connection:Disconnect()
	end)
end

-- Server-requested push on OUR character (e.g. Magnet Pull). We own our physics.
function EffectsController:ApplyImpulse(velocity: Vector3, duration: number)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local attachment = root and root:FindFirstChild("RootAttachment")
	if not attachment then
		return
	end
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.MaxForce = 1e5
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VectorVelocity = velocity
	mover.Parent = root
	Debris:AddItem(mover, duration)
end

-- Blue outline while a Handler is guarding.
local function watchGuard(character: Model)
	local highlight
	local function update()
		local guarding = character:GetAttribute("Guarding") == true
		if guarding and not highlight then
			highlight = UIKit.New("Highlight", {
				FillColor = Color3.fromRGB(90, 160, 255),
				FillTransparency = 0.75,
				OutlineColor = Color3.fromRGB(150, 200, 255),
				Adornee = character,
				Parent = effectsFolder,
			})
		elseif not guarding and highlight then
			highlight:Destroy()
			highlight = nil
		end
	end
	character:GetAttributeChangedSignal("Guarding"):Connect(update)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent and highlight then
			highlight:Destroy()
		end
	end)
	update()
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function EffectsController:Init(registry)
	controllers = registry
end

function EffectsController:Start()
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "ClientEffects"
	effectsFolder.Parent = Workspace

	-- AFTERIMAGE passive (PassiveDefinitions): a Nightmare's sidesteps, step-backs and
	-- dash-ins leave a trail of ghosts (the server makes it untouchable mid-step)
	local function watchNightmare(model: Instance)
		model:GetAttributeChangedSignal("ActionSeq"):Connect(function()
			local action = model:GetAttribute("ActionName")
			if (action == "StepBack" or action == "Sidestep" or action == "DashIn") and Passives.Has(model, "Afterimage") then
				for i = 0, 2 do
					task.delay(i * 0.07, function()
						if model.Parent then
							self:Afterimage(model)
						end
					end)
				end
			end
		end)
	end
	for _, model in CollectionService:GetTagged("Nightmare") do
		watchNightmare(model)
	end
	CollectionService:GetInstanceAddedSignal("Nightmare"):Connect(watchNightmare)

	-- Animation event markers (HandlerAnimator.MarkerReached), on every character you see:
	--   Whoosh          the strike cutting the air (sound at the body)
	--   StepL / StepR   a foot planting hard (dust + footstep sound at that foot)
	--   Land            landing from a jump / dive / drop kick (bigger dust + thud)
	controllers.HandlerAnimator.MarkerReached:Connect(function(character: Model, _slot, name: string)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local audio = controllers.AudioController
		if name == "Whoosh" then
			audio:Play("PunchWhoosh", root.Position)
		elseif name == "StepL" or name == "StepR" then
			local foot = character:FindFirstChild(name == "StepL" and "LeftFoot" or "RightFoot")
			local at = foot and foot.Position or root.Position
			self:Dust(at, 0.5)
			audio:Play("Footstep", at)
		elseif name == "Land" then
			self:Dust(root.Position, 1.1)
			audio:Play("Land", root.Position)
		end
	end)

	-- ...and the same markers on keyframed Nightmare attacks (NightmareAnimator)
	controllers.NightmareAnimator.MarkerReached:Connect(function(model: Model, _action, name: string)
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local audio = controllers.AudioController
		if name == "Whoosh" then
			audio:Play("PunchWhoosh", root.Position)
		elseif name == "StepL" or name == "StepR" then
			local leg = model:FindFirstChild(name == "StepL" and "Legs_L" or "Legs_R")
			local at = Vector3.new((leg or root).Position.X, root.Position.Y, (leg or root).Position.Z)
			self:Dust(at - Vector3.new(0, root.Size.Y / 2, 0), 0.8)
			audio:Play("Footstep", at)
		elseif name == "Land" then
			self:Dust(root.Position - Vector3.new(0, root.Size.Y / 2, 0), 1.4)
			audio:Play("Land", root.Position)
		elseif name == "JawSnap" or name == "Grind" or name == "Rip" then
			local head = model:FindFirstChild("Head_Jaw") or model:FindFirstChild("Head_Root") or root
			audio:Play(name == "JawSnap" and "BiteSnap" or name == "Grind" and "BiteGrind" or "BiteRip", head.Position)
			if name == "Rip" and model:GetAttribute("OwnerUserId") == localPlayer.UserId then
				self:Shake(0.12, 0.1) -- your Nightmare tearing loose: a jolt (the rip's hit bursts the crunch)
			end
		end
	end)

	Net.Get("CombatFeedback").OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" then
			return
		end
		if kind == "Damage" then
			local target = data.Target
			local targetIsMine = target and (target == localPlayer.Character or (target:GetAttribute("OwnerUserId") == localPlayer.UserId))
			local color = targetIsMine and C.Bad or Color3.fromRGB(255, 235, 140)
			if controllers.SettingsController:Get("DamageNumbers") then
				-- a punished (exposed / broken) boss: the number comes up bigger and hotter
				if data.Exposed or data.Broken then
					self:PopText(data.Position, tostring(data.Amount), Color3.fromRGB(255, 150, 60), 30)
				else
					self:PopText(data.Position, tostring(data.Amount), color)
				end
			end
			self:Flash(target)
			local dir = typeof(data.Dir) == "Vector3" and data.Dir or nil
			controllers.NightmareAnimator:Flinch(target, dir, data.Heavy)
			-- a Handler takes it: head snaps, body driven the way of the blow, a heavy one
			-- staggers you out of your strike
			if target and Players:GetPlayerFromCharacter(target) and not data.KnockedDown then
				controllers.HandlerAnimator:React(target, dir, data.Heavy, data.Amount)
				if target == localPlayer.Character and data.Heavy then
					controllers.MeleeController:Interrupt()
				end
			end
			-- contact effects for abilities that physically connect (bites crunch, claws spark)
			local source = type(data.Source) == "string" and data.Source or ""
			local root = target and target:FindFirstChild("HumanoidRootPart")
			if root and (source == "Ability:Bite" or source == "Ability:Charged Bite") then
				-- the bite lands on the side facing the biter
				local attacker = typeof(data.Attacker) == "Instance" and data.Attacker:FindFirstChild("HumanoidRootPart")
				local toward = attacker and (attacker.Position - root.Position) * Vector3.new(1, 0, 1)
				local at = root.Position + (toward and toward.Magnitude > 0.1 and toward.Unit * math.min(root.Size.Z / 2, 1.5) or Vector3.zero) + Vector3.new(0, 0.8, 0)
				self:HitBurst(at, dir and -dir or nil, "Bite")
				self:Shake(0.12, 0.12)
			elseif root and source == "Ability:Rusty Slash" then
				local armoured = (target:GetAttribute("Defence") or 0) >= 10 or target:GetAttribute("BossId") ~= nil
				self:HitBurst(root.Position + Vector3.new(0, 1, 0), dir, "Slash", armoured)
			end
			-- YOUR strike landed: a beat of hit-stop on you, and for a heavy one the camera
			-- punches in toward the impact and jolts
			local character = localPlayer.Character
			if character and data.Attacker == character and type(data.Source) == "string" and data.Source:sub(1, 8) == "Handler:" then
				controllers.HandlerAnimator:HitStop(data.Heavy and 0.085 or 0.045)
				if data.Heavy then
					self:ImpactPunch(data.KnockedDown and 1 or 0.6)
				end
			end
		elseif kind == "Defeated" then
			self:PopText(data.Position + Vector3.new(0, 2, 0), "DEFEATED!", C.Warn, 34)
		elseif kind == "Blocked" then
			self:PopText(data.Position, "BLOCKED", Color3.fromRGB(150, 200, 255), 22)
		elseif kind == "Parried" then
			-- the guard snapped out at the last instant: the blow is knocked away
			local defender = typeof(data.Target) == "Instance" and data.Target or nil
			local attacker = typeof(data.Attacker) == "Instance" and data.Attacker or nil
			self:PopText(data.Position + Vector3.new(0, 2, 0), "PARRY!", Color3.fromRGB(255, 225, 120), 34)
			controllers.HandlerAnimator:PlayOn(defender, "Parry")
			if attacker and Players:GetPlayerFromCharacter(attacker) then
				controllers.HandlerAnimator:PlayOn(attacker, "Parried")
				if attacker == localPlayer.Character then
					controllers.MeleeController:Interrupt()
				end
			elseif attacker and defender then
				controllers.NightmareAnimator:Flinch(attacker, attacker:GetPivot().Position - defender:GetPivot().Position, true)
			end
			if defender == localPlayer.Character or attacker == localPlayer.Character then
				self:Shake(0.18, 0.12)
				controllers.HandlerAnimator:HitStop(0.08)
			end
		elseif kind == "GuardBreak" then
			self:PopText(data.Position, "GUARD BREAK!", C.Bad, 30)
		elseif kind == "KnockedDown" then
			-- a boss floored by a signature strike: rare, so make it a moment
			self:PopText(data.Position + Vector3.new(0, 5, 0), "KNOCKED DOWN!", Color3.fromRGB(255, 120, 70), 40)
			self:Shake(0.35, 0.5)
		elseif kind == "Staggered" then
			local boss = typeof(data.Target) == "Instance" and data.Target:GetAttribute("BossId") ~= nil
			self:PopText(data.Position + Vector3.new(0, boss and 6 or 3, 0), boss and "BROKEN!" or "STAGGERED!", boss and Color3.fromRGB(255, 120, 70) or Color3.fromRGB(255, 220, 90), boss and 44 or 32)
			self:Shake(boss and 0.35 or 0.2, boss and 0.3 or 0.15)
		elseif kind == "Status" then
			local def = StatusDefinitions.Get(data.Status)
			if def then
				self:PopText(data.Position + Vector3.new(0, 1.5, 0), string.upper(def.DisplayName), def.Color, 20)
			end
		elseif kind == "Chain" then
			self:Lightning(data.From, data.To)
		end
	end)

	Net.Get("WorldFX").OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" then
			return
		end
		if kind == "Telegraph" then
			if data.Shape == "Circle" then
				self:TelegraphCircle(data)
			else
				self:TelegraphBox(data)
			end
		elseif kind == "Impact" then
			self:Impact(data)
		elseif kind == "Projectile" then
			self:Projectile(data)
		elseif kind == "Shield" then
			self:ShieldBubble(data.Target, data.Duration or 5)
		elseif kind == "UltimateBanner" then
			self:UltimateBanner(data)
		elseif kind == "Slam" and typeof(data.Position) == "Vector3" then
			self:Slam(data)
		elseif kind == "Breath" then
			self:Breath(data)
		elseif kind == "MagnetBeam" then
			self:MagnetBeam(data.From, data.To, data.Time)
		elseif kind == "SpearThrow" and typeof(data.From) == "Vector3" and typeof(data.To) == "Vector3" then
			self:SpearThrow(data.From, data.To, math.clamp(tonumber(data.Time) or 0.3, 0.05, 1.5))
		end
	end)

	Net.Get("PlayerFX").OnClientEvent:Connect(function(kind, data)
		if kind == "Impulse" and type(data) == "table" and typeof(data.Velocity) == "Vector3" then
			self:ApplyImpulse(data.Velocity, math.clamp(data.Duration or 0.3, 0.05, 1))
		end
	end)

	-- Camera shake (applied after the default camera scripts each frame).
	RunService:BindToRenderStep("NightmareShake", Enum.RenderPriority.Camera.Value + 2, function()
		local now = os.clock()
		if now < shakeUntil then
			local camera = Workspace.CurrentCamera
			local s = shakeStrength * ((shakeUntil - now) / 0.25)
			camera.CFrame *= CFrame.new(math.random(-100, 100) / 100 * s, math.random(-100, 100) / 100 * s, 0)
		else
			shakeStrength = 0
		end
	end)

	-- Guard outlines for every Handler (including ours).
	local function watchAllGuards(player: Player)
		if player.Character then
			watchGuard(player.Character)
		end
		player.CharacterAdded:Connect(watchGuard)
	end
	for _, player in Players:GetPlayers() do
		watchAllGuards(player)
	end
	Players.PlayerAdded:Connect(watchAllGuards)

	for _, tag in { "Nightmare", "Enemy" } do
		local function onAdded(model)
			task.spawn(attachHealthBar, model)
			if tag == "Enemy" then
				model:GetAttributeChangedSignal("ActionSeq"):Connect(function()
					self:Telegraph(model)
				end)
			end
		end
		for _, model in CollectionService:GetTagged(tag) do
			onAdded(model)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded)
	end

end

return EffectsController
