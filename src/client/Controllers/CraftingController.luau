--[[
	CraftingController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/CraftingController

	The Crafting Forge panel (Phase 5), opened from the anvil's "OpenForge" prompt in the
	middle of the hub.
	  CRAFT tab      every recipe with level / Essence / coin / part costs (green = have,
	                 red = missing) and a CRAFT button
	  DISMANTLE tab  every owned part with spare copies -> Essence. Epic and Legendary
	                 parts need a second click to confirm.
	The server (CraftingService) decides everything; rules are shared via
	Shared/CraftingDefinitions so what's shown here is what's enforced.
]]

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local RarityDefinitions = require(Shared:WaitForChild("RarityDefinitions"))
local CraftingDefinitions = require(Shared:WaitForChild("CraftingDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local CraftingController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local FORGE_ORANGE = Color3.fromRGB(255, 150, 60)
local controllers
local ui = {}
local tab = "Craft"
local craftRequest: RemoteFunction
local busy = false
local confirmPending: string? = nil -- part id awaiting a second DISMANTLE click

function CraftingController:Init(registry)
	controllers = registry
	craftRequest = Net.Get("CraftRequest")
end

function CraftingController:IsOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

local function hex(color: Color3): string
	return color:ToHex()
end

local function colored(text: string, ok: boolean): string
	return ('<font color="#%s">%s</font>'):format(hex(ok and C.Good or C.Bad), text)
end

function CraftingController:SetMessage(text: string, color: Color3?)
	ui.Message.Text = text
	ui.Message.TextColor3 = color or C.SubText
end

function CraftingController:Request(action: string, ...)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(craftRequest.InvokeServer, craftRequest, action, ...)
	busy = false
	if not ok or type(result) ~= "table" then
		result = { Ok = false, Error = "Could not reach the server." }
	end
	if result.Ok and result.State then
		controllers.ClientState:SetProfile(result.State) -- also refreshes this panel
	end
	return result
end

------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------
function CraftingController:Open()
	if controllers.BossController:IsInFight() or controllers.PvPController:IsInMatch() then
		return
	end
	if not controllers.ClientState.Profile then
		return
	end
	confirmPending = nil
	self:SetMessage(CraftingDefinitions.IsFree() and "Studio test: crafting is FREE (Config.Dev.FreeCraftingInStudio)." or "", C.Warn)
	ui.Panel.Visible = true
	self:Refresh()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.CraftTab
	end
end

function CraftingController:Close()
	ui.Panel.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Panel) then
		GuiService.SelectedObject = nil
	end
end

------------------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------------------
local function clearList()
	for _, child in ui.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function partTitle(def): string
	local rarity = RarityDefinitions.Info[def.Rarity]
	return ('<font color="#%s">%s</font>'):format(hex(rarity.Color), def.DisplayName)
end

function CraftingController:CraftRow(partId: string, order: number, profile)
	local def = PartDefinitions.Get(partId)
	local recipe = CraftingDefinitions.Get(partId)
	if not def or not recipe then
		return
	end
	local free = CraftingDefinitions.IsFree()
	local canCraft, reason = CraftingDefinitions.CanCraft(profile, partId)

	local row = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 96), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = ui.List }, { UIKit.Corner(8), UIKit.Padding(8) })
	UIKit.Label({
		Text = ("%s   <font color=\"#%s\">%s · %s · owned %d</font>"):format(partTitle(def), hex(C.SubText), RarityDefinitions.Info[def.Rarity].DisplayName, def.Slot, profile.Inventory[partId] or 0),
		RichText = true,
		Size = UDim2.new(0.74, 0, 0, 22),
		MaxTextSize = 17,
		Parent = row,
	})
	UIKit.Label({ Text = def.Description, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(0.74, 0, 0, 18), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 13, Parent = row })

	-- Costs, each green (have) or red (missing).
	local costs = {
		colored(("Lv %d"):format(recipe.Level), free or (profile.Level or 1) >= recipe.Level),
		colored(("%d Essence"):format(recipe.Essence), free or (profile.Essence or 0) >= recipe.Essence),
		colored(("%d Coins"):format(recipe.Coins), free or (profile.Coins or 0) >= recipe.Coins),
	}
	local ingredientIds = {} -- sorted so the cost line doesn't shuffle between refreshes

	for ingredient in recipe.Ingredients do
		table.insert(ingredientIds, ingredient)
	end
	table.sort(ingredientIds)
	for _, ingredient in ingredientIds do
		local count = recipe.Ingredients[ingredient]
		local ingredientDef = PartDefinitions.Get(ingredient)
		local spare = CraftingDefinitions.SpareCount(profile, ingredient)
		table.insert(costs, colored(("%d× %s (%d spare)"):format(count, ingredientDef and ingredientDef.DisplayName or ingredient, spare), free or spare >= count))
	end
	UIKit.Label({ Text = table.concat(costs, "  ·  "), RichText = true, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(0.74, 0, 0, 34), Font = UIKit.FontBody, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 14, Parent = row })

	UIKit.Button({
		Text = free and "CRAFT (FREE)" or "CRAFT",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.23, 0, 0, 44),
		BackgroundColor3 = canCraft and FORGE_ORANGE or C.PanelLighter,
		TextColor3 = canCraft and C.Background or C.SubText,
		Parent = row,
	}, function()
		if not canCraft then
			self:SetMessage(reason or "You can't craft this yet.", C.Bad)
			return
		end
		self:SetMessage("Forging...", C.SubText)
		local result = self:Request("Craft", partId)
		if not result then
			return
		end
		if result.Ok then
			controllers.AudioController:Play("Craft")
			self:SetMessage(("Crafted %s!%s Equip it in the Workshop (B)."):format(def.DisplayName, result.Crafted and result.Crafted.IsNew and " NEW PART!" or ""), C.Good)
		else
			self:SetMessage(result.Error or "Couldn't craft.", C.Bad)
		end
	end)
end

function CraftingController:DismantleRow(partId: string, order: number, profile, spare: number)
	local def = PartDefinitions.Get(partId)
	local value = CraftingDefinitions.DismantleValue[def.Rarity] or 0
	local needsConfirm = def.Rarity == "Epic" or def.Rarity == "Legendary"

	local row = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 54), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = ui.List }, { UIKit.Corner(8), UIKit.Padding(8) })
	UIKit.Label({ Text = partTitle(def), RichText = true, Size = UDim2.new(0.5, 0, 0, 20), MaxTextSize = 16, Parent = row })
	UIKit.Label({
		Text = ("Owned %d · %d spare · +%d Essence each"):format(profile.Inventory[partId] or 0, spare, value),
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(0.5, 0, 0, 18),
		Font = UIKit.FontBody,
		TextColor3 = C.SubText,
		MaxTextSize = 13,
		Parent = row,
	})

	local function dismantle(count: number)
		local key = partId .. ":" .. count
		if needsConfirm and confirmPending ~= key then
			confirmPending = key
			self:SetMessage(("Click again to dismantle %d× %s for %d Essence."):format(count, def.DisplayName, value * count), C.Warn)
			return
		end
		confirmPending = nil
		local result = self:Request("Dismantle", partId, count)
		if not result then
			return
		end
		if result.Ok then
			self:SetMessage(("Dismantled %d× %s: +%d Essence."):format(count, def.DisplayName, result.Essence or 0), C.Good)
		else
			self:SetMessage(result.Error or "Couldn't dismantle.", C.Bad)
		end
	end

	UIKit.Button({ Text = "DISMANTLE 1", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(spare > 1 and 0.75 or 1, spare > 1 and -6 or 0, 0.5, 0), Size = UDim2.new(0.22, 0, 0, 36), BackgroundColor3 = C.PanelLighter, MaxTextSize = 14, Parent = row }, function()
		dismantle(1)
	end)
	if spare > 1 then
		UIKit.Button({ Text = ("ALL %d SPARE"):format(spare), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0.22, 0, 0, 36), BackgroundColor3 = C.PanelLighter, MaxTextSize = 14, Parent = row }, function()
			dismantle(math.min(spare, 50))
		end)
	end
end

------------------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------------------
function CraftingController:Refresh()
	local profile = controllers.ClientState.Profile
	if not profile or not ui.Panel.Visible then
		return
	end
	ui.Currency.Text = ("Level %d   ·   %d Essence   ·   %d Coins"):format(profile.Level or 1, profile.Essence or 0, profile.Coins or 0)
	ui.CraftTab.BackgroundColor3 = tab == "Craft" and FORGE_ORANGE or C.PanelLighter
	ui.CraftTab.TextColor3 = tab == "Craft" and C.Background or C.Text
	ui.DismantleTab.BackgroundColor3 = tab == "Dismantle" and FORGE_ORANGE or C.PanelLighter
	ui.DismantleTab.TextColor3 = tab == "Dismantle" and C.Background or C.Text

	clearList()
	if tab == "Craft" then
		for order, partId in CraftingDefinitions.Order do
			self:CraftRow(partId, order, profile)
		end
		return
	end

	-- Dismantle: spare copies only, best rarity first, then by name.
	local entries = {}
	for partId in profile.Inventory do
		local def = PartDefinitions.Get(partId)
		local spare = def and CraftingDefinitions.SpareCount(profile, partId) or 0
		if spare > 0 then
			table.insert(entries, { Id = partId, Def = def, Spare = spare })
		end
	end
	table.sort(entries, function(a, b)
		local ra, rb = RarityDefinitions.Info[a.Def.Rarity].Rank, RarityDefinitions.Info[b.Def.Rarity].Rank
		if ra ~= rb then
			return ra > rb
		end
		return a.Def.DisplayName < b.Def.DisplayName
	end)
	if #entries == 0 then
		UIKit.Label({
			Text = "No spare parts. Duplicates from boss fights show up here: dismantle them into Essence. Your last copy of a part, and copies used in your saved builds, are always kept.",
			Size = UDim2.new(1, -8, 0, 60),
			Font = UIKit.FontBody,
			TextColor3 = C.SubText,
			MaxTextSize = 14,
			Parent = ui.List,
		})
	end
	for order, entry in entries do
		self:DismantleRow(entry.Id, order, profile, entry.Spare)
	end
end

------------------------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------------------------
function CraftingController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "CraftingGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 16, Parent = localPlayer:WaitForChild("PlayerGui") })

	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.8),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(FORGE_ORANGE, 2, 0.1), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(900, 660), Parent = panel })
	UIKit.Responsive(panel) -- near full screen on phones
	ui.Panel = panel

	UIKit.Label({ Text = "⚒ THE CRAFTING FORGE", Size = UDim2.fromScale(0.85, 0.08), Font = UIKit.FontHeavy, TextColor3 = FORGE_ORANGE, MaxTextSize = 30, Parent = panel })
	UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.08, 0.08), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		self:Close()
	end)
	ui.Currency = UIKit.Label({ Position = UDim2.fromScale(0, 0.09), Size = UDim2.fromScale(1, 0.05), TextColor3 = C.Warn, MaxTextSize = 16, Parent = panel })

	ui.CraftTab = UIKit.Button({ Text = "CRAFT", Position = UDim2.fromScale(0, 0.155), Size = UDim2.fromScale(0.25, 0.065), MaxTextSize = 16, Parent = panel }, function()
		tab = "Craft"
		confirmPending = nil
		self:Refresh()
	end)
	ui.DismantleTab = UIKit.Button({ Text = "DISMANTLE", Position = UDim2.new(0.25, 8, 0.155, 0), Size = UDim2.fromScale(0.25, 0.065), MaxTextSize = 16, Parent = panel }, function()
		tab = "Dismantle"
		confirmPending = nil
		self:Refresh()
	end)

	ui.List = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromScale(0, 0.24),
		Size = UDim2.fromScale(1, 0.68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, { UIKit.List(6) })

	ui.Message = UIKit.Label({ Position = UDim2.fromScale(0, 0.93), Size = UDim2.fromScale(1, 0.07), Font = UIKit.FontBody, MaxTextSize = 14, Parent = panel })
end

function CraftingController:Start()
	self:BuildGui()

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "OpenForge" then
			self:Open()
		end
	end)
	controllers.ClientState.Changed:Connect(function()
		self:Refresh()
	end)
end

return CraftingController
