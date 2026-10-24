--[[
	AnimationExporter  (ModuleScript, DEV TOOL)
	Location: ServerStorage/DevTools/AnimationExporter   (Rojo: tools/, never shipped to players)

	Turns a move's keyframes (the tables in HandlerPoses / NightmarePoses / BossPoses, tuned
	in Studio with the pose lab) into a REAL animation asset: a KeyframeSequence that the
	Animation Editor can open and Roblox can publish.

	  local Exporter = require(game.ServerStorage.DevTools.AnimationExporter:Clone())
	  Exporter.Export("Handler", { "Jab", "Cross", "Hook", "Overhand" })
	  -> ServerStorage.AnimationExport.Handler (a Folder of KeyframeSequences), selected.
	  Then: right-click it > Save / Export > Save to File >
	  src/shared/Animations/Handler.rbxm   (Rojo syncs it to Shared/Animations/Handler)

	(Clone() so Studio's command bar doesn't hand back a cached copy of the pose module.)

	Pose data format (any rig):
	  { Duration, Keys = { { T = seconds, <JointName> = { x, y, z } degrees, ... } },
	    Markers = { { T, "Hit" }, ... } }
	  A joint missing from a key is neutral (0, 0, 0), exactly as the code player treats it.
	  The rig's root joint may also carry a translation: Handler "RootPos", others
	  "<RootJoint>Pos" (e.g. Joint_CorePos) = { x, y, z } studs.

	Every keyframe uses Cubic In/Out easing = the code player's smoothstep, so the asset
	moves exactly like the tuned code version (measured: identical to 0.01 stud).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerStorage = game:GetService("ServerStorage")

local Exporter = {}

-- R15 Handler joints -> { part, parent part } (the avatar's joint names)
local HANDLER_RIG = {
	Root = { "LowerTorso", "HumanoidRootPart" },
	Waist = { "UpperTorso", "LowerTorso" },
	Neck = { "Head", "UpperTorso" },
	RightShoulder = { "RightUpperArm", "UpperTorso" },
	RightElbow = { "RightLowerArm", "RightUpperArm" },
	RightWrist = { "RightHand", "RightLowerArm" },
	LeftShoulder = { "LeftUpperArm", "UpperTorso" },
	LeftElbow = { "LeftLowerArm", "LeftUpperArm" },
	LeftWrist = { "LeftHand", "LeftLowerArm" },
	RightHip = { "RightUpperLeg", "LowerTorso" },
	RightKnee = { "RightLowerLeg", "RightUpperLeg" },
	RightAnkle = { "RightFoot", "RightLowerLeg" },
	LeftHip = { "LeftUpperLeg", "LowerTorso" },
	LeftKnee = { "LeftLowerLeg", "LeftUpperLeg" },
	LeftAnkle = { "LeftFoot", "LeftLowerLeg" },
}

-- Reads a rig's joints off a real model: Motor6D name -> { Part1 name, Part0 name }.
function Exporter.RigFromModel(model: Model)
	local rig = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			rig[d.Name] = { d.Part1.Name, d.Part0.Name }
		end
	end
	return rig
end

local function freshRequire(module: ModuleScript)
	return require(module:Clone())
end

-- Nightmare skeleton (NightmareAssembler): Motor6D name -> { part, parent part }. Slots a
-- Nightmare doesn't have are simply absent at play time.
local NIGHTMARE_RIG = {
	Joint_Core = { "Core_Root", "HumanoidRootPart" },
	Joint_Head = { "Head_Root", "Core_Root" },
	Sub_Head_Jaw = { "Head_Jaw", "Head_Root" }, -- hinged jaw (bite heads)
	Joint_RightArm = { "RightArm_Root", "Core_Root" },
	Joint_LeftArm = { "LeftArm_Root", "Core_Root" },
	Sub_RightArm_Fore = { "RightArm_Fore", "RightArm_Root" }, -- elbows (PartDefinitions arm Groups)
	Sub_LeftArm_Fore = { "LeftArm_Fore", "LeftArm_Root" },
	Joint_Legs = { "Legs_Root", "Core_Root" },
	Sub_Legs_L = { "Legs_L", "Legs_Root" },
	Sub_Legs_R = { "Legs_R", "Legs_Root" },
	Sub_Legs_FL = { "Legs_FL", "Legs_Root" }, -- four legs (Quadruped)
	Sub_Legs_FR = { "Legs_FR", "Legs_Root" },
	Sub_Legs_BL = { "Legs_BL", "Legs_Root" },
	Sub_Legs_BR = { "Legs_BR", "Legs_Root" },
	Joint_Back = { "Back_Root", "Core_Root" },
	Sub_Back_L = { "Back_L", "Back_Root" }, -- wings
	Sub_Back_R = { "Back_R", "Back_Root" },
	Joint_Tail = { "Tail_Root", "Core_Root" },
}

-- The pose libraries by rig kind. Nightmare animations are named
-- Nightmare_<Archetype>_<Action> (what NightmareAnimator / AnimationDefinitions look up).
local SOURCES = {
	Handler = function()
		return freshRequire(StarterPlayer.StarterPlayerScripts.Client.Controllers.HandlerPoses), HANDLER_RIG, "Root", "RootPos"
	end,
	ScrapTitan = function()
		local library = {}
		for action, def in freshRequire(StarterPlayer.StarterPlayerScripts.Client.Controllers.BossPoses).ScrapTitan do
			library["Boss_ScrapTitan_" .. action] = def
		end
		return library, {
			Joint_Core = { "Core_Root", "HumanoidRootPart" },
			Joint_Head = { "Head_Root", "Core_Root" },
			Joint_RightArm = { "RightArm_Root", "Core_Root" },
			Joint_LeftArm = { "LeftArm_Root", "Core_Root" },
			Sub_Legs_L = { "Legs_L", "Core_Root" },
			Knee_L = { "Shin_L", "Legs_L" },
			Sub_Legs_R = { "Legs_R", "Core_Root" },
			Knee_R = { "Shin_R", "Legs_R" },
		}, "Joint_Core", "Joint_CorePos"
	end,
	Nightmare = function()
		local library = {}
		for archetype, moves in freshRequire(StarterPlayer.StarterPlayerScripts.Client.Controllers.NightmarePoses) do
			for action, def in moves do
				library["Nightmare_" .. archetype .. "_" .. action] = def
			end
		end
		return library, NIGHTMARE_RIG, "Joint_Core", "Joint_CorePos"
	end,
}

-- Builds one KeyframeSequence. rig: joint -> { part, parent }. rootJoint/rootPosKey: the
-- joint whose key may carry a translation and the key holding it.
function Exporter.Build(name: string, def, rig, rootJoint: string?, rootPosKey: string?, priority)
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = def.Loop == true
	sequence.Priority = priority or Enum.AnimationPriority.Action2
	for _, key in def.Keys do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = key.T
		local poses = {}
		local function pose(part: string)
			local p = poses[part]
			if not p then
				p = Instance.new("Pose")
				p.Name = part
				p.Weight = 1
				p.EasingStyle = Enum.PoseEasingStyle.Cubic
				p.EasingDirection = Enum.PoseEasingDirection.InOut
				poses[part] = p
			end
			return p
		end
		for joint, link in rig do
			local angles = key[joint] or { 0, 0, 0 }
			local cframe = CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
			if joint == rootJoint and rootPosKey and key[rootPosKey] then
				local p = key[rootPosKey]
				cframe = CFrame.new(p[1], p[2], p[3]) * cframe
			end
			local child = pose(link[1])
			child.CFrame = cframe
			child.Parent = pose(link[2])
		end
		-- attach the tree: every pose without a parent pose hangs off the keyframe (the root)
		for _, p in poses do
			if not p.Parent then
				p.Weight = 0 -- the root part itself isn't animated
				p.Parent = keyframe
			end
		end
		for _, marker in def.Markers or {} do
			if math.abs(marker[1] - key.T) < 0.0005 then
				local m = Instance.new("KeyframeMarker")
				m.Name = marker[2]
				m.Value = marker[3] or ""
				keyframe:AddMarker(m)
			end
		end
		keyframe.Parent = sequence
	end
	return sequence
end

-- Exports `names` from a pose library into ServerStorage.AnimationExport.<kind> and
-- selects it (ready for Save to File). Markers must sit on a keyframe time; any that
-- don't get their own (interpolated-free) marker keyframe would change the motion, so
-- they're reported instead.
function Exporter.Export(kind: string, names: { string }, sourceOverride)
	local library, rig, rootJoint, rootPosKey
	if sourceOverride then
		library, rig, rootJoint, rootPosKey = sourceOverride()
	else
		library, rig, rootJoint, rootPosKey = SOURCES[kind]()
	end
	local exportRoot = ServerStorage:FindFirstChild("AnimationExport") or Instance.new("Folder")
	exportRoot.Name = "AnimationExport"
	exportRoot.Parent = ServerStorage
	local old = exportRoot:FindFirstChild(kind)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = kind
	for _, name in names do
		local def = library[name]
		assert(def, "no pose named " .. name)
		for _, marker in def.Markers or {} do
			local onKey = false
			for _, key in def.Keys do
				if math.abs(key.T - marker[1]) < 0.0005 then
					onKey = true
				end
			end
			if not onKey then
				warn(("[Exporter] %s marker %s at %.3f is not on a keyframe: add a key there"):format(name, marker[2], marker[1]))
			end
		end
		Exporter.Build(name, def, rig, rootJoint, rootPosKey).Parent = folder
	end
	folder.Parent = exportRoot
	game:GetService("Selection"):Set({ folder })
	print(("[Exporter] built %d animations into %s: right-click > Save / Export > Save to File > src/shared/Animations/%s.rbxm"):format(#names, folder:GetFullName(), kind))
	return folder
end

Exporter.HandlerRig = HANDLER_RIG
Exporter.NightmareRig = NIGHTMARE_RIG
Exporter.Sources = SOURCES
return Exporter
