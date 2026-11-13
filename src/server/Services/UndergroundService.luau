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

local Kit = require(script.Parent:WaitForChild("World"):WaitForChild("Kit"))

local UndergroundService = {}

local UG = Config.Underground
local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad = math.rad
local M = Enum.Material
local P, cyl = Kit.P, Kit.Cyl
local glow = { NoCollide = true, Shadow = false }

local CORNER_COLORS = { RGB(255, 60, 70), RGB(70, 140, 255) } -- side 1 red, side 2 blue

local arenas = {} -- [slot] = arena
local slotInUse = {}
local queues: { [string]: { Player } } = { Casual = {}, Ranked = {} }

------------------------------------------------------------------------------------------
-- The arena: a raised ring in a dark concrete hall, crowds on the bleachers, the
-- Handlers' booths at the red and blue corners
------------------------------------------------------------------------------------------
local function buildArena(slot: number)
	local c = UG.ArenaOrigin + V3((slot - 1) * UG.ArenaSpacing, 0, 0)
	local root = Workspace:FindFirstChild("UndergroundArenas") or Kit.Folder("UndergroundArenas", Workspace)
	local a = Kit.Model("Underground" .. slot, root)
	local half = UG.RingHalf
	local apron = 3 -- the ring floor's height above the hall floor
	local floorY = c.Y + apron -- where the fighters stand

	local CONCRETE, DARK, STEEL = RGB(44, 42, 48), RGB(22, 20, 26), RGB(70, 68, 76)
	local ROPE = RGB(150, 24, 34)

	-- the hall: floor, four walls and a roof (closed: the fight is the only light)
	local hall = 72
	P(a, CF(c + V3(0, -0.5, 0)), V3(hall * 2, 1, hall * 2), CONCRETE, M.Concrete, { Name = "HallFloor" })
	for _, side in { { V3(hall, 20, 0), V3(2, 42, hall * 2) }, { V3(-hall, 20, 0), V3(2, 42, hall * 2) }, { V3(0, 20, hall), V3(hall * 2, 42, 2) }, { V3(0, 20, -hall), V3(hall * 2, 42, 2) } } do
		P(a, CF(c + side[1]), side[2], DARK, M.Concrete, { Name = "HallWall" })
	end
	P(a, CF(c + V3(0, 41, 0)), V3(hall * 2, 2, hall * 2), DARK, M.Concrete, { Name = "HallRoof" })

	-- the ring: a raised apron, the canvas, a red circle in the middle
	P(a, CF(c + V3(0, apron / 2, 0)), V3(half * 2 + 8, apron, half * 2 + 8), RGB(30, 28, 34), M.Metal, { Name = "Apron" })
	P(a, CF(c + V3(0, apron + 0.1, 0)), V3(half * 2 + 6, 0.2, half * 2 + 6), RGB(64, 62, 70), M.Fabric, { Name = "Canvas" })
	Kit.Ring(a, CF(c + V3(0, apron + 0.22, 0)), 8, 0.05, 0.6, 40, ROPE, M.Neon, glow)
	Kit.Ring(a, CF(c + V3(0, apron + 0.22, 0)), half - 1.5, 0.05, 0.3, 64, RGB(90, 30, 36), M.SmoothPlastic, glow)

	-- corner posts (red, blue and two neutral), three ropes between them
	local corners = { V3(-half, 0, half), V3(half, 0, -half), V3(half, 0, half), V3(-half, 0, -half) }
	local postColors = { CORNER_COLORS[1], CORNER_COLORS[2], RGB(210, 210, 220), RGB(210, 210, 220) }
	for i, corner in corners do
		local base = c + corner + V3(0, apron, 0)
		cyl(a, base, base + V3(0, 7, 0), 1.2, postColors[i], M.Metal)
		cyl(a, base + V3(0, 6.6, 0), base + V3(0, 7.4, 0), 1.6, postColors[i], M.Neon, glow)
	end
	local ring = { corners[1], corners[3], corners[2], corners[4] } -- (round the square)
	for i = 1, 4 do
		local from, to = ring[i], ring[i % 4 + 1]
		for _, height in { 2.2, 4, 5.8 } do
			cyl(a, c + from + V3(0, apron + height, 0), c + to + V3(0, apron + height, 0), 0.35, ROPE, M.SmoothPlastic, glow)
		end
		-- the ropes hold: an invisible wall the fighters can't get through or over
		local mid = c + (from + to) / 2 + V3(0, apron + 8, 0)
		local along = (to - from)
		local size = math.abs(along.X) > 0.1 and V3(math.abs(along.X) + 2, 16, 1) or V3(1, 16, math.abs(along.Z) + 2)
		P(a, CF(mid), size, Color3.new(), M.SmoothPlastic, { Transparency = 1, Shadow = false, Name = "RingWall" })
	end

	-- the lighting rig over the ring: a square truss, four spotlights straight down
	local rigY = floorY + 26
	for i = 1, 4 do
		local from, to = ring[i], ring[i % 4 + 1]
		Kit.Rod(a, c + from + V3(0, rigY - c.Y, 0), c + to + V3(0, rigY - c.Y, 0), 1, 1, STEEL, M.DiamondPlate)
	end
	for _, corner in corners do
		local lamp = P(a, CF(c + corner * 0.55 + V3(0, rigY - c.Y - 1, 0)), V3(3, 1.4, 3), RGB(240, 230, 210), M.Neon, glow)
		Kit.Light(lamp, RGB(255, 240, 220), 4, 46, { Kind = "SpotLight", Face = Enum.NormalId.Bottom, Angle = 70 })
	end
	local fill = P(a, CF(c + V3(0, rigY - c.Y + 2, 0)), V3(1, 1, 1), Color3.new(), M.SmoothPlastic, { Transparency = 1, NoCollide = true, Shadow = false })
	Kit.Light(fill, RGB(255, 120, 130), 1.2, 70)

	-- the crowd: stepped bleachers on all four sides, a packed house of silhouettes
	local rng = Random.new(slot * 977)
	for side = 0, 3 do
		local frame = CF(c) * ANG(0, rad(side * 90), 0)
		for row = 0, 3 do
			local z = half + 14 + row * 5
			local y = 1 + row * 2.4
			P(a, frame * CF(0, y / 2, z), V3(half * 2 + 30, y, 5), RGB(34, 32, 38), M.Concrete, { Name = "Bleacher" })
			for x = -half - 12, half + 12, 4.2 do
				if rng:NextNumber() < 0.82 then
					local tone = RGB(rng:NextInteger(30, 80), rng:NextInteger(26, 60), rng:NextInteger(30, 70))
					local spot = frame * CF(x + rng:NextNumber(-0.8, 0.8), y + 1.6, z)
					P(a, spot, V3(1.8, 2.6, 1.2), tone, M.SmoothPlastic, { Name = "Fan", Shadow = false, NoCollide = true })
					Kit.Ball(a, (spot * CF(0, 1.9, 0)).Position, 1.3, RGB(rng:NextInteger(60, 120), rng:NextInteger(45, 90), rng:NextInteger(40, 80)), M.SmoothPlastic, { Shadow = false, NoCollide = true })
				end
			end
		end
	end

	-- the Handlers' corner booths, outside the red and blue corners
	local booths = {}
	for side = 1, 2 do
		local corner = corners[side]
		local out = V3(math.sign(corner.X), 0, math.sign(corner.Z))
		local spot = c + corner + out * 7 + V3(0, 0, 0)
		P(a, CF(spot + V3(0, apron / 2, 0)), V3(7, apron, 7), RGB(30, 28, 34), M.Metal, { Name = "Booth" })
		P(a, CF(spot + V3(0, apron + 0.1, 0)), V3(6.4, 0.2, 6.4), CORNER_COLORS[side], M.Neon, glow)
		for _, edge in { V3(3.3, 0, 0), V3(-3.3, 0, 0), V3(0, 0, 3.3), V3(0, 0, -3.3) } do
			local size = edge.X ~= 0 and V3(0.3, 3, 7) or V3(7, 3, 0.3)
			P(a, CF(spot + edge + V3(0, apron + 1.5, 0)), size, STEEL, M.Metal, { Name = "BoothRail" })
		end
		local stand = spot + V3(0, apron + 3.2, 0)
		booths[side] = CFrame.lookAt(stand, V3(c.X, stand.Y, c.Z))
	end

	-- the name over the hall's far wall
	Kit.Sign(a, CF(c + V3(0, 30, -hall + 1.2)), V3(70, 9, 0.6), "NIGHTMARE UNDERGROUND", RGB(255, 70, 80), { Color = RGB(14, 12, 18) })
	Kit.Sign(a, CF(c + V3(0, 30, hall - 1.2)) * ANG(0, rad(180), 0), V3(70, 9, 0.6), "NIGHTMARE UNDERGROUND", RGB(255, 70, 80), { Color = RGB(14, 12, 18) })

	-- the fighters' corners (facing the middle)
	local starts = {}
	for side = 1, 2 do
		local corner = corners[side]
		local spot = c + V3(math.sign(corner.X) * UG.CornerInset, apron, math.sign(corner.Z) * UG.CornerInset)
		starts[side] = CFrame.lookAt(spot, V3(c.X, spot.Y, c.Z))
	end

	return { Model = a, Center = V3(c.X, floorY, c.Z), Starts = starts, Booths = booths }
end

function UndergroundService:ReserveArena()
	for slot = 1, UG.MaxArenas do
		if not slotInUse[slot] then
			slotInUse[slot] = true
			arenas[slot] = arenas[slot] or buildArena(slot)
			return slot, arenas[slot]
		end
	end
	return nil, nil
end

function UndergroundService:ReleaseArena(slot: number)
	slotInUse[slot] = nil
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
	record.Fights = (record.Fights or 0) + 1
	if match.UGRanked then
		record.RankedFights = (record.RankedFights or 0) + 1
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
				act(player, "Gym_Rest", 3.2)
			end
		end
	end
	if stoppage then
		-- the winner celebrates where it stands while the camera stays on the body going down
		if winnerSide then
			act(match.Teams[winnerSide][1], "UG_Victory", 2.6)
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
	local kind, index = queuedIn(player)
	if kind then
		table.remove(queues[kind], index)
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
			local a = table.remove(list, 1)
			local b = table.remove(list, 1)
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
