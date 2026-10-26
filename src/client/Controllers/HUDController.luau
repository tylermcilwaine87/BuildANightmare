--[[
	HUDController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController

	Combat HUD (built in code, no StarterGui setup needed):
	  * Handler HP + Stamina, Nightmare name/HP/shield, archetype, command
	  * Ability slots Q / E with live cooldowns
	  * Level, XP bar, Nightmare Coins
	  * Target readout, toast messages
	  * BUILD and SUMMON/RECALL buttons
	  * Touch devices: ATTACK / KICK / DODGE / GUARD / Q / E / CMD / ULT / POSSESS buttons
	    (the weapon hotbar is MeleeController's)
	  * Control hints for keyboard & gamepad
	Phase 3 adds Possession & Ultimate meters and status-effect icons.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local StatusDefinitions = require(Shared:WaitForChild("StatusDefinitions"))
local LevelUnlocks = require(Shared:WaitForChild("LevelUnlocks"))
local NightmareCombat = require(Shared:WaitForChild("NightmareCombatDefinitions"))
local BossDefinitions = require(Shared:WaitForChild("BossDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local HUDController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local controllers
local ui = { Summoned = true } -- server auto-summons on spawn; updated by "Summon" events
local toastToken = 0

local COMMAND_TEXT = {
	Follow = "DEFEND · stays close",
	Defend = "DEFEND · stays close",
	Aggressive = "AGGRESSIVE · hunting",
	Attack = "ATTACK · focused target",
	Retreat = "RETREAT · returning",
}

function HUDController:Init(registry)
	controllers = registry
end

function HUDController:Toast(text: string, color: Color3?, duration: number?)
	toastToken += 1
	local token = toastToken
	ui.Toast.Text = text
	ui.Toast.TextColor3 = color or C.Text
	ui.Toast.Visible = true
	task.delay(duration or 2.5, function()
		if toastToken == token then
			ui.Toast.Visible = false
		end
	end)
end

-- During a duel: no summon/recall, Workshop or PvP-menu buttons (they're locked anyway).
function HUDController:SetPvPMode(enabled: boolean)
	ui.BuildButton.Visible = not enabled
	ui.SummonButton.Visible = not enabled
	ui.PvPButton.Visible = not enabled
end

function HUDController:SetVisible(visible: boolean)
	if ui.Gui then
		ui.Gui.Enabled = visible
	end
end

local function buildStatusPanel(gui: ScreenGui)
	local panel = UIKit.New("Frame", {
		Name = "Status",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(300, 196),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		Parent = gui,
	}, { UIKit.Corner(10), UIKit.Stroke(C.Accent, 1, 0.5) })
	UIKit.AutoScale(panel)

	ui.LevelLabel = UIKit.Label({ Text = "LV 1", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0.5, -12, 0, 16), TextColor3 = C.Warn, MaxTextSize = 14, Parent = panel })
	ui.CoinsLabel = UIKit.Label({ Text = "0 coins", Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.new(0.5, -12, 0, 16), TextColor3 = C.Warn, TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 14, Parent = panel })
	ui.XPBar = UIKit.Bar({ Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -24, 0, 6), Color = C.Warn, Parent = panel })
	ui.XPBar.Label.Visible = false

	UIKit.Label({ Text = "HANDLER", Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 14), TextColor3 = C.SubText, MaxTextSize = 12, Parent = panel })
	ui.HandlerBar = UIKit.Bar({ Position = UDim2.fromOffset(12, 52), Size = UDim2.new(1, -24, 0, 16), Color = C.HandlerHP, Parent = panel })
	ui.StaminaBar = UIKit.Bar({ Position = UDim2.fromOffset(12, 71), Size = UDim2.new(1, -24, 0, 8), Color = Color3.fromRGB(240, 210, 90), Parent = panel })
	ui.StaminaBar.Label.Visible = false

	ui.NightmareName = UIKit.Label({ Text = "NIGHTMARE", Position = UDim2.fromOffset(12, 86), Size = UDim2.new(1, -24, 0, 18), MaxTextSize = 15, Parent = panel })
	ui.NightmareBar = UIKit.Bar({ Position = UDim2.fromOffset(12, 106), Size = UDim2.new(1, -24, 0, 16), Color = C.NightmareHP, Parent = panel })
	ui.NightmareInfo = UIKit.Label({ Text = "", Position = UDim2.fromOffset(12, 127), Size = UDim2.new(1, -24, 0, 16), TextColor3 = C.SubText, MaxTextSize = 13, Font = UIKit.FontBody, Parent = panel })
	ui.Command = UIKit.Label({ Text = "", Position = UDim2.fromOffset(12, 146), Size = UDim2.new(1, -24, 0, 18), TextColor3 = C.Accent2, MaxTextSize = 14, Parent = panel })
	ui.StatusLine = UIKit.Label({ Text = "", Position = UDim2.fromOffset(12, 166), Size = UDim2.new(1, -24, 0, 14), RichText = true, MaxTextSize = 12, Parent = panel })
	ui.SaveStatus = UIKit.Label({ Text = "", Position = UDim2.fromOffset(12, 182), Size = UDim2.new(1, -24, 0, 12), TextColor3 = C.SubText, MaxTextSize = 11, Font = UIKit.FontBody, Parent = panel })
end

local function buildAbilityBar(gui: ScreenGui)
	local bar = UIKit.New("Frame", {
		Name = "Abilities",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(UIKit.HudCenterX(), 0, 1, -16),
		Size = UDim2.fromOffset(330, 70),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { UIKit.List(10, Enum.FillDirection.Horizontal) })
	bar:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Center
	UIKit.AutoScale(bar)
	UIKit.PlaceHudCenter(bar, 16)
	ui.AbilitySlots = {}
	for slot, key in { "Q", "E" } do
		local button = UIKit.Button({
			Size = UDim2.fromOffset(160, 64),
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.1,
			LayoutOrder = slot,
			Parent = bar,
		}, function()
			controllers.CombatController:UseAbility(slot)
		end)
		UIKit.Stroke(C.Accent, 1, 0.4).Parent = button
		local cooldown = UIKit.New("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			ZIndex = 2,
			Parent = button,
		}, { UIKit.Corner(8) })
		local name = UIKit.Label({ Text = "", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0.55, -4), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 15, ZIndex = 3, Parent = button })
		local sub = UIKit.Label({ Text = "", Position = UDim2.new(0, 4, 0.55, 0), Size = UDim2.new(1, -8, 0.45, -4), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 13, ZIndex = 3, Parent = button })
		ui.AbilitySlots[slot] = { Button = button, Cooldown = cooldown, Name = name, Sub = sub, Key = key }
	end
end

local SYNC_COLOR = Color3.fromRGB(80, 230, 230)

local function buildMeters(gui: ScreenGui)
	local frame = UIKit.New("Frame", {
		Name = "Meters",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(UIKit.HudCenterX(), 0, 1, -92),
		Size = UDim2.fromOffset(330, 53),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.AutoScale(frame)
	UIKit.PlaceHudCenter(frame, 92)
	-- SYNC (SyncService): you and your Nightmare hitting the same enemy together
	ui.SyncBar = UIKit.Bar({ Size = UDim2.new(1, 0, 0, 12), Color = SYNC_COLOR, MaxTextSize = 10, Parent = frame })
	ui.PossessionBar = UIKit.Bar({ Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 17), Color = Color3.fromRGB(170, 100, 255), MaxTextSize = 12, Parent = frame })
	ui.UltimateBar = UIKit.Bar({ Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 17), Color = Color3.fromRGB(255, 190, 60), MaxTextSize = 12, Parent = frame })
	ui.Meters = frame
end

local function buildCommandMenu(gui: ScreenGui)
	local menu = UIKit.New("Frame", {
		Name = "CommandMenu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(440, 382),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(12), UIKit.Stroke(C.Accent, 2, 0.2), UIKit.Padding(10), UIKit.List(6) })
	UIKit.AutoScale(menu)
	ui.CommandMenu = menu
	UIKit.Label({ Text = "COMMAND YOUR NIGHTMARE  (V to close)", Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, MaxTextSize = 14, LayoutOrder = 0, Parent = menu })
	local entries = {
		{ "ATTACK TARGET", "Focus the enemy you're looking at", C.Bad, function(c) c:CommandAttackTarget() end },
		{ "DEFEND", "Stay close and protect you", C.Accent2, function(c) c:CommandDefend() end },
		{ "AGGRESSIVE", "Hunt enemies further away, more heavy attacks", Color3.fromRGB(230, 120, 50), function(c) c:CommandAggressive() end },
		{ "RETREAT", "Disengage and come back to you", C.PanelLighter, function(c) c:CommandRetreat() end },
	}
	ui.CommandButtons = {}
	for order, entry in entries do
		local button = UIKit.Button({
			Text = ("%s  —  %s"):format(entry[1], entry[2]),
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = entry[3],
			MaxTextSize = 14,
			LayoutOrder = order,
			Parent = menu,
		}, function()
			entry[4](controllers.CombatController)
			HUDController:ToggleCommandMenu(false)
		end)
		table.insert(ui.CommandButtons, button)
	end
	-- FIGHTING STYLE (the combat brain, NightmareCombatDefinitions): how it fights on its own.
	-- Each button cycles; the choice is saved. (The menu stays open while you pick.)
	local function styleRow(order: number, label: string, list, attribute: string, default: string, key: string, color: Color3)
		local current = function()
			return localPlayer:GetAttribute(attribute) or default
		end
		local blurb = function(id)
			local def = (key == "Personality" and NightmareCombat.Personalities[id]) or NightmareCombat.Modes[id]
			return def and def.Blurb or "Picked from its body: how it's built decides how it fights."
		end
		local button
		local function refresh()
			local id = current()
			button.Text = ("%s: %s  —  %s"):format(label, string.upper(id), blurb(id))
		end
		button = UIKit.Button({ Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = color, MaxTextSize = 13, LayoutOrder = order, Parent = menu }, function()
			local index = table.find(list, current()) or 0
			local nextId = list[index % #list + 1]
			localPlayer:SetAttribute(attribute, nextId) -- (shown straight away; the server confirms)
			refresh()
			Net.Get("NightmareCommand"):FireServer("Style", { [key] = nextId })
		end)
		localPlayer:GetAttributeChangedSignal(attribute):Connect(refresh)
		refresh()
		table.insert(ui.CommandButtons, button)
	end
	styleRow(10, "STYLE", NightmareCombat.PersonalityOrder, "NightmarePersonality", "Auto", "Personality", Color3.fromRGB(120, 70, 160))
	styleRow(11, "MODE", NightmareCombat.ModeOrder, "NightmareMode", "Balanced", "Mode", Color3.fromRGB(70, 90, 150))
	-- what it knows: every combination, locked or not, and how far it's mastered
	local combosButton = UIKit.Button({ Text = "COMBOS  —  what your Nightmare knows, and what it can still learn", Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(150, 60, 70), MaxTextSize = 13, LayoutOrder = 12, Parent = menu }, function()
		HUDController:ToggleCommandMenu(false)
		HUDController:ToggleCombos(true)
	end)
	table.insert(ui.CommandButtons, combosButton)
end

-- NIGHTMARE COMBOS (Config.Nightmare.Moveset): every combination the brain can use, what
-- body it needs, how it's unlocked and how many fights it has finished (Combo Mastery).
local function comboRequirement(def): string
	local needs = {}
	if def.Quad then
		table.insert(needs, "4 legs")
	elseif def.Legs then
		table.insert(needs, "2 legs")
	end
	if def.Tentacle then
		table.insert(needs, "a tentacle arm")
	elseif def.BothArms then
		table.insert(needs, "2 arms")
	elseif def.Arms then
		table.insert(needs, "an arm")
	end
	if def.Head then
		table.insert(needs, "a head")
	end
	return #needs > 0 and table.concat(needs, ", ") or "any body"
end

local function comboLock(def, profile): string?
	local unlock = def.Unlock
	if not unlock then
		return nil
	end
	if unlock.Boss then
		local record = profile and profile.Bosses and profile.Bosses[unlock.Boss]
		if not (record and (record.Wins or 0) > 0) then
			local boss = BossDefinitions.Get(unlock.Boss)
			return ("Beat %s"):format(boss and boss.DisplayName or unlock.Boss)
		end
	end
	if unlock.Mutation then
		local model = controllers.ClientState:GetMyNightmare()
		if not (model and model:GetAttribute("Mutations")) then
			return "Equip a mutated part"
		end
	end
	if unlock.Mastery then
		local have = profile and profile.ComboMastery and profile.ComboMastery[unlock.Mastery.Action] or 0
		if have < unlock.Mastery.Count then
			return ("Master %s: %d / %d finished fights"):format(NightmareCombat.DisplayName(unlock.Mastery.Action), have, unlock.Mastery.Count)
		end
	end
	return nil
end

local function buildCombosPanel(gui: ScreenGui)
	local panel = UIKit.New("Frame", {
		Name = "CombosPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(560, 470),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.03,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(12), UIKit.Stroke(C.Accent, 2, 0.2), UIKit.Padding(12) })
	UIKit.AutoScale(panel)
	UIKit.Responsive(panel)
	ui.CombosPanel = panel
	UIKit.Label({ Text = "NIGHTMARE COMBOS", Size = UDim2.new(1, -50, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, Parent = panel })
	UIKit.Button({ Text = "X", Size = UDim2.fromOffset(34, 30), Position = UDim2.new(1, -34, 0, 0), BackgroundColor3 = C.PanelLighter, MaxTextSize = 16, Parent = panel }, function()
		HUDController:ToggleCombos(false)
	end)
	UIKit.Label({ Text = "Your Nightmare picks these itself in a fight. Finishing a fight with a combo counts towards mastering it.", Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 13, TextWrapped = true, Parent = panel })
	local list = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 1, -68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, { UIKit.List(6) })
	ui.CombosList = list
end

function HUDController:RefreshCombos()
	local list = ui.CombosList
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local profile = controllers.ClientState.Profile
	for order, def in Config.Nightmare.Moveset do
		if def.Action:sub(1, 6) == "Combo_" then
			local lock = comboLock(def, profile)
			local mastery = profile and profile.ComboMastery and profile.ComboMastery[def.Action] or 0
			local row = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 52), BackgroundColor3 = lock and C.PanelLight or C.PanelLighter, LayoutOrder = order, Parent = list }, { UIKit.Corner(8), UIKit.Padding(6) })
			local tags = table.concat(def.Tags or {}, " · ")
			UIKit.Label({ Text = string.upper(NightmareCombat.DisplayName(def.Action)) .. (lock and "  🔒" or ""), Size = UDim2.new(0.6, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = lock and C.SubText or C.Text, MaxTextSize = 16, Parent = row })
			UIKit.Label({ Text = lock or ("Mastery: %d finished fight%s"):format(mastery, mastery == 1 and "" or "s"), Position = UDim2.new(0.6, 0, 0, 0), Size = UDim2.new(0.4, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = lock and C.Warn or C.Good, Font = UIKit.FontBody, MaxTextSize = 13, Parent = row })
			UIKit.Label({ Text = ("Needs %s  ·  %s"):format(comboRequirement(def), tags), Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 12, Parent = row })
		end
	end
end

function HUDController:ToggleCombos(force: boolean?)
	local panel = ui.CombosPanel
	if not panel then
		return
	end
	local visible = if force == nil then not panel.Visible else force
	panel.Visible = visible
	if visible then
		self:RefreshCombos()
		task.spawn(function()
			if controllers.ClientState:Refresh() and panel.Visible then
				self:RefreshCombos() -- (fresh mastery counts)
			end
		end)
	end
end

function HUDController:ToggleCommandMenu(force: boolean?)
	local visible = if force == nil then not ui.CommandMenu.Visible else force
	ui.CommandMenu.Visible = visible
	local GuiService = game:GetService("GuiService")
	if visible and UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.CommandButtons[1]
	elseif not visible and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.CommandMenu) then
		GuiService.SelectedObject = nil
	end
end

local function buildTopButtons(gui: ScreenGui)
	local frame = UIKit.New("Frame", {
		Name = "TopButtons",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(960, 44),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { UIKit.List(8, Enum.FillDirection.Horizontal) })
	UIKit.AutoScale(frame)
	frame:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Right

	ui.SettingsButton = UIKit.Button({ Text = "⚙", Size = UDim2.fromOffset(44, 44), BackgroundColor3 = C.PanelLighter, MaxTextSize = 24, LayoutOrder = 0, Parent = frame }, function()
		controllers.SettingsController:Toggle()
	end)
	ui.BuildButton = UIKit.Button({ Text = "BUILD", Size = UDim2.fromOffset(110, 44), BackgroundColor3 = C.Accent, LayoutOrder = 1, Parent = frame }, function()
		controllers.WorkshopController:Toggle()
	end)
	ui.SummonButton = UIKit.Button({ Text = "RECALL", Size = UDim2.fromOffset(120, 44), LayoutOrder = 2, Parent = frame }, function()
		controllers.CombatController:ToggleSummon()
	end)
	ui.FighterButton = UIKit.Button({ Text = "FIGHTER", Size = UDim2.fromOffset(110, 44), BackgroundColor3 = Color3.fromRGB(255, 120, 70), LayoutOrder = 7, Parent = frame }, function()
		controllers.FighterController:Toggle()
	end)
	ui.PvPButton = UIKit.Button({ Text = "PVP", Size = UDim2.fromOffset(90, 44), BackgroundColor3 = Color3.fromRGB(255, 80, 100), LayoutOrder = 3, Parent = frame }, function()
		controllers.PvPController:TogglePanel()
	end)
	ui.CodexButton = UIKit.Button({ Text = "CODEX", Size = UDim2.fromOffset(100, 44), BackgroundColor3 = Color3.fromRGB(190, 90, 175), LayoutOrder = 4, Parent = frame }, function()
		controllers.CodexController:Toggle()
	end)
	ui.GoalsButton = UIKit.Button({ Text = "GOALS", Size = UDim2.fromOffset(100, 44), BackgroundColor3 = Color3.fromRGB(70, 160, 110), LayoutOrder = 5, Parent = frame }, function()
		controllers.GoalsController:Toggle()
	end)
	ui.PartyButton = UIKit.Button({ Text = "PARTY", Size = UDim2.fromOffset(100, 44), BackgroundColor3 = Color3.fromRGB(60, 140, 220), LayoutOrder = 6, Parent = frame }, function()
		controllers.PartyController:Toggle()
	end)
	ui.ShopButton = UIKit.Button({ Text = "🛒 SHOP", Size = UDim2.fromOffset(110, 44), BackgroundColor3 = Color3.fromRGB(220, 165, 40), LayoutOrder = 8, Parent = frame }, function()
		controllers.ShopController:Toggle()
	end)

	-- Phones / tablets: a compact bar (MENU · BUILD · RECALL); the MENU hub has the rest.
	-- Seven buttons would run into the status panel on a small screen.
	ui.MenuButton = UIKit.Button({ Text = "☰ MENU", Size = UDim2.fromOffset(120, 44), BackgroundColor3 = Color3.fromRGB(70, 66, 92), LayoutOrder = -1, Visible = false, Parent = frame }, function()
		controllers.MenuController:Toggle()
	end)
	if UIKit.IsTouchOnly() then
		ui.MenuButton.Visible = true
		for _, button in { ui.SettingsButton, ui.FighterButton, ui.PvPButton, ui.CodexButton, ui.GoalsButton, ui.PartyButton } do
			button.Visible = false
		end
		frame.Size = UDim2.fromOffset(490, 44)
	end
end

local function buildMobileControls(gui: ScreenGui)
	local cluster = UIKit.New("Frame", {
		Name = "TouchControls",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -140, 1, -20),
		Size = UDim2.fromOffset(280, 250),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.AutoScale(cluster)

	local function roundButton(text, x, y, size, color, callback)
		local button = UIKit.Button({
			Text = text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.15,
			MaxTextSize = 15,
			Parent = cluster,
		}, callback)
		button:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
		return button
	end

	local combat = function()
		return controllers.CombatController
	end
	local possession = function()
		return controllers.PossessionController
	end
	roundButton("ATTACK", 215, 190, 92, C.Bad, function()
		if possession():IsPossessing() then
			possession():Light()
		else
			combat():BasicAttack()
		end
	end)
	roundButton("KICK", 120, 212, 62, Color3.fromRGB(230, 110, 60), function()
		if possession():IsPossessing() then
			possession():Heavy()
		else
			combat():Kick()
		end
	end)
	roundButton("DODGE", 225, 112, 62, Color3.fromRGB(200, 170, 60), function()
		if possession():IsPossessing() then
			possession():Dodge()
		else
			combat():Dodge()
		end
	end)
	ui.GuardTouch = roundButton("GUARD", 40, 200, 52, Color3.fromRGB(70, 120, 220), function()
		if possession():IsPossessing() then
			possession():Heavy()
		else
			combat():SetGuard(not combat():IsGuarding()) -- toggle on touch
		end
	end)
	roundButton("Q", 140, 135, 54, C.Accent, function()
		combat():UseAbility(1)
	end)
	roundButton("E", 160, 70, 54, C.Accent, function()
		combat():UseAbility(2)
	end)
	-- (SIC lives in CMD: ATTACK TARGET)
	roundButton("CMD", 60, 130, 52, C.Accent2, function()
		HUDController:ToggleCommandMenu()
	end)
	roundButton("ULT", 80, 62, 50, Color3.fromRGB(230, 170, 40), function()
		combat():Ultimate()
	end)
	roundButton("POSSESS", 235, 30, 56, Color3.fromRGB(150, 80, 230), function()
		controllers.PossessionController:Toggle()
	end)
end

local function buildHints(gui: ScreenGui)
	local text
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		text = "R2 Punch · X Kick (mix them: combos) · Y Weapon · L2 Guard · B Dive / close menu (stick back + B: Step back) · Select Lock-on · L1/R1 Abilities · D-Left Possess · R3 Ultimate · L3 Commands · D-Up Summon · D-Down Retreat · D-Right MENU"
	elseif UserInputService.KeyboardEnabled then
		text = "LMB Punch · RMB click Kick (mix them: combos) · 1-3 Weapons, ` Fists · Ctrl Guard · Shift Dive · X Step back (then hit: counter) · Z Lock-on · Q/E Abilities · F Possess · G Ultimate · V Commands · R Sic · T Stance · C Retreat · H Summon · B Build · P PvP · M Codex · J Goals · L Party · U Fighter (moves, weapons, runs) · K Settings"
	else
		return
	end
	local hint = UIKit.Label({
		Text = text,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(330, 40),
		TextColor3 = C.SubText,
		TextStrokeTransparency = 0.6,
		MaxTextSize = 13,
		Font = UIKit.FontBody,
		Parent = gui,
	})
	UIKit.AutoScale(hint)
	-- Settings: ControlHints
	local function apply()
		hint.Visible = controllers.SettingsController:Get("ControlHints") ~= false
	end
	apply()
	controllers.SettingsController.Changed:Connect(apply)
	controllers.ClientState.Changed:Connect(apply)
end

function HUDController:Start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = UIKit.New("ScreenGui", {
		Name = "CombatHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = playerGui,
	})
	ui.Gui = gui

	buildStatusPanel(gui)
	buildAbilityBar(gui)
	buildMeters(gui)
	buildCommandMenu(gui)
	buildCombosPanel(gui)
	buildTopButtons(gui)
	if UserInputService.TouchEnabled then
		buildMobileControls(gui)
	end
	buildHints(gui)

	ui.Toast = UIKit.Label({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(560, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		MaxTextSize = 22,
		Font = UIKit.FontHeavy,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	UIKit.AutoScale(ui.Toast)

	ui.Target = UIKit.Label({
		Name = "Target",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.fromOffset(360, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 200, 200),
		TextStrokeTransparency = 0.5,
		MaxTextSize = 16,
		Visible = false,
		Parent = gui,
	})
	UIKit.AutoScale(ui.Target)

	controllers.ClientState.ServerEvent:Connect(function(kind, data)
		if kind == "NightmareDefeated" then
			self:Toast(("Your Nightmare was defeated! Reforming in %ds..."):format(data.RespawnIn or 0), C.Bad, 4)
		elseif kind == "Summon" then
			ui.Summoned = data.Summoned == true
			if data.Summoned then
				self:Toast("Nightmare summoned!", C.Accent)
			end
		elseif kind == "LevelUp" then
			local unlocked = LevelUnlocks.At(data.Level)
			local extra = #unlocked > 0 and ("  ·  Unlocked: " .. table.concat(unlocked, ", ")) or ""
			self:Toast(("LEVEL UP!  You are now level %d%s"):format(data.Level, extra), C.Warn, #unlocked > 0 and 6 or 4)
		elseif kind == "Toast" and type(data) == "table" then
			self:Toast(tostring(data.Text), C.Text, 4)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		self:Refresh()
	end)
end

function HUDController:RefreshAbilities(nightmare: Model?)
	local serverNow = Workspace:GetServerTimeNow()
	for slot, entry in ui.AbilitySlots do
		local abilityId = nightmare and nightmare:GetAttribute(("Ability%dId"):format(slot)) or ""
		local def = AbilityDefinitions.Get(abilityId)
		if not def then
			entry.Name.Text = ("[%s] —"):format(entry.Key)
			entry.Sub.Text = nightmare and "no ability equipped" or ""
			entry.Cooldown.Size = UDim2.fromScale(1, 0)
			entry.Button.BackgroundTransparency = 0.5
		else
			local remaining = math.max(0, (nightmare:GetAttribute(("Ability%dReadyAt"):format(slot)) or 0) - serverNow)
			entry.Name.Text = ("[%s] %s"):format(entry.Key, def.DisplayName)
			entry.Sub.Text = remaining > 0 and ("%.1fs"):format(remaining) or "READY"
			entry.Sub.TextColor3 = remaining > 0 and C.SubText or C.Good
			entry.Cooldown.Size = UDim2.fromScale(1, math.clamp(remaining / def.Cooldown, 0, 1))
			entry.Button.BackgroundTransparency = 0.1
		end
	end
end

local function statusText(model: Model?): string
	if not model then
		return ""
	end
	local parts = {}
	for id, stacks in StatusDefinitions.Parse(model:GetAttribute("Statuses")) do
		local def = StatusDefinitions.Get(id)
		if def then
			table.insert(parts, ('<font color="#%s">%s%s</font>'):format(def.Color:ToHex(), def.Icon, stacks > 1 and ("x" .. stacks) or ""))
		end
	end
	return table.concat(parts, " ")
end

function HUDController:RefreshMeters(character: Model?, nightmare: Model?)
	local possession = controllers.PossessionController
	local P = Config.Possession
	if possession:IsPossessing() then
		local left = possession:TimeLeft()
		UIKit.SetBar(ui.PossessionBar, left, P.Duration)
		ui.PossessionBar.Label.Text = ("POSSESSED  %.1fs   ·   LMB combo · RMB heavy · Shift dodge · F exit"):format(left)
	else
		local meter = character and character:GetAttribute("Possession") or 0
		local cooldownLeft = math.max(0, (character and character:GetAttribute("PossessionCooldownEnd") or 0) - Workspace:GetServerTimeNow())
		UIKit.SetBar(ui.PossessionBar, meter, P.MeterMax)
		if cooldownLeft > 0 then
			ui.PossessionBar.Label.Text = ("POSSESSION  recharging %ds"):format(math.ceil(cooldownLeft))
		elseif meter >= P.MeterMax then
			ui.PossessionBar.Label.Text = "POSSESSION READY  ·  press F"
		else
			ui.PossessionBar.Label.Text = ("POSSESSION  %d%%"):format(meter)
		end
	end

	-- SYNC: a banner as it fills, both bodies outlined while it lasts
	local syncedLeft = math.max(0, (character and character:GetAttribute("SyncedUntil") or 0) - Workspace:GetServerTimeNow())
	if syncedLeft > 0 then
		UIKit.SetBar(ui.SyncBar, syncedLeft, Config.Sync.Duration)
		ui.SyncBar.Label.Text = ("SYNCED  %.1fs  ·  you both hit harder"):format(syncedLeft)
		if not ui.Synced then
			self:Toast("SYNCED! You and your Nightmare fight as one", SYNC_COLOR, 2.5)
		end
	else
		local sync = character and character:GetAttribute("Sync") or 0
		UIKit.SetBar(ui.SyncBar, sync, Config.Sync.Max)
		ui.SyncBar.Label.Text = sync > 0 and ("SYNC  %d%%"):format(sync) or "SYNC  ·  hit the same enemy as your Nightmare"
	end
	ui.Synced = syncedLeft > 0
	for _, entry in { { "SyncGlowHandler", character }, { "SyncGlowNightmare", nightmare } } do
		local glow = ui[entry[1]]
		local adornee = ui.Synced and entry[2] or nil
		if adornee and not glow then
			glow = UIKit.New("Highlight", {
				FillTransparency = 1,
				OutlineColor = SYNC_COLOR,
				OutlineTransparency = 0.15,
				DepthMode = Enum.HighlightDepthMode.Occluded,
				Parent = Workspace:FindFirstChild("ClientEffects") or Workspace,
			})
			ui[entry[1]] = glow
		end
		if glow then
			glow.Adornee = adornee
			glow.Enabled = adornee ~= nil
		end
	end

	local ultimateDef = nightmare and AbilityDefinitions.GetUltimate(nightmare:GetAttribute("UltimateId"))
	if ultimateDef then
		local energy = nightmare:GetAttribute("UltimateEnergy") or 0
		UIKit.SetBar(ui.UltimateBar, energy, Config.Ultimate.EnergyMax)
		ui.UltimateBar.Label.Text = energy >= Config.Ultimate.EnergyMax and ("%s READY  ·  press G"):format(ultimateDef.DisplayName) or ("%s  %d%%"):format(ultimateDef.DisplayName, energy)
	else
		UIKit.SetBar(ui.UltimateBar, 0, 1)
		ui.UltimateBar.Label.Text = nightmare and "No Ultimate on this build" or ""
	end

	-- Status icons on Handler & Nightmare
	local handlerStatus = statusText(character)
	local nightmareStatus = statusText(nightmare)
	ui.StatusLine.Text = (handlerStatus ~= "" and ("You: " .. handlerStatus .. "   ") or "") .. (nightmareStatus ~= "" and ("Nightmare: " .. nightmareStatus) or "")
	if nightmare and controllers.ClientState.Profile then
		local stagger = nightmare:GetAttribute("Stagger") or 0
		if stagger > 0 then
			ui.StatusLine.Text ..= ("   Stagger %d/%d"):format(stagger, nightmare:GetAttribute("StaggerMax") or 100)
		end
	end
end

function HUDController:Refresh()
	-- Profile (level / coins / save state)
	local profile = controllers.ClientState.Profile
	if profile then
		ui.LevelLabel.Text = ("LV %d"):format(profile.Level or 1)
		ui.CoinsLabel.Text = ("%d coins · %d essence"):format(profile.Coins or 0, profile.Essence or 0)
		UIKit.SetBar(ui.XPBar, profile.XP or 0, profile.XPToNext or 100)
		ui.SaveStatus.Text = profile.Persistence and "● Progress saving" or "○ Not saving (Studio test profile)"
		ui.SaveStatus.TextColor3 = profile.Persistence and C.Good or C.Warn
	end

	-- Handler
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		UIKit.SetBar(ui.HandlerBar, humanoid.Health, humanoid.MaxHealth)
		UIKit.SetBar(ui.StaminaBar, character:GetAttribute("Stamina") or 0, character:GetAttribute("MaxStamina") or Config.Handler.Stamina.Max)
		ui.StaminaBar.Fill.BackgroundColor3 = character:GetAttribute("GuardBroken") and C.Bad or Color3.fromRGB(240, 210, 90)
	else
		UIKit.SetBar(ui.HandlerBar, 0, Config.Handler.MaxHealth)
	end
	if ui.GuardTouch then
		ui.GuardTouch.BackgroundTransparency = controllers.CombatController:IsGuarding() and 0 or 0.15
		ui.GuardTouch.Text = controllers.CombatController:IsGuarding() and "GUARD ON" or "GUARD"
	end

	-- Nightmare
	local nightmare = controllers.ClientState:GetMyNightmare()
	local nightmareHumanoid = nightmare and nightmare:FindFirstChildOfClass("Humanoid")
	if nightmareHumanoid then
		ui.NightmareName.Text = string.upper(nightmare:GetAttribute("NightmareName") or "Nightmare")
		UIKit.SetBar(ui.NightmareBar, nightmareHumanoid.Health, nightmareHumanoid.MaxHealth)
		local shield = nightmare:GetAttribute("Shield") or 0
		if shield > 0 then
			ui.NightmareBar.Label.Text ..= ("  +%d shield"):format(shield)
		end
		ui.NightmareInfo.Text = ("%s · Power %d · Atk %d · Def %d"):format(
			nightmare:GetAttribute("Archetype") or "?",
			nightmare:GetAttribute("PowerCost") or 0,
			nightmare:GetAttribute("AttackPower") or 0,
			nightmare:GetAttribute("Defence") or 0
		)
		ui.Command.Text = "COMMAND: " .. (COMMAND_TEXT[nightmare:GetAttribute("Command")] or "?")
	elseif ui.Summoned then
		ui.NightmareName.Text = "NIGHTMARE REFORMING..."
		UIKit.SetBar(ui.NightmareBar, 0, 1)
		ui.NightmareInfo.Text = "It will return to your side shortly."
		ui.Command.Text = ""
	else
		ui.NightmareName.Text = "NO NIGHTMARE SUMMONED"
		UIKit.SetBar(ui.NightmareBar, 0, 1)
		ui.NightmareInfo.Text = "Press H (or SUMMON) to call it."
		ui.Command.Text = ""
	end
	ui.SummonButton.Text = ui.Summoned and "RECALL" or "SUMMON"
	self:RefreshAbilities(nightmare)
	self:RefreshMeters(character, nightmare)
	if ui.GuardTouch and controllers.PossessionController:IsPossessing() then
		ui.GuardTouch.Text = "HEAVY"
	end

	-- Target readout
	local target = controllers.CombatController:GetTarget()
	local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
	if targetHumanoid and targetHumanoid.Health > 0 then
		ui.Target.Text = ("TARGET: %s  %d / %d"):format(target:GetAttribute("DisplayName") or target.Name, math.ceil(targetHumanoid.Health), targetHumanoid.MaxHealth)
		ui.Target.Visible = true
	else
		ui.Target.Visible = false
	end
end

return HUDController
