--[[
	PartyController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/PartyController

	PARTIES (Phase 6), client side. Open with L or the PARTY button.
	  Panel     your party (leader ★, KICK for the leader, LEAVE) and everyone else in
	            the server with an INVITE button
	  Pop-up    "X invites you to their party" ACCEPT / DECLINE (expires)
	  HUD       party members' names + Handler health under the status panel
	The server (PartyService) decides everything; this only requests and displays.
]]

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local PartyController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local PARTY_COLOR = Color3.fromRGB(90, 190, 255)
local controllers
local ui = {}
local partyRequest: RemoteFunction
local party = { Members = {}, LeaderUserId = 0 } -- latest state from the server
local incoming = nil

function PartyController:Init(registry)
	controllers = registry
	partyRequest = Net.Get("PartyRequest")
end

function PartyController:Request(action: string, ...)
	local ok, result = pcall(partyRequest.InvokeServer, partyRequest, action, ...)
	if not ok or type(result) ~= "table" then
		return { Ok = false, Error = "Could not reach the server." }
	end
	return result
end

-- Shared with other controllers (e.g. the Boss Portal).
function PartyController:GetSize(): number
	return #party.Members
end

function PartyController:IsInParty(): boolean
	return #party.Members > 0
end

function PartyController:IsLeader(): boolean
	return party.LeaderUserId == localPlayer.UserId
end

function PartyController:IsOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

function PartyController:SetMessage(text: string, color: Color3?)
	ui.Message.Text = text
	ui.Message.TextColor3 = color or C.SubText
end

------------------------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------------------------
function PartyController:Toggle()
	if self:IsOpen() then
		self:Close()
	else
		self:Open()
	end
end

function PartyController:Open()
	ui.Panel.Visible = true
	self:SetMessage("")
	self:RefreshPanel()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.CloseButton
	end
end

function PartyController:Close()
	ui.Panel.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Panel) then
		GuiService.SelectedObject = nil
	end
end

local function isMember(userId: number): boolean
	for _, member in party.Members do
		if member.UserId == userId then
			return true
		end
	end
	return false
end

function PartyController:RefreshPanel()
	if not self:IsOpen() then
		return
	end
	for _, child in ui.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local function heading(text: string)
		UIKit.Label({ Text = text, Size = UDim2.new(1, -8, 0, 24), TextColor3 = C.SubText, MaxTextSize = 14, LayoutOrder = nextOrder(), Parent = ui.List })
	end
	local function row(name: string, nameColor: Color3?, buttonText: string?, buttonColor: Color3?, onClick)
		local frame = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 42), BackgroundColor3 = C.PanelLight, LayoutOrder = nextOrder(), Parent = ui.List }, { UIKit.Corner(8), UIKit.Padding(6) })
		UIKit.Label({ Text = name, Size = UDim2.new(0.62, 0, 1, 0), TextColor3 = nameColor or C.Text, MaxTextSize = 16, Parent = frame })
		if buttonText then
			UIKit.Button({ Text = buttonText, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.34, 1), BackgroundColor3 = buttonColor or C.PanelLighter, MaxTextSize = 14, Parent = frame }, onClick)
		end
	end

	local inParty = #party.Members > 0
	local leader = self:IsLeader()
	local maxSize = party.MaxSize or Config.Party.MaxSize
	ui.Status.Text = inParty
		and ("Party of %d / %d  ·  Boss health ×%.2f  ·  %s"):format(#party.Members, maxSize, Config.Bosses.HealthScaling[math.clamp(#party.Members, 1, #Config.Bosses.HealthScaling)], leader and "You're the leader: start a boss to bring everyone." or "The leader starts boss fights.")
		or ("Not in a party. Invite up to %d friends to fight bosses together."):format(maxSize - 1)
	ui.LeaveButton.Visible = inParty

	if inParty then
		heading("YOUR PARTY")
		for _, member in party.Members do
			local isLeader = member.UserId == party.LeaderUserId
			local isMe = member.UserId == localPlayer.UserId
			local label = ("%s%s%s"):format(isLeader and "★ " or "", member.Name, isMe and " (you)" or "")
			if leader and not isMe then
				row(label, isLeader and C.Warn or C.Text, "KICK", C.PanelLighter, function()
					local result = self:Request("Kick", member.UserId)
					self:SetMessage(result.Ok and "Removed." or (result.Error or "Couldn't kick."), result.Ok and C.SubText or C.Bad)
				end)
			else
				row(label, isLeader and C.Warn or C.Text)
			end
		end
	end

	heading("PLAYERS IN THIS SERVER")
	local others = 0
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and not isMember(player.UserId) then
			others += 1
			local canInvite = (not inParty or leader) and #party.Members < maxSize
			row(player.DisplayName, C.Text, canInvite and "INVITE" or nil, PARTY_COLOR, function()
				self:SetMessage("Sending invite...")
				local result = self:Request("Invite", player.UserId)
				self:SetMessage(result.Ok and ("Invite sent to %s!"):format(player.DisplayName) or (result.Error or "Couldn't invite."), result.Ok and C.Good or C.Bad)
			end)
		end
	end
	if others == 0 then
		local text = inParty and "Everyone in this server is already in your party."
			or "Nobody else is here yet. Test with 2+ players in Studio (Test → Clients and Servers)."
		UIKit.Label({ Text = text, Size = UDim2.new(1, -8, 0, 40), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 14, LayoutOrder = nextOrder(), Parent = ui.List })
	end
end

------------------------------------------------------------------------------------------
-- Invite pop-up
------------------------------------------------------------------------------------------
function PartyController:Answer(accept: boolean)
	local invite = incoming
	incoming = nil
	ui.Popup.Visible = false
	if invite then
		local result = self:Request("Respond", invite.InviteId, accept)
		if not result.Ok and result.Error then
			controllers.HUDController:Toast(result.Error, C.Bad, 3)
		end
	end
end

------------------------------------------------------------------------------------------
-- Party HUD (members' Handler health)
------------------------------------------------------------------------------------------
function PartyController:RefreshHud()
	for _, child in ui.Hud:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	ui.HudBars = {}
	for index, member in party.Members do
		if member.UserId ~= localPlayer.UserId then
			local frame = UIKit.New("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.15, LayoutOrder = index, Parent = ui.Hud }, { UIKit.Corner(6), UIKit.Padding(4) })
			UIKit.Label({ Text = (member.UserId == party.LeaderUserId and "★ " or "") .. member.Name, Size = UDim2.new(1, 0, 0, 12), TextColor3 = PARTY_COLOR, MaxTextSize = 12, Parent = frame })
			local bar = UIKit.Bar({ Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 12), Color = C.HandlerHP, MaxTextSize = 10, Parent = frame })
			ui.HudBars[member.UserId] = bar
		end
	end
	ui.Hud.Visible = next(ui.HudBars) ~= nil
end

------------------------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------------------------
function PartyController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "PartyGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 19, Parent = localPlayer:WaitForChild("PlayerGui") })

	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.45, 0.7),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(PARTY_COLOR, 2, 0.1), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(620, 600), Parent = panel })
	UIKit.Responsive(panel) -- near full screen on phones
	ui.Panel = panel
	UIKit.Label({ Text = "PARTY", Size = UDim2.fromScale(0.8, 0.08), Font = UIKit.FontHeavy, TextColor3 = PARTY_COLOR, MaxTextSize = 30, Parent = panel })
	ui.CloseButton = UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.1, 0.08), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		self:Close()
	end)
	ui.Status = UIKit.Label({ Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(1, 0.08), Font = UIKit.FontBody, TextColor3 = C.Warn, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 14, Parent = panel })
	ui.List = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromScale(0, 0.19),
		Size = UDim2.fromScale(1, 0.62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, { UIKit.List(6) })
	ui.LeaveButton = UIKit.Button({ Text = "LEAVE PARTY", Position = UDim2.fromScale(0, 0.83), Size = UDim2.fromScale(0.35, 0.08), BackgroundColor3 = C.PanelLighter, MaxTextSize = 15, Visible = false, Parent = panel }, function()
		local result = self:Request("Leave")
		self:SetMessage(result.Ok and "You left the party." or (result.Error or "Couldn't leave."), result.Ok and C.SubText or C.Bad)
	end)
	ui.Message = UIKit.Label({ Position = UDim2.fromScale(0, 0.93), Size = UDim2.fromScale(1, 0.07), Font = UIKit.FontBody, MaxTextSize = 14, Parent = panel })

	-- Invite pop-up
	local popup = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 250), Size = UDim2.fromOffset(420, 120), BackgroundColor3 = C.Panel, Visible = false, Parent = gui }, { UIKit.Corner(12), UIKit.Stroke(PARTY_COLOR, 2, 0), UIKit.Padding(10) })
	UIKit.AutoScale(popup)
	ui.Popup = popup
	ui.PopupText = UIKit.Label({ Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, MaxTextSize = 18, Parent = popup })
	ui.AcceptButton = UIKit.Button({ Text = "ACCEPT", Position = UDim2.new(0, 0, 1, -42), Size = UDim2.new(0.48, 0, 0, 42), BackgroundColor3 = C.Good, TextColor3 = C.Background, Parent = popup }, function()
		self:Answer(true)
	end)
	UIKit.Button({ Text = "DECLINE", Position = UDim2.new(0.52, 0, 1, -42), Size = UDim2.new(0.48, 0, 0, 42), BackgroundColor3 = C.PanelLighter, Parent = popup }, function()
		self:Answer(false)
	end)

	-- Party HUD: left side, under the status panel.
	local hud = UIKit.New("Frame", { Position = UDim2.new(0, 12, 0.45, 0), Size = UDim2.fromOffset(190, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false, Parent = gui }, { UIKit.List(4) })
	UIKit.AutoScale(hud)
	ui.Hud = hud
	ui.HudBars = {}
end

function PartyController:Start()
	self:BuildGui()

	Net.Get("PartyEvent").OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" then
			return
		end
		if kind == "State" then
			party = { Members = data.Members or {}, LeaderUserId = data.LeaderUserId or 0, MaxSize = data.MaxSize }
			self:RefreshHud()
			self:RefreshPanel()
		elseif kind == "Incoming" then
			incoming = data
			ui.PopupText.Text = ("%s invites you to their party!"):format(data.FromName or "Someone")
			ui.Popup.Visible = true
			if UserInputService.GamepadEnabled then
				GuiService.SelectedObject = ui.AcceptButton
			end
			local id = data.InviteId
			task.delay(data.Timeout or Config.Party.InviteTimeout, function()
				if incoming and incoming.InviteId == id then
					incoming = nil
					ui.Popup.Visible = false
				end
			end)
		elseif kind == "Result" then
			-- The HUD toast draws under open panels, so mirror it in the panel too.
			if self:IsOpen() then
				self:SetMessage(data.Text or "", C.Warn)
			end
			controllers.HUDController:Toast(data.Text or "", C.Warn, 3)
		end
	end)

	Players.PlayerAdded:Connect(function()
		self:RefreshPanel()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			self:RefreshPanel()
		end)
	end)

	-- Party members' Handler health, 5x a second.
	task.spawn(function()
		while true do
			task.wait(0.2)
			for userId, bar in ui.HudBars do
				local player = Players:GetPlayerByUserId(userId)
				local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					UIKit.SetBar(bar, humanoid.Health, humanoid.MaxHealth)
				else
					UIKit.SetBar(bar, 0, 1)
					bar.Label.Text = "down"
				end
			end
		end
	end)
end

return PartyController
