--[[
	UGRankedService  (ModuleScript)
	Location: ServerScriptService/Server/Services/UGRankedService

	NIGHTMARE UNDERGROUND's RANKED LEAGUE (UGRankDefinitions): what a ranked fight does to the
	two fighters' records, and the season's rewards.

	  ApplyResult   (DuelService:EndMatch, ranked Underground matches only) the rating change,
	                placements, streaks, promotion / demotion, the match history; the same two
	                fighters again soon count for less (UGRank.RepeatScale)
	  Seasons       a fighter whose record is from an older season has it closed the next time
	                they're here: the season's title (their division; TOP 20 / CHAMPION from the
	                season's global ranking when the store can be read), then a soft reset
	  Matchmaking   CanPair: the ranked queue only pairs fighters within a rating window that
	                widens as they wait; placement fighters never meet Mythic and above
	  Cosmetics     EquipTitle (DuelRequest "UGTitle"): the title shown over your Handler's head
	                and on your fight plate; TOP 20 / CHAMPION titles give your Nightmare an aura
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UGRank = require(Shared:WaitForChild("UGRankDefinitions"))

local UGRankedService = {}

local recentPairs = {} -- ["userA:userB"] = { os.time of each ranked fight between them }

local AURAS = {
	Gold = { Color = Color3.fromRGB(255, 205, 70), Light = Color3.fromRGB(255, 210, 120) },
	Silver = { Color = Color3.fromRGB(225, 232, 245), Light = Color3.fromRGB(210, 220, 255) },
}

function UGRankedService:Init(services)
	self.Services = services
end

-- The player's league record, its season brought up to date (nil while the profile loads).
function UGRankedService:Record(player: Player)
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile then
		return nil
	end
	local record = profile.UGRanked
	if record.Season ~= UGRank.Season.Id then
		self:CloseSeason(player, record)
	end
	return record
end

function UGRankedService:Rating(player: Player): number
	local record = self:Record(player)
	return record and record.Rating or UGRank.StartRating
end

------------------------------------------------------------------------------------------
-- Seasons
------------------------------------------------------------------------------------------
-- Where `userId` finished in season `seasonId` (1-based), or nil (not in the top 20, or the
-- store can't be read: Studio without API access).
local function finishingPlace(seasonId: number, userId: number): number?
	local ok, place = pcall(function()
		local store = DataStoreService:GetOrderedDataStore(Config.Leaderboards.StorePrefix .. "UGRating_S" .. seasonId)
		local page = store:GetSortedAsync(false, 20):GetCurrentPage()
		for index, entry in page do
			if tonumber(entry.key) == userId then
				return index
			end
		end
		return nil
	end)
	return ok and place or nil
end

function UGRankedService:CloseSeason(player: Player, record)
	local old = record.Season
	if record.Games > 0 then
		local division = UGRank.ById[record.Division] or UGRank.DivisionFor(record.Rating)
		local place = finishingPlace(old, player.UserId)
		table.insert(record.Past, 1, { Season = old, Rating = record.Rating, Peak = record.Peak, Division = division.Id, Games = record.Games, Wins = record.Wins, Place = place })
		while #record.Past > 10 do
			table.remove(record.Past)
		end
		-- the season's titles: your division's, and TOP 20 / CHAMPION
		record.Titles[("S%d_%s"):format(old, division.Id)] = true
		if place and place <= 20 then
			record.Titles[("S%d_Top20"):format(old)] = true
		end
		if place == 1 then
			record.Titles[("S%d_Champion"):format(old)] = true
		end
		-- the soft reset: halfway back toward the start, a few placement fights again
		record.Rating = math.floor(UGRank.StartRating + (record.Rating - UGRank.StartRating) * UGRank.Season.SoftReset + 0.5)
		record.Placements = UGRank.ReturnPlacements
		record.PlacementsTotal = UGRank.ReturnPlacements
	end
	record.Season = UGRank.Season.Id
	record.Division = UGRank.DivisionFor(record.Rating).Id
	record.Peak = record.Rating
	record.Games, record.Wins, record.Losses, record.Draws = 0, 0, 0, 0
	record.Streak = 0
end

------------------------------------------------------------------------------------------
-- Matchmaking
------------------------------------------------------------------------------------------
-- Can these two be paired by the ranked queue, after waiting this long?
function UGRankedService:CanPair(a: Player, b: Player, waitedA: number, waitedB: number): boolean
	local ra, rb = self:Record(a), self:Record(b)
	if not ra or not rb then
		return false
	end
	local window = math.min(UGRank.SearchRange(waitedA), UGRank.SearchRange(waitedB))
	if math.abs(ra.Rating - rb.Rating) > window then
		return false
	end
	-- a fighter still placing never meets the very top
	local protect = UGRank.Search.ProtectFrom
	if (ra.Placements > 0 and rb.Rating >= protect) or (rb.Placements > 0 and ra.Rating >= protect) then
		return false
	end
	return true
end

------------------------------------------------------------------------------------------
-- A ranked fight's result
------------------------------------------------------------------------------------------
local function pairKey(a: Player, b: Player): string
	local x, y = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	return x .. ":" .. y
end

-- winnerSide: 1 / 2 / nil (a draw). Returns { [player] = summary } for the results screens.
function UGRankedService:ApplyResult(match, winnerSide: number?, reason: string)
	local a, b = match.Teams[1][1], match.Teams[2][1]
	if not a or not b then
		return {}
	end
	-- (a fighter who has left the game has no record to change, but their rating going in
	-- still counts for the one who stayed)
	local ra, rb = a.Parent and self:Record(a), b.Parent and self:Record(b)
	if not ra and not rb then
		return {}
	end
	local start = match.UGStartRatings or {}
	-- how many times these two have fought ranked lately (this one included)
	local key = pairKey(a, b)
	local now = os.time()
	local times = recentPairs[key] or {}
	for i = #times, 1, -1 do
		if now - times[i] > UGRank.RepeatWindow then
			table.remove(times, i)
		end
	end
	table.insert(times, now)
	recentPairs[key] = times
	local repeatIndex = #times

	local before = {
		[a] = start[a.UserId] or (ra and ra.Rating) or UGRank.StartRating,
		[b] = start[b.UserId] or (rb and rb.Rating) or UGRank.StartRating,
	}
	local summaries = {}
	for _, player in { a, b } do
		local record = player == a and ra or rb
		if not record then
			continue
		end
		local opponent = player == a and b or a
		local side = match.Side[player]
		local score = winnerSide == nil and 0.5 or (winnerSide == side and 1 or 0)
		local placing = record.Placements > 0
		local delta, scale = UGRank.Delta(before[player], before[opponent], score, placing, record.Streak, repeatIndex)
		local oldRating, oldDivision = record.Rating, record.Division
		record.Rating = math.max(UGRank.MinRating, record.Rating + delta)
		record.Games += 1
		if score == 1 then
			record.Wins += 1
			record.Streak += 1
			record.BestStreak = math.max(record.BestStreak, record.Streak)
		elseif score == 0 then
			record.Losses += 1
			record.Streak = 0
		else
			record.Draws += 1
		end
		if placing then
			record.Placements -= 1
		end
		record.Peak = math.max(record.Peak, record.Rating)
		local division = UGRank.NextDivision(oldDivision, record.Rating)
		record.Division = division.Id
		local result = score == 1 and "Win" or score == 0 and "Loss" or "Draw"
		table.insert(record.History, 1, {
			Opponent = opponent.DisplayName, Result = result, Delta = record.Rating - oldRating, Rating = record.Rating,
			Method = reason, At = now,
		})
		while #record.History > UGRank.HistorySize do
			table.remove(record.History)
		end
		local oldIndex = UGRank.ById[oldDivision] and UGRank.ById[oldDivision].Index or 1
		summaries[player] = {
			Old = oldRating, New = record.Rating, Delta = record.Rating - oldRating,
			Division = division.Id, Promoted = division.Index > oldIndex and not placing or nil, Demoted = division.Index < oldIndex or nil,
			Placement = placing and ((record.PlacementsTotal or UGRank.Placements) - record.Placements) or nil, PlacementsTotal = placing and (record.PlacementsTotal or UGRank.Placements) or nil,
			PlacementsDone = placing and record.Placements == 0 or nil,
			Streak = record.Streak, Damped = scale < 1 and scale or nil,
		}
	end
	return summaries
end

------------------------------------------------------------------------------------------
-- Cosmetics: titles and auras
------------------------------------------------------------------------------------------
function UGRankedService:EquipTitle(player: Player, titleId)
	local record = self:Record(player)
	if not record then
		return { Ok = false, Error = "Your profile is still loading." }
	end
	if titleId ~= nil and (type(titleId) ~= "string" or not record.Titles[titleId] or not UGRank.TitleFor(titleId)) then
		return { Ok = false, Error = "You haven't earned that title." }
	end
	record.Title = titleId
	self:ApplyCosmetics(player)
	self.Services.NightmareBuildService:PushState(player)
	return { Ok = true }
end

-- The equipped title over the Handler's head, and the aura on the Nightmare.
function UGRankedService:ApplyCosmetics(player: Player)
	local record = self:Record(player)
	local title = record and record.Title and UGRank.TitleFor(record.Title)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		local tag = head:FindFirstChild("UGTitleTag")
		if title then
			if not tag then
				tag = Instance.new("BillboardGui")
				tag.Name = "UGTitleTag"
				tag.Size = UDim2.fromOffset(200, 22)
				tag.StudsOffset = Vector3.new(0, 2.6, 0)
				tag.MaxDistance = 80
				tag.LightInfluence = 0
				local label = Instance.new("TextLabel")
				label.Name = "Text"
				label.BackgroundTransparency = 1
				label.Size = UDim2.fromScale(1, 1)
				label.Font = Enum.Font.GothamBlack
				label.TextScaled = true
				label.TextStrokeTransparency = 0.2
				label.Parent = tag
				tag.Parent = head
			end
			local label = tag:FindFirstChild("Text")
			if label then
				label.Text = "★ " .. title.Text .. " ★"
				label.TextColor3 = title.Color
			end
		elseif tag then
			tag:Destroy()
		end
	end
	local nightmare = self.Services.NightmareSpawnService:GetNightmare(player)
	local root = nightmare and nightmare:FindFirstChild("HumanoidRootPart")
	if root then
		local aura = title and title.Aura and AURAS[title.Aura]
		local existing = root:FindFirstChild("UGAura")
		if existing and (not aura or existing:GetAttribute("Kind") ~= title.Aura) then
			existing:Destroy()
			existing = nil
		end
		if aura and not existing then
			local attachment = Instance.new("Attachment")
			attachment.Name = "UGAura"
			attachment:SetAttribute("Kind", title.Aura)
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(aura.Color)
			emitter.LightEmission = 1
			emitter.Size = NumberSequence.new(0.6, 0)
			emitter.Transparency = NumberSequence.new(0.2, 1)
			emitter.Lifetime = NumberRange.new(0.8, 1.4)
			emitter.Rate = 18
			emitter.Speed = NumberRange.new(1.5, 3)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Parent = attachment
			local light = Instance.new("PointLight")
			light.Color = aura.Light
			light.Brightness = 1.2
			light.Range = 10
			light.Parent = attachment
			attachment.Parent = root
		end
	end
	-- (shown on the fight plates too)
	if nightmare then
		nightmare:SetAttribute("UGTitle", title and title.Text or nil)
	end
end

-- STUDIO ONLY (DevBridge): put a fighter's league record somewhere to test from.
--   "Rating", n      placements done, rating n (and its division)
--   "EndSeason", p   close the current season as if it had ended, finishing in place p (nil:
--                    outside the top 20), then reopen it: the titles and the soft reset
function UGRankedService:Dev(player: Player, action: string, value)
	if not game:GetService("RunService"):IsStudio() then
		return nil
	end
	local record = self:Record(player)
	if not record then
		return nil
	end
	if action == "Rating" and type(value) == "number" then
		record.Rating = value
		record.Placements = 0
		record.Division = UGRank.DivisionFor(value).Id
		record.Peak = math.max(record.Peak, value)
		record.Games = math.max(record.Games, 1)
	elseif action == "EndSeason" then
		local season = record.Season
		record.Games = math.max(record.Games, 1)
		local division = UGRank.ById[record.Division] or UGRank.DivisionFor(record.Rating)
		record.Season = season - 1 -- (so the record looks a season old)
		local placeBefore = value
		self:CloseSeason(player, record)
		-- (Studio has no season store to read the place from: give what the place would)
		if type(placeBefore) == "number" then
			if placeBefore <= 20 then
				record.Titles[("S%d_Top20"):format(season - 1)] = true
			end
			if placeBefore == 1 then
				record.Titles[("S%d_Champion"):format(season - 1)] = true
			end
		end
		record.Titles[("S%d_%s"):format(season - 1, division.Id)] = true
	end
	self.Services.NightmareBuildService:PushState(player)
	return { Rating = record.Rating, Division = record.Division, Placements = record.Placements, Season = record.Season }
end

function UGRankedService:Start()
	-- titles and auras follow the character and the Nightmare as they respawn
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			self:ApplyCosmetics(player)
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(self.ApplyCosmetics, self, player)
				if not ok then
					warn("[UGRankedService] cosmetics:", err)
				end
			end
		end
	end)
end

return UGRankedService
