--[[
	PossessionController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/PossessionController

	Client side of NIGHTMARE POSSESSION.
	  * F (gamepad: D-Pad Left, touch: POSSESS) asks the server to start or stop.
	  * On "PossessStart" (PlayerFX), the camera smoothly moves to the Nightmare, a purple
	    tint and timer appear, and your movement input (WASD / thumbstick / touch stick)
	    drives the NIGHTMARE. The server gave us network ownership, so it feels instant.
	  * Attack input is re-routed by InputController: LMB combo, Ctrl heavy, Shift dodge,
	    Q/E abilities, G ultimate, F exit. The server times and validates every hit.
	  * On "PossessEnd" everything is restored.
	No flashing and no forced camera shake: just a short FOV ease and a colour tint.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local PossessionController = {}

local localPlayer = Players.LocalPlayer
local controllers
local combatAction: RemoteEvent
local possessed: Model? = nil
local endsAt = 0
local tint: ColorCorrectionEffect? = nil
local lastDodge = -math.huge

function PossessionController:Init(registry)
	controllers = registry
	combatAction = Net.Get("CombatAction")
end

function PossessionController:IsPossessing(): boolean
	return possessed ~= nil
end

function PossessionController:GetModel(): Model?
	return possessed
end

function PossessionController:TimeLeft(): number
	return math.max(0, endsAt - os.clock())
end


function PossessionController:Toggle()
	if controllers.WorkshopController:IsOpen() then
		return
	end
	if not possessed then
		local character = localPlayer.Character
		local meter = character and character:GetAttribute("Possession") or 0
		local cooldownEnd = character and character:GetAttribute("PossessionCooldownEnd") or 0
		if meter < Config.Possession.MeterMax then
			controllers.HUDController:Toast(("Possession meter %d / %d. Fight, dodge and command to fill it!"):format(meter, Config.Possession.MeterMax), nil, 2)
			return
		elseif Workspace:GetServerTimeNow() < cooldownEnd then
			controllers.HUDController:Toast(("Possession recharging: %ds"):format(math.ceil(cooldownEnd - Workspace:GetServerTimeNow())), nil, 2)
			return
		end
	end
	combatAction:FireServer("Possess")
end

-- Turn the possessed body toward the lock-on target, else toward the camera (mouse users
-- aim with the camera).
local function faceCamera()
	if not possessed then
		return
	end
	local root = possessed:FindFirstChild("HumanoidRootPart")
	local locked = controllers.LockOnController:GetTarget()
	local lockedRoot = locked and locked:FindFirstChild("HumanoidRootPart")
	if root and lockedRoot then
		local toTarget = Util.FlatUnit(lockedRoot.Position - root.Position)
		if toTarget then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + toTarget)
		end
		return
	end
	if not (UserInputService.MouseEnabled and not UserInputService.TouchEnabled) then
		return
	end
	local look = Util.FlatUnit(Workspace.CurrentCamera.CFrame.LookVector)
	if root and look then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end
end

function PossessionController:Light()
	faceCamera()
	combatAction:FireServer("NM_Light")
end

function PossessionController:Heavy()
	faceCamera()
	combatAction:FireServer("NM_Heavy")
end

function PossessionController:Dodge()
	if not possessed then
		return
	end
	local cfg = Config.Possession
	local now = os.clock()
	if now - lastDodge < cfg.DodgeCooldown then
		return
	end
	lastDodge = now
	local root = possessed:FindFirstChild("HumanoidRootPart")
	local humanoid = possessed:FindFirstChildOfClass("Humanoid")
	local attachment = root and root:FindFirstChild("FacingAttachment")
	if not attachment then
		return
	end
	local direction = Util.FlatUnit(humanoid.MoveDirection) or -(Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis)
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.MaxForce = 1e6
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * cfg.DodgeSpeed
	mover.Parent = root
	task.delay(cfg.DodgeDuration, function()
		mover:Destroy()
	end)
	controllers.EffectsController:Afterimage(possessed)
	combatAction:FireServer("NM_Dodge")
end

local function onStart(data)
	local model = data.Model
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	possessed = model
	endsAt = os.clock() + (data.Duration or Config.Possession.Duration)
	controllers.CombatController:SetGuard(false)

	local camera = Workspace.CurrentCamera
	camera.CameraSubject = humanoid
	TweenService:Create(camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { FieldOfView = 78 }):Play()

	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "PossessionTint"
	tint.TintColor = Color3.new(1, 1, 1)
	tint.Saturation = 0
	tint.Parent = Lighting
	TweenService:Create(tint, TweenInfo.new(0.5), { TintColor = Color3.fromRGB(220, 200, 255), Saturation = -0.15, Contrast = 0.08 }):Play()

	controllers.HUDController:Toast("POSSESSION! You ARE your Nightmare.", Color3.fromRGB(200, 150, 255), 2)
	controllers.AudioController:Play("Possess")
end

local function onEnd(data)
	possessed = nil
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	TweenService:Create(camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { FieldOfView = 70 }):Play()
	if tint then
		local old = tint
		tint = nil
		TweenService:Create(old, TweenInfo.new(0.4), { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }):Play()
		task.delay(0.45, function()
			old:Destroy()
		end)
	end
	local reasons = {
		Interrupted = "Possession INTERRUPTED: your Handler was hit hard!",
		Expired = "Possession ended.",
		Released = "You released your Nightmare.",
		HandlerDown = "Possession ended: Handler knocked out.",
		NightmareDown = "Possession ended: your Nightmare fell.",
		TooFar = "Possession ended: too far from your Handler.",
	}
	controllers.HUDController:Toast(reasons[data.Reason] or "Possession ended.", nil, 2)
end

function PossessionController:Start()
	Net.Get("PlayerFX").OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" then
			return
		end
		if kind == "PossessStart" then
			onStart(data)
		elseif kind == "PossessEnd" then
			onEnd(data)
		end
	end)

	-- Drive the Nightmare with the normal movement controls (keyboard, gamepad, touch).
	-- The Handler's Humanoid.MoveDirection already holds the player's movement input
	-- (camera-relative, any device) even though the server has set its WalkSpeed to 0,
	-- so we simply hand that direction to the Nightmare.
	RunService.RenderStepped:Connect(function()
		if not possessed then
			return
		end
		local humanoid = possessed:FindFirstChildOfClass("Humanoid")
		local character = localPlayer.Character
		local handlerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or not handlerHumanoid then
			return
		end
		local direction = handlerHumanoid.MoveDirection
		humanoid:Move(Vector3.new(direction.X, 0, direction.Z), false)
	end)
end

return PossessionController
