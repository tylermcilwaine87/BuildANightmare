--[[
	SpectatorController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/SpectatorController

	NIGHTMARE UNDERGROUND — SPECTATING (UndergroundService:Spectate). You stand in the arena's
	spectators' box; this gives you:
	  * the fight on a HUD: each corner's fighter and Nightmare with its health, the venue,
	    the round and its clock, the score; the result when it ends
	  * the cameras: WIDE (slowly round the ring), RINGSIDE (side-on to the two of them),
	    OVERHEAD, RED CORNER and BLUE CORNER (over each fighter's shoulder), FREE (fly it:
	    WASD, Space / Ctrl up and down, Shift faster, hold the right mouse button to look)
	    C cycles them, V is the free camera, or the buttons
	  * LEAVE: back to the district (DuelRequest "UGStopSpectate")
	The server sends DuelEvent "UGSpectate" twice a second while you watch ({ Active = false }
	when you've stopped).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UIKit = require(script.Parent:WaitForChild("UIKit"))

local SpectatorController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local RGB = Color3.fromRGB
local RED, BLUE, GOLD = RGB(255, 60, 70), RGB(80, 150, 255), RGB(255, 205, 90)

local MODES = { "Wide", "Ringside", "Overhead", "Red", "Blue", "Free" }
local MODE_NAMES = { Wide = "WIDE", Ringside = "RINGSIDE", Overhead = "OVERHEAD", Red = "RED CORNER", Blue = "BLUE CORNER", Free = "FREE CAM" }

local controllers
local ui = {}
local watch = nil -- the latest "UGSpectate" packet (nil: not watching)
local mode = "Wide"
local free = { Pos = Vector3.zero, Yaw = 0, Pitch = -0.3 }

function SpectatorController:Init(registry)
	controllers = registry
end

local function plate(parent: Instance, color: Color3, right: boolean)
	local frame = UIKit.New("Frame", { Size = UDim2.fromOffset(300, 84), Position = right and UDim2.new(1, -300, 0, 0) or UDim2.new(), BackgroundColor3 = RGB(14, 12, 18), BackgroundTransparency = 0.15, Parent = parent }, { UIKit.Corner(6), UIKit.Stroke(color, 2, 0.1) })
	local align = right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	local p = {}
	p.Name = UIKit.Label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 26), Font = UIKit.FontDisplay, TextColor3 = color, TextXAlignment = align, MaxTextSize = 24, Parent = frame })
	p.Sub = UIKit.Label({ Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 18), Font = UIKit.FontSmall, TextColor3 = C.SubText, TextXAlignment = align, MaxTextSize = 13, Parent = frame })
	p.Health = UIKit.Bar({ Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -24, 0, 16), Color = color, Parent = frame })
	return p
end

function SpectatorController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "UGSpectateGui", ResetOnSpawn = false, DisplayOrder = 22, IgnoreGuiInset = false, Enabled = false, Parent = localPlayer:WaitForChild("PlayerGui") })
	ui.Gui = gui
	local top = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(940, 84), BackgroundTransparency = 1, Parent = gui })
	UIKit.AutoScale(top)
	ui.Red = plate(top, RED, false)
	ui.Blue = plate(top, BLUE, true)
	local mid = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(300, 84), BackgroundColor3 = RGB(14, 12, 18), BackgroundTransparency = 0.15, Parent = top }, { UIKit.Corner(6), UIKit.Stroke(GOLD, 1, 0.4) })
	ui.Venue = UIKit.Label({ Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = GOLD, MaxTextSize = 12, Parent = mid })
	ui.Round = UIKit.Label({ Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = C.SubText, MaxTextSize = 14, Parent = mid })
	ui.Clock = UIKit.Label({ Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextColor3 = C.Text, MaxTextSize = 24, Parent = mid })
	ui.Score = UIKit.Label({ Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = GOLD, MaxTextSize = 15, Parent = mid })

	local bottom = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(940, 74), BackgroundTransparency = 1, Parent = gui })
	UIKit.AutoScale(bottom)
	ui.Tag = UIKit.Label({ Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = C.Text, TextStrokeTransparency = 0.4, MaxTextSize = 15, Parent = bottom })
	ui.Buttons = {}
	local width = 112
	for i, id in MODES do
		ui.Buttons[id] = UIKit.Button({ Position = UDim2.fromOffset((i - 1) * (width + 6), 28), Size = UDim2.fromOffset(width, 40), Text = MODE_NAMES[id], MaxTextSize = 13, Parent = bottom }, function()
			SpectatorController:SetMode(id)
		end)
	end
	UIKit.Button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 28), Size = UDim2.fromOffset(120, 40), BackgroundColor3 = RGB(140, 40, 56), Text = "LEAVE", MaxTextSize = 16, Parent = bottom }, function()
		controllers.PvPController:Request("UGStopSpectate")
	end)
	ui.Result = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(900, 90), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextColor3 = GOLD, TextStrokeTransparency = 0.1, MaxTextSize = 64, Visible = false, Parent = gui })
	UIKit.AutoScale(ui.Result)
end

function SpectatorController:SetMode(id: string)
	if id == "Free" and mode ~= "Free" then
		-- (the free camera starts where the view is now)
		local look = Workspace.CurrentCamera.CFrame
		free.Pos = look.Position
		local x, y = look:ToOrientation()
		free.Pitch, free.Yaw = x, y
	end
	mode = id
	for key, button in ui.Buttons do
		button.BackgroundColor3 = key == id and RGB(150, 110, 30) or C.PanelLight
	end
end

local function rootOf(model: Instance?): BasePart?
	local root = model and model.Parent and model:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function updatePlate(p, side, color: Color3)
	p.Name.Text = string.upper(side and side.Name or "?")
	local model = side and side.Model
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	p.Sub.Text = string.upper((model and model.Parent and model:GetAttribute("NightmareName")) or side and side.Nightmare or "—")
	if humanoid then
		UIKit.SetBar(p.Health, math.max(humanoid.Health, 0), humanoid.MaxHealth)
	else
		UIKit.SetBar(p.Health, 0, 1)
	end
end

local STAGES = { Prep = "PICKING THEIR NIGHTMARES", Intro = "THE ENTRANCES", Countdown = "IN THEIR CORNERS", RoundOver = "BETWEEN ROUNDS", Ended = "THE FIGHT IS OVER" }

local function frame(dt: number)
	if not watch then
		return
	end
	-- the HUD
	updatePlate(ui.Red, watch.Red, RED)
	updatePlate(ui.Blue, watch.Blue, BLUE)
	ui.Venue.Text = ("%s%s"):format(watch.Ranked and "RANKED  ·  " or "", string.upper(watch.Arena or "NIGHTMARE UNDERGROUND"))
	ui.Round.Text = ("ROUND %d / %d"):format(math.max(watch.Round or 1, 1), watch.BestOf or 3)
	if watch.State == "Live" then
		local left = math.max(0, (watch.PhaseEndsAt or 0) - Workspace:GetServerTimeNow())
		ui.Clock.Text = ("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60))
	else
		ui.Clock.Text = STAGES[watch.State] or "—"
	end
	ui.Score.Text = ("%d  –  %d"):format(watch.Score and watch.Score[1] or 0, watch.Score and watch.Score[2] or 0)
	ui.Result.Visible = watch.Result ~= nil
	ui.Result.Text = watch.Result or ""
	ui.Tag.Text = ("SPECTATING  ·  %s  ·  C changes camera, V free camera"):format(MODE_NAMES[mode])

	-- the camera
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local center: Vector3 = typeof(watch.Center) == "Vector3" and watch.Center or camera.CFrame.Position
	local a, b = rootOf(watch.Red and watch.Red.Model), rootOf(watch.Blue and watch.Blue.Model)
	local mid = (a and b) and (a.Position + b.Position) / 2 or center + Vector3.new(0, 3, 0)
	local across = (a and b) and (b.Position - a.Position) * Vector3.new(1, 0, 1) or Vector3.xAxis
	across = across.Magnitude > 0.1 and across.Unit or Vector3.xAxis
	local side = across:Cross(Vector3.yAxis)
	local target: CFrame
	local fov = 60
	if mode == "Free" then
		local move = Vector3.zero
		local function down(key)
			return UserInputService:IsKeyDown(key)
		end
		local look = CFrame.fromOrientation(free.Pitch, free.Yaw, 0)
		if down(Enum.KeyCode.W) then move += look.LookVector end
		if down(Enum.KeyCode.S) then move -= look.LookVector end
		if down(Enum.KeyCode.D) then move += look.RightVector end
		if down(Enum.KeyCode.A) then move -= look.RightVector end
		if down(Enum.KeyCode.Space) then move += Vector3.yAxis end
		if down(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
		local speed = down(Enum.KeyCode.LeftShift) and 60 or 24
		if move.Magnitude > 0 then
			free.Pos += move.Unit * speed * dt
		end
		-- (kept within the venue)
		local offset = free.Pos - center
		if offset.Magnitude > 140 then
			free.Pos = center + offset.Unit * 140
		end
		camera.FieldOfView = 70
		camera.CFrame = CFrame.new(free.Pos) * look
		return
	elseif mode == "Wide" then
		local angle = os.clock() * 0.08
		target = CFrame.lookAt(center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 42 + Vector3.new(0, 18, 0), center + Vector3.new(0, 3, 0))
	elseif mode == "Ringside" then
		-- (the side of the fight the camera is already on: no flipping across it)
		if side:Dot(camera.CFrame.Position - mid) < 0 then
			side = -side
		end
		target = CFrame.lookAt(mid + side * 20 + Vector3.new(0, 4.5, 0), mid + Vector3.new(0, 2, 0))
		fov = 55
	elseif mode == "Overhead" then
		target = CFrame.lookAt(mid + Vector3.new(0, 30, 0) + side * 7, mid)
	else
		local from, to = a, b
		if mode == "Blue" then
			from, to = b, a
		end
		if from and to then
			local dir = (to.Position - from.Position) * Vector3.new(1, 0, 1)
			dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.zAxis
			local right = dir:Cross(Vector3.yAxis)
			target = CFrame.lookAt(from.Position - dir * 11 + right * 3 + Vector3.new(0, 5.5, 0), to.Position + Vector3.new(0, 1.5, 0))
		else
			target = camera.CFrame
		end
		fov = 58
	end
	camera.FieldOfView = fov
	camera.CFrame = camera.CFrame:Lerp(target, math.clamp(dt * 5, 0, 1))
end

local function start()
	ui.Gui.Enabled = true
	controllers.HUDController:SetSpectating(true)
	SpectatorController:SetMode("Wide")
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep("UGSpectateCam", Enum.RenderPriority.Last.Value + 6, frame)
end

local function stop()
	RunService:UnbindFromRenderStep("UGSpectateCam")
	ui.Gui.Enabled = false
	controllers.HUDController:SetSpectating(false)
	controllers.UndergroundController:ResetVenue()
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
end

-- DuelEvent "UGSpectate"
function SpectatorController:Update(data)
	if type(data) ~= "table" or not ui.Gui then
		return
	end
	if not data.Active then
		if watch then
			watch = nil
			stop()
		end
		return
	end
	local starting = watch == nil
	watch = data
	controllers.UndergroundController:ApplyVenue(data.Theme)
	if starting then
		start()
	end
end

function SpectatorController:IsWatching(): boolean
	return watch ~= nil
end

function SpectatorController:Start()
	self:BuildGui()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not watch then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			local index = table.find(MODES, mode) or 1
			local nextMode = MODES[index % #MODES + 1]
			self:SetMode(nextMode == "Free" and MODES[1] or nextMode) -- (C skips the free camera: V)
		elseif input.KeyCode == Enum.KeyCode.V then
			self:SetMode(mode == "Free" and "Wide" or "Free")
		end
	end)
	-- the free camera's mouse look: hold the right button and drag
	UserInputService.InputChanged:Connect(function(input)
		if watch and mode == "Free" and input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			free.Yaw -= input.Delta.X * 0.004
			free.Pitch = math.clamp(free.Pitch - input.Delta.Y * 0.004, -1.4, 1.4)
		end
	end)
end

return SpectatorController
