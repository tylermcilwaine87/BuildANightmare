--[[
	StanceController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/StanceController

	THE FIGHTING STANCE on your side of the screen (rules: Shared/FightRules):

	  * Lock on (Z / Select / LOCK) with your fists out and you're IN STANCE: your Handler
	    squares up, guards one side and moves with fighting footwork (HandlerAnimator).
	  * Choose the side you guard (and punch from):
	      mouse      flick it left / right / up
	      gamepad    push the right stick left / right / up
	      phones     the three guard buttons
	    A blow on the side you're guarding is BLOCKED. Move your guard to that side just
	    as it arrives (the last 0.22 s) and it's PARRIED.
	  * Your punch comes from your guard: High = jab (then the cross), Left = lead hook,
	    Right = rear hook (MeleeController / Melee.ResolveStance).
	  * The guard indicator: around your opponent, their guard (white) and, red, the side
	    their next strike is coming from; on you, your own guard (cyan). PARRY / BLOCKED /
	    GUARD BREAK flash when they happen to you or your opponent.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local FightRules = require(Shared:WaitForChild("FightRules"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local StanceController = {}

local localPlayer = Players.LocalPlayer
local controllers
local combatAction
local inStance = false
local guard = "High"
local flick = Vector2.zero
local lastFlickInput = 0
local lastChange = 0
local FLICK_PIXELS = 22 -- how far the mouse has to move to switch sides
local STICK = 0.65 -- how far the right stick has to go

local ui = {}

local COLORS = {
	Idle = Color3.fromRGB(70, 60, 90),
	Guard = Color3.fromRGB(240, 236, 255),
	Mine = Color3.fromRGB(90, 220, 255),
	Attack = Color3.fromRGB(255, 50, 70),
}

local function character(): Model?
	return localPlayer.Character
end

function StanceController:InStance(): boolean
	return inStance
end

function StanceController:GetGuard(): string?
	return inStance and guard or nil
end

local lastRecommit = 0
function StanceController:SetGuard(side: string)
	if not inStance or not FightRules.IsSide(side) then
		return
	end
	if side == guard then
		-- flicked into the side you're already covering: re-commit it (a parry chance)
		if os.clock() - lastRecommit >= FightRules.RecommitCooldown then
			lastRecommit = os.clock()
			combatAction:FireServer("GuardDir", side)
		end
		return
	end
	guard = side
	lastChange = os.clock()
	local body = character()
	if body then
		body:SetAttribute("GuardDir", side) -- shown at once here (the server's copy follows)
	end
	combatAction:FireServer("GuardDir", side)
end

local function setStance(on: boolean)
	if on == inStance then
		return
	end
	inStance = on
	local body = character()
	if body then
		body:SetAttribute("InStance", on or nil)
		if on then
			body:SetAttribute("GuardDir", guard)
		end
	end
	combatAction:FireServer("Stance", on)
	if on then
		combatAction:FireServer("GuardDir", guard)
	end
end

------------------------------------------------------------------------------------------
-- The indicator: a three-sided Nightmare sigil around a fighter
------------------------------------------------------------------------------------------
local function makeSigil(name: string, size: number)
	local gui = UIKit.New("BillboardGui", {
		Name = name,
		Size = UDim2.fromScale(size, size),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		ResetOnSpawn = false,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	local holder = UIKit.New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	local bars = {}
	-- High: a bar over the top; Left / Right: bars at the sides, angled like a crest
	local specs = {
		High = { Position = UDim2.fromScale(0.5, 0.08), Size = UDim2.fromScale(0.5, 0.09), Rotation = 0 },
		Left = { Position = UDim2.fromScale(0.12, 0.55), Size = UDim2.fromScale(0.09, 0.5), Rotation = 18 },
		Right = { Position = UDim2.fromScale(0.88, 0.55), Size = UDim2.fromScale(0.09, 0.5), Rotation = -18 },
	}
	for side, spec in specs do
		local bar = UIKit.New("Frame", {
			Name = side,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = spec.Position,
			Size = spec.Size,
			Rotation = spec.Rotation,
			BackgroundColor3 = COLORS.Idle,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = holder,
		}, { UIKit.Corner(6), UIKit.Stroke(Color3.fromRGB(150, 90, 255), 1.5, 0.3) })
		bars[side] = bar
	end
	UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.07, 0.07), BackgroundColor3 = Color3.fromRGB(150, 90, 255), BorderSizePixel = 0, Parent = holder }, { UIKit.Corner(99) })
	return { Gui = gui, Bars = bars }
end

local function paint(sigil, guardSide: string?, color: Color3, attackSide: string?)
	for side, bar in sigil.Bars do
		if side == attackSide then
			bar.BackgroundColor3 = COLORS.Attack
			bar.BackgroundTransparency = 0
		elseif side == guardSide then
			bar.BackgroundColor3 = color
			bar.BackgroundTransparency = 0.05
		else
			bar.BackgroundColor3 = COLORS.Idle
			bar.BackgroundTransparency = 0.75
		end
	end
end

local function popup(text: string, color: Color3)
	local label = ui.Popup
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.3
	label.Visible = true
	label.Size = UDim2.fromOffset(420, 64)
	TweenService:Create(label, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(460, 72) }):Play()
	local token = os.clock()
	label:SetAttribute("Token", token)
	task.delay(0.7, function()
		if label:GetAttribute("Token") == token then
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local function buildUI()
	ui.Theirs = makeSigil("DuelSigilTarget", 5.5)
	ui.Mine = makeSigil("DuelSigilMine", 3.2)
	ui.Mine.Gui.StudsOffset = Vector3.new(0, 3.6, 0)
	local gui = UIKit.New("ScreenGui", { Name = "DuelUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8, Parent = localPlayer:WaitForChild("PlayerGui") })
	ui.Popup = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromOffset(420, 64), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, MaxTextSize = 48, Visible = false, Parent = gui })
	-- phones: three guard buttons
	ui.Touch = UIKit.New("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -170, 1, -170), Size = UDim2.fromOffset(170, 120), BackgroundTransparency = 1, Visible = false, Parent = gui })
	for side, spec in { High = { 60, 0 }, Left = { 0, 60 }, Right = { 120, 60 } } do
		UIKit.Button({ Text = side == "High" and "▲" or side == "Left" and "◀" or "▶", Position = UDim2.fromOffset(spec[1], spec[2]), Size = UDim2.fromOffset(50, 50), BackgroundColor3 = Color3.fromRGB(60, 40, 90), MaxTextSize = 22, Parent = ui.Touch }, function()
			StanceController:SetGuard(side)
		end)
	end
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function StanceController:Init(registry)
	controllers = registry
end

function StanceController:Start()
	combatAction = Net.Get("CombatAction")
	buildUI()

	-- mouse flicks / right stick pick the side
	local lastMouse: Vector2? = nil
	UserInputService.InputChanged:Connect(function(input, processed)
		-- Delta is only filled in while the mouse is locked; with a free cursor (lock-on
		-- leaves it free) the movement is the change in cursor position instead
		local delta = Vector2.zero
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			delta = Vector2.new(input.Delta.X, input.Delta.Y)
			if delta.Magnitude == 0 and lastMouse then
				delta = pos - lastMouse
			end
			lastMouse = pos
		end
		if not inStance or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local now = os.clock()
			if now - lastFlickInput > 0.15 then
				flick = Vector2.zero -- a slow drift isn't a flick
			end
			lastFlickInput = now
			flick += delta
			if math.abs(flick.X) >= FLICK_PIXELS and math.abs(flick.X) > math.abs(flick.Y) then
				self:SetGuard(flick.X < 0 and "Left" or "Right")
				flick = Vector2.zero
			elseif flick.Y <= -FLICK_PIXELS and -flick.Y > math.abs(flick.X) then
				self:SetGuard("High")
				flick = Vector2.zero
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local p = input.Position
			if math.abs(p.X) >= STICK and math.abs(p.X) > math.abs(p.Y) then
				self:SetGuard(p.X < 0 and "Left" or "Right")
			elseif p.Y >= STICK and p.Y > math.abs(p.X) then
				self:SetGuard("High")
			end
		end
	end)

	local feedback = Net.Get("CombatFeedback")
	feedback.OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" or not FightRules.IsSide(data.Side) then
			return
		end
		local me = character()
		local mine = data.Target == me or data.Attacker == me
		if not mine then
			return
		end
		if kind == "Parried" then
			popup(data.Target == me and "PARRY!" or "PARRIED!", data.Target == me and Color3.fromRGB(255, 220, 90) or COLORS.Attack)
			controllers.AudioController:Play(data.Target == me and "Parry" or "GuardBreak", data.Position)
		elseif kind == "Blocked" then
			popup("BLOCKED", Color3.fromRGB(200, 200, 220))
		elseif kind == "GuardBreak" then
			popup("GUARD BREAK!", COLORS.Attack)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local body = character()
		local humanoid = body and body:FindFirstChildOfClass("Humanoid")
		local lock = controllers.LockOnController
		local possessing = controllers.PossessionController:IsPossessing()
		local fists = body and (body:GetAttribute("Weapon") or "Fists") == "Fists"
		local want = lock:IsLocked() and not possessing and fists and humanoid ~= nil and humanoid.Health > 0
		setStance(want == true)

		-- indicators
		local target = inStance and lock:GetTarget() or nil
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
		ui.Theirs.Gui.Enabled = targetRoot ~= nil
		ui.Theirs.Gui.Adornee = targetRoot
		if targetRoot then
			local attackSide = target:GetAttribute("AttackSide")
			local attackAt = target:GetAttribute("AttackAt") or 0
			local live = attackSide and Workspace:GetServerTimeNow() <= attackAt + 0.15
			local theirGuard = target:GetAttribute("InStance") and target:GetAttribute("GuardDir") or nil
			paint(ui.Theirs, theirGuard, COLORS.Guard, live and attackSide or nil)
		end
		local myRoot = inStance and body and body:FindFirstChild("HumanoidRootPart") or nil
		ui.Mine.Gui.Enabled = myRoot ~= nil
		ui.Mine.Gui.Adornee = myRoot
		if myRoot then
			paint(ui.Mine, guard, COLORS.Mine, nil)
		end
		ui.Touch.Visible = inStance and UIKit.IsTouchOnly()
	end)

	localPlayer.CharacterAdded:Connect(function()
		inStance = false
		guard = "High"
	end)
end

return StanceController
