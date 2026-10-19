--[[
	RankDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/RankDefinitions

	RANKED PvP (Phase 6). Shared so the server computes and the client displays the
	same ranks. Rating is Elo: everyone starts at StartRating; the change depends on
	the opponent's rating (beating a stronger player is worth more). The first
	PlacementGames move the rating faster so new players find their level quickly.

	profile.Ranked = { Rating, Peak, Wins, Losses, Draws, Games }
]]

local RankDefinitions = {}

RankDefinitions.StartRating = 1000
RankDefinitions.K = 32 -- normal rating swing
RankDefinitions.PlacementK = 48 -- first games swing more
RankDefinitions.PlacementGames = 5
RankDefinitions.MinRating = 0
RankDefinitions.BestOf = 3 -- every ranked match

-- Ascending by MinRating.
RankDefinitions.Tiers = {
	{ Id = "Bronze", DisplayName = "BRONZE", MinRating = 0, Color = Color3.fromRGB(205, 127, 70) },
	{ Id = "Silver", DisplayName = "SILVER", MinRating = 900, Color = Color3.fromRGB(200, 205, 220) },
	{ Id = "Gold", DisplayName = "GOLD", MinRating = 1100, Color = Color3.fromRGB(255, 200, 60) },
	{ Id = "Platinum", DisplayName = "PLATINUM", MinRating = 1300, Color = Color3.fromRGB(110, 220, 210) },
	{ Id = "Diamond", DisplayName = "DIAMOND", MinRating = 1500, Color = Color3.fromRGB(110, 170, 255) },
	{ Id = "Nightmare", DisplayName = "NIGHTMARE", MinRating = 1700, Color = Color3.fromRGB(190, 90, 255) },
}

-- Matchmaking: allowed rating gap grows the longer you wait.
RankDefinitions.Search = {
	BaseRange = 100,
	RangePerSecond = 25,
	MaxRange = 800,
	AvoidRematchSeconds = 20, -- don't re-pair the same two players unless they've waited this long
}

function RankDefinitions.TierFor(rating: number)
	local tier = RankDefinitions.Tiers[1]
	for _, candidate in RankDefinitions.Tiers do
		if rating >= candidate.MinRating then
			tier = candidate
		end
	end
	return tier
end

function RankDefinitions.SearchRange(waitedSeconds: number): number
	local s = RankDefinitions.Search
	return math.min(s.MaxRange, s.BaseRange + s.RangePerSecond * waitedSeconds)
end

-- New rating after one match. score: 1 = win, 0.5 = draw, 0 = loss.
function RankDefinitions.NewRating(rating: number, opponentRating: number, score: number, gamesPlayed: number): number
	local expected = 1 / (1 + 10 ^ ((opponentRating - rating) / 400))
	local k = gamesPlayed < RankDefinitions.PlacementGames and RankDefinitions.PlacementK or RankDefinitions.K
	return math.max(RankDefinitions.MinRating, math.floor(rating + k * (score - expected) + 0.5))
end

-- The profile's ranked record, with defaults (never nil).
function RankDefinitions.Record(profile)
	local ranked = profile and profile.Ranked
	if type(ranked) ~= "table" then
		return { Rating = RankDefinitions.StartRating, Peak = RankDefinitions.StartRating, Wins = 0, Losses = 0, Draws = 0, Games = 0 }
	end
	return ranked
end

return RankDefinitions
