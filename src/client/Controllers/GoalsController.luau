--[[
	GoalsController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/GoalsController

	The GOALS screen (Phase 5). Open with J or the GOALS button.
	  LEVEL    level, XP bar, current PvE / PvP Power budgets and every level unlock
	           (✓ = reached)
	  DAILY    3 challenges with progress bars, rewards and a reset countdown
	  WEEKLY   2 challenges, same
	Challenge progress arrives as a small UIStateUpdate("Challenges") message
	(ChallengeService); rewards are paid automatically when one completes.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LevelUnlocks = require(Shared:WaitForChild("LevelUnlocks"))
local ChallengeDefinitions = require(Shared:WaitForChild("ChallengeDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local GoalsController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local GOALS_COLOR = Color3.fromRGB(90, 210, 140)
local controllers
local ui = { ResetLabels = {} }

function GoalsController:Init(registry)
	controllers = registry
end

function GoalsController:IsOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

function GoalsController:Toggle()
	if self:IsOpen() then
		self:Close()
	else
		self:Open()
	end
end

function GoalsController:Open()
	if not controllers.ClientState.Profile then
		return
	end
	ui.Panel.Visible = true
	self:Refresh()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.CloseButton
	end
end

function GoalsController:Close()
	ui.Panel.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Panel) then
		GuiService.SelectedObject = nil
	end
end

local function countdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days, hours, minutes = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if days > 0 then
		return ("%dd %dh"):format(days, hours)
	end
	return ("%dh %02dm"):format(hours, minutes)
end

local function updateCountdowns()
	local now = Workspace:GetServerTimeNow()
	for period, label in ui.ResetLabels do
		if label.Parent then
			local _, endsAt = ChallengeDefinitions.PeriodInfo(period, math.floor(now))
			label.Text = "resets in " .. countdown(endsAt - now)
		end
	end
end

------------------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------------------
local function sectionHeader(order: number, text: string, color: Color3): TextLabel
	local row = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 28), BackgroundTransparency = 1, LayoutOrder = order, Parent = ui.List })
	UIKit.Label({ Text = text, Size = UDim2.fromScale(0.6, 1), Font = UIKit.FontHeavy, TextColor3 = color, MaxTextSize = 18, Parent = row })
	return UIKit.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.4, 1), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.SubText, MaxTextSize = 14, Parent = row })
end

function GoalsController:Refresh()
	local profile = controllers.ClientState.Profile
	if not profile or not self:IsOpen() then
		return
	end
	for _, child in ui.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	ui.ResetLabels = {}
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	-- LEVEL
	local level = profile.Level or 1
	local budgetLabel = sectionHeader(nextOrder(), ("LEVEL %d"):format(level), C.Warn)
	budgetLabel.Text = ("Power budget: PvE %d · PvP %d"):format(LevelUnlocks.PvEBudget(level), Config.Builds.PvPPowerBudget)
	local xpRow = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 22), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = ui.List })
	local xpBar = UIKit.Bar({ Size = UDim2.fromScale(1, 1), Color = C.Warn, Parent = xpRow })
	if level >= Config.Progression.MaxLevel then
		UIKit.SetBar(xpBar, 1, 1)
		xpBar.Label.Text = "MAX LEVEL"
	else
		UIKit.SetBar(xpBar, profile.XP or 0, profile.XPToNext or 1)
		xpBar.Label.Text = ("XP %d / %d to level %d"):format(profile.XP or 0, profile.XPToNext or 0, level + 1)
	end
	for _, unlock in LevelUnlocks.List() do
		local reached = level >= unlock.Level
		UIKit.Label({
			Text = ("%s  Lv %d  ·  %s"):format(reached and "✓" or "○", unlock.Level, unlock.Text),
			Size = UDim2.new(1, -8, 0, 20),
			Font = UIKit.FontBody,
			TextColor3 = reached and C.Good or C.SubText,
			MaxTextSize = 14,
			LayoutOrder = nextOrder(),
			Parent = ui.List,
		})
	end

	-- DAILY / WEEKLY
	local challenges = profile.Challenges or {}
	for _, period in { "Daily", "Weekly" } do
		local rewards = ChallengeDefinitions.Periods[period].Rewards
		UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 8), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = ui.List })
		ui.ResetLabels[period] = sectionHeader(nextOrder(), ("%s CHALLENGES"):format(string.upper(period)), GOALS_COLOR)
		UIKit.Label({
			Text = ("Each: +%d coins · +%d Essence · +%d XP, paid automatically when it's done."):format(rewards.Coins, rewards.Essence, rewards.XP),
			Size = UDim2.new(1, -8, 0, 18),
			Font = UIKit.FontBody,
			TextColor3 = C.SubText,
			MaxTextSize = 13,
			LayoutOrder = nextOrder(),
			Parent = ui.List,
		})
		local list = challenges[period] and challenges[period].List or {}
		if #list == 0 then
			UIKit.Label({ Text = "Loading challenges...", Size = UDim2.new(1, -8, 0, 20), TextColor3 = C.SubText, MaxTextSize = 14, LayoutOrder = nextOrder(), Parent = ui.List })
		end
		for _, entry in list do
			local def = ChallengeDefinitions.Get(entry.Id)
			if def then
				local row = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 58), BackgroundColor3 = C.PanelLight, LayoutOrder = nextOrder(), Parent = ui.List }, { UIKit.Corner(8), UIKit.Padding(8) })
				UIKit.Label({
					Text = (entry.Done and "✓ " or "") .. def.Text,
					Size = UDim2.new(1, 0, 0, 18),
					TextColor3 = entry.Done and C.Good or C.Text,
					MaxTextSize = 15,
					Parent = row,
				})
				local bar = UIKit.Bar({ Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 16), Color = entry.Done and C.Good or GOALS_COLOR, MaxTextSize = 12, Parent = row })
				UIKit.SetBar(bar, entry.Progress or 0, def.Target)
				if entry.Done then
					bar.Label.Text = "COMPLETE · rewards paid"
				end
			end
		end
	end
	updateCountdowns()
end

------------------------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------------------------
function GoalsController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "GoalsGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 22, Parent = localPlayer:WaitForChild("PlayerGui") })
	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.52, 0.84),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(GOALS_COLOR, 2, 0.1), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(760, 700), Parent = panel })
	UIKit.Responsive(panel) -- near full screen on phones
	ui.Panel = panel

	UIKit.Label({ Text = "GOALS", Size = UDim2.fromScale(0.85, 0.07), Font = UIKit.FontHeavy, TextColor3 = GOALS_COLOR, MaxTextSize = 30, Parent = panel })
	ui.CloseButton = UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.08, 0.07), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		self:Close()
	end)
	ui.List = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromScale(0, 0.09),
		Size = UDim2.fromScale(1, 0.91),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, { UIKit.List(5) })
end

function GoalsController:Start()
	self:BuildGui()
	controllers.ClientState.Changed:Connect(function()
		self:Refresh()
	end)
	-- Light-weight challenge progress updates (no full profile snapshot).
	controllers.ClientState.ServerEvent:Connect(function(kind, data)
		if kind == "Challenges" and type(data) == "table" and controllers.ClientState.Profile then
			controllers.ClientState.Profile.Challenges = data
			self:Refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if self:IsOpen() then
				updateCountdowns()
			end
		end
	end)
end

return GoalsController
