--[[
	UGTournamentService  (ModuleScript)
	Location: ServerScriptService/Server/Services/UGTournamentService

	NIGHTMARE UNDERGROUND — THE UNDERGROUND TOURNAMENT: a knockout bracket for the players in
	this server (Config.Underground.Tournament).
	  * sign-ups at the district's TOURNAMENT terminal (DuelRequest "UGTourney": Join / Leave /
	    Start / State). The first to sign up is the host: START once there are enough of them;
	    it starts by itself when the bracket is full.
	  * seeded by Underground rating (the best seeds get the byes when the field isn't a power
	    of two), every fight a normal Underground match (DuelService:StartMatch with
	    opts.Tournament): same rules, same arenas, never ranked
	  * a round's fights all start together; when the last one ends the next round is called
	    (NextRoundDelay). A draw goes to the judge's points for the fight, then the higher
	    rating. Leaving the server or not turning up loses.
	  * the winner: TournamentWins on their career (UGCosmetics unlocks THE TROPHY LIFT), the
	    prize, the district's champion line (DistrictService), and the whole server is told
	Everyone signed up (and anyone with the panel open) gets DuelEvent "UGTourney" (the state)
	whenever it changes.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local UGTournamentService = {}

local T = Config.Underground.Tournament

-- the one tournament this server runs at a time (nil: nobody has signed up)
local tourney = nil
local watchers: { [Player]: boolean } = {} -- the panel is open
local lastChampion: string? = nil

function UGTournamentService:Init(services)
	self.Services = services
end

local function minimum(): number
	return RunService:IsStudio() and T.StudioMinimum or T.Minimum
end

local function names(list)
	local out = {}
	for i, p in list do
		out[i] = p and p.DisplayName or "BYE"
	end
	return out
end

-- What the clients draw: who's in, and the bracket so far.
function UGTournamentService:Snapshot(viewer: Player?)
	if not tourney then
		return { Phase = "None", Champion = lastChampion, Minimum = minimum(), Size = T.Size }
	end
	local rounds = {}
	for r, round in tourney.Rounds do
		local fights = {}
		for i, fight in round do
			fights[i] = {
				A = fight.A and fight.A.DisplayName or "BYE",
				B = fight.B and fight.B.DisplayName or "BYE",
				Winner = fight.Winner and fight.Winner.DisplayName or nil,
				Status = fight.Status,
			}
		end
		rounds[r] = fights
	end
	return {
		Phase = tourney.Phase, Host = tourney.Host and tourney.Host.DisplayName, Entrants = names(tourney.Entrants), Size = T.Size,
		Minimum = minimum(), Round = tourney.Round, Rounds = rounds, Champion = tourney.Champion and tourney.Champion.DisplayName or lastChampion,
		Joined = viewer ~= nil and table.find(tourney.Entrants, viewer) ~= nil, IsHost = viewer ~= nil and tourney.Host == viewer,
		NextAt = tourney.NextAt,
	}
end

function UGTournamentService:Publish()
	local duel = self.Services.DuelService
	local sent = {}
	local function send(player: Player)
		if player.Parent and not sent[player] then
			sent[player] = true
			duel.DuelEvent:FireClient(player, "UGTourney", self:Snapshot(player))
		end
	end
	for player in watchers do
		send(player)
	end
	for _, player in tourney and tourney.Entrants or {} do
		send(player)
	end
end

local function tell(self, player: Player, text: string)
	if player.Parent then
		self.Services.DuelService.DuelEvent:FireClient(player, "RequestResult", { Text = text })
	end
end

local function announce(self, text: string)
	for _, player in Players:GetPlayers() do
		tell(self, player, text)
	end
end

------------------------------------------------------------------------------------------
-- Sign-ups
------------------------------------------------------------------------------------------
function UGTournamentService:Join(player: Player)
	if self.Services.DuelService:IsInMatch(player) then
		return { Ok = false, Error = "Finish your fight first." }
	end
	if tourney and tourney.Phase ~= "Signup" then
		return { Ok = false, Error = "This tournament has already started. Watch it from the WATCH LIVE terminal." }
	end
	if not tourney then
		tourney = { Phase = "Signup", Entrants = {}, Host = player, Rounds = {}, Round = 0, Id = os.clock() }
	end
	if table.find(tourney.Entrants, player) then
		return { Ok = true }
	end
	if #tourney.Entrants >= T.Size then
		return { Ok = false, Error = "The bracket is full." }
	end
	table.insert(tourney.Entrants, player)
	if #tourney.Entrants >= T.Size then
		self:Begin()
	else
		self:Publish()
	end
	return { Ok = true }
end

function UGTournamentService:Leave(player: Player)
	if not tourney then
		return { Ok = true }
	end
	local index = table.find(tourney.Entrants, player)
	if not index then
		return { Ok = true }
	end
	if tourney.Phase == "Signup" then
		table.remove(tourney.Entrants, index)
		if #tourney.Entrants == 0 then
			tourney = nil
		elseif tourney.Host == player then
			tourney.Host = tourney.Entrants[1]
		end
		self:Publish()
		return { Ok = true }
	end
	-- (mid-tournament: you're out; a fight you're waiting for goes to the other side)
	self:Withdraw(player)
	return { Ok = true }
end

function UGTournamentService:StartBracket(player: Player)
	if not tourney or tourney.Phase ~= "Signup" then
		return { Ok = false, Error = "There's nothing to start." }
	end
	if tourney.Host ~= player then
		return { Ok = false, Error = "Only the host (the first to sign up) can start it." }
	end
	if #tourney.Entrants < minimum() then
		return { Ok = false, Error = ("It needs at least %d fighters."):format(minimum()) }
	end
	self:Begin()
	return { Ok = true }
end

------------------------------------------------------------------------------------------
-- The bracket
------------------------------------------------------------------------------------------
local function rating(self, player: Player): number
	return self.Services.UGRankedService:Rating(player) or 1000
end

-- Standard seeding: 1 meets the lowest seed, and the top two can only meet in the final.
local function seedOrder(size: number)
	local order = { 1 }
	while #order < size do
		local n = #order * 2
		local nextOrder = {}
		for _, s in order do
			table.insert(nextOrder, s)
			table.insert(nextOrder, n + 1 - s)
		end
		order = nextOrder
	end
	return order
end

function UGTournamentService:Begin()
	local entrants = table.clone(tourney.Entrants)
	table.sort(entrants, function(a, b)
		return rating(self, a) > rating(self, b)
	end)
	local size = 2
	while size < #entrants do
		size *= 2
	end
	local order = seedOrder(size)
	local first = {}
	for i = 1, size, 2 do
		-- (a missing seed is a BYE: the best seeds get them)
		table.insert(first, { A = entrants[order[i]], B = entrants[order[i + 1]], Status = "Waiting" })
	end
	tourney.Phase = "Running"
	tourney.Rounds = { first }
	tourney.Round = 1
	tourney.Seeded = entrants
	announce(self, ("THE UNDERGROUND TOURNAMENT IS ON: %d fighters. Watch from the WATCH LIVE terminal."):format(#entrants))
	self:PlayRound()
end

-- Start every fight of the current round that can be started (byes go straight through).
function UGTournamentService:PlayRound()
	local round = tourney.Rounds[tourney.Round]
	local duel = self.Services.DuelService
	for slot, fight in round do
		if fight.Status == "Waiting" then
			local a, b = fight.A, fight.B
			local aHere = a and a.Parent and table.find(tourney.Entrants, a) ~= nil
			local bHere = b and b.Parent and table.find(tourney.Entrants, b) ~= nil
			if not aHere or not bHere then
				fight.Winner = (aHere and a) or (bHere and b) or nil
				fight.Status = "Bye"
			elseif duel:IsInMatch(a) or duel:IsInMatch(b) then
				-- (still finishing something else: tried again shortly)
				fight.Status = "Waiting"
			else
				local result = duel:StartMatch(a, b, T.BestOf, { Mode = "Underground", Tournament = { Id = tourney.Id, Round = tourney.Round, Slot = slot } })
				if result and result.Ok then
					fight.Status = "Fighting"
				end
			end
		end
	end
	self:Publish()
	self:CheckRound()
end

-- A tournament fight is over (DuelService:Cleanup).
function UGTournamentService:MatchOver(match)
	local info = match.Tournament
	if not info or not tourney or info.Id ~= tourney.Id then
		return
	end
	local fight = tourney.Rounds[info.Round] and tourney.Rounds[info.Round][info.Slot]
	if not fight or fight.Status == "Done" then
		return
	end
	local side = match.WinnerSide
	if not side then
		-- a draw: the judge's points for the fight, then the higher rating
		local points = match.UGMatch and match.UGMatch.Points or { 0, 0 }
		if points[1] ~= points[2] then
			side = points[1] > points[2] and 1 or 2
		else
			side = rating(self, match.Teams[1][1]) >= rating(self, match.Teams[2][1]) and 1 or 2
		end
	end
	fight.Winner = match.Teams[side][1]
	fight.Status = "Done"
	local loser = match.Teams[3 - side][1]
	if loser then
		tell(self, loser, "Out of the tournament. Watch the rest from the WATCH LIVE terminal.")
	end
	self:Publish()
	self:CheckRound()
end

function UGTournamentService:Withdraw(player: Player)
	if not tourney or tourney.Phase ~= "Running" then
		return
	end
	local index = table.find(tourney.Entrants, player)
	if index then
		table.remove(tourney.Entrants, index)
	end
	-- a fight they hadn't started yet goes to the other side (one in progress ends through the
	-- duel's own forfeit / leaving)
	for _, fight in tourney.Rounds[tourney.Round] or {} do
		if fight.Status == "Waiting" and (fight.A == player or fight.B == player) then
			fight.Winner = fight.A == player and fight.B or fight.A
			fight.Status = "Bye"
		end
	end
	self:Publish()
	self:CheckRound()
end

-- Is the round finished? Then the next one (or the champion).
function UGTournamentService:CheckRound()
	local round = tourney and tourney.Rounds[tourney.Round]
	if not round or tourney.Phase ~= "Running" then
		return
	end
	for _, fight in round do
		if fight.Status ~= "Done" and fight.Status ~= "Bye" then
			return
		end
	end
	local winners = {}
	for _, fight in round do
		table.insert(winners, fight.Winner or false)
	end
	if #winners == 1 then
		self:Crown(winners[1] or nil)
		return
	end
	local nextRound = {}
	for i = 1, #winners, 2 do
		table.insert(nextRound, { A = winners[i] or nil, B = winners[i + 1] or nil, Status = "Waiting" })
	end
	table.insert(tourney.Rounds, nextRound)
	tourney.Round += 1
	tourney.NextAt = workspace:GetServerTimeNow() + T.NextRoundDelay
	local id = tourney.Id
	local label = #nextRound == 1 and "THE FINAL" or ("ROUND %d"):format(tourney.Round)
	for _, player in tourney.Entrants do
		tell(self, player, ("Tournament: %s starts in %d seconds."):format(label, T.NextRoundDelay))
	end
	self:Publish()
	task.delay(T.NextRoundDelay, function()
		if tourney and tourney.Id == id and tourney.Phase == "Running" then
			tourney.NextAt = nil
			self:PlayRound()
		end
	end)
end

function UGTournamentService:Crown(champion: Player?)
	tourney.Phase = "Done"
	tourney.Champion = champion
	if champion and champion.Parent then
		lastChampion = champion.DisplayName
		local profile = self.Services.PlayerDataService:Get(champion)
		if profile then
			profile.Underground = profile.Underground or {}
			profile.Underground.TournamentWins = (profile.Underground.TournamentWins or 0) + 1
			profile.Coins = (profile.Coins or 0) + T.PrizeCoins
			self.Services.NightmareBuildService:PushState(champion)
		end
		announce(self, ("%s WINS THE UNDERGROUND TOURNAMENT!"):format(string.upper(champion.DisplayName)))
		tell(self, champion, ("Tournament champion: +%d coins, and THE TROPHY LIFT is yours in the Locker Room."):format(T.PrizeCoins))
	end
	self:Publish()
	-- (the bracket stays up a while, then sign-ups open again)
	local id = tourney.Id
	task.delay(T.ShowResultFor, function()
		if tourney and tourney.Id == id then
			tourney = nil
			self:Publish()
		end
	end)
end

function UGTournamentService:LastChampion(): string?
	return lastChampion
end

------------------------------------------------------------------------------------------
-- Requests (DuelRequest "UGTourney", action)
------------------------------------------------------------------------------------------
function UGTournamentService:Request(player: Player, action)
	if action == "Join" then
		return self:Join(player)
	elseif action == "Leave" then
		return self:Leave(player)
	elseif action == "Start" then
		return self:StartBracket(player)
	elseif action == "Watch" then
		watchers[player] = true
		return { Ok = true, State = self:Snapshot(player) }
	elseif action == "Unwatch" then
		watchers[player] = nil
		return { Ok = true }
	end
	return { Ok = false, Error = "Unknown request." }
end

function UGTournamentService:Start()
	Players.PlayerRemoving:Connect(function(player)
		watchers[player] = nil
		if tourney then
			if tourney.Phase == "Signup" then
				self:Leave(player)
			else
				self:Withdraw(player)
			end
		end
	end)
	-- (a fight that couldn't start yet: someone was still finishing another one, or every
	-- ring was taken) tried again every few seconds
	task.spawn(function()
		while true do
			task.wait(3)
			if tourney and tourney.Phase == "Running" and not tourney.NextAt then
				local pending = false
				for _, fight in tourney.Rounds[tourney.Round] or {} do
					if fight.Status == "Waiting" then
						pending = true
					end
				end
				if pending then
					self:PlayRound()
				end
			end
		end
	end)
end

return UGTournamentService
