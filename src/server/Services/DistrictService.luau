--[[
	DistrictService  (ModuleScript)
	Location: ServerScriptService/Server/Services/DistrictService

	NIGHTMARE UNDERGROUND — THE FIGHTING DISTRICT (built by World/District): what runs in it.
	  * the RANKED terminals (prompt UGRankedQueue): the Underground's ranked queue
	    (the CASUAL ones are UndergroundService's own "UndergroundQueue" prompt)
	  * the PRACTICE ARENA door (UGPractice): over to the Training Arena in the Forge
	  * the LIVE NOW screens (UGLiveBoard): every Underground fight going on, round and score
	  * the LEADERBOARD (UGLeaderboard): most Underground wins / knockouts
	    (LeaderboardService: global boards, or this server's when those can't be reached)
	  * the training corner's dummies (UGDummySpot: TrainingService's Training Dummy)
	The private duel station, the stats terminal and the loadout station are client-side
	(DistrictController / WorkshopController).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))
local UGRank = require(Shared:WaitForChild("UGRankDefinitions"))
local RANKED = "UGRating_S" .. UGRank.Season.Id -- (LeaderboardService: this season's ranked board)

local DistrictService = {}

local RGB = Color3.fromRGB
local RED, BLUE, GOLD = RGB(255, 60, 70), RGB(80, 150, 255), RGB(255, 200, 80)

local function label(parent: Instance, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = RGB(236, 232, 240)
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

function DistrictService:Init(services)
	self.Services = services
end

------------------------------------------------------------------------------------------
-- The screens
------------------------------------------------------------------------------------------
-- LIVE NOW: up to four fights, one line each.
function DistrictService:BuildLive(panel: BasePart)
	local gui = panel:FindFirstChild("Screen")
	if not gui then
		return nil
	end
	label(gui, { Text = "LIVE NOW  ·  NIGHTMARE UNDERGROUND", Size = UDim2.fromScale(1, 0.2), Font = Enum.Font.GothamBlack, TextColor3 = RED })
	local rows = {}
	for i = 1, 4 do
		rows[i] = label(gui, { Position = UDim2.fromScale(0.03, 0.22 + (i - 1) * 0.19), Size = UDim2.fromScale(0.94, 0.16), TextXAlignment = Enum.TextXAlignment.Left })
	end
	return rows
end

local STATE_TEXT = { Prep = "PICKING FIGHTERS", Countdown = "IN THE CORNERS", Live = "FIGHTING", RoundOver = "BETWEEN ROUNDS", SuddenDeath = "FIGHTING" }

function DistrictService:RenderLive(rows)
	local fights = self.Services.DuelService:UndergroundMatches()
	local now = Workspace:GetServerTimeNow()
	for i, row in rows do
		local fight = fights[i]
		if fight then
			local clock = ""
			if fight.State == "Live" and fight.EndsAt then
				local left = math.max(0, fight.EndsAt - now)
				clock = ("  %d:%02d"):format(left // 60, left % 60)
			end
			row.Text = ("%s%s  %d — %d  %s   ·   ROUND %d/%d  %s%s"):format(fight.Ranked and "★ " or "", string.upper(fight.Names[1]), fight.Score[1], fight.Score[2],
				string.upper(fight.Names[2]), math.max(fight.Round, 1), fight.BestOf, STATE_TEXT[fight.State] or "", clock)
			row.TextColor3 = fight.Ranked and GOLD or RGB(236, 232, 240)
		else
			row.Text = i == 1 and "No fights right now. Step up to a terminal and start one." or ""
			row.TextColor3 = RGB(170, 160, 180)
		end
	end
end

-- The leaderboard: two columns (wins, knockouts).
function DistrictService:BuildBoard(panel: BasePart)
	local gui = panel:FindFirstChild("Screen")
	if not gui then
		return nil
	end
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 14), UDim.new(0, 14), UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = gui
	label(gui, { Text = "THE UNDERGROUND  ·  TOP FIGHTERS", Size = UDim2.fromScale(1, 0.1), Font = Enum.Font.GothamBlack, TextColor3 = GOLD })
	local board = { Scope = label(gui, { Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(1, 0.05), Font = Enum.Font.Gotham, TextColor3 = RGB(170, 160, 180) }) }
	for column, id in { RANKED, "UGKOs" } do
		local x = (column - 1) * 0.52
		label(gui, { Text = id == RANKED and ("RANKED  ·  " .. UGRank.Season.Name) or "MOST KNOCKOUTS", Position = UDim2.fromScale(x, 0.17), Size = UDim2.fromScale(0.48, 0.07), TextColor3 = id == RANKED and GOLD or BLUE })
		local rows = {}
		for i = 1, 10 do
			local y = 0.26 + (i - 1) * 0.073
			rows[i] = {
				Name = label(gui, { Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(0.27, 0.06), TextXAlignment = Enum.TextXAlignment.Left }),
				Value = label(gui, { Position = UDim2.fromScale(x + 0.27, y), Size = UDim2.fromScale(0.21, 0.06), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = RGB(255, 210, 120) }),
			}
		end
		board[id] = rows
	end
	return board
end

local MEDALS = { RGB(255, 205, 80), RGB(210, 215, 230), RGB(215, 140, 80) }

function DistrictService:RenderBoard(board)
	local leaderboards = self.Services.LeaderboardService
	local scope = "loading..."
	for _, id in { RANKED, "UGKOs" } do
		local top = leaderboards:Top(id)
		scope = top.Scope
		for i, row in board[id] do
			local entry = top.Rows[i]
			row.Name.Text = entry and ("%s%d. %s"):format(id == RANKED and i == 1 and "♛ " or "", i, entry.Name) or (i == 1 and "Nobody yet: be the first" or "")
			row.Name.TextColor3 = MEDALS[i] or RGB(236, 232, 240)
			-- (the season's #1 glows)
			row.Name.TextStrokeColor3 = id == RANKED and i == 1 and entry and GOLD or Color3.new(0, 0, 0)
			row.Name.TextStrokeTransparency = id == RANKED and i == 1 and entry and 0.3 or 1
			row.Value.Text = entry and entry.Text or ""
		end
		if id == RANKED and board.Plaque then
			local champion = top.Rows[1]
			board.Plaque.Text = champion and ("%s  ·  #1  %s"):format(UGRank.Season.Name, string.upper(champion.Name)) or "CHAMPIONSHIP TROPHIES"
		end
	end
	board.Scope.Text = scope == "GLOBAL" and "ALL SERVERS" or scope == "THIS SERVER" and "THIS SERVER (global boards unavailable)" or scope
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function DistrictService:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name ~= "UGRankedQueue" and prompt.Name ~= "UGPractice" then
			return
		end
		if not self.Services.AntiExploitService:Allow(player, "DuelRequest") then
			return
		end
		if prompt.Name == "UGRankedQueue" then
			self.Services.UndergroundService:Join(player, "Ranked")
		else
			-- through the door: the Training Arena's striking range, in the Forge
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not self.Services.DuelService:IsInMatch(player) then
				local at = Config.ArenaPoint(Config.World.Arena.RangeFacing) + Vector3.new(0, 4, 0)
				local look = Config.ArenaPoint(Config.World.Arena.Dummies[2])
				character:PivotTo(CFrame.lookAt(at, Vector3.new(look.X, at.Y, look.Z)))
				self.Services.DuelService.DuelEvent:FireClient(player, "RequestResult", { Text = "THE PRACTICE ARENA: the Training Arena's dummies, guard dummy and the Pit." })
			end
		end
	end)

	task.spawn(function()
		local root = Workspace:WaitForChild("NightmareForgeHub", 60)
		local district = root and root:WaitForChild("FightingDistrict", 60)
		if not district then
			warn("[DistrictService] the Fighting District wasn't built")
			return
		end
		-- the dummies in the training corner (facing into the lobby)
		local inward = -WorldDefinitions.District.Center -- (unused fallback)
		local frame = CFrame.lookAt(WorldDefinitions.District.Center, Vector3.new(WorldDefinitions.HubCenter.X, WorldDefinitions.District.Center.Y, WorldDefinitions.HubCenter.Z))
		for _, spot in CollectionService:GetTagged("UGDummySpot") do
			if spot:IsDescendantOf(district) then
				local ground = Vector3.new(spot.Position.X, WorldDefinitions.District.Center.Y + 0.05, spot.Position.Z)
				inward = ground - frame.RightVector * 10
				self.Services.TrainingService:SpawnEnemy({ Kind = "TrainingDummy", Ground = ground, Facing = inward })
			end
		end
		-- the screens
		local lives = {}
		local board
		local plaque
		for _, part in district:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "UGLiveBoard" then
				table.insert(lives, self:BuildLive(part))
			elseif part:IsA("BasePart") and part.Name == "UGLeaderboard" then
				board = self:BuildBoard(part)
			elseif part:IsA("BasePart") and part.Name == "ChampionPlaque" then
				local gui = part:FindFirstChildOfClass("SurfaceGui")
				plaque = gui and gui:FindFirstChildOfClass("TextLabel")
			end
		end
		if board then
			board.Plaque = plaque
		end
		local tick = 0
		while true do
			for _, rows in lives do
				self:RenderLive(rows)
			end
			if board and tick % 10 == 0 then
				self:RenderBoard(board)
			end
			tick += 1
			task.wait(1)
		end
	end)
end

return DistrictService
