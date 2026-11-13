--[[
	UGRankDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/UGRankDefinitions

	NIGHTMARE UNDERGROUND's RANKED LEAGUE (UGRankedService): its own rating and divisions,
	separate from the Colosseum's ranked duels (RankDefinitions). Shared so the server and
	every screen agree.

	  RATING     Elo from StartRating. The first Placements fights swing harder (PlacementK)
	             and show "PLACEMENT n/5" instead of a division. A winning streak adds a little
	             (StreakBonus). Fighting the SAME opponent again soon counts for less
	             (RepeatScale: nobody farms the ladder off a friend).
	  DIVISIONS  RUST, IRON, STEEL, CHROME, TITANIUM, MYTHIC, NIGHTMARE LEGEND by rating.
	             Promotion as soon as you reach the next one; demotion only once you're
	             DemoteBuffer under your division's floor (one bad night doesn't drop you).
	  SEASONS    Season.Id. When a new season starts, a fighter's next visit closes their old
	             season: its rewards are granted and the rating is pulled halfway back toward
	             StartRating (SoftReset), with ReturnPlacements placement fights.
	  REWARDS    cosmetic only: a season title for the division you finished in; TOP 20 and the
	             CHAMPION (#1) also get an aura on their Nightmare.

	profile.UGRanked = { Season, Rating, Division, Games, Wins, Losses, Draws, Placements,
	                     Streak, BestStreak, Peak, History = { recent fights }, Past = { seasons },
	                     Titles = { [titleId] = true }, Title = equipped title id }
]]

local UGRank = {}

local RGB = Color3.fromRGB

UGRank.StartRating = 1000
UGRank.K = 32
UGRank.PlacementK = 64
UGRank.Placements = 5
UGRank.ReturnPlacements = 3 -- after a season reset
UGRank.MinRating = 0
UGRank.DemoteBuffer = 25
UGRank.StreakBonus = { From = 3, Per = 2, Max = 6 } -- the 3rd win in a row on: +2 each, up to +6
UGRank.HistorySize = 12
-- the same two fighters again within RepeatWindow seconds: the 1st fight counts fully, then less
UGRank.RepeatWindow = 3600
UGRank.RepeatScale = { 1, 0.5, 0.25, 0 }

-- Ascending by Min. Badge: the glyph on its badge.
UGRank.Divisions = {
	{ Id = "Rust", Name = "RUST", Min = 0, Color = RGB(196, 110, 66), Badge = "◆" },
	{ Id = "Iron", Name = "IRON", Min = 1100, Color = RGB(150, 136, 128), Badge = "◆◆" },
	{ Id = "Steel", Name = "STEEL", Min = 1250, Color = RGB(176, 184, 196), Badge = "◆◆◆" },
	{ Id = "Chrome", Name = "CHROME", Min = 1400, Color = RGB(225, 232, 245), Badge = "✦" },
	{ Id = "Titanium", Name = "TITANIUM", Min = 1600, Color = RGB(130, 205, 255), Badge = "✦✦" },
	{ Id = "Mythic", Name = "MYTHIC", Min = 1800, Color = RGB(214, 110, 255), Badge = "✦✦✦" },
	{ Id = "Legend", Name = "NIGHTMARE LEGEND", Min = 2000, Color = RGB(255, 64, 76), Badge = "♛" },
}
UGRank.ById = {}
for index, division in UGRank.Divisions do
	division.Index = index
	UGRank.ById[division.Id] = division
end

-- MATCHMAKING: the rating gap allowed grows the longer both have waited; a fighter still in
-- placements never meets anyone at or above ProtectFrom (no new player is thrown to a champion).
UGRank.Search = { BaseRange = 150, RangePerSecond = 20, MaxRange = 600, ProtectFrom = 1800 }

UGRank.Season = {
	Id = 1,
	Name = "SEASON 1",
	EndsAt = 1801440000, -- 2027-02-01 00:00 UTC
	SoftReset = 0.5, -- the new rating keeps this share of the distance from StartRating
}

-- Titles (cosmetic). Season titles are made per season: "S<n>_<division>", "S<n>_Top20",
-- "S<n>_Champion". Aura: the glow on their Nightmare while it's equipped.
function UGRank.TitleFor(id: string)
	if type(id) ~= "string" then
		return nil
	end
	local season, kind = id:match("^S(%d+)_(%w+)$")
	if not season then
		return nil
	end
	if kind == "Champion" then
		return { Id = id, Text = ("S%s CHAMPION"):format(season), Color = RGB(255, 205, 70), Aura = "Gold", Rank = 100 }
	elseif kind == "Top20" then
		return { Id = id, Text = ("S%s TOP 20"):format(season), Color = RGB(225, 232, 245), Aura = "Silver", Rank = 90 }
	end
	local division = UGRank.ById[kind]
	return division and { Id = id, Text = ("S%s %s"):format(season, division.Name), Color = division.Color, Rank = division.Index } or nil
end

------------------------------------------------------------------------------------------
-- Rating maths
------------------------------------------------------------------------------------------
function UGRank.DivisionFor(rating: number)
	local found = UGRank.Divisions[1]
	for _, division in UGRank.Divisions do
		if rating >= division.Min then
			found = division
		end
	end
	return found
end

-- The division a fighter holds after a change of rating (promotion at once, demotion only
-- past the buffer).
function UGRank.NextDivision(currentId: string?, rating: number)
	local earned = UGRank.DivisionFor(rating)
	local current = currentId and UGRank.ById[currentId]
	if not current or earned.Index >= current.Index then
		return earned
	end
	if rating < current.Min - UGRank.DemoteBuffer then
		return earned
	end
	return current
end

-- 0..1 through the current division toward the next (1 at the top division).
function UGRank.Progress(rating: number, divisionId: string?)
	local division = (divisionId and UGRank.ById[divisionId]) or UGRank.DivisionFor(rating)
	local nextDivision = UGRank.Divisions[division.Index + 1]
	if not nextDivision then
		return 1, nil
	end
	return math.clamp((rating - division.Min) / (nextDivision.Min - division.Min), 0, 1), nextDivision
end

-- The change of rating for one fight. score: 1 win, 0.5 draw, 0 loss. placement: still
-- placing; streak: wins in a row BEFORE this fight; repeatIndex: 1 for the first fight against
-- this opponent inside RepeatWindow, 2 for the second...
function UGRank.Delta(rating: number, opponentRating: number, score: number, placement: boolean, streak: number, repeatIndex: number): (number, number)
	local expected = 1 / (1 + 10 ^ ((opponentRating - rating) / 400))
	local k = placement and UGRank.PlacementK or UGRank.K
	local delta = k * (score - expected)
	local bonus = 0
	if score == 1 and streak + 1 >= UGRank.StreakBonus.From then
		bonus = math.min(UGRank.StreakBonus.Max, (streak + 2 - UGRank.StreakBonus.From) * UGRank.StreakBonus.Per)
	end
	local scale = UGRank.RepeatScale[math.min(repeatIndex, #UGRank.RepeatScale)]
	return math.floor((delta + bonus) * scale + 0.5), scale
end

function UGRank.SearchRange(waited: number): number
	local s = UGRank.Search
	return math.min(s.MaxRange, s.BaseRange + s.RangePerSecond * waited)
end

-- A fresh record (and the defaults a loaded one is checked against).
function UGRank.NewRecord()
	return {
		Season = UGRank.Season.Id,
		Rating = UGRank.StartRating,
		Division = "Rust",
		Games = 0, Wins = 0, Losses = 0, Draws = 0,
		Placements = UGRank.Placements,
		PlacementsTotal = UGRank.Placements, -- (how many this round of placements started with)
		Streak = 0, BestStreak = 0,
		Peak = UGRank.StartRating,
		History = {},
		Past = {},
		Titles = {},
		Title = nil,
	}
end

return UGRank
