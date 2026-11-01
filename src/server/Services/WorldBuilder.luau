--[[
	WorldBuilder  (ModuleScript)
	Location: ServerScriptService/Server/Services/WorldBuilder

	Builds the whole world at server start (see Shared/WorldDefinitions for the layout):
	  World/Hub         THE NIGHTMARE FORGE: spawn, Engine + Crafting Forge, Workshop,
	                    Training Arena, Hall of Nightmares, Colosseum, four route gates
	  World/ScrapRoute  west  → the Scrap Titan's Foundry
	  World/MirrorRoute east  → the Mirror Warden's Hall of Reflections
	  World/StormRoute  north → the Storm Beast's Tempest Summit
	  World/AbyssRoute  south → the Abyssal Maw's Cathedral
	  World/Backdrop    distant mountains, silhouettes and fill so no direction is empty
	The boss arenas themselves are built by Bosses/ArenaBuilder (BossService builds each
	boss's first arena slot at the end of its route on start-up).

	Each part is built in its own pcall: one broken piece never takes the world down.
	If Workspace already contains "NightmareForgeHub", generation is skipped so a
	hand-built map can replace this one (keep the prompt names: OpenWorkshop, OpenForge,
	OpenColosseum, BossPortal, Waystone, Relic).

	Also registers collision groups so Nightmares never shove their own Handlers around.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldFolder = script.Parent:WaitForChild("World")

local WorldBuilder = {}

WorldBuilder.CollisionGroups = {
	Nightmares = "Nightmares",
	Characters = "Characters",
	Enemies = "Enemies",
	-- A boss that just landed on someone (pounce / eruption): passes through players and
	-- Nightmares for a moment so physics can't shove anyone through the floor.
	BossPhasing = "BossPhasing",
	-- Client-side impact debris (EffectsController): bounces off the world, never trips or
	-- blocks players, Nightmares or enemies.
	Effects = "Effects",
}

local RGB = Color3.fromRGB
local Mat = Enum.Material

local function setupCollisionGroups()
	for _, group in WorldBuilder.CollisionGroups do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(group)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("Nightmares", "Characters", false)
	PhysicsService:CollisionGroupSetCollidable("Nightmares", "Nightmares", false)
	PhysicsService:CollisionGroupSetCollidable("BossPhasing", "Characters", false)
	PhysicsService:CollisionGroupSetCollidable("BossPhasing", "Nightmares", false)
	for _, other in { "Characters", "Nightmares", "Enemies", "BossPhasing" } do
		PhysicsService:CollisionGroupSetCollidable("Effects", other, false)
	end
end

-- Base lighting / sky / clouds. The client's WorldController blends the per-region look
-- (Shared/WorldDefinitions) on top of this as players walk between regions.
local function setupEnvironment()
	if Config.World.ApplyLighting then
		Lighting.ClockTime = 19.4
		Lighting.Brightness = 1.7
		Lighting.Ambient = RGB(72, 60, 96)
		Lighting.OutdoorAmbient = RGB(100, 86, 130)
		Lighting.EnvironmentDiffuseScale = 1
		Lighting.EnvironmentSpecularScale = 1
		Lighting.GlobalShadows = true
		if not Lighting:FindFirstChildOfClass("Atmosphere") then
			local atmosphere = Instance.new("Atmosphere")
			atmosphere.Density = 0.32
			atmosphere.Offset = 0.12
			atmosphere.Color = RGB(150, 120, 190)
			atmosphere.Decay = RGB(70, 46, 110)
			atmosphere.Haze = 1.6
			atmosphere.Parent = Lighting
		end
		if not Lighting:FindFirstChildOfClass("Sky") then
			local sky = Instance.new("Sky")
			sky.StarCount = 3000
			sky.Parent = Lighting
		end
	end

	local terrain = Workspace.Terrain
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.35
		clouds.Color = RGB(150, 120, 190)
		clouds.Parent = terrain
	end
	pcall(function()
		terrain.WaterColor = RGB(16, 60, 64)
		terrain.WaterTransparency = 0.35
		terrain.WaterReflectance = 0.6
		terrain.WaterWaveSize = 0.08
		terrain.WaterWaveSpeed = 4
	end)
	-- One look per terrain material (each region uses its own materials).
	for material, color in {
		[Mat.Basalt] = RGB(84, 78, 98), -- the Forge mesa, storm cliffs
		[Mat.Ground] = RGB(110, 80, 58), -- the rust wasteland
		[Mat.Rock] = RGB(86, 88, 96),
		[Mat.Slate] = RGB(84, 92, 110), -- storm highland
		[Mat.Mud] = RGB(48, 66, 66), -- abyss
		[Mat.Limestone] = RGB(92, 106, 104), -- abyss stone
		[Mat.CrackedLava] = RGB(140, 60, 30),
		[Mat.Snow] = RGB(200, 210, 225),
		[Mat.Salt] = RGB(220, 220, 236), -- mirror islands
		[Mat.Glacier] = RGB(170, 190, 230),
	} do
		pcall(function()
			terrain:SetMaterialColor(material, color)
		end)
	end
	pcall(function()
		Workspace.FallenPartsDestroyHeight = -450
	end)
end

function WorldBuilder:Init()
	setupCollisionGroups()
end

function WorldBuilder:Start()
	local envOk, envErr = pcall(setupEnvironment)
	if not envOk then
		warn("[WorldBuilder] environment setup failed:", envErr)
	end

	for _, folderName in { "Nightmares", "Enemies" } do
		if not Workspace:FindFirstChild(folderName) then
			local folder = Instance.new("Folder")
			folder.Name = folderName
			folder.Parent = Workspace
		end
	end

	if Workspace:FindFirstChild("NightmareForgeHub") then
		return -- a hand-built map is present
	end

	-- The place's starter Baseplate / SpawnLocation would cut through the generated world
	-- (and spawn players inside the Engine). Removed for this server only; the place file
	-- itself is untouched.
	for _, child in Workspace:GetChildren() do
		if (child:IsA("BasePart") and child.Name == "Baseplate") or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local root = Instance.new("Folder")
	root.Name = "NightmareForgeHub"
	root.Parent = Workspace

	local started = os.clock()
	for _, name in { "Hub", "Gym", "ScrapRoute", "MirrorRoute", "StormRoute", "AbyssRoute", "Backdrop" } do
		local module = WorldFolder:FindFirstChild(name)
		if module then
			local ok, err = pcall(function()
				require(module).Build(root)
			end)
			if not ok then
				warn(("[WorldBuilder] %s failed to build: %s"):format(name, tostring(err)))
			end
		end
	end
	print(("[WorldBuilder] World built in %.1fs"):format(os.clock() - started))
end

function WorldBuilder.SetCollisionGroup(model: Instance, group: string)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

return WorldBuilder
