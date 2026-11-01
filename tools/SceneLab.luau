--[[
	SceneLab  (ModuleScript, DEV TOOL)
	Location: ServerStorage/DevTools/SceneLab   (Rojo: tools/, never shipped to players)

	Fixed camera shots of every area, for comparing the game's look before and after a change.
	Only moves things in the playtest; it doesn't touch the saved profile.

	1) Client view, command bar (holds the camera on the shot and names it on screen):

	  local P=game.Players.LocalPlayer for _,g in P.PlayerGui:GetChildren() do if g:IsA('ScreenGui') then g.Enabled=false end end local s=Instance.new('ScreenGui') s.DisplayOrder=99 s.Parent=P.PlayerGui local t=Instance.new('TextLabel') t.Size=UDim2.fromOffset(300,30) t.Position=UDim2.new(0.5,-150,0,8) t.TextSize=22 t.Parent=s game:GetService('RunService'):BindToRenderStep('SceneCam',2000,function() local c=workspace:GetAttribute('ShotCam') if c then workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable workspace.CurrentCamera.CFrame=CFrame.lookAt(c,workspace:GetAttribute('ShotLook')) t.Text=workspace:GetAttribute('ShotName') end end)

	2) Server view, command bar:

	  require(game.ServerStorage.DevTools.SceneLab:Clone()).Tour(8)      (a new shot every 8 s)
	  require(game.ServerStorage.DevTools.SceneLab:Clone()).Go("Abyss_Plaza")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GymDefinitions = require(Shared:WaitForChild("GymDefinitions"))
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))

local SceneLab = {}

local V3, CF = Vector3.new, CFrame.new

-- Rests a point on whatever is below it (the routes sit at different heights).
local function ground(position: Vector3, from: number?): Vector3
	local params = RaycastParams.new()
	local exclude = {}
	for _, player in Players:GetPlayers() do
		table.insert(exclude, player.Character)
	end
	local nightmares = Workspace:FindFirstChild("Nightmares")
	if nightmares then
		table.insert(exclude, nightmares)
	end
	params.FilterDescendantsInstances = exclude
	params.FilterType = Enum.RaycastFilterType.Exclude
	local top = from or 300
	local hit = Workspace:Raycast(V3(position.X, position.Y + top, position.Z), V3(0, -(top + 500), 0), params)
	return hit and hit.Position or position
end

local function buildShots()
	local shots = {}
	local function add(name: string, foot: Vector3, facing: Vector3)
		local flat = V3(facing.X, foot.Y, facing.Z)
		local frame = (flat - foot).Magnitude > 0.1 and CFrame.lookAt(foot, flat) or CF(foot)
		table.insert(shots, { Name = name, Foot = frame, Cam = (frame * CF(5, 7, 24)).Position, Look = (frame * CF(0, 4, -20)).Position })
	end

	local hub, world = WorldDefinitions.HubCenter, Config.World
	add("Hub_Spawn", ground(WorldDefinitions.HubSpawn, 20), hub)
	add("Hub_Workshop", ground(world.WorkshopCenter:Lerp(hub, 0.6), 20), world.WorkshopCenter)
	add("Hub_Arena", ground(world.ArenaCenter:Lerp(hub, 0.6), 20), world.ArenaCenter)
	add("Hub_Colosseum", ground(world.ColosseumCenter:Lerp(hub, 0.6), 20), world.ColosseumCenter)
	for _, regionId in WorldDefinitions.RouteOrder do
		local plaza = WorldDefinitions.GatePlaza(regionId)
		local arena = WorldDefinitions.Regions[regionId].Arena
		add(regionId .. "_Route", ground(hub:Lerp(plaza.Position, 0.55)), plaza.Position)
		add(regionId .. "_Plaza", ground(plaza.Position, 30), arena.Position)
		add(regionId .. "_Arena", ground((arena * CF(0, 0, -30)).Position, 60), arena.Position)
	end
	add("Gym", ground(GymDefinitions.Origin.Position, 12), GymDefinitions.Origin.Position + V3(0, 0, -30))
	return shots
end

local function show(shot)
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	if character then
		character.HumanoidRootPart.Anchored = true
		character:PivotTo(shot.Foot + V3(-5, 4, 0))
	end
	local nightmare = player and Workspace:FindFirstChild("Nightmare_" .. player.UserId, true)
	if nightmare then
		nightmare:PivotTo(shot.Foot + V3(5, 5, 0))
	end
	Workspace:SetAttribute("ShotName", shot.Name)
	Workspace:SetAttribute("ShotCam", shot.Cam)
	Workspace:SetAttribute("ShotLook", shot.Look)
end

function SceneLab.Go(name: string)
	for _, shot in buildShots() do
		if shot.Name == name then
			show(shot)
			return
		end
	end
	warn("[SceneLab] no shot named", name)
end

-- (`only`: just these shots, e.g. { "Scrap_Route", "Gym" })
function SceneLab.Tour(seconds: number, only: { string }?)
	task.spawn(function()
		for _, shot in buildShots() do
			if not only or table.find(only, shot.Name) then
				show(shot)
				task.wait(seconds)
			end
		end
		Workspace:SetAttribute("ShotName", "END")
	end)
end

return SceneLab
