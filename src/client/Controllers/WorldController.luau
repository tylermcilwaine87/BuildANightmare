--[[
	WorldController  (ModuleScript)
	Location: StarterPlayerScripts/Client/Controllers/WorldController

	Brings the world to life on the client (Shared/WorldDefinitions):
	  * Region look: lighting, fog, colour grading, bloom, clouds and sky blend as you
	    walk between the Forge and the four boss regions (in a boss fight: that boss's).
	  * A region title card the first time you enter each region (per session).
	  * The gate reveal: reaching a boss gate for the first time sweeps the camera over
	    the arena to the boss waiting inside.
	  * Lightning flashes in the Storm region.
	  * Animated set pieces (tags from World/Kit): WSpin, WBob, WSwing, WOrbit,
	    WConveyor, WPulse, WFlicker. Only things near the camera are animated.
	  * Relics you've already taken are hidden.
	  * Region ambience (AudioDefinitions: HubAmbience, ScrapAmbience, ...).
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))

local WorldController = {}

local controllers
local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local ANIMATE_RANGE = 450 -- studs from the camera
local BLEND = TweenInfo.new(2.5, Enum.EasingStyle.Sine)

local effects = {}
local currentRegion: string? = nil
local seenRegions = {}
local revealed = {}
local busyCamera = false

function WorldController:Init(registry)
	controllers = registry
end

------------------------------------------------------------------------------------------
-- Region look
------------------------------------------------------------------------------------------
local function effect(class: string, name: string)
	local e = Lighting:FindFirstChild(name)
	if not e then
		e = Instance.new(class)
		e.Name = name
		e.Parent = Lighting
	end
	return e
end

function WorldController:ApplyRegion(regionId: string)
	local region = WorldDefinitions.Regions[regionId]
	if not region or currentRegion == regionId then
		return
	end
	currentRegion = regionId
	local look = region.Lighting
	Lighting.ClockTime = look.ClockTime
	TweenService:Create(Lighting, BLEND, { Brightness = look.Brightness, Ambient = look.Ambient, OutdoorAmbient = look.OutdoorAmbient }):Play()
	TweenService:Create(effects.Atmosphere, BLEND, look.Atmosphere):Play()
	TweenService:Create(effects.Grading, BLEND, look.Grading):Play()
	TweenService:Create(effects.Bloom, BLEND, look.Bloom):Play()
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		TweenService:Create(clouds, BLEND, look.Clouds):Play()
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky and look.Sky then
		sky.SunAngularSize = look.Sky.SunSize
		sky.MoonAngularSize = look.Sky.MoonSize
		sky.StarCount = look.Sky.Stars
	end
	local audio = controllers.AudioController
	if audio and audio.SetAmbience then
		audio:SetAmbience(region.Ambience)
	end
	if not seenRegions[regionId] then
		seenRegions[regionId] = true
		if regionId ~= "Hub" and not controllers.BossController:IsInFight() then
			controllers.BossController:Banner(region.Name, region.Subtitle, region.Color, 3)
		end
	end
end

function WorldController:CurrentRegion(): string?
	return currentRegion
end

local function regionNow(): string?
	local bossId = controllers.BossController.GetBossId and controllers.BossController:GetBossId()
	if controllers.BossController:IsInFight() and bossId and WorldDefinitions.BossRegion[bossId] then
		return WorldDefinitions.BossRegion[bossId]
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	if root.Position.Magnitude > 3000 then
		return nil -- a duel arena far away: keep the current look
	end
	return WorldDefinitions.RegionAt(root.Position)
end

------------------------------------------------------------------------------------------
-- Gate reveal: a short camera sweep over the arena the first time you reach a gate
------------------------------------------------------------------------------------------
function WorldController:Reveal(regionId: string)
	local region = WorldDefinitions.Regions[regionId]
	if busyCamera or not region or not region.Arena then
		return
	end
	busyCamera = true
	local arena = region.Arena
	local center = arena.Position
	local out = arena.LookVector
	local bossAt = (arena * CFrame.new(0, 10, 28)).Position
	local startCF = camera.CFrame
	local high = CFrame.lookAt(center + out * 150 + Vector3.new(0, 70, 0), center)
	local close = CFrame.lookAt(center + out * 40 + Vector3.new(0, 24, 0), bossAt)
	camera.CameraType = Enum.CameraType.Scriptable
	controllers.BossController:Banner(region.ArenaName or region.Name, "Speak to the altar to challenge it", region.Color, 3.5)
	local t1 = TweenService:Create(camera, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { CFrame = high })
	t1:Play()
	t1.Completed:Wait()
	local t2 = TweenService:Create(camera, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { CFrame = close })
	t2:Play()
	t2.Completed:Wait()
	task.wait(0.8)
	local t3 = TweenService:Create(camera, TweenInfo.new(1, Enum.EasingStyle.Sine), { CFrame = startCF })
	t3:Play()
	t3.Completed:Wait()
	camera.CameraType = Enum.CameraType.Custom
	busyCamera = false
end

function WorldController:IsCameraBusy(): boolean
	return busyCamera
end

------------------------------------------------------------------------------------------
-- Lightning (Storm region)
------------------------------------------------------------------------------------------
local function lightningFlash()
	local grading = effects.Grading
	local base = grading.Brightness
	grading.Brightness = base + 0.35
	TweenService:Create(grading, TweenInfo.new(0.35), { Brightness = base }):Play()
	-- a bolt somewhere in the distance
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local rng = Random.new()
	local a = rng:NextNumber(0, math.pi * 2)
	local at = root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(150, 400)
	local bolt = Instance.new("Model")
	bolt.Name = "LightningBolt"
	local prev = at + Vector3.new(0, 260, 0)
	for k = 1, 8 do
		local p = at + Vector3.new(rng:NextNumber(-14, 14), 260 * (1 - k / 8) - 40, rng:NextNumber(-14, 14))
		local len = (p - prev).Magnitude
		local seg = Instance.new("Part")
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CastShadow = false
		seg.Material = Enum.Material.Neon
		seg.Color = Color3.fromRGB(215, 240, 255)
		seg.Size = Vector3.new(1.4, 1.4, len)
		seg.CFrame = CFrame.lookAt((prev + p) / 2, p)
		seg.Parent = bolt
		prev = p
	end
	bolt.Parent = Workspace:FindFirstChild("ClientEffects") or Workspace
	task.delay(0.18, function()
		bolt:Destroy()
	end)
end

------------------------------------------------------------------------------------------
-- Animated set pieces
------------------------------------------------------------------------------------------
local tracked = {} -- [inst] = { Kind, Base, Phase }
local active = {} -- subset near the camera

local function track(inst: Instance, kind: string)
	if tracked[inst] then
		return
	end
	local entry = { Kind = kind, Phase = math.random() * 6.28 }
	if kind == "WPulse" or kind == "WFlicker" then
		entry.Base = 0
	elseif kind == "WConveyor" then
		entry.Slats = {}
		for _, child in inst:GetChildren() do
			if child:IsA("BasePart") then
				entry.Slats[child] = child.CFrame
			end
		end
	elseif inst:IsA("Model") or inst:IsA("BasePart") then
		entry.Base = (inst :: any):GetPivot()
	else
		return
	end
	tracked[inst] = entry
end

local function positionOf(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	elseif inst:IsA("Light") then
		local parent = inst.Parent
		return parent and parent:IsA("BasePart") and parent.Position or nil
	end
	return nil
end

local AXES = {
	X = function(a)
		return CFrame.Angles(a, 0, 0)
	end,
	Y = function(a)
		return CFrame.Angles(0, a, 0)
	end,
	Z = function(a)
		return CFrame.Angles(0, 0, a)
	end,
}

local function animate(t: number)
	for inst, a in active do
		if not inst.Parent then
			active[inst] = nil
			tracked[inst] = nil
			continue
		end
		local kind = a.Kind
		if kind == "WSpin" then
			local rotate = AXES[inst:GetAttribute("Axis") or "Y"] or AXES.Y;
			(inst :: any):PivotTo(a.Base * rotate(t * (inst:GetAttribute("Speed") or 0.5)))
		elseif kind == "WBob" then
			(inst :: any):PivotTo(a.Base + Vector3.new(0, math.sin(t * (inst:GetAttribute("Speed") or 1) + a.Phase) * (inst:GetAttribute("Amp") or 0.5), 0))
		elseif kind == "WSwing" then
			local rotate = AXES[inst:GetAttribute("Axis") or "X"] or AXES.X
			local angle = math.rad(inst:GetAttribute("Angle") or 5) * math.sin(t * (inst:GetAttribute("Speed") or 0.5) + a.Phase);
			(inst :: any):PivotTo(a.Base * rotate(angle))
		elseif kind == "WOrbit" then
			local center = inst:GetAttribute("Center") or a.Base.Position
			local radius = inst:GetAttribute("Radius") or 10
			local angle = t * (inst:GetAttribute("Speed") or 0.1) + a.Phase
			local pos = center + Vector3.new(math.cos(angle) * radius, math.sin(t * 0.4 + a.Phase) * (inst:GetAttribute("Height") or 2), math.sin(angle) * radius);
			(inst :: any):PivotTo(CFrame.new(pos) * a.Base.Rotation)
		elseif kind == "WConveyor" then
			local spacing = inst:GetAttribute("Spacing") or 2
			local offset = (t * (inst:GetAttribute("Speed") or 4)) % spacing
			for slat, base in a.Slats do
				slat.CFrame = base * CFrame.new(0, 0, -offset)
			end
		elseif kind == "WPulse" or kind == "WFlicker" then
			local min = inst:GetAttribute("Min") or 0
			local max = inst:GetAttribute("Max") or 1
			local speed = inst:GetAttribute("Speed") or 1
			local k
			if kind == "WFlicker" then
				k = math.clamp(0.5 + math.noise(t * speed * 0.6, a.Phase) * 1.6, 0, 1)
			else
				k = 0.5 + 0.5 * math.sin(t * speed + a.Phase)
			end
			local value = min + (max - min) * k
			if inst:IsA("Light") then
				inst.Brightness = value
			elseif inst:IsA("BasePart") then
				inst.Transparency = value
			end
		end
	end
end

local function refreshActive()
	local camPos = camera.CFrame.Position
	table.clear(active)
	for inst, entry in tracked do
		if not inst.Parent then
			tracked[inst] = nil
		else
			local p = positionOf(inst)
			if p and (p - camPos).Magnitude <= ANIMATE_RANGE + (inst:IsA("Model") and inst.Name:find("Giant") and 900 or 0) then
				active[inst] = entry
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- Relics
------------------------------------------------------------------------------------------
local function refreshRelics()
	local profile = controllers.ClientState.Profile
	local found = profile and profile.Relics or {}
	for _, model in CollectionService:GetTagged("Relic") do
		local id = model:GetAttribute("RelicId")
		local taken = id and found[id] == true
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = taken and 1 or 0
			elseif d:IsA("ProximityPrompt") then
				d.Enabled = not taken
			elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
				d.Enabled = not taken
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function WorldController:Start()
	effects.Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or effect("Atmosphere", "WorldAtmosphere")
	effects.Grading = effect("ColorCorrectionEffect", "WorldGrading")
	effects.Bloom = effect("BloomEffect", "WorldBloom")

	for _, kind in { "WSpin", "WBob", "WSwing", "WOrbit", "WConveyor", "WPulse", "WFlicker" } do
		for _, inst in CollectionService:GetTagged(kind) do
			track(inst, kind)
		end
		CollectionService:GetInstanceAddedSignal(kind):Connect(function(inst)
			task.defer(track, inst, kind)
		end)
	end

	controllers.ClientState.Changed:Connect(refreshRelics)
	CollectionService:GetInstanceAddedSignal("Relic"):Connect(function()
		task.defer(refreshRelics)
	end)
	refreshRelics()

	RunService.RenderStepped:Connect(function()
		animate(os.clock())
	end)

	-- region checks, reveals and lightning
	task.spawn(function()
		local nextFlash = os.clock() + 6
		while true do
			local regionId = regionNow()
			if regionId then
				self:ApplyRegion(regionId)
			end
			refreshActive()

			-- first time at a boss gate: reveal the arena
			local character = localPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and not controllers.BossController:IsInFight() and not busyCamera then
				for _, id in WorldDefinitions.RouteOrder do
					if not revealed[id] then
						local plaza = WorldDefinitions.GatePlaza(id).Position
						if (root.Position - plaza).Magnitude < 34 then
							revealed[id] = true
							task.spawn(self.Reveal, self, id)
						end
					end
				end
			end

			local look = currentRegion and WorldDefinitions.Regions[currentRegion].Lighting
			if look and look.Lightning and os.clock() >= nextFlash then
				nextFlash = os.clock() + Random.new():NextNumber(4, 10)
				lightningFlash()
			end
			task.wait(0.5)
		end
	end)
end

return WorldController
