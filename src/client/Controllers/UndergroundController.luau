--[[
	UndergroundController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/UndergroundController

	Client side of NIGHTMARE UNDERGROUND (server: UndergroundService + DuelService Mode
	"Underground"). PvPController hands it every duel "State"; in an Underground match it
	replaces the duel scoreboard with the fight HUD:
	  TOP LEFT     you: name, your Nightmare's name, health, guard, rounds won
	  TOP RIGHT    the opponent, the same
	  TOP CENTRE   ROUND n / 3, the round clock, the score
	  BOTTOM LEFT  your stance and the controls
	  CALLOUTS     what your blows just did: HEAVY IMPACT, GUARD BREAK, KNOCKDOWN, n HIT COMBO,
	               and the fight's own (UndergroundFightService "UGCallout": PARRY!, SLIPPED,
	               COUNTER!, GASSED, FEINT, the combo's name) under the plate of who it's about
	Also the "searching for an opponent" pill while you're in the queue (DuelEvent "UGQueue").
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UGRank = require(Shared:WaitForChild("UGRankDefinitions"))

local UndergroundController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local RGB = Color3.fromRGB
local RED, BLUE = RGB(255, 60, 70), RGB(80, 150, 255)
local STEEL = RGB(18, 16, 20)

local controllers
local ui = {}
local state = nil -- the latest Underground "State" (nil = not in an Underground match)
local chain = { Count = 0, At = 0 }

function UndergroundController:Init(registry)
	controllers = registry
end

function UndergroundController:IsInMatch(): boolean
	return state ~= nil
end

local fighters -- (defined below)

-- The other fighter's Nightmare (nil outside an Underground match).
function UndergroundController:GetOpponent(): Model?
	if not state then
		return nil
	end
	local _, theirs = fighters()
	return theirs
end

------------------------------------------------------------------------------------------
-- Who's who
------------------------------------------------------------------------------------------
function fighters(): (Model?, Model?)
	local character = localPlayer.Character
	local duelId = character and character:GetAttribute("DuelId")
	local mySide = character and character:GetAttribute("DuelSide")
	if not duelId then
		return nil, nil
	end
	local mine, theirs
	for _, model in CollectionService:GetTagged("Nightmare") do
		if model:GetAttribute("DuelId") == duelId then
			if model:GetAttribute("OwnerUserId") == localPlayer.UserId then
				mine = model
			elseif model:GetAttribute("DuelSide") ~= mySide then
				theirs = model
			end
		end
	end
	return mine, theirs
end

------------------------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------------------------
-- One fighter's plate (a corner of the screen): name, Nightmare, health, guard, round pips.
local function plate(parent: Instance, right: boolean, color: Color3)
	local frame = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(right and 1 or 0, 0),
		Position = right and UDim2.new(1, -16, 0, 60) or UDim2.new(0, 16, 0, 60), -- (below Roblox's top bar)
		Size = UDim2.fromOffset(380, 98),
		BackgroundColor3 = STEEL,
		BackgroundTransparency = 0.15,
		Parent = parent,
	}, { UIKit.Corner(6), UIKit.Stroke(color, 2, 0.15) })
	UIKit.AutoScale(frame)
	local align = right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	-- a slab of the corner's colour along the outside edge
	UIKit.New("Frame", { AnchorPoint = Vector2.new(right and 1 or 0, 0), Position = UDim2.fromScale(right and 1 or 0, 0), Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, Parent = frame })
	local p = {}
	p.Name = UIKit.Label({ Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -28, 0, 26), TextXAlignment = align, Font = UIKit.FontDisplay, TextColor3 = C.Text, MaxTextSize = 24, Parent = frame })
	p.Sub = UIKit.Label({ Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -28, 0, 16), TextXAlignment = align, TextColor3 = C.SubText, MaxTextSize = 12, Parent = frame })
	p.Health = UIKit.Bar({ Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -28, 0, 18), Color = color, MaxTextSize = 12, Parent = frame })
	p.Guard = UIKit.Bar({ Position = UDim2.fromOffset(14, 72), Size = UDim2.new(0.62, -14, 0, 8), Color = RGB(235, 225, 200), Parent = frame })
	if right then
		p.Guard.Frame.AnchorPoint = Vector2.new(1, 0)
		p.Guard.Frame.Position = UDim2.new(1, -14, 0, 72)
	end
	p.Guard.Label.Visible = false
	-- stamina (UndergroundFightService): under the guard, gold, red when gassed
	p.Stamina = UIKit.Bar({ Position = UDim2.fromOffset(14, 84), Size = UDim2.new(0.62, -14, 0, 6), Color = RGB(255, 200, 60), Parent = frame })
	if right then
		p.Stamina.Frame.AnchorPoint = Vector2.new(1, 0)
		p.Stamina.Frame.Position = UDim2.new(1, -14, 0, 84)
	end
	p.Stamina.Label.Visible = false
	-- what just happened to this fighter (PARRY!, SLIPPED, GASSED, a combo's name), under the plate
	p.Flash = UIKit.Label({ AnchorPoint = Vector2.new(right and 1 or 0, 0), Position = right and UDim2.new(1, -4, 1, 6) or UDim2.new(0, 4, 1, 6), Size = UDim2.fromOffset(372, 26), TextXAlignment = align, Font = UIKit.FontPunch, TextColor3 = C.Warn, TextStrokeTransparency = 0.2, MaxTextSize = 24, Visible = false, Parent = frame })
	p.Pips =UIKit.Label({ AnchorPoint = Vector2.new(right and 0 or 1, 0), Position = right and UDim2.fromOffset(14, 68) or UDim2.new(1, -14, 0, 68), Size = UDim2.fromOffset(110, 18), TextXAlignment = right and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextColor3 = C.Warn, MaxTextSize = 14, Parent = frame })
	p.Frame = frame
	return p
end

function UndergroundController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "UndergroundGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 17, Enabled = false, Parent = localPlayer:WaitForChild("PlayerGui") })
	ui.Gui = gui
	ui.Me = plate(gui, false, RED)
	ui.Them = plate(gui, true, BLUE)

	-- the clock in the middle
	local clock = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(190, 100), BackgroundColor3 = STEEL, BackgroundTransparency = 0.1, Parent = gui }, { UIKit.Corner(6), UIKit.Stroke(RGB(120, 110, 120), 1, 0.3) })
	UIKit.AutoScale(clock)
	ui.Round = UIKit.Label({ Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, MaxTextSize = 13, Parent = clock })
	ui.Timer = UIKit.Label({ Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 46), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontPunch, TextColor3 = C.Text, MaxTextSize = 44, Parent = clock })
	ui.Score = UIKit.Label({ Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextColor3 = C.Warn, MaxTextSize = 24, Parent = clock })

	-- your stance and the controls, bottom left
	local hints = UIKit.New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(500, 104), BackgroundColor3 = STEEL, BackgroundTransparency = 0.25, Parent = gui }, { UIKit.Corner(6), UIKit.Padding(8) })
	UIKit.AutoScale(hints)
	ui.Stance = UIKit.Label({ Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.Warn, MaxTextSize = 15, Parent = hints })
	ui.Controls = UIKit.Label({ Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -22), TextColor3 = C.SubText, Font = UIKit.FontBody, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 12, Parent = hints })

	-- the callout: what your last blows did
	ui.Callout = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 168), Size = UDim2.fromOffset(520, 44), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontPunch, TextColor3 = C.Warn, TextStrokeTransparency = 0.1, MaxTextSize = 40, Visible = false, Parent = gui })
	ui.CalloutSub = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 210), Size = UDim2.fromOffset(520, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Text, MaxTextSize = 16, Visible = false, Parent = gui })

	-- the queue pill (outside a match)
	local queueGui = UIKit.New("ScreenGui", { Name = "UndergroundQueueGui", ResetOnSpawn = false, DisplayOrder = 16, Enabled = false, Parent = localPlayer.PlayerGui })
	ui.QueueGui = queueGui
	local pill = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(560, 40), BackgroundColor3 = STEEL, BackgroundTransparency = 0.1, Parent = queueGui }, { UIKit.Corner(20), UIKit.Stroke(RED, 2, 0.2) })
	UIKit.AutoScale(pill)
	ui.QueueText = UIKit.Label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Text, MaxTextSize = 15, Parent = pill })

	self:BuildCount(gui)
	self:BuildCard(gui)
	self:BuildResults()
end

------------------------------------------------------------------------------------------
-- The scorecard rows (the round card and the results screen share them)
------------------------------------------------------------------------------------------
local STAT_ROWS = {
	{ "STRIKES LANDED", function(s)
		return ("%d / %d"):format(s.Landed or 0, s.Thrown or 0)
	end },
	{ "ACCURACY", function(s)
		return (s.Thrown or 0) > 0 and ("%d%%"):format(math.floor(math.min(1, (s.Landed or 0) / s.Thrown) * 100 + 0.5)) or "—"
	end },
	{ "POWER SHOTS", function(s)
		return tostring(s.Power or 0)
	end },
	{ "COMBOS", function(s)
		return tostring(s.Combos or 0)
	end },
	{ "COUNTERS", function(s)
		return tostring(s.Counters or 0)
	end },
	{ "PARRIES", function(s)
		return tostring(s.Parries or 0)
	end },
	{ "SLIPS", function(s)
		return tostring(s.Slips or 0)
	end },
	{ "KNOCKDOWNS", function(s)
		return tostring(s.Knockdowns or 0)
	end },
	{ "DAMAGE", function(s)
		return tostring(math.floor((s.Damage or 0) + 0.5))
	end },
}
local ROW_HEIGHT = 17

-- A table of the two fighters' numbers: yours on the left (red), theirs on the right (blue).
-- Returns a function(mine, theirs) that fills it in.
local function statTable(parent: Instance, position: UDim2, width: number)
	local frame = UIKit.New("Frame", { Position = position, Size = UDim2.fromOffset(width, #STAT_ROWS * ROW_HEIGHT), BackgroundTransparency = 1, Parent = parent })
	local cells = {}
	for index, row in STAT_ROWS do
		local y = (index - 1) * ROW_HEIGHT
		if index % 2 == 1 then
			UIKit.New("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, ROW_HEIGHT), BackgroundColor3 = RGB(255, 255, 255), BackgroundTransparency = 0.95, BorderSizePixel = 0, Parent = frame })
		end
		local mine = UIKit.Label({ Position = UDim2.fromOffset(8, y), Size = UDim2.new(0.28, -8, 0, ROW_HEIGHT), TextXAlignment = Enum.TextXAlignment.Left, Font = UIKit.FontSmall, TextColor3 = RED, MaxTextSize = 13, Parent = frame })
		UIKit.Label({ Position = UDim2.new(0.28, 0, 0, y), Size = UDim2.new(0.44, 0, 0, ROW_HEIGHT), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 11, Text = row[1], Parent = frame })
		local theirs = UIKit.Label({ Position = UDim2.new(0.72, 0, 0, y), Size = UDim2.new(0.28, -8, 0, ROW_HEIGHT), TextXAlignment = Enum.TextXAlignment.Right, Font = UIKit.FontSmall, TextColor3 = BLUE, MaxTextSize = 13, Parent = frame })
		cells[index] = { mine, theirs }
	end
	return function(mine, theirs)
		for index, row in STAT_ROWS do
			cells[index][1].Text = row[2](mine or {})
			cells[index][2].Text = row[2](theirs or {})
		end
	end
end

------------------------------------------------------------------------------------------
-- The count over a fighter who's down
------------------------------------------------------------------------------------------
function UndergroundController:BuildCount(gui: ScreenGui)
	ui.CountNumber = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(240, 110), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontPunch, TextColor3 = C.Bad, TextStrokeTransparency = 0, MaxTextSize = 100, Visible = false, Parent = gui })
	ui.CountText = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 108), Size = UDim2.fromOffset(560, 24), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = C.Text, TextStrokeTransparency = 0.2, MaxTextSize = 17, Visible = false, Parent = gui })
end

-- data = { UserId (who's down), Duration, Interval, Count (its knockdowns this round), Left }
function UndergroundController:Count(data)
	if not ui.CountNumber or not state then
		return
	end
	local token = (ui.CountToken or 0) + 1
	ui.CountToken = token
	local me = data.UserId == localPlayer.UserId
	ui.CountText.Text = ("%s  ·  knockdown %d of %d (the %s one stops the fight)"):format(me and "GET UP!" or "THEY'RE DOWN", data.Count or 1, Config.Underground.TKO.Knockdowns,
		Config.Underground.TKO.Knockdowns == 3 and "third" or "last")
	ui.CountText.Visible = true
	ui.CountNumber.Visible = true
	controllers.AudioController:Play("Victory") -- (the crowd)
	task.spawn(function()
		local started = os.clock()
		local shown = 0
		while ui.CountToken == token and os.clock() - started < (data.Duration or 2.4) do
			local n = math.floor((os.clock() - started) / (data.Interval or 0.6)) + 1
			if n ~= shown then
				shown = n
				ui.CountNumber.Text = tostring(n)
				local grow = ui.CountNumber:FindFirstChildOfClass("UIScale") or UIKit.New("UIScale", { Parent = ui.CountNumber })
				grow.Scale = 1.4
				TweenService:Create(grow, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			task.wait()
		end
		if ui.CountToken == token then
			ui.CountNumber.Visible = false
			ui.CountText.Visible = false
		end
	end)
end

------------------------------------------------------------------------------------------
-- The round card (between rounds) and the knockout camera
------------------------------------------------------------------------------------------
function UndergroundController:BuildCard(gui: ScreenGui)
	local card = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 250), Size = UDim2.fromOffset(440, 64 + #STAT_ROWS * ROW_HEIGHT), BackgroundColor3 = STEEL, BackgroundTransparency = 0.08, Visible = false, Parent = gui }, { UIKit.Corner(6), UIKit.Stroke(RGB(255, 200, 60), 2, 0.2) })
	UIKit.AutoScale(card)
	ui.Card = card
	ui.CardTitle = UIKit.Label({ Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextColor3 = RGB(255, 210, 90), MaxTextSize = 22, Parent = card })
	ui.CardJudge = UIKit.Label({ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = C.Text, MaxTextSize = 15, Parent = card })
	ui.CardFill = statTable(card, UDim2.fromOffset(10, 56), 420)
end

local METHOD_TEXT = { KO = "KNOCKOUT", TKO = "TKO", DEC = "DECISION", DRAW = "DRAWN", Left = "OPPONENT LEFT", Forfeit = "FORFEIT" }

-- The camera stays on a fighter going down: side-on to the blow, easing in (both players).
function UndergroundController:KnockoutCamera(winnerUserId: number?, loserUserId: number?, seconds: number)
	local winner, loser
	for _, model in CollectionService:GetTagged("Nightmare") do
		local owner = model:GetAttribute("OwnerUserId")
		if owner == winnerUserId then
			winner = model
		elseif owner == loserUserId then
			loser = model
		end
	end
	local loserRoot = loser and loser:FindFirstChild("HumanoidRootPart")
	local winnerRoot = winner and winner:FindFirstChild("HumanoidRootPart")
	if not loserRoot or not winnerRoot then
		return
	end
	local camera = Workspace.CurrentCamera
	controllers.LockOnController:Release() -- (the lock would keep pulling the view back to the fight)
	local away = (loserRoot.Position - winnerRoot.Position) * Vector3.new(1, 0, 1)
	away = away.Magnitude > 0.1 and away.Unit or Vector3.zAxis
	local side = away:Cross(Vector3.yAxis)
	-- (the side the camera is already on, so the cut doesn't jump across the fight)
	if side:Dot(camera.CFrame.Position - loserRoot.Position) < 0 then
		side = -side
	end
	local floor = loserRoot.Position.Y
	local started = os.clock()
	local focus = loserRoot.Position
	ui.KOCam = true
	RunService:BindToRenderStep("UGKnockoutCamera", Enum.RenderPriority.Last.Value + 1, function()
		local k = math.clamp((os.clock() - started) / seconds, 0, 1)
		if not loserRoot.Parent or not winnerRoot.Parent then
			k = 1
		else
			-- from beyond the one going down, low, looking back at it with the winner standing
			-- over it (the winner is the far side of the shot: never against the lens)
			local between = winnerRoot.Position:Lerp(loserRoot.Position, 0.7)
			focus = focus:Lerp(Vector3.new(between.X, floor + 0.5, between.Z), 0.12)
			local push = 9 - 2 * k
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = 55
			camera.CFrame = CFrame.lookAt(loserRoot.Position * Vector3.new(1, 0, 1) + Vector3.new(0, floor, 0) + away * push + side * 6 + Vector3.new(0, 3.2 - 1.2 * k, 0), focus)
		end
		if k >= 1 then
			RunService:UnbindFromRenderStep("UGKnockoutCamera")
			-- (handed back behind your Handler in its booth, looking into the ring: left where
			-- the shot ended it would face out of the ring at your own Handler)
			local character = localPlayer.Character
			local handler = character and character:FindFirstChild("HumanoidRootPart")
			if handler and loserRoot.Parent then
				local back = (handler.Position - loserRoot.Position) * Vector3.new(1, 0, 1)
				back = back.Magnitude > 0.1 and back.Unit or Vector3.zAxis
				camera.CFrame = CFrame.lookAt(handler.Position + back * 11 + Vector3.new(0, 6, 0), loserRoot.Position)
			end
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70 -- (the round is over: nobody is driving a Nightmare any more)
			ui.KOCam = false
		end
	end)
end

-- data: the round's card (UndergroundService:EndRound "UGRound")
function UndergroundController:RoundCard(data)
	if not ui.Card or not state then
		return
	end
	ui.CountToken = (ui.CountToken or 0) + 1
	ui.CountNumber.Visible = false
	ui.CountText.Visible = false
	local method = METHOD_TEXT[data.Method] or tostring(data.Method or "")
	local who = data.Result == "Win" and "YOU WIN" or data.Result == "Loss" and "YOU LOSE" or "DRAWN"
	ui.CardTitle.Text = ("ROUND %d  ·  %s  ·  %s"):format(data.Round or 1, method, who)
	ui.CardTitle.TextColor3 = data.Result == "Win" and RGB(120, 255, 150) or data.Result == "Loss" and RGB(255, 90, 90) or RGB(255, 210, 90)
	if data.Stoppage then
		ui.CardJudge.Text = data.Move and ("FINISHED WITH THE " .. data.Move) or "STOPPAGE"
	else
		ui.CardJudge.Text = ("JUDGE  %d — %d   ·   points  %d — %d"):format(data.MyJudge or 10, data.TheirJudge or 10, data.MyPoints or 0, data.TheirPoints or 0)
	end
	ui.CardFill(data.Mine, data.Theirs)
	local token = (ui.CardToken or 0) + 1
	ui.CardToken = token
	-- a stoppage: the camera first, the card once the body is on the floor
	local wait = data.Stoppage and (data.CamTime or 2.6) or 0.9
	if data.Stoppage then
		controllers.AudioController:Play("BodySlam")
		controllers.AudioController:Play("Victory")
		self:KnockoutCamera(data.WinnerUserId, data.LoserUserId, data.CamTime or 2.6)
	else
		controllers.AudioController:Play("Defeat") -- (the bell)
	end
	task.delay(wait, function()
		if ui.CardToken == token and state and state.State == "RoundOver" then
			ui.Card.Visible = true
		end
	end)
	task.delay(data.ShowFor or 7, function()
		if ui.CardToken == token then
			ui.Card.Visible = false
		end
	end)
end

------------------------------------------------------------------------------------------
-- The results screen (DuelEvent "MatchEnd" with data.Underground)
------------------------------------------------------------------------------------------
function UndergroundController:BuildResults()
	local gui = UIKit.New("ScreenGui", { Name = "UndergroundResultsGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, Enabled = false, Parent = localPlayer.PlayerGui })
	ui.ResultsGui = gui
	UIKit.New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(4, 3, 6), BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = gui })
	local panel = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(860, 500), BackgroundColor3 = STEEL, BackgroundTransparency = 0.03, Parent = gui }, { UIKit.Corner(8), UIKit.Stroke(RED, 2, 0.1) })
	UIKit.AutoScale(panel)
	ui.ResultsPanel = panel

	-- the winner, in 3D, on the left
	ui.ResultsView = UIKit.New("ViewportFrame", { Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(300, 380), BackgroundColor3 = RGB(10, 8, 12), BackgroundTransparency = 0.2, Parent = panel }, { UIKit.Corner(6), UIKit.Stroke(RGB(120, 110, 120), 1, 0.4) })
	ui.ResultsWinner = UIKit.Label({ Position = UDim2.fromOffset(16, 402), Size = UDim2.fromOffset(300, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextColor3 = C.Text, MaxTextSize = 26, Parent = panel })
	ui.ResultsWinnerSub = UIKit.Label({ Position = UDim2.fromOffset(16, 432), Size = UDim2.fromOffset(300, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, MaxTextSize = 13, Parent = panel })
	ui.ResultsRecord = UIKit.Label({ Position = UDim2.fromOffset(16, 456), Size = UDim2.fromOffset(300, 18), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 12, Parent = panel })

	-- the result, on the right
	local x, w = 336, 508
	ui.ResultsTitle = UIKit.Label({ Position = UDim2.fromOffset(x, 10), Size = UDim2.fromOffset(w, 58), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextColor3 = C.Good, MaxTextSize = 56, Parent = panel })
	ui.ResultsMethod = UIKit.Label({ Position = UDim2.fromOffset(x, 68), Size = UDim2.fromOffset(w, 22), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = RGB(255, 210, 90), MaxTextSize = 17, Parent = panel })
	ui.ResultsScore = UIKit.Label({ Position = UDim2.fromOffset(x, 92), Size = UDim2.fromOffset(w, 34), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontPunch, TextColor3 = C.Text, MaxTextSize = 32, Parent = panel })
	ui.ResultsRounds = UIKit.Label({ Position = UDim2.fromOffset(x, 128), Size = UDim2.fromOffset(w, 20), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 13, Parent = panel })
	-- (whose column is whose)
	ui.ResultsMe = UIKit.Label({ Position = UDim2.fromOffset(x + 8, 154), Size = UDim2.fromOffset(200, 18), TextXAlignment = Enum.TextXAlignment.Left, Font = UIKit.FontSmall, TextColor3 = RED, MaxTextSize = 14, Parent = panel })
	ui.ResultsThem = UIKit.Label({ Position = UDim2.fromOffset(x + w - 208, 154), Size = UDim2.fromOffset(200, 18), TextXAlignment = Enum.TextXAlignment.Right, Font = UIKit.FontSmall, TextColor3 = BLUE, MaxTextSize = 14, Parent = panel })
	ui.ResultsFill = statTable(panel, UDim2.fromOffset(x, 174), w)
	local below = 174 + #STAT_ROWS * ROW_HEIGHT + 8
	ui.ResultsRewards = UIKit.Label({ Position = UDim2.fromOffset(x, below), Size = UDim2.fromOffset(w, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Warn, MaxTextSize = 15, Parent = panel })
	-- the ranked league (UGRankedService): the rating change and the way to the next division
	ui.ResultsRank = UIKit.Label({ Position = UDim2.fromOffset(x, below + 24), Size = UDim2.fromOffset(w, 22), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = C.Text, MaxTextSize = 16, Parent = panel })
	ui.ResultsRankBar = UIKit.Bar({ Position = UDim2.fromOffset(x + 40, below + 50), Size = UDim2.fromOffset(w - 80, 8), Color = RGB(255, 200, 60), Parent = panel })
	ui.ResultsRankBar.Label.Visible = false

	local function choose(choice: string)
		ui.ResultsChoice = ui.ResultsChoice ~= choice and choice or "None"
		local chosen = ui.ResultsChoice
		if chosen == "Queue" then
			ui.ResultsNote.Text = "Back in the queue when this closes."
		elseif chosen == "Rematch" then
			ui.ResultsNote.Text = "Rematch asked: waiting for the other fighter (else you're queued again)."
		end
		task.spawn(function()
			local reply = controllers.PvPController:Request("UGAfter", chosen)
			if type(reply) == "table" and reply.Both and ui.ResultsChoice == "Rematch" then
				ui.ResultsNote.Text = "REMATCH ON: straight back in when this closes."
			end
		end)
		self:RefreshResultsButtons()
	end
	local by = 500 - 16 - 40
	ui.RematchButton = UIKit.Button({ Position = UDim2.fromOffset(x, by), Size = UDim2.fromOffset(160, 40), BackgroundColor3 = RGB(150, 40, 46), Text = "REMATCH", MaxTextSize = 18, Parent = panel }, function()
		choose("Rematch")
	end)
	ui.QueueButton = UIKit.Button({ Position = UDim2.fromOffset(x + 174, by), Size = UDim2.fromOffset(160, 40), BackgroundColor3 = RGB(46, 70, 130), Text = "QUEUE AGAIN", MaxTextSize = 18, Parent = panel }, function()
		choose("Queue")
	end)
	ui.ReturnButton = UIKit.Button({ Position = UDim2.fromOffset(x + 348, by), Size = UDim2.fromOffset(160, 40), Text = "CLOSE", MaxTextSize = 18, Parent = panel }, function()
		gui.Enabled = false
	end)
	ui.ResultsNote = UIKit.Label({ Position = UDim2.fromOffset(x, by - 24), Size = UDim2.fromOffset(w, 18), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 12, Parent = panel })
end

function UndergroundController:RefreshResultsButtons()
	local choice = ui.ResultsChoice
	ui.RematchButton.Text = choice == "Rematch" and "REMATCH ✓" or (ui.RematchAsked and "ACCEPT REMATCH" or "REMATCH")
	ui.QueueButton.Text = choice == "Queue" and "QUEUE AGAIN ✓" or "QUEUE AGAIN"
end

-- The ranked line on the results: "STEEL 1312 → 1340 (+28) · PROMOTED TO CHROME!", or the
-- placement count; the bar shows the way to the next division. change = nil: not ranked.
function UndergroundController:ShowRankChange(change)
	ui.ResultsRank.Visible = change ~= nil
	ui.ResultsRankBar.Frame.Visible = change ~= nil
	if not change then
		return
	end
	local division = UGRank.ById[change.Division] or UGRank.DivisionFor(change.New or UGRank.StartRating)
	local sign = (change.Delta or 0) >= 0 and "+" or "−"
	local delta = ("%s%d"):format(sign, math.abs(change.Delta or 0))
	local text
	if change.Placement then
		text = change.PlacementsDone and ("PLACEMENTS DONE  ·  %s %s %d"):format(delta, division.Name, change.New)
			or ("PLACEMENT %d / %d  ·  %s  ·  rating %d"):format(change.Placement, change.PlacementsTotal or UGRank.Placements, delta, change.New)
	else
		text = ("%s %d → %d  (%s)"):format(division.Name, change.Old, change.New, delta)
		if change.Promoted then
			text ..= "  ·  PROMOTED TO " .. division.Name .. "!"
		elseif change.Demoted then
			text ..= "  ·  DOWN TO " .. division.Name
		end
	end
	if (change.Streak or 0) >= UGRank.StreakBonus.From then
		text ..= ("  ·  %d WIN STREAK"):format(change.Streak)
	end
	if change.Damped then
		text ..= ("  ·  same opponent again: x%.2g"):format(change.Damped)
	end
	ui.ResultsRank.Text = text
	ui.ResultsRank.TextColor3 = change.Promoted and RGB(255, 210, 90) or division.Color
	local progress = change.Placement and not change.PlacementsDone and (change.Placement / (change.PlacementsTotal or UGRank.Placements)) or UGRank.Progress(change.New, division.Id)
	UIKit.SetBar(ui.ResultsRankBar, progress, 1)
	ui.ResultsRankBar.Fill.BackgroundColor3 = division.Color
end

local RESULT_TITLES = { Win = "VICTORY", Loss = "DEFEAT", Draw = "DRAW" }
local RESULT_COLORS = { Win = RGB(120, 255, 150), Loss = RGB(255, 90, 90), Draw = RGB(255, 210, 90) }
local STOP_TEXT = { ThreeKnockdowns = "THREE KNOCKDOWNS", Count = "COULDN'T BEAT THE COUNT" }

function UndergroundController:ShowResults(data)
	local ug = data.Underground
	if not ui.ResultsGui or type(ug) ~= "table" then
		return
	end
	ui.ResultsChoice = "None"
	ui.RematchAsked = false
	ui.Card.Visible = false
	ui.ResultsTitle.Text = RESULT_TITLES[data.Result] or "FIGHT OVER"
	ui.ResultsTitle.TextColor3 = RESULT_COLORS[data.Result] or C.Text
	local method = "BY " .. tostring(ug.Method or "DECISION")
	if ug.Method == "DRAW" then
		method = "LEVEL ON ROUNDS AND ON THE SCORECARDS"
	elseif ug.Method == "THE SCORECARDS" then
		method = ("ON THE SCORECARDS  ·  %d — %d"):format(ug.MyPoints or 0, ug.TheirPoints or 0)
	elseif ug.Method == "ROUNDS WON" then
		method = "ON ROUNDS WON  ·  ALL THREE FOUGHT"
	elseif ug.Method == "KNOCKOUT" or ug.Method == "TKO" then
		method = ("BY %s%s  ·  ROUND %d"):format(ug.Method, (ug.Stop and STOP_TEXT[ug.Stop] and ("  ·  " .. STOP_TEXT[ug.Stop])) or (ug.Move and ("  ·  " .. ug.Move)) or "", ug.FinalRound or 1)
	end
	ui.ResultsMethod.Text = (ug.Ranked and "RANKED  ·  " or "") .. method
	ui.ResultsScore.Text = ("%d — %d"):format(data.MyScore or 0, data.OpponentScore or 0)
	local rounds = {}
	for _, round in ug.Rounds or {} do
		local how = round.Method == "DEC" and ("%d-%d"):format(round.Mine or 10, round.Theirs or 10) or (METHOD_TEXT[round.Method] or tostring(round.Method))
		table.insert(rounds, round.Result == "Draw" and ("R%d DRAWN"):format(round.Round or 0) or ("R%d %s %s"):format(round.Round or 0, round.Result == "Win" and "WON" or "LOST", how))
	end
	ui.ResultsRounds.Text = table.concat(rounds, "   ·   ")
	ui.ResultsMe.Text = string.upper(localPlayer.DisplayName)
	ui.ResultsThem.Text = string.upper(data.OpponentName or "OPPONENT")
	ui.ResultsFill(ug.Mine, ug.Theirs)
	local r = data.Rewards
	ui.ResultsRewards.Text = r and ("+%d Arena Tokens   ·   +%d XP   ·   +%d coins"):format(r.ArenaTokens or 0, r.XP or 0, r.Coins or 0) or (data.RewardNote or "No rewards this time.")
	self:ShowRankChange(data.UGRanked)
	local record = ug.Record
	ui.ResultsRecord.Text = record and ("UNDERGROUND RECORD   %d W  ·  %d L  ·  %d D"):format(record.Wins or 0, record.Losses or 0, record.Draws or 0) or ""
	ui.ResultsWinner.Text = ug.WinnerName and string.upper(ug.WinnerName) or "NO WINNER"
	ui.ResultsWinnerSub.Text = ug.WinnerNightmare and ("with  " .. string.upper(ug.WinnerNightmare)) or ""

	-- the winner's Nightmare, as it stands in the ring (a draw: yours)
	local shown = nil
	local wanted = ug.WinnerUserId or localPlayer.UserId
	for _, model in CollectionService:GetTagged("Nightmare") do
		if model:GetAttribute("OwnerUserId") == wanted then
			shown = model
		end
	end
	local parts = {}
	if shown then
		for _, part in shown:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				table.insert(parts, part)
			end
		end
	end
	local camera = UIKit.ShowParts(ui.ResultsView, parts, 24)
	ui.ResultsView.Visible = camera ~= nil

	local returnIn = data.ReturnIn or 14
	ui.ResultsNote.Text = ("Back to the Forge in %ds"):format(returnIn)
	self:RefreshResultsButtons()
	ui.ResultsGui.Enabled = true
	controllers.AudioController:Play(data.Result == "Loss" and "Defeat" or "Victory")
	local token = (ui.ResultsToken or 0) + 1
	ui.ResultsToken = token
	local ends = os.clock() + returnIn
	task.spawn(function()
		while ui.ResultsToken == token and os.clock() < ends and ui.ResultsGui.Enabled do
			if ui.ResultsChoice == "None" and not ui.RematchAsked then
				ui.ResultsNote.Text = ("Back to the Forge in %ds"):format(math.max(0, math.ceil(ends - os.clock())))
			end
			task.wait(0.25)
		end
		if ui.ResultsToken == token then
			ui.ResultsGui.Enabled = false
		end
	end)
end

-- The other fighter asked for a rematch.
function UndergroundController:RematchAsked(data)
	if ui.ResultsGui and ui.ResultsGui.Enabled then
		ui.RematchAsked = true
		ui.ResultsNote.Text = data.Both and "REMATCH ON: straight back in when this closes."
			or ("%s wants a REMATCH"):format(string.upper(tostring(data.From or "Your opponent")))
		self:RefreshResultsButtons()
	end
end

function UndergroundController:Callout(title: string, subtitle: string?, color: Color3?)
	ui.Callout.Text = title
	ui.Callout.TextColor3 = color or C.Warn
	ui.Callout.Visible = true
	ui.Callout.TextTransparency = 0
	ui.CalloutSub.Text = subtitle or ""
	ui.CalloutSub.Visible = subtitle ~= nil
	ui.CalloutSub.TextTransparency = 0
	local token = (ui.CalloutToken or 0) + 1
	ui.CalloutToken = token
	local grow = ui.Callout:FindFirstChildOfClass("UIScale") or UIKit.New("UIScale", { Parent = ui.Callout })
	grow.Scale = 1.35
	TweenService:Create(grow, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.3, function()
		if ui.CalloutToken == token then
			TweenService:Create(ui.Callout, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			TweenService:Create(ui.CalloutSub, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		end
	end)
end

------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------
local function pips(won: number, needed: number): string
	return string.rep("◆", won) .. string.rep("◇", math.max(0, needed - won))
end

------------------------------------------------------------------------------------------
-- The venues (Config.Underground.Arenas): their lighting and sound, what a big hit does in
-- them, and the first round's introductions
------------------------------------------------------------------------------------------
local THEME_LOOKS = {
	-- the stadium: dark stands, the light all on the ring
	ColossusDome = {
		Ambience = "DistrictAmbience",
		ClockTime = 0, Brightness = 1.2, Exposure = 0.35, Ambient = RGB(70, 66, 92), OutdoorAmbient = RGB(60, 58, 80),
		Atmosphere = { Density = 0.28, Offset = 0, Color = RGB(120, 110, 160), Decay = RGB(40, 34, 70), Glare = 0, Haze = 1.2 },
		Grading = { Brightness = 0, Contrast = 0.18, Saturation = 0.1, TintColor = RGB(245, 242, 255) },
		Bloom = { Intensity = 0.6, Size = 26, Threshold = 1.4 },
	},
	-- the fight club: grimy, warm, close
	UndergroundPit = {
		Ambience = "DistrictAmbience",
		ClockTime = 0, Brightness = 0.6, Exposure = 0.3, Ambient = RGB(90, 76, 66), OutdoorAmbient = RGB(70, 60, 54),
		Atmosphere = { Density = 0.4, Offset = 0, Color = RGB(140, 120, 100), Decay = RGB(60, 46, 36), Glare = 0, Haze = 2 },
		Grading = { Brightness = 0, Contrast = 0.22, Saturation = -0.05, TintColor = RGB(255, 240, 225) },
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.6 },
	},
	-- the furnace: hot orange, hazy with smoke
	IronworksFurnace = {
		Ambience = "ScrapAmbience",
		ClockTime = 0, Brightness = 1, Exposure = 0.3, Ambient = RGB(120, 80, 60), OutdoorAmbient = RGB(100, 70, 54),
		Atmosphere = { Density = 0.36, Offset = 0, Color = RGB(190, 120, 80), Decay = RGB(90, 40, 20), Glare = 0, Haze = 1.8 },
		Grading = { Brightness = 0, Contrast = 0.16, Saturation = 0.12, TintColor = RGB(255, 236, 220) },
		Bloom = { Intensity = 0.6, Size = 26, Threshold = 1.5 },
	},
}

-- a burst of particles at `position` (dust in the Pit, sparks in the Furnace)
local function burst(position: Vector3, texture: string, color: Color3, count: number, speed: number, size: number, sparks: boolean?)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(2, 1, 2)
	part.Position = position
	part.Parent = Workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(size, size * 2.4)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Lifetime = NumberRange.new(0.6, 1.4)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(80, 80)
	emitter.Acceleration = Vector3.new(0, -8, 0)
	if sparks then
		-- hot metal: bright, small, short-lived, thrown out and falling hard, with a flash
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new(size, 0)
		emitter.Transparency = NumberSequence.new(0, 0.6)
		emitter.Lifetime = NumberRange.new(0.35, 0.8)
		emitter.Acceleration = Vector3.new(0, -60, 0)
		emitter.Drag = 1.5
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.EmissionDirection = Enum.NormalId.Top
		local flash = Instance.new("PointLight")
		flash.Color = color
		flash.Range = 14
		flash.Brightness = 6
		flash.Parent = part
		TweenService:Create(flash, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	end
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(count)
	task.delay(2, function()
		part:Destroy()
	end)
end

-- A heavy blow, a knockdown, in this venue: the Pit's dust and its crowd, the Furnace's sparks
-- and clang, the Dome erupting.
local function venueImpact(data)
	local theme = ui.Theme
	local position = typeof(data.Position) == "Vector3" and data.Position or nil
	if not theme or not position then
		return
	end
	local big = data.KnockedDown or data.Heavy or data.GuardBroken
	if not big then
		return
	end
	local floor = position - Vector3.new(0, 2.5, 0)
	if theme == "UndergroundPit" then
		burst(floor, "rbxasset://textures/particles/smoke_main.dds", Color3.fromRGB(150, 130, 110), data.KnockedDown and 24 or 10, 8, 2)
		if data.KnockedDown then
			controllers.AudioController:Play("Victory")
		end
	elseif theme == "IronworksFurnace" then
		burst(position, "rbxasset://textures/particles/sparkles_main.dds", Color3.fromRGB(255, 180, 70), data.KnockedDown and 90 or 45, 30, 0.7, true)
		controllers.AudioController:Play("MetalClang", position)
	elseif theme == "ColossusDome" and data.KnockedDown then
		controllers.AudioController:Play("Victory") -- (the stadium erupts)
	end
end

-- THE ENTRANCES (round 1: DuelService "Intro", UndergroundService:RunEntrance). The server
-- walks the bodies; this films them on the same clock (data.StartAt, server time):
--   the sweep: the lights go down, the camera drifts over the crowd, the venue's name
--   each corner: the camera waits at ringside as the Nightmare walks out to it, the corner's
--   card comes up, and it performs its entrance (UGCosmetics) with the staging that goes
--   with it: the King's golden spotlight, the Machine's sparks, the Beast's slam
-- SPACE (or the button) asks to skip; when both fighters have, the server moves on.
local GOLD_LIGHT = RGB(255, 205, 90)

local function stopEntrance(restoreCamera: boolean)
	ui.IntroToken = (ui.IntroToken or 0) + 1
	RunService:UnbindFromRenderStep("UGEntranceCam")
	if ui.Spot then
		ui.Spot:Destroy()
		ui.Spot = nil
	end
	if ui.Key then
		ui.Key:Destroy()
		ui.Key = nil
	end
	if ui.Intro then
		ui.Intro.Visible = false
		ui.IntroSkip.Visible = false
	end
	if ui.IntroDim then
		TweenService:Create(ui.IntroDim, TweenInfo.new(0.8), { Brightness = 0, Contrast = 0 }):Play()
	end
	if ui.Cinematic and restoreCamera then
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
	end
	ui.Cinematic = false
end

-- the staging for an entrance, `t` seconds after it starts (once per moment)
local function stageEntrance(card, model: Model, fired, t: number)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local function once(key: string, at: number, fn)
		if t >= at and not fired[key] then
			fired[key] = true
			fn()
		end
	end
	local floor = root.Position - Vector3.new(0, root.Size.Y / 2 + 2, 0)
	if card.Intro == "Beast" then
		once("slam", 1.52, function()
			burst(floor, "rbxasset://textures/particles/smoke_main.dds", RGB(150, 135, 120), 28, 10, 2.4)
			controllers.EffectsController:Shake(0.3, 0.35)
		end)
	elseif card.Intro == "Machine" then
		for i, at in { 0.48, 0.84, 1.2, 1.5 } do
			once("lock" .. i, at, function()
				local part = (i == 1 and model:FindFirstChild("Head_Root")) or (i == 2 and model:FindFirstChild("RightArm_Upper")) or (i == 3 and model:FindFirstChild("LeftArm_Upper")) or root
				burst((part or root).Position, "rbxasset://textures/particles/sparkles_main.dds", RGB(140, 220, 255), 26, 18, 0.5, true)
				controllers.AudioController:Play("MetalClang", root.Position)
			end)
		end
	elseif card.Intro == "Champion" then
		once("crowd", 0.8, function()
			controllers.AudioController:Play("Victory")
		end)
	end
end

function UndergroundController:Intro(data)
	if not ui.Gui then
		return
	end
	stopEntrance(false)
	local token = ui.IntroToken
	if not ui.Intro then
		local frame = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromOffset(760, 190), BackgroundTransparency = 1, Visible = false, Parent = ui.Gui })
		UIKit.AutoScale(frame)
		ui.Intro = frame
		ui.IntroTop = UIKit.Label({ Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = C.SubText, TextStrokeTransparency = 0.3, MaxTextSize = 22, Parent = frame })
		ui.IntroMain = UIKit.Label({ Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 74), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextStrokeTransparency = 0.1, MaxTextSize = 70, Parent = frame })
		ui.IntroSub = UIKit.Label({ Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = C.Text, TextStrokeTransparency = 0.3, MaxTextSize = 24, Parent = frame })
		ui.IntroTag = UIKit.Label({ Position = UDim2.fromOffset(0, 146), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontSmall, TextColor3 = GOLD_LIGHT, TextStrokeTransparency = 0.3, MaxTextSize = 20, Parent = frame })
		ui.IntroDim = Instance.new("ColorCorrectionEffect")
		ui.IntroDim.Name = "UGIntroDim"
		ui.IntroDim.Parent = game:GetService("Lighting")
		ui.IntroSkip = UIKit.Button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Size = UDim2.fromOffset(260, 40), Text = "SKIP ENTRANCES  [SPACE]", MaxTextSize = 15, Visible = false, Parent = ui.Gui }, function()
			UndergroundController:SkipIntro()
		end)
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == Enum.KeyCode.Space and ui.Cinematic then
				UndergroundController:SkipIntro()
			end
		end)
	end
	ui.Skipped = false
	ui.IntroSkip.Text = "SKIP ENTRANCES  [SPACE]"
	ui.IntroSkip.Visible = true
	ui.Cinematic = true
	ui.EntranceShown = true
	controllers.LockOnController:Release()
	TweenService:Create(ui.IntroDim, TweenInfo.new(0.6), { Brightness = -0.22, Contrast = 0.18 }):Play()

	local center: Vector3 = typeof(data.Center) == "Vector3" and data.Center or Vector3.zero
	local sweep, beat, walk = data.Sweep or 2.6, data.Beat or 5.2, data.Walk or 2.8
	local cards = { data.Red or {}, data.Blue or {} }
	local function cardText(side: number)
		local f = cards[side]
		local bits = { "with " .. string.upper(f.Nightmare or "?") }
		if f.Record then
			table.insert(bits, f.Record)
		end
		if f.Rank then
			table.insert(bits, f.Rank)
		end
		return side == 1 and "IN THE RED CORNER" or "IN THE BLUE CORNER", string.upper(f.Name or "?"), table.concat(bits, "  ·  "),
			(f.Title and ("★ " .. f.Title .. "  ·  ") or "") .. (f.IntroName or "")
	end
	local lines = {
		{ data.Ranked and "RANKED  ·  NIGHTMARE UNDERGROUND" or "NIGHTMARE UNDERGROUND", string.upper(data.Arena or ""), data.Subtitle or "", "", RGB(255, 210, 90) },
		{ cardText(1) },
		{ cardText(2) },
	}
	lines[2][5], lines[3][5] = RED, BLUE
	local shown = 0
	local fired = { {}, {} }
	-- the sweep starts on the far side from the red corner's walk-out, turning toward it
	local redOut = cards[1].To and (cards[1].To.Position - center) * Vector3.new(1, 0, 1) or Vector3.xAxis
	local a0 = math.atan2(redOut.Z, redOut.X) + math.rad(110)
	local camera = Workspace.CurrentCamera
	controllers.AudioController:Play("Victory")

	RunService:BindToRenderStep("UGEntranceCam", Enum.RenderPriority.Last.Value + 3, function()
		if ui.IntroToken ~= token then
			return
		end
		local t = Workspace:GetServerTimeNow() - (data.StartAt or 0)
		local which = t < sweep and 1 or (t < sweep + beat and 2 or (t < sweep + beat * 2 and 3 or 4))
		if which >= 4 then
			-- (the server's countdown takes over in a moment: hold the last shot)
			return
		end
		-- the card for this beat
		if which ~= shown then
			shown = which
			local line = lines[which]
			ui.IntroTop.Text, ui.IntroMain.Text, ui.IntroSub.Text, ui.IntroTag.Text = line[1], line[2], line[3], line[4]
			ui.IntroMain.TextColor3 = line[5]
			ui.Intro.Visible = true
			local grow = ui.IntroMain:FindFirstChildOfClass("UIScale") or UIKit.New("UIScale", { Parent = ui.IntroMain })
			grow.Scale = 1.3
			TweenService:Create(grow, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			if ui.Spot then
				ui.Spot:Destroy()
				ui.Spot = nil
			end
		end
		camera.CameraType = Enum.CameraType.Scriptable
		if which == 1 then
			-- up over the ring, turning: first across the crowd in the stands, then settling down
			-- onto the ring
			local k = t / sweep
			local a = a0 - math.rad(80) * k
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local ahead = Vector3.new(math.cos(a - math.rad(150)), 0, math.sin(a - math.rad(150)))
			local settle = k * k * (3 - 2 * k)
			local crowd = center + ahead * 70 + Vector3.new(0, 16, 0)
			camera.FieldOfView = 64
			camera.CFrame = CFrame.lookAt(center + out * (28 + 10 * k) + Vector3.new(0, 20 - 6 * k, 0), crowd:Lerp(center + Vector3.new(0, 3, 0), settle))
			return
		end
		-- a corner's walk-out: the camera at ringside, the fighter walking out to it
		local side = which - 1
		local card = cards[side]
		local bt = t - sweep - (side - 1) * beat
		local model = card.Model
		local root = model and model.Parent and model:FindFirstChild("HumanoidRootPart")
		local stop: CFrame = card.To or CFrame.new(center)
		local look = stop.LookVector
		local right = stop.RightVector
		local k = math.clamp(bt / beat, 0, 1)
		-- (up and to one side of where it stops: over the barriers and the boards, looking down
		-- the walk at it coming out)
		-- (framed by its size: a hulking Nightmare needs the camera further back)
		if not card.Height and root then
			card.Height = math.clamp(math.max(model:GetExtentsSize().Y, (root.Position.Y - stop.Position.Y) * 1.8), 7, 16)
		end
		local h = card.Height or 8
		local eye = stop.Position + look * (h * 0.6 + 2.5 - k) + right * (h * 0.95 + 3.5 - 1.5 * k) + Vector3.new(0, h * 0.6 + 2.5 - k, 0)
		local focus = root and (root.Position + Vector3.new(0, h * 0.08, 0)) or (stop.Position + Vector3.new(0, 3, 0))
		camera.FieldOfView = 55
		camera.CFrame = CFrame.lookAt(eye, focus)
		-- a key light on whoever is walking out (the house lights are down), in its corner's
		-- colour from behind and white from the front
		if root then
			if not ui.Key then
				local key = Instance.new("Part")
				key.Anchored, key.CanCollide, key.CanQuery, key.CanTouch = true, false, false, false
				key.Transparency, key.Size = 1, Vector3.new(1, 1, 1)
				local front = Instance.new("PointLight")
				front.Name, front.Color, front.Brightness, front.Range = "Front", RGB(255, 240, 225), 0.9, 14
				front.Parent = key
				local rim = Instance.new("Attachment")
				rim.Parent = key
				local back = Instance.new("PointLight")
				back.Name, back.Brightness, back.Range = "Rim", 1.6, 12
				back.Parent = rim
				key.Parent = Workspace
				ui.Key = key
			end
			ui.Key.CFrame = CFrame.new(root.Position:Lerp(eye, 0.45) + Vector3.new(0, 1.5, 0))
			ui.Key.Attachment.WorldPosition = root.Position - look * 4 + Vector3.new(0, 4, 0)
			ui.Key.Attachment.Rim.Color = side == 1 and RED or BLUE
		end
		-- THE KING: a golden spotlight on it the whole way
		if card.Intro == "King" and root then
			if not ui.Spot then
				local spot = Instance.new("Part")
				spot.Anchored, spot.CanCollide, spot.CanQuery, spot.CanTouch = true, false, false, false
				spot.Transparency, spot.Size = 1, Vector3.new(1, 1, 1)
				local light = Instance.new("SpotLight")
				light.Face, light.Color, light.Brightness, light.Range, light.Angle = Enum.NormalId.Bottom, GOLD_LIGHT, 4, 34, 30
				light.Parent = spot
				spot.Parent = Workspace
				ui.Spot = spot
			end
			ui.Spot.CFrame = CFrame.new(root.Position + Vector3.new(0, 16, 0))
		end
		if bt >= walk and model then
			stageEntrance(card, model, fired[side], bt - walk)
		end
	end)
end

function UndergroundController:SkipIntro()
	if not ui.Cinematic or ui.Skipped then
		return
	end
	ui.Skipped = true
	ui.IntroSkip.Text = "SKIPPING  ·  waiting for the other fighter"
	controllers.PvPController:Request("UGSkipIntro")
end

-- the other fighter asked too / one of you did ("UGIntroSkip")
function UndergroundController:IntroSkipCount(data)
	if ui.IntroSkip and ui.Cinematic and type(data) == "table" then
		ui.IntroSkip.Text = ("SKIP  ·  %d / %d ready"):format(data.Count or 0, data.Needed or 2)
	end
end

-- Round 1's countdown, after the entrances: the face-off. From the side of the line between
-- the two corners, both fighters in the shot, for a moment before the fight camera.
local function faceOff()
	local camera = Workspace.CurrentCamera
	local started = os.clock()
	ui.Cinematic = true
	local token = ui.IntroToken
	local holdFrom: number? = nil
	RunService:BindToRenderStep("UGEntranceCam", Enum.RenderPriority.Last.Value + 3, function()
		-- (the countdown puts fresh bodies in the corners as it starts: wait for them to arrive)
		local mine, theirs = fighters()
		local a = mine and mine:FindFirstChild("HumanoidRootPart")
		local b = theirs and theirs:FindFirstChild("HumanoidRootPart")
		if a and b and not holdFrom then
			holdFrom = os.clock()
		end
		local k = holdFrom and (os.clock() - holdFrom) / 2.1 or 0
		if k >= 1 or ui.IntroToken ~= token or (not holdFrom and os.clock() - started > 1.5) then
			RunService:UnbindFromRenderStep("UGEntranceCam")
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			ui.Cinematic = false
			return
		end
		if not a or not b then
			return
		end
		local mid = (a.Position + b.Position) / 2
		local across = (b.Position - a.Position) * Vector3.new(1, 0, 1)
		across = across.Magnitude > 0.1 and across.Unit or Vector3.xAxis
		local side = across:Cross(Vector3.yAxis)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 50
		camera.CFrame = CFrame.lookAt(mid + side * (19 - 3 * k) + Vector3.new(0, 3.5, 0), mid + Vector3.new(0, 2, 0))
	end)
end

function UndergroundController:ApplyState(data)
	if not ui.Gui then
		return
	end
	if data.State == "None" or data.Mode ~= "Underground" then
		if ui.Cinematic then
			stopEntrance(true)
		end
		if state then
			controllers.HUDController:SetUndergroundMode(false)
		end
		if ui.Theme then
			ui.Theme = nil
			controllers.WorldController:ResetRegion() -- (the world's own lighting again)
		end
		state = nil
		ui.Gui.Enabled = false
		-- (back at the Forge: the results and the round card go with the fight)
		if data.State == "None" and ui.ResultsGui then
			ui.ResultsToken = (ui.ResultsToken or 0) + 1
			ui.ResultsGui.Enabled = false
			ui.Card.Visible = false
		end
		return
	end
	controllers.HUDController:SetUndergroundMode(true)
	-- the venue's own lighting and sound (World/UndergroundArenas)
	if data.ArenaTheme and data.ArenaTheme ~= ui.Theme and THEME_LOOKS[data.ArenaTheme] then
		ui.Theme = data.ArenaTheme
		local look = THEME_LOOKS[data.ArenaTheme]
		controllers.WorldController:ApplyLook(look, look.Ambience)
	end
	if not state or state.Round ~= data.Round then
		ui.RoundStartedAt = os.clock()
	end
	if not state then
		ui.ResultsGui.Enabled = false -- (a rematch: the last fight's results are done with)
	end
	-- the bell at FIGHT; the card comes down when the next round is being set up
	if data.State == "Live" and (not state or state.State ~= "Live") then
		controllers.AudioController:Play("Defeat")
	end
	if data.State ~= "RoundOver" and data.State ~= "Ended" then
		ui.Card.Visible = false
	end
	-- the entrances end when the server moves on (their time is up, or both skipped); round
	-- 1's countdown opens on the face-off
	if data.State ~= "Intro" and ui.Cinematic and (not state or state.State == "Intro") then
		stopEntrance(true)
	end
	if data.State == "Countdown" and data.Round == 1 and ui.EntranceShown then
		ui.EntranceShown = false
		faceOff()
	end
	state = data
	ui.Gui.Enabled = true
	ui.QueueGui.Enabled = false
	local needed = math.ceil((data.BestOf or 3) / 2)
	ui.Me.Name.Text = string.upper(data.MyName or localPlayer.DisplayName)
	ui.Them.Name.Text = string.upper(data.OpponentName or "?")
	ui.Me.Pips.Text = pips(data.MyScore or 0, needed)
	ui.Them.Pips.Text = pips(data.OpponentScore or 0, needed)
	ui.Round.Text = ("%sROUND %d / %d"):format(data.UGRanked and "RANKED · " or "", math.max(data.Round or 1, 1), data.BestOf or 3)
	ui.Score.Text = ("%d — %d"):format(data.MyScore or 0, data.OpponentScore or 0)
end

function UndergroundController:SetQueue(data)
	if not ui.QueueGui then
		return
	end
	local searching = data.Searching == true and not state
	ui.QueueGui.Enabled = searching
	if searching then
		ui.QueueText.Text = ("NIGHTMARE UNDERGROUND  ·  %ssearching for an opponent  ·  %d in the queue"):format(data.Kind == "Ranked" and "RANKED  ·  " or "", data.Waiting or 1)
	end
end

local function updatePlate(p, model: Model?)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		UIKit.SetBar(p.Health, 0, 1)
		p.Sub.Text = "—"
		return
	end
	UIKit.SetBar(p.Health, math.max(humanoid.Health, 0), humanoid.MaxHealth)
	local guard = model:GetAttribute("GuardLevel") or Config.Block.Max
	UIKit.SetBar(p.Guard, guard, Config.Block.Max)
	p.Guard.Fill.BackgroundColor3 = model:GetAttribute("GuardBroken") and C.Bad or (guard < Config.Block.CrackAt and C.Warn or RGB(235, 225, 200))
	local stamina = Config.Underground.Fight.Stamina
	UIKit.SetBar(p.Stamina, model:GetAttribute("UGStamina") or stamina.Max, stamina.Max)
	p.Stamina.Fill.BackgroundColor3 = model:GetAttribute("UGGassed") and C.Bad or RGB(255, 200, 60)
	local name = model:GetAttribute("NightmareName") or "Nightmare"
	local archetype = model:GetAttribute("Archetype") or ""
	local extra = ""
	local rank = model:GetAttribute("UGRankText") -- (a ranked fight: their division and rating)
	local title = model:GetAttribute("UGTitle")
	if rank then
		extra ..= "  ·  " .. rank
	end
	if title then
		extra ..= "  ·  ★ " .. title
	end
	p.Sub.Text = ("%s  ·  %s%s"):format(string.upper(name), string.upper(archetype), extra)
end

function UndergroundController:UpdateFrame()
	if not state then
		return
	end
	local mine, theirs = fighters()
	updatePlate(ui.Me, mine)
	updatePlate(ui.Them, theirs)

	-- a fighting game's camera: locked on to the other fighter from the corner onwards (Z lets
	-- go; it locks again next round)
	local lock = controllers.LockOnController
	local theirHumanoid = theirs and theirs:FindFirstChildOfClass("Humanoid")
	if (state.State == "Live" or state.State == "Countdown") and controllers.PossessionController:IsBound()
		and theirHumanoid and theirHumanoid.Health > 0 and not lock:IsLocked()
		and lock:ReleasedByPlayerAt() < (ui.RoundStartedAt or 0) then
		lock:Lock(theirs)
	end

	-- the clock
	local left = math.max(0, (state.PhaseEndsAt or 0) - Workspace:GetServerTimeNow())
	local phase = state.State
	if phase == "Live" then
		ui.Timer.Text = ("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60))
		ui.Timer.TextColor3 = left <= 10 and C.Bad or C.Text
	elseif phase == "Countdown" then
		ui.Timer.Text = tostring(math.max(1, math.ceil(left)))
		ui.Timer.TextColor3 = C.Warn
	elseif phase == "Prep" then
		ui.Timer.Text = ("PICK %d"):format(math.ceil(left))
		ui.Timer.TextColor3 = C.SubText
	elseif phase == "Intro" then
		ui.Timer.Text = "VS"
		ui.Timer.TextColor3 = C.Warn
	else
		ui.Timer.Text = "—"
		ui.Timer.TextColor3 = C.SubText
	end

	-- your stance
	local status
	if mine and mine:GetAttribute("GuardBroken") then
		status = "GUARD BROKEN"
	elseif mine and mine:GetAttribute("Ragdolled") then
		status = "DOWN!"
	elseif mine and mine:GetAttribute("Guarding") then
		status = mine:GetAttribute("GuardLow") and "LOW GUARD (body)" or "HIGH GUARD (head)"
	else
		status = phase == "Live" and "FIGHTING" or (phase == "Countdown" and "IN YOUR CORNER" or (phase == "Intro" and "THE ENTRANCES" or "BETWEEN ROUNDS"))
	end
	if mine and mine:GetAttribute("UGGassed") then
		status ..= "  ·  GASSED"
	end
	ui.Stance.Text = ("STANCE  ·  %s"):format(status)
	local touch = UIKit.IsTouchOnly()
	local pad = not touch and UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
	local L, H = touch and "ATK" or pad and "R2" or "LMB", touch and "KICK" or pad and "X" or "RMB"
	local G, D = touch and "GUARD" or pad and "L2" or "Ctrl", touch and "DIVE" or pad and "B" or "Shift"
	-- (the strings, Config.Underground.Fight Strings: presses of one button chain, the power
	-- button finishes)
	ui.Controls.Text = ("%s ×1-4: jab, cross, hook, uppercut  ·  %s: overhand\n%s then %s: liver  ·  ×2 then %s: overhand  ·  ×3 then %s: LAUNCHER\n%s: guard (+back: low)  ·  just as they swing: PARRY  ·  %s+dir: slip\nRULES  best of 3  ·  the bell: judge decides  ·  3 knockdowns in a round = TKO")
		:format(L, H, L, H, H, H, G, D)
end

-- A callout from the server (UndergroundFightService): under the plate of the fighter it's
-- about; your own combos also big in the middle.
local CALLOUT_COLORS = { Good = RGB(120, 255, 150), Bad = RGB(255, 90, 90), Combo = RGB(255, 210, 90), Info = RGB(220, 220, 230) }
function UndergroundController:Flash(p, text: string, color: Color3)
	p.Flash.Text = text
	p.Flash.TextColor3 = color
	p.Flash.TextTransparency = 0
	p.Flash.Visible = true
	local token = (p.FlashToken or 0) + 1
	p.FlashToken = token
	task.delay(1.2, function()
		if p.FlashToken == token then
			TweenService:Create(p.Flash, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		end
	end)
end

local function onCallout(data)
	if not state or typeof(data.Target) ~= "Instance" or type(data.Text) ~= "string" then
		return
	end
	local mine, theirs = fighters()
	local color = CALLOUT_COLORS[data.Kind] or C.Warn
	if data.Target == mine then
		UndergroundController:Flash(ui.Me, data.Text, color)
		if data.Kind == "Combo" or data.Text == "COUNTER!" or data.Text == "PARRY!" then
			UndergroundController:Callout(data.Text, chain.Count >= 2 and ("%d HIT COMBO"):format(chain.Count) or nil, color)
		end
	elseif data.Target == theirs then
		UndergroundController:Flash(ui.Them, data.Text, color)
	end
end

-- A blow you landed on the other fighter: the callout says what it did.
local function onFeedback(kind: string, data)
	if kind == "UGCallout" and type(data) == "table" then
		onCallout(data)
		return
	end
	if state and type(data) == "table" and (kind == "Damage" or kind == "KnockedDown") then
		venueImpact(data)
	end
	if not state or kind ~= "Damage" or type(data) ~= "table" then
		return
	end
	local mine, theirs = fighters()
	if not mine or data.Attacker ~= mine or data.Target ~= theirs then
		return
	end
	local now = os.clock()
	chain.Count = (now - chain.At <= 1.4) and chain.Count + 1 or 1
	chain.At = now
	if data.KnockedDown then
		UndergroundController:Callout("KNOCKDOWN!", nil, C.Bad)
	elseif data.GuardBroken then
		UndergroundController:Callout("GUARD BREAK", nil, C.Warn)
	elseif data.Heavy and not data.Guarded then
		UndergroundController:Callout("HEAVY IMPACT", chain.Count >= 3 and ("%d HIT COMBO"):format(chain.Count) or nil, C.Warn)
	elseif chain.Count >= 3 then
		UndergroundController:Callout(("%d HIT COMBO"):format(chain.Count), nil, C.Text)
	end
end

-- The fight camera sits behind your Nightmare, which in your corner puts the corner post (the
-- Pit's 15-stud cage post, the Furnace's machinery) between the lens and the fight. Anything of
-- the arena's between the camera and your Nightmare goes see-through while it's in the way.
local FADE = 0.8
local faded: { [BasePart]: boolean } = {}

local function updateCameraFade()
	local hit: { [BasePart]: boolean } = {}
	local camera = Workspace.CurrentCamera
	local subject = camera and camera.CameraSubject
	local arenas = Workspace:FindFirstChild("UndergroundArenas")
	-- (not while a cinematic camera is filming: the entrances, the face-off, a knockout)
	if state and not ui.Cinematic and not ui.KOCam and arenas and subject and subject:IsA("Humanoid") and subject.RootPart then
		local root = subject.RootPart.Position
		local ignore = { subject.Parent :: Instance }
		local character = Players.LocalPlayer.Character
		if character then
			table.insert(ignore, character)
		end
		-- every part on the lines from the lens to your Nightmare's hips, chest and head
		local targets = { root, root + Vector3.new(0, 2, 0), root + Vector3.new(0, 4, 0) }
		for _, part in camera:GetPartsObscuringTarget(targets, ignore) do
			if part.Transparency < 1 and part:IsDescendantOf(arenas) then
				hit[part] = true
			end
		end
	end
	for part in faded do
		if not hit[part] then
			part.LocalTransparencyModifier = 0
			faded[part] = nil
		end
	end
	for part in hit do
		part.LocalTransparencyModifier = FADE
		faded[part] = true
	end
end

function UndergroundController:Start()
	self:BuildGui()
	Net.Get("CombatFeedback").OnClientEvent:Connect(onFeedback)
	RunService.RenderStepped:Connect(function()
		self:UpdateFrame()
	end)
	-- (after every camera script: lock-on and the shake move the lens at Camera + 1 and + 2)
	RunService:BindToRenderStep("UGCameraFade", Enum.RenderPriority.Last.Value, updateCameraFade)
end

return UndergroundController
