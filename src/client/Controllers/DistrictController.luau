--[[
	DistrictController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/DistrictController

	Client side of NIGHTMARE UNDERGROUND — THE FIGHTING DISTRICT (World/District):
	  * the advertising screens on the facade (tag UGScreen): cycling fight-night ads
	  * the PRIVATE DUEL station (prompt UGPrivateDuel): everyone else in the server, with a
	    CHALLENGE button each (DuelRequest "UGChallenge"; they answer the usual duel popup)
	  * the FIGHTER STATS terminal (prompt UGStats): your Underground record and career numbers
	    (profile.Underground)
	The rest of the district's stations are other controllers' prompts (UndergroundQueue,
	OpenWorkshop) or the server's (UGRankedQueue, UGPractice).
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UGRank = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("UGRankDefinitions"))

local DistrictController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local RGB = Color3.fromRGB
local RED, GOLD, STEEL = RGB(255, 60, 70), RGB(255, 200, 80), RGB(18, 16, 20)

local controllers
local ui = {}

function DistrictController:Init(registry)
	controllers = registry
end

------------------------------------------------------------------------------------------
-- The advertising screens
------------------------------------------------------------------------------------------
local ADS = {
	{ "TONIGHT", "TWO NIGHTMARES ENTER\nONE WALKS OUT", RED },
	{ "YOU ARE YOUR NIGHTMARE", "No Handler. No commands.\nYour hands, its fists.", RGB(255, 235, 235) },
	{ "BEST OF 3", "KNOCKOUTS · TKOs · THE JUDGE'S CARD", GOLD },
	{ "RANKED SEASON 1", "Rust → Iron → Steel → Chrome\n→ Titanium → Mythic → LEGEND", RGB(150, 210, 255) },
	{ "IRONJAW  31-0", "Can anyone take the belt?", RED },
	{ "PARRY · SLIP · COUNTER", "Read them. Make them miss.\nMake them pay.", RGB(120, 255, 150) },
}

local function startScreens()
	local screens = {}
	local function add(panel: Instance)
		local gui = panel:FindFirstChild("Screen")
		if not gui or screens[panel] then
			return
		end
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 0.42)
		title.Position = UDim2.fromScale(0, 0.06)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.Parent = gui
		local body = Instance.new("TextLabel")
		body.BackgroundTransparency = 1
		body.Size = UDim2.fromScale(0.94, 0.44)
		body.Position = UDim2.fromScale(0.03, 0.52)
		body.Font = Enum.Font.GothamBold
		body.TextScaled = true
		body.TextColor3 = RGB(230, 225, 232)
		body.Parent = gui
		screens[panel] = { Title = title, Body = body, Offset = math.random(0, #ADS - 1) }
	end
	for _, panel in CollectionService:GetTagged("UGScreen") do
		add(panel)
	end
	CollectionService:GetInstanceAddedSignal("UGScreen"):Connect(add)
	task.spawn(function()
		local index = 0
		while true do
			index += 1
			for panel, screen in screens do
				if not panel.Parent then
					screens[panel] = nil
					continue
				end
				local ad = ADS[(index + screen.Offset) % #ADS + 1]
				screen.Title.Text = ad[1]
				screen.Title.TextColor3 = ad[3]
				screen.Body.Text = ad[2]
				screen.Title.TextTransparency = 1
				TweenService:Create(screen.Title, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
			end
			task.wait(4.5)
		end
	end)
end

------------------------------------------------------------------------------------------
-- The station panels
------------------------------------------------------------------------------------------
local function panel(title: string, color: Color3, size: Vector2?)
	local gui = UIKit.New("ScreenGui", { Name = "DistrictGui", ResetOnSpawn = false, DisplayOrder = 25, Enabled = false, Parent = localPlayer:WaitForChild("PlayerGui") })
	local frame = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size and size.X or 460, size and size.Y or 420), BackgroundColor3 = STEEL, BackgroundTransparency = 0.04, Parent = gui }, { UIKit.Corner(8), UIKit.Stroke(color, 2, 0.1) })
	UIKit.AutoScale(frame)
	local heading = UIKit.Label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -80, 0, 34), Font = UIKit.FontDisplay, TextColor3 = color, MaxTextSize = 30, Text = title, Parent = frame })
	UIKit.Button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(40, 32), Text = "X", MaxTextSize = 18, Parent = frame }, function()
		gui.Enabled = false
	end)
	local body = UIKit.New("Frame", { Position = UDim2.fromOffset(16, 52), Size = UDim2.new(1, -32, 1, -68), BackgroundTransparency = 1, Parent = frame })
	return gui, body, heading
end

-- PRIVATE DUEL: everyone else here, a CHALLENGE button each.
function DistrictController:OpenDuel()
	if not ui.Duel then
		local gui, body = panel("PRIVATE DUEL", RGB(200, 120, 255))
		ui.Duel = gui
		ui.DuelNote = UIKit.Label({ Size = UDim2.new(1, 0, 0, 40), TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 13, TextWrapped = true, Parent = body,
			Text = "Challenge someone in this server to a NIGHTMARE UNDERGROUND fight: 1v1, best of 3, you both fight AS your Nightmares. Never ranked." })
		ui.DuelList = UIKit.New("ScrollingFrame", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -76), BackgroundTransparency = 1, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = body }, { UIKit.List(6) })
		ui.DuelMessage = UIKit.Label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 24), TextColor3 = C.Warn, MaxTextSize = 14, Parent = body })
	end
	for _, child in ui.DuelList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local count = 0
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			count += 1
			local row = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = C.PanelLight, LayoutOrder = count, Parent = ui.DuelList }, { UIKit.Corner(6) })
			UIKit.Label({ Text = player.DisplayName, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.6, -10, 1, 0), MaxTextSize = 16, Parent = row })
			UIKit.Button({ Text = "CHALLENGE", Position = UDim2.new(0.62, 0, 0.14, 0), Size = UDim2.new(0.36, 0, 0.72, 0), BackgroundColor3 = RGB(140, 60, 190), MaxTextSize = 14, Parent = row }, function()
				ui.DuelMessage.Text = "Sending..."
				local result = controllers.PvPController:Request("UGChallenge", player.UserId)
				ui.DuelMessage.Text = result.Ok and ("Challenge sent to %s: waiting for them to accept."):format(player.DisplayName) or (result.Error or "Couldn't send.")
				ui.DuelMessage.TextColor3 = result.Ok and C.Good or C.Bad
			end)
		end
	end
	if count == 0 then
		UIKit.Label({ Text = "Nobody else is here yet.", Size = UDim2.new(1, -8, 0, 40), TextColor3 = C.SubText, MaxTextSize = 15, Parent = ui.DuelList })
	end
	ui.DuelMessage.Text = ""
	ui.Duel.Enabled = true
end

-- FIGHTER STATS: your record and career numbers.
local STAT_LINES = {
	{ "FIGHTS", "Fights" }, { "WINS", "Wins" }, { "LOSSES", "Losses" }, { "DRAWS", "Draws" },
	{ "KNOCKOUTS", "KOs" }, { "TKOs", "TKOs" }, { "KNOCKDOWNS SCORED", "Knockdowns" },
	{ "STRIKES LANDED", "Landed" }, { "STRIKES THROWN", "Thrown" }, { "POWER SHOTS LANDED", "Power" },
	{ "COMBOS", "Combos" }, { "COUNTERS", "Counters" }, { "PARRIES", "Parries" }, { "SLIPS", "Slips" },
	{ "DAMAGE DEALT", "Damage" }, { "RANKED FIGHTS", "RankedFights" },
}

-- the ranked card's badge: "◆◆◆ STEEL" in the division's colour
local function badgeText(division): string
	return ("%s  %s"):format(division.Badge, division.Name)
end

function DistrictController:OpenStats()
	if not ui.Stats then
		local gui, body = panel("FIGHTER STATS", RGB(120, 220, 255), Vector2.new(820, 470))
		ui.Stats = gui
		-- LEFT: the career numbers
		local left = UIKit.New("Frame", { Size = UDim2.new(0, 360, 1, 0), BackgroundTransparency = 1, Parent = body })
		UIKit.Label({ Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.SubText, MaxTextSize = 13, Text = "CAREER", Parent = left })
		ui.StatRows = {}
		for i, line in STAT_LINES do
			local y = 22 + (i - 1) * 20
			if i % 2 == 1 then
				UIKit.New("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = RGB(255, 255, 255), BackgroundTransparency = 0.95, BorderSizePixel = 0, Parent = left })
			end
			UIKit.Label({ Position = UDim2.fromOffset(8, y), Size = UDim2.new(0.6, 0, 0, 20), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 13, Text = line[1], Parent = left })
			ui.StatRows[i] = UIKit.Label({ Position = UDim2.new(0.6, 0, 0, y), Size = UDim2.new(0.4, -8, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, Font = UIKit.FontSmall, TextColor3 = C.Text, MaxTextSize = 14, Parent = left })
		end
		ui.StatAccuracy = UIKit.Label({ Position = UDim2.fromOffset(0, 22 + #STAT_LINES * 20 + 4), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = GOLD, MaxTextSize = 15, Parent = left })

		-- RIGHT: the ranked league card
		local right = UIKit.New("Frame", { Position = UDim2.fromOffset(380, 0), Size = UDim2.new(1, -380, 1, 0), BackgroundTransparency = 1, Parent = body })
		ui.RankSeason = UIKit.Label({ Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.SubText, MaxTextSize = 13, Parent = right })
		ui.RankBadge = UIKit.Label({ Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 40), Font = UIKit.FontDisplay, MaxTextSize = 36, Parent = right })
		ui.RankRating = UIKit.Label({ Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 20), Font = UIKit.FontSmall, TextColor3 = C.Text, MaxTextSize = 16, Parent = right })
		ui.RankBar = UIKit.Bar({ Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 12), Color = GOLD, Parent = right })
		ui.RankBar.Label.Visible = false
		ui.RankNext = UIKit.Label({ Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 0, 18), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 12, Parent = right })
		ui.RankRecord = UIKit.Label({ Position = UDim2.fromOffset(0, 124), Size = UDim2.new(1, 0, 0, 20), Font = UIKit.FontSmall, TextColor3 = C.Text, MaxTextSize = 14, Parent = right })
		UIKit.Label({ Position = UDim2.fromOffset(0, 150), Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.SubText, MaxTextSize = 12, Text = "RECENT RANKED FIGHTS", Parent = right })
		ui.RankHistory = {}
		for i = 1, 6 do
			ui.RankHistory[i] = UIKit.Label({ Position = UDim2.fromOffset(0, 168 + (i - 1) * 18), Size = UDim2.new(1, 0, 0, 18), Font = UIKit.FontBody, TextColor3 = C.Text, MaxTextSize = 12, Parent = right })
		end
		UIKit.Label({ Position = UDim2.fromOffset(0, 282), Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.SubText, MaxTextSize = 12, Text = "YOUR TITLES  (shown over your head and on your fight plate)", Parent = right })
		ui.TitleList = UIKit.New("ScrollingFrame", { Position = UDim2.fromOffset(0, 302), Size = UDim2.new(1, 0, 1, -302), BackgroundTransparency = 1, ScrollBarThickness = 5, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = right }, { UIKit.List(4) })
	end
	local profile = controllers.ClientState.Profile
	local ug = profile and profile.Underground or {}
	for i, line in STAT_LINES do
		ui.StatRows[i].Text = tostring(math.floor((ug[line[2]] or 0) + 0.5))
	end
	local thrown, landed = ug.Thrown or 0, ug.Landed or 0
	-- (records from before the career numbers were kept have wins and losses but no Fights)
	local decided = (ug.Wins or 0) + (ug.Losses or 0) + (ug.Draws or 0)
	ui.StatRows[1].Text = tostring(math.max(ug.Fights or 0, decided))
	local winRate = decided > 0 and ("WIN RATE %d%%"):format(math.floor((ug.Wins or 0) / decided * 100 + 0.5)) or nil
	if thrown > 0 then
		ui.StatAccuracy.Text = ("ACCURACY %d%%%s"):format(math.floor(math.min(1, landed / thrown) * 100 + 0.5), winRate and ("  ·  " .. winRate) or "")
	else
		ui.StatAccuracy.Text = winRate or "No fights yet: the terminals are on the left wall."
	end

	-- the ranked card
	local ranked = profile and profile.UGRanked or UGRank.NewRecord()
	local division = UGRank.ById[ranked.Division] or UGRank.DivisionFor(ranked.Rating or UGRank.StartRating)
	local seasonLeft = math.max(0, UGRank.Season.EndsAt - os.time())
	ui.RankSeason.Text = ("RANKED LEAGUE  ·  %s  ·  %d days left"):format(UGRank.Season.Name, math.floor(seasonLeft / 86400))
	if (ranked.Placements or 0) > 0 then
		local total = math.max(ranked.PlacementsTotal or UGRank.Placements, ranked.Placements)
		ui.RankBadge.Text = ("PLACEMENTS  %d / %d"):format(total - ranked.Placements, total)
		ui.RankBadge.TextColor3 = C.Text
		ui.RankRating.Text = ("%d placement fight%s left before your division shows"):format(ranked.Placements, ranked.Placements == 1 and "" or "s")
		UIKit.SetBar(ui.RankBar, total - ranked.Placements, total)
		ui.RankBar.Fill.BackgroundColor3 = GOLD
		ui.RankNext.Text = "Placement fights move your rating twice as far."
	else
		ui.RankBadge.Text = badgeText(division)
		ui.RankBadge.TextColor3 = division.Color
		ui.RankRating.Text = ("RATING %d   ·   PEAK %d"):format(ranked.Rating, ranked.Peak or ranked.Rating)
		local progress, nextDivision = UGRank.Progress(ranked.Rating, division.Id)
		UIKit.SetBar(ui.RankBar, progress, 1)
		ui.RankBar.Fill.BackgroundColor3 = division.Color
		ui.RankNext.Text = nextDivision and ("%d to %s (%d)"):format(nextDivision.Min - ranked.Rating, nextDivision.Name, nextDivision.Min) or "The top of the ladder."
	end
	ui.RankRecord.Text = ("%d W  ·  %d L  ·  %d D    STREAK %d  ·  BEST %d"):format(ranked.Wins or 0, ranked.Losses or 0, ranked.Draws or 0, ranked.Streak or 0, ranked.BestStreak or 0)
	for i, label in ui.RankHistory do
		local fight = ranked.History and ranked.History[i]
		if fight then
			label.Text = ("%s  vs %s   %s%d  →  %d"):format(fight.Result == "Win" and "WON" or fight.Result == "Loss" and "LOST" or "DREW", tostring(fight.Opponent), (fight.Delta or 0) >= 0 and "+" or "", fight.Delta or 0, fight.Rating or 0)
			label.TextColor3 = fight.Result == "Win" and RGB(120, 255, 150) or fight.Result == "Loss" and RGB(255, 110, 110) or C.Text
		else
			label.Text = i == 1 and "None yet: the gold terminals start a ranked fight." or ""
			label.TextColor3 = C.SubText
		end
	end
	-- the titles you've earned: click one to wear it, click it again to take it off
	for _, child in ui.TitleList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local owned = {}
	for id in ranked.Titles or {} do
		local title = UGRank.TitleFor(id)
		if title then
			table.insert(owned, title)
		end
	end
	table.sort(owned, function(a, b)
		return a.Rank > b.Rank
	end)
	for index, title in owned do
		local wearing = ranked.Title == title.Id
		UIKit.Button({ LayoutOrder = index, Size = UDim2.new(1, -8, 0, 30), BackgroundColor3 = wearing and RGB(60, 52, 30) or C.PanelLight, TextColor3 = title.Color, MaxTextSize = 14,
			Text = (wearing and "✓ " or "") .. title.Text, Parent = ui.TitleList }, function()
			controllers.PvPController:Request("UGTitle", (not wearing) and title.Id or nil)
			task.delay(0.5, function()
				self:OpenStats()
			end)
		end)
	end
	if #owned == 0 then
		UIKit.Label({ Size = UDim2.new(1, -8, 0, 36), TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 12, TextWrapped = true, Parent = ui.TitleList,
			Text = "None yet. Each season ends with a title for the division you finished in; the top 20 and the champion get more." })
	end
	ui.Stats.Enabled = true
end

-- A fight is starting: the station panels get out of the way.
function DistrictController:CloseAll()
	for _, gui in { ui.Duel, ui.Stats } do
		if gui then
			gui.Enabled = false
		end
	end
end

function DistrictController:Start()
	startScreens()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "UGPrivateDuel" then
			self:OpenDuel()
		elseif prompt.Name == "UGStats" then
			self:OpenStats()
		end
	end)
end

return DistrictController
