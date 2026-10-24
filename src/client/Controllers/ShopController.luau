--[[
	ShopController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController

	THE SHOP: every game pass and developer product (Shared/MonetizationDefinitions), in
	tabs (Featured · Exclusive · Gym · Perks · Currency). Buying opens Roblox's own purchase
	prompt; MonetizationService grants it and this shows the thank-you card.
	  Open it: the SHOP button (top bar), the MENU hub's SHOP tile, N on a keyboard, or the
	  gym panel's "MORE LUCK & SPEED" button.

	  * Prices are Roblox's live prices (GetProductInfo); Price in the definitions is only
	    shown until that arrives.
	  * Passes you own show OWNED. Luck items are hidden where Roblox restricts paid random
	    items (the server decides: profile.Shop.Restricted).
	  * Entries not created on the dashboard yet (Id = 0) are hidden on live servers; in
	    Studio they're TEST BUY (free, through MonetizationService:DevBuy).
	Also here: the SERVER LUCK banner (top centre, while one runs) and the NIGHT SHIFT
	"while you were away" card.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Monetization = require(Shared:WaitForChild("MonetizationDefinitions"))
local GymDefinitions = require(Shared:WaitForChild("GymDefinitions"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))

local ShopController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local IS_STUDIO = RunService:IsStudio()
local GOLD = Color3.fromRGB(255, 196, 60)

local controllers
local request
local ui = {}
local tab = "Featured"
local livePrice = {} -- [Kind..Id] = Robux (Roblox's real price)

function ShopController:Init(registry)
	controllers = registry
end

local function shopState()
	local profile = controllers.ClientState.Profile
	return profile and profile.Shop or {}
end

local function owns(key: string): boolean
	local passes = shopState().Passes
	return passes ~= nil and passes[key] == true
end

-- Should this entry be on sale for me?
local function listed(def): boolean
	if def.Id == 0 and not IS_STUDIO then
		return false -- not created on the Creator Dashboard yet
	end
	if def.Luck and shopState().Restricted then
		return false -- paid random items restricted where they live
	end
	return true
end

local function priceOf(def): number
	return livePrice[def.Kind .. def.Id] or def.Price
end

-- Fetches Roblox's real prices once (for entries that exist on the dashboard).
local function fetchPrices()
	for _, list in { Monetization.Passes, Monetization.Products } do
		for _, def in list do
			local cacheKey = def.Kind .. def.Id
			if def.Id ~= 0 and livePrice[cacheKey] == nil then
				livePrice[cacheKey] = def.Price
				task.spawn(function()
					local infoType = def.Kind == "Pass" and Enum.InfoType.GamePass or Enum.InfoType.Product
					local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, def.Id, infoType)
					if ok and info and info.PriceInRobux then
						livePrice[cacheKey] = info.PriceInRobux
						if ShopController:IsOpen() then
							ShopController:Render()
						end
					end
				end)
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- Buying
------------------------------------------------------------------------------------------
function ShopController:Buy(def)
	if def.Kind == "Pass" and owns(def.Key) then
		return
	end
	if def.Id ~= 0 then
		if def.Kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(localPlayer, def.Id)
		else
			MarketplaceService:PromptProductPurchase(localPlayer, def.Id)
		end
		return
	end
	if IS_STUDIO then
		local ok, result = pcall(request.InvokeServer, request, "DevBuy", def.Key)
		if not ok or type(result) ~= "table" or not result.Ok then
			controllers.HUDController:Toast(type(result) == "table" and result.Error or "Test purchase failed.", nil, 2)
		end
	end
end

------------------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------------------
function ShopController:IsOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

function ShopController:Close()
	ui.Panel.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Panel) then
		GuiService.SelectedObject = nil
	end
end

-- Asks the server what you own right now. (Your passes are looked up as you join, and
-- that first push can arrive before this client is listening, so the SHOP never trusts
-- it alone: it asks again when it opens.)
local function refreshState(): boolean
	local ok, result = pcall(request.InvokeServer, request, "State")
	local profile = controllers.ClientState.Profile
	if ok and type(result) == "table" and type(result.Summary) == "table" and profile then
		profile.Shop = result.Summary
		return true
	end
	return false
end

function ShopController:Open(which: string?)
	tab = which and table.find(Monetization.Categories, which) and which or tab
	fetchPrices()
	ui.Panel.Visible = true
	self:Render()
	task.spawn(function()
		if refreshState() and self:IsOpen() then
			self:Render()
		end
	end)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.TabButtons[tab]
	end
end

function ShopController:Toggle()
	if self:IsOpen() then
		self:Close()
	else
		self:Open()
	end
end

-- The entries for a tab: Featured = the Featured ones plus anything with a badge.
local function entriesFor(category: string)
	local list = {}
	for _, source in { Monetization.Passes, Monetization.Products } do
		for _, def in source do
			local show = def.Category == category or (category == "Featured" and def.Badge ~= nil and def.Category ~= "Currency")
			if show and listed(def) then
				table.insert(list, def)
			end
		end
	end
	table.sort(list, function(a, b)
		if (a.Category == "Featured") ~= (b.Category == "Featured") then
			return a.Category == "Featured"
		end
		if a.Kind ~= b.Kind then
			return a.Kind == "Pass"
		end
		return a.Price < b.Price
	end)
	return list
end

-- What the card's description says (products list what you get).
local function describe(def): string
	if def.Text then
		return def.Text
	end
	if def.Coins then
		return ("%s coins, straight to your wallet."):format(Util.FormatNumber(def.Coins))
	end
	if def.Essence then
		return ("%d Nightmare Essence for crafting at the Forge."):format(def.Essence)
	end
	return ""
end

local function card(def, order: number)
	local color = def.Color or (def.Category == "Currency" and GOLD) or (def.Category == "Gym" and Color3.fromRGB(110, 230, 150)) or C.Accent
	local frame = UIKit.New("Frame", { BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = ui.Grid }, {
		UIKit.Corner(10),
		UIKit.Stroke(color, 2, 0.25),
		UIKit.Padding(8),
	})
	UIKit.Label({ Text = def.Icon or "★", Size = UDim2.fromOffset(44, 44), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 34, Parent = frame })
	UIKit.Label({ Text = def.Name, Position = UDim2.fromOffset(50, 2), Size = UDim2.new(1, -50, 0, 22), Font = UIKit.FontHeavy, TextColor3 = color, MaxTextSize = 17, Parent = frame })
	local kind = def.Kind == "Pass" and (def.Category == "Exclusive" and "EXCLUSIVE · YOURS FOREVER" or "GAME PASS · FOREVER") or "ITEM"
	UIKit.Label({ Text = kind, Position = UDim2.fromOffset(50, 24), Size = UDim2.new(1, -50, 0, 14), TextColor3 = C.SubText, MaxTextSize = 11, Parent = frame })
	if def.Badge then
		local badge = UIKit.Label({
			Text = def.Badge, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -40), Size = UDim2.fromOffset(86, 18), -- (above the price, clear of the name)
			BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(230, 60, 80), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 12, Parent = frame,
		})
		UIKit.Corner(6).Parent = badge
	end
	UIKit.Label({
		Text = describe(def), Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -112),
		Font = UIKit.FontBody, TextColor3 = C.Text, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 13, Parent = frame,
	})

	local owned = def.Kind == "Pass" and owns(def.Key)
	local text, buttonColor
	if owned then
		text, buttonColor = "OWNED ✓", C.Good
	elseif def.Id == 0 then
		text, buttonColor = ("TEST BUY · R$ %d"):format(def.Price), Color3.fromRGB(110, 80, 170)
	else
		text, buttonColor = ("R$ %s"):format(Util.FormatNumber(priceOf(def))), Color3.fromRGB(40, 170, 90)
	end
	local button = UIKit.Button({
		Text = text, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = buttonColor, AutoButtonColor = not owned, MaxTextSize = 17, Parent = frame,
	}, function()
		if not owned then
			ShopController:Buy(def)
		end
	end)
	return button
end

function ShopController:Render()
	for _, child in ui.Grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for id, button in ui.TabButtons do
		button.BackgroundColor3 = id == tab and GOLD or C.PanelLighter
		button.TextColor3 = id == tab and Color3.fromRGB(30, 24, 10) or C.Text
	end
	local notes = {
		Featured = "The best deals. Everything here is also in its own tab.",
		Exclusive = "Exclusive parts and weapons: their own looks, special attacks and animations. Same power budget as everything else, so they're different, not stronger.",
		Gym = "Make AFK training luckier and faster. Odds are always shown in full in the gym.",
		Perks = "Permanent upgrades for your account.",
		Currency = "Coins and Essence. 2x Coins / VIP only boost coins you EARN.",
	}
	ui.Note.Text = notes[tab] or ""
	local first
	for order, def in entriesFor(tab) do
		local button = card(def, order)
		first = first or button
	end
	if IS_STUDIO then
		ui.Note.Text ..= "  (Studio: items without an id are free TEST BUYs.)"
	end
	ui.FirstCard = first
end

function ShopController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "ShopGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 26, Parent = localPlayer:WaitForChild("PlayerGui") })
	ui.Gui = gui
	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.78),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(GOLD, 2, 0.2), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(980, 640), Parent = panel })
	UIKit.Responsive(panel)
	ui.Panel = panel

	local title = UIKit.Label({ Text = "🛒 SHOP", Size = UDim2.new(0.5, 0, 0, 34), Font = UIKit.FontHeavy, TextColor3 = GOLD, MaxTextSize = 30, Parent = panel })
	-- keep the title clear of Roblox's top-bar buttons (phones: the panel runs under them)
	local function fitTitle()
		local inset = GuiService.TopbarInset
		local covered = title.AbsolutePosition.Y < inset.Max.Y
		local pad = covered and math.max(0, inset.Min.X - panel.AbsolutePosition.X) or 0
		title.Position = UDim2.fromOffset(pad, 0)
	end
	fitTitle()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fitTitle)
	panel:GetPropertyChangedSignal("AbsolutePosition"):Connect(fitTitle)
	UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(40, 34), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		self:Close()
	end)

	local tabs = UIKit.New("Frame", { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = panel }, { UIKit.List(6, Enum.FillDirection.Horizontal) })
	ui.TabButtons = {}
	for order, id in Monetization.Categories do
		ui.TabButtons[id] = UIKit.Button({ Text = id:upper(), Size = UDim2.new(1 / #Monetization.Categories, -6, 1, 0), LayoutOrder = order, MaxTextSize = 16, Parent = tabs }, function()
			tab = id
			self:Render()
		end)
	end
	ui.Note = UIKit.Label({ Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 32), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 13, Parent = panel })

	local grid = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 122), Size = UDim2.new(1, 0, 1, -122),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	})
	UIKit.New("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 0, 196), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	UIKit.New("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 8), Parent = grid })
	ui.Grid = grid

	-- the thank-you card (after a purchase) and the Night Shift card share this popup
	local popup = UIKit.New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(), BackgroundTransparency = 0.45, Visible = false, ZIndex = 20, Parent = gui })
	local box = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 300),
		BackgroundColor3 = C.Panel, ZIndex = 21, Parent = popup,
	}, { UIKit.Corner(14), UIKit.Stroke(GOLD, 3, 0), UIKit.Padding(16) })
	UIKit.AutoScale(box)
	ui.Popup = popup
	ui.PopupIcon = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 64), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 56, ZIndex = 22, Parent = box })
	ui.PopupTitle = UIKit.Label({ Text = "", Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, TextColor3 = GOLD, MaxTextSize = 28, ZIndex = 22, Parent = box })
	ui.PopupBody = UIKit.Label({ Text = "", Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 1, -158), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Font = UIKit.FontBody, MaxTextSize = 17, ZIndex = 22, Parent = box })
	UIKit.Button({ Text = "AWESOME", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(200, 42), BackgroundColor3 = Color3.fromRGB(40, 170, 90), ZIndex = 22, MaxTextSize = 18, Parent = box }, function()
		popup.Visible = false
	end)

	-- SERVER LUCK banner
	-- (its own low layer: every menu draws over it)
	local bannerGui = UIKit.New("ScreenGui", { Name = "ServerLuckGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 2, Parent = localPlayer:WaitForChild("PlayerGui") })
	ui.Banner = UIKit.Label({
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 116), Size = UDim2.fromOffset(460, 28), -- (under the top bar)
		BackgroundTransparency = 0.2, BackgroundColor3 = Color3.fromRGB(60, 50, 10), TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 16, Visible = false, Parent = bannerGui,
	})
	UIKit.Corner(8).Parent = ui.Banner
	UIKit.AutoScale(ui.Banner)
end

function ShopController:ShowPopup(icon: string, title: string, body: string)
	ui.PopupIcon.Text = icon
	ui.PopupTitle.Text = title
	ui.PopupBody.Text = body
	ui.Popup.Visible = true
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
	if h > 0 then
		return ("%dh %02dm"):format(h, m)
	end
	return ("%d:%02d"):format(m, s)
end

local function onGranted(data)
	local lines = data.Lines or {}
	local body = #lines > 0 and table.concat(lines, "\n") or "It's yours. Enjoy!"
	ShopController:ShowPopup(data.Icon or "🎁", "THANK YOU!", ("%s\n%s"):format(data.Name or "", body))
	if controllers.AudioController then
		controllers.AudioController:Play("RevealLegendary")
	end
	if ShopController:IsOpen() then
		task.delay(0.3, function()
			ShopController:Render()
		end)
	end
end

local function onNightShift(t)
	-- parts grouped ("Electric Jaw x3"), the first few named
	local counts, order = {}, {}
	for _, p in t.Parts or {} do
		if not counts[p.Id] then
			table.insert(order, p.Id)
		end
		counts[p.Id] = (counts[p.Id] or 0) + 1
	end
	local parts = {}
	for i, id in order do
		if i > 5 then
			table.insert(parts, ("+%d more"):format(#order - 5))
			break
		end
		local def = PartDefinitions.Get(id)
		table.insert(parts, ("%s%s"):format(def and def.DisplayName or id, counts[id] > 1 and (" x%d"):format(counts[id]) or ""))
	end
	local best = GymDefinitions.TierOrder[t.Best or 1] or "Common"
	local body = ("Your Nightmare trained for %s while you were away.\n%d rewards · +%s coins · +%d Essence\nBest: %s%s"):format(
		clock(t.Seconds or 0), t.Count or 0, Util.FormatNumber(t.Coins or 0), t.Essence or 0, best:upper(),
		#parts > 0 and ("\n%d parts: %s"):format(#(t.Parts or {}), table.concat(parts, ", ")) or ""
	)
	ShopController:ShowPopup("🌙", "NIGHT SHIFT", body)
end

-- The Server Luck banner (twice a second while one is running).
local function tickBanner()
	local untilAt = Workspace:GetAttribute("ServerLuckUntil") or 0
	local left = untilAt - Workspace:GetServerTimeNow()
	if left > 0 then
		ui.Banner.Text = ("🌟 SERVER LUCK: 2x gym luck for everyone · %s · thanks %s!"):format(clock(left), Workspace:GetAttribute("ServerLuckBy") or "?")
		ui.Banner.Visible = true
	else
		ui.Banner.Visible = false
	end
end

function ShopController:Start()
	request = Net.Get("ShopRequest")
	self:BuildGui()
	Net.Get("ShopEvent").OnClientEvent:Connect(function(kind, data)
		if kind == "Granted" and type(data) == "table" then
			onGranted(data)
		end
	end)
	Net.Get("GymEvent").OnClientEvent:Connect(function(kind, data)
		if kind == "NightShift" and type(data) == "table" then
			onNightShift(data)
		end
	end)
	-- a pass bought elsewhere (or the profile arriving) refreshes the cards
	Net.Get("UIStateUpdate").OnClientEvent:Connect(function(kind)
		if kind == "Profile" and self:IsOpen() then
			task.defer(function()
				self:Render()
			end)
		end
	end)
	task.spawn(function()
		while true do
			tickBanner()
			task.wait(0.5)
		end
	end)
	-- (once your passes have been looked up: the VIP tag, the Workshop's slots... read it)
	task.delay(6, refreshState)

	-- VIP: a gold [VIP] tag and gold name in chat (the server sets the player's "VIP"
	-- attribute while they own the pass)
	local TextChatService = game:GetService("TextChatService")
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		if sender and sender:GetAttribute("VIP") then
			props.PrefixText = ('<font color="#FFC43C">[VIP] %s</font>'):format(message.PrefixText)
		end
		return props
	end
end

return ShopController
