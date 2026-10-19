--[[
	PvPController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/PvPController

	Client UI for THE NIGHTMARE COLOSSEUM (server logic: DuelService).
	  * Colosseum panel (P / PVP button / the podium south of the Forge):
	    your record + Arena Tokens, "Allow duel requests" toggle, everyone in the server
	    with CHALLENGE (Best of 1 / Best of 3) buttons.
	  * Incoming challenge pop-up with ACCEPT / DECLINE (expires).
	  * Match HUD: score, round, timer, Handler knockouts, FORFEIT.
	  * PREP: pick which saved build to fight with (illegal builds show why).
	  * Big round banners, sudden-death shrinking ring, results screen.
	  * Red outline on your opponent's Handler and Nightmare. Reset is disabled mid-duel.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local RankDefinitions = require(Shared:WaitForChild("RankDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local PvPController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local PVP_RED = Color3.fromRGB(255, 80, 100)
local controllers
local ui = {}
local duelRequest: RemoteFunction
local matchState = nil -- latest "State" from the server (nil = not in a duel)
local queueState = nil -- latest "Queue" from the server ({ Searching, Waited, Range })
local incoming = nil -- current incoming request
local zoneParts = {}
local highlights = {}

function PvPController:Init(registry)
	controllers = registry
	duelRequest = Net.Get("DuelRequest")
end

function PvPController:IsInMatch(): boolean
	return matchState ~= nil
end

function PvPController:Request(action: string, ...)
	local ok, result = pcall(duelRequest.InvokeServer, duelRequest, action, ...)
	if not ok or type(result) ~= "table" then
		return { Ok = false, Error = "Could not reach the server." }
	end
	return result
end

-- Opponent Handler + Nightmare (for targeting and outlines).
function PvPController:GetOpponentModels(): { Model }
	local list = {}
	local character = localPlayer.Character
	local myDuel = character and character:GetAttribute("DuelId")
	local mySide = character and character:GetAttribute("DuelSide")
	if not myDuel then
		return list
	end
	-- Enemies only (other side), and not players who are out for this round.
	for _, player in Players:GetPlayers() do
		local other = player.Character
		if other and other:GetAttribute("DuelId") == myDuel and other:GetAttribute("DuelSide") ~= mySide and not other:GetAttribute("DuelOut") then
			table.insert(list, other)
		end
	end
	for _, nightmare in CollectionService:GetTagged("Nightmare") do
		if nightmare:GetAttribute("DuelId") == myDuel and nightmare:GetAttribute("DuelSide") ~= mySide and not nightmare:GetAttribute("DuelOut") then
			table.insert(list, nightmare)
		end
	end
	return list
end

local function setResetEnabled(enabled: boolean)
	for _ = 1, 5 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", enabled) then
			return
		end
		task.wait(0.5)
	end
end

------------------------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------------------------
-- The RANKED box: rank, rating, record and the queue button / search status.
function PvPController:RefreshRanked()
	local profile = controllers.ClientState.Profile
	if not profile or not ui.RankLabel then
		return
	end
	local record = RankDefinitions.Record(profile)
	local tier = RankDefinitions.TierFor(record.Rating)
	local placement = record.Games < RankDefinitions.PlacementGames and ("  ·  placement %d/%d"):format(record.Games, RankDefinitions.PlacementGames) or ""
	ui.RankLabel.Text = ('RANKED  <font color="#%s">%s %d</font>'):format(tier.Color:ToHex(), tier.DisplayName, record.Rating)
	local searching = queueState and queueState.Searching
	if searching then
		local waited = math.floor(queueState.Waited or 0)
		ui.RankStatus.Text = ("Searching... %d:%02d  ·  rating range ±%d"):format(waited // 60, waited % 60, math.floor(queueState.Range or 0))
		ui.RankStatus.TextColor3 = C.Warn
		ui.QueueButton.Text = "CANCEL SEARCH"
		ui.QueueButton.BackgroundColor3 = C.PanelLighter
	else
		ui.RankStatus.Text = ("%d W · %d L · %d D  ·  peak %d%s  ·  Best of %d, 100 Power"):format(record.Wins or 0, record.Losses or 0, record.Draws or 0, record.Peak or record.Rating, placement, RankDefinitions.BestOf)
		ui.RankStatus.TextColor3 = C.SubText
		ui.QueueButton.Text = "FIND MATCH"
		ui.QueueButton.BackgroundColor3 = PVP_RED
	end
end

function PvPController:RefreshPanel()
	self:RefreshRanked()
	local profile = controllers.ClientState.Profile
	if profile then
		local pvp = profile.PvP or {}
		ui.Record.Text = ("Record  %d W · %d L · %d D    Arena Tokens: %d"):format(pvp.Wins or 0, pvp.Losses or 0, pvp.Draws or 0, profile.ArenaTokens or 0)
		local allow = not (profile.Settings and profile.Settings.AllowDuels == false)
		ui.AllowButton.Text = allow and "DUEL REQUESTS: ON" or "DUEL REQUESTS: OFF"
		ui.AllowButton.BackgroundColor3 = allow and C.Good or C.PanelLighter
		ui.AllowButton.TextColor3 = allow and C.Background or C.Text
	end

	for _, child in ui.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	-- Team duels: as the leader of a party of 2-3 you can challenge another party's leader.
	local partySize = controllers.PartyController:GetSize()
	local canTeamDuel = controllers.PartyController:IsLeader() and partySize >= Config.PvP.MinTeamSize and partySize <= Config.PvP.MaxTeamSize
	local count = 0
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			count += 1
			local row = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = C.PanelLight, LayoutOrder = count, Parent = ui.List }, { UIKit.Corner(8) })
			UIKit.Label({ Text = player.DisplayName, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(canTeamDuel and 0.34 or 0.45, -10, 1, 0), MaxTextSize = 16, Parent = row })
			if canTeamDuel then
				UIKit.Button({
					Text = ("TEAM %dv%d"):format(partySize, partySize),
					Position = UDim2.new(0.79, 0, 0.15, 0),
					Size = UDim2.new(0.2, 0, 0.7, 0),
					BackgroundColor3 = Color3.fromRGB(60, 140, 220),
					MaxTextSize = 14,
					Parent = row,
				}, function()
					ui.PanelMessage.Text = "Sending team challenge..."
					ui.PanelMessage.TextColor3 = C.SubText
					local result = self:Request("ChallengeTeam", player.UserId)
					ui.PanelMessage.Text = result.Ok and ("Team challenge sent to %s's party!"):format(player.DisplayName) or (result.Error or "Couldn't send.")
					ui.PanelMessage.TextColor3 = result.Ok and C.Good or C.Bad
				end)
			end
			for i, bestOf in Config.PvP.BestOfOptions do
				UIKit.Button({
					Text = ("BEST OF %d"):format(bestOf),
					Position = UDim2.new((canTeamDuel and 0.35 or 0.45) + (i - 1) * (canTeamDuel and 0.22 or 0.27), 0, 0.15, 0),
					Size = UDim2.new(canTeamDuel and 0.2 or 0.25, 0, 0.7, 0),
					BackgroundColor3 = PVP_RED,
					MaxTextSize = 14,
					Parent = row,
				}, function()
					ui.PanelMessage.Text = "Sending challenge..."
					ui.PanelMessage.TextColor3 = C.SubText
					local result = self:Request("Challenge", player.UserId, bestOf)
					ui.PanelMessage.Text = result.Ok and ("Challenge sent to %s!"):format(player.DisplayName) or (result.Error or "Couldn't send.")
					ui.PanelMessage.TextColor3 = result.Ok and C.Good or C.Bad
				end)
			end
		end
	end
	if count == 0 then
		UIKit.Label({ Text = "Nobody else is here yet. Invite a friend, or test with 2 players in Studio (Test → Clients and Servers → 2 Players).", Size = UDim2.new(1, -8, 0, 60), TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 14, Parent = ui.List })
	end
end

function PvPController:OpenPanel()
	if matchState then
		return
	end
	ui.Panel.Visible = true
	ui.PanelMessage.Text = ""
	self:RefreshPanel()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.AllowButton
	end
end

function PvPController:IsPanelOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

function PvPController:ClosePanel()
	ui.Panel.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Panel) then
		GuiService.SelectedObject = nil
	end
end

function PvPController:TogglePanel()
	if ui.Panel.Visible then
		self:ClosePanel()
	else
		self:OpenPanel()
	end
end

------------------------------------------------------------------------------------------
-- Match display
------------------------------------------------------------------------------------------
function PvPController:Banner(title: string, subtitle: string?)
	ui.BannerTitle.Text = title
	ui.BannerSub.Text = subtitle or ""
	ui.Banner.Visible = true
	ui.BannerTitle.TextTransparency = 0
	ui.BannerSub.TextTransparency = 0
	local token = (ui.BannerToken or 0) + 1
	ui.BannerToken = token
	task.delay(2.4, function()
		if ui.BannerToken ~= token then
			return
		end
		TweenService:Create(ui.BannerTitle, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(ui.BannerSub, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.wait(0.5)
		if ui.BannerToken == token then
			ui.Banner.Visible = false
		end
	end)
end

local function pips(count: number): string
	local filled = string.rep("●", count)
	return filled .. string.rep("○", math.max(0, Config.PvP.HandlerKOsToLose - count))
end

function PvPController:RefreshPrep()
	for _, child in ui.PrepList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local state = matchState
	if not state or state.State ~= "Prep" or not state.Builds then
		ui.Prep.Visible = false
		return
	end
	ui.Prep.Visible = true
	for _, build in state.Builds do
		local chosen = build.Index == state.Choice
		local text = ("%s%s  ·  %s  ·  Power %d"):format(chosen and "★ " or "", build.Name, build.Archetype, build.Power)
		if not build.Legal then
			text ..= "  ·  NOT PvP-LEGAL"
		end
		UIKit.Button({
			Text = text,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = build.Index,
			BackgroundColor3 = chosen and C.Accent or (build.Legal and C.PanelLight or Color3.fromRGB(60, 30, 35)),
			AutoButtonColor = build.Legal,
			MaxTextSize = 15,
			Parent = ui.PrepList,
		}, function()
			if not build.Legal then
				ui.PrepMessage.Text = build.Reason or "Over the PvP Power budget (100)."
				return
			end
			local result = self:Request("SelectBuild", build.Index)
			ui.PrepMessage.Text = result.Ok and "" or (result.Error or "")
		end)
	end
end

function PvPController:ApplyState(state)
	if state.State == "None" then
		matchState = nil
		ui.Scoreboard.Visible = false
		ui.Prep.Visible = false
		for _, part in zoneParts do
			part.Transparency = 1
		end
		setResetEnabled(true)
		controllers.HUDController:SetPvPMode(false)
		return
	end
	local firstState = matchState == nil
	matchState = state
	if firstState then
		self:ClosePanel()
		ui.Results.Visible = false
		controllers.WorkshopController:Close()
		setResetEnabled(false)
		controllers.HUDController:SetPvPMode(true)
	end
	ui.Scoreboard.Visible = true
	ui.Score.Text = ("YOU  %d  —  %d  %s"):format(state.MyScore or 0, state.OpponentScore or 0, string.upper(state.OpponentName or "?"))
	ui.RoundInfo.Text = ("%sRound %d  ·  Best of %d"):format(state.Ranked and "RANKED  ·  " or "", math.max(state.Round or 0, 1), state.BestOf or 1)
	if (state.TeamSize or 1) > 1 then
		local function standing(list)
			local n = 0
			for _, member in list or {} do
				if not member.Out then
					n += 1
				end
			end
			return n
		end
		ui.KOs.Text = ("Standing  —  Your team %d/%d   ·   Enemy %d/%d%s"):format(standing(state.Allies), #(state.Allies or {}), standing(state.Enemies), #(state.Enemies or {}), state.AmOut and "   ·   YOU'RE OUT" or "")
	else
		ui.KOs.Text = ("Handler KOs  —  You %s   ·   Them %s"):format(pips(state.MyKOs or 0), pips(state.OpponentKOs or 0))
	end
	self:RefreshPrep()
end

function PvPController:ShowResults(data)
	ui.Results.Visible = true
	local titles = { Win = "VICTORY!", Loss = "DEFEAT", Draw = "DRAW" }
	local colors = { Win = C.Good, Loss = C.Bad, Draw = C.Warn }
	ui.ResultTitle.Text = titles[data.Result] or "MATCH OVER"
	ui.ResultTitle.TextColor3 = colors[data.Result] or C.Text
	ui.ResultScore.Text = ("You %d — %d %s%s"):format(data.MyScore or 0, data.OpponentScore or 0, data.OpponentName or "", data.Reason == "Forfeit" and "  (forfeit)" or "")
	local r = data.Rewards
	ui.ResultRewards.Text = r and ("+%d Arena Tokens   ·   +%d XP   ·   +%d coins"):format(r.ArenaTokens or 0, r.XP or 0, r.Coins or 0) or (data.RewardNote or "No rewards this time.")
	local ranked = data.Ranked
	if ranked then
		ui.ResultRewards.Text ..= ("\nRATING %s%d  →  %s %d"):format(ranked.Delta >= 0 and "+" or "−", math.abs(ranked.Delta), ranked.Tier or "", ranked.New)
	end
	ui.ResultFooter.Text = ("Returning to the Forge in %ds..."):format(data.ReturnIn or 8)
	task.delay(data.ReturnIn or 8, function()
		ui.Results.Visible = false
	end)
end

------------------------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------------------------
function PvPController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "PvPGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 18, Parent = localPlayer:WaitForChild("PlayerGui") })

	-- Colosseum panel
	local panel = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.55, 0.72), BackgroundColor3 = C.Panel, Visible = false, Parent = gui }, { UIKit.Corner(14), UIKit.Stroke(PVP_RED, 2, 0.1), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(760, 620), Parent = panel })
	UIKit.Responsive(panel) -- near full screen on phones
	ui.Panel = panel
	UIKit.Label({ Text = "THE NIGHTMARE COLOSSEUM", Size = UDim2.fromScale(0.85, 0.08), Font = UIKit.FontHeavy, TextColor3 = PVP_RED, MaxTextSize = 30, Parent = panel })
	UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.08, 0.08), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		self:ClosePanel()
	end)
	UIKit.Label({
		Text = "1v1 Nightmare Duels. Win a round by defeating the enemy NIGHTMARE or knocking out their HANDLER twice. Builds must fit the 100 Power budget. Rounds last 3 minutes, then the arena shrinks.",
		Position = UDim2.fromScale(0, 0.09),
		Size = UDim2.fromScale(1, 0.12),
		Font = UIKit.FontBody,
		TextColor3 = C.SubText,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 14,
		Parent = panel,
	})
	ui.Record = UIKit.Label({ Position = UDim2.fromScale(0, 0.22), Size = UDim2.fromScale(0.62, 0.06), TextColor3 = C.Warn, TextWrapped = false, MaxTextSize = 15, Parent = panel })
	ui.AllowButton = UIKit.Button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0.215), Size = UDim2.fromScale(0.36, 0.07), MaxTextSize = 14, Parent = panel }, function()
		local profile = controllers.ClientState.Profile
		local allow = not (profile and profile.Settings and profile.Settings.AllowDuels == false)
		self:Request("SetAllow", not allow)
	end)
	-- RANKED: rank, rating, record, FIND MATCH / CANCEL and the search status.
	local ranked = UIKit.New("Frame", { Position = UDim2.fromScale(0, 0.3), Size = UDim2.fromScale(1, 0.15), BackgroundColor3 = C.PanelLight, Parent = panel }, { UIKit.Corner(10), UIKit.Padding(8) })
	ui.RankLabel = UIKit.Label({ Size = UDim2.fromScale(0.6, 0.5), RichText = true, Font = UIKit.FontHeavy, MaxTextSize = 18, Parent = ranked })
	ui.RankStatus = UIKit.Label({ Position = UDim2.fromScale(0, 0.52), Size = UDim2.fromScale(0.6, 0.46), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 13, Parent = ranked })
	ui.QueueButton = UIKit.Button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromScale(0.36, 0.8), BackgroundColor3 = PVP_RED, MaxTextSize = 16, Parent = ranked }, function()
		local searching = queueState and queueState.Searching
		local result = self:Request(searching and "LeaveQueue" or "QueueRanked")
		if not result.Ok then
			ui.PanelMessage.Text = result.Error or "Couldn't join the queue."
			ui.PanelMessage.TextColor3 = C.Bad
		end
	end)

	UIKit.Label({ Text = "CASUAL DUELS · PLAYERS IN THIS SERVER", Position = UDim2.fromScale(0, 0.47), Size = UDim2.fromScale(1, 0.05), TextColor3 = C.SubText, MaxTextSize = 13, Parent = panel })
	ui.List = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromScale(0, 0.53),
		Size = UDim2.fromScale(1, 0.38),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, { UIKit.List(6) })
	ui.PanelMessage = UIKit.Label({ Position = UDim2.fromScale(0, 0.93), Size = UDim2.fromScale(1, 0.07), Font = UIKit.FontBody, MaxTextSize = 14, Parent = panel })

	-- Incoming challenge
	local popup = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(420, 120), BackgroundColor3 = C.Panel, Visible = false, Parent = gui }, { UIKit.Corner(12), UIKit.Stroke(PVP_RED, 2, 0), UIKit.Padding(10) })
	UIKit.AutoScale(popup)
	ui.Popup = popup
	ui.PopupText = UIKit.Label({ Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, MaxTextSize = 18, Parent = popup })
	ui.AcceptButton = UIKit.Button({ Text = "ACCEPT", Position = UDim2.new(0, 0, 1, -42), Size = UDim2.new(0.48, 0, 0, 42), BackgroundColor3 = C.Good, TextColor3 = C.Background, Parent = popup }, function()
		self:AnswerIncoming(true)
	end)
	UIKit.Button({ Text = "DECLINE", Position = UDim2.new(0.52, 0, 1, -42), Size = UDim2.new(0.48, 0, 0, 42), BackgroundColor3 = C.PanelLighter, Parent = popup }, function()
		self:AnswerIncoming(false)
	end)

	-- Scoreboard
	local board = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(460, 92), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.1, Visible = false, Parent = gui }, { UIKit.Corner(10), UIKit.Stroke(PVP_RED, 1, 0.3) })
	UIKit.AutoScale(board)
	ui.Scoreboard = board
	ui.Score = UIKit.Label({ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -110, 0, 30), Font = UIKit.FontHeavy, MaxTextSize = 22, Parent = board })
	ui.Timer = UIKit.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 4), Size = UDim2.fromOffset(150, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = UIKit.FontHeavy, TextColor3 = C.Warn, MaxTextSize = 20, Parent = board })
	ui.RoundInfo = UIKit.Label({ Position = UDim2.fromOffset(10, 36), Size = UDim2.new(0.6, -10, 0, 20), TextColor3 = C.SubText, MaxTextSize = 14, Parent = board })
	ui.KOs = UIKit.Label({ Position = UDim2.fromOffset(10, 60), Size = UDim2.new(0.75, -10, 0, 22), MaxTextSize = 14, Parent = board })
	UIKit.Button({ Text = "FORFEIT", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -8), Size = UDim2.fromOffset(96, 30), BackgroundColor3 = C.PanelLighter, MaxTextSize = 13, Parent = board }, function()
		self:Request("Forfeit")
	end)

	-- Prep (choose build)
	local prep = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 156), Size = UDim2.fromOffset(460, 210), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.05, Visible = false, Parent = gui }, { UIKit.Corner(10), UIKit.Padding(10) })
	UIKit.AutoScale(prep)
	ui.Prep = prep
	UIKit.Label({ Text = "PREPARATION — choose your Nightmare for this round", Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Warn, MaxTextSize = 15, Parent = prep })
	ui.PrepList = UIKit.New("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 140), BackgroundTransparency = 1, Parent = prep }, { UIKit.List(6) })
	ui.PrepMessage = UIKit.Label({ Position = UDim2.new(0, 0, 1, -20), Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.Bad, Font = UIKit.FontBody, MaxTextSize = 13, Parent = prep })

	-- Banner
	ui.Banner = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.9, 0.16), BackgroundTransparency = 1, Visible = false, Parent = gui })
	ui.BannerTitle = UIKit.Label({ Size = UDim2.fromScale(1, 0.62), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, TextColor3 = PVP_RED, TextStrokeTransparency = 0.2, MaxTextSize = 56, Parent = ui.Banner })
	ui.BannerSub = UIKit.Label({ Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.38), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, MaxTextSize = 24, Parent = ui.Banner })

	-- Results
	local results = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 260), BackgroundColor3 = C.Panel, Visible = false, Parent = gui }, { UIKit.Corner(14), UIKit.Stroke(PVP_RED, 2, 0.1), UIKit.Padding(16) })
	UIKit.AutoScale(results)
	ui.Results = results
	ui.ResultTitle = UIKit.Label({ Size = UDim2.new(1, 0, 0, 64), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, MaxTextSize = 52, Parent = results })
	ui.ResultScore = UIKit.Label({ Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 20, Parent = results })
	ui.ResultRewards = UIKit.Label({ Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Warn, MaxTextSize = 18, Parent = results })
	ui.ResultFooter = UIKit.Label({ Position = UDim2.new(0, 0, 1, -28), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 14, Parent = results })

	-- Sudden death ring (32 glowing panels repositioned every frame)
	local folder = Instance.new("Folder")
	folder.Name = "DuelZone"
	folder.Parent = Workspace
	for i = 1, 32 do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Neon
		p.Color = PVP_RED
		p.Transparency = 1
		p.Size = Vector3.new(0.3, 10, 4)
		p.Parent = folder
		zoneParts[i] = p
	end
end

function PvPController:AnswerIncoming(accept: boolean)
	local request = incoming
	incoming = nil
	ui.Popup.Visible = false
	if request then
		local result = self:Request("Respond", request.RequestId, accept)
		if not result.Ok and result.Error then
			controllers.HUDController:Toast(result.Error, C.Bad, 3)
		end
	end
end

function PvPController:UpdateFrame()
	local state = matchState
	-- Timer
	if state and state.PhaseEndsAt then
		local left = math.max(0, state.PhaseEndsAt - Workspace:GetServerTimeNow())
		local labels = { Prep = "PREP", Countdown = "GET READY", Live = "", SuddenDeath = "SUDDEN DEATH", RoundOver = "", Ended = "" }
		local label = labels[state.State] or ""
		ui.Timer.Text = (state.State == "RoundOver" or state.State == "Ended") and "" or ("%s %d:%02d"):format(label, math.floor(left / 60), math.floor(left % 60))
		ui.Timer.TextColor3 = state.State == "SuddenDeath" and C.Bad or C.Warn
	end

	-- Sudden death ring
	local showZone = state and state.State == "SuddenDeath" and state.SuddenDeathStart
	if showZone then
		local duration = state.SuddenDeathEnd - state.SuddenDeathStart
		local t = math.clamp((Workspace:GetServerTimeNow() - state.SuddenDeathStart) / duration, 0, 1)
		local radius = state.ZoneStartRadius + (state.ZoneEndRadius - state.ZoneStartRadius) * t
		local center = state.ZoneCenter
		for i, p in zoneParts do
			local angle = (i / #zoneParts) * math.pi * 2
			p.Size = Vector3.new(0.3, 10, (2 * math.pi * radius) / #zoneParts + 0.2)
			p.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * radius, 5, math.sin(angle) * radius)) * CFrame.Angles(0, -angle, 0)
			p.Transparency = 0.55
		end
	elseif zoneParts[1] and zoneParts[1].Transparency < 1 then
		for _, p in zoneParts do
			p.Transparency = 1
		end
	end

	-- Opponent outlines
	local opponents = state and self:GetOpponentModels() or {}
	for model, highlight in highlights do
		if not table.find(opponents, model) or not model.Parent then
			highlight:Destroy()
			highlights[model] = nil
		end
	end
	for _, model in opponents do
		if not highlights[model] then
			local highlight = Instance.new("Highlight")
			highlight.FillTransparency = 0.85
			highlight.FillColor = PVP_RED
			highlight.OutlineColor = PVP_RED
			highlight.Adornee = model
			highlight.Parent = Workspace:FindFirstChild("ClientEffects") or Workspace
			highlights[model] = highlight
		end
	end
end

function PvPController:Start()
	self:BuildGui()

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "OpenColosseum" then
			self:OpenPanel()
		end
	end)
	controllers.ClientState.Changed:Connect(function()
		if ui.Panel.Visible then
			self:RefreshPanel()
		end
	end)
	Players.PlayerAdded:Connect(function()
		if ui.Panel.Visible then
			self:RefreshPanel()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if ui.Panel.Visible then
				self:RefreshPanel()
			end
		end)
	end)

	Net.Get("DuelEvent").OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" then
			return
		end
		if kind == "Incoming" then
			incoming = data
			if data.TeamSize then
				ui.PopupText.Text = ("%s's party challenges your party to a %dv%d Team Duel (Best of %d)!"):format(data.FromName, data.TeamSize, data.TeamSize, data.BestOf)
			else
				ui.PopupText.Text = ("%s challenges you to a Best-of-%d Nightmare Duel!"):format(data.FromName, data.BestOf)
			end
			ui.Popup.Visible = true
			if UserInputService.GamepadEnabled then
				GuiService.SelectedObject = ui.AcceptButton
			end
			local id = data.RequestId
			task.delay(data.Timeout or 20, function()
				if incoming and incoming.RequestId == id then
					incoming = nil
					ui.Popup.Visible = false
				end
			end)
		elseif kind == "RequestResult" then
			-- The HUD toast draws under this ScreenGui, so mirror it in the panel when it's open.
			if ui.Panel.Visible then
				ui.PanelMessage.Text = data.Text or ""
				ui.PanelMessage.TextColor3 = C.Warn
			end
			controllers.HUDController:Toast(data.Text or "", C.Warn, 3)
		elseif kind == "State" then
			self:ApplyState(data)
		elseif kind == "Banner" then
			self:Banner(data.Title or "", data.Subtitle)
		elseif kind == "MatchEnd" then
			self:ShowResults(data)
		elseif kind == "Queue" then
			queueState = data
			self:RefreshRanked()
		end
	end)

	RunService.RenderStepped:Connect(function()
		self:UpdateFrame()
	end)
end

return PvPController
