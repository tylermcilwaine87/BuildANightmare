--[[
	LockOnController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/LockOnController

	Lock-on camera (Config.LockOn). Toggle with Z (keyboard), Select / View (gamepad) or
	the LOCK button (phones):
	  * Locks onto the nearest boss in range, otherwise the enemy you're looking at.
	  * The camera sits behind you and keeps you and the target in frame; your character
	    faces the target, so you can strafe and dive around it.
	  * Works on whichever body you control: your Handler, or your Nightmare while you
	    POSSESS it. A lock carries straight over when you possess / release (the camera
	    glides to the new body), and Z locks on from inside a possession too.
	  * Releases by itself when the target dies or gets too far away, when you're knocked
	    out, or during a scripted camera reveal.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local LockOnController = {}

local CFG = Config.LockOn
local localPlayer = Players.LocalPlayer
local controllers
local target: Model? = nil
local smoothCF: CFrame? = nil
local lockedAt = 0
local releasing = nil -- { From: CFrame, Start: number } while gliding back after unlocking
local lockButton: TextButton? = nil

function LockOnController:Init(registry)
	controllers = registry
end

local function rootOf(model: Model?): BasePart?
	return model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function alive(model: Model?): boolean
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and not model:GetAttribute("Defeated")
end

-- The body you're controlling right now: the possessed Nightmare, else your character.
local function body(): Model?
	local possessed = controllers.PossessionController:IsPossessing() and controllers.PossessionController:GetModel()
	return possessed or localPlayer.Character
end

local lockedBody: Model? = nil -- the body whose AutoRotate the lock turned off

local function setAutoRotate(model: Model?, on: boolean)
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = on
	end
end

function LockOnController:IsLocked(): boolean
	return target ~= nil
end

function LockOnController:GetTarget(): Model?
	return target
end

-- Nearest living boss in range, else the enemy best aligned with the camera.
function LockOnController:Pick(): Model?
	local myRoot = rootOf(body())
	if not myRoot then
		return nil
	end
	local best, bestDistance = nil, CFG.Range
	for _, model in CollectionService:GetTagged("Boss") do
		local root = rootOf(model)
		if root and alive(model) then
			local distance = (root.Position - myRoot.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best or controllers.CombatController:FindBestTarget()
end

function LockOnController:Lock(model: Model)
	self:Release()
	local root = rootOf(model)
	if not root then
		return
	end
	target = model
	-- glide from wherever the camera is now (no snap)
	smoothCF = Workspace.CurrentCamera.CFrame
	lockedAt = os.clock()
	releasing = nil
	lockedBody = body()
	setAutoRotate(lockedBody, false)
	if lockButton then
		lockButton.Text = "UNLOCK"
	end
end

function LockOnController:Release()
	-- glide back to the normal camera instead of snapping
	if target and smoothCF then
		releasing = { From = smoothCF, Start = os.clock() }
	end
	target = nil
	smoothCF = nil
	setAutoRotate(lockedBody, true)
	lockedBody = nil
	if lockButton then
		lockButton.Text = "LOCK"
	end
end

function LockOnController:Toggle()
	if target then
		self:Release()
		return
	end
	local picked = self:Pick()
	if picked then
		self:Lock(picked)
	else
		controllers.HUDController:Toast("Nothing to lock on to. Look toward an enemy.", nil, 1.5)
	end
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function update(dt: number)
	dt = math.min(dt or 1 / 60, 0.1)
	if releasing then
		local t = (os.clock() - releasing.Start) / CFG.ReleaseTime
		if t >= 1 then
			releasing = nil
		else
			-- the default camera has just placed itself; blend from our last lock view to it
			Workspace.CurrentCamera.CFrame = releasing.From:Lerp(Workspace.CurrentCamera.CFrame, ease(t))
		end
	end
	if not target then
		return
	end
	-- possessing / releasing swaps the body you control: keep the lock and glide over
	local character = body()
	if character ~= lockedBody then
		setAutoRotate(lockedBody, true)
		lockedBody = character
		setAutoRotate(lockedBody, false)
		lockedAt = os.clock()
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local myRoot = rootOf(character)
	local targetRoot = rootOf(target)
	if not humanoid or humanoid.Health <= 0 or not myRoot or not targetRoot or not alive(target)
		or (targetRoot.Position - myRoot.Position).Magnitude > CFG.BreakRange
		or (controllers.WorldController and controllers.WorldController:IsCameraBusy()) then
		LockOnController:Release()
		return
	end
	local toTarget = Util.FlatUnit(targetRoot.Position - myRoot.Position)
	if not toTarget then
		return
	end
	-- turn smoothly to face the target (not while knocked down: let the ragdoll tumble;
	-- not mid-dive: you face the way you roll, then turn back to the target after)
	if not character:GetAttribute("Ragdolled") and not character:GetAttribute("Diving") then
		local look = Util.FlatUnit(myRoot.CFrame.LookVector) or toTarget
		local turned = look:Lerp(toTarget, 1 - math.exp(-14 * dt))
		if turned.Magnitude > 0.01 then
			myRoot.CFrame = CFrame.lookAt(myRoot.Position, myRoot.Position + turned.Unit)
		end
	end
	local height = targetRoot.Size.Y / 2
	-- a big possessed Nightmare pushes the camera further back and up
	local bulk = math.max(0, math.max(myRoot.Size.X, myRoot.Size.Y, myRoot.Size.Z) - 2)
	local focus = myRoot.Position:Lerp(targetRoot.Position + Vector3.new(0, height * 0.5, 0), 0.35) + Vector3.new(0, 2.5 + bulk * 0.3, 0)
	local goal = CFrame.lookAt(myRoot.Position - toTarget * (CFG.Distance + bulk * 1.5) + Vector3.new(0, CFG.Height + bulk * 0.6, 0), focus)
	-- the glide starts gentle and settles into a tight follow over LockInTime
	local settle = ease((os.clock() - lockedAt) / CFG.LockInTime)
	local rate = 3 + 9 * settle
	smoothCF = (smoothCF or Workspace.CurrentCamera.CFrame):Lerp(goal, 1 - math.exp(-rate * dt))
	Workspace.CurrentCamera.CFrame = smoothCF
end

function LockOnController:Start()
	-- After the default camera (and before the camera shake, which runs at +2).
	RunService:BindToRenderStep("LockOnCamera", Enum.RenderPriority.Camera.Value + 1, update)
	localPlayer.CharacterAdded:Connect(function()
		self:Release()
	end)

	-- Phones: a LOCK button.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local gui = Instance.new("ScreenGui")
		gui.Name = "LockOnButton"
		gui.ResetOnSpawn = false
		gui.Parent = localPlayer:WaitForChild("PlayerGui")
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -16, 0.42, 0)
		button.Size = UDim2.fromOffset(74, 74)
		button.BackgroundColor3 = Color3.fromRGB(40, 20, 26)
		button.BackgroundTransparency = 0.2
		button.TextColor3 = Color3.fromRGB(255, 90, 90)
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 15
		button.Text = "LOCK"
		button.Parent = gui
		Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)
		button.Activated:Connect(function()
			self:Toggle()
		end)
		lockButton = button
	end
end

return LockOnController
