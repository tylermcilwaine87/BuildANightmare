--[[
	RankedService  (ModuleScript)
	Location: ServerScriptService/Server/Services/RankedService

	RANKED PvP (Phase 6): a matchmaking queue + Elo rating (rules in Shared/RankDefinitions).

	  Join   -> needs a PvP-legal build and must not be busy (duel / boss fight / down)
	  Every second the matchmaker pairs the closest-rated players whose rating gap fits
	  BOTH players' search range (it widens the longer they wait). It avoids re-pairing
	  the same two players unless they've waited a while. Ranked = Best of 3.
	  Busy players (e.g. they started a boss fight) are dropped from the queue with a note.
	  ApplyResult (called once by DuelService:EndMatch) updates both ratings; forfeits
	  and leaving count as losses, so dodging never protects your rating.

	Same-server matchmaking. Cross-server queues would need MemoryStore + teleports.
	Client updates: DuelEvent "Queue" { Searching, Since, Range }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local RankDefinitions = require(Shared:WaitForChild("RankDefinitions"))

local RankedService = {}

local queue: { [Player]: { Since: number } } = {}
local lastOpponent: { [Player]: Player } = {}

function RankedService:Init(services)
	self.Services = services
	self.DuelEvent = Net.Get("DuelEvent")
end

local function rating(self, player: Player): number
	return RankDefinitions.Record(self.Services.PlayerDataService:Get(player)).Rating
end

function RankedService:SendQueue(player: Player)
	local entry = queue[player]
	if player.Parent then
		self.DuelEvent:FireClient(player, "Queue", {
			Searching = entry ~= nil,
			Waited = entry and (os.clock() - entry.Since) or 0,
			Range = entry and RankDefinitions.SearchRange(os.clock() - entry.Since) or 0,
		})
	end
end

function RankedService:IsQueued(player: Player): boolean
	return queue[player] ~= nil
end

function RankedService:Join(player: Player)
	if queue[player] then
		return { Ok = true }
	end
	local busy, why = self.Services.DuelService:IsBusy(player)
	if busy then
		return { Ok = false, Error = "You're " .. why .. "." }
	end
	if not self.Services.DuelService:HasLegalBuild(player) then
		return { Ok = false, Error = "None of your saved builds fit the PvP Power budget (100)." }
	end
	queue[player] = { Since = os.clock() }
	self:SendQueue(player)
	return { Ok = true }
end

-- note = message for the player (nil = silent, e.g. because a match is starting).
function RankedService:Leave(player: Player, note: string?)
	if not queue[player] then
		return
	end
	queue[player] = nil
	self:SendQueue(player)
	if note and player.Parent then
		self.DuelEvent:FireClient(player, "RequestResult", { Text = note })
	end
end

-- One matchmaking pass: oldest searchers first, each takes the closest-rated fit.
function RankedService:Match()
	local now = os.clock()
	local searching = {}
	for player, entry in queue do
		local busy, why = self.Services.DuelService:IsBusy(player)
		if busy then
			self:Leave(player, ("Left the ranked queue: you're %s."):format(why))
		else
			table.insert(searching, { Player = player, Since = entry.Since, Rating = rating(self, player) })
		end
	end
	table.sort(searching, function(a, b)
		return a.Since < b.Since
	end)

	local taken = {}
	for _, a in searching do
		if not taken[a.Player] then
			local best, bestGap = nil, math.huge
			for _, b in searching do
				if b ~= a and not taken[b.Player] then
					local gap = math.abs(a.Rating - b.Rating)
					local range = math.min(RankDefinitions.SearchRange(now - a.Since), RankDefinitions.SearchRange(now - b.Since))
					local rematch = lastOpponent[a.Player] == b.Player and math.min(now - a.Since, now - b.Since) < RankDefinitions.Search.AvoidRematchSeconds
					if gap <= range and not rematch and gap < bestGap then
						best, bestGap = b, gap
					end
				end
			end
			if best then
				taken[a.Player], taken[best.Player] = true, true
				queue[a.Player], queue[best.Player] = nil, nil
				lastOpponent[a.Player], lastOpponent[best.Player] = best.Player, a.Player
				local result = self.Services.DuelService:StartMatch(a.Player, best.Player, RankDefinitions.BestOf, { Ranked = true })
				if not result.Ok then
					-- No free arena: put them back (keeping their wait time) and try later.
					queue[a.Player] = { Since = a.Since }
					queue[best.Player] = { Since = best.Since }
				end
				self:SendQueue(a.Player)
				self:SendQueue(best.Player)
			end
		end
	end
end

-- Called ONCE per ranked match by DuelService:EndMatch. winner nil = draw.
-- Returns { [player] = { Old, New, Delta, Tier } }.
function RankedService:ApplyResult(match, winner: Player?)
	local a, b = match.Players[1], match.Players[2]
	local profiles = { [a] = self.Services.PlayerDataService:Get(a), [b] = self.Services.PlayerDataService:Get(b) }
	local before = { [a] = RankDefinitions.Record(profiles[a]), [b] = RankDefinitions.Record(profiles[b]) }
	local changes = {}
	for _, player in { a, b } do
		local profile = profiles[player]
		local opponent = player == a and b or a
		if profile then
			local record = before[player]
			local score = winner == nil and 0.5 or (winner == player and 1 or 0)
			local old = record.Rating
			local new = RankDefinitions.NewRating(old, before[opponent].Rating, score, record.Games)
			profile.Ranked = {
				Rating = new,
				Peak = math.max(record.Peak or old, new),
				Wins = (record.Wins or 0) + (score == 1 and 1 or 0),
				Losses = (record.Losses or 0) + (score == 0 and 1 or 0),
				Draws = (record.Draws or 0) + (score == 0.5 and 1 or 0),
				Games = (record.Games or 0) + 1,
			}
			changes[player] = { Old = old, New = new, Delta = new - old, Tier = RankDefinitions.TierFor(new).DisplayName }
		end
	end
	return changes
end

function RankedService:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			self:Match()
			-- Keep searchers' timers / ranges up to date (cheap: a few players at most).
			for player in queue do
				self:SendQueue(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		queue[player] = nil
		lastOpponent[player] = nil
		for other, opponent in lastOpponent do
			if opponent == player then
				lastOpponent[other] = nil -- don't keep a reference to a departed player
			end
		end
	end)
end

return RankedService
