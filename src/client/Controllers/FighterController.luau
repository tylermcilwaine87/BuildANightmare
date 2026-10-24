--[[
	FighterController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/FighterController

	The FIGHTER menu (U, the FIGHTER button, or the MENU hub): everything about how YOU fight,
	what you've got and what's left to unlock.
	  MOVES    the signature combos (MeleeDefinitions.Combos). Discovered ones show their
	           inputs; the rest show only a hint until you pull them off. Locked ones say
	           the level that opens them.
	  WEAPONS  your loadout (ARSENAL): which (up to 3) weapons you carry, their charges and
	           unlock levels.
	  RUNS     run styles: buy them with coins, pick the one you run with.
	Also shows the "NEW MOVE DISCOVERED" banner when the server reports a first-time combo.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Melee = require(Shared:WaitForChild("MeleeDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local FighterController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local FIGHT_COLOR = Color3.fromRGB(255, 120, 70)
local TABS = { "Moves", "Weapons", "Runs" }

local controllers
local combatAction: RemoteEvent
local ui = { Tab = "Moves", TabButtons = {} }

function FighterController:Init(registry)
	controllers = registry
	combatAction = Net.Get("CombatAction")
end

local function profile()
	return controllers.ClientState.Profile or {}
end

function FighterController:IsOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

function FighterController:Open(tab: string?)
	ui.Tab = tab or ui.Tab
	ui.Panel.Visible = true
	self:Refresh()
end

function FighterController:Close()
	ui.Panel.Visible = false
end

function FighterController:Toggle(tab: string?)
	if self:IsOpen() and (tab == nil or tab == ui.Tab) then
		self:Close()
	else
		self:Open(tab)
	end
end

------------------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------------------
local function clear()
	for _, child in ui.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function section(order: number, text: string)
	UIKit.Label({ Text = text, Size = UDim2.new(1, -8, 0, 26), TextColor3 = FIGHT_COLOR, MaxTextSize = 16, Font = UIKit.FontHeavy, LayoutOrder = order, Parent = ui.List })
end

local function row(order: number, height: number?)
	return UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, height or 64), BackgroundColor3 = C.PanelLighter, BackgroundTransparency = 0.35, LayoutOrder = order, Parent = ui.List }, { UIKit.Corner(8) })
end

-- "P P K" as little key chips.
local function inputChips(parent: GuiObject, inputs: string, x: number)
	local frame = UIKit.New("Frame", { Position = UDim2.fromOffset(x, 32), Size = UDim2.new(1, -x - 140, 0, 24), BackgroundTransparency = 1, Parent = parent }, { UIKit.List(4, Enum.FillDirection.Horizontal) })
	for word in inputs:gmatch("%S+") do
		local key = #word <= 2
		UIKit.Label({
			Text = word,
			Size = UDim2.fromOffset(key and 26 or math.max(34, #word * 8), 22),
			BackgroundColor3 = key and (word == "K" and Color3.fromRGB(200, 100, 60) or Color3.fromRGB(90, 110, 200)) or C.Panel,
			BackgroundTransparency = key and 0 or 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			MaxTextSize = 13,
			Font = UIKit.FontHeavy,
			Parent = frame,
		})
	end
end

local function buildMoves()
	local data = profile()
	local found = data.Combos or {}
	local count = 0
	for _, combo in Melee.Combos do
		if found[combo.Id] then
			count += 1
		end
	end
	UIKit.Label({
		Text = "P = punch (left-click)   K = kick (quick right-click)   X = step back   Shift = dive   Mix them: the right string of strikes becomes a signature move.",
		Size = UDim2.new(1, -8, 0, 34), TextColor3 = C.SubText, MaxTextSize = 13, Font = UIKit.FontBody, TextWrapped = true, LayoutOrder = 0, Parent = ui.List,
	})
	section(1, ("SIGNATURE MOVES · %d / %d discovered"):format(count, #Melee.Combos))
	for order, combo in Melee.Combos do
		local discovered = found[combo.Id] == true
		local locked = combo.Move and not Melee.MoveUnlocked(combo.Move, data.Level)
		local r = row(order + 1)
		UIKit.Label({
			Text = discovered and combo.Name or "???",
			Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -160, 0, 22),
			TextColor3 = discovered and C.Text or C.SubText, MaxTextSize = 17, Font = UIKit.FontHeavy, Parent = r,
		})
		if discovered then
			inputChips(r, combo.Inputs, 12)
		else
			UIKit.Label({ Text = combo.Hint, Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -160, 0, 24), TextColor3 = C.SubText, MaxTextSize = 13, Font = UIKit.FontBody, Parent = r })
		end
		local move = combo.Move and Melee.Moves[combo.Move]
		UIKit.Label({
			Text = locked and ("LOCKED · LV %d"):format(move.Unlock.Level) or discovered and "DISCOVERED" or "UNDISCOVERED",
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(130, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = locked and C.Warn or discovered and C.Good or C.SubText, MaxTextSize = 13, Font = UIKit.FontHeavy, Parent = r,
		})
	end
end

local function buildWeapons()
	local data = profile()
	local carried = data.Loadout or { "Magnet" }
	UIKit.Label({
		Text = ("You fight with your fists plus up to %d weapons. Weapons hit far harder, so each has a few charges, then goes back on your belt to recharge."):format(Melee.LoadoutSlots),
		Size = UDim2.new(1, -8, 0, 34), TextColor3 = C.SubText, MaxTextSize = 13, Font = UIKit.FontBody, TextWrapped = true, LayoutOrder = 0, Parent = ui.List,
	})
	for order, weapon in Melee.Weapons do
		local unlocked = Melee.WeaponUnlocked(weapon.Id, data.Level, data.Owned)
		local slot = table.find(carried, weapon.Id)
		local r = row(order, 74)
		UIKit.Label({ Text = weapon.Icon, Position = UDim2.fromOffset(10, 12), Size = UDim2.fromOffset(46, 46), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 34, Parent = r })
		UIKit.Label({ Text = weapon.Display, Position = UDim2.fromOffset(64, 6), Size = UDim2.new(1, -260, 0, 20), TextColor3 = weapon.Color, MaxTextSize = 17, Font = UIKit.FontHeavy, Parent = r })
		UIKit.Label({
			Text = ("%s  ·  %d %s, %ds recharge"):format(weapon.Blurb, weapon.Uses, weapon.Uses == 1 and "use" or "uses", weapon.Recharge),
			Position = UDim2.fromOffset(64, 26), Size = UDim2.new(1, -260, 0, 42), TextColor3 = C.SubText, MaxTextSize = 11, Font = UIKit.FontBody, TextWrapped = true, Parent = r,
		})
		UIKit.Label({
			Text = not unlocked and (Melee.IsExclusive(weapon.Id) and "IN THE SHOP" or ("LOCKED · LV %d"):format(weapon.Unlock.Level)) or slot and ("In slot %d"):format(slot) or "Not carried",
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(170, 18),
			TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = not unlocked and C.Warn or slot and C.Good or C.SubText, MaxTextSize = 13, Parent = r,
		})
		if unlocked then
			for index = 1, Melee.LoadoutSlots do
				UIKit.Button({
					Text = tostring(index),
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -10 - (Melee.LoadoutSlots - index) * 40, 1, -8),
					Size = UDim2.fromOffset(34, 30),
					BackgroundColor3 = slot == index and weapon.Color or C.Panel,
					Parent = r,
				}, function()
					-- put this weapon in slot `index` (moving it if it's carried elsewhere)
					local new = table.clone(carried)
					local at = table.find(new, weapon.Id)
					if at then
						table.remove(new, at)
					end
					table.insert(new, math.min(index, #new + 1), weapon.Id)
					while #new > Melee.LoadoutSlots do
						table.remove(new)
					end
					combatAction:FireServer("Loadout", new)
				end)
			end
			if slot then
				UIKit.Button({
					Text = "-",
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -10 - Melee.LoadoutSlots * 40, 1, -8),
					Size = UDim2.fromOffset(34, 30),
					BackgroundColor3 = C.Bad,
					Parent = r,
				}, function()
					local new = table.clone(carried)
					table.remove(new, slot)
					combatAction:FireServer("Loadout", new)
				end)
			end
		end
	end
end

local function buildRuns()
	local data = profile()
	local owned = data.Runs or { Charge = true }
	UIKit.Label({
		Text = "How you run around (everyone sees it). Every style snaps straight into a strike the moment you attack.",
		Size = UDim2.new(1, -8, 0, 34), TextColor3 = C.SubText, MaxTextSize = 13, Font = UIKit.FontBody, TextWrapped = true, LayoutOrder = 0, Parent = ui.List,
	})
	for order, run in Melee.Runs do
		local r = row(order)
		UIKit.Label({ Text = run.Name, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -170, 0, 22), MaxTextSize = 17, Font = UIKit.FontHeavy, Parent = r })
		UIKit.Label({ Text = run.Blurb, Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -170, 0, 24), TextColor3 = C.SubText, MaxTextSize = 13, Font = UIKit.FontBody, Parent = r })
		local equipped = data.RunStyle == run.Id or (data.RunStyle == nil and run.Id == "Charge")
		local has = owned[run.Id] == true
		local text = equipped and "EQUIPPED" or has and "EQUIP" or ("BUY · %d coins"):format(run.Cost)
		local color = equipped and C.Good or has and C.Accent or ((data.Coins or 0) >= run.Cost and C.Warn or C.Panel)
		UIKit.Button({
			Text = text,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 36),
			BackgroundColor3 = color, MaxTextSize = 13, Parent = r,
		}, function()
			if equipped then
				return
			end
			combatAction:FireServer(has and "SetRun" or "BuyRun", run.Id)
		end)
	end
end

function FighterController:Refresh()
	if not ui.Panel or not ui.Panel.Visible then
		return
	end
	local data = profile()
	ui.Stats.Text = ("LV %d  ·  %d coins"):format(data.Level or 1, data.Coins or 0)
	for name, button in ui.TabButtons do
		button.BackgroundColor3 = name == ui.Tab and FIGHT_COLOR or C.PanelLighter
	end
	clear()
	if ui.Tab == "Moves" then
		buildMoves()
	elseif ui.Tab == "Weapons" then
		buildWeapons()
	else
		buildRuns()
	end
end

------------------------------------------------------------------------------------------
-- The discovery banner
------------------------------------------------------------------------------------------
function FighterController:ShowDiscovered(comboId: string)
	local combo
	for _, c in Melee.Combos do
		if c.Id == comboId then
			combo = c
		end
	end
	if not combo then
		return
	end
	local banner = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(460, 96),
		BackgroundColor3 = Color3.fromRGB(30, 18, 14),
		BackgroundTransparency = 0.1,
		Parent = ui.Gui,
	}, { UIKit.Corner(12), UIKit.Stroke(FIGHT_COLOR, 3, 0) })
	local scale = UIKit.AutoScale(banner)
	local target = scale.Scale
	scale.Scale = target * 0.6
	UIKit.Label({ Text = "NEW MOVE DISCOVERED!", Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = FIGHT_COLOR, MaxTextSize = 18, Font = UIKit.FontHeavy, Parent = banner })
	UIKit.Label({ Text = combo.Name:upper(), Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 30, Font = UIKit.FontHeavy, Parent = banner })
	UIKit.Label({ Text = combo.Inputs .. "   ·   saved in your FIGHTER menu (U)", Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, MaxTextSize = 14, Font = UIKit.FontBody, Parent = banner })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	pcall(function()
		controllers.AudioController:Play("LevelUp")
	end)
	task.delay(3.2, function()
		TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 0.01 }):Play()
		task.wait(0.27)
		banner:Destroy()
	end)
end

------------------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------------------
function FighterController:Start()
	local gui = UIKit.New("ScreenGui", { Name = "FighterGui", ResetOnSpawn = false, DisplayOrder = 20, Parent = localPlayer:WaitForChild("PlayerGui") })
	ui.Gui = gui
	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 520),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(FIGHT_COLOR, 2, 0.3) })
	UIKit.AutoScale(panel)
	ui.Panel = panel
	UIKit.Label({ Text = "FIGHTER", Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(240, 34), TextColor3 = FIGHT_COLOR, MaxTextSize = 30, Font = UIKit.FontHeavy, Parent = panel })
	ui.Stats = UIKit.Label({ Text = "", Position = UDim2.fromOffset(240, 18), Size = UDim2.new(1, -320, 0, 24), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Warn, MaxTextSize = 16, Parent = panel })
	UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		self:Close()
	end)
	local tabs = UIKit.New("Frame", { Position = UDim2.fromOffset(20, 56), Size = UDim2.new(1, -40, 0, 38), BackgroundTransparency = 1, Parent = panel }, { UIKit.List(8, Enum.FillDirection.Horizontal) })
	for order, name in TABS do
		ui.TabButtons[name] = UIKit.Button({ Text = name:upper(), Size = UDim2.fromOffset(140, 38), LayoutOrder = order, Parent = tabs }, function()
			ui.Tab = name
			self:Refresh()
		end)
	end
	ui.List = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 104),
		Size = UDim2.new(1, -32, 1, -118),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, { UIKit.List(8, Enum.FillDirection.Vertical) })

	controllers.ClientState.Changed:Connect(function()
		self:Refresh()
	end)
	controllers.ClientState.ServerEvent:Connect(function(kind, data)
		if kind == "ComboDiscovered" and type(data) == "table" and type(data.Id) == "string" then
			self:ShowDiscovered(data.Id)
		end
	end)
end

return FighterController
