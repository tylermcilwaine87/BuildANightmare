--[[
	LeaderboardService  (ModuleScript)
	Location: ServerScriptService/Server/Services/LeaderboardService

	LEADERBOARDS (Phase 6): global top-10 lists in OrderedDataStores, shown on the
	HALL OF NIGHTMARES board in the Forge (it cycles through the boards).

	  Highest Level · Most Boss Wins (Normal+) · Most PvP Wins ·
	  Fastest Scrap Titan · Fastest Mirror Warden (best win time, any real difficulty)

	Writes: every WriteInterval, only values that changed, only for SAVING profiles of
	real players (Studio test players / non-saving profiles never reach global boards).
	Reads: every ReadInterval. If the stores can't be reached (Studio without API access,
	Roblox outage) the board shows a "THIS SERVER" ranking of the players present instead.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BossDefinitions = require(Shared:WaitForChild("BossDefinitions"))
local RankDefinitions = require(Shared:WaitForChild("RankDefinitions"))
local UGRank = require(Shared:WaitForChild("UGRankDefinitions"))

local LeaderboardService = {}
local LB = Config.Leaderboards

local function bestTime(profile, bossId: string): number?
	local record = profile.Bosses and profile.Bosses[bossId]
	local best
	for _, mode in Config.Difficulties.Order do
		local time = BossDefinitions.ModeRecord(record, mode).BestTime
		if time and (not best or time < best) then
			best = time
		end
	end
	return best
end

local function formatTime(seconds: number): string
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

-- Value(profile) returns a whole number, or nil to stay off this board.
local BOARDS = {
	{
		Id = "Level",
		Title = "HIGHEST LEVEL",
		Value = function(profile)
			return profile.Level
		end,
		Format = function(value)
			return "Lv " .. value
		end,
	},
	{
		Id = "BossWins",
		Title = "MOST BOSS WINS",
		Value = function(profile)
			local total = 0
			for bossId in BossDefinitions.ById do
				total += BossDefinitions.RealWins(profile.Bosses and profile.Bosses[bossId])
			end
			return total > 0 and total or nil
		end,
		Format = function(value)
			return value .. (value == 1 and " win" or " wins")
		end,
	},
	{
		Id = "Rating",
		Title = "HIGHEST RANKED RATING",
		Value = function(profile)
			local ranked = profile.Ranked
			return ranked and (ranked.Games or 0) > 0 and ranked.Rating or nil
		end,
		Format = function(value)
			return ("%s %d"):format(RankDefinitions.TierFor(value).DisplayName, value)
		end,
	},
	{
		Id = "PvPWins",
		Title = "MOST PVP WINS",
		Value = function(profile)
			local wins = profile.PvP and profile.PvP.Wins or 0
			return wins > 0 and wins or nil
		end,
		Format = function(value)
			return value .. (value == 1 and " win" or " wins")
		end,
	},
	-- NIGHTMARE UNDERGROUND (also on the Fighting District's board). The ranked board is one
	-- per season (its own store), so a new season starts from an empty board.
	{
		Id = "UGRating_S" .. UGRank.Season.Id,
		Title = "UNDERGROUND RANKED · " .. UGRank.Season.Name,
		Value = function(profile)
			local ranked = profile.UGRanked
			return ranked and ranked.Season == UGRank.Season.Id and ranked.Games > 0 and ranked.Placements <= 0 and ranked.Rating or nil
		end,
		Format = function(value)
			return ("%s %d"):format(UGRank.DivisionFor(value).Name, value)
		end,
	},
	{
		Id = "UGWins",
		Title = "MOST UNDERGROUND WINS",
		Value = function(profile)
			local wins = profile.Underground and profile.Underground.Wins or 0
			return wins > 0 and wins or nil
		end,
		Format = function(value)
			return value .. (value == 1 and " win" or " wins")
		end,
	},
	{
		Id = "UGKOs",
		Title = "MOST UNDERGROUND KNOCKOUTS",
		Value = function(profile)
			local ug = profile.Underground
			local finishes = ug and ((ug.KOs or 0) + (ug.TKOs or 0)) or 0
			return finishes > 0 and finishes or nil
		end,
		Format = function(value)
			return value .. (value == 1 and " KO" or " KOs")
		end,
	},
	{
		Id = "Likes",
		Title = "MOST RESPECTED NIGHTMARES",
		Value = function(profile)
			local likes = profile.Showcase and profile.Showcase.Likes or 0
			return likes > 0 and likes or nil
		end,
		Format = function(value)
			return ("★ %d"):format(value)
		end,
	},
	{
		Id = "TitanTime",
		Title = "FASTEST SCRAP TITAN",
		Ascending = true,
		Value = function(profile)
			return bestTime(profile, "ScrapTitan")
		end,
		Format = formatTime,
	},
	{
		Id = "WardenTime",
		Title = "FASTEST MIRROR WARDEN",
		Ascending = true,
		Value = function(profile)
			return bestTime(profile, "MirrorWarden")
		end,
		Format = formatTime,
	},
	{
		Id = "StormTime",
		Title = "FASTEST STORM BEAST",
		Ascending = true,
		Value = function(profile)
			return bestTime(profile, "StormBeast")
		end,
		Format = formatTime,
	},
	{
		Id = "MawTime",
		Title = "FASTEST ABYSSAL MAW",
		Ascending = true,
		Value = function(profile)
			return bestTime(profile, "AbyssalMaw")
		end,
		Format = formatTime,
	},
}

local stores = {} -- [boardId] = OrderedDataStore (nil if unavailable)
local tops = {} -- [boardId] = { Scope = "GLOBAL" | "THIS SERVER", Rows = { { Name, Value } } }
local lastWritten = {} -- [userId] = { [boardId] = value }
local nameCache = {} -- [userId] = name
local board -- the in-world display

function LeaderboardService:Init(services)
	self.Services = services
	for _, def in BOARDS do
		local suffix = RunService:IsStudio() and (Config.Data.StudioStoreSuffix or "") or ""
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, LB.StorePrefix .. def.Id .. suffix)
		stores[def.Id] = ok and store or nil
	end
end

------------------------------------------------------------------------------------------
-- Writing
------------------------------------------------------------------------------------------
function LeaderboardService:WritePlayer(player: Player)
	if player.UserId <= 0 or not self.Services.PlayerDataService:IsPersistent(player) then
		return
	end
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile then
		return
	end
	local written = lastWritten[player.UserId] or {}
	lastWritten[player.UserId] = written
	for _, def in BOARDS do
		local value = def.Value(profile)
		local store = stores[def.Id]
		if store and value and value ~= written[def.Id] then
			local ok = pcall(store.SetAsync, store, tostring(player.UserId), math.floor(value))
			if ok then
				written[def.Id] = value
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- Reading
------------------------------------------------------------------------------------------
local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = ok and name or ("Player " .. userId)
	return nameCache[userId]
end

-- The latest top list for one board: { Scope, Rows = { { Name, Value, Text } } } (the Fighting
-- District's own board reads the Underground ones).
function LeaderboardService:Top(boardId: string)
	local data = tops[boardId]
	local def
	for _, d in BOARDS do
		if d.Id == boardId then
			def = d
		end
	end
	if not data or not def then
		return { Scope = "loading...", Rows = {} }
	end
	local rows = {}
	for _, row in data.Rows do
		table.insert(rows, { Name = row.Name, Value = row.Value, Text = def.Format(row.Value) })
	end
	return { Scope = data.Scope, Rows = rows }
end

-- Ranking of the players in this server (used when the global store can't be read).
function LeaderboardService:ServerRanking(def)
	local rows = {}
	for _, player in Players:GetPlayers() do
		local profile = self.Services.PlayerDataService:Get(player)
		local value = profile and def.Value(profile)
		if value then
			table.insert(rows, { Name = player.DisplayName, Value = value })
		end
	end
	table.sort(rows, function(a, b)
		if def.Ascending then
			return a.Value < b.Value
		end
		return a.Value > b.Value
	end)
	while #rows > LB.Size do
		table.remove(rows)
	end
	return rows
end

function LeaderboardService:Refresh()
	for _, def in BOARDS do
		local store = stores[def.Id]
		local rows
		if store then
			local ok, pages = pcall(store.GetSortedAsync, store, def.Ascending == true, LB.Size)
			if ok and pages then
				rows = {}
				for _, entry in pages:GetCurrentPage() do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(rows, { Name = nameFor(userId), Value = entry.value })
					end
				end
			end
		end
		if rows then
			tops[def.Id] = { Scope = "GLOBAL", Rows = rows }
		else
			tops[def.Id] = { Scope = "THIS SERVER", Rows = self:ServerRanking(def) }
		end
	end
end

------------------------------------------------------------------------------------------
-- The HALL OF NIGHTMARES board
------------------------------------------------------------------------------------------
local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(236, 232, 248)
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function LeaderboardService:BuildBoard()
	local parent = Workspace:FindFirstChild("NightmareForgeHub") or Workspace
	local base = LB.BoardPosition
	local facing = Config.World.HubSpawn
	local model = Instance.new("Model")
	model.Name = "HallOfNightmares"

	local look = CFrame.lookAt(base + Vector3.new(0, 9, 0), Vector3.new(facing.X, base.Y + 9, facing.Z))
	local panel = Instance.new("Part")
	panel.Name = "Board"
	panel.Anchored = true
	panel.Size = Vector3.new(14, 16, 0.6)
	panel.CFrame = look
	panel.Color = Color3.fromRGB(22, 18, 32)
	panel.Material = Enum.Material.Slate
	panel.Parent = model
	for _, side in { -1, 1 } do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Anchored = true
		post.Size = Vector3.new(1, 18, 1)
		post.CFrame = look * CFrame.new(7.5 * side, -0.5, 0)
		post.Color = Color3.fromRGB(150, 90, 255)
		post.Material = Enum.Material.Neon
		post.Parent = model
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 18), UDim.new(0, 18)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12)
	padding.Parent = gui

	board = { Rows = {} }
	label(gui, { Text = "HALL OF NIGHTMARES", Size = UDim2.fromScale(1, 0.08), Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(200, 160, 255) })
	board.Title = label(gui, { Position = UDim2.fromScale(0, 0.09), Size = UDim2.fromScale(1, 0.07), TextColor3 = Color3.fromRGB(255, 190, 60) })
	board.Scope = label(gui, { Position = UDim2.fromScale(0, 0.16), Size = UDim2.fromScale(1, 0.04), Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(165, 158, 188) })
	for i = 1, LB.Size do
		local y = 0.22 + (i - 1) * 0.07
		local rank = label(gui, { Position = UDim2.fromScale(0, y), Size = UDim2.fromScale(0.1, 0.055), TextXAlignment = Enum.TextXAlignment.Left })
		local name = label(gui, { Position = UDim2.fromScale(0.1, y), Size = UDim2.fromScale(0.6, 0.055), TextXAlignment = Enum.TextXAlignment.Left })
		local value = label(gui, { Position = UDim2.fromScale(0.7, y), Size = UDim2.fromScale(0.3, 0.055), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(120, 220, 255) })
		board.Rows[i] = { Rank = rank, Name = name, Value = value }
	end
	board.Footer = label(gui, { Position = UDim2.fromScale(0, 0.93), Size = UDim2.fromScale(1, 0.05), Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(165, 158, 188) })
	model.Parent = parent
end

local MEDALS = { Color3.fromRGB(255, 205, 80), Color3.fromRGB(210, 215, 230), Color3.fromRGB(215, 140, 80) }

function LeaderboardService:Render(index: number)
	local def = BOARDS[index]
	local data = tops[def.Id] or { Scope = "loading...", Rows = {} }
	board.Title.Text = def.Title
	board.Scope.Text = data.Scope == "GLOBAL" and "ALL SERVERS" or (data.Scope == "THIS SERVER" and "THIS SERVER (global boards unavailable)" or data.Scope)
	for i, row in board.Rows do
		local entry = data.Rows[i]
		row.Rank.Text = entry and ("#%d"):format(i) or ""
		row.Rank.TextColor3 = MEDALS[i] or Color3.fromRGB(236, 232, 248)
		row.Name.Text = entry and entry.Name or (i == 1 and "No entries yet: be the first!" or "")
		row.Value.Text = entry and def.Format(entry.Value) or ""
	end
	board.Footer.Text = ("Board %d / %d"):format(index, #BOARDS)
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function LeaderboardService:Start()
	self:BuildBoard()

	task.spawn(function()
		while true do
			self:Refresh()
			task.wait(LB.ReadInterval)
		end
	end)
	task.spawn(function()
		local index = 0
		while true do
			index = index % #BOARDS + 1
			self:Render(index)
			task.wait(LB.CycleSeconds)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(LB.WriteInterval)
			for _, player in Players:GetPlayers() do
				self:WritePlayer(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:WritePlayer(player) -- last chance (no-op if the profile is already released)
		lastWritten[player.UserId] = nil
	end)
end

return LeaderboardService
