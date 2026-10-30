--[[
	WorkshopController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/WorkshopController

	The Nightmare Workshop: full-screen creature builder (built in code).

	  LEFT    three saved-build tabs · seven slot buttons · owned parts for the slot
	          (rarity colour bar, Power Cost, owned count, "None" for optional slots)
	  CENTRE  live 3D preview (ViewportFrame) using the SAME NightmareAssembler as the
	          server · drag / right stick to orbit · zoom · selected-socket marker
	  RIGHT   name · stats with +/- vs saved (colour AND ▲/▼ text for colour-blind
	          players) · Power Cost meter · selected part details · fit controls
	          (scale/yaw/pitch within safe limits) · Undo · Reset · Save · Set Active

	Everything edits a local DRAFT. Only SAVE sends it to the server, which re-validates
	ownership, slots, Legendary limit, Power Cost and filters the name.

	Open with B / D-Pad Right / the BUILD button / the workshop table's ProximityPrompt.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local SlotDefinitions = require(Shared:WaitForChild("SlotDefinitions"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local RarityDefinitions = require(Shared:WaitForChild("RarityDefinitions"))
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))
local BuildValidator = require(Shared:WaitForChild("BuildValidator"))
local NightmareAssembler = require(Shared:WaitForChild("NightmareAssembler"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local WorkshopController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local STAT_LABELS = {
	MaxHealth = "Max Health",
	AttackPower = "Attack Power",
	Defence = "Defence",
	MoveSpeed = "Move Speed",
	AttackSpeed = "Attack Speed",
	Reach = "Reach",
}
local HISTORY_LIMIT = 50

local controllers
local ui = {}
local state = {
	open = false,
	buildIndex = 1,
	selectedSlot = "Core",
	draft = nil,
	saved = nil,
	history = {},
	saving = false,
	-- camera
	yaw = 0.5,
	pitch = 0.3,
	zoom = 1,
	focus = Vector3.zero,
	fitDistance = 14,
	dragging = false,
	lastPointer = nil,
	stick = Vector2.zero,
	lastInteraction = 0,
}

------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------
local function profile()
	return controllers.ClientState.Profile
end

local function rarityColor(def): Color3
	return def and RarityDefinitions.Info[def.Rarity].Color or C.SubText
end

local function ensureAdjust(slot: string)
	state.draft.Adjust = state.draft.Adjust or {}
	local adjust = state.draft.Adjust[slot]
	if not adjust then
		adjust = BuildValidator.DefaultAdjust()
		state.draft.Adjust[slot] = adjust
	end
	return adjust
end

local function isDirty(): boolean
	return state.draft ~= nil and not Util.DeepEqual(state.draft, state.saved)
end

local function isCreateStep(): boolean
	return controllers.TutorialController ~= nil and controllers.TutorialController:IsCreateStep()
end

local function setMessage(text: string?, color: Color3?)
	ui.Message.Text = text or ""
	ui.Message.TextColor3 = color or C.SubText
end

local function statLine(stats): string
	local parts = {}
	for _, row in StatCalculator.DisplayOrder do
		local value = stats[row.Key]
		if value and value ~= 0 then
			table.insert(parts, ("%s%d %s"):format(value > 0 and "+" or "", value, row.Label))
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "No stat changes"
end

------------------------------------------------------------------------------------------
-- Draft editing
------------------------------------------------------------------------------------------
function WorkshopController:Change(mutator)
	table.insert(state.history, Util.DeepCopy(state.draft))
	if #state.history > HISTORY_LIMIT then
		table.remove(state.history, 1)
	end
	mutator(state.draft)
	self:RefreshAll()
end

function WorkshopController:LoadBuild(index: number)
	local p = profile()
	if not p or not p.Builds[index] then
		return
	end
	state.buildIndex = index
	state.saved = Util.DeepCopy(p.Builds[index])
	state.draft = Util.DeepCopy(p.Builds[index])
	state.history = {}
	self:RefreshAll()
end

-- mutationId = nil equips the plain part.
function WorkshopController:EquipPart(partId: string?, mutationId: string?)
	local slot = state.selectedSlot
	if state.draft.Parts[slot] == partId and MutationDefinitions.ForSlot(state.draft, slot) == mutationId then
		return
	end
	self:Change(function(draft)
		draft.Parts[slot] = partId
		if partId and mutationId then
			draft.Mutations = draft.Mutations or {}
			draft.Mutations[slot] = mutationId
		elseif draft.Mutations then
			draft.Mutations[slot] = nil
			-- Back to no mutations at all: match the saved build's shape (older saves have
			-- no Mutations table) so "unsaved changes" only shows for real changes.
			if next(draft.Mutations) == nil and not (state.saved and state.saved.Mutations) then
				draft.Mutations = nil
			end
		end
	end)
end

function WorkshopController:Adjust(key: string, delta: number)
	local cfg = Config.Builds
	self:Change(function()
		local adjust = ensureAdjust(state.selectedSlot)
		if key == "Scale" then
			adjust.Scale = Util.RoundTo(math.clamp(adjust.Scale + delta, cfg.ScaleMin, cfg.ScaleMax), 0.01)
		else
			adjust[key] = math.clamp(adjust[key] + delta, -cfg.RotateLimit, cfg.RotateLimit)
		end
	end)
end

function WorkshopController:ResetFit()
	self:Change(function(draft)
		draft.Adjust[state.selectedSlot] = BuildValidator.DefaultAdjust()
	end)
end

function WorkshopController:Undo()
	local previous = table.remove(state.history)
	if previous then
		state.draft = previous
		self:RefreshAll()
	end
end

function WorkshopController:ResetToSaved()
	if not isDirty() then
		return
	end
	self:Change(function()
		state.draft = Util.DeepCopy(state.saved)
	end)
end

function WorkshopController:Save()
	if state.saving or (not isDirty() and not isCreateStep()) then
		return
	end
	local p = profile()
	local ok, err = BuildValidator.Validate(state.draft, p.Inventory, p.PowerBudget, p.Mutations)
	if not ok then
		setMessage(err, C.Bad)
		return
	end

	state.saving = true
	setMessage("Saving...", C.SubText)
	local result = controllers.ClientState:Request("SaveBuild", state.buildIndex, state.draft)
	state.saving = false

	if result.Ok then
		self:LoadBuild(state.buildIndex)
		local isActive = profile().ActiveBuild == state.buildIndex
		setMessage(result.Warning or (isActive and "Saved! Your Nightmare is reforming." or "Saved!"), result.Warning and C.Warn or C.Good)
	else
		setMessage(result.Error or "Save failed.", C.Bad)
	end
end

function WorkshopController:SetActive()
	if isDirty() then
		setMessage("Save your changes before setting this build active.", C.Warn)
		return
	end
	local result = controllers.ClientState:Request("SetActive", state.buildIndex)
	if result.Ok then
		setMessage("Active Nightmare switched!", C.Good)
		self:RefreshAll()
	else
		setMessage(result.Error or "Could not switch.", C.Bad)
	end
end

------------------------------------------------------------------------------------------
-- GUI construction
------------------------------------------------------------------------------------------
local function panel(name, position, size, parent)
	return UIKit.New("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = C.Panel,
		Parent = parent,
	}, { UIKit.Corner(12), UIKit.Padding(8) })
end

function WorkshopController:BuildGui()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screen = UIKit.New("ScreenGui", {
		Name = "WorkshopGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Enabled = false,
		Parent = playerGui,
	})
	ui.Screen = screen

	local root = UIKit.New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.04,
		Parent = screen,
	})

	-- Header ------------------------------------------------------------------------------
	local header = UIKit.New("Frame", {
		Position = UDim2.fromScale(0.01, 0.015),
		Size = UDim2.fromScale(0.98, 0.075),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local title = UIKit.Label({ Text = "NIGHTMARE WORKSHOP", Size = UDim2.fromScale(0.26, 1), Font = UIKit.FontHeavy, TextColor3 = C.Accent, MaxTextSize = 30, Parent = header })
	-- Keep the title clear of Roblox's top-bar buttons (the screen ignores the GUI inset).
	local function fitTitle()
		local pad = math.max(0, GuiService.TopbarInset.Min.X - header.AbsolutePosition.X)
		title.Position = UDim2.fromOffset(pad, 0)
		title.Size = UDim2.new(0.26, -pad, 1, 0)
	end
	fitTitle()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fitTitle)
	header:GetPropertyChangedSignal("AbsolutePosition"):Connect(fitTitle)

	ui.BuildTabs = {}
	-- (MaxSlotCount tabs; RefreshHeader shows as many as you have saved builds, laid out
	-- across the header, plus a "+3 SLOTS" tab that opens the SHOP while you have 3)
	for index = 1, Config.Builds.MaxSlotCount do
		local tab = UIKit.Button({
			Position = UDim2.fromScale(0.27 + (index - 1) * 0.16, 0.1),
			Size = UDim2.fromScale(0.15, 0.8),
			MaxTextSize = 16,
			Parent = header,
		}, function()
			if index ~= state.buildIndex then
				local discarded = isDirty()
				self:LoadBuild(index)
				if discarded then
					setMessage("Unsaved changes on the previous build were discarded.", C.Warn)
				end
			end
		end)
		ui.BuildTabs[index] = tab
	end
	ui.MoreSlotsTab = UIKit.Button({ Text = "+3 SLOTS 🛒", Size = UDim2.fromScale(0.15, 0.8), BackgroundColor3 = Color3.fromRGB(150, 110, 30), MaxTextSize = 14, Visible = false, Parent = header }, function()
		controllers.ShopController:Open("Perks")
	end)
	ui.FirstButton = ui.BuildTabs[1]

	UIKit.Button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0.1),
		Size = UDim2.fromScale(0.1, 0.8),
		BackgroundColor3 = C.PanelLighter,
		Parent = header,
	}, function()
		self:Close()
	end)

	-- Left: slots + parts -------------------------------------------------------------------
	local left = panel("Left", UDim2.fromScale(0.01, 0.105), UDim2.fromScale(0.25, 0.88), root)
	local slotFrame = UIKit.New("Frame", { Size = UDim2.fromScale(1, 0.44), BackgroundTransparency = 1, Parent = left }, { UIKit.List(4) })
	ui.SlotButtons = {}
	for order, slot in SlotDefinitions.Order do
		local button = UIKit.Button({
			Size = UDim2.new(1, 0, 1 / #SlotDefinitions.Order, -4),
			LayoutOrder = order,
			RichText = true,
			Font = UIKit.Font,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 15,
			Parent = slotFrame,
		}, function()
			state.selectedSlot = slot
			self:RefreshAll()
		end)
		ui.SlotButtons[slot] = { Button = button, Stroke = UIKit.Stroke(C.Accent, 2, 1) }
		ui.SlotButtons[slot].Stroke.Parent = button
	end

	ui.PartsTitle = UIKit.Label({ Text = "PARTS", Position = UDim2.fromScale(0, 0.455), Size = UDim2.fromScale(1, 0.04), TextColor3 = C.SubText, MaxTextSize = 14, Parent = left })
	ui.PartList = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = left,
	}, { UIKit.List(5) })

	-- Centre: 3D preview --------------------------------------------------------------------
	local centre = panel("Centre", UDim2.fromScale(0.27, 0.105), UDim2.fromScale(0.45, 0.88), root)
	local viewport = UIKit.New("ViewportFrame", {
		Size = UDim2.fromScale(1, 0.9),
		BackgroundColor3 = Color3.fromRGB(22, 18, 34),
		Ambient = Color3.fromRGB(150, 140, 175),
		LightColor = Color3.fromRGB(255, 245, 235),
		LightDirection = Vector3.new(-1, -1.5, -0.6),
		Active = true,
		Parent = centre,
	}, { UIKit.Corner(10) })
	ui.Viewport = viewport
	ui.WorldModel = UIKit.New("WorldModel", { Parent = viewport })
	ui.Camera = UIKit.New("Camera", { FieldOfView = 40, Parent = viewport })
	viewport.CurrentCamera = ui.Camera

	-- Pedestal under the creature
	ui.Pedestal = UIKit.New("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 9, 9),
		Color = Color3.fromRGB(60, 50, 85),
		Material = Enum.Material.Marble,
		Anchored = true,
		Parent = ui.WorldModel,
	})
	ui.PedestalRing = UIKit.New("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 9.6, 9.6),
		Color = C.Accent,
		Material = Enum.Material.Neon,
		Anchored = true,
		Parent = ui.WorldModel,
	})
	-- Glowing marker on the selected socket
	ui.SocketMarker = UIKit.New("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.7, 0.7, 0.7),
		Color = Color3.fromRGB(120, 230, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		Anchored = true,
		Parent = ui.WorldModel,
	})

	ui.ArchetypeLabel = UIKit.Label({
		Position = UDim2.fromScale(0.03, 0.02),
		Size = UDim2.fromScale(0.6, 0.05),
		TextColor3 = C.SubText,
		MaxTextSize = 16,
		ZIndex = 2,
		Parent = viewport,
	})

	local camBar = UIKit.New("Frame", {
		Position = UDim2.fromScale(0, 0.915),
		Size = UDim2.fromScale(1, 0.085),
		BackgroundTransparency = 1,
		Parent = centre,
	}, { UIKit.List(6, Enum.FillDirection.Horizontal) })
	camBar:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Center
	UIKit.Button({ Text = "ZOOM −", Size = UDim2.fromScale(0.2, 1), LayoutOrder = 1, Parent = camBar }, function()
		state.zoom = math.clamp(state.zoom + 0.15, 0.55, 1.8)
	end)
	UIKit.Button({ Text = "ZOOM +", Size = UDim2.fromScale(0.2, 1), LayoutOrder = 2, Parent = camBar }, function()
		state.zoom = math.clamp(state.zoom - 0.15, 0.55, 1.8)
	end)
	UIKit.Button({ Text = "FRONT VIEW", Size = UDim2.fromScale(0.25, 1), LayoutOrder = 3, Parent = camBar }, function()
		state.yaw, state.pitch, state.zoom = 0.5, 0.3, 1
		state.lastInteraction = os.clock()
	end)

	-- Right: info & actions -----------------------------------------------------------------
	local right = panel("Right", UDim2.fromScale(0.73, 0.105), UDim2.fromScale(0.26, 0.88), root)
	UIKit.List(6).Parent = right

	ui.NameBox = UIKit.New("TextBox", {
		Size = UDim2.fromScale(1, 0.065),
		BackgroundColor3 = C.PanelLight,
		Font = UIKit.FontHeavy,
		TextColor3 = C.Text,
		PlaceholderText = "Name your Nightmare",
		PlaceholderColor3 = C.SubText,
		ClearTextOnFocus = false,
		TextScaled = true,
		LayoutOrder = 1,
		Parent = right,
	}, { UIKit.Corner(8), UIKit.New("UITextSizeConstraint", { MaxTextSize = 20 }) })
	ui.NameBox.FocusLost:Connect(function()
		if not state.draft then
			return
		end
		local name = Util.TruncateUtf8(Util.Trim(ui.NameBox.Text), Config.Builds.MaxNameLength)
		if name ~= "" and name ~= state.draft.Name then
			self:Change(function(draft)
				draft.Name = name
			end)
		else
			ui.NameBox.Text = state.draft.Name
		end
	end)

	local statsFrame = UIKit.New("Frame", {
		Size = UDim2.fromScale(1, 0.3),
		BackgroundColor3 = C.PanelLight,
		LayoutOrder = 2,
		Parent = right,
	}, { UIKit.Corner(8), UIKit.Padding(6), UIKit.List(2) })
	ui.StatRows = {}
	local rowCount = #StatCalculator.DisplayOrder + 1
	for order, row in StatCalculator.DisplayOrder do
		local rowFrame = UIKit.New("Frame", { Size = UDim2.new(1, 0, 1 / rowCount, -2), BackgroundTransparency = 1, LayoutOrder = order, Parent = statsFrame })
		UIKit.Label({ Text = row.Label, Size = UDim2.fromScale(0.5, 1), TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 15, Parent = rowFrame })
		ui.StatRows[row.Key] = UIKit.Label({ Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.5, 1), TextXAlignment = Enum.TextXAlignment.Right, RichText = true, MaxTextSize = 15, Parent = rowFrame })
	end
	local powerRow = UIKit.New("Frame", { Size = UDim2.new(1, 0, 1 / rowCount, -2), BackgroundTransparency = 1, LayoutOrder = rowCount, Parent = statsFrame })
	ui.PowerBar = UIKit.Bar({ Size = UDim2.fromScale(1, 1), Color = C.Accent2, MaxTextSize = 14, Parent = powerRow })

	ui.Detail = UIKit.New("Frame", {
		Size = UDim2.fromScale(1, 0.22),
		BackgroundColor3 = C.PanelLight,
		LayoutOrder = 3,
		Parent = right,
	}, { UIKit.Corner(8), UIKit.Padding(6) })
	ui.DetailStroke = UIKit.Stroke(C.SubText, 2, 0.2)
	ui.DetailStroke.Parent = ui.Detail
	ui.DetailName = UIKit.Label({ Size = UDim2.fromScale(1, 0.2), Font = UIKit.FontHeavy, MaxTextSize = 18, Parent = ui.Detail })
	ui.DetailMeta = UIKit.Label({ Position = UDim2.fromScale(0, 0.2), Size = UDim2.fromScale(1, 0.15), TextColor3 = C.SubText, MaxTextSize = 13, Parent = ui.Detail })
	ui.DetailDesc = UIKit.Label({ Position = UDim2.fromScale(0, 0.37), Size = UDim2.fromScale(1, 0.3), Font = UIKit.FontBody, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 13, Parent = ui.Detail })
	ui.DetailStats = UIKit.Label({ Position = UDim2.fromScale(0, 0.68), Size = UDim2.fromScale(1, 0.32), TextColor3 = C.Accent2, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 13, Parent = ui.Detail })

	local fit = UIKit.New("Frame", {
		Size = UDim2.fromScale(1, 0.2),
		BackgroundColor3 = C.PanelLight,
		LayoutOrder = 4,
		Parent = right,
	}, { UIKit.Corner(8), UIKit.Padding(6), UIKit.List(3) })
	ui.FitTitle = UIKit.Label({ Size = UDim2.new(1, 0, 0.22, -3), TextColor3 = C.SubText, MaxTextSize = 13, LayoutOrder = 0, Parent = fit })
	ui.FitValues = {}
	local fitRows = {
		{ Key = "Scale", Label = "Size", Step = Config.Builds.ScaleStep },
		{ Key = "Yaw", Label = "Turn", Step = Config.Builds.RotateStep },
		{ Key = "Pitch", Label = "Tilt", Step = Config.Builds.RotateStep },
	}
	for order, row in fitRows do
		local rowFrame = UIKit.New("Frame", { Size = UDim2.new(1, 0, 0.26, -3), BackgroundTransparency = 1, LayoutOrder = order, Parent = fit })
		UIKit.Label({ Text = row.Label, Size = UDim2.fromScale(0.3, 1), Font = UIKit.FontBody, MaxTextSize = 14, Parent = rowFrame })
		UIKit.Button({ Text = "−", Position = UDim2.fromScale(0.3, 0), Size = UDim2.fromScale(0.18, 1), Parent = rowFrame }, function()
			self:Adjust(row.Key, -row.Step)
		end)
		ui.FitValues[row.Key] = UIKit.Label({ Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.28, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 14, Parent = rowFrame })
		UIKit.Button({ Text = "+", Position = UDim2.fromScale(0.8, 0), Size = UDim2.fromScale(0.18, 1), Parent = rowFrame }, function()
			self:Adjust(row.Key, row.Step)
		end)
	end

	ui.Message = UIKit.Label({ Size = UDim2.fromScale(1, 0.06), Font = UIKit.FontBody, MaxTextSize = 14, LayoutOrder = 5, Parent = right })

	local actions = UIKit.New("Frame", { Size = UDim2.fromScale(1, 0.13), BackgroundTransparency = 1, LayoutOrder = 6, Parent = right })
	UIKit.Button({ Text = "UNDO", Size = UDim2.new(0.32, -3, 0.47, 0), Parent = actions }, function()
		self:Undo()
	end)
	UIKit.Button({ Text = "RESET", Position = UDim2.fromScale(0.34, 0), Size = UDim2.new(0.32, -3, 0.47, 0), Parent = actions }, function()
		self:ResetToSaved()
	end)
	UIKit.Button({ Text = "RESET FIT", Position = UDim2.fromScale(0.68, 0), Size = UDim2.new(0.32, 0, 0.47, 0), MaxTextSize = 14, Parent = actions }, function()
		self:ResetFit()
	end)
	ui.SaveButton = UIKit.Button({ Text = "SAVE", Position = UDim2.fromScale(0, 0.53), Size = UDim2.new(0.5, -3, 0.47, 0), BackgroundColor3 = C.Good, TextColor3 = C.Background, Parent = actions }, function()
		self:Save()
	end)
	ui.ActiveButton = UIKit.Button({ Text = "SET ACTIVE", Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.new(0.5, 0, 0.47, 0), BackgroundColor3 = C.Accent, MaxTextSize = 15, Parent = actions }, function()
		self:SetActive()
	end)

	self:ConnectViewportInput()
end

------------------------------------------------------------------------------------------
-- Viewport camera
------------------------------------------------------------------------------------------
function WorkshopController:ConnectViewportInput()
	local viewport = ui.Viewport
	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			state.dragging = true
			state.lastPointer = input.Position
			state.lastInteraction = os.clock()
		end
	end)
	viewport.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			state.zoom = math.clamp(state.zoom - input.Position.Z * 0.1, 0.55, 1.8)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not state.open then
			return
		end
		if state.dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - state.lastPointer
			state.lastPointer = input.Position
			state.yaw -= delta.X * 0.01
			state.pitch = math.clamp(state.pitch + delta.Y * 0.008, -0.2, 1.2)
			state.lastInteraction = os.clock()
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			state.stick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			state.dragging = false
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not state.open then
			return
		end
		if state.stick.Magnitude > 0.15 then
			state.yaw -= state.stick.X * dt * 2.5
			state.pitch = math.clamp(state.pitch + state.stick.Y * dt * 1.5, -0.2, 1.2)
			state.lastInteraction = os.clock()
		elseif not state.dragging and os.clock() - state.lastInteraction > 3 then
			state.yaw += dt * 0.35 -- slow showcase spin when idle
		end
		local distance = state.fitDistance * state.zoom
		local direction = Vector3.new(math.sin(state.yaw) * math.cos(state.pitch), math.sin(state.pitch), -math.cos(state.yaw) * math.cos(state.pitch))
		ui.Camera.CFrame = CFrame.lookAt(state.focus + direction * distance, state.focus)
	end)
end

------------------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------------------
function WorkshopController:RefreshPreview()
	if ui.PreviewModel then
		ui.PreviewModel:Destroy()
		ui.PreviewModel = nil
	end
	local ok, model, info = pcall(NightmareAssembler.Build, state.draft, { Preview = true })
	if not ok then
		ui.ArchetypeLabel.Text = "Preview unavailable: " .. tostring(model)
		return
	end
	model.Parent = ui.WorldModel
	ui.PreviewModel = model

	-- Ground level relative to the hitbox centre (accounts for floating hover height).
	local floorY = -(info.HitboxSize.Y / 2) - info.HipHeight
	ui.Pedestal.CFrame = CFrame.new(0, floorY - 0.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	ui.PedestalRing.CFrame = CFrame.new(0, floorY - 0.3, 0) * CFrame.Angles(0, 0, math.rad(90))

	local boxCFrame, boxSize = model:GetBoundingBox()
	state.focus = boxCFrame.Position
	state.fitDistance = math.max(boxSize.X, boxSize.Y, boxSize.Z) * 1.9 + 4

	local socket = info.SlotRoots[state.selectedSlot]
	if socket then
		ui.SocketMarker.Transparency = 0.2
		ui.SocketMarker.CFrame = socket.CFrame
	else
		-- Empty optional slot: show where it would attach.
		local core = PartDefinitions.Get(state.draft.Parts.Core)
		local socketPos = core and core.Sockets[state.selectedSlot]
		if socketPos then
			local coreScale = (state.draft.Adjust.Core and state.draft.Adjust.Core.Scale) or 1
			ui.SocketMarker.Transparency = 0.5
			ui.SocketMarker.CFrame = info.SlotRoots.Core.CFrame * CFrame.new(socketPos * coreScale)
		end
	end

	local abilities = AbilityDefinitions.ForBuild(state.draft, PartDefinitions)
	local function abilityName(id)
		local def = AbilityDefinitions.Get(id)
		return def and def.DisplayName or "—"
	end
	local ultimate = AbilityDefinitions.GetUltimate(AbilityDefinitions.UltimateForBuild(state.draft, PartDefinitions))
	ui.ArchetypeLabel.Text = ("%s  ·  Q: %s  ·  E: %s  ·  G: %s"):format(string.upper(info.Archetype), abilityName(abilities[1]), abilityName(abilities[2]), ultimate and ultimate.DisplayName or "—")
end

function WorkshopController:RefreshStats()
	local p = profile()
	local stats = StatCalculator.Compute(state.draft)
	local savedStats = StatCalculator.Compute(state.saved)

	for key, label in ui.StatRows do
		local value, before = stats[key], savedStats[key]
		local diff = value - before
		local text = tostring(math.floor(value + 0.5))
		if math.abs(diff) >= 0.5 then
			local color = diff > 0 and C.Good or C.Bad
			text = ('<font color="#%s">(%s%d %s)</font>  %s'):format(color:ToHex(), diff > 0 and "+" or "−", math.abs(diff), diff > 0 and "▲" or "▼", text)
		end
		label.Text = text
	end

	local budget = p.PowerBudget
	UIKit.SetBar(ui.PowerBar, stats.PowerCost, budget)
	ui.PowerBar.Label.Text = ("POWER COST  %d / %d"):format(stats.PowerCost, budget)
	ui.PowerBar.Fill.BackgroundColor3 = stats.PowerCost > budget and C.Bad or C.Accent2
end

function WorkshopController:RefreshSlots()
	for _, slot in SlotDefinitions.Order do
		local entry = ui.SlotButtons[slot]
		local def = PartDefinitions.Get(state.draft.Parts[slot])
		local info = SlotDefinitions.Info[slot]
		local partText
		if def then
			local mutation = MutationDefinitions.Get(MutationDefinitions.ForSlot(state.draft, slot))
			local prefix = mutation and ('<font color="#%s">%s </font>'):format(mutation.Color:ToHex(), mutation.DisplayName) or ""
			partText = ('%s<font color="#%s">%s</font>'):format(prefix, rarityColor(def):ToHex(), def.DisplayName)
		else
			partText = info.Required and '<font color="#F05555">REQUIRED</font>' or '<font color="#8A84A0">empty</font>'
		end
		entry.Button.Text = ("%s:  %s"):format(info.DisplayName, partText)
		local selected = slot == state.selectedSlot
		entry.Stroke.Transparency = selected and 0 or 1
		entry.Button.BackgroundColor3 = selected and C.PanelLighter or C.PanelLight
	end
end

function WorkshopController:RefreshPartList()
	for _, child in ui.PartList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local p = profile()
	local slot = state.selectedSlot
	local info = SlotDefinitions.Info[slot]
	ui.PartsTitle.Text = ("PARTS FOR %s"):format(string.upper(info.DisplayName))

	local list = PartDefinitions.ForPartSlot(info.PartSlot)
	table.sort(list, function(a, b)
		local ra, rb = RarityDefinitions.Info[a.Rarity].Rank, RarityDefinitions.Info[b.Rarity].Rank
		if ra ~= rb then
			return ra < rb
		end
		return a.DisplayName < b.DisplayName
	end)

	local equippedId = state.draft.Parts[slot]
	local equippedMutation = MutationDefinitions.ForSlot(state.draft, slot)
	local order = 0

	-- One entry per plain part, plus one per mutation you own of it.
	local function addEntry(def, mutationId: string?, owned: number?)
		order += 1
		local mutation = MutationDefinitions.Get(mutationId)
		local selected = (def and def.Id) == equippedId and mutationId == equippedMutation
		local color = def and rarityColor(def) or C.SubText
		local accent = mutation and mutation.Color or color
		local button = UIKit.Button({
			Size = UDim2.new(1, -8, 0, 54),
			LayoutOrder = order,
			BackgroundColor3 = selected and C.PanelLighter or C.PanelLight,
			Parent = ui.PartList,
		}, function()
			self:EquipPart(def and def.Id or nil, mutationId)
		end)
		UIKit.Stroke(accent, selected and 3 or 1, selected and 0 or 0.6).Parent = button
		UIKit.New("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = accent, BorderSizePixel = 0, Parent = button }, { UIKit.Corner(3) })
		UIKit.Label({
			Text = def and (mutation and ('<font color="#%s">★ %s</font> %s'):format(mutation.Color:ToHex(), mutation.DisplayName, def.DisplayName) or def.DisplayName) or "None (remove part)",
			RichText = true,
			Position = UDim2.fromOffset(14, 4),
			Size = UDim2.new(1, -20, 0.5, -2),
			TextColor3 = color,
			MaxTextSize = 16,
			Parent = button,
		})
		local meta
		if def then
			local power = def.PowerCost + (mutation and mutation.PowerCost or 0)
			meta = ("%s%s · Power %d · Owned ×%d%s"):format(RarityDefinitions.Info[def.Rarity].DisplayName, mutation and " MUTATION" or "", power, owned or 0, selected and " · EQUIPPED" or "")
		else
			meta = selected and "EQUIPPED (slot empty)" or "Optional slot"
		end
		UIKit.Label({
			Text = meta,
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.new(1, -20, 0.5, -4),
			TextColor3 = C.SubText,
			Font = UIKit.FontBody,
			MaxTextSize = 13,
			Parent = button,
		})
	end

	if not info.Required then
		addEntry(nil)
	end
	local ownedAny = false
	for _, def in list do
		local owned = p.Inventory[def.Id] or 0
		if owned > 0 then
			ownedAny = true
			-- Plain entry: shown if you have a plain copy (or it's what's equipped now).
			local plain = owned - MutationDefinitions.MutatedCount(p, def.Id)
			if plain > 0 or (equippedId == def.Id and not equippedMutation) then
				addEntry(def, nil, plain)
			end
			for _, mutationId in MutationDefinitions.Order do
				local count = p.Mutations and p.Mutations[def.Id] and p.Mutations[def.Id][mutationId] or 0
				if count > 0 then
					addEntry(def, mutationId, count)
				end
			end
		end
	end
	if not ownedAny then
		UIKit.Label({ Text = "You don't own any parts for this slot yet. Defeat bosses to find some!", Size = UDim2.new(1, -8, 0, 50), TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 14, LayoutOrder = 999, Parent = ui.PartList })
	end
end

function WorkshopController:RefreshDetail()
	local slot = state.selectedSlot
	local def = PartDefinitions.Get(state.draft.Parts[slot])
	if not def then
		ui.DetailName.Text = "Nothing equipped"
		ui.DetailName.TextColor3 = C.SubText
		ui.DetailMeta.Text = SlotDefinitions.Info[slot].DisplayName
		ui.DetailDesc.Text = SlotDefinitions.Info[slot].Required and "This slot is required." or "Optional slot — leaving it empty saves Power Cost."
		ui.DetailStats.Text = ""
		ui.DetailStroke.Color = C.SubText
		return
	end
	local color = rarityColor(def)
	ui.DetailName.Text = def.DisplayName
	ui.DetailName.TextColor3 = color
	ui.DetailStroke.Color = color
	local movement = def.Movement and (" · " .. def.Movement .. " movement") or ""
	ui.DetailMeta.Text = ("%s · Power %d · Source: %s%s"):format(RarityDefinitions.Info[def.Rarity].DisplayName, def.PowerCost, def.Source, movement)
	ui.DetailDesc.Text = def.Description
	local ability = AbilityDefinitions.Get(def.AbilityId)
	local abilityText = ability and ("Ability: %s — %s (%ds cooldown)"):format(ability.DisplayName, ability.Description, ability.Cooldown) or ("Passive: " .. def.PlannedAbility)
	local ultimate = AbilityDefinitions.GetUltimate(def.UltimateId)
	if ultimate then
		abilityText ..= ("\nUltimate: %s"):format(ultimate.DisplayName)
	end
	if def.OnHit then
		abilityText ..= ("\nOn hit: %s%s"):format(def.OnHit.Status, def.OnHit.ComboHit and " (combo finisher)" or "")
	end
	local mutation = MutationDefinitions.Get(MutationDefinitions.ForSlot(state.draft, slot))
	if mutation then
		ui.DetailName.Text = MutationDefinitions.FullName(def.DisplayName, MutationDefinitions.ForSlot(state.draft, slot))
		abilityText ..= ("\n★ %s MUTATION: %s (%s, +%d Power)"):format(string.upper(mutation.DisplayName), mutation.Description, statLine(mutation.Stats), mutation.PowerCost)
	end
	ui.DetailStats.Text = ("%s\n%s"):format(statLine(def.Stats), abilityText)
end

function WorkshopController:RefreshFit()
	local slot = state.selectedSlot
	local adjust = ensureAdjust(slot)
	local hasPart = state.draft.Parts[slot] ~= nil
	ui.FitTitle.Text = hasPart and ("FIT: %s"):format(string.upper(SlotDefinitions.Info[slot].DisplayName)) or "FIT: (equip a part first)"
	ui.FitValues.Scale.Text = ("%d%%"):format(math.floor(adjust.Scale * 100 + 0.5))
	ui.FitValues.Yaw.Text = ("%d°"):format(adjust.Yaw)
	ui.FitValues.Pitch.Text = ("%d°"):format(adjust.Pitch)
end

function WorkshopController:RefreshHeader()
	local p = profile()
	local slots = #p.Builds
	local more = slots < Config.Builds.MaxSlotCount
	local shown = slots + (more and 1 or 0)
	local width = 0.61 / shown
	for index, tab in ui.BuildTabs do
		local build = p.Builds[index]
		tab.Visible = build ~= nil
		tab.Position = UDim2.fromScale(0.27 + (index - 1) * width, 0.1)
		tab.Size = UDim2.fromScale(width - 0.01, 0.8)
		local marker = index == p.ActiveBuild and "★ " or ""
		tab.Text = ("%s%d · %s"):format(marker, index, build and build.Name or "?")
		tab.BackgroundColor3 = index == state.buildIndex and C.Accent or C.PanelLight
	end
	ui.MoreSlotsTab.Visible = more
	ui.MoreSlotsTab.Position = UDim2.fromScale(0.27 + slots * width, 0.1)
	ui.MoreSlotsTab.Size = UDim2.fromScale(width - 0.01, 0.8)
	if not ui.NameBox:IsFocused() then
		ui.NameBox.Text = state.draft.Name
	end

	local valid, err = BuildValidator.Validate(state.draft, p.Inventory, p.PowerBudget, p.Mutations)
	local dirty = isDirty()
	local canSave = (dirty or isCreateStep()) and valid
	ui.SaveButton.Text = isCreateStep() and "CREATE!" or (dirty and "SAVE" or "SAVED")
	ui.SaveButton.AutoButtonColor = canSave
	ui.SaveButton.BackgroundTransparency = canSave and 0 or 0.6
	ui.ActiveButton.Text = p.ActiveBuild == state.buildIndex and "ACTIVE ★" or "SET ACTIVE"

	if not valid then
		setMessage(err, C.Bad)
	elseif dirty then
		setMessage("● Unsaved changes", C.Warn)
	elseif ui.Message.TextColor3 == C.Bad or ui.Message.TextColor3 == C.Warn then
		setMessage(p.Persistence and "" or "Prototype: builds reset when you leave (saving arrives in Phase 2).", C.SubText)
	end
end

function WorkshopController:RefreshAll()
	if not state.open or not state.draft or not profile() then
		return
	end
	self:RefreshHeader()
	self:RefreshSlots()
	self:RefreshPartList()
	self:RefreshStats()
	self:RefreshDetail()
	self:RefreshFit()
	self:RefreshPreview()
end

------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------
function WorkshopController:IsOpen(): boolean
	return state.open
end

function WorkshopController:Open()
	if state.open then
		return
	end
	local p = profile()
	if not p then
		controllers.HUDController:Toast("Workshop is still loading...", nil, 1.5)
		task.spawn(function()
			controllers.ClientState:Refresh()
		end)
		return
	end
	state.open = true
	ui.Screen.Enabled = true
	state.lastInteraction = os.clock()
	self:LoadBuild(p.ActiveBuild)
	setMessage(p.Persistence and "" or "Prototype: builds reset when you leave (saving arrives in Phase 2).", C.SubText)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.FirstButton
	end
end

-- Opens the workshop on the active build with the right slot selected for a part
-- (used by the reward screen's EQUIP NOW button).
function WorkshopController:OpenToPart(partId: string, mutationId: string?)
	local def = PartDefinitions.Get(partId)
	self:Open()
	if not state.open or not def then
		return
	end
	for _, slot in SlotDefinitions.Order do
		local info = SlotDefinitions.Info[slot]
		if info.PartSlot == def.Slot and (def.Slot ~= "Arm" or slot == "RightArm") then
			state.selectedSlot = slot
			break
		end
	end
	self:RefreshAll()
	setMessage(("Tap %s in the list to equip it, then SAVE."):format(MutationDefinitions.FullName(def.DisplayName, mutationId)), C.Warn)
end

function WorkshopController:Close()
	if not state.open then
		return
	end
	state.open = false
	state.dragging = false
	ui.Screen.Enabled = false
	if ui.PreviewModel then
		ui.PreviewModel:Destroy()
		ui.PreviewModel = nil
	end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Screen) then
		GuiService.SelectedObject = nil
	end
end

function WorkshopController:Toggle()
	if state.open then
		self:Close()
	else
		self:Open()
	end
end

function WorkshopController:Init(registry)
	controllers = registry
end

function WorkshopController:Start()
	self:BuildGui()

	-- A new snapshot arrived (save, inventory grant, ...): keep the draft, refresh views.
	controllers.ClientState.Changed:Connect(function()
		if state.open and state.draft then
			local p = profile()
			if not isDirty() and p.Builds[state.buildIndex] then
				state.saved = Util.DeepCopy(p.Builds[state.buildIndex])
				state.draft = Util.DeepCopy(state.saved)
			end
			self:RefreshAll()
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "OpenWorkshop" then
			self:Open()
		end
	end)
end

return WorkshopController
