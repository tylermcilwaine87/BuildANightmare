--[[
	HandlerAnimator  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/HandlerAnimator

	Animations for every Handler (player character), driven by Shared/AnimationDefinitions:
	  * Run / Walk: swaps Roblox's default cycles for the ids in the definitions (checked
	    first: an id that fails to load keeps the default, so movement never breaks).
	  * Play(slot): a move with an uploaded Id plays that animation; otherwise its built-in
	    CODE animation (HandlerPoses) plays: joint poses blended over time, applied after
	    Roblox's animations each frame (RunService.Stepped), so they override for their
	    duration.
	  * Other players: code poses are written locally, so they don't replicate by
	    themselves. The server stamps each move on the character ("HPose" attribute) and
	    every client plays it on that character too, so everyone sees your punches, kicks,
	    dives and get-ups. (Uploaded animations replicate on their own.)
	  * Ragdoll (PlayerFX "Ragdoll"): throws you, then GetUp when the knockdown ends.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local AnimationDefinitions = require(Shared:WaitForChild("AnimationDefinitions"))
local Melee = require(Shared:WaitForChild("MeleeDefinitions"))
local Config = require(Shared:WaitForChild("Config"))
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local studioKeyframes -- (defined with the API below)
local POSES = require(script.Parent:WaitForChild("HandlerPoses"))

local HandlerAnimator = {}

local localPlayer = Players.LocalPlayer
local SLOTS = AnimationDefinitions.Handler
local CULL_DISTANCE = 150 -- other players further than this aren't animated
local BLEND_TIME = 0.07 -- seconds a new move blends out of the previous pose
local IS_STUDIO = RunService:IsStudio()
local HttpService = game:GetService("HttpService")
local lab = {} -- the Studio pose lab (see applyAll)

local JOINTS = { "Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftHip", "RightHip", "LeftKnee", "RightKnee" }
local UPPER_BODY = { "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow" }

local rigs = {} -- [Model] = { motors = {}, pose = { Def, Start }?, isLocal }
local tracks = {} -- [slot] = AnimationTrack (uploaded animations on YOUR character)

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function angleAt(def, joint: string, t: number): (number, number, number)
	local keys = def.Keys
	local prev, nextKey = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i].T and t <= keys[i + 1].T then
			prev, nextKey = keys[i], keys[i + 1]
			break
		end
	end
	local a = prev[joint] or { 0, 0, 0 }
	local b = nextKey[joint] or { 0, 0, 0 }
	local span = nextKey.T - prev.T
	local k = span > 0 and smooth(math.clamp((t - prev.T) / span, 0, 1)) or 1
	return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

-- RUN STYLES (MeleeDefinitions.Runs, the character's "RunStyle" attribute): Roblox's
-- running legs stay; on top, each style poses the body and arms. Every player's style
-- plays on everyone's screen, and any strike takes over instantly.
--   add(joint, x, y, z)  turns the joint further by these degrees
--   set(joint, x, y, z)  blends the joint toward exactly this angle
local RUN_STYLES = {
	-- leaning in, fists up and pumping: rushing someone to hit them
	Charge = function(add, set, pump)
		add("Root", -14, 0, 0)
		add("Waist", -8, 0, 0)
		add("Neck", 12, 0, 0)
		set("LeftShoulder", 40 + pump * 28, 0, -12)
		set("RightShoulder", 40 - pump * 28, 0, 12)
		set("LeftElbow", 95 - pump * 10, 0, 0)
		set("RightElbow", 95 + pump * 10, 0, 0)
	end,
	-- bent double, arms streaming straight back
	Ninja = function(add, set)
		add("Root", -30, 0, 0)
		add("Waist", -10, 0, 0)
		add("Neck", 28, 0, 0)
		set("LeftShoulder", -74, 0, -8)
		set("RightShoulder", -74, 0, 8)
		set("LeftElbow", 6, 0, 0)
		set("RightElbow", 6, 0, 0)
	end,
	-- shoulders rolling, arms out wide
	Swagger = function(add, set, pump)
		add("Root", -4, pump * 14, 0)
		add("Neck", 6, -pump * 8, 0)
		set("LeftShoulder", 12 - pump * 18, 0, -32)
		set("RightShoulder", 12 + pump * 18, 0, 32)
		set("LeftElbow", 26, 0, 0)
		set("RightElbow", 26, 0, 0)
	end,
	-- arms straight out, head lolling
	Zombie = function(add, set, pump, slow)
		add("Root", -8, 0, slow * 6)
		add("Neck", -14, slow * 12, 12)
		set("LeftShoulder", 86, 0, -6 + pump * 3)
		set("RightShoulder", 86, 0, 6 + pump * 3)
		set("LeftElbow", 4, 0, 0)
		set("RightElbow", 4, 0, 0)
	end,
	-- elbows flapping, head bobbing
	Chicken = function(add, set, _, _, fast)
		local flap = 40 + 36 * math.abs(fast)
		add("Root", -14, 0, 0)
		add("Neck", -12 + 16 * fast, 0, 0)
		set("LeftShoulder", 25, 0, -flap)
		set("RightShoulder", 25, 0, flap)
		set("LeftElbow", 125, 0, 0)
		set("RightElbow", 125, 0, 0)
	end,
	-- low and heavy, knuckles swinging at the floor
	Gorilla = function(add, set, pump)
		add("Root", -40, 0, 0)
		add("Waist", -10, 0, 0)
		add("Neck", 34, 0, 0)
		set("LeftShoulder", 22 + pump * 45, 0, -14)
		set("RightShoulder", 22 - pump * 45, 0, 14)
		set("LeftElbow", 10, 0, 0)
		set("RightElbow", 10, 0, 0)
	end,
	-- one fist punching the sky
	Superhero = function(add, set, pump)
		add("Root", -16, 0, 0)
		add("Neck", 8, 0, 0)
		set("RightShoulder", 172, 0, 8)
		set("RightElbow", 0, 0, 0)
		set("LeftShoulder", -25 + pump * 20, 0, -12)
		set("LeftElbow", 30, 0, 0)
	end,
}

local runWeight = 0 -- your own character's (also read by holdFor)

-- Is this character running flat out right now? (Your own: your input; others: speed.)
local function isRunning(rig): (boolean, number)
	local model = rig.model
	if model:GetAttribute("Ragdolled") or model:GetAttribute("Diving") then
		return false, 0
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if rig.isLocal then
		if not humanoid then
			return false, 0
		end
		return humanoid.MoveDirection.Magnitude > 0.5 and humanoid:GetState() == Enum.HumanoidStateType.Running and humanoid.WalkSpeed >= 12, humanoid.WalkSpeed
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, 0
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	return speed > 11 and math.abs(v.Y) < 8, speed
end

local function applyRun(rig, dt: number)
	if SLOTS.Run.Id ~= "" then
		return -- an uploaded run animation replaces the styles
	end
	local running, speed = isRunning(rig)
	rig.runWeight = math.clamp((rig.runWeight or 0) + (running and dt or -dt) / 0.18, 0, 1)
	if rig.isLocal then
		runWeight = rig.runWeight
	end
	if rig.runWeight <= 0 then
		return
	end
	local style = RUN_STYLES[rig.model:GetAttribute("RunStyle") or "Charge"] or RUN_STYLES.Charge
	local motors = rig.motors
	local w = smooth(rig.runWeight)
	local phase = os.clock() * 9 * (math.max(speed, 12) / 16)
	local function add(joint: string, x: number, y: number, z: number)
		local motor = motors[joint]
		if motor then
			motor.Transform = motor.Transform * CFrame.Angles(math.rad(x * w), math.rad(y * w), math.rad(z * w))
		end
	end
	local function set(joint: string, x: number, y: number, z: number)
		local motor = motors[joint]
		if motor then
			motor.Transform = motor.Transform:Lerp(CFrame.Angles(math.rad(x), math.rad(y), math.rad(z)), w)
		end
	end
	style(add, set, math.sin(phase), math.sin(phase * 0.5), math.sin(phase * 2))
end

-- The overlay to hold while no move is playing: the weapon's hold pose, or (your own
-- character, fists up, in a fight) the fighting guard.
local function holdFor(rig): string?
	local model = rig.model
	local weapon = Melee.WeaponsById[model:GetAttribute("Weapon") or ""]
	if weapon then
		return weapon.Hold
	end
	if rig.isLocal and model:GetAttribute("InFight") and runWeight <= 0 then
		return "Guard"
	end
	return nil
end

-- Blends a Hold pose's single key over whatever Roblox's animations did this frame.
local function applyHold(rig, dt: number)
	local wanted = holdFor(rig)
	if wanted and wanted ~= rig.holdSlot then
		rig.holdSlot = wanted
	end
	rig.holdWeight = math.clamp((rig.holdWeight or 0) + (wanted and dt or -dt) / 0.15, 0, 1)
	local def = rig.holdSlot and POSES[rig.holdSlot]
	if not def or rig.holdWeight <= 0 then
		if rig.holdWeight <= 0 then
			rig.holdSlot = nil
		end
		return
	end
	local w = smooth(rig.holdWeight)
	for joint, angles in def.Keys[1] do
		local motor = joint ~= "T" and rig.motors[joint]
		if motor and motor.Parent then
			motor.Transform = motor.Transform:Lerp(CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3])), w)
		end
	end
end

local function applyRig(rig, now: number, dt: number, cameraPosition: Vector3?)
	local pose = rig.pose
	if not rig.isLocal and cameraPosition then
		local root = rig.model:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - cameraPosition).Magnitude > CULL_DISTANCE then
			return
		end
	end
	if not pose and rig.isLocal then
		-- an animation asset (uploaded, or previewed in Studio) is playing: it owns the body
		for _, track in tracks do
			if track.IsPlaying and track.WeightCurrent > 0.05 then
				rig.holdWeight, rig.runWeight, runWeight = 0, 0, 0
				return
			end
		end
	end
	if not pose then
		local weaponOut = (rig.model:GetAttribute("Weapon") or "Fists") ~= "Fists"
		if weaponOut then
			rig.runWeight = 0
			if rig.isLocal then
				runWeight = 0
			end
		else
			applyRun(rig, dt)
		end
		applyHold(rig, dt)
		return
	end
	rig.holdWeight = 0 -- a move takes over the arms; the hold blends back in after it
	rig.runWeight = 0
	if rig.isLocal then
		runWeight = 0
	end
	local t = now - pose.Start
	if pose.HoldUntil then
		if now < pose.HoldUntil then
			t = pose.HoldAt -- hit-stop: frozen on the frame the blow landed
		else
			pose.HoldUntil = nil
		end
	end
	local def = pose.Def
	if t > def.Duration then
		rig.pose = nil
		return
	end
	-- the first moments of a move blend from wherever the body was (the last strike, a
	-- run...) so combos flow from one strike into the next instead of snapping
	local blend = pose.From and t < BLEND_TIME and smooth(t / BLEND_TIME) or nil
	for _, joint in def.UpperBody and UPPER_BODY or JOINTS do
		local motor = rig.motors[joint]
		if motor and motor.Parent then
			local x, y, z = angleAt(def, joint, t)
			local target = CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
			if joint == "Root" then
				-- RootPos (studs, -Z = forward): the whole body shifting its weight, dipping...
				local px, py, pz = angleAt(def, "RootPos", t)
				target = CFrame.new(px, py, pz) * target
			end
			local from = blend and pose.From[joint]
			motor.Transform = from and from:Lerp(target, blend) or target
		end
	end
end

local lastStep = os.clock()
local function applyAll()
	local now = os.clock()
	local dt = math.min(now - lastStep, 0.1)
	lastStep = now
	local camera = workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position
	-- Studio scrubbing (for reviewing a move frame by frame): workspace attributes
	-- ScrubPose = "Overhand", ScrubTime = 0.31 hold your character on that frame
	-- (ScrubTime < 0 loops the move in real time). ScrubPose = "Lab" plays the pose in the
	-- PoseLab attribute (JSON), so a move can be tuned live from the command bar.
	if IS_STUDIO then
		local slot, at = workspace:GetAttribute("ScrubPose"), workspace:GetAttribute("ScrubTime")
		local rig = localPlayer.Character and rigs[localPlayer.Character]
		local def = type(slot) == "string" and (POSES[slot] or POSES[(SLOTS[slot] and SLOTS[slot].Code) or ""])
		if slot == "Lab" then
			local source = workspace:GetAttribute("PoseLab")
			if source ~= lab.Source then
				lab.Source = source
				local ok, decoded = pcall(HttpService.JSONDecode, HttpService, source)
				lab.Def = ok and type(decoded) == "table" and decoded or nil
			end
			def = lab.Def
		end
		if rig and def and type(at) == "number" then
			local time = at >= 0 and math.clamp(at, 0, def.Duration) or (now % (def.Duration + 0.5))
			rig.pose = { Def = def, Start = now - math.min(time, def.Duration) }
		end
	end
	for model, rig in rigs do
		if not model.Parent then
			rigs[model] = nil
		else
			applyRig(rig, now, dt, cameraPosition)
		end
	end
end

-- Starts a code pose on a character (by slot name).
local function playPose(model: Model?, slot: string)
	local rig = model and rigs[model]
	local def = SLOTS[slot]
	local pose = POSES[(def and def.Code) or slot]
	if rig and pose then
		-- remember the body as it is right now: the new move blends out of it
		local from = {}
		for joint, motor in rig.motors do
			if motor.Parent then
				from[joint] = motor.Transform
			end
		end
		rig.pose = { Def = pose, Start = os.clock(), From = from }
	end
end

------------------------------------------------------------------------------------------
-- Character setup
------------------------------------------------------------------------------------------
-- Checks an animation id actually loads before using it.
local function idWorks(id: string): boolean
	if id == "" then
		return false
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok = pcall(function()
		ContentProvider:PreloadAsync({ animation })
	end)
	if not ok then
		return false
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	local loaded, track = pcall(animator.LoadAnimation, animator, animation)
	if not loaded or not track then
		return false
	end
	local deadline = os.clock() + 4
	while track.Length == 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	local good = track.Length > 0
	track:Destroy()
	return good
end

-- Run / Walk: point the default Animate script at our animations.
local function applyMovementAnimations(character: Model)
	local animate = character:WaitForChild("Animate", 10)
	if not animate then
		return
	end
	for slot, folderName in { Run = "run", Walk = "walk" } do
		local def = SLOTS[slot]
		-- (no Id: Run uses the charge style on top of the default legs, see applyCombatRun)
		if def and def.Id ~= "" and idWorks(def.Id) then
			local folder = animate:FindFirstChild(folderName)
			if folder then
				for _, animation in folder:GetChildren() do
					if animation:IsA("Animation") then
						animation.AnimationId = def.Id
					end
				end
			end
		end
	end
end

-- Registers any player's character for code poses.
local function trackCharacter(character: Model, isLocal: boolean)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return -- code poses are written for R15 rigs
	end
	task.wait(0.5)
	if not character.Parent then
		return
	end
	-- Classic rigs use Motor6D joints; avatars with Roblox's joint upgrade use
	-- AnimationConstraint joints (same names, same Transform). Either works.
	local motors = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and table.find(JOINTS, d.Name) then
			motors[d.Name] = d
		end
	end
	rigs[character] = { model = character, motors = motors, pose = nil, isLocal = isLocal }

	if isLocal then
		return
	end
	-- Another player: play the moves the server stamps on them ("Name#count").
	character:GetAttributeChangedSignal("HPose"):Connect(function()
		local stamp = character:GetAttribute("HPose")
		local slot = type(stamp) == "string" and stamp:match("^([^#]+)")
		local def = slot and SLOTS[slot]
		if slot and not (def and def.Id ~= "") then -- uploaded animations replicate themselves
			playPose(character, slot)
		end
	end)
	-- ...and their get-up after a knockdown
	character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if character:GetAttribute("Ragdolled") then
			local rig = rigs[character]
			if rig then
				rig.pose = nil
			end
			return
		end
		local torso = character:FindFirstChild("UpperTorso")
		playPose(character, torso and torso.CFrame.LookVector.Y > 0.25 and "GetUpBack" or "GetUpFront")
	end)
end

local function onLocalCharacter(character: Model)
	table.clear(tracks)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	task.spawn(applyMovementAnimations, character)
	if not humanoid:GetAttribute("BaseHipHeight") then
		humanoid:SetAttribute("BaseHipHeight", humanoid.HipHeight)
	end
	-- Stand up when a knockdown ends, the right way for how you landed.
	character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if character:GetAttribute("Ragdolled") then
			return
		end
		local torso = character:FindFirstChild("UpperTorso")
		-- the torso's front faces the sky = on your back
		HandlerAnimator:GetUp(torso ~= nil and torso.CFrame.LookVector.Y > 0.25)
	end)
	trackCharacter(character, true)
end

-- Puts the body back together around the root, in the rig's own layout: walks the joint
-- tree out from the HumanoidRootPart and places each part where its joint says it goes.
-- (After a ragdoll the limbs are wherever they fell; Roblox would never stand you up.)
local function snapToRig(character: Model, rootCF: CFrame)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local links = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(links, { d.Part0, d.Part1, d.C0, d.C1 })
		elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			table.insert(links, { d.Attachment0.Parent, d.Attachment1.Parent, d.Attachment0.CFrame, d.Attachment1.CFrame })
		end
	end
	root.CFrame = rootCF
	local placed = { [root] = true }
	local progress = true
	while progress do
		progress = false
		for _, link in links do
			local part0, part1 = link[1], link[2]
			if placed[part0] and not placed[part1] and part1:IsA("BasePart") then
				part1.CFrame = part0.CFrame * link[3] * link[4]:Inverse()
				placed[part1] = true
				progress = true
			end
		end
	end
	for part in placed do
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end
end

-- Rises from floor level: the body starts low and the hips come up as the pose plays.
function HandlerAnimator:GetUp(faceUp: boolean)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local base = humanoid:GetAttribute("BaseHipHeight") or humanoid.HipHeight
	local slot = faceUp and "GetUpBack" or "GetUpFront"
	local pose = POSES[SLOTS[slot].Code or ""]
	local duration = pose and pose.Duration or 0.9

	-- Stand the body up where it lies: hips at floor level, facing the way you get up
	-- (face-down: toward where your head was; on your back: toward your feet).
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
	local hips = character:FindFirstChild("LowerTorso") :: BasePart?
	if root and torso and hips and humanoid.Health > 0 then
		local headward = Vector3.new(torso.CFrame.UpVector.X, 0, torso.CFrame.UpVector.Z)
		local facing = headward.Magnitude > 0.1 and headward.Unit * (faceUp and -1 or 1) or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(hips.Position + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
		local floorY = hit and hit.Position.Y or hips.Position.Y - 1
		local at = Vector3.new(hips.Position.X, floorY + base * 0.25 + root.Size.Y / 2 + 0.05, hips.Position.Z)
		humanoid.PlatformStand = false
		snapToRig(character, CFrame.lookAt(at, at + facing))
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	humanoid.HipHeight = base * 0.25
	TweenService:Create(humanoid, TweenInfo.new(duration * 0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { HipHeight = base }):Play()
	self:Play(slot)
end

-- Studio preview of an editable animation asset: Shared/Animations/<Code> (a
-- KeyframeSequence) registered with KeyframeSequenceProvider for a temporary id. Studio
-- only (Config.Dev.PreviewKeyframesInStudio); nil anywhere else, or if there's no asset.
local studioIds = {} -- [name] = id | false
function studioKeyframes(slot: string): string?
	if not IS_STUDIO or not Config.Dev.PreviewKeyframesInStudio then
		return nil
	end
	local def = SLOTS[slot]
	local name = (def and def.Code) or slot
	if studioIds[name] == nil then
		studioIds[name] = false
		local folder = Shared:FindFirstChild("Animations")
		local sequence = folder and folder:FindFirstChild(name)
		if sequence and sequence:IsA("KeyframeSequence") then
			local ok, result = pcall(KeyframeSequenceProvider.RegisterKeyframeSequence, KeyframeSequenceProvider, sequence)
			if ok and type(result) == "string" then
				studioIds[name] = result
			else
				warn("[HandlerAnimator] couldn't preview", name, result)
			end
		end
	end
	return studioIds[name] or nil
end

------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------
-- Plays a move on YOUR character: its uploaded animation if the slot has an Id, else its
-- code animation. (Everyone else sees it through the server's "HPose" stamp.)
function HandlerAnimator:Play(slot: string, speed: number?)
	local def = SLOTS[slot]
	local id = (def and def.Id ~= "" and def.Id) or studioKeyframes(slot)
	if id then
		local track = tracks[slot]
		if not track then
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
			if animator then
				local animation = Instance.new("Animation")
				animation.AnimationId = id
				local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
				if ok then
					track = loaded
					track.Priority = Enum.AnimationPriority.Action2
					tracks[slot] = track
				end
			end
		end
		if track then
			-- the animation takes over from whatever code pose was still finishing
			local rig = localPlayer.Character and rigs[localPlayer.Character]
			if rig then
				rig.pose = nil
			end
			track:Play(0.05, 1, speed or 1)
			return
		end
	end
	playPose(localPlayer.Character, slot)
end

-- How long a slot's code pose lasts (e.g. one stride of the sprint, to loop it).
function HandlerAnimator:Duration(slot: string): number?
	local def = SLOTS[slot]
	local pose = POSES[(def and def.Code) or slot]
	return pose and pose.Duration
end

-- Hit-stop: your strike landed, so your body freezes on that frame for `duration` seconds
-- and then carries on exactly where it was (the move runs that much longer). The tiny
-- pause is what makes a blow feel like it hit something solid.
function HandlerAnimator:HitStop(duration: number)
	local rig = localPlayer.Character and rigs[localPlayer.Character]
	local pose = rig and rig.pose
	if pose and not pose.HoldUntil then
		local now = os.clock()
		pose.HoldAt = now - pose.Start
		pose.HoldUntil = now + duration
		pose.Start += duration
	end
	local track = nil
	for _, t in tracks do
		if t.IsPlaying then
			track = t
		end
	end
	if track then -- (an uploaded animation: pause it the same way)
		local speed = track.Speed
		track:AdjustSpeed(0)
		task.delay(duration, function()
			track:AdjustSpeed(speed > 0 and speed or 1)
		end)
	end
end

-- Stops whatever code pose your character is in (e.g. knocked down mid-punch).
function HandlerAnimator:Stop()
	local rig = localPlayer.Character and rigs[localPlayer.Character]
	if rig then
		rig.pose = nil
	end
end

function HandlerAnimator:Init() end

function HandlerAnimator:Start()
	if localPlayer.Character then
		task.spawn(onLocalCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onLocalCharacter)
	local function watchPlayer(player: Player)
		if player == localPlayer then
			return
		end
		if player.Character then
			task.spawn(trackCharacter, player.Character, false)
		end
		player.CharacterAdded:Connect(function(character)
			trackCharacter(character, false)
		end)
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	-- After Roblox's animations, before physics: our poses win for their duration.
	RunService.Stepped:Connect(applyAll)

	Net.Get("PlayerFX").OnClientEvent:Connect(function(kind, data)
		if kind == "Ragdoll" and type(data) == "table" then
			HandlerAnimator:Stop()
			local character = localPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and typeof(data.Velocity) == "Vector3" then
				-- tip over backwards, away from the hit (plus a touch of randomness)
				local spin = typeof(data.Spin) == "Vector3" and data.Spin or Vector3.zero
				spin += Vector3.new(math.random(-10, 10), math.random(-15, 15), math.random(-10, 10)) / 10
				-- Throw the WHOLE body: with physics joints every limb is its own assembly,
				-- so each one gets the launch plus its share of the tumble around the root.
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.PlatformStand = true -- limp now, not a frame later
				end
				local center = root.Position
				for _, part in character:GetDescendants() do
					if part:IsA("BasePart") and not part.Anchored and part.AssemblyRootPart == part then
						part.AssemblyLinearVelocity = data.Velocity + spin:Cross(part.Position - center)
						part.AssemblyAngularVelocity = spin
					end
				end
			end
		end
	end)
end

return HandlerAnimator
