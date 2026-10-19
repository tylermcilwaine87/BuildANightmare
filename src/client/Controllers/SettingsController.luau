--[[
	SettingsController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/SettingsController

	SETTINGS (Phase 7). Open with the ⚙ button or K. Every setting (Shared/
	SettingsDefinitions) applies instantly and is saved to your profile.

	Other controllers read settings with SettingsController:Get(key):
	  EffectsController  CameraShake (Full / Reduced / Off), HitFlashes, DamageNumbers
	  HUDController      ControlHints
	  this module        OtherNightmares (hides other players' Nightmares + their
	                     overhead bars, except in your boss fights and duels)
	  AudioController    MusicVolume, SfxVolume
]]

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsDefinitions = require(Shared:WaitForChild("SettingsDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local SettingsController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local controllers
local ui = {}
local localValues = {} -- applied immediately; the server copy follows
local changedEvent = Instance.new("BindableEvent")
SettingsController.Changed = changedEvent.Event -- (key, value)

function SettingsController:Init(registry)
	controllers = registry
end

function SettingsController:Get(key: string)
	if localValues[key] ~= nil then
		return localValues[key]
	end
	local profile = controllers.ClientState.Profile
	return SettingsDefinitions.Get(profile and profile.Settings, key)
end

function SettingsController:Set(key: string, value)
	local clean = SettingsDefinitions.Sanitize(key, value)
	if clean == nil then
		return
	end
	localValues[key] = clean
	changedEvent:Fire(key, clean)
	self:Refresh()
	task.spawn(function()
		local result = controllers.ClientState:Request("SetSetting", key, clean)
		if result.Ok then
			localValues[key] = nil -- the saved profile now has it
		end
	end)
end

function SettingsController:IsOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

function SettingsController:Close()
	ui.Panel.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Panel) then
		GuiService.SelectedObject = nil
	end
end

function SettingsController:Toggle()
	if self:IsOpen() then
		ui.Panel.Visible = false
	else
		ui.Panel.Visible = true
		self:Refresh()
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = ui.CloseButton
		end
	end
end

------------------------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------------------------
function SettingsController:Refresh()
	if not self:IsOpen() then
		return
	end
	for _, child in ui.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for order, def in SettingsDefinitions.List do
		local value = self:Get(def.Key)
		local row = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, def.Hint and 58 or 44), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = ui.List }, { UIKit.Corner(8), UIKit.Padding(6) })
		UIKit.Label({ Text = def.Label, Size = UDim2.new(0.58, 0, 0, 30), MaxTextSize = 16, Parent = row })
		if def.Hint then
			UIKit.Label({ Text = def.Hint, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(0.58, 0, 0, 16), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 12, Parent = row })
		end
		local controls = UIKit.New("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.4, 0, 0, 30), BackgroundTransparency = 1, Parent = row })
		if def.Type == "Toggle" then
			UIKit.Button({ Text = value and "ON" or "OFF", Size = UDim2.fromScale(1, 1), BackgroundColor3 = value and C.Good or C.PanelLighter, TextColor3 = value and C.Background or C.Text, MaxTextSize = 15, Parent = controls }, function()
				self:Set(def.Key, not value)
			end)
		elseif def.Type == "Choice" then
			UIKit.Button({ Text = string.upper(value) .. "  ▸", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Accent, MaxTextSize = 15, Parent = controls }, function()
				local index = table.find(def.Options, value) or 1
				self:Set(def.Key, def.Options[index % #def.Options + 1])
			end)
		elseif def.Type == "Slider" then
			UIKit.Button({ Text = "−", Size = UDim2.fromScale(0.25, 1), BackgroundColor3 = C.PanelLighter, MaxTextSize = 18, Parent = controls }, function()
				self:Set(def.Key, value - def.Step)
			end)
			UIKit.Label({ Text = ("%d%%"):format(value), Position = UDim2.fromScale(0.27, 0), Size = UDim2.fromScale(0.46, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 16, Parent = controls })
			UIKit.Button({ Text = "+", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.25, 1), BackgroundColor3 = C.PanelLighter, MaxTextSize = 18, Parent = controls }, function()
				self:Set(def.Key, value + def.Step)
			end)
		end
	end
end

function SettingsController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "SettingsGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 23, Parent = localPlayer:WaitForChild("PlayerGui") })
	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.72),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(C.SubText, 2, 0.2), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(600, 600), Parent = panel })
	UIKit.Responsive(panel) -- near full screen on phones
	ui.Panel = panel
	UIKit.Label({ Text = "⚙ SETTINGS", Size = UDim2.fromScale(0.8, 0.08), Font = UIKit.FontHeavy, MaxTextSize = 28, Parent = panel })
	ui.CloseButton = UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.1, 0.08), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		ui.Panel.Visible = false
	end)
	ui.List = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromScale(0, 0.1),
		Size = UDim2.fromScale(1, 0.84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, { UIKit.List(6) })
	UIKit.Label({ Text = "Saved to your profile automatically.", Position = UDim2.fromScale(0, 0.95), Size = UDim2.fromScale(1, 0.05), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 13, Parent = panel })
end

------------------------------------------------------------------------------------------
-- "Other players' Nightmares" (performance)
------------------------------------------------------------------------------------------
local hidden = {} -- [model] = true

local function setHidden(model: Model, hide: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = hide and 1 or 0
		elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") then
			d.Enabled = not hide
		end
	end
	hidden[model] = hide or nil
end

function SettingsController:UpdateNightmareVisibility()
	local inFight = controllers.BossController:IsInFight() or controllers.PvPController:IsInMatch()
	local hideOthers = not self:Get("OtherNightmares") and not inFight
	for _, model in CollectionService:GetTagged("Nightmare") do
		local isMine = model:GetAttribute("OwnerUserId") == localPlayer.UserId
		local shouldHide = hideOthers and not isMine
		-- Re-apply while hidden: overhead bars / sparkles can be added after we hid it.
		if shouldHide or hidden[model] then
			setHidden(model, shouldHide)
		end
	end
	for model in hidden do
		if not model.Parent then
			hidden[model] = nil
		end
	end
end

function SettingsController:Start()
	self:BuildGui()
	controllers.ClientState.Changed:Connect(function()
		self:Refresh()
	end)
	-- Cheap: a handful of Nightmares, twice a second.
	task.spawn(function()
		while true do
			task.wait(0.5)
			self:UpdateNightmareVisibility()
		end
	end)
end

return SettingsController
