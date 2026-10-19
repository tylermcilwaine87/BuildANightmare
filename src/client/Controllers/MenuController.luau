--[[
	MenuController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/MenuController

	THE MENU HUB (Phase 7, mobile + controller pass): one screen of big tiles that opens
	every other menu, so phones and controllers can reach everything without a keyboard.
	  Phone       the MENU button (the top bar is compact on touch screens)
	  Controller  D-Pad Right (B closes any menu)
	  PC          also works (the full top bar is still there)
]]

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local UIKit = require(script.Parent:WaitForChild("UIKit"))

local MenuController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local controllers
local ui = {}

function MenuController:Init(registry)
	controllers = registry
end

function MenuController:IsOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

function MenuController:Close()
	ui.Panel.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Panel) then
		GuiService.SelectedObject = nil
	end
end

function MenuController:Toggle()
	if self:IsOpen() then
		self:Close()
		return
	end
	ui.SummonTile.Text = controllers.ClientState:GetMyNightmare() and "RECALL" or "SUMMON"
	ui.Panel.Visible = true
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.FirstTile
	end
end

-- { label, colour, hint, action }: the action runs after the hub closes.
local function tiles()
	return {
		{ "WORKSHOP", C.Accent, "Build & edit your Nightmares", function()
			if not controllers.PossessionController:IsPossessing() and not controllers.PvPController:IsInMatch() then
				controllers.WorkshopController:Toggle()
			end
		end },
		{ "FIGHTER", Color3.fromRGB(255, 120, 70), "Moves, weapons & run styles", function()
			controllers.FighterController:Toggle()
		end },
		{ "PVP", Color3.fromRGB(230, 70, 90), "Duels, ranked & team duels", function()
			controllers.PvPController:TogglePanel()
		end },
		{ "PARTY", Color3.fromRGB(60, 140, 220), "Team up for bosses", function()
			controllers.PartyController:Toggle()
		end },
		{ "GOALS", Color3.fromRGB(70, 160, 110), "Level, unlocks & challenges", function()
			controllers.GoalsController:Toggle()
		end },
		{ "CODEX", Color3.fromRGB(150, 80, 160), "Bosses, parts & mutations", function()
			controllers.CodexController:Toggle()
		end },
		{ "SETTINGS", C.PanelLighter, "Sound, camera & performance", function()
			controllers.SettingsController:Toggle()
		end },
		{ "SUMMON", Color3.fromRGB(90, 80, 120), "Call / recall your Nightmare", function()
			controllers.CombatController:ToggleSummon()
		end },
	}
end

function MenuController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "MenuHubGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 24, Parent = localPlayer:WaitForChild("PlayerGui") })
	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.62),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(C.SubText, 2, 0.2), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(720, 520), Parent = panel })
	UIKit.Responsive(panel)
	ui.Panel = panel

	UIKit.Label({ Text = "MENU", Size = UDim2.fromScale(0.8, 0.1), Font = UIKit.FontHeavy, MaxTextSize = 28, Parent = panel })
	UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.1, 0.1), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		self:Close()
	end)

	local grid = UIKit.New("Frame", { Position = UDim2.fromScale(0, 0.13), Size = UDim2.fromScale(1, 0.87), BackgroundTransparency = 1, Parent = panel })
	UIKit.New("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0.25, -6), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for order, tile in tiles() do
		local label, color, hint, action = tile[1], tile[2], tile[3], tile[4]
		local button = UIKit.Button({ Text = "", BackgroundColor3 = color, LayoutOrder = order, Parent = grid }, function()
			self:Close()
			action()
		end)
		local title = UIKit.Label({ Text = label, Size = UDim2.fromScale(1, 0.58), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, MaxTextSize = 24, Parent = button })
		UIKit.Label({ Text = hint, Position = UDim2.fromScale(0, 0.58), Size = UDim2.fromScale(1, 0.4), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontBody, TextColor3 = Color3.fromRGB(230, 225, 240), MaxTextSize = 13, Parent = button })
		if order == 1 then
			ui.FirstTile = button
		end
		if label == "SUMMON" then
			ui.SummonTile = title
		end
	end
end

function MenuController:Start()
	self:BuildGui()
end

return MenuController
