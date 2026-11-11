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
	local pill = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(420, 40), BackgroundColor3 = STEEL, BackgroundTransparency = 0.1, Parent = queueGui }, { UIKit.Corner(20), UIKit.Stroke(RED, 2, 0.2) })
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
			-- between the two of them, drifting onto the one on the floor
			local between = winnerRoot.Position:Lerp(loserRoot.Position, 0.65)
			focus = focus:Lerp(Vector3.new(between.X, floor - 0.5, between.Z), 0.12)
			local distance = 17 - 4 * k
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = 52
			camera.CFrame = CFrame.lookAt(focus + side * distance - away * 3 + Vector3.new(0, 4.5 - 1.5 * k, 0), focus)
		end
		if k >= 1 then
			RunService:UnbindFromRenderStep("UGKnockoutCamera")
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
	ui.ResultsRewards = UIKit.Label({ Position = UDim2.fromOffset(x, below), Size = UDim2.fromOffset(w, 36), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Warn, MaxTextSize = 15, Parent = panel })

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
	ui.ResultsMethod.Text = method
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

function UndergroundController:ApplyState(data)
	if not ui.Gui then
		return
	end
	if data.State == "None" or data.Mode ~= "Underground" then
		if state then
			controllers.HUDController:SetUndergroundMode(false)
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
	state = data
	ui.Gui.Enabled = true
	ui.QueueGui.Enabled = false
	local needed = math.ceil((data.BestOf or 3) / 2)
	ui.Me.Name.Text = string.upper(data.MyName or localPlayer.DisplayName)
	ui.Them.Name.Text = string.upper(data.OpponentName or "?")
	ui.Me.Pips.Text = pips(data.MyScore or 0, needed)
	ui.Them.Pips.Text = pips(data.OpponentScore or 0, needed)
	ui.Round.Text = ("ROUND %d / %d"):format(math.max(data.Round or 1, 1), data.BestOf or 3)
	ui.Score.Text = ("%d — %d"):format(data.MyScore or 0, data.OpponentScore or 0)
end

function UndergroundController:SetQueue(data)
	if not ui.QueueGui then
		return
	end
	local searching = data.Searching == true and not state
	ui.QueueGui.Enabled = searching
	if searching then
		ui.QueueText.Text = ("NIGHTMARE UNDERGROUND  ·  searching for an opponent  ·  %d in the queue"):format(data.Waiting or 1)
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
	p.Sub.Text = ("%s  ·  %s"):format(string.upper(name), string.upper(archetype))
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
		status = phase == "Live" and "FIGHTING" or (phase == "Countdown" and "IN YOUR CORNER" or "BETWEEN ROUNDS")
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

function UndergroundController:Start()
	self:BuildGui()
	Net.Get("CombatFeedback").OnClientEvent:Connect(onFeedback)
	RunService.RenderStepped:Connect(function()
		self:UpdateFrame()
	end)
end

return UndergroundController
