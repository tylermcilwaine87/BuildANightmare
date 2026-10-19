--[[
	TutorialController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController

	Shows the current tutorial objective (from the server's profile snapshot) with a
	checklist and a SKIP button. Completion is decided by the SERVER (TutorialService);
	this only displays it. Hidden once the tutorial is done.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local TutorialDefinitions = require(Shared:WaitForChild("TutorialDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local TutorialController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local controllers
local ui = {}
local introShown = false

local NEED_TEXT = {
	BuildSaved = "Open the Workshop and press CREATE",
	HandlerHit = "Hit an enemy (Left Click)",
	Dodged = "Dive once (Shift)",
	CommandAttack = "Send your Nightmare at an enemy (R)",
	AbilityUsed = "Use your Nightmare's ability (Q)",
	EnemyDefeated = "Defeat a Scrapling",
	TutorialBossWon = "Defeat the Scrap Titan",
	EquippedReward = "Equip your new part and SAVE",
}

function TutorialController:Init(registry)
	controllers = registry
end

-- True while the "create your first Nightmare" step is active (Workshop shows CREATE).
function TutorialController:IsCreateStep(): boolean
	local profile = controllers.ClientState.Profile
	local tutorial = profile and profile.Tutorial
	return tutorial ~= nil and not tutorial.Done and tutorial.Step == 1
end

function TutorialController:Start()
	local gui = UIKit.New("ScreenGui", {
		Name = "TutorialGui",
		ResetOnSpawn = false,
		DisplayOrder = 8,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})

	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 66),
		Size = UDim2.fromOffset(320, 170),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(10), UIKit.Stroke(C.Warn, 2, 0.2) })
	UIKit.AutoScale(panel)
	ui.Panel = panel
	ui.Step = UIKit.Label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -90, 0, 16), TextColor3 = C.Warn, MaxTextSize = 13, Parent = panel })
	UIKit.Button({ Text = "SKIP", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(64, 22), MaxTextSize = 12, BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		Net.Get("TutorialAction"):FireServer("Skip")
	end)
	ui.Title = UIKit.Label({ Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 22), Font = UIKit.FontHeavy, MaxTextSize = 17, Parent = panel })
	ui.Text = UIKit.Label({ Position = UDim2.fromOffset(12, 52), Size = UDim2.new(1, -24, 0, 54), Font = UIKit.FontBody, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 14, Parent = panel })
	ui.Checklist = UIKit.Label({ Position = UDim2.fromOffset(12, 110), Size = UDim2.new(1, -24, 0, 52), RichText = true, Font = UIKit.FontBody, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 14, Parent = panel })

	-- Big intro line for brand-new players.
	ui.Intro = UIKit.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.35),
		Size = UDim2.fromScale(0.8, 0.12),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UIKit.FontHeavy,
		TextColor3 = Color3.fromRGB(255, 200, 120),
		TextStrokeTransparency = 0.3,
		MaxTextSize = 44,
		Text = "EVERY NIGHTMARE STARTS SOMEWHERE.\nYOURS STARTS IN PIECES.",
		Visible = false,
		Parent = gui,
	})

	controllers.ClientState.Changed:Connect(function()
		self:Refresh()
	end)
	self:Refresh()
end

function TutorialController:Refresh()
	local profile = controllers.ClientState.Profile
	local tutorial = profile and profile.Tutorial
	if not tutorial or tutorial.Done then
		ui.Panel.Visible = false
		return
	end
	local step = TutorialDefinitions.Steps[tutorial.Step]
	if not step then
		ui.Panel.Visible = false
		return
	end
	ui.Panel.Visible = true
	ui.Step.Text = ("TUTORIAL  %d / %d"):format(tutorial.Step, #TutorialDefinitions.Steps)
	ui.Title.Text = step.Title
	ui.Text.Text = step.Text

	local lines = {}
	local flags = tutorial.Flags or {}
	for _, need in step.Needs do
		local done = flags[need] == true
		table.insert(lines, ('<font color="#%s">%s %s</font>'):format((done and C.Good or C.Text):ToHex(), done and "✓" or "○", NEED_TEXT[need] or need))
	end
	ui.Checklist.Text = table.concat(lines, "\n")

	if tutorial.Step == 1 and not introShown then
		introShown = true
		ui.Intro.Visible = true
		ui.Intro.TextTransparency = 0
		task.delay(4, function()
			TweenService:Create(ui.Intro, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(1)
			ui.Intro.Visible = false
		end)
	end
end

return TutorialController
