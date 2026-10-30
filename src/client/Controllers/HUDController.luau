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
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local TweenService = game:GetService("TweenService")

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
	ui.ToastLine.BackgroundColor3 = color or C.Accent
	ui.ToastStrip.Visible = not ui.HideAll
	task.delay(duration or 2.5, function()
		if toastToken == token then
			ui.ToastStrip.Visible = false
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

-- The status: no box, a brand on the screen. Your Nightmare's own head (the real sculpted parts,
-- in 3D) in an iron medallion with its level stamped on, its name in scratched lettering, its life, and yours
-- under it. It fades out to nothing behind the bars.
local function buildStatusPanel(gui: ScreenGui)
	local panel = UIKit.New("Frame", {
		Name = "Status",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(384, 176),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	ui.StatusPanel = panel
	UIKit.AutoScale(panel)
	-- the smoked backing, burning out to the right
	UIKit.New("Frame", {
		Name = "Backing",
		Position = UDim2.fromOffset(46, 4),
		Size = UDim2.new(1, -46, 0, 120),
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = panel,
	}, {
		UIKit.New("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		}),
	})

	-- bars (everything sits to the right of the medallion)
	local x = 112
	ui.NightmareName = UIKit.Label({ Text = "NIGHTMARE", Position = UDim2.fromOffset(x, 2), Size = UDim2.new(1, -x, 0, 30), Font = UIKit.FontDisplay, TextStrokeTransparency = 0.1, TextStrokeColor3 = Color3.fromRGB(60, 10, 90), MaxTextSize = 28, Parent = panel })
	ui.NightmareBar = UIKit.Bar({ Position = UDim2.fromOffset(x, 34), Size = UDim2.new(1, -x - 8, 0, 20), Color = C.NightmareHP, MaxTextSize = 14, Parent = panel })
	ui.NightmareInfo = UIKit.Label({ Text = "", Position = UDim2.fromOffset(x, 56), Size = UDim2.new(1, -x - 8, 0, 15), TextColor3 = C.SubText, MaxTextSize = 13, Font = UIKit.FontBody, Parent = panel })
	ui.Command = UIKit.Label({ Text = "", Position = UDim2.fromOffset(x, 71), Size = UDim2.new(1, -x - 8, 0, 15), TextColor3 = C.Accent2, MaxTextSize = 13, Parent = panel })
	UIKit.Label({ Text = "YOU", Position = UDim2.fromOffset(x, 88), Size = UDim2.fromOffset(34, 16), TextColor3 = C.SubText, MaxTextSize = 13, Parent = panel })
	ui.HandlerBar = UIKit.Bar({ Position = UDim2.fromOffset(x + 36, 88), Size = UDim2.new(1, -x - 78, 0, 16), Color = C.HandlerHP, MaxTextSize = 12, Parent = panel })
	ui.StaminaBar = UIKit.Bar({ Position = UDim2.fromOffset(x + 36, 106), Size = UDim2.new(1, -x - 78, 0, 6), Color = Color3.fromRGB(240, 205, 85), Parent = panel })
	ui.StaminaBar.Label.Visible = false

	-- the medallion: iron ring, the head turning slowly in the dark inside it
	local medallion = UIKit.New("Frame", {
		Name = "Medallion",
		Position = UDim2.fromOffset(4, 6),
		Size = UDim2.fromOffset(100, 100),
		BackgroundColor3 = Color3.fromRGB(10, 6, 9),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = panel,
	})
	UIKit.New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = medallion })
	ui.MedallionRing = UIKit.New("UIStroke", { Color = C.Iron, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = medallion })
	UIKit.New("UIGradient", { Color = ColorSequence.new(C.Text, Color3.fromRGB(60, 40, 40)), Rotation = 60, Parent = ui.MedallionRing })
	ui.Portrait = UIKit.New("ViewportFrame", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = Color3.fromRGB(24, 12, 30),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = medallion,
	})
	UIKit.New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ui.Portrait })
	UIKit.New("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(130, 100, 150)), Rotation = 90, Parent = ui.Portrait })
	-- the level, a stamped plate across the bottom of the ring
	local plate = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.fromOffset(58, 24),
		BackgroundColor3 = Color3.fromRGB(150, 56, 28),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = medallion,
	}, { UIKit.Corner(3), UIKit.Stroke(Color3.fromRGB(20, 10, 8), 2) })
	ui.LevelLabel = UIKit.Label({ Text = "LV 1", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextStrokeTransparency = 0.2, MaxTextSize = 18, ZIndex = 6, Parent = plate })

	-- the purse, and how far to the next level, along the bottom
	ui.XPBar = UIKit.Bar({ Position = UDim2.fromOffset(6, 124), Size = UDim2.new(1, -46, 0, 5), Color = C.Warn, Parent = panel })
	ui.XPBar.Label.Visible = false
	ui.CoinsLabel = UIKit.Label({ Text = "0 coins", Position = UDim2.fromOffset(6, 130), Size = UDim2.new(1, -46, 0, 16), TextColor3 = C.Warn, MaxTextSize = 14, Parent = panel })
	ui.StatusLine = UIKit.Label({ Text = "", Position = UDim2.fromOffset(6, 146), Size = UDim2.new(1, -46, 0, 15), RichText = true, MaxTextSize = 13, Parent = panel })
	ui.SaveStatus = UIKit.Label({ Text = "", Position = UDim2.fromOffset(6, 161), Size = UDim2.new(1, -46, 0, 12), TextColor3 = C.SubText, MaxTextSize = 11, Font = UIKit.FontBody, Parent = panel })
end

-- Which parts of a body gave it an ability, for its icon.
local function partsOfSlot(model: Model, slot: string)
	local list = {}
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name:match("^" .. slot .. "_%d+$") and part.Transparency < 0.95 then
			table.insert(list, part)
		end
	end
	return list
end

local ABILITY_SLOT = {}
for id, def in PartDefinitions.ById do
	if def.AbilityId then
		ABILITY_SLOT[def.AbilityId] = def.Slot
	end
end

local function refreshPortrait(nightmare: Model?)
	if ui.PortraitOf == nightmare then
		return
	end
	local parts = nightmare and partsOfSlot(nightmare, "Head") or {}
	if nightmare and #parts == 0 then
		parts = partsOfSlot(nightmare, "Core")
	end
	if nightmare and #parts == 0 then
		return -- (still loading in: try again next refresh)
	end
	ui.PortraitOf = nightmare
	ui.PortraitCamera = UIKit.ShowParts(ui.Portrait, parts, 22)
	ui.PortraitBase = ui.PortraitCamera and ui.PortraitCamera.CFrame or nil
end

-- the head turns a little, as if it's looking about; the ring burns when it's hurt
local function animatePortrait(nightmare: Model?, health: number?)
	local camera = ui.PortraitCamera
	if camera and ui.PortraitBase then
		local t = os.clock()
		local focus = ui.PortraitBase.Position + ui.PortraitBase.LookVector * 10
		camera.CFrame = CFrame.lookAt(focus + CFrame.Angles(math.sin(t * 0.4) * 0.1, math.sin(t * 0.7) * 0.28, 0):VectorToWorldSpace(ui.PortraitBase.Position - focus), focus)
	end
	if health and ui.LastPortraitHealth and health < ui.LastPortraitHealth - 0.5 then
		ui.MedallionRing.Color = C.Bad
		TweenService:Create(ui.MedallionRing, TweenInfo.new(0.5), { Color = C.Iron }):Play()
		ui.Portrait.ImageColor3 = Color3.fromRGB(255, 90, 80)
		TweenService:Create(ui.Portrait, TweenInfo.new(0.45), { ImageColor3 = Color3.new(1, 1, 1) }):Play()
	end
	ui.LastPortraitHealth = health
	local _ = nightmare
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
	ui.AbilityBar = bar
	bar:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Center
	UIKit.AutoScale(bar)
	UIKit.PlaceHudCenter(bar, 16)
	ui.AbilitySlots = {}
	for slot, key in { "Q", "E" } do
		local button = UIKit.Button({
			Size = UDim2.fromOffset(160, 64),
			BackgroundColor3 = C.PanelLight,
			LayoutOrder = slot,
			Parent = bar,
		}, function()
			controllers.CombatController:UseAbility(slot)
		end)
		local ring = UIKit.Stroke(C.Iron, 2, 0.1)
		ring.Parent = button
		-- the part behind the ability, in 3D, in the left of the plate
		local icon = UIKit.New("ViewportFrame", {
			Position = UDim2.fromOffset(-6, -3),
			Size = UDim2.new(0, 58, 1, 6),
			BackgroundColor3 = Color3.fromRGB(14, 9, 12),
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = button,
		})
		local cooldown = UIKit.New("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, -6, 1, 3),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			ZIndex = 3,
			Parent = button,
		})
		-- the key, stamped on the icon's corner
		local badge = UIKit.New("Frame", { Position = UDim2.fromOffset(-6, -3), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromRGB(150, 56, 28), BorderSizePixel = 0, ZIndex = 5, Parent = button })
		UIKit.Label({ Text = key, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2, MaxTextSize = 15, ZIndex = 6, Parent = badge })
		local name = UIKit.Label({ Text = "", Position = UDim2.fromOffset(56, 2), Size = UDim2.new(1, -60, 0.58, -2), MaxTextSize = 15, ZIndex = 4, Parent = button })
		local sub = UIKit.Label({ Text = "", Position = UDim2.new(0, 56, 0.58, 0), Size = UDim2.new(1, -60, 0.42, -2), TextColor3 = C.SubText, MaxTextSize = 14, ZIndex = 4, Parent = button })
		-- the time left, big over the icon
		local count = UIKit.Label({ Text = "", Position = UDim2.fromOffset(-6, -3), Size = UDim2.new(0, 58, 1, 6), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextStrokeTransparency = 0, MaxTextSize = 26, ZIndex = 5, Parent = button })
		ui.AbilitySlots[slot] = { Button = button, Cooldown = cooldown, Name = name, Sub = sub, Key = key, Icon = icon, Ring = ring, Count = count }
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
	ui.SyncBar = UIKit.Bar({ Size = UDim2.new(1, 0, 0, 15), Color = SYNC_COLOR, MaxTextSize = 13, Parent = frame })
	ui.PossessionBar = UIKit.Bar({ Position = UDim2.fromOffset(0, 17), Size = UDim2.new(1, 0, 0, 17), Color = Color3.fromRGB(170, 100, 255), MaxTextSize = 12, Parent = frame })
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

local function buildCombosPanel(hud: ScreenGui)
	-- (its own layer, above the hotbar and the rest of the HUD)
	local gui = UIKit.New("ScreenGui", { Name = "NightmareCombos", ResetOnSpawn = false, DisplayOrder = 21, IgnoreGuiInset = hud.IgnoreGuiInset, Parent = hud.Parent })
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
	ui.TopButtons = frame
	UIKit.AutoScale(frame)
	frame:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Right

	-- A row of iron tabs instead of a rainbow: each carries its colour as a hot strip along the
	-- bottom, and a stamped key letter on the corner.
	local function tab(text: string, width: number, color: Color3, order: number, key: string?, onClick)
		local button = UIKit.Button({ Text = text, Size = UDim2.fromOffset(width, 40), BackgroundColor3 = C.PanelLight, MaxTextSize = 17, LayoutOrder = order, Parent = frame }, onClick)
		UIKit.New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -6, 1, 3), Size = UDim2.new(1, 12, 0, 4), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 2, Parent = button })
		if key and UserInputService.KeyboardEnabled then
			UIKit.Label({ Text = key, Position = UDim2.fromOffset(-3, -2), Size = UDim2.fromOffset(14, 13), TextColor3 = C.SubText, MaxTextSize = 11, ZIndex = 2, Parent = button })
		end
		return button
	end
	ui.SettingsButton = tab("⚙", 40, C.Iron, 0, "K", function()
		controllers.SettingsController:Toggle()
	end)
	ui.SettingsButton.TextSize = 22
	ui.BuildButton = tab("BUILD", 92, C.Accent, 1, "B", function()
		controllers.WorkshopController:Toggle()
	end)
	ui.SummonButton = tab("RECALL", 92, C.Accent2, 2, "H", function()
		controllers.CombatController:ToggleSummon()
	end)
	ui.PvPButton = tab("PVP", 72, Color3.fromRGB(255, 70, 90), 3, "P", function()
		controllers.PvPController:TogglePanel()
	end)
	ui.CodexButton = tab("CODEX", 84, Color3.fromRGB(190, 90, 175), 4, "M", function()
		controllers.CodexController:Toggle()
	end)
	ui.GoalsButton = tab("GOALS", 84, C.Good, 5, "J", function()
		controllers.GoalsController:Toggle()
	end)
	ui.PartyButton = tab("PARTY", 84, Color3.fromRGB(70, 160, 240), 6, "L", function()
		controllers.PartyController:Toggle()
	end)
	ui.FighterButton = tab("FIGHTER", 92, Color3.fromRGB(255, 130, 60), 7, "U", function()
		controllers.FighterController:Toggle()
	end)
	ui.ShopButton = tab("SHOP", 84, C.Warn, 8, nil, function()
		controllers.ShopController:Toggle()
	end)

	-- Phones / tablets: a compact bar (MENU · BUILD · RECALL); the MENU hub has the rest.
	-- Seven buttons would run into the status panel on a small screen.
	ui.MenuButton = tab("☰ MENU", 120, C.Iron, -1, nil, function()
		controllers.MenuController:Toggle()
	end)
	ui.MenuButton.Visible = false
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
		button.Skin:Destroy() -- (its square edges don't belong on a round button)
		UIKit.Stroke(C.IronDark, 3).Parent = button
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
		text = "LMB Punch · RMB click Kick (mix them: combos) · 1-3 Weapons, ` Fists · Ctrl Guard · Shift Dive · X Step back (then hit: counter) · Z Lock-on · Q/E Abilities · F Possess · G Ultimate · V Commands · R Sic · T Stance · C Retreat · H Summon · B Build · P PvP · M Codex · J Goals · L Party · U Fighter (moves, weapons, runs) · K Settings · Y Hide HUD"
	else
		return
	end
	local hint = UIKit.Label({
		Text = text,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(450, 70),
		TextColor3 = C.SubText,
		TextStrokeTransparency = 0.6,
		MaxTextSize = 13,
		Font = UIKit.FontBody,
		Parent = gui,
	})
	UIKit.AutoScale(hint)
	-- Settings: ControlHints
	local function apply()
		hint.Visible = controllers.SettingsController:Get("ControlHints") ~= false and not ui.HideAll
	end
	ui.ApplyHint = apply
	apply()
	-- (it has done its job after a while: it fades back so it isn't a wall of text in the corner)
	task.delay(25, function()
		TweenService:Create(hint, TweenInfo.new(3), { TextTransparency = 0.72, TextStrokeTransparency = 1 }):Play()
	end)
	controllers.SettingsController.Changed:Connect(apply)
	controllers.ClientState.Changed:Connect(apply)
end

-- WHICH PARTS SHOW: each one's own setting (saved), and the whole HUD off for the moment (Y, not
-- saved: nobody should come back to a game with no HUD and not know why). Only the HUD itself:
-- menus still open, and touch controls stay, or a phone couldn't play.
function HUDController:ApplyParts()
	local settings = controllers.SettingsController
	local function shown(key: string): boolean
		return not ui.HideAll and settings:Get(key) ~= false
	end
	ui.StatusPanel.Visible = shown("HudStatus")
	ui.AbilityBar.Visible = shown("HudAbilities")
	ui.Meters.Visible = shown("HudMeters")
	ui.TopButtons.Visible = shown("HudButtons")
	ui.HurtLayer.Enabled = shown("HudHurtEdges")
	ui.TargetAllowed = shown("HudTarget")
	if not ui.TargetAllowed then
		ui.TargetFrame.Visible = false
	end
	if ui.HideAll then
		ui.ToastStrip.Visible = false
	end
	if ui.ApplyHint then
		ui.ApplyHint()
	end
	controllers.MeleeController:SetHudVisible(shown("HudHotbar"))
	controllers.BossController:SetBarAllowed(not ui.HideAll)
	-- a way back, always: the corner button, whenever the top row is gone
	ui.ShowHudButton.Visible = ui.HideAll == true or settings:Get("HudButtons") == false
	ui.ShowHudButton.Text = ui.HideAll and "SHOW HUD" or "SETTINGS"
end

function HUDController:ToggleHideAll(force: boolean?)
	if force == nil then
		ui.HideAll = not ui.HideAll
	else
		ui.HideAll = force
	end
	self:ApplyParts()
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

	-- A toast: a strip of smoke across the screen, burning out at both ends, a hot line under it.
	ui.ToastStrip = UIKit.New("Frame", {
		Name = "ToastStrip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(620, 38),
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	}, {
		UIKit.New("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.15), NumberSequenceKeypoint.new(0.82, 0.15), NumberSequenceKeypoint.new(1, 1) }) }),
	})
	UIKit.AutoScale(ui.ToastStrip)
	ui.ToastLine = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = ui.ToastStrip,
	}, {
		UIKit.New("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0), NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(1, 1) }) }),
	})
	ui.Toast = UIKit.Label({
		Name = "Toast",
		Position = UDim2.fromScale(0.08, 0),
		Size = UDim2.fromScale(0.84, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		MaxTextSize = 24,
		Font = UIKit.FontHeavy,
		ZIndex = 7,
		Parent = ui.ToastStrip,
	})

	-- What you're fighting: its name and its life, under the toast.
	ui.TargetFrame = UIKit.New("Frame", {
		Name = "Target",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(300, 34),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	UIKit.AutoScale(ui.TargetFrame)
	ui.Target = UIKit.Label({ Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextColor3 = Color3.fromRGB(255, 205, 190), TextStrokeTransparency = 0.15, MaxTextSize = 20, Parent = ui.TargetFrame })
	ui.TargetBar = UIKit.Bar({ Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, 0, 0, 14), Color = C.EnemyHP, MaxTextSize = 12, Parent = ui.TargetFrame })

	-- HURT: the edges of the screen go dark and red, and pulse as it gets worse.
	ui.Hurt = {}
	local hurtLayer = UIKit.New("ScreenGui", { Name = "HurtEdges", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1, Parent = playerGui })
	ui.HurtLayer = hurtLayer
	for _, edge in {
		{ Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.22, 0), 90 },
		{ Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0.22, 0), 270 },
		{ Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0.16, 0, 1, 0), 0 },
		{ Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.new(0.16, 0, 1, 0), 180 },
	} do
		local frame = UIKit.New("Frame", { AnchorPoint = edge[1], Position = edge[2], Size = edge[3], BackgroundColor3 = Color3.fromRGB(110, 8, 8), BorderSizePixel = 0, BackgroundTransparency = 1, Parent = hurtLayer })
		UIKit.New("UIGradient", { Rotation = edge[4], Transparency = NumberSequence.new(0, 1), Parent = frame })
		table.insert(ui.Hurt, frame)
	end

	-- the way back when the HUD or its buttons are hidden: it fades out of the way until you want it
	ui.ShowHudButton = UIKit.Button({
		Text = "SHOW HUD",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(104, 30),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.35,
		MaxTextSize = 14,
		Visible = false,
		Parent = gui,
	}, function()
		if ui.HideAll then
			self:ToggleHideAll(false)
		else
			controllers.SettingsController:Toggle()
		end
	end)
	UIKit.AutoScale(ui.ShowHudButton)
	controllers.SettingsController.Changed:Connect(function()
		self:ApplyParts()
	end)
	controllers.ClientState.Changed:Connect(function()
		self:ApplyParts()
	end)
	task.defer(function()
		self:ApplyParts()
	end)

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
		-- the icon: the real part that gives it
		local iconKey = def and nightmare and (tostring(nightmare) .. abilityId) or ""
		if entry.IconKey ~= iconKey then
			local parts = {}
			if def and nightmare then
				local partSlot = ABILITY_SLOT[abilityId] or "Head"
				if partSlot == "RightArm" or partSlot == "LeftArm" then
					parts = partsOfSlot(nightmare, "RightArm")
					if #parts == 0 then
						parts = partsOfSlot(nightmare, "LeftArm")
					end
				else
					parts = partsOfSlot(nightmare, partSlot)
				end
			end
			if #parts > 0 or iconKey == "" then
				entry.IconKey = iconKey
				UIKit.ShowParts(entry.Icon, parts, 35)
			end
		end
		if not def then
			entry.Name.Text = "—"
			entry.Sub.Text = nightmare and "no ability" or ""
			entry.Count.Text = ""
			entry.Cooldown.Size = UDim2.fromScale(1, 0)
			entry.Ring.Color = C.IronDark
		else
			local remaining = math.max(0, (nightmare:GetAttribute(("Ability%dReadyAt"):format(slot)) or 0) - serverNow)
			entry.Name.Text = def.DisplayName
			entry.Sub.Text = remaining > 0 and "RECHARGING" or "READY"
			entry.Sub.TextColor3 = remaining > 0 and C.SubText or C.Good
			entry.Count.Text = remaining > 0 and (remaining >= 10 and ("%d"):format(remaining) or ("%.1f"):format(remaining)) or ""
			-- (the dark drains off the icon as it comes back)
			entry.Cooldown.Size = UDim2.new(0, 58, math.clamp(remaining / def.Cooldown, 0, 1), remaining > 0 and 6 or 0)
			entry.Ring.Color = remaining > 0 and C.IronDark or C.Accent
			-- the moment it's back: a flash round the plate
			if entry.WasCooling and remaining <= 0 then
				entry.Ring.Color = C.Text
				TweenService:Create(entry.Ring, TweenInfo.new(0.5), { Color = C.Accent }):Play()
			end
			entry.WasCooling = remaining > 0
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
		local ready = energy >= Config.Ultimate.EnergyMax
		ui.UltimateBar.Label.Text = ready and ("%s READY  ·  press G"):format(ultimateDef.DisplayName) or ("%s  %d%%"):format(ultimateDef.DisplayName, energy)
		-- full: the whole bar burns, a light running along it
		local stroke = ui.UltimateBar.Frame:FindFirstChildOfClass("UIStroke")
		local burn = ready and (0.5 + 0.5 * math.sin(os.clock() * 7)) or 0
		stroke.Color = ready and C.Warn:Lerp(C.Text, burn) or C.IronDark
		ui.UltimateBar.Fill.BackgroundColor3 = ready and Color3.fromRGB(255, 165, 40):Lerp(Color3.fromRGB(255, 235, 170), burn) or Color3.fromRGB(255, 165, 40)
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
		ui.Target.Text = target:GetAttribute("DisplayName") or target.Name
		if ui.TargetOf ~= target then
			ui.TargetOf = target
			ui.TargetBar.Ratio = nil -- (a new body: no chip from the last one)
			ui.TargetBar.Chip.Size = UDim2.fromScale(0, 1)
		end
		UIKit.SetBar(ui.TargetBar, targetHumanoid.Health, targetHumanoid.MaxHealth)
		ui.TargetFrame.Visible = ui.TargetAllowed ~= false
	else
		ui.TargetFrame.Visible = false
	end

	refreshPortrait(nightmare)
	animatePortrait(nightmare, nightmareHumanoid and nightmareHumanoid.Health or nil)
	-- the edges of the screen when you're close to going down
	local lowest = humanoid and humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
	local pain = lowest < 0.35 and (1 - lowest / 0.35) or 0
	local pulse = pain > 0 and (0.55 + 0.45 * math.sin(os.clock() * (3 + pain * 5))) or 0
	for _, frame in ui.Hurt do
		frame.BackgroundTransparency = 1 - math.clamp(pain * (0.45 + 0.4 * pulse), 0, 0.8)
	end
end

return HUDController
