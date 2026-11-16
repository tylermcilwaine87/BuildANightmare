--[[
	UndergroundService  (ModuleScript)
	Location: ServerScriptService/Server/Services/UndergroundService

	NIGHTMARE UNDERGROUND: a 1v1 where each player IS their Nightmare (Config.Underground).

	DuelService runs the match (rounds, forfeits, leaving, rewards) with Mode "Underground";
	this service does what is different about it:
	  * its own arenas: a boxing ring in a hall, the two Handlers in their corner booths
	  * the Handler sits the fight out: parked in its booth, untouchable (CombatService only
	    lets the two Nightmares hurt each other), and the player's controls drive the
	    Nightmare for the whole round (PossessionService:Bind: no meter, no timer)
	  * the fighters are frozen in their corners until FIGHT, and again when the round ends
	  * every fighter gets the same health (a build changes how it fights, not how long)
	  * a round ends on a KNOCKOUT (the Nightmare goes down for good), a TKO (its third
	    knockdown of the round, or a knockdown it can't get up from: Config.Underground.TKO)
	    or, at the bell, on a DECISION: the judge's points for clean work (Config.Underground
	    .Score); too close to call = drawn
	  * the scorecard: what each side threw, landed, countered, parried, slipped and floored,
	    per round and for the match (Stat, RecordRound), shown between rounds and at the end
	  * a match is at most BestOf rounds: first to 2, else rounds won, else the match's points,
	    else a draw (Verdict)
	  * after it: REMATCH (both ask) or QUEUE AGAIN (After, AfterCleanup)
	  * the in-server queue: the UndergroundQueue prompt (the kiosk at the Colosseum) pairs
	    the first two players who use it

	Remote DuelEvent (server -> client): "UGQueue" { Searching, Waiting }, "UGCount" (a fighter
	is down: the count), "UGRound" (the round's card), "UGRematch" (the other fighter asked).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UGRank = require(Shared:WaitForChild("UGRankDefinitions"))
local UGCosmetics = require(Shared:WaitForChild("UGCosmetics"))
local WorldDefinitions = require(Shared:WaitForChild("WorldDefinitions"))

local Kit = require(script.Parent:WaitForChild("World"):WaitForChild("Kit"))
local Arenas = require(script.Parent:WaitForChild("World"):WaitForChild("UndergroundArenas"))

local UndergroundService = {}

local UG = Config.Underground
local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad = math.rad
local M = Enum.Material
local P, cyl = Kit.P, Kit.Cyl
local glow = { NoCollide = true, Shadow = false }

local CORNER_COLORS = { RGB(255, 60, 70), RGB(70, 140, 255) } -- side 1 red, side 2 blue

local arenas = {} -- ["Theme:copy"] = arena
local devNextArena: string? = nil
local slotInUse = {}
local queues: { [string]: { Player } } = { Casual = {}, Ranked = {} }
local joinedAt: { [Player]: number } = {} -- (how long each has been searching: the ranked window)

------------------------------------------------------------------------------------------
-- The arenas (World/UndergroundArenas): a random venue for each fight, every one with the
-- same ring. Each kind is built the first time a fight needs it; MaxArenas of each kind.
------------------------------------------------------------------------------------------
function UndergroundService:ReserveArena()
	-- a random kind that has a free copy
	local kinds = {}
	for index, def in UG.Arenas do
		for copy = 1, UG.MaxArenas do
			local key = def.Id .. ":" .. copy
			if not slotInUse[key] then
				table.insert(kinds, { Key = key, Def = def, Index = index, Copy = copy })
				break
			end
		end
	end
	if #kinds == 0 then
		return nil, nil
	end
	local pick = kinds[math.random(1, #kinds)]
	-- (Studio: DevNextArena chose the next one)
	if devNextArena then
		for _, kind in kinds do
			if kind.Def.Id == devNextArena then
				pick = kind
			end
		end
		devNextArena = nil
	end
	slotInUse[pick.Key] = true
	if not arenas[pick.Key] then
		local origin = UG.ArenaOrigin + V3((pick.Index - 1) * UG.ArenaThemeSpacing, 0, (pick.Copy - 1) * UG.ArenaSpacing)
		local ok, built = pcall(Arenas.Build, pick.Def.Id, origin, pick.Index * 100 + pick.Copy)
		if not ok then
			warn("[UndergroundService] couldn't build " .. pick.Key .. ": " .. tostring(built))
			slotInUse[pick.Key] = nil
			return nil, nil
		end
		built.Name, built.Subtitle = pick.Def.Name, pick.Def.Subtitle
		arenas[pick.Key] = built
	end
	return pick.Key, arenas[pick.Key]
end

-- STUDIO ONLY (DevBridge): the next fight is held in this arena (Config.Underground.Arenas Id).
function UndergroundService:DevNextArena(themeId)
	if game:GetService("RunService"):IsStudio() then
		devNextArena = themeId
	end
end

function UndergroundService:ReleaseArena(key)
	slotInUse[key] = nil
	if arenas[key] then
		arenas[key].Match = nil
	end
end

------------------------------------------------------------------------------------------
-- Fighters
------------------------------------------------------------------------------------------
local function fighterOf(self, player: Player): Model?
	return self.Services.NightmareSpawnService:GetNightmare(player)
end

local function handlerRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

-- The Handler to its booth (anchored there: it watches), the Nightmare to its corner.
function UndergroundService:Place(match, player: Player)
	local side = match.Side[player]
	local arena = match.Arena
	local root = handlerRoot(player)
	if root then
		root.Anchored = false
		player.Character:PivotTo(arena.Booths[side])
		root.Anchored = true
	end
	self.Services.NightmareSpawnService:TeleportNightmare(player, arena.Starts[side])
end

function UndergroundService:Unpark(player: Player)
	local root = handlerRoot(player)
	if root then
		root.Anchored = false
	end
end

-- A fresh body for the round: the match's health, marked as a fighter (knockdowns count).
function UndergroundService:PrepareFighter(match, player: Player)
	local model = fighterOf(self, player)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.MaxHealth = UG.FighterHealth
	humanoid.Health = UG.FighterHealth
	model:SetAttribute("UGFighter", true)
	-- (the two fighters collide with each other: Nightmares normally walk through one another)
	self.Services.WorldBuilder.SetCollisionGroup(model, self.Services.WorldBuilder.CollisionGroups.UGFighters)
	-- (fresh stamina, no guard; it reports knockdowns back here: UndergroundService:Knockdown)
	self.Services.UndergroundFightService:Register(model, player)
	-- (a ranked fight: the division and rating on the fight plates)
	local ranked = match.UGRanked and self.Services.UGRankedService:Record(player)
	if ranked then
		local division = UGRank.ById[ranked.Division] or UGRank.DivisionFor(ranked.Rating)
		model:SetAttribute("UGRankText", ranked.Placements > 0 and "PLACEMENTS" or ("%s %d"):format(division.Name, ranked.Rating))
	else
		model:SetAttribute("UGRankText", nil)
	end
end

------------------------------------------------------------------------------------------
-- The scorecard (Config.Underground Score)
------------------------------------------------------------------------------------------
local STAT_KEYS = { "Thrown", "Landed", "Power", "Counters", "Parries", "Slips", "Combos", "Knockdowns", "Damage" }

local function blankStats()
	local stats = {}
	for _, key in STAT_KEYS do
		stats[key] = 0
	end
	return stats
end

local function liveMatch(self, player: Player?)
	local match = player and self.Services.DuelService:GetMatch(player)
	if match and match.Mode == "Underground" and match.State == "Live" and match.UG then
		return match
	end
	return nil
end

-- Something `player` did this round (UndergroundFightService): only counted while it's live.
function UndergroundService:Stat(player: Player, key: string, amount: number?)
	local match = liveMatch(self, player)
	if match then
		local stats = match.UG.Stats[match.Side[player]]
		stats[key] = (stats[key] or 0) + (amount or 1)
	end
end

-- What a round's work is worth to the judge.
local function pointsOf(stats): number
	local S = UG.Score
	return stats.Damage + stats.Landed * S.Landed + stats.Counters * S.Counter + stats.Parries * S.Parry + stats.Slips * S.Slip
		+ stats.Combos * S.Combo + stats.Knockdowns * S.Knockdown
end

-- A fighter went down (UndergroundFightService:OnKnockdown). info = { Count (its knockdowns
-- this round), Duration, TKO = "ThreeKnockdowns" | "Count" | nil, Move }.
function UndergroundService:Knockdown(downed: Player, by: Player?, info)
	local match = liveMatch(self, downed)
	if not match then
		return
	end
	local duel = self.Services.DuelService
	local side = match.Side[downed]
	match.UG.Stats[3 - side].Knockdowns += 1
	match.UG.Downs[side] += 1
	if info.TKO then
		-- the fight is stopped
		match.UG.Finish = { Move = info.Move, Stop = info.TKO }
		duel:EndRound(match, 3 - side, "TKO")
		return
	end
	duel:Broadcast(match, "Banner", { Title = "KNOCKDOWN!", Subtitle = ("%s IS DOWN  ·  %s"):format(string.upper(downed.DisplayName), info.Move or "") })
	-- (the count, on both HUDs, until it's back on its feet)
	duel:Broadcast(match, "UGCount", {
		UserId = downed.UserId, Duration = info.Duration, Interval = UG.Knockdown.CountInterval,
		Count = info.Count, Left = UG.TKO.Knockdowns - info.Count,
	})
end

-- The blow that knocked a fighter out (UndergroundFightService:NoteFinish).
function UndergroundService:Finish(by: Player, move: string)
	local match = liveMatch(self, by)
	if match then
		match.UG.Finish = { Move = move }
	end
end

-- The round is over (DuelService:EndRound): work out the judge's card and keep it for the
-- match. Returns the card: { Round, Winner (side?), Method, Move, Points, Judge, Stats }.
function UndergroundService:RecordRound(match, winnerSide: number?, reason: string)
	local ug = match.UG or { Stats = { blankStats(), blankStats() }, Downs = { 0, 0 } }
	local points = { pointsOf(ug.Stats[1]), pointsOf(ug.Stats[2]) }
	local method = (reason == "NightmareDefeated" and "KO") or (reason == "TKO" and "TKO") or (reason == "Decision" and (winnerSide and "DEC" or "DRAW")) or reason
	local judge = { 10, 10 }
	if winnerSide then
		-- ten to the winner; nine to the loser, less a point for every time it was floored
		judge[3 - winnerSide] = math.max(7, 9 - ug.Downs[3 - winnerSide])
	end
	local card = {
		Round = match.Round, Winner = winnerSide, Method = method, Move = ug.Finish and ug.Finish.Move or nil, Stop = ug.Finish and ug.Finish.Stop or nil,
		Points = points, Judge = judge, Stats = ug.Stats,
	}
	local whole = match.UGMatch
	if not whole then
		whole = { Rounds = {}, Stats = { blankStats(), blankStats() }, Points = { 0, 0 } }
		match.UGMatch = whole
	end
	table.insert(whole.Rounds, card)
	for side = 1, 2 do
		whole.Points[side] += points[side]
		for _, key in STAT_KEYS do
			whole.Stats[side][key] += ug.Stats[side][key]
		end
	end
	return card
end

-- After a round: is the match over? Returns over, winning side (nil = a draw), why.
function UndergroundService:Verdict(match)
	local needed = math.ceil(match.BestOf / 2)
	for side = 1, 2 do
		if match.Score[side] >= needed then
			return true, side, "Score"
		end
	end
	if match.Round < match.BestOf then
		return false
	end
	-- every round fought and nobody has two: rounds won, then the judge's points for the match
	if match.Score[1] ~= match.Score[2] then
		return true, match.Score[1] > match.Score[2] and 1 or 2, "Score"
	end
	local points = match.UGMatch and match.UGMatch.Points or { 0, 0 }
	if math.abs(points[1] - points[2]) <= UG.DrawMargin then
		return true, nil, "Draw"
	end
	return true, points[1] > points[2] and 1 or 2, "Scorecards"
end

-- The fight is over (DuelService:EndMatch): add what `player` did to their career numbers
-- (profile.Underground: the Fighter Stats terminal, the district's leaderboards).
function UndergroundService:AddCareer(match, player: Player, record)
	local whole = match.UGMatch
	local side = match.Side[player]
	-- (every fight counts, even one forfeited before a round was fought)
	record.Fights = (record.Fights or 0) + 1
	if match.UGRanked then
		record.RankedFights = (record.RankedFights or 0) + 1
	end
	if not whole or not side then
		return
	end
	for _, key in STAT_KEYS do
		record[key] = (record[key] or 0) + math.floor((whole.Stats[side][key] or 0) + 0.5)
	end
	for _, card in whole.Rounds do
		if card.Winner == side and card.Method == "KO" then
			record.KOs = (record.KOs or 0) + 1
		elseif card.Winner == side and card.Method == "TKO" then
			record.TKOs = (record.TKOs or 0) + 1
		end
	end
end

-- What `player` sees on the results screen (DuelService:EndMatch "MatchEnd").
function UndergroundService:Results(match, player: Player, winnerSide: number?, reason: string)
	local side = match.Side[player]
	local other = 3 - side
	local whole = match.UGMatch or { Rounds = {}, Stats = { blankStats(), blankStats() }, Points = { 0, 0 } }
	local last = whole.Rounds[#whole.Rounds]
	local method = "DECISION"
	if reason == "Forfeit" or reason == "Left" then
		method = reason == "Forfeit" and "FORFEIT" or "OPPONENT LEFT"
	elseif not winnerSide then
		method = "DRAW"
	elseif last and last.Winner == winnerSide and (last.Method == "KO" or last.Method == "TKO") then
		method = last.Method == "KO" and "KNOCKOUT" or "TKO"
	elseif reason == "Scorecards" then
		method = "THE SCORECARDS"
	elseif winnerSide and match.Score[winnerSide] < math.ceil(match.BestOf / 2) then
		method = "ROUNDS WON" -- (every round fought: more of them won, not two)
	end
	local rounds = {}
	for _, card in whole.Rounds do
		table.insert(rounds, {
			Round = card.Round, Method = card.Method, Move = card.Move,
			Result = (card.Winner == nil and "Draw") or (card.Winner == side and "Win" or "Loss"),
			Mine = card.Judge[side], Theirs = card.Judge[other],
		})
	end
	local winner = winnerSide and match.Teams[winnerSide][1]
	local winnerBody = winner and fighterOf(self, winner)
	local profile = self.Services.PlayerDataService:Get(player)
	return {
		Method = method,
		Move = last and (last.Method == "KO" or last.Method == "TKO") and last.Move or nil,
		Stop = last and last.Stop or nil,
		FinalRound = last and last.Round or match.Round,
		WinnerName = winner and winner.DisplayName or nil,
		WinnerUserId = winner and winner.UserId or nil,
		WinnerNightmare = winnerBody and winnerBody:GetAttribute("NightmareName") or nil,
		Rounds = rounds,
		Mine = whole.Stats[side], Theirs = whole.Stats[other],
		MyPoints = math.floor(whole.Points[side] + 0.5), TheirPoints = math.floor(whole.Points[other] + 0.5),
		Record = profile and profile.Underground or nil,
		Ranked = match.UGRanked == true,
	}
end

local function setFrozen(self, match, frozen: boolean)
	for _, player in match.Players do
		local model = fighterOf(self, player)
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.WalkSpeed = frozen and 0 or (model:GetAttribute("MoveSpeed") or 16)
			humanoid.JumpPower = 0
		end
	end
end

-- Countdown: everyone in control of their Nightmare, frozen in their corner.
function UndergroundService:BeginCountdown(match)
	-- (the arena's screens follow this fight; the first round opens with the introductions)
	if match.Arena then
		match.Arena.Match = match
	end
	-- (this round's work: what each side did, and how often each was floored)
	match.UG = { Stats = { blankStats(), blankStats() }, Downs = { 0, 0 } }
	setFrozen(self, match, true)
	-- (the new bodies were just put in their corners: let that reach the clients before they
	-- take over the physics, or a client still holding the old spot drags it back)
	local token = match.Token
	task.delay(0.6, function()
		if match.Token ~= token or match.State ~= "Countdown" then
			return
		end
		for _, player in match.Players do
			if player.Parent and not match.Left[player] then
				self.Services.PossessionService:Bind(player)
			end
		end
		setFrozen(self, match, true)
	end)
end

function UndergroundService:BeginLive(match)
	setFrozen(self, match, false)
end

function UndergroundService:Freeze(match)
	setFrozen(self, match, true)
end

-- The bell: the winning side on the judge's points, nil when it's too close to call.
function UndergroundService:Decide(match): number?
	local ug = match.UG
	if not ug then
		return nil
	end
	local a, b = pointsOf(ug.Stats[1]), pointsOf(ug.Stats[2])
	if math.abs(a - b) <= UG.DrawMargin then
		return nil
	end
	return a > b and 1 or 2
end

-- The round has ended (DuelService:EndRound, already RoundOver): everyone stops, the card
-- goes up, the players let go of their Nightmares (after the knockout camera, on a stoppage)
-- and the fighters still standing go back to their corners to get their breath.
function UndergroundService:EndRound(match, winnerSide: number?, reason: string)
	local duel = self.Services.DuelService
	local ai = self.Services.NightmareAIService
	setFrozen(self, match, true)
	local card = self:RecordRound(match, winnerSide, reason)
	local stoppage = reason == "NightmareDefeated" or reason == "TKO"
	local token = match.Token
	-- (did this round settle the match? Verdict reads the score this round just changed)
	local decided, matchWinner = self:Verdict(match)
	local function victory(player: Player)
		return UGCosmetics.VictoryFor(self.Services.PlayerDataService:Get(player))
	end

	local function act(player: Player, action: string, duration: number)
		local model = fighterOf(self, player)
		local brain = model and ai:GetBrainByModel(model)
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if brain and humanoid and humanoid.Health > 0 and not model:GetAttribute("Ragdolled") then
			ai:PlayAction(brain, action, 0, duration)
		end
	end
	local function release()
		if match.Token ~= token then
			return
		end
		for _, player in match.Players do
			self.Services.PossessionService:End(player, "RoundOver")
		end
		if stoppage then
			return -- (the winner stays over the fighter it stopped)
		end
		for _, player in match.Players do
			local model = fighterOf(self, player)
			local humanoid = model and model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not model:GetAttribute("Ragdolled") and player.Parent and not match.Left[player] then
				self.Services.NightmareSpawnService:TeleportNightmare(player, match.Arena.Starts[match.Side[player]])
				-- (the fight's over on the cards: its winner celebrates; everyone else gets its breath)
				if decided and match.Side[player] == matchWinner then
					task.delay(0.3, function()
						act(player, victory(player).Clip, victory(player).Duration)
					end)
				else
					act(player, "Gym_Rest", 3.2)
				end
			end
		end
	end
	if stoppage then
		-- the winner celebrates where it stands while the camera stays on the body going down
		if winnerSide then
			-- (its own victory pose: the locker room, UGCosmetics)
			local winner = match.Teams[winnerSide][1]
			act(winner, victory(winner).Clip, victory(winner).Duration)
		end
		task.delay(UG.KOCamTime, release)
	else
		release()
	end

	-- the call
	local winnerName = winnerSide and string.upper(match.TeamNames[winnerSide]) or nil
	local title, subtitle
	if reason == "NightmareDefeated" then
		title = "KNOCKOUT!"
		subtitle = ("%s%s WINS ROUND %d"):format(card.Move and (card.Move .. " KNOCKOUT  ·  ") or "", winnerName or "", match.Round)
	elseif reason == "TKO" then
		title = "TKO!"
		subtitle = ("%s  ·  %s WINS ROUND %d"):format(card.Stop == "ThreeKnockdowns" and "THREE KNOCKDOWNS: THE FIGHT IS STOPPED" or "IT CAN'T BEAT THE COUNT", winnerName or "", match.Round)
	elseif reason == "Decision" then
		title = winnerSide and "DECISION" or "ROUND DRAWN"
		subtitle = winnerSide and ("%s TAKES ROUND %d  ·  %d — %d"):format(winnerName, match.Round, card.Judge[winnerSide], card.Judge[3 - winnerSide])
			or "Too close to call  ·  10 — 10"
	else
		title = winnerSide and (winnerName .. " WINS THE ROUND") or "ROUND DRAWN"
		subtitle = reason == "Left" and "The other fighter left." or reason == "Forfeit" and "Opponent forfeited." or ""
	end
	duel:Broadcast(match, "Banner", { Title = title, Subtitle = subtitle })
	-- the scorecard, each player's own side first (deferred: the blow that ended the round is
	-- still being dealt, and it belongs on the card)
	task.defer(function()
		local points = { pointsOf(card.Stats[1]), pointsOf(card.Stats[2]) }
		for _, player in match.Players do
			if player.Parent then
				local side = match.Side[player]
				duel.DuelEvent:FireClient(player, "UGRound", {
					Round = card.Round, Method = card.Method, Move = card.Move, Stoppage = stoppage,
					Result = (winnerSide == nil and "Draw") or (winnerSide == side and "Win" or "Loss"),
					WinnerUserId = winnerSide and match.Teams[winnerSide][1].UserId or nil,
					LoserUserId = winnerSide and match.Teams[3 - winnerSide][1].UserId or nil,
					Mine = card.Stats[side], Theirs = card.Stats[3 - side],
					MyJudge = card.Judge[side], TheirJudge = card.Judge[3 - side],
					MyPoints = math.floor(points[side] + 0.5), TheirPoints = math.floor(points[3 - side] + 0.5),
					CamTime = stoppage and UG.KOCamTime or nil,
					ShowFor = UG.BetweenRoundsTime,
				})
			end
		end
	end)
end

------------------------------------------------------------------------------------------
-- After the match: REMATCH (both have to ask) or QUEUE AGAIN (DuelRequest "UGAfter")
------------------------------------------------------------------------------------------
function UndergroundService:After(player: Player, choice)
	local match = self.Services.DuelService:GetMatch(player)
	if not match or match.Mode ~= "Underground" or match.State ~= "Ended" or (choice ~= "Rematch" and choice ~= "Queue" and choice ~= "None") then
		return { Ok = false, Error = "The fight isn't over." }
	end
	if match.Tournament and choice == "Rematch" then
		return { Ok = false, Error = "It's a tournament: the bracket decides your next fight." }
	end
	match.UGAfter = match.UGAfter or {}
	match.UGAfter[player] = choice ~= "None" and choice or nil
	if choice == "Rematch" then
		local other = match.Teams[3 - match.Side[player]][1]
		if other and other.Parent then
			self.Services.DuelService.DuelEvent:FireClient(other, "UGRematch", { From = player.DisplayName, Both = match.UGAfter[other] == "Rematch" })
		end
	end
	return { Ok = true, Both = choice == "Rematch" and match.UGAfter[match.Teams[3 - match.Side[player]][1]] == "Rematch" }
end

-- Both players are back at the Forge (DuelService:Cleanup): start what they asked for.
function UndergroundService:AfterCleanup(match)
	local wants = match.UGAfter
	if not wants then
		return
	end
	local a, b = match.Players[1], match.Players[2]
	task.defer(function()
		if a and b and a.Parent and b.Parent and wants[a] == "Rematch" and wants[b] == "Rematch" then
			-- (always casual: a ranked fight only ever comes from the ranked queue, so two players
			-- can't farm the ladder by rematching each other)
			local result = self.Services.DuelService:StartMatch(a, b, UG.BestOf, { Mode = "Underground" })
			if result.Ok then
				return
			end
		end
		-- (a rematch nobody answered goes back in the queue too)
		for _, player in { a, b } do
			if player and player.Parent and wants[player] and not self:IsQueued(player) then
				self:Join(player, match.UGRanked and "Ranked" or "Casual")
			end
		end
	end)
end

------------------------------------------------------------------------------------------
-- The in-server queues: CASUAL (the Colosseum kiosk, the district's red terminals) and
-- RANKED (the district's gold terminals). Two separate pools: a ranked player is only ever
-- paired with another ranked player.
------------------------------------------------------------------------------------------
local QUEUE_TEXT = { Casual = "", Ranked = "RANKED  ·  " }

local function tell(self, player: Player, text: string)
	self.Services.DuelService.DuelEvent:FireClient(player, "RequestResult", { Text = text })
end

local function publishQueue(self)
	for kind, list in queues do
		for _, player in list do
			self.Services.DuelService.DuelEvent:FireClient(player, "UGQueue", { Searching = true, Waiting = #list, Kind = kind })
		end
	end
end

-- Which queue `player` is in, and where.
local function queuedIn(player: Player): (string?, number?)
	for kind, list in queues do
		local index = table.find(list, player)
		if index then
			return kind, index
		end
	end
	return nil, nil
end

function UndergroundService:Leave(player: Player, message: string?)
	-- (a fight of your own, or a queue: you stop watching someone else's)
	self:StopSpectating(player, true)
	local kind, index = queuedIn(player)
	if kind then
		table.remove(queues[kind], index)
		joinedAt[player] = nil
		if player.Parent then
			self.Services.DuelService.DuelEvent:FireClient(player, "UGQueue", { Searching = false })
			if message then
				tell(self, player, message)
			end
		end
	end
end

-- kind: "Casual" (default) or "Ranked". Using the same kind of terminal again cancels; the
-- other kind moves you over.
function UndergroundService:Join(player: Player, kind: string?)
	self:StopSpectating(player, true)
	kind = kind == "Ranked" and "Ranked" or "Casual"
	local duel = self.Services.DuelService
	local current = queuedIn(player)
	if current == kind then
		self:Leave(player, "You left the Underground queue.")
		return { Ok = true }
	elseif current then
		self:Leave(player, nil)
	end
	local busy, why = duel:IsBusy(player)
	if busy then
		tell(self, player, "You can't queue: you're " .. (why or "busy") .. ".")
		return { Ok = false }
	end
	if not duel:HasLegalBuild(player) then
		tell(self, player, "None of your saved Nightmares fit the PvP Power budget (100).")
		return { Ok = false }
	end
	table.insert(queues[kind], player)
	joinedAt[player] = os.clock()
	tell(self, player, ("NIGHTMARE UNDERGROUND: %ssearching for an opponent... (use the terminal again to cancel)"):format(QUEUE_TEXT[kind]))
	publishQueue(self)
	self:TryPair()
	return { Ok = true }
end

function UndergroundService:TryPair()
	for kind, list in queues do
		-- drop anyone who can't fight any more
		for i = #list, 1, -1 do
			local player = list[i]
			if not player.Parent or self.Services.DuelService:IsBusy(player) then
				table.remove(list, i)
			end
		end
		while #list >= 2 do
			local a, b
			if kind == "Ranked" then
				-- by rating: the first pair close enough for how long they've both waited
				-- (UGRankedService:CanPair); nobody fits yet: try again in a moment
				local now = os.clock()
				for i = 1, #list - 1 do
					for j = i + 1, #list do
						if not a and self.Services.UGRankedService:CanPair(list[i], list[j], now - (joinedAt[list[i]] or now), now - (joinedAt[list[j]] or now)) then
							a, b = list[i], list[j]
						end
					end
				end
				if not a then
					break
				end
				table.remove(list, table.find(list, a))
				table.remove(list, table.find(list, b))
			else
				a = table.remove(list, 1)
				b = table.remove(list, 1)
			end
			for _, player in { a, b } do
				self.Services.DuelService.DuelEvent:FireClient(player, "UGQueue", { Searching = false })
			end
			local result = self.Services.DuelService:StartMatch(a, b, UG.BestOf, { Mode = "Underground", UGRanked = kind == "Ranked" })
			if not result.Ok then
				for _, player in { a, b } do
					tell(self, player, result.Error or "Couldn't start the fight.")
				end
			end
		end
	end
	publishQueue(self)
end

------------------------------------------------------------------------------------------
-- The arena's screens and the introductions
------------------------------------------------------------------------------------------
local boardLabels = setmetatable({}, { __mode = "k" }) -- [panel] = its labels

local function boardText(panel: BasePart)
	local labels = boardLabels[panel]
	if labels then
		return labels
	end
	local gui = panel:FindFirstChild("Screen")
	if not gui then
		return nil
	end
	local function label(y: number, h: number, color: Color3, font)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.03, y)
		l.Size = UDim2.fromScale(0.94, h)
		l.TextScaled = true
		l.Font = font or Enum.Font.GothamBlack
		l.TextColor3 = color
		l.Parent = gui
		return l
	end
	local function bar(x: number, color: Color3)
		local back = Instance.new("Frame")
		back.BackgroundColor3 = RGB(30, 28, 34)
		back.BorderSizePixel = 0
		back.Position = UDim2.fromScale(x, 0.83)
		back.Size = UDim2.fromScale(0.44, 0.1)
		back.Parent = gui
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(1, 1)
		fill.Parent = back
		return fill
	end
	labels = {
		Arena = label(0.03, 0.14, RGB(255, 200, 80)),
		Names = label(0.2, 0.22, RGB(240, 236, 244)),
		Round = label(0.45, 0.16, RGB(200, 195, 210), Enum.Font.GothamBold),
		Score = label(0.62, 0.18, RGB(255, 210, 90)),
		Red = bar(0.03, CORNER_COLORS[1]),
		Blue = bar(0.53, CORNER_COLORS[2]),
	}
	boardLabels[panel] = labels
	return labels
end

local STATE_TEXT = { Prep = "PICKING FIGHTERS", Countdown = "IN THE CORNERS", Live = "", RoundOver = "BETWEEN ROUNDS", Ended = "FINAL" }

function UndergroundService:RenderBoards(arena)
	local match = arena.Match
	for _, panel in arena.Screens do
		local labels = boardText(panel)
		if labels then
			labels.Arena.Text = arena.Name or ""
			if match then
				labels.Names.Text = ("%s  vs  %s"):format(string.upper(match.TeamNames[1]), string.upper(match.TeamNames[2]))
				local clock = ""
				if match.State == "Live" and match.PhaseEndsAt then
					local left = math.max(0, match.PhaseEndsAt - Workspace:GetServerTimeNow())
					clock = ("%d:%02d"):format(left // 60, left % 60)
				end
				labels.Round.Text = ("%sROUND %d / %d  ·  %s%s"):format(match.UGRanked and "RANKED  ·  " or "", math.max(match.Round, 1), match.BestOf, STATE_TEXT[match.State] or "", clock)
				labels.Score.Text = ("%d  —  %d"):format(match.Score[1], match.Score[2])
				for side, fill in { labels.Red, labels.Blue } do
					local player = match.Teams[side][1]
					local body = player and fighterOf(self, player)
					local humanoid = body and body:FindFirstChildOfClass("Humanoid")
					fill.Size = UDim2.fromScale(humanoid and math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1) or 0, 1)
				end
			else
				labels.Names.Text = "NIGHTMARE UNDERGROUND"
				labels.Round.Text = arena.Subtitle or ""
				labels.Score.Text = ""
			end
		end
	end
end

-- THE ENTRANCES (round 1, DuelService "Intro"): the lights go down and the camera sweeps the
-- crowd; then each fighter in turn walks out from beyond its corner to ringside (the
-- arena's walk-out: UndergroundArenas.FindEntrance) and performs its entrance (UGCosmetics:
-- a keyframed clip on its own anatomy). The bodies are walked here; UndergroundController
-- films it from the same clock ("UGIntro" StartAt) and adds the cards, light and dust.
local function fighterCard(self, match, side: number)
	local player = match.Teams[side][1]
	local body = player and fighterOf(self, player)
	local profile = player and self.Services.PlayerDataService:Get(player)
	local ranked = match.UGRanked and player and self.Services.UGRankedService:Record(player)
	local division = ranked and (UGRank.ById[ranked.Division] or UGRank.DivisionFor(ranked.Rating))
	local ug = profile and profile.Underground
	local intro = UGCosmetics.IntroFor(profile)
	return {
		Name = player and player.DisplayName or "?",
		Nightmare = body and body:GetAttribute("NightmareName") or "Nightmare",
		Rank = ranked and (ranked.Placements > 0 and "PLACEMENTS" or ("%s %d"):format(division.Name, ranked.Rating)) or nil,
		Title = body and body:GetAttribute("UGTitle") or nil,
		Record = ug and ("%d-%d-%d"):format(ug.Wins or 0, ug.Losses or 0, ug.Draws or 0) or nil,
		Intro = intro.Id,
		IntroName = intro.Name,
		Model = body,
	}, intro
end

function UndergroundService:RunEntrance(match)
	local arena = match.Arena
	local beats = UG.Entrance
	local ai = self.Services.NightmareAIService
	local token = match.Token
	local startAt = Workspace:GetServerTimeNow() + 0.35
	local cards, intros = {}, {}
	for side = 1, 2 do
		cards[side], intros[side] = fighterCard(self, match, side)
		local walk = arena and arena.Entrances and arena.Entrances[side]
		if walk then
			cards[side].From, cards[side].To = walk.From, walk.To
		end
	end
	self.Services.DuelService:Broadcast(match, "UGIntro", {
		Arena = arena and arena.Name, Theme = arena and arena.Theme, Subtitle = arena and arena.Subtitle,
		Center = arena and arena.Center, StartAt = startAt, Sweep = beats.Sweep, Beat = beats.Beat, Walk = beats.Walk,
		Red = cards[1], Blue = cards[2], Ranked = match.UGRanked == true,
	})
	local function live(): boolean
		return match.Token == token and match.State == "Intro"
	end
	local function bodyOf(side: number)
		local player = match.Teams[side][1]
		local model = player and player.Parent and fighterOf(self, player)
		local brain = model and ai:GetBrainByModel(model)
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if not brain or not humanoid or humanoid.Health <= 0 then
			return nil
		end
		return player, model, brain, humanoid
	end
	-- out of sight at the far end of their walks while the camera takes in the crowd (this
	-- service walks them now: their brains stand aside)
	match.EntranceBrains = {}
	for side = 1, 2 do
		local player, _, brain = bodyOf(side)
		if player and cards[side].From then
			brain.scripted = true
			ai:Stop(brain)
			ai:StopFacing(brain)
			match.EntranceBrains[side] = brain
			self.Services.NightmareSpawnService:TeleportNightmare(player, cards[side].From)
		end
	end
	for side = 1, 2 do
		local beatAt = startAt + beats.Sweep + (side - 1) * beats.Beat
		task.delay(math.max(0, beatAt - Workspace:GetServerTimeNow()), function()
			local player, model, brain, humanoid = bodyOf(side)
			if not live() or not player or not cards[side].From then
				return
			end
			local from, to = cards[side].From.Position, cards[side].To.Position
			local distance = (to - from).Magnitude
			humanoid.JumpPower = 0
			if intros[side].Circle and distance > 6 then
				-- THE PREDATOR: it comes in on a curve, sizing the ring up
				local across = cards[side].To.RightVector * math.min(7, distance * 0.35)
				local bend = from:Lerp(to, 0.5) + across
				humanoid.WalkSpeed = ((bend - from).Magnitude + (to - bend).Magnitude) / beats.Walk
				humanoid:MoveTo(bend)
				task.delay(beats.Walk * 0.5, function()
					if live() and humanoid.Parent then
						humanoid:MoveTo(to)
					end
				end)
			else
				humanoid.WalkSpeed = math.max(distance / beats.Walk, 4)
				humanoid:MoveTo(to)
			end
			-- at ringside: square up to the ring and perform it
			task.delay(beats.Walk, function()
				if not live() or not model.Parent then
					return
				end
				humanoid.WalkSpeed = 0
				ai:Face(brain, (arena and arena.Center or to + cards[side].To.LookVector * 10))
				ai:PlayAction(brain, intros[side].Clip, 0, intros[side].Duration)
			end)
		end)
	end
end

-- The entrances are over (or skipped): the brains take their bodies back (the countdown puts
-- fresh ones in the corners).
function UndergroundService:EndEntrance(match)
	for _, brain in match.EntranceBrains or {} do
		brain.scripted = false
	end
	match.EntranceBrains = nil
end

-- SKIP INTRO: once every fighter has asked, straight to the corners.
function UndergroundService:SkipIntro(player: Player)
	local duel = self.Services.DuelService
	local match = duel:GetMatch(player)
	if not match or match.Mode ~= "Underground" or match.State ~= "Intro" then
		return { Ok = false }
	end
	match.IntroSkips = match.IntroSkips or {}
	match.IntroSkips[player] = true
	local count, needed = 0, 0
	for _, p in match.Players do
		if p.Parent and not match.Left[p] then
			needed += 1
			if match.IntroSkips[p] then
				count += 1
			end
		end
	end
	duel:Broadcast(match, "UGIntroSkip", { Count = count, Needed = needed })
	if count >= needed then
		duel:EndIntro(match)
	end
	return { Ok = true }
end

-- THE LOCKER ROOM: wear an entrance ("Intro") or a victory pose ("Victory") you've earned.
function UndergroundService:EquipCosmetic(player: Player, kind, id)
	local profile = self.Services.PlayerDataService:Get(player)
	local list = kind == "Intro" and UGCosmetics.IntroById or kind == "Victory" and UGCosmetics.VictoryById or nil
	if not profile or not list or type(id) ~= "string" or not list[id] then
		return { Ok = false, Error = "There's no such thing to wear." }
	end
	if not UGCosmetics.Unlocked(list[id], profile) then
		return { Ok = false, Error = "You haven't earned that yet." }
	end
	profile.Underground = profile.Underground or {}
	profile.Underground[kind] = id
	self.Services.NightmareBuildService:PushState(player)
	return { Ok = true }
end

-- STUDIO ONLY (DevBridge): wear any entrance / victory pose, earned or not (to film them all).
-- UGCosmetics.IntroFor still checks the unlock, so this also sets the career number it needs.
function UndergroundService:DevCosmetic(player: Player, kind: string, id: string)
	if not game:GetService("RunService"):IsStudio() then
		return false
	end
	local profile = self.Services.PlayerDataService:Get(player)
	local def = (kind == "Intro" and UGCosmetics.IntroById or UGCosmetics.VictoryById)[id]
	if not profile or not def then
		return false
	end
	profile.Underground = profile.Underground or {}
	local unlock = def.Unlock
	if unlock and unlock.Count then
		profile.Underground[unlock.Stat] = math.max(profile.Underground[unlock.Stat] or 0, unlock.Count)
	elseif unlock then
		profile.UGRanked.Titles = profile.UGRanked.Titles or {}
		profile.UGRanked.Titles["S1_Champion"] = true
	end
	profile.Underground[kind] = id
	self.Services.NightmareBuildService:PushState(player)
	return true
end

------------------------------------------------------------------------------------------
-- SPECTATING: the district's WATCH LIVE terminal lists every fight going on (DuelService
-- :UndergroundMatches); WATCH stands you in that arena's spectators' box (UndergroundArenas
-- .SpectatorBox) with your Nightmare beside you, and SpectatorController gives you the
-- cameras and the fight on a HUD. Real fights only: there is nothing to watch when nobody is
-- fighting. You go back to the district when you leave, or a little after the fight ends.
------------------------------------------------------------------------------------------
local spectating: { [Player]: any } = {} -- [player] = the match they're watching
local SPECTATE_AFTER = 6 -- seconds the result stays up before the watchers go home

local function spectatePacket(self, match)
	local arena = match.Arena
	local sides = {}
	for side = 1, 2 do
		local player = match.Teams[side][1]
		local body = player and player.Parent and fighterOf(self, player)
		sides[side] = { Name = match.TeamNames[side], Model = body, Nightmare = body and body:GetAttribute("NightmareName") or nil }
	end
	return {
		Active = true, MatchId = match.Id, Arena = arena and arena.Name, Theme = arena and arena.Theme, Center = arena and arena.Center,
		Red = sides[1], Blue = sides[2], Round = match.Round, BestOf = match.BestOf, Score = { match.Score[1], match.Score[2] },
		State = match.State, PhaseEndsAt = match.PhaseEndsAt, Ranked = match.UGRanked == true, Result = match.SpectateResult,
	}
end

function UndergroundService:Spectate(player: Player, matchId)
	local duel = self.Services.DuelService
	if duel:IsInMatch(player) then
		return { Ok = false, Error = "You're in a fight yourself." }
	end
	local match = duel:FindMatch(matchId)
	if not match or match.Mode ~= "Underground" or match.State == "Ended" or not match.Arena then
		return { Ok = false, Error = "That fight has finished." }
	end
	local spots = match.Arena.SpectatorSpots
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not spots or not root or not humanoid or humanoid.Health <= 0 then
		return { Ok = false, Error = "You can't watch right now." }
	end
	self:Leave(player, nil) -- (out of any queue; this also ends watching another fight)
	match.Spectators = match.Spectators or {}
	local count = 0
	for _ in match.Spectators do
		count += 1
	end
	local spot = spots[count % #spots + 1]
	root.Anchored = false
	character:PivotTo(spot + Vector3.new(0, 3, 0))
	root.Anchored = true
	-- your Nightmare stands with you and keeps still (it's no part of this fight)
	self.Services.NightmareSpawnService:TeleportNightmare(player, spot * CFrame.new(2.5, 0, 1.5))
	local model = fighterOf(self, player)
	local brain = model and self.Services.NightmareAIService:GetBrainByModel(model)
	if brain then
		brain.scripted = true
		self.Services.NightmareAIService:Stop(brain)
	end
	match.Spectators[player] = true
	spectating[player] = match
	player:SetAttribute("UGSpectating", match.Id)
	duel.DuelEvent:FireClient(player, "UGSpectate", spectatePacket(self, match))
	return { Ok = true }
end

-- quiet: they're off to something else (a queue, a fight of their own), no message
function UndergroundService:StopSpectating(player: Player, quiet: boolean?)
	local match = spectating[player]
	if not match then
		return
	end
	spectating[player] = nil
	if match.Spectators then
		match.Spectators[player] = nil
	end
	if not player.Parent then
		return
	end
	player:SetAttribute("UGSpectating", nil)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = false
		-- back where they started watching from: the district
		local center = WorldDefinitions.District.Center
		character:PivotTo(CFrame.new(center + Vector3.new(math.random(-6, 6), 4, math.random(-6, 6))))
	end
	local model = fighterOf(self, player)
	local brain = model and self.Services.NightmareAIService:GetBrainByModel(model)
	if brain then
		brain.scripted = false -- (it's far behind now: it catches up with its Handler)
	end
	self.Services.DuelService.DuelEvent:FireClient(player, "UGSpectate", { Active = false })
	if not quiet then
		tell(self, player, "Back in the Fighting District.")
	end
end

-- Every half second: the watchers get the fight; when it ends, the result, then home.
function UndergroundService:SpectateTick()
	for player, match in spectating do
		if not player.Parent then
			spectating[player] = nil
		elseif match.State == "Ended" or match.Closed then
			if not match.SpectateResult then
				local a, b = match.Score[1], match.Score[2]
				match.SpectateResult = a == b and "THE FIGHT IS A DRAW" or (string.upper(match.TeamNames[a > b and 1 or 2]) .. " WINS")
				match.SpectateEndAt = os.clock() + SPECTATE_AFTER
			end
			if os.clock() >= match.SpectateEndAt then
				self:StopSpectating(player)
			else
				self.Services.DuelService.DuelEvent:FireClient(player, "UGSpectate", spectatePacket(self, match))
			end
		else
			self.Services.DuelService.DuelEvent:FireClient(player, "UGSpectate", spectatePacket(self, match))
		end
	end
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function UndergroundService:Init(services)
	self.Services = services
end

function UndergroundService:Start()
	local duel = self.Services.DuelService

	-- the decision: what each side landed on the other's Nightmare during a live round
	-- (clean blows only: one that was blocked scores nothing)
	self.Services.CombatService:OnDamaged(function(target, attacker, amount, params)
		if not attacker or amount <= 0 or not target:GetAttribute("UGFighter") or params.WasGuarded then
			return
		end
		-- (strikes, abilities and Ultimates: not a passive's splinters or a burn ticking)
		local source = params.Source or ""
		if not params.Move and source:sub(1, 8) ~= "Ability:" and source:sub(1, 9) ~= "Ultimate:" then
			return
		end
		local owner = self.Services.CombatService:GetOwnerPlayer(attacker)
		local match = liveMatch(self, owner)
		-- (the blow that ends the round may already have ended it by now: it still counts,
		-- on the round's card and the match's)
		local late = false
		if not match and owner then
			local ended = duel:GetMatch(owner)
			match = ended and ended.Mode == "Underground" and ended.State == "RoundOver" and ended.UG and ended or nil
			late = match ~= nil
		end
		if match and duel:GetMatch(self.Services.CombatService:GetOwnerPlayer(target)) == match and attacker ~= target then
			local side = match.Side[owner]
			local power = params.Move and params.Move.Power and 1 or 0
			for _, stats in { match.UG.Stats[side], late and match.UGMatch and match.UGMatch.Stats[side] or nil } do
				stats.Damage += amount
				stats.Landed += 1
				stats.Power += power
			end
			if late and match.UGMatch then
				match.UGMatch.Points[side] += amount + UG.Score.Landed
			end
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name == "UndergroundQueue" then
			if not self.Services.AntiExploitService:Allow(player, "DuelRequest") then
				return
			end
			self:Join(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:Leave(player, nil)
		publishQueue(self)
	end)

	-- the arenas' screens: twice a second for every arena with a fight in it
	task.spawn(function()
		while true do
			task.wait(0.5)
			local okWatch, watchErr = pcall(self.SpectateTick, self) -- (and the spectators' view of their fight)
			if not okWatch then
				warn("[UndergroundService] spectators: " .. tostring(watchErr))
			end
			for key, arena in arenas do
				if slotInUse[key] then
					local ok, err = pcall(self.RenderBoards, self, arena)
					if not ok then
						warn("[UndergroundService] boards:", err)
					end
				end
			end
		end
	end)

	-- the ranked window widens as fighters wait: look again every couple of seconds
	task.spawn(function()
		while true do
			task.wait(2)
			if #queues.Ranked >= 2 then
				local ok, err = pcall(self.TryPair, self)
				if not ok then
					warn("[UndergroundService] ranked pairing:", err)
				end
			end
		end
	end)
end

-- (used by tests and other services)
function UndergroundService:IsQueued(player: Player): boolean
	for _, list in queues do
		if table.find(list, player) then
			return true
		end
	end
	return false
end

function UndergroundService:IsFighter(model: Model?): boolean
	return model ~= nil and CollectionService:HasTag(model, "Nightmare") and model:GetAttribute("UGFighter") == true
end

return UndergroundService
